/// Tests unitaires pour [DashboardSnapshot].
library;

import 'package:easyrent/features/dashboard/domain/dashboard_kpi.dart';
import 'package:easyrent/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:easyrent/features/dashboard/domain/onboarding_progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DashboardSnapshot.onboarding', () {
    const progress = OnboardingProgress(
      hasProperty: false,
      hasTenant: false,
      hasLease: false,
      hasPayment: false,
      hasReceipt: false,
      firstLeaseId: null,
    );

    test('factory onboarding — isOnboarding=true et KPI vides', () {
      final snapshot = DashboardSnapshot.onboarding(progress);
      expect(snapshot.isOnboarding, isTrue);
      expect(snapshot.onboarding, progress);
      expect(snapshot.loyers.encaissedCents, 0);
      expect(snapshot.loyers.dueCents, 0);
      expect(snapshot.retards.count, 0);
      expect(snapshot.docs.count, 0);
      expect(snapshot.activity, isEmpty);
    });

    test('snapshot sans onboarding — isOnboarding=false', () {
      final snapshot = DashboardSnapshot(
        loyers: const LoyersMoisKpi(encaissedCents: 0, dueCents: 0),
        retards: const RetardsKpi(count: 0),
        docs: const DocsPendingKpi(count: 0),
        activity: const [],
      );
      expect(snapshot.isOnboarding, isFalse);
      expect(snapshot.onboarding, isNull);
    });
  });

  group('DashboardSnapshot equality', () {
    const progress = OnboardingProgress(
      hasProperty: false,
      hasTenant: false,
      hasLease: false,
      hasPayment: false,
      hasReceipt: false,
      firstLeaseId: null,
    );

    test('deux snapshots identiques sont égaux', () {
      final s1 = DashboardSnapshot.onboarding(progress);
      final s2 = DashboardSnapshot.onboarding(progress);
      expect(s1, equals(s2));
    });

    test('snapshots différents ne sont pas égaux', () {
      final s1 = DashboardSnapshot.onboarding(progress);
      final s2 = DashboardSnapshot(
        loyers: const LoyersMoisKpi(encaissedCents: 0, dueCents: 0),
        retards: const RetardsKpi(count: 0),
        docs: const DocsPendingKpi(count: 0),
        activity: const [],
      );
      expect(s1, isNot(equals(s2)));
    });
  });

  test('isOnboarding dérive de la présence de onboarding', () {
    const progress = OnboardingProgress(
      hasProperty: false,
      hasTenant: false,
      hasLease: false,
      hasPayment: false,
      hasReceipt: false,
      firstLeaseId: null,
    );
    expect(DashboardSnapshot.onboarding(progress).isOnboarding, isTrue);
    expect(
      DashboardSnapshot(
        loyers: const LoyersMoisKpi(encaissedCents: 0, dueCents: 0),
        retards: const RetardsKpi(count: 0),
        docs: const DocsPendingKpi(count: 0),
        activity: const [],
      ).isOnboarding,
      isFalse,
    );
  });
}
