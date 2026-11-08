# Simulation fiscale LMNP (FEAT-061) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dans le simulateur d'achat, comparer micro-BIC et réel sur 10 ans pour un projet de location meublée longue durée (LMNP), réservé à l'offre Pro.

**Architecture:** Calcul pur en Dart (`lmnp_tax_simulation.dart`) à partir du `InvestmentScenario` et d'une table de règles datée (`lmnp_tax_rules.dart`). Quatre champs ajoutés au scénario (modèle, dépôt, callable `createScenario`). Une carte `LmnpTaxCard` sous les résultats, masquée si le bien n'est pas meublé, verrouillée hors Pro.

**Tech Stack:** Flutter 3.44.6 / Dart, Riverpod 2, freezed + json_serializable (build_runner), gen-l10n (ARB FR/EN), Cloud Functions TypeScript (vitest, eslint).

Spec : [`docs/superpowers/specs/2026-11-06-lmnp-tax-simulation-design.md`](../specs/2026-11-06-lmnp-tax-simulation-design.md).

## Global Constraints

- PATH : `export PATH=/opt/homebrew/bin:$PATH` avant toute commande flutter/dart/npm/gh.
- Montants en **centimes entiers** ; arrondi `(x).round()` à chaque montant calculé ; jamais de `double` stocké.
- Règles 2026 exactes : abattement micro 50 %, minimum 305 € ; plafond micro 83 600 € ; prélèvements sociaux 18,6 % ; bâti 30 ans, travaux 15 ans, mobilier 7 ans ; alerte LMP 23 000 € ; report du déficit 10 ans ; amortissement non déduit reporté sans limite.
- Tranches autorisées : `{0, 11, 30, 41, 45}`, défaut 30. Part du terrain : 0–50, défaut 15. Mobilier ≥ 0.
- Firestore en **camelCase** (`isFurnished`, `furnitureCents`, `tmiPercent`, `landSharePercent`) ; clés JSON du modèle en **snake_case** (`is_furnished`, `furniture_cents`, `tmi_percent`, `land_share_percent`) — `firestoreDocToSnakeJson` convertit.
- Accès Firestore uniquement via les dépôts existants (ADR 0003, `scripts/check-db-isolation.sh`).
- Fichiers `*.freezed.dart` / `*.g.dart` / `lib/l10n/app_localizations*.dart` : générés, **jamais commités**.
- Avant chaque commit Dart : `dart format $(git ls-files -m -o --exclude-standard '*.dart')` puis `flutter analyze` propre. Tâches Functions : `npm run lint` + `npm run build` + vitest.
- Textes : français, phrases simples ; aucun nom de palier autre que « Pro » dans les apps (règle 2.1 App Store) ; pas de bouton d'achat si `!canOfferUpgrade` (`lib/core/config/store_billing.dart`).
- Commits : messages en français, `git add` de chemins explicites (jamais `-A`), terminer par `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

---

### Task 1: Table de règles 2026

**Files:**
- Create: `lib/features/simulator/domain/lmnp_tax_rules.dart`
- Test: `test/unit/lmnp_tax_rules_test.dart`

**Interfaces:**
- Produces: `class LmnpTaxRules` (champs ci-dessous), `const LmnpTaxRules lmnpRules2026`, `const List<int> kTmiChoices = [0, 11, 30, 41, 45]`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:easyrent/features/simulator/domain/lmnp_tax_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Chaque valeur est figée : la modifier doit être un choix explicite
  // (nouvelle loi de finances), pas un effet de bord.
  test('règles 2026 — valeurs de la loi en vigueur', () {
    const r = lmnpRules2026;
    expect(r.label, 'Règles 2026');
    expect(r.microAbatementPercent, 50);
    expect(r.microMinAbatementCents, 30500);
    expect(r.microCeilingCents, 8360000);
    expect(r.socialRatePermille, 186);
    expect(r.buildingYears, 30);
    expect(r.worksYears, 15);
    expect(r.furnitureYears, 7);
    expect(r.lmpAlertCents, 2300000);
    expect(r.deficitCarryYears, 10);
  });

  test('tranches proposées', () {
    expect(kTmiChoices, [0, 11, 30, 41, 45]);
  });
}
```

- [ ] **Step 2: Run** `flutter test test/unit/lmnp_tax_rules_test.dart` — Expected: FAIL (fichier absent).

