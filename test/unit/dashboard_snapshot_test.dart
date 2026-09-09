/// Tests unitaires pour [DashboardSnapshot].
library;

import 'package:easyrent/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DashboardSnapshot.empty', () {
    test('factory empty — isOnboarding=true', () {
      final snapshot = DashboardSnapshot.empty(isOnboarding: true);
      expect(snapshot.isOnboarding, isTrue);
      expect(snapshot.loyers.encaissedCents, 0);
      expect(snapshot.loyers.dueCents, 0);
      expect(snapshot.retards.count, 0);
      expect(snapshot.docs.count, 0);
      expect(snapshot.activity, isEmpty);
    });

    test('factory empty — isOnboarding=false', () {
      final snapshot = DashboardSnapshot.empty(isOnboarding: false);
      expect(snapshot.isOnboarding, isFalse);
    });
  });

  group('DashboardSnapshot equality', () {
    test('deux snapshots identiques sont égaux', () {
      final s1 = DashboardSnapshot.empty(isOnboarding: true);
      final s2 = DashboardSnapshot.empty(isOnboarding: true);
      expect(s1, equals(s2));
    });

    test('snapshots différents ne sont pas égaux', () {
      final s1 = DashboardSnapshot.empty(isOnboarding: true);
      final s2 = DashboardSnapshot.empty(isOnboarding: false);
      expect(s1, isNot(equals(s2)));
    });
  });
}
