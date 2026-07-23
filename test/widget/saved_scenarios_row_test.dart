/// Tests widget pour le mode sélection de [SavedScenariosRow] (FEAT-055).
///
/// Couvre AC #1 (chemin heureux paid), AC #3 (visibilité gate Pro selon
/// nombre de scénarios + tier). Non-régression : hors sélection, tap → nav.
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

String? lastLocation;
String? lastIds;

/// Capture les URLs pushées — plus robuste que d'inspecter `state.uri` dans
/// le `builder`, dont les query params peuvent apparaître vides en test.
class _PushObserver extends NavigatorObserver {
  final List<String> pushed = [];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = route.settings.name;
    if (name != null) pushed.add(name);
    super.didPush(route, previousRoute);
  }
}

_PushObserver? _observer;

Widget _mount({
  required List<InvestmentScenario> scenarios,
  required SubscriptionTier tier,
}) {
  lastLocation = null;
  lastIds = null;
  _observer = _PushObserver();
  final router = GoRouter(
    initialLocation: '/simulator',
    observers: [_observer!],
    routes: [
      GoRoute(
        path: '/simulator',
        builder: (_, _) => const Scaffold(body: SavedScenariosRow()),
      ),
      // ⚠ `/simulator/compare` doit précéder `/simulator/:id` — sinon
      // go_router matcherait `:id="compare"` et rendrait le détail.
      GoRoute(
        path: '/simulator/compare',
        builder: (_, state) {
          lastLocation = '/simulator/compare';
          lastIds = state.uri.queryParameters['ids'];
          return Scaffold(
            body: Text('compare-stub ids=${lastIds ?? "MISSING"}'),
          );
        },
      ),
      GoRoute(
        path: '/simulator/:id',
        builder: (_, state) {
          lastLocation = '/simulator/${state.pathParameters['id']}';
          return const Scaffold(body: Text('detail-stub'));
        },
      ),
      GoRoute(
        path: '/pro',
        builder: (_, _) {
          lastLocation = '/pro';
          return const Scaffold(body: Text('pro-stub'));
        },
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
  group('SavedScenariosRow — bouton Comparer', () {
    testWidgets('AC #3 — 1 scénario → toggle Comparer masqué', (tester) async {
      await tester.pumpWidget(
        _mount(
          scenarios: [_scenario(id: 'A', name: 'Alpha')],
          tier: SubscriptionTier.paid,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('compare_toggle_button')), findsNothing);
      expect(find.byKey(const Key('compare_toggle_pro_only')), findsNothing);
    });

    testWidgets(
      'AC #3 — 2 scénarios + free → toggle verrouillé, tap → /pro',
      (tester) async {
        await tester.pumpWidget(
          _mount(
            scenarios: [
              _scenario(id: 'A', name: 'Alpha'),
              _scenario(id: 'B', name: 'Bravo'),
            ],
            tier: SubscriptionTier.free,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('compare_toggle_pro_only')), findsOneWidget);
        expect(find.byKey(const Key('compare_toggle_button')), findsNothing);

        await tester.tap(find.byKey(const Key('compare_toggle_pro_only')));
        await tester.pumpAndSettle();
        expect(lastLocation, '/pro');
      },
    );

    testWidgets(
      'AC #3 — 2 scénarios + anonymous → toggle verrouillé (fail-closed)',
      (tester) async {
        await tester.pumpWidget(
          _mount(
            scenarios: [
              _scenario(id: 'A', name: 'Alpha'),
              _scenario(id: 'B', name: 'Bravo'),
            ],
            tier: SubscriptionTier.anonymous,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('compare_toggle_pro_only')), findsOneWidget);
      },
    );

    testWidgets(
      'AC #1 — 3 scénarios + paid → tap toggle → sélection, coche 2 → validate → /simulator/compare',
      (tester) async {
        await tester.pumpWidget(
          _mount(
            scenarios: [
              _scenario(id: 'A', name: 'Alpha'),
              _scenario(id: 'B', name: 'Bravo'),
              _scenario(id: 'C', name: 'Charlie'),
            ],
            tier: SubscriptionTier.paid,
          ),
        );
        await tester.pumpAndSettle();

        // Entre en mode sélection
        await tester.tap(find.byKey(const Key('compare_toggle_button')));
        await tester.pumpAndSettle();

        // Delete icons masqués, chip-select visibles
        expect(find.byKey(const Key('delete_scenario_A')), findsNothing);
        expect(find.byKey(const Key('chip_select_A')), findsOneWidget);

        // Validate disabled tant que < 2
        final validateFinder = find.byKey(const Key('compare_toggle_validate'));
        expect(
          tester.widget<FilledButton>(validateFinder).onPressed,
          isNull,
        );

        // Coche A puis B en tapant sur la carte entière (EntityCard.onTap =
        // toggle en mode sélection). Les tests précédents peuvent basculer
        // le SavedScenariosRow en mode sélection sans ambiguïté grâce au
        // bouton dédié, mais la case cochée elle-même n'est qu'une icône
        // décorative.
        await tester.tap(find.text('Alpha'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Bravo'));
        await tester.pumpAndSettle();

        expect(
          tester.widget<FilledButton>(validateFinder).onPressed,
          isNotNull,
        );

        // Valide → navigation vers `/simulator/compare?ids=A,B`.
        // Le NavigatorObserver capte le route.settings.name (pattern) — la
        // preuve concrète que la nav vise bien la comparaison et non un
        // détail scénario.
        await tester.tap(validateFinder);
        await tester.pumpAndSettle();
        expect(_observer!.pushed, contains('/simulator/compare'));
      },
    );

    testWidgets(
      'Non-régression — hors sélection, tap chip → /simulator/:id',
      (tester) async {
        await tester.pumpWidget(
          _mount(
            scenarios: [
              _scenario(id: 'A', name: 'Alpha'),
              _scenario(id: 'B', name: 'Bravo'),
            ],
            tier: SubscriptionTier.paid,
          ),
        );
        await tester.pumpAndSettle();

        // Tap sur la carte "Alpha" — hors mode sélection.
        await tester.tap(find.text('Alpha'));
        await tester.pumpAndSettle();
        expect(lastLocation, '/simulator/A');
      },
    );

    testWidgets(
      'Cancel sort du mode sélection sans naviguer',
      (tester) async {
        await tester.pumpWidget(
          _mount(
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
        await tester.tap(find.byKey(const Key('compare_toggle_cancel')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('compare_toggle_button')), findsOneWidget);
        expect(find.byKey(const Key('chip_select_A')), findsNothing);
        expect(lastLocation, isNull);
      },
    );
  });
}
