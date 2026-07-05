/// Tests unitaires pour [MonthlyAmount].
library;

import 'package:easyrent/features/dashboard/domain/monthly_amount.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MonthlyAmount', () {
    test('construction et champs', () {
      const m = MonthlyAmount(
        year: 2026,
        month: 6,
        encaissedCents: 85000,
        dueCents: 90000,
      );
      expect(m.year, 2026);
      expect(m.month, 6);
      expect(m.encaissedCents, 85000);
      expect(m.dueCents, 90000);
    });

    test('equality', () {
      const m1 = MonthlyAmount(
        year: 2026,
        month: 1,
        encaissedCents: 0,
        dueCents: 0,
      );
      const m2 = MonthlyAmount(
        year: 2026,
        month: 1,
        encaissedCents: 0,
        dueCents: 0,
      );
      expect(m1, equals(m2));
    });

    test('inequality — mois différent', () {
      const m1 = MonthlyAmount(
        year: 2026,
        month: 1,
        encaissedCents: 0,
        dueCents: 0,
      );
      const m2 = MonthlyAmount(
        year: 2026,
        month: 2,
        encaissedCents: 0,
        dueCents: 0,
      );
      expect(m1, isNot(equals(m2)));
    });

    test('zéros — état initial', () {
      const m = MonthlyAmount(
        year: 2026,
        month: 3,
        encaissedCents: 0,
        dueCents: 0,
      );
      expect(m.encaissedCents, 0);
      expect(m.dueCents, 0);
    });

    test('copyWith — modifie un seul champ', () {
      const m = MonthlyAmount(
        year: 2026,
        month: 6,
        encaissedCents: 0,
        dueCents: 90000,
      );
      final updated = m.copyWith(encaissedCents: 80000);
      expect(updated.encaissedCents, 80000);
      expect(updated.dueCents, 90000);
      expect(updated.year, 2026);
    });
  });
}
