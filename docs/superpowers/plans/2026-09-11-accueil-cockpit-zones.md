# Onglet Accueil — cockpit à 3 zones — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructurer le contenu de l'onglet Accueil en trois zones nommées (À traiter / Mon patrimoine / Analyse), déplacer « documents en attente » en ligne passive, et dédupliquer le cash-flow.

**Architecture:** Pure recomposition de widgets et providers déjà montés — aucune nouvelle requête Firestore. Quatre tâches séquentielles, chacune laissant l'arbre compilable et la suite verte : d'abord les widgets changent leur contenu/signature (T1 interne, T2 et T3 changent leur constructeur et mettent à jour leur unique call-site dans `dashboard_page.dart`), puis T4 réorganise la composition en 3 zones.

**Tech Stack:** Flutter (web + mobile), Riverpod, freezed, flutter gen-l10n (ARB FR/EN).

## Global Constraints

- **Zéro nouvelle requête Firestore** ; accès Firestore jamais en direct (aucun nouvel accès — recomposition).
- **Jetons de design uniquement** : `Theme.of(context).extension<AppColors>()`, `AppSpacing`, `AppRadii`. Aucune couleur en dur.
- **i18n FR + EN** pour tout libellé visible ; `@key.description` obligatoire sur le gabarit EN (`app_en.arb`) — le test `test/l10n/arb_parity_test.dart` l'impose, ainsi que la parité des clés FR/EN.
- **Responsive** via `core/ui/breakpoints.dart` (seuil 600).
- Réutiliser les widgets et providers existants ; ne pas réécrire les panneaux.
- Commits : terminer par `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`. Stager des chemins explicites, jamais `git add -A`.
- Générés gitignored : après toute modif d'ARB lancer `flutter gen-l10n` ; après modif d'un modèle freezed lancer `dart run build_runner build --delete-conflicting-outputs`.

---

### Task 1: PortfolioYield — déduplication du cash-flow

Retire la carte « cash-flow mensuel total », l'agrégat `totalMonthlyCashflowCents` (devenu mort, seul la carte le consommait), la note de méthodologie cash-flow, et le titre interne de la section (il sera porté par l'en-tête de zone en T4). Conserve rendement brut/net + la note « X/total ».

**Files:**
- Modify: `lib/features/dashboard/presentation/widgets/portfolio_yield_section.dart`
- Modify: `test/widget/portfolio_yield_section_test.dart`
- Modify: `lib/l10n/app_fr.arb`, `lib/l10n/app_en.arb`
- Regénère: `portfolio_yield_section.freezed.dart` (via build_runner)

**Interfaces:**
- Consumes: `computeSnapshotForProperty` (inchangé), `propertiesListItemsProvider`, `expensesRepositoryProvider` (inchangés).
- Produces: `PortfolioYieldSummary` SANS le champ `totalMonthlyCashflowCents` ; `PortfolioYieldSection()` (constructeur inchangé) affichant 2 cartes (brut, net) et plus de titre interne.

- [ ] **Step 1: Mettre à jour les tests (retirer les attentes cash-flow)**

Dans `test/widget/portfolio_yield_section_test.dart` :
- Supprimer les 4 assertions unitaires restantes référençant le champ : lignes `expect(summary.totalMonthlyCashflowCents, 62500);`, `expect(summary.totalMonthlyCashflowCents, isNull);` (dans le test « entièrement non calculable »), `expect(summary.totalMonthlyCashflowCents, 144000);`, et `expect(summary.totalMonthlyCashflowCents, isNull);` (dans « portfolio vide »).
- Supprimer **entièrement** le test dédié dont c'est la seule assertion : `test('dépenses réelles fournies pour un bien → cash flow agrégé bascule ...', () { ... expect(summary.totalMonthlyCashflowCents, 130000); });` (le basculement réel/prévisionnel par bien reste couvert au niveau de la fiche bien).

- [ ] **Step 2: Lancer les tests — échec de compilation attendu**

