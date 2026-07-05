import 'package:easyrent/features/auth/data/landlord_tier_repository.dart';
import 'package:easyrent/features/auth/domain/subscription_tier.dart';
import 'package:easyrent/features/simulator/application/scenario_limit_controller.dart';
import 'package:easyrent/features/simulator/data/investment_scenario_repository.dart';
import 'package:easyrent/features/simulator/domain/investment_scenario.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

InvestmentScenario _scenario(String id) => InvestmentScenario(
  id: id,
  landlordId: 'lld-1',
  name: 'Scénario $id',
  purchasePriceCents: 20000000,
  monthlyRentHcCents: 80000,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

class _FakeListNotifier extends InvestmentScenariosListNotifier {
  _FakeListNotifier(this._scenarios);
  final List<InvestmentScenario> _scenarios;

  @override
  Future<List<InvestmentScenario>> build() async => _scenarios;
}

ProviderContainer _makeContainer({
  required int scenarioCount,
  required SubscriptionTier tier,
}) {
  final scenarios = List.generate(
    scenarioCount,
    (i) => _scenario('scenario-$i'),
  );
  final container = ProviderContainer(
    overrides: [
      // Le scenarioCountProvider est passé en StreamProvider Firestore
      // (fix HIGH review : bypass cross-tab). Les tests overrident le
      // stream directement plutôt que via la liste de scénarios chargée.
      scenarioCountProvider.overrideWith((ref) => Stream.value(scenarioCount)),
      // On garde l'override de investmentScenariosListProvider pour les
      // tests qui liraient encore la liste (aujourd'hui aucun ici, mais
      // pas de coût si l'override reste — Firestore n'est pas touché).
      investmentScenariosListProvider.overrideWith(
        () => _FakeListNotifier(scenarios),
      ),
      landlordTierProvider.overrideWith(
        (ref) => Stream.value(LandlordTierSnapshot(tier: tier)),
      ),
    ],
  );
  return container;
}

void main() {
  group('scenarioLimitForTierProvider', () {
    test('anonymous → 1', () async {
      final container = _makeContainer(
        scenarioCount: 0,
        tier: SubscriptionTier.anonymous,
      );
      addTearDown(container.dispose);
      await container.read(landlordTierProvider.future);
      expect(container.read(scenarioLimitForTierProvider), 1);
    });

    test('free → 3', () async {
      final container = _makeContainer(
        scenarioCount: 0,
        tier: SubscriptionTier.free,
      );
      addTearDown(container.dispose);
      await container.read(landlordTierProvider.future);
      expect(container.read(scenarioLimitForTierProvider), 3);
    });

    test('paid → null (illimité)', () async {
      final container = _makeContainer(
        scenarioCount: 0,
        tier: SubscriptionTier.paid,
      );
      addTearDown(container.dispose);
      await container.read(landlordTierProvider.future);
      expect(container.read(scenarioLimitForTierProvider), isNull);
    });
  });

  group('canSaveAnotherScenarioProvider', () {
    test('anonymous, count=0 → true', () async {
      final container = _makeContainer(
        scenarioCount: 0,
        tier: SubscriptionTier.anonymous,
      );
      addTearDown(container.dispose);
      await container.read(landlordTierProvider.future);
      await container.read(investmentScenariosListProvider.future);
      await container.read(scenarioCountProvider.future);
      expect(container.read(canSaveAnotherScenarioProvider), isTrue);
    });

    test('anonymous, count=1 → false (limite atteinte)', () async {
      final container = _makeContainer(
        scenarioCount: 1,
        tier: SubscriptionTier.anonymous,
      );
      addTearDown(container.dispose);
      await container.read(landlordTierProvider.future);
      await container.read(investmentScenariosListProvider.future);
      await container.read(scenarioCountProvider.future);
      expect(container.read(canSaveAnotherScenarioProvider), isFalse);
    });

    test('free, count=2 → true', () async {
      final container = _makeContainer(
        scenarioCount: 2,
        tier: SubscriptionTier.free,
      );
      addTearDown(container.dispose);
      await container.read(landlordTierProvider.future);
      await container.read(investmentScenariosListProvider.future);
      await container.read(scenarioCountProvider.future);
      expect(container.read(canSaveAnotherScenarioProvider), isTrue);
    });

    test('free, count=3 → false (limite atteinte)', () async {
      final container = _makeContainer(
        scenarioCount: 3,
        tier: SubscriptionTier.free,
      );
      addTearDown(container.dispose);
      await container.read(landlordTierProvider.future);
      await container.read(investmentScenariosListProvider.future);
      await container.read(scenarioCountProvider.future);
      expect(container.read(canSaveAnotherScenarioProvider), isFalse);
    });

    test('paid, count=999 → true (illimité)', () async {
      final container = _makeContainer(
        scenarioCount: 999,
        tier: SubscriptionTier.paid,
      );
      addTearDown(container.dispose);
      await container.read(landlordTierProvider.future);
      await container.read(investmentScenariosListProvider.future);
      await container.read(scenarioCountProvider.future);
      expect(container.read(canSaveAnotherScenarioProvider), isTrue);
    });
  });

  group('scenarioCountProvider', () {
    test('reflète la longueur de la liste chargée', () async {
      final container = _makeContainer(
        scenarioCount: 2,
        tier: SubscriptionTier.free,
      );
      addTearDown(container.dispose);
      await container.read(investmentScenariosListProvider.future);
      await container.read(scenarioCountProvider.future);
      expect(container.read(scenarioCountProvider).valueOrNull, 2);
    });
  });
}
