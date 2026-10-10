/// Tests unitaires pour les KPI du dashboard.
library;

import 'package:easyrent/features/dashboard/domain/dashboard_kpi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LoyersMoisKpi', () {
    test('equality — mêmes valeurs', () {
      const kpi1 = LoyersMoisKpi(encaissedCents: 85000, dueCents: 90000);
      const kpi2 = LoyersMoisKpi(encaissedCents: 85000, dueCents: 90000);
      expect(kpi1, equals(kpi2));
    });

    test('inequality — valeurs différentes', () {
      const kpi1 = LoyersMoisKpi(encaissedCents: 85000, dueCents: 90000);
      const kpi2 = LoyersMoisKpi(encaissedCents: 0, dueCents: 90000);
      expect(kpi1, isNot(equals(kpi2)));
    });

    test('encaissé == dû → pas de retard', () {
      const kpi = LoyersMoisKpi(encaissedCents: 90000, dueCents: 90000);
      expect(kpi.encaissedCents >= kpi.dueCents, isTrue);
    });

    test('encaissé < dû → retard', () {
      const kpi = LoyersMoisKpi(encaissedCents: 50000, dueCents: 90000);
      expect(kpi.encaissedCents < kpi.dueCents, isTrue);
    });

    test('zéros', () {
      const kpi = LoyersMoisKpi(encaissedCents: 0, dueCents: 0);
      expect(kpi.encaissedCents, 0);
      expect(kpi.dueCents, 0);
    });
  });

  group('RetardsKpi', () {
    test('count 0 → pas de retard', () {
      const kpi = RetardsKpi(count: 0);
      expect(kpi.count, 0);
    });

    test('count > 0 → retards présents', () {
      const kpi = RetardsKpi(count: 3);
      expect(kpi.count > 0, isTrue);
    });

    test('equality', () {
      const kpi1 = RetardsKpi(count: 2);
      const kpi2 = RetardsKpi(count: 2);
      expect(kpi1, equals(kpi2));
    });
  });

  group('DocsPendingKpi', () {
    test('count = 0 → aucun document en attente', () {
      const kpi = DocsPendingKpi(count: 0);
      expect(kpi.count, 0);
    });

    test('count = 5 → 5 documents en attente', () {
      const kpi = DocsPendingKpi(count: 5);
      expect(kpi.count, 5);
    });
  });
}
