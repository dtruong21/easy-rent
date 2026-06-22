# Plan — FEAT-012 Phase 3 — Refonte page Tenants en cards

> Designé par architect le 2026-06-22. À démarrer après merge Phase 2 (Properties cards).
> Réutilise les foundations Phase 0 et les patterns Phases 1/2.

## 1. Vue d'ensemble

**Objectif** : Migrer `/tenants` vers une vue cards + table (toggle), cohérente avec Leases / Properties, et exposer le statut locatif (Actif / Sans bail) via jointure leases.

**Non-objectifs** (reportés Phase 3.5+) :
- Avatar / photo (pas de bucket avatar aujourd'hui)
- Indicateur de paiement à jour ("En retard") — même décision que Phase 1.5
- Recherche full-text, filtres multi-statuts, saved views
- Distinction fine "Inactif" vs "Sans bail"

**Cible** : 1 PR mergeable en ~1 jour (10-12 h).

**Branche** : `feature/feat-012-tenants-cards` dérivée de `develop` après merge Phase 2.

## 2. Composition TenantCard v2

```
EntityCard(
  onTap: () => context.push('/tenants/${item.tenant.id}'),
  header: EntityCardHeader(
    title: "${firstName} ${lastName}",
    subtitle: tenant.email,                            // NOT NULL en DB
    trailing: StatusPill(tone, label),                 // Actif / Sans bail
  ),
  body: Column([
    _TenantCardRow(Icons.phone_outlined, tenant.phone ?? '—'),
    _TenantCardRow(Icons.home_outlined, item.currentPropertyName ?? 'Aucun bien occupé'),
    _TenantCardRow(Icons.calendar_today_outlined, item.activeLeasePeriodLabel ?? '—'),
  ]),
  footer: Wrap([
    if (activeLeaseId != null) OutlinedButton('Voir le bail' → /leases/:id)
    else OutlinedButton('Créer un bail' → /leases/new?tenantId=...)
    OutlinedButton('Modifier' → /tenants/:id/edit)
  ]),
)
```

## 3. Mapping statut

| Condition | Tone | Label | Icon |
|---|---|---|---|
| `activeLeaseId != null` | success | Actif | `person_outline` |
| `activeLeaseId == null` | warning | Sans bail | `person_add_outlined` |

**Décision : 2 statuts seulement** (pas de "Inactif" distinct — granularité historique dispo dans `/tenants/:id`).

Helper : `lib/features/tenants/presentation/widgets/tenant_status_mapper.dart` (pure function).

## 4. Source des données — `TenantListItem`

```dart
class TenantListItem {
  final Tenant tenant;
  final String? activeLeaseId;
  final String? currentPropertyName;
  final String? activeLeasePeriodLabel;
  final int? activeLeaseRentCents;
}
```

Requête repo `listWithActiveLeases()` :
```dart
await Db.from('tenants')
  .select('*, leases:leases!leases_tenant_id_fkey('
          'id, status, deleted_at, start_date, end_date, rent_amount_cents, '
          'property:properties(id, name))')
  .order('last_name', ascending: true)
  .order('first_name', ascending: true)
  .limit(200);
```

Filtrage client : `status='active' AND deleted_at IS NULL`. Si plusieurs baux actifs, prendre le plus récent par `start_date`.

**Pas de migration SQL.** RLS automatique.

Format `activeLeasePeriodLabel` :
- `end_date == null` → `"Depuis ${FrenchDate.formatIsoString(startDate)}"`
- sinon → `"${start} → ${end}"`

## 5. Table view

| Colonne | Largeur min | Tri |
|---|---|---|
| Nom | 180 | A↔Z |
| Email | 200 | A↔Z |
| Téléphone | 130 | — |
| Statut | 110 | — |
| Bien occupé | 180 | A↔Z |
| Loyer CC | 130 (right) | num ↑↓ |
| Actions | 100 | — |

Tri client-side, lignes cliquables (`DataRow.onSelectChanged`, `showCheckboxColumn: false`).

## 6. Empty / Loading / Error

**Empty** :
```dart
CardEmptyState(
  icon: Icons.people_outline,
  title: 'Aucun locataire enregistré',
  message: "Ajoutez votre premier locataire pour démarrer.\n"
           "Vous pourrez ensuite l'associer à un bien via un bail.",
  action: FilledButton.icon('Ajouter un locataire', → /tenants/new),
)
```

**Loading** : 6 `CardSkeleton` (card) ou 6 `_TableSkeletonRow` (table).

**Error** : `_ErrorView` actuel conservé.

**Bandeau limite 200** : conservé.

## 7. Filtres MVP

`SegmentedButton` mono-select, 3 segments : `Tous` / `Actifs` / `Sans bail`.

```dart
enum TenantFilter { all, withActiveLease, withoutActiveLease }
```

État local, filtrage client-side. Mobile → `DropdownButton`.

## 8. Responsive

Identique Phases 1-2 (ViewModeToggle masqué <600px, CardGrid auto, DropdownButton fallback).

## 9. Fichiers

### À créer

| Chemin |
|---|
| `lib/features/tenants/domain/tenant_list_item.dart` |
| `lib/features/tenants/domain/tenant_filter.dart` |
| `lib/features/tenants/presentation/widgets/tenant_status_mapper.dart` |
| `lib/features/tenants/presentation/widgets/tenants_card_view.dart` |
| `lib/features/tenants/presentation/widgets/tenants_table_view.dart` |
| `lib/features/tenants/presentation/widgets/tenants_filter_bar.dart` |
| `lib/features/tenants/application/tenants_filter_provider.dart` |
| `test/widget/tenant_status_mapper_test.dart` |
| `test/widget/tenants_card_view_test.dart` |
| `test/widget/tenants_table_view_test.dart` |
| `test/widget/tenants_filter_bar_test.dart` |

### À modifier

| Chemin | Changement |
|---|---|
| `lib/features/tenants/data/tenant_repository.dart` | Ajouter `listWithActiveLeases()`. `list()` conservé (utilisé par TenantPicker dans LeaseForm). |
| `lib/features/tenants/application/tenants_list_provider.dart` | Nouveau `tenantsListItemsProvider`. Conserver `tenantsListProvider` (utilisé ailleurs). |
| `lib/features/tenants/presentation/tenants_list_page.dart` | Refactor (switch viewMode + FilterBar + CardEmptyState) |
| `lib/features/tenants/presentation/widgets/tenant_card.dart` | Réécriture complète (signature change : `TenantListItem`) |
| `test/widget/tenants_list_page_test.dart` | Adapter empty + ajouter toggle/filter |

### À NE PAS toucher

- `tenant_detail_page.dart`, `tenant_lease_summary.dart`, `tenant_form.dart`
- `lease_status_badge.dart` (encore consommé par `tenant_lease_summary`)

## 10. Tests

**Unit `tenant_status_mapper_test.dart`** (3 cas).

**Widget** :
- `tenants_card_view_test` : 0/3/6 items, tap, skeleton, warning/success
- `tenants_table_view_test` : N rows, tri 4 cols, tap row, action contextuelle
- `tenants_filter_bar_test` : segment → state, mobile dropdown, filtre
- `tenants_list_page_test` (update) : empty rename, toggle, filter

## 11. Effort

| Sous-tâche | Heures |
|---|---|
| TenantListItem + sérialisation jointure | 1 |
| Refactor repo + provider (jointure) | 1.5 |
| Mapper + tests unit | 0.5 |
| TenantCard v2 | 1.5 |
| TenantsCardView | 0.5 |
| TenantsTableView | 2 |
| FilterBar + provider + enum | 1 |
| Refactor tenants_list_page | 1 |
| 4 widget tests | 2 |
| Adapter tests existants | 0.5 |
| QA manuel | 0.5 |
| **Total** | **~12 h ≈ 1-1,5 j** |

## 12. Décisions verrouillées

| # | Décision | Choix |
|---|---|---|
| 1 | Statuts | 2 tons (Actif / Sans bail) — pas de "Inactif" |
| 2 | Détection actif | jointure `leases` côté repo |
| 3 | Indicateur paiement | Reporté (cohérent task #27) |
| 4 | Filtres | SegmentedButton 3 segments mono-select |
| 5 | Footer | "Modifier" + "Voir/Créer bail" (contextuel) |
| 6 | Sort par défaut | `last_name ASC, first_name ASC` (inchangé) |
| 7 | TenantCard v1 | Réécriture complète |
| 8 | `tenantsListProvider` brut | Conservé (LeaseForm picker) |
| 9 | Subtitle email | Affiché direct (NOT NULL en DB) |
| 10 | Branche | `feature/feat-012-tenants-cards` post-merge Phase 2 |

## 13. Risques

1. Jointure peut renvoyer plusieurs baux → filtre client + tri par `start_date DESC`.
2. Double provider tenants (avec / sans lease info) → maintenance temporaire, acceptable.
3. Performance 200 × ~5 baux historiques ≈ 1000 sous-lignes max, OK.
4. DataTable mobile → toggle masqué <600px.
5. Drift conventions Phases 1-2 → réutiliser strictement les patterns/noms.
