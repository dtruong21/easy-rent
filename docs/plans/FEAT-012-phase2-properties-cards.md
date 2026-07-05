# Plan — FEAT-012 Phase 2 — Refonte page Properties en cards

> Designé par architect le 2026-06-22. À démarrer après merge Phase 1 (Leases cards).
> Réutilise les foundations Phase 0 (`EntityCard`, `StatusPill`, `CardGrid`, `ViewModeToggle`, `CardSkeleton`, `CardEmptyState`) et les patterns Phase 1.

## 1. Vue d'ensemble

**Objectif** : Migrer la page `/properties` vers une vue cards + table (toggle), cohérente avec Leases, et exposer un indicateur d'occupation Loué/Vacant.

**Non-objectifs** (reportés Phase 2.5+) :
- Photo / image du bien (exige bucket Storage + UI upload)
- Compteur de documents (les documents ne sont pas FK `property_id` aujourd'hui)
- Filtres avancés (multi-tri, recherche full-text, saved views)

**Cible** : 1 PR mergeable en ~1 jour (10-12 h).

**Branche** : `feature/feat-012-properties-cards` dérivée de `develop` après merge Phase 1.

## 2. Composition PropertyCard v2

```
EntityCard(
  onTap: () => context.push('/properties/${item.property.id}'),
  header: EntityCardHeader(
    title: item.property.name,             // "Appartement Paris 2e"
    subtitle: item.property.address,       // "12 rue de la Paix, 75002 Paris"
    trailing: StatusPill(tone, label),     // Loué / Vacant / Archivé
  ),
  body: Column([
    _PropertyCardRow(_iconForType(type), '${type.labelFr}${surfaceSuffix}'),
    _PropertyCardRow(Icons.person_outline, item.currentTenantName ?? 'Aucun locataire'),
    _PropertyCardRow(Icons.euro_outlined, item.currentRentLabel ?? '—'),
  ]),
  footer: Wrap([
    if (activeLeaseId != null) OutlinedButton('Voir le bail' → /leases/:id)
    else OutlinedButton('Créer un bail' → /leases/new?propertyId=...)
    OutlinedButton('Modifier' → /properties/:id/edit)
  ]),
)
```

## 3. Mapping statut → StatusPillTone

| Condition | Tone | Label | Icon |
|---|---|---|---|
| `activeLeaseId != null` | success | Loué | `home_filled` |
| `activeLeaseId == null` | warning | Vacant | `home_work_outlined` |
| `deletedAt != null` | neutral | Archivé | `archive_outlined` |

Helper : `lib/features/properties/presentation/widgets/property_status_mapper.dart` (pas de `now` injectable — pas de dépendance temporelle).

## 4. Source des données — `PropertyListItem`

Nouveau modèle composé via jointure PostgREST :

```dart
class PropertyListItem {
  final Property property;
  final String? activeLeaseId;       // null = vacant
  final String? currentTenantName;
  final String? currentRentLabel;    // formaté FR "1 200 € CC / mois"
}
```

Requête repo :
```dart
await Db.from('properties')
  .select('*, leases:leases!leases_property_id_fkey('
          'id, rent_amount_cents, charges_amount_cents, status, deleted_at, '
          'tenant:tenants(id, first_name, last_name))')
  .order('created_at', ascending: false)
  .limit(200);
```

Filtrage client : `status='active' AND deleted_at IS NULL`. Hypothèse 1 bail actif max/bien (convention métier).

**Pas de migration SQL.** RLS automatique via jointure.

## 5. Table view

`DataTable` M3, 7 colonnes :

| Colonne | Largeur min | Tri |
|---|---|---|
| Bien (name + address) | 220 | A↔Z |
| Type | 110 | A↔Z |
| Surface | 90 (right) | num ↑↓ |
| Statut | 110 | — |
| Locataire | 160 | A↔Z |
| Loyer CC | 130 (right) | num ↑↓ |
| Actions | 80 | — |

Tri client-side, lignes cliquables.

## 6. Empty / Loading / Error

**Empty** :
```dart
CardEmptyState(
  icon: Icons.home_outlined,
  title: 'Aucun bien enregistré',
  message: 'Ajoutez votre premier bien pour démarrer la gestion locative.\n'
           'Vous pourrez ensuite y associer des locataires et des baux.',
  action: FilledButton.icon('Ajouter un bien', → /properties/new),
)
```

**Loading** : 6 `CardSkeleton` (card) ou 6 `_TableSkeletonRow` (table).

**Error** : `_ErrorView` actuel conservé.

## 7. Filtres MVP

`SegmentedButton` mono-select, 3 segments : `Tous` / `Loués` / `Vacants`.

```dart
enum PropertyFilter { all, occupied, vacant }
```

État local non persisté. Filtrage client-side via `filteredPropertiesProvider`.

Mobile : `DropdownButton`.

## 8. Responsive

Identique Phase 1 (ViewModeToggle masqué <600px, CardGrid auto via `maxCrossAxisExtent: 380`).

## 9. Fichiers

### À créer

| Chemin |
|---|
| `lib/features/properties/domain/property_list_item.dart` |
| `lib/features/properties/domain/property_filter.dart` |
| `lib/features/properties/presentation/widgets/property_status_mapper.dart` |
| `lib/features/properties/presentation/widgets/properties_card_view.dart` |
| `lib/features/properties/presentation/widgets/properties_table_view.dart` |
| `lib/features/properties/presentation/widgets/properties_filter_bar.dart` |
| `lib/features/properties/application/properties_filter_provider.dart` |
| `test/widget/property_status_mapper_test.dart` |
| `test/widget/properties_card_view_test.dart` |
| `test/widget/properties_table_view_test.dart` |
| `test/widget/properties_filter_bar_test.dart` |

### À modifier

| Chemin | Changement |
|---|---|
| `lib/features/properties/data/property_repository.dart` | Ajouter `listWithLeases()` (jointure PostgREST) |
| `lib/features/properties/application/properties_list_provider.dart` | Nouveau provider `propertiesListItemsProvider` (AsyncNotifier<List<PropertyListItem>>) — conserver l'ancien si consommé ailleurs |
| `lib/features/properties/presentation/properties_list_page.dart` | Refactor : switch viewMode + FilterBar + CardEmptyState |
| `lib/features/properties/presentation/widgets/property_card.dart` | Réécriture complète (signature change : `(PropertyListItem item, {VoidCallback? onTap})`) |
| `test/widget/properties_list_page_test.dart` | Adapter empty + ajouter toggle/filter |

### À NE PAS toucher

- `property_detail_page.dart` (Phase 3)
- `property_form_page.dart` (Phase 3)
- `lib/features/leases/*` (déjà Phase 1)

## 10. Tests

**Unit `property_status_mapper_test.dart`** (4 cas) : occupied/vacant/archived + rent null.

**Widget** :
- `properties_card_view_test` : 0/3/6 items, tap, skeleton, warning vacant, success loué
- `properties_table_view_test` : N rows, tri, tap, action contextuelle
- `properties_filter_bar_test` : segment → state, mobile dropdown, filtre occupied
- `properties_list_page_test` (update) : empty rename, toggle, filter

## 11. Effort

| Sous-tâche | Heures |
|---|---|
| PropertyListItem + sérialisation | 1 |
| Refactor repo + provider (jointure) | 1.5 |
| Mapper + tests unit | 0.5 |
| PropertyCard v2 | 1.5 |
| PropertiesCardView | 0.5 |
| PropertiesTableView | 2 |
| FilterBar + provider + enum | 1 |
| Refactor properties_list_page | 1 |
| 4 widget tests | 2 |
| Adapter tests existants | 0.5 |
| QA manuel | 0.5 |
| **Total** | **~12 h ≈ 1-1,5 j** |

## 12. Décisions verrouillées

| # | Décision | Choix |
|---|---|---|
| 1 | Statuts | Loué / Vacant / Archivé (3 tons) |
| 2 | Détection occupé | jointure `leases` côté repo |
| 3 | Filtres | SegmentedButton 3 segments mono-select |
| 4 | Format loyer | `1 200 € CC / mois` (identique Phase 1) |
| 5 | Footer | "Modifier" + "Voir/Créer bail" (contextuel) |
| 6 | Branche | `feature/feat-012-properties-cards` post-merge Phase 1 |
| 7 | PropertyCard v1 | Réécriture complète (pas de coexistence) |
| 8 | Photo / Documents count | Hors scope (Phase 2.5) |
| 9 | Sort par défaut | `created_at DESC` (inchangé) |

## 13. Risques

1. Jointure peut renvoyer plusieurs baux → filtre client `status='active'`, prendre le premier. Documenter dans repo.
2. Performance 200 × ~3 baux → ~600 lignes max, OK.
3. Renommage provider → garder l'ancien en plus du nouveau pour ne pas casser d'autres pages.
4. DataTable mobile → toggle masqué <600px.
5. Drift conventions Phase 1 → réutiliser strictement les patterns/noms.
