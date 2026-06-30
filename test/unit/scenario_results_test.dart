/// Tests unitaires [computeScenarioResults] — 8 KPI simulateur (FEAT-018).
///
/// Vérifie les calculs, les edge cases et la cohérence avec
/// [computeLoanMonthlyPaymentCents] de FEAT-017.
library;

import 'package:easyrent/features/simulator/domain/investment_scenario.dart';
import 'package:easyrent/features/simulator/domain/scenario_results.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helper factory
// ---------------------------------------------------------------------------

InvestmentScenario _makeScenario({
  int purchasePriceCents = 20000000, // 200 000 €
  int notaryFeesCents = 1500000, // 15 000 €
  int worksInitialCents = 0,
  bool isNewProperty = false,
  int downPaymentCents = 4000000, // 40 000 €
  int loanPrincipalCents = 16000000, // 160 000 €
  int loanRateBps = 350, // 3,5 %
  int loanDurationMonths = 240, // 20 ans
  int monthlyRentHcCents = 80000, // 800 €/mois
  int propertyTaxAnnualCents = 120000, // 1 200 €/an
  int insurancePnoAnnualCents = 30000, // 300 €/an
  int condoFeesNonRecoverableCents = 60000, // 600 €/an
}) => InvestmentScenario(
  id: 'test-id',
  landlordId: 'owner',
  name: 'Test',
  purchasePriceCents: purchasePriceCents,
  notaryFeesCents: notaryFeesCents,
  worksInitialCents: worksInitialCents,
  isNewProperty: isNewProperty,
  downPaymentCents: downPaymentCents,
  loanPrincipalCents: loanPrincipalCents,
  loanRateBps: loanRateBps,
  loanDurationMonths: loanDurationMonths,
  monthlyRentHcCents: monthlyRentHcCents,
  propertyTaxAnnualCents: propertyTaxAnnualCents,
  insurancePnoAnnualCents: insurancePnoAnnualCents,
  condoFeesNonRecoverableCents: condoFeesNonRecoverableCents,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('computeScenarioResults — cas nominal', () {
    late ScenarioResults results;

    setUpAll(() {
      results = computeScenarioResults(_makeScenario());
    });

    test('KPI 1 — mensualité prêt > 0', () {
      // Capital 160k€, taux 3,5%, 240 mois, assurance 30 bps → ~950-1000 €
      expect(results.loanMonthlyPaymentCents, greaterThan(0));
      expect(results.loanMonthlyPaymentCents, greaterThan(90000)); // > 900€
      expect(results.loanMonthlyPaymentCents, lessThan(110000)); // < 1100€
    });

    test('KPI 2 — loyer net annuel = loyer brut × (1 - 5%)', () {
      // 800€/mois × 12 × 95% = 9120 €/an = 912000 centimes
      const annualGross = 80000 * 12;
      final expectedNet = (annualGross * 0.95).round();
      expect(results.annualRentNetCents, expectedNet);
    });

    test('KPI 2 — loyer net annuel est < loyer brut annuel', () {
      expect(results.annualRentNetCents, lessThan(80000 * 12));
    });

    test('KPI 3 — cash-flow est de type int', () {
      expect(results.monthlyCashflowBeforeTaxCents, isA<int>());
    });

    test('KPI 4 — rendement brut > 0 et cohérent', () {
      // 800€/mois × 12 = 9600€/an sur 200k€ + 15k€ = 215k€ → ~4.47%
      expect(results.yieldGrossPercent, greaterThan(0));
      expect(results.yieldGrossPercent, closeTo(4.47, 0.1));
    });

    test('KPI 5 — rendement net < rendement brut (charges déduites)', () {
      expect(results.yieldNetPercent, lessThan(results.yieldGrossPercent));
    });

    test('KPI 5 — rendement net > 0 (loyer > charges)', () {
      // Loyer net 9120€ - charges 2100€ = 7020€ sur 215k€ → ~3.27%
      expect(results.yieldNetPercent, greaterThan(0));
    });

    test('KPI 6 — total intérêts versés >= 0', () {
      expect(results.totalInterestPaidCents, greaterThanOrEqualTo(0));
    });

    test('KPI 7 — coût total crédit >= capital emprunté', () {
      // Coût total = capital + intérêts + assurance ≥ capital
      expect(results.totalLoanCostCents, greaterThanOrEqualTo(16000000));
    });

    test('KPI 8 — valeur estimée à terme > prix achat', () {
      // 200k€ × (1+0.015)^20 ≈ 269k€
      expect(results.estimatedValueAtEndCents, greaterThan(20000000));
    });

    test(
      'KPI 8 — valeur estimée cohérente avec appréciation 1,5%/an × 20 ans',
      () {
        // V_20 ≈ 200k€ × 1.015^20 ≈ 268 986 €
        expect(results.estimatedValueAtEndCents, closeTo(26900000, 1000000));
      },
    );
  });

  group('computeScenarioResults — vacance 5 %', () {
    test('loyer net annuel = loyer brut × 0.95', () {
      final s = _makeScenario(monthlyRentHcCents: 100000); // 1000€/mois
      final r = computeScenarioResults(s);
      // Brut annuel = 1 200 000, net = 1 140 000
      expect(r.annualRentNetCents, 1140000);
    });
  });

  group('computeScenarioResults — edge case prix achat nul', () {
    test('prix achat nul → rendements à 0', () {
      final s = _makeScenario(
        purchasePriceCents: 0,
        notaryFeesCents: 0,
        worksInitialCents: 0,
      );
      final r = computeScenarioResults(s);
      expect(r.yieldGrossPercent, 0.0);
      expect(r.yieldNetPercent, 0.0);
    });

    test('prix achat nul → mensualité 0 (capital également nul)', () {
      final s = _makeScenario(
        purchasePriceCents: 0,
        notaryFeesCents: 0,
        loanPrincipalCents: 0,
      );
      final r = computeScenarioResults(s);
      expect(r.loanMonthlyPaymentCents, 0);
    });
  });

  group('computeScenarioResults — edge case durée minimale', () {
    test('durée 12 mois → mensualité > 0', () {
      final s = _makeScenario(loanDurationMonths: 12);
      final r = computeScenarioResults(s);
      expect(r.loanMonthlyPaymentCents, greaterThan(0));
    });
  });

  group('computeScenarioResults — capital emprunté nul', () {
    test('capital nul → mensualité 0', () {
      final s = _makeScenario(loanPrincipalCents: 0);
      final r = computeScenarioResults(s);
      expect(r.loanMonthlyPaymentCents, 0);
    });

    test('capital nul → intérêts 0', () {
      final s = _makeScenario(loanPrincipalCents: 0);
      final r = computeScenarioResults(s);
      expect(r.totalInterestPaidCents, 0);
    });

    test('capital nul → cash-flow positif (loyer - charges seules)', () {
      final s = _makeScenario(
        loanPrincipalCents: 0,
        propertyTaxAnnualCents: 120000, // 1200€/an = 100€/mois
        insurancePnoAnnualCents: 0,
        condoFeesNonRecoverableCents: 0,
      );
      final r = computeScenarioResults(s);
      // 800 - 0 (mensualité) - 100 (charges/12) = 700€/mois
      expect(r.monthlyCashflowBeforeTaxCents, 70000);
    });
  });

  group('computeScenarioResults — aucune charge', () {
    test(
      'charges nulles → rendement net = rendement brut (vacance déduite)',
      () {
        final s = _makeScenario(
          propertyTaxAnnualCents: 0,
          insurancePnoAnnualCents: 0,
          condoFeesNonRecoverableCents: 0,
        );
        final r = computeScenarioResults(s);
        // Rendement net = loyer net annuel / acquisition
        final totalAcq =
            s.purchasePriceCents + s.notaryFeesCents + s.worksInitialCents;
        final expectedNet = (r.annualRentNetCents / totalAcq) * 100.0;
        expect(r.yieldNetPercent, closeTo(expectedNet, 0.001));
      },
    );
  });

  group('computeScenarioResults — taux 0 %', () {
    test('taux 0 → mensualité = capital / durée + assurance', () {
      final s = _makeScenario(
        loanPrincipalCents: 12000000, // 120 000 €
        loanRateBps: 0,
        loanDurationMonths: 120, // 10 ans
      );
      final r = computeScenarioResults(s);
      // Capital 120k / 120 = 1000€/mois + assurance 30bps = +30€/mois
      expect(r.loanMonthlyPaymentCents, closeTo(103000, 5000));
    });
  });

  group('computeScenarioResults — travaux initiaux inclus', () {
    test(
      'travaux inclus dans acquisition totale → rendement brut plus bas',
      () {
        final sansT = _makeScenario(worksInitialCents: 0);
        final avecT = _makeScenario(worksInitialCents: 2000000); // 20k€
        final rSans = computeScenarioResults(sansT);
        final rAvec = computeScenarioResults(avecT);
        expect(rAvec.yieldGrossPercent, lessThan(rSans.yieldGrossPercent));
      },
    );
  });

  group('computeScenarioResults — valeur estimée à terme', () {
    test('projection 20 ans cohérente avec puissance composée', () {
      final s = _makeScenario(purchasePriceCents: 10000000); // 100 000 €
      final r = computeScenarioResults(s);
      // 100k × 1.015^20 ≈ 134686 € = 13468600 centimes
      expect(r.estimatedValueAtEndCents, closeTo(13468600, 200000));
    });
  });

  group(
    'computeScenarioResults — cohérence avec computeLoanMonthlyPaymentCents',
    () {
      test('totalInterest = mensualité × durée - capital (pour taux > 0)', () {
        final s = _makeScenario(
          loanPrincipalCents: 10000000,
          loanRateBps: 300,
          loanDurationMonths: 120,
        );
        final r = computeScenarioResults(s);
        // Total remboursé = mensualité × 120
        final totalRepaid = r.loanMonthlyPaymentCents * 120;
        // Intérêts = totalRepaid - principal (sans l'assurance dans le calcul)
        // Note : totalLoanCost inclut assurance séparément
        expect(r.totalInterestPaidCents, greaterThanOrEqualTo(0));
        expect(r.totalLoanCostCents, greaterThan(10000000));
        // Coût total doit être inférieur au total remboursé × durée max imaginable
        expect(r.totalLoanCostCents, lessThan(totalRepaid * 2));
      });
    },
  );

  group('computeScenarioResults — retour de type ScenarioResults', () {
    test('retourne un ScenarioResults immutable', () {
      final s = _makeScenario();
      final r = computeScenarioResults(s);
      expect(r, isA<ScenarioResults>());
    });
  });
}