- [ ] **Step 3: Implement**

```dart
/// Règles fiscales LMNP (location meublée longue durée) utilisées par le
/// simulateur d'achat (FEAT-061). UNE table par loi de finances : changer de
/// loi = ajouter une table et basculer [lmnpRules2026] là où elle est lue ;
/// le calcul (`lmnp_tax_simulation.dart`) ne change pas.
///
/// Sources à confirmer sur Légifrance / BOFiP avant toute mise à jour.
library;

/// Tranches marginales d'imposition proposées à la saisie.
const List<int> kTmiChoices = [0, 11, 30, 41, 45];

class LmnpTaxRules {
  const LmnpTaxRules({
    required this.label,
    required this.microAbatementPercent,
    required this.microMinAbatementCents,
    required this.microCeilingCents,
    required this.socialRatePermille,
    required this.buildingYears,
    required this.worksYears,
    required this.furnitureYears,
    required this.lmpAlertCents,
    required this.deficitCarryYears,
  });

  /// Affiché dans l'UI (« Règles 2026 »).
  final String label;
  final int microAbatementPercent;
  final int microMinAbatementCents;

  /// Au-delà de ces recettes annuelles, le micro-BIC n'est pas disponible.
  final int microCeilingCents;

  /// Prélèvements sociaux, en pour mille (186 = 18,6 %).
  final int socialRatePermille;
  final int buildingYears;
  final int worksYears;
  final int furnitureYears;

  /// Recettes annuelles au-delà desquelles le statut LMP peut s'appliquer.
  final int lmpAlertCents;

  /// Durée de report d'un déficit hors amortissement.
  final int deficitCarryYears;
}

/// Loi de finances 2026 (promulguée en février 2026) + LFSS 2026.
const LmnpTaxRules lmnpRules2026 = LmnpTaxRules(
  label: 'Règles 2026',
  microAbatementPercent: 50,
  microMinAbatementCents: 30500,
  microCeilingCents: 8360000,
  socialRatePermille: 186,
  buildingYears: 30,
  worksYears: 15,
  furnitureYears: 7,
  lmpAlertCents: 2300000,
  deficitCarryYears: 10,
);
```

- [ ] **Step 4: Run** the test — Expected: PASS.
- [ ] **Step 5: Commit** `git add lib/features/simulator/domain/lmnp_tax_rules.dart test/unit/lmnp_tax_rules_test.dart` → `feat(simulator): table des règles LMNP 2026 (FEAT-061)`.

---

### Task 2: Champs du scénario (modèle + dépôt)

**Files:**
- Modify: `lib/features/simulator/domain/investment_scenario.dart` (après `condoFeesNonRecoverableCents`)
- Modify: `lib/features/simulator/data/investment_scenario_repository.dart` (`create` : paramètres + payload ; `update` : champs racine + `scenarioJson`)
- Test: `test/unit/investment_scenario_serialization_test.dart`, `test/unit/investment_scenario_repository_firestore_test.dart`

**Interfaces:**
- Produces: `InvestmentScenario.isFurnished` (bool, défaut false), `.furnitureCents` (int, 0), `.tmiPercent` (int, 30), `.landSharePercent` (int, 15) ; `create({..., bool isFurnished = false, int furnitureCents = 0, int tmiPercent = 30, int landSharePercent = 15})`.

- [ ] **Step 1: Failing tests**
  - Sérialisation : un JSON **sans** les 4 clés donne `isFurnished == false`, `furnitureCents == 0`, `tmiPercent == 30`, `landSharePercent == 15` ; un JSON avec `is_furnished: true, furniture_cents: 700000, tmi_percent: 41, land_share_percent: 20` les relit à l'identique ; `toJson` les écrit en snake_case.
  - Dépôt (`fake_cloud_firestore`, même patron que les tests existants du fichier) : `update(scenario.copyWith(isFurnished: true, furnitureCents: 700000, tmiPercent: 41, landSharePercent: 20))` écrit `isFurnished`, `furnitureCents`, `tmiPercent`, `landSharePercent` à la racine **et** dans `scenarioJson` ; `getById` relit ces valeurs. `create(...)` transmet les 4 clés camelCase au payload de la callable (vérifier sur le faux `FirebaseFunctions` déjà utilisé par le fichier de test ; s'il n'y en a pas, tester le payload via la fonction qui le construit).
