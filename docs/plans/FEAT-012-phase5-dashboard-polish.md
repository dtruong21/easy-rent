# Plan — FEAT-012 Phase 5 — Dashboard polish (harmonisation cards)

> Designé par architect le 2026-06-22.
> Démarrage : après merge des PRs Phases 1-4.
> Branche : `feature/feat-012-dashboard-polish`.

## 1. Vue d'ensemble

**Objectif** : Aligner le dashboard FEAT-010 (KpiCard, MonthlyBarchart, RecentActivitySection, OnboardingFirstSteps, ShortcutsRow) sur les foundations Phase 0 (`AppColors`, `AppSpacing`, `AppRadii`, `StatusPill`). Phase **polish**, pas refonte.

**Cible** : 1 PR ≤ 1j. Aucune migration SQL, aucun changement backend, aucun changement de structure visuelle. On échange juste les valeurs hardcodées contre des tokens.

**Non-objectifs** :
- Pas de refonte Stripe-like (déjà esprit FEAT-010, on harmonise sans réinventer)
- Pas de transformation `KpiCard` en `EntityCard`
- Pas de page `/activity` dédiée
- Pas de mini-charts dans les KPI cards

## 2. Audit du dashboard

| Widget | Dette tokens |
|---|---|
| `DashboardHeader` | `EdgeInsets.only(bottom: 20)` hardcodé |
| `KpiCard` | `EdgeInsets.all(16)`, `BorderRadius.circular(8)`, sizes 20/12/2 hardcodés |
| `KpiGrid` | `crossAxisSpacing: 12`, breakpoints 900/600, couleurs sémantiques via Material |
| `MonthlyBarchart` | `BorderRadius.circular(4)`, couleurs `primary` + `outlineVariant`, bg/wrapper inexistant |
| `RecentActivitySection` | `ListTile` natif, `contentPadding 0`, pas de wrapper card |
| `OnboardingFirstSteps` | `Padding(24)`, `Divider`, déjà cohérent |
| `ShortcutsRow` | `Wrap(spacing: 12)`, `EdgeInsets.symmetric(16, 12)` |
| `dashboard_page.dart` | `EdgeInsets.fromLTRB(16, 16, 16, 32)`, `SizedBox(height: 24)` × 3 |

Dette commune : couleurs status tirées du `ColorScheme` Material au lieu de `AppColors`. Le barchart n'a pas de container card.

## 3. Refactor par composant

### 3.1 `KpiCard`
Garder API publique. Internes :
- `padding` → `spacing.cardPaddingStandard` (16)
- `Container` icône radius → `radii.sm` (6), padding → `spacing.sm` (8)
- `SizedBox(height: 12)` → `spacing.md`
- Chevron `16` conservé (cohérent leases card v2)

**Pas migré vers `EntityCard`** : format ultra-compact spécifique, slots header/body/footer pas pertinents.

### 3.2 `KpiGrid`
Couleurs sémantiques via `AppColors` :
```dart
final colors = Theme.of(context).extension<AppColors>()!;
loyersTone = encaissed < due ? colors.danger.solid : colors.success.solid;
retardsTone = retards > 0 ? colors.danger.solid : colors.neutral.solid;
renouvellementsTone = renouvellements > 0 ? colors.warning.solid : colors.neutral.solid;
docsTone = docs > 0 ? colors.info.solid : colors.neutral.solid;
```

Gaps → `spacing.md`. Breakpoints inchangés.

### 3.3 `MonthlyBarchart`
Wrapper card autour :
```dart
Container(
  padding: EdgeInsets.all(spacing.cardPaddingStandard),
  decoration: BoxDecoration(
    color: surface, borderRadius: BorderRadius.circular(radii.md),
    border: Border.all(color: outlineVariant),
  ),
  child: Column([titre, chart, legend]),
)
```

- Couleur barre "encaissé" → `AppColors.info.solid`
- Couleur barre "dû" → `AppColors.neutral.surface`
- `_EmptyState` → `CardEmptyState(icon: Icons.bar_chart_outlined, title: 'Pas encore d\'historique', message: 'Les loyers apparaîtront ici dès le 1er paiement.')`

### 3.4 `RecentActivitySection`
Wrapper card identique. Garder `ListTile`. `_EmptyState` → `CardEmptyState(icon: Icons.history, title: 'Aucune activité récente', message: 'Commencez par enregistrer un paiement.')`. Bouton "Voir tout" reste disabled.

### 3.5 `OnboardingFirstSteps` + `ShortcutsRow`
Juste swap tokens (`spacing.xl`, `spacing.md`, `radii.md`).

### 3.6 `DashboardHeader` + `dashboard_page.dart`
- `EdgeInsets.fromLTRB(16, 16, 16, 32)` → `EdgeInsets.fromLTRB(spacing.lg, spacing.lg, spacing.lg, spacing.xxl)`
- `SizedBox(height: 24)` → `spacing.xl` (×3)

## 4. Décisions clés

