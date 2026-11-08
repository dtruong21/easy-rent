/// Tests unitaires pour [loanMonthlyPaymentForMonthCents] et
/// [sumLoanMonthlyPaymentCentsForMonth] — fenêtre du prêt appliquée au
/// graphique « Cash-flow mensuel » du dashboard.
///
/// Couvre :
/// - Mois dans la fenêtre du prêt → mensualité déduite, identique à
///   `computeLoanMonthlyPaymentCents` (core/finance/profitability.dart)
/// - Bien sans prêt → rien déduit
/// - Mois antérieur au départ du prêt → rien déduit
/// - Mois postérieur à la dernière échéance → rien déduit
/// - `loanMonthlyPaymentOverrideCents` prioritaire, comme
///   `computeSnapshotForProperty`
/// - `loanStartDate` absent → fenêtre indéterminée, rien déduit (même si
///   principal/taux/durée sont renseignés)
/// - Agrégation multi-biens (`sumLoanMonthlyPaymentCentsForMonth`)
library;

import 'package:easyrent/core/finance/profitability.dart';
import 'package:easyrent/features/dashboard/domain/monthly_loan_payment.dart';
import 'package:easyrent/features/properties/domain/property.dart';
import 'package:easyrent/features/properties/domain/property_type.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Property _property({
  String id = 'p1',
  int? loanPrincipalCents,
  int? loanRateBps,
  int? loanInsuranceBps,
  int? loanDurationMonths,
  DateTime? loanStartDate,
  int? loanMonthlyPaymentOverrideCents,
}) => Property(
  id: id,
  landlordId: 'owner',
  name: 'Bien Test',
  address: '1 rue Test',
  type: PropertyType.appartement,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
  loanPrincipalCents: loanPrincipalCents,
  loanRateBps: loanRateBps,
  loanInsuranceBps: loanInsuranceBps,
  loanDurationMonths: loanDurationMonths,
  loanStartDate: loanStartDate,
  loanMonthlyPaymentOverrideCents: loanMonthlyPaymentOverrideCents,
);

