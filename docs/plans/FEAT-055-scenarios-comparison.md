# Plan — FEAT-055 Comparaison de scénarios de simulation (Pro)

> **Sources** : spec [`docs/backlog/053-scenarios-comparison.md`](../backlog/053-scenarios-comparison.md) ·
> pattern gate [`FEAT-044b`](../state/FEATURES.md) via `charge_regularization_section.dart` ·
> stack simulateur `FEAT-018`.
>
> **Statut** : plan V1 — décisions produit validées 2026-07-23 (§ ci-dessous), prêt pour `flutter-dev`.

## 0. Décisions produit validées 2026-07-23

Trois décisions posées par le product-owner en réponse aux zones grises §11. **Elles priment sur les valeurs par défaut ci-dessous en cas d'écart.**

| # | Question | Décision | Impact |
|---|---|---|---|
| P1 | Min. sélection pour lancer une comparaison | **2** (le nombre est laissé à l'orchestrateur ; free étant gaté quoi qu'il arrive, garder 2 = flexibilité max pour le Pro qui n'aurait sauvegardé que 2 scénarios) | §11 D1/D2 : min 2, max 3 confirmés |
| P2 | Deep-link `/simulator/compare?ids=…` pour un compte non-paid | **Écran verrouillé + upsell** (pattern miroir de `chargeRegularizationProOnly` FEAT-044b) — pas de redirect router | §5 : le router ne redirige jamais, le gate est rendu dans la page |
| P3 | Formule KPI « effort d'épargne » | **`max(0, -cashflow_mensuel) × 12` en €/an** | §4 KPI #6, §11 D9 : effort annualisé, cohérent avec le cash-flow mensuel affiché en KPI voisin |

## 1. Résumé exécutif

FEAT-055 est une V1 exclusivement client, greffée sur l'existant :

- Bascule un **mode sélection** dans `SavedScenariosRow` (rail scénarios sauvegardés). Bouton « Comparer » qui n'apparaît que si le landlord a ≥ 2 scénarios sauvegardés (AC #3).
- Route push `/simulator/compare?ids=a,b,c` (max 3) rendue par un nouvel écran plein-page hors shell, sous la même branche que `/simulator/:id`.
- KPIs (6, V1) tirés du `scenarioJson` déjà persisté sur `investment_scenarios/{id}` — aucune Cloud Function, aucun index, aucun nouveau champ Firestore, aucune règle à toucher.
- Gate Pro **client uniquement**, miroir strict de `chargeRegularizationProOnly` (FEAT-044b) : free voit le bouton grisé + upsell vers `/pro`.
- Responsive : desktop = tableau à colonnes fixes ; mobile = accordéons par KPI.

Effort estimé (S, cohérent avec la spec) : ~1,5 jour dev + 0,5 j QA/review.

## 2. Arborescence des fichiers touchés

### Créés (`lib/features/simulator/`)

| Chemin | Rôle |
|---|---|
| `presentation/scenario_comparison_page.dart` | Écran `/simulator/compare` — lit ids depuis la query, charge la liste, gate Pro, rend `ScenarioComparisonTable` (desktop) ou `ScenarioComparisonAccordion` (mobile) via LayoutBuilder. |
| `presentation/widgets/scenario_comparison_table.dart` | Tableau à colonnes fixes (une par scénario). Header = nom scénario ; 6 lignes = KPIs (label + valeurs formatées + delta % pour les colonnes ≥ 2). |
| `presentation/widgets/scenario_comparison_accordion.dart` | Version mobile — un `ExpansionTile` par KPI, empilant les valeurs par scénario. |
| `presentation/widgets/scenario_comparison_cell.dart` | Cellule atomique (valeur + éventuel delta% coloré) — réutilisée par les deux vues, garantit un format cohérent. |
| `presentation/widgets/compare_scenarios_toggle.dart` | Bouton d'entrée « Comparer » exposé par `SavedScenariosRow`. Sait afficher : action activée (paid + ≥ 2 scénarios), verrouillée grisée (free/anon + upsell), masquée (< 2 scénarios). |
| `domain/scenario_comparison_view_model.dart` | View-model + fonctions pures : `ComparisonKpi`, `ComparisonRow`, `buildComparisonRows(List<InvestmentScenario>) → List<ComparisonRow>`, `computeSignedDeltaPercent(reference, other)`. Zéro dépendance UI, zéro Firestore — testable unitairement. |

### Modifiés

| Chemin | Nature du changement |
|---|---|
| `lib/features/simulator/presentation/widgets/saved_scenarios_row.dart` | Passe stateful (mode sélection : `Set<String> _selectedIds`). Insère `CompareScenariosToggle` à côté du titre « Mes scénarios ». Ajoute une case à cocher visuelle + décoration ring sur `_ScenarioChip` quand `selectionMode` est actif. En mode sélection, le tap sur la carte **toggle la sélection** au lieu de naviguer, et l'icône `delete_outline` est masquée (évite le geste destructeur accidentel). Un « Comparer les N » (validation) apparaît quand `_selectedIds.length ∈ [2,3]` ; un « Annuler » sort du mode. `context.push('/simulator/compare?ids=…')`. |
| `lib/core/router/app_router.dart` | Nouvelle `GoRoute` `/simulator/compare` **sœur** de `/simulator/:id`, hors shell, transition standard. Extrait `ids` depuis `state.uri.queryParameters['ids']`, split `,`, trim, unique, cap à 3. Passe `List<String> ids` au constructeur de `ScenarioComparisonPage`. |
| `lib/l10n/app_fr.arb` + `lib/l10n/app_en.arb` | Ajout des clés listées §8. Bloc groupé sous un séparateur `// FEAT-055 — Comparaison scénarios`. |
| `lib/l10n/app_localizations*.dart` | Régénéré par `flutter gen-l10n` — pas d'édition manuelle. |

### Non touchés (garde-fous)

- `investment_scenario_repository.dart` (aucune méthode ajoutée : on filtre in-memory depuis `investmentScenariosListProvider`).
- `investment_scenario.dart` (freezed) et son schéma Firestore.
- `firestore.rules`, `firestore.indexes.json`.
- `functions/` (zéro nouvelle Cloud Function).
- `scenario_results.dart` (les 6 KPIs V1 sont dérivés localement dans le view-model, sans muter le contrat de `ScenarioResults`).

## 3. Modèle de données côté widget

Pas de nouveau modèle persisté. Deux petits records/classes freezed en `domain/scenario_comparison_view_model.dart` :

```dart
enum ComparisonKpi {
  grossYield,          // % (double)
  netYield,            // % (double)
  monthlyCashflow,     // centimes (int, signé)
  totalLoanCost,       // centimes (int)
  downPaymentRequired, // centimes (int)
  savingsEffort,       // centimes (int, ≥ 0) — voir §4
}

/// Une valeur atomique pour un scénario donné.
/// [rawNumber] est la grandeur brute utilisée pour le calcul du delta —
/// double normalisé (% pour rendements, euros pour montants). [display] est
/// le libellé formaté prêt à peindre (« 5,20 % », « 1 234,56 € », etc.).
class ComparisonValue {
  final double rawNumber;
  final String display;
  const ComparisonValue({required this.rawNumber, required this.display});
}

/// Une ligne = un KPI, avec la valeur pour chaque scénario (dans l'ordre
/// d'entrée). Le delta % s'établit toujours vs. `values[0]` — voir §4.
class ComparisonRow {
  final ComparisonKpi kpi;
  final String label;             // via l10n (chargé côté widget, pas ici)
  final List<ComparisonValue> values;
  const ComparisonRow({required this.kpi, required this.label,
                       required this.values});
}
```

Fonction pure de construction :

```dart
List<ComparisonRow> buildComparisonRows(
  List<InvestmentScenario> ordered,       // 2-3 scénarios, ordre = ids query
  AppLocalizations l10n,
);
```

Sous le capot : appelle `computeScenarioResults(s)` (existant) pour chaque scénario, complète avec les champs bruts `downPaymentCents`, calcule `savingsEffort` (formule §4), et produit les `ComparisonValue` en formatant via `MoneyFormat.formatEurosFromCents` / `%` (`toStringAsFixed(2).replaceAll('.', ',')`), déjà utilisés dans `ScenarioResultsCard`.

Helper delta :

```dart
/// Retourne le signe et l'amplitude du delta relatif de [other] vs.
/// [reference]. `null` si [reference] == 0 (division impossible) ou si les
/// deux valeurs sont identiques (delta = 0 est traité comme "aucune signal").
/// La signalisation ± 5 % vit dans le widget, pas dans cette fonction pure.
double? computeSignedDeltaPercent(double reference, double other);
```

## 4. Contrat KPI (V1)

Toutes les valeurs sont dérivées **à partir de `InvestmentScenario`** (champs snake_case Firestore → camelCase freezed) et de `computeScenarioResults(s)` — aucun round-trip serveur.

| # | KPI (i18n) | Source | Type | Formatage | Sens « positif » |
|---|---|---|---|---|---|
| 1 | Rendement brut | `computeScenarioResults(s).yieldGrossPercent` | `double %` | `X,YZ %` | ↑ = mieux |
| 2 | Rendement net | `computeScenarioResults(s).yieldNetPercent` | `double %` | `X,YZ %` | ↑ = mieux |
| 3 | Cash-flow mensuel | `computeScenarioResults(s).monthlyCashflowBeforeTaxCents` | `int cents (signé)` | `MoneyFormat.formatEurosFromCents` | ↑ = mieux |
| 4 | Coût total du crédit | `computeScenarioResults(s).totalLoanCostCents` | `int cents` | `MoneyFormat.formatEurosFromCents` | ↓ = mieux |
| 5 | Apport requis | `s.downPaymentCents` (champ brut du scénario) | `int cents` | `MoneyFormat.formatEurosFromCents` | ↓ = mieux |
| 6 | Effort d'épargne | `max(0, -cashflowMensuel) × 12` (voir ci-dessous) | `int cents/an` | `MoneyFormat.formatEurosFromCents` + « /an » (`simulatorCompareEffortPerYearSuffix`) | ↓ = mieux |

**Formule effort d'épargne**. Le cash-flow est un montant signé mensuel : positif = revenu résiduel, négatif = à combler par l'épargne personnelle. L'effort d'épargne annuel = `max(0, -cashflow) × 12`. Un scénario auto-financé affiche donc « 0 € /an ».

### Calcul du delta %

- **Colonne 0 = référence**. Toujours affichée sans delta (indication implicite « base »).
- Colonnes ≥ 1 : `delta% = ((value - values[0]) / values[0]) × 100`. Si `values[0] == 0` → pas de delta affiché (division impossible), l'écart est indiqué en valeur absolue seule.
- Formatage : signé avec un chiffre après la virgule : `« +8,3 % »`, `« −4,1 %  »`. Utiliser un « + » explicite pour les positifs (`NumberFormat.decimalPattern('fr_FR')` + concaténation manuelle du signe — pas de `signPattern` ISO qui alternerait `+` et `-`).

### Seuils de signal couleur (± 5 %)

Un widget `ComparisonCell` mappe `|delta|` sur un token couleur du `ColorScheme` courant. Pour rester conforme au thème Baillan et fonctionner dark/light, **on réutilise strictement** les codes déjà employés dans `ScenarioResultsCard._yieldColor / _cashflowColor` — pas de nouveau token :

- `|delta| < 5 %` → couleur neutre `theme.colorScheme.onSurfaceVariant` (pas de signal).
- `|delta| ≥ 5 %` **et** sens favorable au scénario → `Colors.green.shade700` (déjà utilisé §KPI results).
- `|delta| ≥ 5 %` **et** sens défavorable → `theme.colorScheme.error` (déjà utilisé).
- La direction favorable est portée par un booléen `higherIsBetter` sur `ComparisonKpi`. Cf. la 5ᵉ colonne du tableau §4 (« Sens positif »).

> Ce mapping vit dans `scenario_comparison_cell.dart` — pas dans le view-model. Le view-model expose la donnée numérique brute, le widget se charge du rendu (permet de tester les rows sans MaterialApp).

## 5. Route + navigation

### Déclaration router

```dart
GoRoute(
  path: '/simulator/compare',
  pageBuilder: (context, state) {
    final raw = state.uri.queryParameters['ids'] ?? '';
    final ids = raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet()             // unique — dedup silencieux
        .take(3)             // cap à 3 (défensif, cf. spec)
        .toList();
    return appPage(
      key: state.pageKey,
      child: ScenarioComparisonPage(ids: ids),
      transition: AppTransition.standard,
    );
  },
),
```

Placement : **sœur** de `/simulator/:id` sous la même branche shell-out (ligne ~275 de `app_router.dart`). Ordre déclaratif : `/simulator/compare` **avant** `/simulator/:id`, sinon go_router matcherait `:id = "compare"` (piège classique).

### Garde d'accès

- La garde 3-états existante (`isAnonAccessible` couvre `startsWith('/simulator/')`) laisse passer anonymes + comptes complets — inchangé. Pas de nouveau segment public à ajouter à `publicRoutes`.
- **Pas** de redirection Pro dans le router (spec : gate 100 % client-side). Le tier check vit dans la page.

### Comportement runtime

`ScenarioComparisonPage.build` :

1. Lit `landlordTierProvider`. Fallback `anonymous`. Si tier ≠ `paid` → rend `_ProGatedComparisonBody` (miroir de §7).
2. Sinon lit `investmentScenariosListProvider` (déjà chargé la plupart du temps depuis `/simulator`) puis **filtre** la liste par `widget.ids`, dans l'ordre des ids. Un id manquant dans la liste est simplement omis — pas de fetch individuel (évite d'ajouter un `getById` en cascade).
3. Si après filtrage `filtered.length < 2` → écran vide `_EmptyComparisonBody` avec CTA retour `/simulator`. Couvre AC #5 (soft-delete pendant la session : la liste stream se met à jour, filtered rétrécit, l'écran bascule sur le vide sans crash).
4. Sinon calcule `buildComparisonRows(filtered, l10n)` et rend le tableau/accordéon.