- [ ] **Step 2: Run** `flutter test test/unit/investment_scenario_serialization_test.dart test/unit/investment_scenario_repository_firestore_test.dart` — Expected: FAIL.
- [ ] **Step 3: Implement** — dans le factory freezed :

```dart
    /// FEAT-061 — bien loué meublé (LMNP longue durée) : active la simulation
    /// fiscale. Défaut false : les scénarios existants n'en ont pas.
    @JsonKey(name: 'is_furnished') @Default(false) bool isFurnished,

    /// FEAT-061 — mobilier (centimes), amorti sur 7 ans au réel.
    @JsonKey(name: 'furniture_cents') @Default(0) int furnitureCents,

    /// FEAT-061 — tranche marginale d'imposition (%), parmi `kTmiChoices`.
    @JsonKey(name: 'tmi_percent') @Default(30) int tmiPercent,

    /// FEAT-061 — part du terrain dans le prix (%), non amortissable.
    @JsonKey(name: 'land_share_percent') @Default(15) int landSharePercent,
```

  Dépôt : ajouter les 4 paramètres nommés à `create` (interface abstraite **et** implémentation, mêmes défauts) et les clés `'isFurnished'`, `'furnitureCents'`, `'tmiPercent'`, `'landSharePercent'` au payload ; dans `update`, ajouter les 4 clés à la racine et dans `'scenarioJson'`. Puis `dart run build_runner build --delete-conflicting-outputs`.
- [ ] **Step 4: Run** the tests — PASS ; `flutter analyze` propre.
- [ ] **Step 5: Commit** les deux sources + deux tests → `feat(simulator): champs LMNP du scénario (FEAT-061)`.

---

### Task 3: Callable `createScenario` — nouveaux champs

**Files:**
- Modify: `functions/src/callable/scenarios.ts` (`ScenarioInputs`, `parseScenarioInputs`, `buildScenarioDocument`)
- Test: `functions/src/__tests__/scenarios.test.ts`

**Interfaces:**
- Consumes: payload camelCase de la Task 2.
- Produces: doc Firestore avec `isFurnished`, `furnitureCents`, `tmiPercent`, `landSharePercent` à la racine et dans `scenarioJson`.

- [ ] **Step 1: Failing tests** (`parseScenarioInputs` + `buildScenarioDocument`) :
  - payload sans les 4 champs → `isFurnished: false, furnitureCents: 0, tmiPercent: 30, landSharePercent: 15` ;
  - payload `{isFurnished: true, furnitureCents: 700000, tmiPercent: 41, landSharePercent: 20}` → repris tel quel, présents à la racine et dans `scenarioJson` ;
  - `tmiPercent: 25` → `invalid-argument` ; `landSharePercent: 51` et `-1` → `invalid-argument` ; `furnitureCents: -1` → `invalid-argument` ; `isFurnished: "oui"` → `invalid-argument`.
- [ ] **Step 2: Run** `cd functions && npx vitest run src/__tests__/scenarios.test.ts` — FAIL.
- [ ] **Step 3: Implement**

```ts
/** FEAT-061 — tranches marginales proposées (miroir de `kTmiChoices`). */
const TMI_CHOICES: ReadonlySet<number> = new Set([0, 11, 30, 41, 45]);
```

  Dans `ScenarioInputs` : `readonly isFurnished: boolean; readonly furnitureCents: number; readonly tmiPercent: number; readonly landSharePercent: number;`. Dans `parseScenarioInputs` :

```ts
    isFurnished:
      data.isFurnished === undefined || data.isFurnished === null ?
        false :
        requireBool(data.isFurnished, "isFurnished"),
    furnitureCents:
      optionalInt(data.furnitureCents, "furnitureCents", {min: 0}) ?? 0,
    tmiPercent: parseTmi(data.tmiPercent),
    landSharePercent:
      optionalInt(data.landSharePercent, "landSharePercent", {min: 0, max: 50}) ?? 15,
```

```ts
function parseTmi(value: unknown): number {
  const tmi = optionalInt(value, "tmiPercent", {min: 0}) ?? 30;
  if (!TMI_CHOICES.has(tmi)) {
    throw new HttpsError("invalid-argument", "tmiPercent must be 0, 11, 30, 41 or 45");
  }
  return tmi;
}
```

  (Vérifier que `optionalInt` accepte `max` dans `utils/callable_helpers.ts` ; sinon tester la borne haute à la main avec la même erreur `invalid-argument`.) Ajouter les 4 champs à `financials` dans `buildScenarioDocument`.
