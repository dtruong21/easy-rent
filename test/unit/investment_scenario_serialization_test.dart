/// Tests de sérialisation [InvestmentScenario] — round-trip JSON (FEAT-018).
///
/// Vérifie fromJson, toJson, valeurs par défaut et backward compat.
library;

import 'package:easyrent/features/simulator/domain/investment_scenario.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// JSON helpers
// ---------------------------------------------------------------------------

/// JSON minimal : seulement les champs NOT NULL sans DEFAULT.
Map<String, dynamic> _jsonMinimal() => {
  'id': 'scenario-1',
  'landlord_id': 'lld-1',
  'name': 'Appartement Paris',
  'purchase_price_cents': 30000000,
  'notary_fees_cents': 0,
  'works_initial_cents': 0,
  'is_new_property': false,
  'down_payment_cents': 0,
  'loan_principal_cents': 0,
  'loan_rate_bps': 0,
  'loan_duration_months': 240,
  'monthly_rent_hc_cents': 120000,
  'property_tax_annual_cents': 0,
  'insurance_pno_annual_cents': 0,
  'condo_fees_non_recoverable_cents': 0,
  'notes': null,
  'created_at': '2026-01-01T10:00:00Z',
  'updated_at': '2026-01-01T10:00:00Z',
  'deleted_at': null,
};

