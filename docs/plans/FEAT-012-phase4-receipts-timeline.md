# Plan — FEAT-012 Phase 4 — Refonte page Receipts en timeline / cards

> Designé par architect le 2026-06-22. À démarrer après merge Phase 3 (Tenants cards).
> Réutilise les foundations Phase 0 et les patterns Phases 1/2/3. Spécificité : page nested `/leases/:id/receipts`, pas de liste globale.

## 1. Vue d'ensemble

**Objectif** : Migrer `LeaseReceiptsPage` d'un `ListView`+`ListTile` plat vers une vue **timeline verticale par défaut** + toggle "Cards", cohérente avec les Phases 1-3 mais adaptée à la nature séquentielle mensuelle des quittances.

**Recommandation timeline par défaut** :
- Quittances forment une séquence temporelle mensuelle dense
- Pattern naturel "Stripe Payments" / "Linear changelog"
- Densité optimale (30-60 lignes/bail) sans scroll infini pénible
- Groupement par année apporte repère visuel immédiat

**Non-objectifs** (reportés Phase 4.5+) :
- Vue Table (pas pertinent pour cette page nested)
- Export PDF de l'année (ZIP)
- Preview PDF inline (modale `pdf.js`)
- Filtres composites multi-statuts

**Cible** : 1 PR mergeable en ~1,5 j (12-14 h).

**Branche** : `feature/feat-012-receipts-timeline` post-merge Phase 3.

## 2. Layout — Timeline + toggle Cards

### Toggle ViewMode
Réutilise `ViewModeToggle` Phase 0 sous clé `viewModeProvider('receipts:$leaseId')`. Labels custom `["Timeline", "Cards"]`.

### Structure timeline
```
┌── Bandeau contexte bail ──┐
└────────────────────────────┘
┌─ FilterBar : [Toutes] [Envoyées] [Payées] [Annulées]  • Année: 2026 ▾  • [Timeline|Cards]
─── 2026 ───  (sticky header)
│
●─ Mars 2026     ✓ Envoyée    1 200 € CC   [PDF] [Partager] [⋮]
│  Payée le 05/03 · Partagée le 06/03 à m***@gmail.com
│
●─ Février 2026  ✓ Payée      1 200 € CC   [PDF] [Partager] [⋮]
│  Payée le 04/02
│
●─ Janvier 2026  ⏳ Émise     1 200 € CC   [PDF] [Partager] [⋮]
│  Émise le 04/01
│
─── 2025 ───
│
●─ Décembre 2025 ✗ Annulée    —            [PDF] [⋮]
│  Erreur saisie loyer
```

- Ligne verticale `outlineVariant`, 2px
- Marker cercle 12px coloré selon tone du statut
- Header année : `titleSmall` semi-bold uppercase, séparateur 1px

### Vue Cards alternative
`CardGrid` 1/2/3 cols (max 360px). Pas de groupement année (juste tri DESC).

## 3. Composition

### TimelineItem
```dart
_ReceiptTimelineItem(
  receipt, tone, leftMarker,
  content: Row([
    Expanded(Column([
      Row([Text(periodMonthYear), StatusPill(tone, label, icon)]),
      Text(secondaryLine, style: bodySmall, color: onSurfaceVariant),
      if (voidReason != null) Text('Motif : $voidReason', color: error),
    ])),
    Text(totalEuros, style: titleMedium),
    _ReceiptActionsMenu(receipt, leaseId),
  ]),
)
```

`secondaryLine` :
- `valid + paid + sent` → "Payée le 04/03 · Partagée le 05/03 à m***@gmail.com"
- `valid + paid` → "Payée le 04/03"
- `valid` → "Émise le 04/03"
- `void` → "Annulée le 06/03"

### ReceiptCard v2 (vue Cards)
```dart
EntityCard(
  onTap: () => _openPdf(receipt),  // tap = ouvre PDF
  header: EntityCardHeader(
    title: periodMonthYear, subtitle: secondaryLine,
    trailing: StatusPill(tone, label),
  ),
  body: Column([
    _ReceiptCardRow(Icons.euro_outlined, '${totalEuros} CC'),
    if (isStale) _ReceiptCardRow(Icons.warning_amber, 'Périmée', color: warning),
    if (voidReason != null) _ReceiptCardRow(Icons.info_outline, voidReason!, color: danger),
  ]),
  footer: Wrap([
    OutlinedButton.icon('PDF', → _openPdf),
    ShareReceiptButton(...),
    if (!isVoided) IconButton('Annuler', color: danger),
  ]),
)
```

