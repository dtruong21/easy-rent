/// Tests widget pour la carte « + Nouvelle simulation » de
/// [SavedScenariosRow].
///
/// Correctif (a) : taper une carte de scénario emmène en mode édition
/// (`/simulator/:id`), sans affordance de retour à un formulaire vierge pour
/// un compte complet (le bouton retour AppBar vise le dashboard). La carte
/// « + Nouvelle simulation », toujours en premier item de la rangée hors
/// mode sélection, comble ce trou en ramenant vers `/simulator`.
library;

import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/features/auth/data/landlord_tier_repository.dart';
import 'package:easyrent/features/auth/domain/subscription_tier.dart';
import 'package:easyrent/features/simulator/data/investment_scenario_repository.dart';
import 'package:easyrent/features/simulator/domain/investment_scenario.dart';
import 'package:easyrent/features/simulator/presentation/widgets/saved_scenarios_row.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

InvestmentScenario _scenario({required String id, required String name}) {
  return InvestmentScenario(
    id: id,
    landlordId: 'lld-1',
    name: name,
    purchasePriceCents: 20000000,
    notaryFeesCents: 1500000,
    loanPrincipalCents: 16000000,
    loanRateBps: 350,
    loanDurationMonths: 240,
    monthlyRentHcCents: 80000,
    propertyTaxAnnualCents: 120000,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

class _FakeListNotifier extends InvestmentScenariosListNotifier {
  _FakeListNotifier(this._scenarios);
  final List<InvestmentScenario> _scenarios;
  @override
  Future<List<InvestmentScenario>> build() async => _scenarios;
}

/// Monte [SavedScenariosRow] comme le ferait `SimulatorPage` en mode édition
/// (`/simulator/:id`) — c'est le cas concret décrit dans le correctif (a) :
/// un compte complet, déjà en train d'éditer un scénario existant, doit
/// pouvoir revenir à un formulaire vierge.
Widget _mountEditMode({
  required List<InvestmentScenario> scenarios,
  required SubscriptionTier tier,
}) {
  final router = GoRouter(
    initialLocation: '/simulator/${scenarios.first.id}',
    routes: [
      GoRoute(
        path: '/simulator',
        builder: (_, _) => const Scaffold(body: Text('new-scenario-form-stub')),
      ),
      GoRoute(
        path: '/simulator/:id',
        builder: (_, _) => const Scaffold(body: SavedScenariosRow()),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      investmentScenariosListProvider.overrideWith(
        () => _FakeListNotifier(scenarios),
      ),
      landlordTierProvider.overrideWith(
        (ref) => Stream.value(LandlordTierSnapshot(tier: tier)),
      ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: supportedLocales,
      locale: const Locale('fr'),
    ),
  );
}

void main() {
  group('SavedScenariosRow — carte + Nouvelle simulation', () {
    testWidgets(
      'toujours visible en premier item, ramène vers /simulator vierge '
      'depuis le mode édition',
      (tester) async {
        await tester.pumpWidget(
          _mountEditMode(
            scenarios: [
              _scenario(id: 'A', name: 'Alpha'),
              _scenario(id: 'B', name: 'Bravo'),
            ],
            tier: SubscriptionTier.paid,
          ),
        );
        await tester.pumpAndSettle();

        // Toujours là malgré l'édition d'un scénario existant.
        expect(find.byKey(const Key('scenario_new_card')), findsOneWidget);
        expect(find.text('Nouvelle simulation'), findsOneWidget);

        await tester.tap(find.byKey(const Key('scenario_new_card')));
        await tester.pumpAndSettle();

        expect(find.text('new-scenario-form-stub'), findsOneWidget);
      },
    );

    testWidgets('masquée en mode sélection (comparaison)', (tester) async {
      await tester.pumpWidget(
        _mountEditMode(
          scenarios: [
            _scenario(id: 'A', name: 'Alpha'),
            _scenario(id: 'B', name: 'Bravo'),
          ],
          tier: SubscriptionTier.paid,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('scenario_new_card')), findsOneWidget);

      await tester.tap(find.byKey(const Key('compare_toggle_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('scenario_new_card')), findsNothing);
    });

    testWidgets('réapparaît après annulation de la sélection', (tester) async {
      await tester.pumpWidget(
        _mountEditMode(
          scenarios: [
            _scenario(id: 'A', name: 'Alpha'),
            _scenario(id: 'B', name: 'Bravo'),
          ],
          tier: SubscriptionTier.paid,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('compare_toggle_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('scenario_new_card')), findsNothing);

      await tester.tap(find.byKey(const Key('compare_toggle_cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('scenario_new_card')), findsOneWidget);
    });
  });
}