/// JSON complet avec tous les champs renseignés.
Map<String, dynamic> _jsonFull() => {
  'id': 'scenario-2',
  'landlord_id': 'lld-2',
  'name': 'Maison Lyon',
  'purchase_price_cents': 25000000,
  'notary_fees_cents': 1875000,
  'works_initial_cents': 500000,
  'is_new_property': false,
  'down_payment_cents': 5000000,
  'loan_principal_cents': 22375000,
  'loan_rate_bps': 375,
  'loan_duration_months': 300,
  'monthly_rent_hc_cents': 95000,
  'property_tax_annual_cents': 150000,
  'insurance_pno_annual_cents': 40000,
  'condo_fees_non_recoverable_cents': 80000,
  'notes': 'Quartier Confluence — fort potentiel locatif',
  'created_at': '2026-03-15T08:30:00Z',
  'updated_at': '2026-04-01T12:00:00Z',
  'deleted_at': null,
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('fromJson — JSON minimal', () {
    late InvestmentScenario s;

    setUpAll(() => s = InvestmentScenario.fromJson(_jsonMinimal()));

    test('id correct', () => expect(s.id, 'scenario-1'));
    test('landlordId correct', () => expect(s.landlordId, 'lld-1'));
    test('name correct', () => expect(s.name, 'Appartement Paris'));
    test(
      'purchasePriceCents correct',
      () => expect(s.purchasePriceCents, 30000000),
    );
    test(
      'monthlyRentHcCents correct',
      () => expect(s.monthlyRentHcCents, 120000),
    );
    test('notaryFeesCents = 0', () => expect(s.notaryFeesCents, 0));
    test('loanPrincipalCents = 0', () => expect(s.loanPrincipalCents, 0));
    test('loanRateBps = 0', () => expect(s.loanRateBps, 0));
    test('loanDurationMonths = 240', () => expect(s.loanDurationMonths, 240));
    test('isNewProperty = false', () => expect(s.isNewProperty, isFalse));
    test('notes = null', () => expect(s.notes, isNull));
    test('deletedAt = null', () => expect(s.deletedAt, isNull));
    test('createdAt parsé', () => expect(s.createdAt, isA<DateTime>()));
    test('updatedAt parsé', () => expect(s.updatedAt, isA<DateTime>()));
  });

  group('fromJson — JSON complet', () {
    late InvestmentScenario s;

    setUpAll(() => s = InvestmentScenario.fromJson(_jsonFull()));

    test('name complet', () => expect(s.name, 'Maison Lyon'));
    test('purchasePriceCents', () => expect(s.purchasePriceCents, 25000000));
    test('notaryFeesCents', () => expect(s.notaryFeesCents, 1875000));
    test('worksInitialCents', () => expect(s.worksInitialCents, 500000));
    test('downPaymentCents', () => expect(s.downPaymentCents, 5000000));
    test('loanPrincipalCents', () => expect(s.loanPrincipalCents, 22375000));
    test('loanRateBps = 375', () => expect(s.loanRateBps, 375));
    test('loanDurationMonths = 300', () => expect(s.loanDurationMonths, 300));
    test(
      'monthlyRentHcCents = 95000',
      () => expect(s.monthlyRentHcCents, 95000),
    );
    test(
      'propertyTaxAnnualCents = 150000',
      () => expect(s.propertyTaxAnnualCents, 150000),
    );
    test(
      'insurancePnoAnnualCents = 40000',
      () => expect(s.insurancePnoAnnualCents, 40000),
    );
    test(
      'condoFeesNonRecoverableCents = 80000',
      () => expect(s.condoFeesNonRecoverableCents, 80000),
    );
    test('notes non null', () => expect(s.notes, isNotNull));
    test('notes contenu', () => expect(s.notes, contains('Confluence')));
  });

  group('round-trip toJson → fromJson', () {
    test('scénario minimal sérialisé puis désérialisé est identique', () {
      final original = InvestmentScenario.fromJson(_jsonMinimal());
      final json = original.toJson();
      final restored = InvestmentScenario.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.purchasePriceCents, original.purchasePriceCents);
      expect(restored.monthlyRentHcCents, original.monthlyRentHcCents);
      expect(restored.loanRateBps, original.loanRateBps);
      expect(restored.loanDurationMonths, original.loanDurationMonths);
      expect(restored.isNewProperty, original.isNewProperty);
    });

    test('scénario complet round-trip préserve tous les champs', () {
      final original = InvestmentScenario.fromJson(_jsonFull());
      final json = original.toJson();
      final restored = InvestmentScenario.fromJson(json);

      expect(restored.notaryFeesCents, original.notaryFeesCents);
      expect(restored.worksInitialCents, original.worksInitialCents);
      expect(restored.downPaymentCents, original.downPaymentCents);
      expect(restored.loanPrincipalCents, original.loanPrincipalCents);
      expect(restored.propertyTaxAnnualCents, original.propertyTaxAnnualCents);
      expect(
        restored.insurancePnoAnnualCents,
        original.insurancePnoAnnualCents,
      );
      expect(
        restored.condoFeesNonRecoverableCents,
        original.condoFeesNonRecoverableCents,
      );
      expect(restored.notes, original.notes);
    });

    test('toJson inclut les clés snake_case correctes', () {
      final s = InvestmentScenario.fromJson(_jsonFull());
      final json = s.toJson();
      expect(json.containsKey('purchase_price_cents'), isTrue);
      expect(json.containsKey('loan_rate_bps'), isTrue);
      expect(json.containsKey('monthly_rent_hc_cents'), isTrue);
      expect(json.containsKey('landlord_id'), isTrue);
      expect(json.containsKey('loan_duration_months'), isTrue);
      expect(json.containsKey('condo_fees_non_recoverable_cents'), isTrue);
    });
  });

  group('constructeur Dart — valeurs par défaut', () {
    test('defaults via constructeur', () {
      final s = InvestmentScenario(
        id: 'test',
        landlordId: 'owner',
        name: 'Test',
        purchasePriceCents: 10000000,
        monthlyRentHcCents: 50000,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      expect(s.notaryFeesCents, 0);
      expect(s.worksInitialCents, 0);
      expect(s.isNewProperty, isFalse);
      expect(s.downPaymentCents, 0);
      expect(s.loanPrincipalCents, 0);
      expect(s.loanRateBps, 0);
      expect(s.loanDurationMonths, 240);
      expect(s.propertyTaxAnnualCents, 0);
      expect(s.insurancePnoAnnualCents, 0);
      expect(s.condoFeesNonRecoverableCents, 0);
      expect(s.notes, isNull);
      expect(s.deletedAt, isNull);
    });

    test('copyWith modifie uniquement le champ cible', () {
      final original = InvestmentScenario.fromJson(_jsonFull());
      final modified = original.copyWith(name: 'Nouveau nom');
      expect(modified.name, 'Nouveau nom');
      expect(modified.purchasePriceCents, original.purchasePriceCents);
      expect(modified.loanRateBps, original.loanRateBps);
    });
  });
}