Run: `flutter test test/widget/portfolio_yield_section_test.dart`
Expected: échoue — le code source référence encore `totalMonthlyCashflowCents` et la carte, mais c'est cohérent ; on corrige la source à l'étape suivante. (Si l'outil compile tout le paquet, l'erreur vient du source non encore modifié — c'est attendu.)

- [ ] **Step 3: Retirer le champ de l'agrégat et son calcul**

Dans `portfolio_yield_section.dart`, classe `PortfolioYieldSummary` : supprimer la ligne
```dart
    /// Cash flow mensuel total (centimes) — somme des biens calculables.
    /// Null si aucun bien n'a de charges ou de prêt renseignés.
    int? totalMonthlyCashflowCents,
```
Dans `computePortfolioYield` : supprimer `int totalMonthlyCashflowCents = 0;`, `bool hasCashflow = false;`, le bloc
```dart
    final cashflow = snapshot.monthlyCashflowBeforeTaxCents;
    if (cashflow != null) {
      totalMonthlyCashflowCents += cashflow;
      hasCashflow = true;
    }
```
et la ligne `totalMonthlyCashflowCents: hasCashflow ? totalMonthlyCashflowCents : null,` du `return`.

- [ ] **Step 4: Retirer le titre interne, la carte cash-flow et la note de méthodologie**

Dans le widget `PortfolioYieldSection.build`, supprimer le `Text(context.l10n.dashboardPortfolioYieldSectionTitle, ...)` et le `SizedBox(height: spacing.md)` qui le suit, de sorte que la section commence directement par le `asyncYield.when(...)`.

Dans `_PortfolioYieldData.build`, supprimer la 3ᵉ `_PortfolioKpiCard` (`key: const Key('kpi_portfolio_cashflow')`) du `Wrap`, et supprimer le bloc
```dart
        if (summary.totalMonthlyCashflowCents != null)
          Text(
            l10n.dashboardPortfolioYieldCashflowMethodology,
            ...
          ),
```

- [ ] **Step 5: Régénérer le freezed**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: succès ; `portfolio_yield_section.freezed.dart` ne mentionne plus `totalMonthlyCashflowCents`.

- [ ] **Step 6: Retirer les 3 clés i18n orphelines + regénérer**

Dans `app_fr.arb` ET `app_en.arb`, supprimer les clés (et leurs blocs `@...` côté EN) : `dashboardPortfolioYieldSectionTitle`, `dashboardPortfolioYieldCashflowLabel`, `dashboardPortfolioYieldCashflowMethodology`. Ne PAS toucher `dashboardPortfolioYieldBeforeTaxSubtitle` (encore utilisée par la carte rendement net).

Run: `flutter gen-l10n`
Expected: succès, pas d'erreur de clé manquante.

- [ ] **Step 7: Analyze + tests verts**

Run: `flutter analyze && flutter test test/widget/portfolio_yield_section_test.dart`
Expected: « No issues found! » et tous les tests du fichier passent.

- [ ] **Step 8: Commit**

```bash
git add lib/features/dashboard/presentation/widgets/portfolio_yield_section.dart test/widget/portfolio_yield_section_test.dart lib/l10n/app_fr.arb lib/l10n/app_en.arb
git commit -m "refactor(dashboard): retire la carte et l'agrégat cash-flow de PortfolioYield (dédup)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: ActionItemsPanel — ligne passive « documents en attente »

Ajoute un paramètre `docsPendingCount` et une ligne passive (non cliquable) en bas du panneau, visible seulement si `> 0`.

**Files:**
- Modify: `lib/features/dashboard/presentation/widgets/action_items_panel.dart`
- Modify: `lib/features/dashboard/presentation/dashboard_page.dart:211` (call-site)
- Modify: `test/widget/action_items_panel_test.dart`
- Modify: `lib/l10n/app_fr.arb`, `lib/l10n/app_en.arb`

**Interfaces:**
- Consumes: `dashboardActionItemsProvider` (inchangé), `LoyersMoisKpi`.
- Produces: `ActionItemsPanel({required LoyersMoisKpi loyers, required int docsPendingCount})`. Ligne passive sous la clé `Key('action_docs_pending')`. Nouvelle clé i18n `dashboardActionDocsPending(count)`.

- [ ] **Step 1: Écrire les tests (ligne docs visible/masquée, non cliquable)**

Dans `test/widget/action_items_panel_test.dart`, modifier le builder `_router()` pour accepter un compte docs, puis ajouter les tests. Remplacer le `GoRoute(path: '/')` builder par un qui prend un paramètre :

```dart
GoRouter _router({int docsPendingCount = 0}) => GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (_, _) => Scaffold(
        body: ActionItemsPanel(
          loyers: const LoyersMoisKpi(encaissedCents: 60000, dueCents: 80000),
          docsPendingCount: docsPendingCount,
        ),
      ),
    ),
    GoRoute(
      path: '/leases',
      builder: (_, s) => Scaffold(body: Text('leases ${s.uri.query}')),
    ),
  ],
);
```

Ajouter ces tests :

```dart
testWidgets('docs en attente > 0 → ligne passive affichée, non cliquable', (
  tester,
) async {
  final far = DateTime.now().add(const Duration(days: 300));
  await tester.pumpWidget(
    _wrap([_item(id: 'C', endDate: far)], router: _router(docsPendingCount: 3)),
  );
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('action_docs_pending')), findsOneWidget);
  expect(find.textContaining('3 documents en attente'), findsOneWidget);
  // Pas un bouton / ListTile cliquable : aucun InkWell sous la ligne.
  expect(
    find.descendant(
      of: find.byKey(const Key('action_docs_pending')),
      matching: find.byType(InkWell),
    ),
    findsNothing,
  );
});