### AppBar

Réutilise `AppAppBar` (comme `SimulatorPage`), title = `simulatorCompareTitle`, `fallbackRoute: '/simulator'`. Pas d'action supplémentaire en V1 (pas d'export, pas de partage).

## 6. UI/UX

### Rail — mode sélection

- État en local dans `SavedScenariosRow` (`StatefulWidget` désormais, ou `ConsumerStatefulWidget` puisqu'il utilise `ref.watch`). Deux champs : `bool _selectionMode`, `Set<String> _selectedIds`.
- Header du rail (`Row`) :
  - À gauche : titre `simulatorSavedScenariosTitle`.
  - À droite (nouveau) : `CompareScenariosToggle` — visibilité conditionnée par `scenarios.length ≥ 2` (AC #3).
- Bouton toggle :
  - Hors mode sélection : `TextButton.icon(icon: compare_arrows, label: simulatorCompareButton)`.
  - En mode sélection : deux boutons — `TextButton('simulatorCompareCancel')` et `FilledButton('simulatorCompareValidate(count)')`, ce dernier disabled tant que `_selectedIds.length < 2`.
- `_ScenarioChip` :
  - Reçoit deux nouveaux paramètres `bool selectionMode`, `bool selected`, `VoidCallback onToggle`.
  - En mode sélection : le tap déclenche `onToggle` au lieu de `context.go('/simulator/${id}')`. Cache l'`IconButton(delete)` et affiche à sa place un `Icon(Icons.check_circle / Icons.radio_button_unchecked)` selon `selected`. La bordure `EntityCard` gagne un `borderColor: primary` quand `selected`.
- Bouton « Comparer les N » → `context.push('/simulator/compare?ids=${_selectedIds.join(",")}')` (préserve l'ordre de sélection via `LinkedHashSet`, pas `HashSet`). Utiliser `push` plutôt que `go` pour permettre le back naturel vers le simulateur.

**Non-régression**. Les tests widget existants du rail (via `simulator_page_test.dart`) ne cliquent jamais sur `CompareScenariosToggle`. Ils continueront de passer si :
- La branche « pas de mode sélection » préserve le comportement historique : tap = navigation, `delete_scenario_${id}` visible.
- Les nouvelles keys (`compare_toggle_button`, `chip_select_${id}`, etc.) n'entrent pas en collision.

### Écran comparaison — desktop (≥ 720 px)

- `LayoutBuilder`. `constraints.maxWidth ≥ 720` → `ScenarioComparisonTable`.
- `SingleChildScrollView(horizontal)` autour d'un `Table` (Flutter Material `Table` widget) — un scroll horizontal si N=3 débordait sur petit desktop. `columnWidths` : première colonne `IntrinsicColumnWidth` (labels), scénarios `FixedColumnWidth(220)`.
- Ligne d'en-tête : nom du scénario (bold, ellipsis 1 ligne). Colonne 0 marquée par un chip discret `simulatorCompareReferenceChip` (« Référence »).
- Six lignes suivantes = KPIs. Chaque cellule = `ScenarioComparisonCell(value: ..., delta: ..., higherIsBetter: ...)`.
- Ligne finale = disclaimer réutilisé (`simulatorResultsTaxDisclaimer`) — cohérent avec `ScenarioResultsCard`.

### Écran comparaison — mobile (< 720 px)

- Une `Column` de 6 `ExpansionTile` (un par KPI). Titre = label du KPI + valeur de la colonne 0 en gros (aperçu rapide sans dérouler).
- Enfants : liste des scénarios ≥ 1 avec leur valeur + delta % coloré. Layout `Row` (nom scénario, valeur, delta).
- Tous fermés par défaut (« place à l'écran », spec). Un CTA « Tout déplier » optionnel — **hors V1** (à trancher §11).

### Bouton retour et empty states

- `AppAppBar(fallbackRoute: '/simulator')` — le back ramène toujours au simulateur, jamais dans un état comparaison intermédiaire.
- Empty state « ids invalides / trop peu de scénarios sélectionnés » : `EmptyState` (widget maison si existant, sinon `Column` centrée avec icône + texte + `FilledButton('simulatorCompareBackToRail')`).

## 7. Gate Pro — pattern FEAT-044b

Reproduction strictement à l'identique du miroir `charge_regularization_section.dart` (lignes 63-115) :

1. **Bouton d'entrée** (`CompareScenariosToggle`, dans le rail) :
   ```dart
   final isPaid = ref.watch(landlordTierProvider).valueOrNull?.tier
       == SubscriptionTier.paid;
   ```
   - `isPaid` **et** ≥ 2 scénarios → bouton actif (voir §6).
   - Non paid **et** ≥ 2 scénarios → `Row` verrouillé : `Icon(Icons.lock_outline)` + texte `simulatorCompareProOnly` + tap → `context.go('/pro')`. Wrapped dans un `InkWell` pour rester tappable (pattern « bouton grisé mais cliquable » cohérent avec l'AC #2 qui exige « visible mais désactivé »).
   - < 2 scénarios → toggle masqué (AC #3, précédence sur le gate Pro : rien à comparer, pas d'upsell trompeur).
2. **Écran `/simulator/compare`** : deuxième niveau de gate côté page (deep-link direct par URL ou session dégradée). Si `landlordTierProvider` renvoie ≠ `paid`, la page rend `_ProGatedComparisonBody` : titre « Comparaison — Plan Pro », icône lock, message `simulatorCompareProOnly`, CTA `FilledButton('proUpgradeButton')` → `context.go('/pro')`. Aucun calcul ni chargement de scénarios ne s'exécute avant d'avoir vu `paid`.
3. **Fail-closed pendant le chargement du tier**. Comme dans FEAT-044b (`valueOrNull?.tier == paid`), une valeur `loading/null` = pas paid = état verrouillé. On préfère un flash « verrouillé » à un flash « déverrouillé retiré ».

Aucun garde-fou serveur ajouté : la lecture des scénarios est déjà couverte par les règles Firestore existantes (`isOwner(landlordId)`), qui suffisent — les calculs sont purs, sans donnée sensible.

## 8. i18n — clés à ajouter (FR + EN)

Localisation groupée dans un bloc `// FEAT-055 — Comparaison scénarios` à la suite des clés `simulatorTierChipPaid` dans les deux ARB.

| Clé | FR | EN | Description |
|---|---|---|---|
| `simulatorCompareButton` | `Comparer` | `Compare` | Bouton d'entrée dans le rail (mode normal). Icône compare_arrows à côté. |
| `simulatorCompareCancel` | `Annuler` | `Cancel` | Sortie du mode sélection. |
| `simulatorCompareValidate` | `Comparer les {count, plural, =2{2 scénarios} =3{3 scénarios}}` | `Compare {count, plural, =2{the 2 scenarios} =3{the 3 scenarios}}` | Bouton de validation en mode sélection. ICU plural. |
| `simulatorCompareProOnly` | `La comparaison de scénarios est réservée au Plan Pro.` | `Scenario comparison is reserved for the Pro plan.` | Message état verrouillé (miroir de `chargeRegularizationProOnly`). |
| `simulatorCompareTitle` | `Comparer les scénarios` | `Compare scenarios` | Titre AppBar de `/simulator/compare`. |
| `simulatorCompareReferenceChip` | `Référence` | `Reference` | Chip « base de comparaison » sur la colonne 0. |
| `simulatorCompareBackToRail` | `Retour aux scénarios` | `Back to scenarios` | CTA de l'empty state, retour à `/simulator`. |
| `simulatorCompareEmptyTooFew` | `Sélectionnez 2 ou 3 scénarios pour lancer une comparaison.` | `Select 2 or 3 scenarios to start a comparison.` | Empty state quand ids < 2 après filtrage. |
| `simulatorCompareKpiDownPaymentLabel` | `Apport requis` | `Required down payment` | Ligne KPI 5. |
| `simulatorCompareKpiSavingsEffortLabel` | `Effort d'épargne` | `Savings effort` | Ligne KPI 6. |
| `simulatorCompareEffortPerYearSuffix` | `/an` | `/year` | Suffixe unité pour l'effort d'épargne. |
| `simulatorCompareSelectionHint` | `Choisissez 2 ou 3 scénarios à comparer.` | `Pick 2 or 3 scenarios to compare.` | Sous-titre affiché quand `_selectionMode == true` mais `_selectedIds.length < 2`. |

**Réutilisation** : `simulatorKpiGrossYieldLabel`, `simulatorKpiNetYieldLabel`, `simulatorKpiMonthlyCashflowLabel`, `simulatorKpiTotalLoanCostLabel`, `simulatorResultsTaxDisclaimer`, `proUpgradeButton` — pas de redéclaration.

**Contrainte non négociable**. `flutter gen-l10n` doit passer clean après les ajouts (ne pas oublier les blocs `"@key": {"description": "…"}` dans `app_en.arb` — le linter les exige, cf. autres clés).

## 9. Découpage tâches `flutter-dev`

Ordre concret d'implémentation, une PR possible par étape ou un unique commit selon l'appétit :

1. **Domain view-model + tests unitaires**
   Créer `domain/scenario_comparison_view_model.dart` (types, `buildComparisonRows`, `computeSignedDeltaPercent`, formule effort d'épargne). Tests unitaires purs — pas de widget, pas de MaterialApp.
2. **i18n**
   Ajouter les 12 clés FR + EN + blocs `@` dans `app_en.arb`. `flutter gen-l10n` propre.
3. **Widget cellule + tableau + accordéon**
   `ScenarioComparisonCell`, `ScenarioComparisonTable`, `ScenarioComparisonAccordion`. Tests widget sur chaque, isolés du router.
4. **Page + route**
   `ScenarioComparisonPage` + ajout GoRoute dans `app_router.dart` (ORDRE : avant `/simulator/:id`). Empty state, gated body.
5. **Rail selection mode**
   Passe `SavedScenariosRow` en `ConsumerStatefulWidget`, ajoute `CompareScenariosToggle`, adapte `_ScenarioChip` (toggle vs. delete). Vérifier que les tests existants (`simulator_page_test.dart`) passent sans modification.
6. **QA end-to-end mode sélection → compare page**
   Un widget test qui traverse le flow complet (paid, 3 scénarios, tap Comparer, coche 2, tap Valider, page compare visible avec 2 colonnes).

Une bascule feature-flag n'est pas nécessaire : l'entrée est déjà cachée par le gate Pro tant que FEAT-044e n'a pas livré le checkout — cf. dépendance bloquante spec.

## 10. Plan de test (mapping AC → tests)

Tous les tests sont **client** : widget test Flutter, avec `landlordTierProvider.overrideWith(...)` (pattern déjà en place dans `simulator_page_test.dart`, cf. lignes 172-175). Aucun test Firestore rules à ajouter (pas de règles modifiées).

### Unitaires (pas de widget)

`test/unit/scenario_comparison_view_model_test.dart` :

- `buildComparisonRows` : 2 scénarios identiques → 6 rows, chaque row a 2 valeurs égales.
- `buildComparisonRows` : ordre d'entrée préservé — le premier scénario passé reste colonne 0.
- `computeSignedDeltaPercent` : delta positif, négatif, exact 5 %, exact -5 %.
- `computeSignedDeltaPercent` : `reference == 0` → `null`.
- Formule effort d'épargne : cashflow positif → 0 ; cashflow -100 €/mois → 1200 €/an ; cashflow 0 → 0.
- Formatage : rendement `5.2` → `« 5,20 % »` ; delta `+8.3` → chaîne signée `« +8,3 % »`.

### Widget

`test/widget/saved_scenarios_row_test.dart` (nouveau) :

- **AC #3** — 1 scénario en base → `CompareScenariosToggle` `findsNothing`.
- **AC #3** — 2 scénarios, tier free → toggle visible en état verrouillé (icône lock + texte `simulatorCompareProOnly`), tap → nav `/pro`.
- **AC #2** — 2 scénarios, tier anonymous → même chose (mêmes assertions).
- **AC #1 (setup)** — 2 scénarios, tier paid → tap toggle → mode sélection actif, delete icon `findsNothing`, texte `simulatorCompareSelectionHint` visible, `FilledButton` disabled.
- **AC #1 (chemin heureux)** — 3 scénarios, tier paid → coche 2, bouton devient enabled avec libellé « Comparer les 2 scénarios », tap → route `/simulator/compare?ids=x,y`.
- Non-régression : hors mode sélection, tap chip → nav `/simulator/{id}` (assertion identique aux tests existants qui pourraient être répliqués ici).

`test/widget/scenario_comparison_page_test.dart` (nouveau) :

- **AC #1** — tier paid + 2 scénarios en base + route `/simulator/compare?ids=A,B` → les 6 labels de KPIs visibles, 2 colonnes.
- **AC #2** — tier free + route directe → `_ProGatedComparisonBody` visible, KPIs `findsNothing`, tap CTA → nav `/pro`.
- **AC #4** — 2 scénarios paramétrés pour donner un delta `+10 %` et `+2 %` → le premier delta est rendu en `Colors.green.shade700` (favorable, ≥ 5 %), le second en couleur neutre (< 5 %). Assertion sur `Text.style.color`.
- **AC #5** — mount avec 3 ids, override la liste avec seulement 2 scénarios présents → 2 colonnes rendues, pas de crash, pas d'erreur console.
- **AC #5** — mount avec 3 ids, override initial 3 scénarios ; puis `notifier.state = AsyncValue.data([...deux scénarios])` → widget se rafraîchit, 2 colonnes. Si passe à 1 scénario, empty state.
- Layout desktop vs mobile : `tester.view.physicalSize = Size(800, 1000)` → `ScenarioComparisonTable` visible ; `Size(400, 800)` → `ScenarioComparisonAccordion` visible.

### Non-régression tests existants

- `test/widget/simulator_page_test.dart` : aucune assertion existante ne mentionne le bouton « Comparer ». La bascule stateful de `SavedScenariosRow` ne casse rien tant que les tests continuent à trouver `delete_scenario_${id}` **hors** mode sélection (comportement default). Vérifier passage `flutter test test/widget/simulator_page_test.dart` avant de merger.
- `test/unit/scenario_results_test.dart` et `investment_scenario_serialization_test.dart` : intacts (aucune modif du domain existant).
- `test/widget/scenario_limit_modal_test.dart` : intact (le limit modal reste `showScenarioLimitReachedModal`).

## 11. Décisions par défaut retenues

À valider par Daki au moment du dev — sinon prises telles quelles.

| # | Zone grise | Décision par défaut | Justification |
|---|---|---|---|
| D1 | Nombre minimal de scénarios sélectionnables | **2** (validation enabled à partir de 2). La spec dit « 2 à 3 », ce qui inclut 2. | Cohérent avec la user story : « trancher entre plusieurs ». |
| D2 | Nombre maximal | **3 strict**. La 4ᵉ case ne se coche pas (feedback visuel silencieux : impossibilité, pas d'erreur). | Contrainte UI de la spec (« Plus de 3 scénarios simultanément » exclu). |
| D3 | Comportement du tap sur chip en mode sélection | **Toggle sélection**, jamais navigation. Delete icon masqué. | Évite le geste destructeur accidentel + garde une seule action par tap. |
| D4 | Ordre des colonnes | **Ordre de sélection** (LinkedHashSet). Le premier coché = colonne 0 = référence. | Le landlord contrôle explicitement qui est la référence — plus explicite qu'un tri arbitraire. |
| D5 | Seuil couleur signal | **± 5 %**. Neutre en dessous, `green.shade700`/`colorScheme.error` au-dessus selon la direction favorable. | La spec impose ± 5 %. Réutilise les tokens déjà utilisés dans `ScenarioResultsCard` — pas de nouveau design token. |
| D6 | Direction favorable par KPI | Rendement brut/net, cash-flow ↑ = mieux. Coût crédit, apport, effort ↓ = mieux. | Sens économique standard. Encapsulé dans `ComparisonKpi.higherIsBetter`. |
| D7 | Delta sur colonne 0 | **Aucun affichage** (référence). Chip `Référence` sous le nom du scénario. | Évite `0,0 %` inutile. |
| D8 | Division par zéro sur delta | Affichage de la valeur brute seule, pas de delta. Pas d'erreur. | Cas rare (rendement 0 %, apport 0 €). |
| D9 | Formule effort d'épargne | `max(0, -cashflow) × 12` en euros/an. Un scénario au cash-flow positif = 0 €/an. | La V1 se limite au coût annuel « manqué » ; l'accumulation projetée sur 20 ans est V2. |
| D10 | Route push vs. go | `context.push('/simulator/compare?...')` depuis le rail. | Permet un back naturel vers le simulateur — cohérent avec le pattern shell-out (spec dit « sous la même branche »). |
| D11 | Deep-link direct (URL saisie à la main) | Autorisé pour anonyme et free — la page rend l'état verrouillé Pro. **Pas de redirect** dans le router. | Miroir de FEAT-044b : gate produit, pas de sécurité. Cohérent avec le fait que `/simulator/*` reste anon-accessible. |
| D12 | Persistance des ids sélectionnés | Aucune (query string seulement). Fermer la page perd la sélection. | Spec « exclus V1 : persistance de la paire ». |
| D13 | Ids > 3 dans la query | Cap silencieux aux 3 premiers, dedup par set. | Défensif. Un `Snackbar` d'avertissement serait bruit UX inutile. |
| D14 | Ids dupliqués dans la query | Dedup par `Set`. Le 2ᵉ occurrence est ignorée. | Pas de colonne dupliquée qui n'a aucun sens. |
| D15 | Ids invalides / scénarios disparus | Simplement filtrés hors liste, jamais de fetch individuel. Si `< 2` après filtrage → empty state avec CTA retour. | Couvre AC #5 sans complexifier — la liste stream est la source de vérité. |
| D16 | Mobile : accordéons initialement | **Tous fermés**. L'aperçu affiche déjà la valeur de la colonne 0 dans le titre. | « Place à l'écran », spec. |
| D17 | Bouton « Tout déplier » sur mobile | **Hors V1**. À évaluer si retour utilisateur négatif. | Reste minimal. |
| D18 | Nom des scénarios trop long | Ellipsis 1 ligne dans l'en-tête. Tooltip natif au tap long. | Cohérent avec le comportement des `_ScenarioChip` existants. |
| D19 | Export PDF / partage | **Hors V1** (spec exclut). Aucune action dans l'AppBar de la page compare. | — |
| D20 | Analytics / logging | Aucun ajout — les logs `Logger('ScenarioComparisonPage')` en warning uniquement (erreurs de parsing ids). | Pas de tracking prod à ce stade. |

---

## Rappels non-négociables (recap)

- Aucune nouvelle collection Firestore. Aucun champ ajouté à `investment_scenarios`.
- Aucune Cloud Function nouvelle ou modifiée.
- Aucune règle `firestore.rules` touchée.
- Gate 100 % client (`landlordTierProvider` + `SubscriptionTier.paid`), pattern FEAT-044b à l'identique.
- Toutes les 12 clés i18n ajoutées en FR **et** EN, avec bloc `@` en EN.
- Tests widget existants du simulateur (`simulator_page_test.dart`) doivent passer sans modification.
