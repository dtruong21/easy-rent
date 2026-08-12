/// Tests unitaires pour [MonthlyCashflow].
library;

import 'package:easyrent/features/dashboard/domain/monthly_cashflow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MonthlyCashflow', () {
    test('construction et champs', () {
      const m = MonthlyCashflow(
        year: 2026,
        month: 6,
        collectedRentCents: 85000,
        nonRecoverableExpenseCents: 20000,
        hasData: true,
      );
      expect(m.year, 2026);
      expect(m.month, 6);
      expect(m.collectedRentCents, 85000);
      expect(m.nonRecoverableExpenseCents, 20000);
      expect(m.hasData, isTrue);
    });

    test('equality', () {
      const m1 = MonthlyCashflow(
        year: 2026,
        month: 1,
        collectedRentCents: 0,
        nonRecoverableExpenseCents: 0,
        hasData: false,
      );
      const m2 = MonthlyCashflow(
        year: 2026,
        month: 1,
        collectedRentCents: 0,
        nonRecoverableExpenseCents: 0,
        hasData: false,
      );
      expect(m1, equals(m2));
    });

    test('inequality — mois différent', () {
      const m1 = MonthlyCashflow(
        year: 2026,
        month: 1,
        collectedRentCents: 0,
        nonRecoverableExpenseCents: 0,
        hasData: false,
      );
      const m2 = MonthlyCashflow(
        year: 2026,
        month: 2,
        collectedRentCents: 0,
        nonRecoverableExpenseCents: 0,
        hasData: false,
      );
      expect(m1, isNot(equals(m2)));
    });

    test('copyWith — modifie un seul champ', () {
      const m = MonthlyCashflow(
        year: 2026,
        month: 6,
        collectedRentCents: 0,
        nonRecoverableExpenseCents: 90000,
        hasData: true,
      );
      final updated = m.copyWith(collectedRentCents: 80000);
      expect(updated.collectedRentCents, 80000);
      expect(updated.nonRecoverableExpenseCents, 90000);
      expect(updated.year, 2026);
    });

    group('netCents', () {
      test('mois positif : loyers > dépenses → net positif', () {
        const m = MonthlyCashflow(
          year: 2026,
          month: 3,
          collectedRentCents: 85000,
          nonRecoverableExpenseCents: 20000,
          hasData: true,
        );
        expect(m.netCents, 65000);
      });

      test('mois négatif : dépenses > loyers → net négatif', () {
        const m = MonthlyCashflow(
          year: 2026,
          month: 4,
          collectedRentCents: 85000,
          nonRecoverableExpenseCents: 300000,
          hasData: true,
        );
        expect(m.netCents, -215000);
        expect(m.netCents, lessThan(0));
      });

      test('mois exactement équilibré → net zéro (données présentes)', () {
        const m = MonthlyCashflow(
          year: 2026,
          month: 5,
          collectedRentCents: 50000,
          nonRecoverableExpenseCents: 50000,
          hasData: true,
        );
        expect(m.netCents, 0);
        expect(m.hasData, isTrue);
      });

      test('mois sans donnée → net zéro par construction, hasData=false '
          '(distinct du cas équilibré)', () {
        const m = MonthlyCashflow(
          year: 2026,
          month: 6,
          collectedRentCents: 0,
          nonRecoverableExpenseCents: 0,
          hasData: false,
        );
        expect(m.netCents, 0);
        expect(m.hasData, isFalse);
      });
    });
  });
}