- [ ] **Step 4: Run** vitest (fichier puis suite), `npm run lint`, `npm run build` — tout vert.
- [ ] **Step 5: Commit** → `feat(functions): createScenario accepte les champs LMNP (FEAT-061)`.

---

### Task 4: Moteur de calcul LMNP

**Files:**
- Create: `lib/features/simulator/domain/lmnp_tax_simulation.dart`
- Modify: `lib/features/simulator/domain/scenario_results.dart` (rendre public `_kInsuranceBps` → `const int kScenarioLoanInsuranceBps = 30;` et l'utiliser à l'identique)
- Test: `test/unit/lmnp_tax_simulation_test.dart`

**Interfaces:**
- Consumes: `InvestmentScenario` (Task 2), `LmnpTaxRules`/`lmnpRules2026` (Task 1), `computeLoanMonthlyPaymentCents` (`lib/core/finance/profitability.dart`).
- Produces:

```dart
enum LmnpRegime { micro, reel }

class LmnpYear {
  const LmnpYear({required this.year, required this.taxableCents,
    required this.incomeTaxCents, required this.socialCents,
    required this.cashflowAfterTaxCents});
  final int year; final int taxableCents; final int incomeTaxCents;
  final int socialCents; final int cashflowAfterTaxCents;
  int get totalTaxCents => incomeTaxCents + socialCents;
}

class LmnpRegimeResult {
  const LmnpRegimeResult({required this.available, required this.years});
  final bool available; final List<LmnpYear> years;
  int get totalTaxCents => years.fold(0, (s, y) => s + y.totalTaxCents);
  int get totalCashflowAfterTaxCents =>
      years.fold(0, (s, y) => s + y.cashflowAfterTaxCents);
}

class LmnpTaxSimulation {
  const LmnpTaxSimulation({required this.micro, required this.reel,
    required this.annualRentCents, required this.rules});
  final LmnpRegimeResult micro; final LmnpRegimeResult reel;
  final int annualRentCents; final LmnpTaxRules rules;
  bool get lmpAlert => annualRentCents > rules.lmpAlertCents;
  LmnpRegime get best => !micro.available || reel.totalTaxCents < micro.totalTaxCents
      ? LmnpRegime.reel : LmnpRegime.micro;
}

LmnpTaxSimulation simulateLmnpTax(InvestmentScenario s,
    {LmnpTaxRules rules = lmnpRules2026, int years = 10});
```

- [ ] **Step 1: Failing tests** — valeurs calculées à la main (script de référence du cadrage), en centimes :

```dart
InvestmentScenario _s({
  int price = 10000000, int notary = 0, int works = 0, int furniture = 0,
  int land = 15, int rent = 60000, int tf = 0, int pno = 0, int copro = 0,
  int loan = 0, int bps = 0, int months = 240, int tmi = 30,
}) => InvestmentScenario(
  id: 't', landlordId: 'l', name: 't', purchasePriceCents: price,
  notaryFeesCents: notary, worksInitialCents: works, furnitureCents: furniture,
  landSharePercent: land, monthlyRentHcCents: rent, propertyTaxAnnualCents: tf,
  insurancePnoAnnualCents: pno, condoFeesNonRecoverableCents: copro,
  loanPrincipalCents: loan, loanRateBps: bps, loanDurationMonths: months,
  tmiPercent: tmi, isFurnished: true,
);
```

  1. **Cas A, sans prêt** : `_s(price: 10000000, notary: 800000, furniture: 700000, land: 20, rent: 60000, tf: 80000, pno: 15000)`.
     - micro année 1 : `taxableCents 360000, incomeTaxCents 108000, socialCents 66960, cashflowAfterTaxCents 450040` ; micro total 10 ans `1749600`, cash-flow après impôt cumulé `4500400`.
     - réel : années 1–3 imposable 0 (cash-flow 625000 chacune) ; année 4 : `taxable 233332, IR 70000, PS 43400` ; années 5–7 : `taxable 258333` ; **années 8–10 : `taxable 358333`** (fin du mobilier après 7 ans) ; réel total `1012500`, cash-flow cumulé `5237500`.
     - `best == LmnpRegime.reel`.
  2. **Cas B, avec prêt** : `_s(price: 20000000, notary: 1500000, works: 1000000, furniture: 500000, land: 15, rent: 90000, tf: 120000, pno: 20000, copro: 30000, loan: 18000000, bps: 350, months: 240)` → micro année 1 `taxable 540000, IR 162000, PS 100440, cash-flow -659156`, micro total `2624400` ; réel : 10 années à imposable 0, cash-flow `-396716` chaque année, total `0` ; `best == reel`.
  3. **Plancher 305 €** : `_s(rent: 5000)` → micro année 1 `taxable 29500, IR 8850, PS 5487`.
  4. **Plafond** : `_s(rent: 700000)` → `micro.available == false`, `best == reel`, `lmpAlert == true`.
  5. **Alerte LMP seule** : `_s(rent: 200000)` (24 000 €/an) → `lmpAlert == true`, `micro.available == true` ; `_s(rent: 190000)` → `lmpAlert == false`.
  6. **Déficit périmé après 10 ans** : `simulateLmnpTax(_s(price: 30000, notary: 10000000, land: 50, rent: 60000), years: 12)` → réel années 1–11 imposable 0 ; **année 12 : `taxable 714000, IR 214200, PS 132804, cash-flow 372996`**.
  7. **Égalité** : à total égal, `best == micro` (micro plus simple) — `_s(rent: 0)` : les deux totaux à 0 → `micro`.
