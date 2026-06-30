import 'package:easyrent/core/finance/profitability.dart';
import 'package:easyrent/core/finance/profitability_snapshot.dart';
import 'package:easyrent/features/properties/domain/property.dart';
import 'package:easyrent/features/properties/domain/property_type.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Property _makeProperty({
  int? purchasePriceCents,
  int? notaryFeesCents,
  int? propertyTaxAnnualCents,
  int? insurancePnoAnnualCents,
  int? condoFeesNonRecoverableCents,
  int? loanPrincipalCents,
  int? loanRateBps,
  int? loanInsuranceBps,
  int? loanDurationMonths,
  int? loanMonthlyPaymentOverrideCents,
}) => Property(
  id: 'test-id',
  landlordId: 'owner',
  name: 'Test',
  address: '1 rue Test',
  type: PropertyType.appartement,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
  purchasePriceCents: purchasePriceCents,
  notaryFeesCents: notaryFeesCents,
  propertyTaxAnnualCents: propertyTaxAnnualCents,
  insurancePnoAnnualCents: insurancePnoAnnualCents,
  condoFeesNonRecoverableCents: condoFeesNonRecoverableCents,
  loanPrincipalCents: loanPrincipalCents,
  loanRateBps: loanRateBps,
  loanInsuranceBps: loanInsuranceBps,
  loanDurationMonths: loanDurationMonths,
  loanMonthlyPaymentOverrideCents: loanMonthlyPaymentOverrideCents,
);

// ---------------------------------------------------------------------------
// Tests — computeLoanMonthlyPaymentCents
// ---------------------------------------------------------------------------