### `_ReceiptActionsMenu`
PopupMenuButton compact sur mobile/tablet, Row inline desktop (≥1024px) :
- "Ouvrir PDF" (toujours)
- "Partager" (si `!isVoided && !isStale && tenantEmail != null`)
- "Annuler" (si `!isVoided`, danger color)

## 4. Mapping statuts (5 effectifs)

| Condition | Tone | Label | Icon |
|---|---|---|---|
| `isVoided` | danger | Annulée | `cancel_outlined` |
| `isStale && !isVoided` | warning | Périmée | `warning_amber_outlined` |
| `!isVoided && hasBeenShared` | success | Envoyée | `task_alt_outlined` |
| `!isVoided && !shared && payment_ids non vide` | info | Payée | `paid_outlined` |
| sinon | info | Émise | `receipt_long_outlined` |

**Pas de "Brouillon"** : en DB une receipts row n'existe qu'après génération PDF réussie.

Helper : `receipt_status_mapper.dart` (pure function).

## 5. Bandeau contexte bail

`_LeaseContextBanner` compact card horizontal en tête de page :
```
Appartement Paris 2e · 12 rue de la Paix
▸ Jean Dupont · Bail 01/03/2026 → 01/03/2029 · 1 200 € CC/mois
                                12 quittances générées · 11 envoyées
```

- Nom property + locataire cliquables → navigation
- Skeleton si async pas résolu

## 6. Empty / Loading / Error

**Empty** :
```dart
CardEmptyState(
  icon: Icons.receipt_long_outlined,
  title: 'Aucune quittance générée',
  message: "Les quittances apparaissent ici dès qu'un paiement est enregistré et "
           "qu'une quittance est générée depuis la page Paiements.",
  action: FilledButton.icon('Voir les paiements', → /leases/:id/payments),
)
```

**Loading** : 6 `_TimelineSkeletonItem` (timeline) ou 6 `CardSkeleton` (cards).

**Error** : `_ErrorView` actuel conservé.

## 7. Filtres MVP

**Statut** : `SegmentedButton` 4 segments
```dart
enum ReceiptStatusFilter { all, sent, paid, voided }
```

**Année** : `DropdownButton<int>` peuplé dynamiquement. Défaut : année courante si présente.

État local non persisté via `receiptStatusFilterProvider(leaseId)` + `receiptYearFilterProvider(leaseId)`. Filtrage client-side via `filteredReceiptsProvider(leaseId)`.

Mobile : statut bascule Dropdown, toggle masqué (force Timeline).

## 8. Responsive

| Breakpoint | Timeline | Cards | FilterBar | Bandeau |
|---|---|---|---|---|
| Mobile <600 | Visible forcée | Masquée | Dropdowns empilés | Vertical 3 lignes |
| Tablet 600-1023 | Actions en menu ⋮ | Grid 2 col | SegmentedButton + Dropdown 1 ligne | Horizontal |
| Desktop ≥1024 | Actions inline Row | Grid 3 col | Tout sur 1 ligne | Horizontal full |

ViewMode initial : `timeline`.

## 9. Fichiers

### À créer

| Chemin |
|---|
| `lib/features/receipts/domain/receipt_status_filter.dart` |
| `lib/features/receipts/presentation/widgets/receipt_status_mapper.dart` |
| `lib/features/receipts/presentation/widgets/receipts_timeline_view.dart` |
| `lib/features/receipts/presentation/widgets/receipts_card_view.dart` |
| `lib/features/receipts/presentation/widgets/receipt_card.dart` |
| `lib/features/receipts/presentation/widgets/receipts_filter_bar.dart` |
| `lib/features/receipts/presentation/widgets/lease_context_banner.dart` |
| `lib/features/receipts/presentation/widgets/receipt_actions_menu.dart` |
| `lib/features/receipts/application/receipts_filter_provider.dart` |
| `test/widget/receipt_status_mapper_test.dart` |
| `test/widget/receipts_timeline_view_test.dart` |
| `test/widget/receipts_card_view_test.dart` |
| `test/widget/receipts_filter_bar_test.dart` |
| `test/widget/lease_context_banner_test.dart` |

