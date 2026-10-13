import 'package:easyrent/features/dashboard/domain/onboarding_progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OnboardingProgress', () {
    test('isComplete suit hasReceipt', () {
      const notDone = OnboardingProgress(
        hasProperty: true,
        hasTenant: true,
        hasLease: true,
        hasPayment: true,
        hasReceipt: false,
        firstLeaseId: 'l1',
      );
      expect(notDone.isComplete, isFalse);
      expect(notDone.copyWith(hasReceipt: true).isComplete, isTrue);
    });

    test('completedCount compte les étapes vraies', () {
      const p = OnboardingProgress(
        hasProperty: true,
        hasTenant: true,
        hasLease: false,
        hasPayment: false,
        hasReceipt: false,
        firstLeaseId: null,
      );
      expect(p.completedCount, 2);
    });

    test('completedCount = 5 quand tout est fait', () {
      const p = OnboardingProgress(
        hasProperty: true,
        hasTenant: true,
        hasLease: true,
        hasPayment: true,
        hasReceipt: true,
        firstLeaseId: 'l1',
      );
      expect(p.completedCount, 5);
    });
  });
}