- [ ] **Step 2: Run** `flutter test test/unit/lmnp_tax_simulation_test.dart` — FAIL.
- [ ] **Step 3: Implement** (types de la section Interfaces, plus) :

```dart
LmnpTaxSimulation simulateLmnpTax(
  InvestmentScenario s, {
  LmnpTaxRules rules = lmnpRules2026,
  int years = 10,
}) {
  final rent = s.monthlyRentHcCents * 12;
  final fixedCharges = s.propertyTaxAnnualCents + s.insurancePnoAnnualCents +
      s.condoFeesNonRecoverableCents;
  final loan = _loanYears(s, years);

  int incomeTax(int taxable) => (taxable * s.tmiPercent / 100).round();
  int social(int taxable) => (taxable * rules.socialRatePermille / 1000).round();
  LmnpYear row(int y, int taxable, int cashflowBefore) {
    final it = incomeTax(taxable), ps = social(taxable);
    return LmnpYear(year: y, taxableCents: taxable, incomeTaxCents: it,
        socialCents: ps, cashflowAfterTaxCents: cashflowBefore - it - ps);
  }

  // Micro-BIC.
  final abatement = math.max(
      (rent * rules.microAbatementPercent / 100).round(),
      rules.microMinAbatementCents);
  final microTaxable = math.max(rent - abatement, 0);

  // Réel : dotations annuelles par composant.
  final building = (s.purchasePriceCents * (100 - s.landSharePercent) / 100 /
      rules.buildingYears).round();
  final works = (s.worksInitialCents / rules.worksYears).round();
  final furniture = (s.furnitureCents / rules.furnitureYears).round();

  final micro = <LmnpYear>[], reel = <LmnpYear>[];
  final deficits = <({int year, int amount})>[];
  var amortCarry = 0;
  for (var y = 1; y <= years; y++) {
    final l = loan[y - 1];
    final cashflowBefore = rent - fixedCharges - l.paymentsCents;
    micro.add(row(y, microTaxable, cashflowBefore));

    final dotation = (y <= rules.buildingYears ? building : 0) +
        (y <= rules.worksYears ? works : 0) +
        (y <= rules.furnitureYears ? furniture : 0);
    final charges = fixedCharges + l.interestCents + l.insuranceCents +
        (y == 1 ? s.notaryFeesCents : 0);
    var result = rent - charges;
    deficits.removeWhere((d) => y - d.year > rules.deficitCarryYears);
    var taxable = 0;
    if (result < 0) {
      deficits.add((year: y, amount: -result));
      amortCarry += dotation;
    } else {
      for (var i = 0; i < deficits.length && result > 0; i++) {
        final used = math.min(deficits[i].amount, result);
        deficits[i] = (year: deficits[i].year, amount: deficits[i].amount - used);
        result -= used;
      }
      deficits.removeWhere((d) => d.amount == 0);
      final available = amortCarry + dotation;
      final deducted = math.min(available, result);
      amortCarry = available - deducted;
      taxable = result - deducted;
    }
    reel.add(row(y, taxable, cashflowBefore));
  }
  return LmnpTaxSimulation(
    micro: LmnpRegimeResult(available: rent <= rules.microCeilingCents, years: micro),
    reel: LmnpRegimeResult(available: true, years: reel),
    annualRentCents: rent,
    rules: rules,
  );
}

/// Intérêts, assurance et mensualités payés chaque année (échéancier à
/// mensualité constante, même mensualité que `computeScenarioResults`).
List<({int interestCents, int insuranceCents, int paymentsCents})> _loanYears(
    InvestmentScenario s, int years) {
  final p = s.loanPrincipalCents;
  final payment = computeLoanMonthlyPaymentCents(principalCents: p,
      rateBps: s.loanRateBps, durationMonths: s.loanDurationMonths,
      insuranceBps: kScenarioLoanInsuranceBps);
  final monthlyInsurance =
      p > 0 ? (p * kScenarioLoanInsuranceBps / 10000 / 12).round() : 0;
  final rate = s.loanRateBps / 10000 / 12;
  var balance = p.toDouble();
  return [
    for (var y = 0; y < years; y++)
      () {
        var interest = 0.0, months = 0;
        for (var m = 0; m < 12; m++) {
          if (p <= 0 || y * 12 + m >= s.loanDurationMonths) continue;
          final i = balance * rate;
          interest += i;
          balance -= (payment - monthlyInsurance) - i;
          months++;
        }
        return (interestCents: interest.round(),
            insuranceCents: monthlyInsurance * months,
            paymentsCents: payment * months);
      }(),
  ];
}
```

  Les montants de cash-flow ci-dessus sont ceux attendus par les tests : si un écart d'un centime apparaît, il vient d'un arrondi — aligner l'implémentation sur la formule, ne pas modifier l'attendu sans recalcul justifié dans le rapport.
