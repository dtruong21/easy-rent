/// Tests de [PlanLevel.fromRaw] — dérivation client du palier commercial
/// (FEAT-056 §1.4/§1.5, invariants I1/I3/I4).
library;

import 'package:easyrent/features/auth/domain/plan_level.dart';
import 'package:easyrent/features/auth/domain/subscription_tier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlanLevel.fromRaw', () {
    test('raw connu + tier paid → le palier correspondant', () {
      expect(
        PlanLevel.fromRaw('ultra', tier: SubscriptionTier.paid),
        PlanLevel.ultra,
      );
      expect(
        PlanLevel.fromRaw('max', tier: SubscriptionTier.paid),
        PlanLevel.max,
      );
      expect(
        PlanLevel.fromRaw('pro', tier: SubscriptionTier.paid),
        PlanLevel.pro,
      );
    });

    test('raw inconnu + tier paid → pro (fail-UP, I4 — JAMAIS anonymous)', () {
      expect(
        PlanLevel.fromRaw('quantum', tier: SubscriptionTier.paid),
        PlanLevel.pro,
      );
    });

    test('raw null + tier paid → pro (grandfathering, I3)', () {
      expect(
        PlanLevel.fromRaw(null, tier: SubscriptionTier.paid),
        PlanLevel.pro,
      );
    });

    test('tier free → null quel que soit raw (invariant I1)', () {
      expect(PlanLevel.fromRaw('pro', tier: SubscriptionTier.free), isNull);
      expect(PlanLevel.fromRaw(null, tier: SubscriptionTier.free), isNull);
      expect(PlanLevel.fromRaw('quantum', tier: SubscriptionTier.free), isNull);
    });

    test('tier anonymous → null quel que soit raw (invariant I1)', () {
      expect(
        PlanLevel.fromRaw('pro', tier: SubscriptionTier.anonymous),
        isNull,
      );
      expect(PlanLevel.fromRaw(null, tier: SubscriptionTier.anonymous), isNull);
    });
  });
}