void main() {
  group('loanMonthlyPaymentForMonthCents — bien sans prêt', () {
    test('aucun champ de prêt renseigné → 0', () {
      final property = _property();
      expect(
        loanMonthlyPaymentForMonthCents(
          property: property,
          year: 2026,
          month: 6,
        ),
        0,
      );
    });
  });

  group('loanMonthlyPaymentForMonthCents — fenêtre du prêt', () {
    test('mois dans la fenêtre → mensualité déduite, identique à '
        'computeLoanMonthlyPaymentCents', () {
      final property = _property(
        loanPrincipalCents: 20000000, // 200 000 €
        loanRateBps: 350,
        loanInsuranceBps: 0,
        loanDurationMonths: 240,
        loanStartDate: DateTime(2024, 1, 1),
      );
      final expected = computeLoanMonthlyPaymentCents(
        principalCents: 20000000,
        rateBps: 350,
        durationMonths: 240,
        insuranceBps: 0,
      );

      // Un mois bien à l'intérieur de la fenêtre (janvier 2024 → 240 mois).
      final result = loanMonthlyPaymentForMonthCents(
        property: property,
        year: 2026,
        month: 3,
      );
      expect(result, expected);
      expect(result, greaterThan(0));
    });

    test('mois antérieur au départ du prêt → 0 (pas de charge inventée)', () {
      final property = _property(
        loanPrincipalCents: 20000000,
        loanRateBps: 350,
        loanDurationMonths: 240,
        loanStartDate: DateTime(2026, 6, 1),
      );

      // Un mois avant juin 2026.
      final result = loanMonthlyPaymentForMonthCents(
        property: property,
        year: 2026,
        month: 5,
      );
      expect(result, 0);
    });

    test('mois exactement égal au mois de départ → mensualité déduite', () {
      final property = _property(
        loanPrincipalCents: 20000000,
        loanRateBps: 350,
        loanDurationMonths: 240,
        loanStartDate: DateTime(2026, 6, 15),
      );

      final result = loanMonthlyPaymentForMonthCents(
        property: property,
        year: 2026,
        month: 6,
      );
      expect(result, greaterThan(0));
    });

    test('mois postérieur à la dernière échéance → 0', () {
      // Départ janvier 2020, durée 12 mois → dernière échéance décembre 2020.
      final property = _property(
        loanPrincipalCents: 12000000,
        loanRateBps: 0,
        loanDurationMonths: 12,
        loanStartDate: DateTime(2020, 1, 1),
      );

      // Dernière échéance (décembre 2020) → toujours déduite.
      expect(
        loanMonthlyPaymentForMonthCents(
          property: property,
          year: 2020,
          month: 12,
        ),
        greaterThan(0),
      );

      // Le mois suivant (janvier 2021) → prêt soldé, rien déduit.
      expect(
        loanMonthlyPaymentForMonthCents(
          property: property,
          year: 2021,
          month: 1,
        ),
        0,
      );
    });

    test('loanStartDate absent → fenêtre indéterminée, rien déduit même si '
        'le montant serait calculable', () {
      final property = _property(
        loanPrincipalCents: 20000000,
        loanRateBps: 350,
        loanDurationMonths: 240,
        // loanStartDate volontairement absent.
      );

      final result = loanMonthlyPaymentForMonthCents(
        property: property,
        year: 2026,
        month: 6,
      );
      expect(result, 0);
    });
  });

  group('loanMonthlyPaymentForMonthCents — override prioritaire', () {
    test('loanMonthlyPaymentOverrideCents prioritaire sur le calcul, '
        'comme computeSnapshotForProperty', () {
      final property = _property(
        loanPrincipalCents: 20000000,
        loanRateBps: 350,
        loanDurationMonths: 240,
        loanStartDate: DateTime(2024, 1, 1),
        loanMonthlyPaymentOverrideCents: 123456,
      );

      final result = loanMonthlyPaymentForMonthCents(
        property: property,
        year: 2026,
        month: 3,
      );
      expect(result, 123456);
    });

    test('override sans durée connue → fenêtre ouverte indéfiniment à '
        'partir du départ (même logique que le KPI, jamais bornée dans le '
        'temps sans durée)', () {
      final property = _property(
        loanStartDate: DateTime(2020, 1, 1),
        loanMonthlyPaymentOverrideCents: 50000,
      );

      expect(
        loanMonthlyPaymentForMonthCents(
          property: property,
          year: 2030,
          month: 1,
        ),
        50000,
      );
      expect(
        loanMonthlyPaymentForMonthCents(
          property: property,
          year: 2019,
          month: 12,
        ),
        0,
      );
    });
  });

  group('sumLoanMonthlyPaymentCentsForMonth — agrégation multi-biens', () {
    test('somme les mensualités de plusieurs biens, ignore ceux hors '
        'fenêtre ou sans prêt', () {
      final activeLoan = _property(
        id: 'p-active',
        loanPrincipalCents: 12000000,
        loanRateBps: 0,
        loanDurationMonths: 12,
        loanStartDate: DateTime(2026, 1, 1),
      );
      final noLoan = _property(id: 'p-no-loan');
      final futureLoan = _property(
        id: 'p-future',
        loanPrincipalCents: 6000000,
        loanRateBps: 0,
        loanDurationMonths: 12,
        loanStartDate: DateTime(2027, 1, 1),
      );

      final expectedActive = computeLoanMonthlyPaymentCents(
        principalCents: 12000000,
        rateBps: 0,
        durationMonths: 12,
        insuranceBps: 0,
      );

      final result = sumLoanMonthlyPaymentCentsForMonth(
        properties: [activeLoan, noLoan, futureLoan],
        year: 2026,
        month: 6,
      );
      expect(result, expectedActive);
    });

    test('liste de biens vide → 0', () {
      final result = sumLoanMonthlyPaymentCentsForMonth(
        properties: const [],
        year: 2026,
        month: 6,
      );
      expect(result, 0);
    });
  });
}
