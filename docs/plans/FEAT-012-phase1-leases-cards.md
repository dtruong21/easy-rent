# Plan — FEAT-012 Phase 1 — Refonte page Leases en cards

> Designé par architect le 2026-06-22. Validation user OK (toutes décisions par défaut retenues).
> Démarrage : après merge de la PR Phase 0 (foundations).

## 1. Vue d'ensemble

**Objectif** : Première application des foundations Phase 0 (`EntityCard`, `StatusPill`, `CardGrid`, `ViewModeToggle`, `CardSkeleton`, `CardEmptyState`) à une page réelle — Leases — la plus rich en métadonnées.

**Non-objectifs** (reportés Phase 1.5+) :
- Statut "En retard" composite (exige jointure payments — voir task #27)
- Recherche full-text, filtres multi-statuts, saved views
- Migration des pages Properties / Tenants / Receipts

**Cible** : 1 PR mergeable en 1-2 jours après Phase 0. Code v1 supprimé (pas de coexistence).

**Branche** : `feature/feat-012-leases-cards` dérivée de `develop` après merge Phase 0.

## 2. Composition LeaseCard v2

```
EntityCard(
  onTap: () => context.push('/leases/${lease.id}'),
  header: EntityCardHeader(
    title: item.propertyName,
    trailing: StatusPill(tone, label, icon, size: sm),
  ),
  body: Column(
    [
      _LeaseCardRow(Icons.person_outline, item.tenantDisplayName),
      _LeaseCardRow(Icons.calendar_today_outlined, "01/03/2026 → 01/03/2029 (3 ans)"),
      _LeaseCardRow(Icons.euro_outlined, "1 200 € CC / mois"),
    ],
  ),
  footer: Wrap(spacing: 8, [
    OutlinedButton.icon(Icons.receipt_long_outlined, 'Quittances', → /leases/:id/receipts),
    OutlinedButton.icon(Icons.add, 'Paiement', → /leases/:id/payments/new),
  ]),
)
```

- `subtitle` retiré en Phase 1 (LeaseListItem ne contient pas address+apt+rooms — à enrichir plus tard si besoin)
- `_LeaseCardRow` privé inline dans `lease_card.dart` (Row + Icon size 14 + Text bodySmall)
- Tap sur card entière → push détail bail. Footer actions ne propagent pas (hit-testing Flutter natif).

## 3. Mapping statuts (priorité descendante)

| Condition | Tone | Label | Icon |
|---|---|---|---|
| `active` ET `endDate − today < 60j` | warning | À renouveler | `event_repeat_outlined` |
| `active` (par défaut) | success | Actif | `check_circle_outline` |
| `terminated` | neutral | Terminé | `lock_outline` |
| `archived` | neutral | Archivé | `archive_outlined` |

**Helper** : `lib/features/leases/presentation/widgets/lease_status_mapper.dart`
```dart
({StatusPillTone tone, String label, IconData icon}) leaseStatusPill(
  Lease lease, {DateTime? now}) { ... }
```

`now` injectable pour tests sans `package:clock`.

**"En retard" reporté Phase 1.5** — exige jointure backend payments (task #27 tracké).

## 4. Table view (ViewMode.table)

`DataTable` Material 3 wrappé dans `SingleChildScrollView` horizontal + `Card` container.

| Colonne | Largeur min | Tri | Source |
|---|---|---|---|
| Bien | 200 | A↔Z | `item.propertyName` |
| Locataire | 180 | A↔Z | `item.tenantDisplayName` |
| Période | 200 | début ↑↓ | `lease.startDate → lease.endDate` |
| Loyer CC | 120 (right) | montant ↑↓ | `MoneyFormat.formatEurosFromCents` |
| Statut | 120 | — | `StatusPill` |
| Actions | 100 | — | IconButton Quittances + IconButton Paiement |

- Tri client-side (`sortColumnIndex` + `sortAscending`)
- Lignes cliquables via `DataRow(onSelectChanged: ...)` + `showCheckboxColumn: false`
- Container : padding 16, bg `surfaceContainerLow`, border 1px `outlineVariant`, radius `radii.md`

## 5. Empty / Loading / Error

**Empty** (`leases.isEmpty`) :
```dart
CardEmptyState(
  icon: Icons.description_outlined,
  title: 'Aucun bail enregistré',
  message: 'Créez un bail pour démarrer la gestion locative.\n'
           "Vous aurez besoin d'au moins un bien et un locataire.",
  action: FilledButton.icon(Icons.add, 'Créer un bail', → /leases/new),
)
```

**Loading** :
- Card view : `CardGrid` avec 6 `CardSkeleton`
- Table view : 6 `_TableSkeletonRow` privées (cellule Container w=120, h=12, color outlineVariant 60%)

**Error** : conservé `_ErrorView` actuel.

## 6. Filtres MVP

`SegmentedButton` mono-select, 4 segments :
```
[Tous] [Actifs] [À renouveler] [Terminés]
```

```dart
enum LeaseFilter { all, active, renewable, terminated }
```

- État via `StateProvider<LeaseFilter>` local au feature, non persisté
- Filtrage client-side via `filteredLeasesProvider` dérivé (200 items max, OK en mémoire)
- Mobile (<600px) : bascule en `DropdownButton`

## 7. Responsive

| Breakpoint | ViewModeToggle | CardGrid | DataTable | Filtres |
|---|---|---|---|---|
| Mobile <600 | Masqué (force Card) | 1 col | N/A | `DropdownButton` |
| Tablet 600-1023 | Visible | 2 col auto | scroll horizontal | `SegmentedButton` |
| Desktop ≥1024 | Visible | 3+ col auto | full width | `SegmentedButton` |

ViewMode initial : `card`. Persisté via Phase 0 `viewModeProvider('leases')`.

## 8. Fichiers

### À créer

| Chemin | Rôle |
|---|---|
| `lib/features/leases/presentation/widgets/lease_status_mapper.dart` | Pure function status → pill |
| `lib/features/leases/presentation/widgets/leases_card_view.dart` | CardGrid + builder LeaseCard |
| `lib/features/leases/presentation/widgets/leases_table_view.dart` | DataTable + tri + container |
| `lib/features/leases/presentation/widgets/leases_filter_bar.dart` | SegmentedButton/Dropdown + ViewModeToggle |
| `lib/features/leases/application/leases_filter_provider.dart` | StateProvider + filteredLeasesProvider |
| `lib/features/leases/domain/lease_filter.dart` | enum + labelFr |
| `test/widget/lease_status_mapper_test.dart` | Unit pure (6 cas) |
| `test/widget/leases_card_view_test.dart` | Widget (5 tests) |
| `test/widget/leases_table_view_test.dart` | Widget (5 tests) |
| `test/widget/leases_filter_bar_test.dart` | Widget (3 tests) |

### À modifier

| Chemin | Changement |
|---|---|
| `lib/features/leases/presentation/leases_list_page.dart` | Refactor : switch viewMode → CardView/TableView + FilterBar en haut, garde Scaffold/AppBar/FAB/_ErrorView, empty via CardEmptyState |
| `lib/features/leases/presentation/widgets/lease_card.dart` | Réécriture complète (EntityCard + StatusPill + mapper). Signature publique inchangée `(LeaseListItem item, VoidCallback onTap)` |
| `test/widget/leases_list_page_test.dart` | Adapter assertion empty + ajouter test toggle/filter |

### À NE PAS toucher (hors scope Phase 1)

- `lib/features/leases/presentation/lease_detail_page.dart` (Phase 2)
- `lib/features/tenants/presentation/widgets/tenant_lease_summary.dart` (Phase 2)
- `lib/core/widgets/lease_status_badge.dart` (conservé `@Deprecated`, supprimé Phase 2)

## 9. Tests

**Unit** (`lease_status_mapper_test.dart`) — 6 cas :
- `active, endDate=null` → success "Actif"
- `active, endDate=today+90j` → success
- `active, endDate=today+59j` → warning "À renouveler"
- `active, endDate=today-10j` → success (échu pas pertinent ici)
- `terminated` → neutral "Terminé"
- `archived` → neutral "Archivé"

**Widget** :
- `leases_card_view_test` : 0/3/6 items, tap → push, skeleton state, warning renewable
- `leases_table_view_test` : N rows, tri header, tap row, action icons, loading
- `leases_filter_bar_test` : segment → provider state, mobile dropdown, filtre renewable
- `leases_list_page_test` (update) : empty rename, toggle viewMode, filter

**Pas de RLS tests** (aucune migration Phase 1).

## 10. Effort

| Sous-tâche | Heures |
|---|---|
| Mapper + tests | 1 |
| LeaseCard v2 réécriture | 1.5 |
| LeasesCardView | 1 |
| LeasesTableView (DataTable + tri) | 2.5 |
| FilterBar + provider + enum | 1.5 |
| Refactor leases_list_page | 1 |
| Adapter test page existant | 0.5 |
| 3 widget tests nouveaux | 2.5 |
| QA manuel multi-écrans + dark mode | 1 |
| **Total** | **12.5 h ≈ 1.5j** |

## 11. Décisions verrouillées

| # | Décision | Choix |
|---|---|---|
| 1 | "En retard" | Reporté Phase 1.5 (task #27) |
| 2 | Footer actions | "Quittances" + "+ Paiement" |
| 3 | Filtres | SegmentedButton 4 segments mono-select |
| 4 | Format période | `01/03/2026 → 01/03/2029 (3 ans)` |
| 5 | Loyer | `1 200 € CC / mois` |
| 6 | Branche | Nouvelle `feature/feat-012-leases-cards` post-merge Phase 0 |
| 7 | Suppression `LeaseStatusBadge` | Phase 2 (encore consommé par detail + tenants) |
| 8 | Sort par défaut | Conserver actuel (status ASC, start_date DESC) |

## 12. Risques

1. **Pas de "En retard" Phase 1** — décalage potentiel vs attentes UI Linear/Jira complète. Mitigation : tracker task #27, comm transparente.
2. **DataTable mobile UX** — couvert par toggle masqué <600px.
3. **Tests existants à fixer** — ~30 min adapt.
4. **Performance 200 cards** — OK via `CardGrid.builder` virtualization.
