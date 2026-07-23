/// Tests unitaires du view-model de comparaison de scénarios (FEAT-055).
///
/// Fonction pure — pas de widget, pas de MaterialApp. Couvre le contrat KPI,
/// le delta signé et la formule d'effort d'épargne.
library;

import 'package:easyrent/features/simulator/domain/investment_scenario.dart';
import 'package:easyrent/features/simulator/domain/scenario_comparison_view_model.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

InvestmentScenario _scenario({
  required String id,
  required String name,
  int purchasePriceCents = 20000000,
  int notaryFeesCents = 1500000,
  int downPaymentCents = 0,
  int loanPrincipalCents = 16000000,
  int loanRateBps = 350,
  int loanDurationMonths = 240,
  int monthlyRentHcCents = 80000,
  int propertyTaxAnnualCents = 120000,
}) {
  return InvestmentScenario(
    id: id,
    landlordId: 'lld-1',
    name: name,
    purchasePriceCents: purchasePriceCents,
    notaryFeesCents: notaryFeesCents,
    downPaymentCents: downPaymentCents,
    loanPrincipalCents: loanPrincipalCents,
    loanRateBps: loanRateBps,
    loanDurationMonths: loanDurationMonths,
    monthlyRentHcCents: monthlyRentHcCents,
    propertyTaxAnnualCents: propertyTaxAnnualCents,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

Future<AppLocalizations> _fr() =>
    AppLocalizations.delegate.load(const Locale('fr'));

void main() {
  group('computeAnnualSavingsEffortCents', () {
    test('cashflow positif → 0 (auto-financé)', () {
      expect(computeAnnualSavingsEffortCents(15000), 0);
    });
    test('cashflow nul → 0', () {
      expect(computeAnnualSavingsEffortCents(0), 0);
    });
    test('cashflow -100 €/mois → 1200 €/an', () {
      expect(computeAnnualSavingsEffortCents(-10000), 120000);
    });
    test('cashflow -1 c/mois → 12 c/an', () {
      expect(computeAnnualSavingsEffortCents(-1), 12);
    });
  });

  group('computeSignedDeltaPercent', () {
    test('même valeur → 0', () {
      expect(computeSignedDeltaPercent(100, 100), 0);
    });
    test('other > reference → positif', () {
      expect(computeSignedDeltaPercent(100, 110), closeTo(10, 1e-9));
    });
    test('other < reference → négatif', () {
      expect(computeSignedDeltaPercent(100, 90), closeTo(-10, 1e-9));
    });
    test('reference == 0 → null (division impossible)', () {
      expect(computeSignedDeltaPercent(0, 100), isNull);
    });
    test('reference négative → sens économique préservé (division par abs)', () {
      // Cash-flow -100 € → -50 € : other est meilleur (moins négatif) → delta +50.
      expect(computeSignedDeltaPercent(-100, -50), closeTo(50, 1e-9));
      // -100 € → -200 € : pire, delta -100.
      expect(computeSignedDeltaPercent(-100, -200), closeTo(-100, 1e-9));
    });
    test('seuils exacts ±5 %', () {
      expect(computeSignedDeltaPercent(100, 105), closeTo(5, 1e-9));
      expect(computeSignedDeltaPercent(100, 95), closeTo(-5, 1e-9));
    });
  });

  group('buildComparisonRows', () {
    testWidgets('produit 6 lignes, N valeurs par ligne, ordre préservé', (
      tester,
    ) async {
      final l10n = await _fr();
      final rows = buildComparisonRows([
        _scenario(id: 'A', name: 'Alpha'),
        _scenario(id: 'B', name: 'Bravo'),
        _scenario(id: 'C', name: 'Charlie'),
      ], l10n);

      expect(rows.length, 6);
      for (final row in rows) {
        expect(row.values.length, 3, reason: 'row ${row.kpi.name}');
      }
      expect(rows.map((r) => r.kpi).toList(), [
        ComparisonKpi.grossYield,
        ComparisonKpi.netYield,
        ComparisonKpi.monthlyCashflow,
        ComparisonKpi.totalLoanCost,
        ComparisonKpi.downPaymentRequired,
        ComparisonKpi.savingsEffort,
      ]);
    });

    testWidgets('scénarios identiques → valeurs égales sur chaque ligne', (
      tester,
    ) async {
      final l10n = await _fr();
      final rows = buildComparisonRows([
        _scenario(id: 'A', name: 'Alpha'),
        _scenario(id: 'B', name: 'Bravo'),
      ], l10n);
      for (final row in rows) {
        expect(
          row.values[0].rawNumber,
          row.values[1].rawNumber,
          reason: 'row ${row.kpi.name}',
        );
      }
    });

    testWidgets('effort d\'épargne exposé en centimes/an dans rawNumber', (
      tester,
    ) async {
      final l10n = await _fr();
      // Scénario A : loyer très bas → cashflow négatif → effort > 0
      final scenarioA = _scenario(
        id: 'A',
        name: 'Alpha',
        monthlyRentHcCents: 10000, // 100 €/mois
      );
      // Scénario B : loyer élevé → cashflow probablement positif → effort 0
      final scenarioB = _scenario(
        id: 'B',
        name: 'Bravo',
        monthlyRentHcCents: 200000, // 2000 €/mois
      );
      final rows = buildComparisonRows([scenarioA, scenarioB], l10n);
      final effortRow = rows.firstWhere(
        (r) => r.kpi == ComparisonKpi.savingsEffort,
      );
      expect(effortRow.values[0].rawNumber, greaterThan(0));
      expect(effortRow.values[1].rawNumber, 0);
    });
  });

  group('ComparisonKpi.higherIsBetter', () {
    test('rendements + cashflow : plus haut = mieux', () {
      expect(ComparisonKpi.grossYield.higherIsBetter, true);
      expect(ComparisonKpi.netYield.higherIsBetter, true);
      expect(ComparisonKpi.monthlyCashflow.higherIsBetter, true);
    });
    test('coût crédit, apport, effort : plus bas = mieux', () {
      expect(ComparisonKpi.totalLoanCost.higherIsBetter, false);
      expect(ComparisonKpi.downPaymentRequired.higherIsBetter, false);
      expect(ComparisonKpi.savingsEffort.higherIsBetter, false);
    });
  });
}