| # | Question | Décision | Pourquoi |
|---|---|---|---|
| 1 | `KpiCard` → `EntityCard` ? | NON, séparé | Format/contraintes spécifiques, code court |
| 2 | Refonte profonde (feed, sparklines) | NON | Hors scope polish |
| 3 | `fl_chart` conservé | OUI | Déjà installé FEAT-010, mature |
| 4 | `StatusPill` dans dashboard | NON Phase 5 | Pas de statut texte explicite |
| 5 | Dark mode | Hérité auto | Tokens validés WCAG AA Phase 0 |
| 6 | Nouveau `StatsBlock`/`ActivityFeed` | NON | YAGNI |
| 7 | Empty states | `CardEmptyState` partout | Cohérence Phase 0 |
| 8 | Couleur barre "encaissé" | `AppColors.info.solid` | Lit mieux pour montants positifs neutres |

## 5. Layout responsive

Conservé tel quel :
- `KpiGrid` : 1/2/4 cols (breakpoints 600/900)
- `MonthlyBarchart` : hauteur 160 (<600) / 200 (≥600)
- `ShortcutsRow` : Wrap natif
- `OnboardingFirstSteps` : pleine largeur

À vérifier QA : breakpoints toujours OK avec wrapper card barchart (texte axes en <600px).

## 6. Fichiers

### À modifier (8 fichiers)

| Chemin | Changement |
|---|---|
| `lib/features/dashboard/presentation/dashboard_page.dart` | Padding/SizedBox → tokens |
| `lib/features/dashboard/presentation/widgets/dashboard_header.dart` | Padding bottom → `spacing.lg` |
| `lib/features/dashboard/presentation/widgets/kpi_card.dart` | Paddings/radius/sizes → tokens (API publique inchangée) |
| `lib/features/dashboard/presentation/widgets/kpi_grid.dart` | Couleurs via `AppColors` + spacings tokens |
| `lib/features/dashboard/presentation/widgets/monthly_barchart.dart` | Wrapper card + `AppColors` + `CardEmptyState` |
| `lib/features/dashboard/presentation/widgets/recent_activity_section.dart` | Wrapper card + `CardEmptyState` + tokens |
| `lib/features/dashboard/presentation/widgets/onboarding_first_steps.dart` | Paddings → tokens |
| `lib/features/dashboard/presentation/widgets/shortcuts_row.dart` | Wrap/padding → tokens |
| `test/widget/dashboard_page_test.dart` | Adapter assertions empty states |

### À créer

Aucun (Phase polish, tout passe par foundations existantes).

## 7. Tests

Pas de nouveau fichier. Adapter `dashboard_page_test.dart` :
- Empty state activity : nouvelle assertion `CardEmptyState`
- Empty state barchart : idem
- Ajouter assertion "KPI retards utilise `AppColors.danger` quand count>0"

**Aucun test backend** (pas de changement).

QA manuel :
- Light + dark mode
- Breakpoints 360 / 768 / 1280
- Onboarding vs data view
- Screenshots avant/après recommandés

## 8. Effort

| Sous-tâche | Heures |
|---|---|
| `KpiCard` swap tokens | 0.5 |
| `KpiGrid` couleurs `AppColors` | 0.5 |
| `MonthlyBarchart` wrapper + couleurs + EmptyState | 1.5 |
| `RecentActivitySection` wrapper + EmptyState + tokens | 1 |
| `OnboardingFirstSteps` + `ShortcutsRow` + `DashboardHeader` + page | 1 |
| Adapter `dashboard_page_test.dart` | 0.5 |
| QA manuel + revue ratios | 1 |
| **Total** | **~6 h ≈ 1 j** |

Phase la plus light de FEAT-012.

## 9. Décisions verrouillées

1. `KpiCard` reste séparé (pas de `EntityCard` migration).
2. Pas de refonte feed activité (`ListTile` conservé).
3. `fl_chart` conservé.
4. Couleur barre "encaissé" = `AppColors.info.solid`, "dû" = `AppColors.neutral.surface`.
5. Empty states barchart + activity → `CardEmptyState`.
6. Wrapper card autour barchart + activity (border `outlineVariant`, radius `radii.md`, padding `cardPaddingStandard`, bg `surface`).
7. Dark mode hérité.
8. Branche `feature/feat-012-dashboard-polish` post-merge Phase 4.

## 10. Risques

1. **Couleurs barchart "info"** (bleu) vs "primary" (teal) — peut perdre cohérence FEAT-010. Mitigation : QA visuel ; fallback `colors.success.solid` si rejet.
2. **Wrapper card MonthlyBarchart débordant <360px** — axes Y serrés. Mitigation : padding compact si `maxWidth < 480`.
3. **Tests dashboard** — empty states changent de texte, ~20 min adapt.
4. **Rod radius `fl_chart`** — peut différer de `radii.sm` (6). Si bizarre, conserver `4` hardcodé.
5. **Régression visuelle** — phase polish = peu logique mais beaucoup pixels. QA screenshots avant/après recommandé.