testWidgets('docs en attente == 0 → aucune ligne docs', (tester) async {
  final far = DateTime.now().add(const Duration(days: 300));
  await tester.pumpWidget(
    _wrap([_item(id: 'C', endDate: far)], router: _router(docsPendingCount: 0)),
  );
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('action_docs_pending')), findsNothing);
});
```

- [ ] **Step 2: Lancer les tests — échec attendu**

Run: `flutter test test/widget/action_items_panel_test.dart`
Expected: échec de compilation (`docsPendingCount` n'existe pas encore sur `ActionItemsPanel`).

- [ ] **Step 3: Ajouter le paramètre et la ligne passive**

Dans `action_items_panel.dart` :
- Constructeur : `const ActionItemsPanel({super.key, required this.loyers, required this.docsPendingCount});`
- Champ : `final int docsPendingCount;` (sous `final LoyersMoisKpi loyers;`).
- À la fin du `Column` du `Container` (après le bloc `if (items != null) ... else if ... else ...`), ajouter :

```dart
          if (docsPendingCount > 0) ...[
            SizedBox(height: spacing.lg),
            Row(
              key: const Key('action_docs_pending'),
              children: [
                Icon(
                  Icons.folder_outlined,
                  size: 18,
                  color: (theme.extension<AppColors>() ?? AppColors.light)
                      .info
                      .solid,
                ),
                SizedBox(width: spacing.xs),
                Expanded(
                  child: Text(
                    l10n.dashboardActionDocsPending(docsPendingCount),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ],
```

- [ ] **Step 4: Ajouter la clé i18n (FR + EN) + regénérer**

Dans `app_fr.arb` :
```json
  "dashboardActionDocsPending": "{count, plural, =1{1 document en attente} other{{count} documents en attente}}",
```
Dans `app_en.arb` :
```json
  "dashboardActionDocsPending": "{count, plural, =1{1 pending document} other{{count} pending documents}}",
  "@dashboardActionDocsPending": {
    "description": "Passive line in the dashboard action panel showing how many documents are pending. {count} is the number of pending documents.",
    "placeholders": { "count": { "type": "int" } }
  },
```

Run: `flutter gen-l10n`
Expected: succès ; `context.l10n.dashboardActionDocsPending(int)` est généré.

- [ ] **Step 5: Mettre à jour le call-site**

Dans `dashboard_page.dart`, la ligne `ActionItemsPanel(loyers: snapshot.loyers),` devient :
```dart
        ActionItemsPanel(
          loyers: snapshot.loyers,
          docsPendingCount: snapshot.docs.count,
        ),
```

- [ ] **Step 6: Analyze + tests verts**

Run: `flutter analyze && flutter test test/widget/action_items_panel_test.dart`
Expected: « No issues found! » et tous les tests passent.

- [ ] **Step 7: Commit**

```bash
git add lib/features/dashboard/presentation/widgets/action_items_panel.dart lib/features/dashboard/presentation/dashboard_page.dart test/widget/action_items_panel_test.dart lib/l10n/app_fr.arb lib/l10n/app_en.arb
git commit -m "feat(dashboard): ligne passive « documents en attente » dans le panneau À traiter

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: KpiGrid — retirer la tuile docs (→ 2 tuiles)

`KpiGrid` ne garde qu'occupation + patrimoine. Docs disparaît (désormais porté par la ligne passive de T2). Le constructeur perd `snapshot` : après retrait de docs, `KpiGrid` ne lit plus que `dashboardPortfolioKpisProvider`.

**Files:**
- Modify: `lib/features/dashboard/presentation/widgets/kpi_grid.dart`
- Modify: `lib/features/dashboard/presentation/dashboard_page.dart:207` (call-site)
- Modify: `test/widget/kpi_grid_test.dart`
- Modify: `test/widget/dashboard_page_test.dart` (tests docs obsolètes)
- Modify: `lib/l10n/app_fr.arb`, `lib/l10n/app_en.arb`

**Interfaces:**
- Consumes: `dashboardPortfolioKpisProvider` (inchangé).
- Produces: `KpiGrid({super.key})` (plus de paramètre). N'affiche que `Key('kpi_occupation')` et `Key('kpi_patrimoine')`.

- [ ] **Step 1: Mettre à jour `kpi_grid_test.dart`**

Dans `test/widget/kpi_grid_test.dart` :
- Supprimer le helper `DashboardSnapshot _snapshot() => ...` et les imports devenus inutiles (`dashboard_kpi.dart`, `dashboard_snapshot.dart`).
- Dans `_wrap`, le builder route `/` : remplacer `KpiGrid(snapshot: _snapshot())` par `const KpiGrid()`.
- Dans le 1er test, remplacer le titre et les attentes : retirer `expect(find.byKey(const Key('kpi_docs')), findsOneWidget);`, et ajouter `expect(find.byKey(const Key('kpi_docs')), findsNothing);`. Conserver `kpi_occupation`/`kpi_patrimoine` `findsOneWidget` et les `find.textContaining('50')` / `('236')`.

- [ ] **Step 2: Lancer — échec attendu**

Run: `flutter test test/widget/kpi_grid_test.dart`
Expected: échec de compilation (`KpiGrid` exige encore `snapshot`).

- [ ] **Step 3: Retirer docs de `KpiGrid` et le paramètre `snapshot`**

Dans `kpi_grid.dart` :
- Constructeur : `const KpiGrid({super.key});` ; supprimer `final DashboardSnapshot snapshot;` et l'import `../../domain/dashboard_snapshot.dart`.
- Dans `_buildCards` : supprimer `final docs = snapshot.docs;`, la ligne `final docsColor = ...`, et la `KpiCard(key: const Key('kpi_docs'), ...)` (dernier élément de la liste retournée).
- Ajuster la grille pour 2 tuiles dans `build` :
```dart
        final crossAxisCount = width > 600 ? 2 : 1;
        const ratio = 1.6;
```
(supprimer la branche `width > 900 ? 3`).
- Mettre à jour le commentaire de tête de classe : « Grille responsive de 2 KPI : occupation, patrimoine. »

- [ ] **Step 4: Mettre à jour le call-site**

Dans `dashboard_page.dart`, `KpiGrid(snapshot: snapshot)` devient `const KpiGrid()`.

- [ ] **Step 5: Mettre à jour `dashboard_page_test.dart` (tests docs obsolètes)**

- Test « affiche les 3 KPI patrimoniaux (occupation, patrimoine, docs) » : renommer en « affiche 2 KPI patrimoniaux (occupation, patrimoine) » ; remplacer `expect(find.byKey(const Key('kpi_docs')), findsOneWidget);` par `expect(find.byKey(const Key('kpi_docs')), findsNothing);`. Conserver les autres `findsNothing` (loyers/retards/renouvellements).
- Supprimer **entièrement** le test « « Documents en attente » n'est PAS cliquable » (groupe « drill-down KPI cliquables ») qui tape `Key('kpi_docs')` : la non-cliquabilité de docs est désormais couverte par `action_items_panel_test.dart` (T2). Si le groupe devient vide, le supprimer aussi.

- [ ] **Step 6: Retirer les 2 clés i18n docs orphelines + regénérer**

Dans `app_fr.arb` ET `app_en.arb`, supprimer `dashboardKpiDocsPendingLabel` et `dashboardKpiDocsPendingSubtitle` (+ blocs `@...` côté EN).

Run: `flutter gen-l10n`
Expected: succès.

- [ ] **Step 7: Analyze + tests verts**

Run: `flutter analyze && flutter test test/widget/kpi_grid_test.dart test/widget/dashboard_page_test.dart`
Expected: « No issues found! » et tous les tests passent.

- [ ] **Step 8: Commit**

```bash
git add lib/features/dashboard/presentation/widgets/kpi_grid.dart lib/features/dashboard/presentation/dashboard_page.dart test/widget/kpi_grid_test.dart test/widget/dashboard_page_test.dart lib/l10n/app_fr.arb lib/l10n/app_en.arb
git commit -m "refactor(dashboard): KpiGrid à 2 tuiles (docs déplacé en ligne passive)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: dashboard_page — 3 zones + réordonnancement

Réorganise `_DataView` en trois zones nommées, chacune introduite par un `SectionHeader`. Ordre : À traiter → Mon patrimoine → Analyse. Supprime l'en-tête unique « Vue d'ensemble ».

**Files:**
- Modify: `lib/features/dashboard/presentation/dashboard_page.dart`
- Modify: `test/widget/dashboard_page_test.dart`
- Modify: `lib/l10n/app_fr.arb`, `lib/l10n/app_en.arb`

**Interfaces:**
- Consumes: `ActionItemsPanel({loyers, docsPendingCount})` (T2), `KpiGrid()` (T3), `PortfolioYieldSection()` (T1), `CollapsibleCashflowSection()`, `RecentActivitySection({items})` (inchangés), `SectionHeader({title})`.
- Produces: Accueil à 3 zones. Nouvelles clés i18n `dashboardZoneTodoTitle`, `dashboardZonePatrimonyTitle`, `dashboardZoneAnalysisTitle`.

- [ ] **Step 1: Écrire le test (3 en-têtes présents + ordre)**

Dans `test/widget/dashboard_page_test.dart`, dans le groupe « état data normal », ajouter :

```dart
testWidgets('3 zones nommées, dans l\'ordre À traiter → patrimoine → analyse', (
  tester,
) async {
  await tester.pumpWidget(_wrap());
  await tester.pumpAndSettle();

  final todo = find.text('À traiter');
  final patrimony = find.text('Mon patrimoine');
  final analysis = find.text('Analyse');
  expect(todo, findsOneWidget);
  expect(patrimony, findsOneWidget);
  expect(analysis, findsOneWidget);

  // Ordre vertical : À traiter au-dessus de Mon patrimoine, au-dessus d'Analyse.
  expect(
    tester.getTopLeft(todo).dy,
    lessThan(tester.getTopLeft(patrimony).dy),
  );
  expect(
    tester.getTopLeft(patrimony).dy,
    lessThan(tester.getTopLeft(analysis).dy),
  );
});
```

- [ ] **Step 2: Lancer — échec attendu**

Run: `flutter test test/widget/dashboard_page_test.dart -n "3 zones"`
Expected: échec (les textes de zone n'existent pas encore).

- [ ] **Step 3: Ajouter les 3 clés i18n + regénérer**

Dans `app_fr.arb` :
```json
  "dashboardZoneTodoTitle": "À traiter",
  "dashboardZonePatrimonyTitle": "Mon patrimoine",
  "dashboardZoneAnalysisTitle": "Analyse",
```
Dans `app_en.arb` :
```json
  "dashboardZoneTodoTitle": "To do",
  "@dashboardZoneTodoTitle": { "description": "Dashboard Home zone header for actionable items (late rents, ending leases, pending documents)." },
  "dashboardZonePatrimonyTitle": "My portfolio",
  "@dashboardZonePatrimonyTitle": { "description": "Dashboard Home zone header for portfolio state (occupancy, portfolio value, yield)." },
  "dashboardZoneAnalysisTitle": "Analysis",
  "@dashboardZoneAnalysisTitle": { "description": "Dashboard Home zone header for analysis (cash-flow chart, recent activity)." },
```
Supprimer la clé orpheline `dashboardOverviewSectionTitle` (FR + EN + bloc `@`).

Run: `flutter gen-l10n`
Expected: succès.

- [ ] **Step 4: Réécrire `_DataView`**

Remplacer le `return Column(...)` de `_DataView.build` (après le court-circuit onboarding) par :

```dart
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ZONE 1 — À traiter
        SectionHeader(title: context.l10n.dashboardZoneTodoTitle),
        SizedBox(height: spacing.md),
        ActionItemsPanel(
          loyers: snapshot.loyers,
          docsPendingCount: snapshot.docs.count,
        ),
        SizedBox(height: spacing.xl),
        // ZONE 2 — Mon patrimoine
        SectionHeader(title: context.l10n.dashboardZonePatrimonyTitle),
        SizedBox(height: spacing.md),
        const KpiGrid(),
        SizedBox(height: spacing.xl),
        const PortfolioYieldSection(),
        SizedBox(height: spacing.xl),
        // ZONE 3 — Analyse
        SectionHeader(title: context.l10n.dashboardZoneAnalysisTitle),
        SizedBox(height: spacing.md),
        const CollapsibleCashflowSection(),
        SizedBox(height: spacing.xl),
        RecentActivitySection(items: snapshot.activity),
      ],
    );
```

Mettre à jour le commentaire de composition de la doc de tête de `DashboardPage` (lignes « Sinon : [SectionHeader] « Vue d'ensemble » + ... ») pour refléter les 3 zones.

- [ ] **Step 5: Analyze + tests verts**

Run: `flutter analyze && flutter test test/widget/dashboard_page_test.dart`
Expected: « No issues found! » et tous les tests passent (dont le nouveau test d'ordre).

- [ ] **Step 6: Commit**

```bash
git add lib/features/dashboard/presentation/dashboard_page.dart test/widget/dashboard_page_test.dart lib/l10n/app_fr.arb lib/l10n/app_en.arb
git commit -m "feat(dashboard): Accueil en 3 zones (À traiter / Mon patrimoine / Analyse)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Vérification finale (après les 4 tâches)

- Run: `flutter analyze` → « No issues found! »
- Run: `flutter test` → suite complète verte.
- Contrôle manuel (optionnel, preview) : l'Accueil montre 3 zones dans l'ordre ; docs en ligne passive sous « À traiter » quand count > 0 ; une seule représentation cash-flow (le graphe sous « Analyse »).
- Mettre à jour `docs/state/routes/dashboard.md` si la composition y est décrite, et ajouter l'entrée `docs/state/CHANGELOG.md` (fait hors plan, à la finition de branche).
