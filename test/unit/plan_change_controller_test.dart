/// Tests unitaires de [PlanChangeController] (FEAT-056 §4.4).
library;

import 'package:easyrent/features/paid_plan/application/plan_change_controller.dart';
import 'package:easyrent/features/paid_plan/data/subscription_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSubscriptionRepository implements SubscriptionRepository {
  _FakeSubscriptionRepository({this.changePlanException});

  final Exception? changePlanException;
  int changePlanCallCount = 0;
  String? lastLevel;
  String? lastPeriod;

  @override
  Future<void> cancel() async {}

  @override
  Future<void> reactivate() async {}

  @override
  Future<void> changePlan({
    required String level,
    required String period,
  }) async {
    changePlanCallCount++;
    lastLevel = level;
    lastPeriod = period;
    if (changePlanException != null) throw changePlanException!;
  }

  @override
  Future<String?> currentBillingPeriod() async =>
      throw UnimplementedError('not exercised by these tests');
}

ProviderContainer _makeContainer(SubscriptionRepository repo) {
  return ProviderContainer(
    overrides: [subscriptionRepositoryProvider.overrideWithValue(repo)],
  );
}

void main() {
  group('PlanChangeController — succès', () {
    test(
      'changePlan(level, period) → true, repo appelé avec les bons paramètres',
      () async {
        final repo = _FakeSubscriptionRepository();
        final container = _makeContainer(repo);
        addTearDown(container.dispose);

        final ok = await container
            .read(planChangeControllerProvider.notifier)
            .changePlan(level: 'ultra', period: 'annual');

        expect(ok, isTrue);
        expect(repo.changePlanCallCount, 1);
        expect(repo.lastLevel, 'ultra');
        expect(repo.lastPeriod, 'annual');
        expect(container.read(planChangeControllerProvider).hasError, isFalse);
      },
    );
  });

  group('PlanChangeController — erreurs mappées', () {
    test('NoActiveWebSubscriptionException → false, error exposée', () async {
      final repo = _FakeSubscriptionRepository(
        changePlanException: const NoActiveWebSubscriptionException(),
      );
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      final ok = await container
          .read(planChangeControllerProvider.notifier)
          .changePlan(level: 'max', period: 'monthly');

      expect(ok, isFalse);
      expect(
        container.read(planChangeControllerProvider).error,
        isA<NoActiveWebSubscriptionException>(),
      );
    });

    test('PriceNotConfiguredException → false, error exposée', () async {
      final repo = _FakeSubscriptionRepository(
        changePlanException: const PriceNotConfiguredException(),
      );
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      final ok = await container
          .read(planChangeControllerProvider.notifier)
          .changePlan(level: 'max', period: 'monthly');

      expect(ok, isFalse);
      expect(
        container.read(planChangeControllerProvider).error,
        isA<PriceNotConfiguredException>(),
      );
    });

    test('erreur générique → false, SubscriptionException exposée', () async {
      final repo = _FakeSubscriptionRepository(
        changePlanException: const SubscriptionException('boom'),
      );
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      final ok = await container
          .read(planChangeControllerProvider.notifier)
          .changePlan(level: 'max', period: 'monthly');

      expect(ok, isFalse);
      expect(
        container.read(planChangeControllerProvider).error,
        isA<SubscriptionException>(),
      );
    });
  });
}