- [ ] **Step 4: Run** test + `flutter test test/unit/scenario_results_test.dart` (renommage de la constante sans effet) — PASS.
- [ ] **Step 5: Commit** → `feat(simulator): calcul micro-BIC / réel LMNP sur 10 ans (FEAT-061)`.

---

### Task 5: Saisie dans le formulaire du simulateur

**Files:**
- Modify: `lib/features/simulator/presentation/simulator_page.dart` (état `_isFurnished`, `_furnitureCtrl`, `_tmiPercent`, `_landShareCtrl` ; chargement d'un scénario ; `_buildScenarioFromForm` ; création `create(...)` ; `_ScenarioForm`)
- Modify: `lib/features/simulator/presentation/widgets/scenario_form_validators.dart` (validateur part du terrain 0–50)
- Modify: `lib/l10n/app_fr.arb`, `lib/l10n/app_en.arb`
- Test: `test/widget/simulator_page_test.dart`

**Interfaces:**
- Consumes: champs de la Task 2, `kTmiChoices` (Task 1).

- [ ] **Step 1: Failing widget tests**
  - interrupteur `Key('lmnp_furnished_switch')` présent, désactivé par défaut ; les champs `Key('lmnp_furniture_field')`, `Key('lmnp_tmi_dropdown')`, `Key('lmnp_land_share_field')` absents tant qu'il est désactivé, présents après activation ;
  - après activation + saisie mobilier 7000, tranche 41, terrain 20, sauvegarde : le faux dépôt reçoit `isFurnished: true, furnitureCents: 700000, tmiPercent: 41, landSharePercent: 20` ;
  - charger un scénario meublé pré-remplit les 4 champs ;
  - terrain 60 → message d'erreur de validation, pas de sauvegarde.
- [ ] **Step 2: Run** `flutter test test/widget/simulator_page_test.dart` — FAIL.
- [ ] **Step 3: Implement** — après le bloc charges du formulaire : `SwitchListTile(key: Key('lmnp_furnished_switch'), title: Text(l10n.simulatorLmnpFurnishedLabel), subtitle: Text(l10n.simulatorLmnpFurnishedHelper))` ; si actif : champ montant mobilier (même widget de saisie monétaire que les autres champs du formulaire), `DropdownButtonFormField<int>` sur `kTmiChoices` (libellé `l10n.simulatorLmnpTmiOption(v)`), champ part du terrain (%) dans un `ExpansionTile(title: Text(l10n.simulatorLmnpAdvancedTitle))`. Chaque changement appelle `_onFieldChanged()` comme les autres champs. Chaînes ARB (FR / EN) :
  - `simulatorLmnpFurnishedLabel` : « Bien meublé (LMNP) » / "Furnished rental (LMNP)"
  - `simulatorLmnpFurnishedHelper` : « Location meublée longue durée : compare micro-BIC et réel » / "Long-term furnished rental: compares micro-BIC and actual regime"
  - `simulatorLmnpFurnitureLabel` : « Mobilier (€) » / "Furniture (€)"
  - `simulatorLmnpTmiLabel` : « Tranche d'imposition » / "Marginal tax rate"
  - `simulatorLmnpTmiOption` (`{rate}` int) : « {rate} % » / "{rate}%"
  - `simulatorLmnpAdvancedTitle` : « Réglages avancés » / "Advanced settings"
  - `simulatorLmnpLandShareLabel` : « Part du terrain dans le prix (%) » / "Land share of the price (%)"
  - `simulatorLmnpLandShareError` : « Entre 0 et 50 % » / "Between 0 and 50%"
  Puis `flutter gen-l10n`.
- [ ] **Step 4: Run** tests + `flutter analyze` — PASS.
- [ ] **Step 5: Commit** → `feat(simulator): saisie du bien meublé, de la tranche et du terrain (FEAT-061)`.

---

### Task 6: Carte « Fiscalité LMNP » (Pro, verrouillée, masquée)

**Files:**
- Create: `lib/features/simulator/presentation/widgets/lmnp_tax_card.dart`
- Modify: `lib/features/simulator/presentation/simulator_page.dart` (afficher la carte sous `ScenarioResultsCard` si le scénario du formulaire est meublé)
- Modify: `lib/features/simulator/presentation/widgets/coming_soon_paid_plan_section.dart` (retirer `'fiscal_lmnp'` et son libellé des deux listes, dans le même ordre)
- Modify: `lib/l10n/app_fr.arb`, `lib/l10n/app_en.arb`
- Test: `test/widget/lmnp_tax_card_test.dart`, mise à jour du test existant de la section « bientôt » s'il compte 4 éléments

**Interfaces:**
- Consumes: `simulateLmnpTax`, `LmnpTaxSimulation`, `LmnpRegime` (Task 4) ; `landlordTierProvider` → `snapshot.plan.atLeast(PlanLevel.pro)` ; `canOfferUpgrade`.
- Produces: `class LmnpTaxCard extends ConsumerWidget { const LmnpTaxCard({super.key, required this.scenario}); final InvestmentScenario scenario; }`.

- [ ] **Step 1: Failing widget tests**
  - Pro (`LandlordTierSnapshot(tier: SubscriptionTier.paid, planLevel: 'pro')`) + cas A de la Task 4 : clés `Key('lmnp_micro_total')` et `Key('lmnp_reel_total')` affichent les totaux 10 ans formatés en euros (`17 496 €`, `10 125 €`, via le formateur monétaire de l'app) ; `Key('lmnp_best_badge')` sur la colonne réel ; libellé « Règles 2026 » visible ; tableau annuel `Key('lmnp_yearly_table')` visible après tap sur `Key('lmnp_yearly_toggle')` ;
  - avertissements : `Key('lmnp_warning_resale')` et `Key('lmnp_warning_reform')` toujours ; `Key('lmnp_warning_lmp')` seulement si `lmpAlert` ; micro « non disponible » (`Key('lmnp_micro_unavailable')`) seulement au-dessus du plafond ;
  - gratuit : `Key('lmnp_locked')` affiché, aucun montant ; bouton `Key('lmnp_upgrade_button')` vers `/pro` si `canOfferUpgrade`, absent sinon (surcharger `isStoreApp` comme le font les tests existants de `canOfferUpgrade`) ;
  - simulateur : carte absente quand l'interrupteur meublé est désactivé (dans `simulator_page_test.dart`).
- [ ] **Step 2: Run** les tests — FAIL.
- [ ] **Step 3: Implement** la carte : en-tête `l10n.simulatorLmnpCardTitle` + `rules.label` ; deux colonnes (micro / réel) avec impôt + prélèvements année 1, total 10 ans, cash-flow après impôt cumulé ; badge `l10n.simulatorLmnpBestBadge` sur `sim.best` ; `ExpansionTile` du tableau annuel (année, imposable, impôt, prélèvements, cash-flow — une ligne par régime) ; liste d'avertissements ; mention `l10n.simulatorLmnpDisclaimer`. Variante verrouillée hors Pro : titre, `l10n.simulatorLmnpLockedBody`, bouton `l10n.simulatorLmnpUpgradeButton` (`context.push('/pro')`) si `canOfferUpgrade`. Chaînes (FR / EN) :
  - `simulatorLmnpCardTitle` : « Fiscalité LMNP » / "LMNP taxation"
  - `simulatorLmnpMicroTitle` : « Micro-BIC » / "Micro-BIC"
  - `simulatorLmnpReelTitle` : « Réel » / "Actual regime"
  - `simulatorLmnpYear1Tax` : « Impôt + prélèvements (année 1) » / "Tax + social charges (year 1)"
  - `simulatorLmnpTotalTax` : « Total sur 10 ans » / "10-year total"
  - `simulatorLmnpCashflowAfterTax` : « Cash-flow après impôt (10 ans) » / "Cash flow after tax (10 years)"
  - `simulatorLmnpBestBadge` : « Le plus favorable » / "Most favourable"
  - `simulatorLmnpYearlyToggle` : « Détail année par année » / "Year-by-year detail"
  - `simulatorLmnpMicroUnavailable` : « Non disponible : loyers au-delà de 83 600 € par an » / "Not available: rent above €83,600 a year"
  - `simulatorLmnpWarningLmp` : « Au-delà de 23 000 € de loyers par an, le statut de loueur professionnel (LMP) peut s'appliquer ; il n'est pas simulé. » / "Above €23,000 of rent a year, professional landlord status (LMP) may apply; it is not simulated."
  - `simulatorLmnpWarningResale` : « À la revente, les amortissements déduits sont réintégrés dans la plus-value (loi de finances 2025). » / "On resale, deducted depreciation is added back to the capital gain (2025 Finance Act)."
  - `simulatorLmnpWarningReform` : « Calcul selon les règles 2026 ; une réforme de l'amortissement est en discussion pour 2027. » / "Calculated with 2026 rules; a depreciation reform is under discussion for 2027."
  - `simulatorLmnpDisclaimer` : « Estimation indicative, qui ne constitue pas un conseil financier ou fiscal. » / "Indicative estimate, not financial or tax advice."
  - `simulatorLmnpLockedBody` : « Comparez micro-BIC et réel sur 10 ans avec l'offre Pro. » / "Compare micro-BIC and the actual regime over 10 years with the Pro plan."
  - `simulatorLmnpUpgradeButton` : « Passer à Pro » / "Upgrade to Pro"
  Retirer de `coming_soon_paid_plan_section.dart` l'entrée `'fiscal_lmnp'` et `l10n.simulatorPaidPlanFeatureTaxSimulation` ; supprimer la clé ARB `simulatorPaidPlanFeatureTaxSimulation` (FR + EN) si plus aucun usage (`grep`). `flutter gen-l10n`.
- [ ] **Step 4: Run** `flutter test` (suite complète), `flutter analyze` — PASS.
- [ ] **Step 5: Commit** → `feat(simulator): carte Fiscalité LMNP réservée à Pro (FEAT-061)`.

---

### Task 7: État du projet et docs

**Files:**
- Modify: `docs/state/FEATURES.md` (ligne FEAT-061), `docs/state/CHANGELOG.md` (entrée datée), `docs/state/schema/simulator.md` (4 champs), `docs/state/functions/simulator.md` (`createScenario` : champs et bornes), `docs/state/routes/simulator.md` (carte LMNP, accès Pro), `docs/backlog/018-investment-simulator.md` (la fiscalité « P2 » devient FEAT-061, lien vers la spec)

- [ ] **Step 1:** Mettre à jour ces fichiers (phrases courtes ; noter dans CHANGELOG : redéploiement des Functions requis ; valeurs 2026 à confirmer sur Légifrance / BOFiP ; mise à jour à prévoir après le vote de la loi de finances 2027).
- [ ] **Step 2:** Vérification finale : `dart format --output=none --set-exit-if-changed $(git ls-files '*.dart')`, `flutter analyze`, `flutter test`, `cd functions && npm run lint && npm run build && npx vitest run`, `bash scripts/check-db-isolation.sh`, `bash scripts/check-secrets.sh --all`.
- [ ] **Step 3: Commit** → `docs(state): FEAT-061 simulation fiscale LMNP`.