void main() {
  group('computeLoanMonthlyPaymentCents', () {
    test('taux 0 → mensualité = capital / durée', () {
      // Capital 120 000 € sur 120 mois, taux 0, assurance 0
      // = 120 000 000 / 120 = 1 000 000 centimes = 1000 €
      final result = computeLoanMonthlyPaymentCents(
        principalCents: 12000000,
        rateBps: 0,
        durationMonths: 120,
        insuranceBps: 0,
      );
      expect(result, 100000); // 1000 €
    });

    test('taux 0 avec assurance', () {
      // Capital 100 000 €, taux 0, assurance 0.30% annuel = 30 bps
      // mensualité assurance = 10_000_000 * 30 / 10000 / 12 = 2500 centimes = 25 €
      // mensualité capital = 10_000_000 / 120 = 83333 centimes
      final result = computeLoanMonthlyPaymentCents(
        principalCents: 10000000,
        rateBps: 0,
        durationMonths: 120,
        insuranceBps: 30,
      );
      expect(result, closeTo(85833, 5)); // 83333 + 2500
    });

    test('formule annuité classique 200k€ sur 240 mois à 3.5%', () {
      // Capital 200 000 € = 20 000 000 centimes, taux 3.5%, 240 mois, assurance 0
      // Calcul attendu : ~1160 € ≈ 116 000 centimes
      final result = computeLoanMonthlyPaymentCents(
        principalCents: 20000000,
        rateBps: 350,
        durationMonths: 240,
        insuranceBps: 0,
      );
      // Vérification approximative (formule annuité)
      expect(result, greaterThan(110000)); // > 1100 € en centimes
      expect(result, lessThan(120000)); // < 1200 € en centimes
    });

    test('durée minimale 12 mois', () {
      final result = computeLoanMonthlyPaymentCents(
        principalCents: 1200000,
        rateBps: 200,
        durationMonths: 12,
        insuranceBps: 0,
      );
      expect(result, greaterThan(0));
    });

    test('durée maximale 360 mois', () {
      final result = computeLoanMonthlyPaymentCents(
        principalCents: 20000000,
        rateBps: 400,
        durationMonths: 360,
        insuranceBps: 30,
      );
      expect(result, greaterThan(0));
    });

    test('capital nul → 0', () {
      final result = computeLoanMonthlyPaymentCents(
        principalCents: 0,
        rateBps: 350,
        durationMonths: 240,
        insuranceBps: 0,
      );
      expect(result, 0);
    });

    test('durée nulle → 0', () {
      final result = computeLoanMonthlyPaymentCents(
        principalCents: 20000000,
        rateBps: 350,
        durationMonths: 0,
        insuranceBps: 0,
      );
      expect(result, 0);
    });

    test('capital négatif → 0', () {
      final result = computeLoanMonthlyPaymentCents(
        principalCents: -1000,
        rateBps: 350,
        durationMonths: 240,
        insuranceBps: 0,
      );
      expect(result, 0);
    });

    test('résultat en centimes entiers (cohérence unité)', () {
      final result = computeLoanMonthlyPaymentCents(
        principalCents: 18000000,
        rateBps: 370,
        durationMonths: 200,
        insuranceBps: 30,
      );
      // Doit être un entier
      expect(result, isA<int>());
      expect(result, greaterThan(0));
    });
  });

  // ---------------------------------------------------------------------------
  // Tests — computeYieldGrossPercent
  // ---------------------------------------------------------------------------

  group('computeYieldGrossPercent', () {
    test('cas nominal : 800€/mois sur 200k€', () {
      // Loyer annuel = 9600 €, prix achat = 200k € → 4.8%
      final result = computeYieldGrossPercent(
        annualRentHcCents: 960000,
        purchasePriceCents: 20000000,
        notaryFeesCents: null,
      );
      expect(result, closeTo(4.8, 0.01));
    });

    test('avec frais de notaire', () {
      // Loyer annuel = 9600 €, prix achat + notaire = 215k € → ~4.47%
      final result = computeYieldGrossPercent(
        annualRentHcCents: 960000,
        purchasePriceCents: 20000000,
        notaryFeesCents: 1500000,
      );
      expect(result, closeTo(4.47, 0.05));
    });

    test('prix achat nul → null', () {
      final result = computeYieldGrossPercent(
        annualRentHcCents: 960000,
        purchasePriceCents: 0,
        notaryFeesCents: null,
      );
      expect(result, isNull);
    });

    test('prix achat absent → null', () {
      final result = computeYieldGrossPercent(
        annualRentHcCents: 960000,
        purchasePriceCents: null,
        notaryFeesCents: null,
      );
      expect(result, isNull);
    });

    test('résultat en pourcentage double positif', () {
      final result = computeYieldGrossPercent(
        annualRentHcCents: 1200000,
        purchasePriceCents: 15000000,
        notaryFeesCents: 0,
      );
      expect(result, isA<double>());
      expect(result, greaterThan(0));
    });
  });

  // ---------------------------------------------------------------------------
  // Tests — computeYieldNetPercent
  // ---------------------------------------------------------------------------

  group('computeYieldNetPercent', () {
    test('cas nominal avec charges complètes', () {
      // Loyer 800€/mois = 9600€/an, charges = 1200+300+600 = 2100€/an
      // Net = (9600 - 2100) / 200000 = 3.75%
      final result = computeYieldNetPercent(
        annualRentHcCents: 960000,
        purchasePriceCents: 20000000,
        notaryFeesCents: null,
        propertyTaxAnnualCents: 120000,
        insurancePnoAnnualCents: 30000,
        condoFeesNonRecoverableCents: 60000,
      );
      expect(result, closeTo(3.75, 0.01));
    });

    test('aucune charge renseignée → null', () {
      final result = computeYieldNetPercent(
        annualRentHcCents: 960000,
        purchasePriceCents: 20000000,
        notaryFeesCents: null,
        propertyTaxAnnualCents: null,
        insurancePnoAnnualCents: null,
        condoFeesNonRecoverableCents: null,
      );
      expect(result, isNull);
    });

    test('prix achat absent → null', () {
      final result = computeYieldNetPercent(
        annualRentHcCents: 960000,
        purchasePriceCents: null,
        notaryFeesCents: null,
        propertyTaxAnnualCents: 120000,
        insurancePnoAnnualCents: null,
        condoFeesNonRecoverableCents: null,
      );
      expect(result, isNull);
    });

    test('charge partielle (seulement taxe foncière) → calcule quand même', () {
      // Une seule charge renseignée suffit.
      final result = computeYieldNetPercent(
        annualRentHcCents: 960000,
        purchasePriceCents: 20000000,
        notaryFeesCents: null,
        propertyTaxAnnualCents: 120000,
        insurancePnoAnnualCents: null,
        condoFeesNonRecoverableCents: null,
      );
      expect(result, isNotNull);
      expect(result, greaterThan(0));
    });

    test('rendement net peut être négatif (charges > loyer)', () {
      final result = computeYieldNetPercent(
        annualRentHcCents: 100000, // 1000 €/an
        purchasePriceCents: 20000000,
        notaryFeesCents: null,
        propertyTaxAnnualCents: 200000, // 2000 €/an de charges
        insurancePnoAnnualCents: null,
        condoFeesNonRecoverableCents: null,
      );
      expect(result, isNotNull);
      expect(result!, lessThan(0));
    });
  });

  // ---------------------------------------------------------------------------
  // Tests — computeMonthlyCashflowBeforeTaxCents
  // ---------------------------------------------------------------------------

  group('computeMonthlyCashflowBeforeTaxCents', () {
    test('cas nominal avec prêt et charges', () {
      // Loyer 800€, mensualité 750€, charges annuelles 2400€ → 200€/mois
      // 800 - 750 - (2400/12) = 800 - 750 - 200 = -150
      final result = computeMonthlyCashflowBeforeTaxCents(
        monthlyRentHcCents: 80000,
        loanMonthlyPaymentCents: 75000,
        propertyTaxAnnualCents: 240000,
        insurancePnoAnnualCents: null,
        condoFeesNonRecoverableCents: null,
      );
      expect(result, -15000); // -150€
    });

    test('sans prêt mais avec charges', () {
      // Loyer 1000€, pas de prêt, charges 2400€/an → 200€/mois
      // 1000 - 0 - 200 = 800€
      final result = computeMonthlyCashflowBeforeTaxCents(
        monthlyRentHcCents: 100000,
        loanMonthlyPaymentCents: null,
        propertyTaxAnnualCents: 240000,
        insurancePnoAnnualCents: null,
        condoFeesNonRecoverableCents: null,
      );
      expect(result, 80000); // 800€
    });

    test('aucune donnée → null', () {
      final result = computeMonthlyCashflowBeforeTaxCents(
        monthlyRentHcCents: 80000,
        loanMonthlyPaymentCents: null,
        propertyTaxAnnualCents: null,
        insurancePnoAnnualCents: null,
        condoFeesNonRecoverableCents: null,
      );
      expect(result, isNull);
    });

    test('cash flow positif', () {
      // Loyer 1500€, mensualité 500€, charges 1200€/an → 100€/mois
      // 1500 - 500 - 100 = 900€
      final result = computeMonthlyCashflowBeforeTaxCents(
        monthlyRentHcCents: 150000,
        loanMonthlyPaymentCents: 50000,
        propertyTaxAnnualCents: 120000,
        insurancePnoAnnualCents: null,
        condoFeesNonRecoverableCents: null,
      );
      expect(result, 90000); // 900€
    });

    test('résultat en centimes entiers', () {
      final result = computeMonthlyCashflowBeforeTaxCents(
        monthlyRentHcCents: 80000,
        loanMonthlyPaymentCents: 70000,
        propertyTaxAnnualCents: 12000,
        insurancePnoAnnualCents: 0,
        condoFeesNonRecoverableCents: 0,
      );
      expect(result, isA<int>());
    });
  });

  // ---------------------------------------------------------------------------
  // Tests — computeSnapshotForProperty
  // ---------------------------------------------------------------------------

  group('computeSnapshotForProperty', () {
    test(
      'bien vacant → snapshot non computable avec missingField active_lease',
      () {
        final property = _makeProperty(purchasePriceCents: 20000000);
        final snapshot = computeSnapshotForProperty(
          property: property,
          monthlyRentHcCents: null,
        );

        expect(snapshot.isComputable, isFalse);
        expect(snapshot.missingFields, contains('active_lease'));
      },
    );

    test('prix achat manquant → snapshot non computable', () {
      final property = _makeProperty(); // pas de purchasePriceCents
      final snapshot = computeSnapshotForProperty(
        property: property,
        monthlyRentHcCents: 80000,
      );

      expect(snapshot.isComputable, isFalse);
      expect(snapshot.missingFields, contains('purchase_price'));
    });

    test('données complètes → snapshot computable avec KPIs', () {
      final property = _makeProperty(
        purchasePriceCents: 20000000, // 200k€
        notaryFeesCents: 1500000, // 15k€
        propertyTaxAnnualCents: 120000, // 1200€/an
        insurancePnoAnnualCents: 30000, // 300€/an
        condoFeesNonRecoverableCents: 60000, // 600€/an
        loanPrincipalCents: 16000000, // 160k€
        loanRateBps: 350, // 3.5%
        loanInsuranceBps: 30, // 0.30%
        loanDurationMonths: 240,
      );

      final snapshot = computeSnapshotForProperty(
        property: property,
        monthlyRentHcCents: 80000, // 800€/mois
      );

      expect(snapshot.isComputable, isTrue);
      expect(snapshot.missingFields, isEmpty);
      expect(snapshot.yieldGrossPercent, isNotNull);
      expect(snapshot.yieldGrossPercent!, greaterThan(0));
      expect(snapshot.yieldNetPercent, isNotNull);
      expect(snapshot.loanMonthlyPaymentCents, isNotNull);
      expect(snapshot.loanMonthlyPaymentCents!, greaterThan(0));
      expect(snapshot.monthlyCashflowBeforeTaxCents, isNotNull);
    });

    test('override mensualité prêt prioritaire sur calcul', () {
      final property = _makeProperty(
        purchasePriceCents: 20000000,
        loanPrincipalCents: 16000000,
        loanRateBps: 350,
        loanDurationMonths: 240,
        loanMonthlyPaymentOverrideCents: 99999, // override
      );

      final snapshot = computeSnapshotForProperty(
        property: property,
        monthlyRentHcCents: 80000,
      );

      // L'override doit être utilisé, pas le calcul automatique.
      expect(snapshot.loanMonthlyPaymentCents, 99999);
    });

    test('backward compat : bien existant sans données FEAT-017', () {
      // Un bien sans aucun champ FEAT-017 doit charger sans erreur.
      final legacyProperty = _makeProperty(); // tout null
      final snapshot = computeSnapshotForProperty(
        property: legacyProperty,
        monthlyRentHcCents: 80000,
      );

      expect(snapshot.isComputable, isFalse);
      expect(snapshot.missingFields, contains('purchase_price'));
      // Aucune exception levée.
    });

    test('rendement brut cohérent avec formule manuelle', () {
      // 800€/mois × 12 = 9600€/an sur 200k€ = 4.8%
      final property = _makeProperty(purchasePriceCents: 20000000);
      final snapshot = computeSnapshotForProperty(
        property: property,
        monthlyRentHcCents: 80000,
      );

      expect(snapshot.yieldGrossPercent, closeTo(4.8, 0.01));
    });

    test('snapshot immutable (freezed) — toJson/fromJson round-trip', () {
      const snapshot = ProfitabilitySnapshot(
        isComputable: true,
        missingFields: [],
        yieldGrossPercent: 5.5,
        yieldNetPercent: 3.2,
        monthlyCashflowBeforeTaxCents: -5000,
        loanMonthlyPaymentCents: 85000,
      );

      final json = snapshot.toJson();
      final restored = ProfitabilitySnapshot.fromJson(json);

      expect(restored.isComputable, isTrue);
      expect(restored.yieldGrossPercent, closeTo(5.5, 0.001));
      expect(restored.yieldNetPercent, closeTo(3.2, 0.001));
      expect(restored.monthlyCashflowBeforeTaxCents, -5000);
    });
  });
}