### À modifier

| Chemin | Changement |
|---|---|
| `lib/features/receipts/presentation/lease_receipts_page.dart` | Refactor (switch viewMode + FilterBar + Bandeau + CardEmptyState) |
| `test/widget/lease_receipts_page_test.dart` | Adapter (si existe) |

### À supprimer

| Chemin |
|---|
| `lib/features/receipts/presentation/widgets/receipt_list_tile.dart` |

### À NE PAS toucher

- `share_receipt_button.dart`, `generate_receipt_button.dart`, `void_receipt_dialog.dart`, `profile_incomplete_dialog.dart`, `receipt_preview_dialog.dart`, `confirm_resend_dialog.dart`
- Repository + `leaseReceiptsProvider`
- `lease_detail_page.dart` ReceiptsListSection (hors scope)

## 10. Tests

**Unit `receipt_status_mapper_test.dart`** (6 cas).

**Widget** :
- `receipts_timeline_view_test` : 0/3/6 items, year header, marker color, tap actions menu, skeleton
- `receipts_card_view_test` : grid 1/2/3 col, tap → ouvre PDF (mock), footer actions, skeleton
- `receipts_filter_bar_test` : segment → state, dropdown année dynamique, mobile, toggle
- `lease_context_banner_test` : rendu nominal, skeletons partiels, tap navigation
- `lease_receipts_page_test` : empty rename, toggle, filtre combiné

## 11. Effort

| Sous-tâche | Heures |
|---|---|
| ReceiptStatusFilter + mapper + tests | 1 |
| Filter providers | 1 |
| FilterBar + dropdown année | 1.5 |
| LeaseContextBanner | 1.5 |
| ReceiptsTimelineView (item + year header + skeleton) | 3 |
| ReceiptCard v2 + ReceiptsCardView | 2 |
| ReceiptActionsMenu (popup + adaptation Row desktop) | 1 |
| Refactor lease_receipts_page | 1 |
| 5 widget tests | 3 |
| QA manuel | 1 |
| **Total** | **~15 h ≈ 1,5-2 j** |

## 12. Décisions verrouillées

| # | Décision | Choix |
|---|---|---|
| 1 | Vue par défaut | Timeline |
| 2 | Vue alternative | Cards uniquement (pas de Table) |
| 3 | Statuts | 5 (Annulée / Périmée / Envoyée / Payée / Émise) |
| 4 | "Brouillon" | Non applicable |
| 5 | Groupement | Par année avec header sticky |
| 6 | Tap card | Ouvre PDF directement |
| 7 | Actions timeline | PopupMenuButton mobile/tablet, Row desktop |
| 8 | Bandeau contexte | Compact card en tête, navigable |
| 9 | Filtres | SegmentedButton statut + Dropdown année + ViewModeToggle |
| 10 | Pagination | Aucune (200 items couvre 16 ans) |
| 11 | Réutilisation ShareReceiptButton | Oui (card footer + helper pour menu) |
| 12 | Sort | `period_start DESC` (inchangé) |
| 13 | Branche | `feature/feat-012-receipts-timeline` post-Phase 3 |
| 14 | Suppression `receipt_list_tile.dart` | Oui |
| 15 | Promotion Timeline → design system | Non (local feature) |

## 13. Risques

1. **"Payée le DD/MM" approximé par `generated_at`** — pas de jointure `payments.paid_at` Phase 4. À tracker P1.
2. **Sticky year header sur Flutter Web** — `SliverPersistentHeader` peut friction sur grandes listes. Fallback : commencer non-sticky.
3. **Drift conventions Phases 1-3** — Timeline nouveau pattern. Si Payments réutilise, promouvoir au design system à ce moment.
4. **PopupMenuButton vs Row desktop** — factoriser via liste `_ReceiptAction` parcourue par les deux variantes.
5. **Bandeau 3 async chargements** — skeleton ligne-par-ligne pour éviter "flash".
