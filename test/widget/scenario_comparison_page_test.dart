/// Tests widget pour [ScenarioComparisonPage] (FEAT-055).
///
/// Couvre les AC #1, #2, #5 : rendu paid + KPIs, gate free/anon, résilience
/// aux ids manquants (soft-delete en cours de session).
library;

import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/features/auth/data/landlord_tier_repository.dart';
import 'package:easyrent/features/auth/domain/subscription_tier.dart';
import 'package:easyrent/features/simulator/data/investment_scenario_repository.dart';
import 'package:easyrent/features/simulator/domain/investment_scenario.dart';
import 'package:easyrent/features/simulator/presentation/scenario_comparison_page.dart';
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

Widget _buildRouter({
  required List<InvestmentScenario> scenarios,
  required SubscriptionTier tier,
  required String initialLocation,
}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/simulator',
        builder: (_, _) => const Scaffold(body: Text('simulator-stub')),
      ),
      GoRoute(
        path: '/simulator/compare',
        builder: (_, state) {
          final raw = state.uri.queryParameters['ids'] ?? '';
          final ids = raw
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toSet()
              .take(3)
              .toList(growable: false);
          return ScenarioComparisonPage(ids: ids);
        },
      ),
      GoRoute(
        path: '/pro',
        builder: (_, _) => const Scaffold(body: Text('pro-stub')),
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
  group('ScenarioComparisonPage', () {
    testWidgets('AC #1 — paid + 2 scénarios → 6 labels KPI visibles', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildRouter(
          scenarios: [
            _scenario(id: 'A', name: 'Alpha'),
            _scenario(id: 'B', name: 'Bravo'),
          ],
          tier: SubscriptionTier.paid,
          initialLocation: '/simulator/compare?ids=A,B',
        ),
      );
      await tester.pumpAndSettle();

      // Titre AppBar
      expect(find.text('Comparer les scénarios'), findsOneWidget);
      // Noms de scénarios en colonnes
      expect(find.text('Alpha'), findsWidgets);
      expect(find.text('Bravo'), findsWidgets);
      // 6 labels KPI
      expect(find.text('Rendement brut'), findsOneWidget);
      expect(find.text('Rendement net'), findsOneWidget);
      expect(find.text('Cash-flow mensuel'), findsOneWidget);
      expect(find.text('Coût total crédit'), findsOneWidget);
      expect(find.text('Apport requis'), findsOneWidget);
      expect(find.text("Effort d'épargne"), findsOneWidget);
      // Chip « Référence » sur la colonne 0
      expect(find.text('Référence'), findsOneWidget);
      // Pas d'état verrouillé
      expect(
        find.byKey(const Key('scenario_comparison_pro_gated')),
        findsNothing,
      );
    });

    testWidgets('AC #2 — free tier → écran verrouillé, KPIs absents', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildRouter(
          scenarios: [
            _scenario(id: 'A', name: 'Alpha'),
            _scenario(id: 'B', name: 'Bravo'),
          ],
          tier: SubscriptionTier.free,
          initialLocation: '/simulator/compare?ids=A,B',
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('scenario_comparison_pro_gated')),
        findsOneWidget,
      );
      expect(
        find.text('La comparaison de scénarios est réservée au Plan Pro.'),
        findsOneWidget,
      );
      // Aucun KPI rendu
      expect(find.text('Rendement brut'), findsNothing);
      expect(find.text('Alpha'), findsNothing);
    });

    testWidgets('AC #2 — anonymous tier → écran verrouillé (fail-closed)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildRouter(
          scenarios: [
            _scenario(id: 'A', name: 'Alpha'),
            _scenario(id: 'B', name: 'Bravo'),
          ],
          tier: SubscriptionTier.anonymous,
          initialLocation: '/simulator/compare?ids=A,B',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('scenario_comparison_pro_gated')),
        findsOneWidget,
      );
    });

    testWidgets('AC #2 — CTA "Passer à Pro" navigue vers /pro', (tester) async {
      await tester.pumpWidget(
        _buildRouter(
          scenarios: [
            _scenario(id: 'A', name: 'Alpha'),
            _scenario(id: 'B', name: 'Bravo'),
          ],
          tier: SubscriptionTier.free,
          initialLocation: '/simulator/compare?ids=A,B',
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Passer à Pro'));
      await tester.pumpAndSettle();

      expect(find.text('pro-stub'), findsOneWidget);
    });

    testWidgets(
      'AC #5 — 3 ids, seuls 2 scénarios présents → 2 colonnes, pas de crash',
      (tester) async {
        await tester.pumpWidget(
          _buildRouter(
            scenarios: [
              _scenario(id: 'A', name: 'Alpha'),
              _scenario(id: 'B', name: 'Bravo'),
              // C absent — a été supprimé en cours de session.
            ],
            tier: SubscriptionTier.paid,
            initialLocation: '/simulator/compare?ids=A,B,C',
          ),
        );
        await tester.pumpAndSettle();

        // La page reste rendue avec les 2 scénarios présents.
        expect(find.text('Alpha'), findsWidgets);
        expect(find.text('Bravo'), findsWidgets);
        expect(find.text('Rendement brut'), findsOneWidget);
        // Aucun état vide affiché : 2 ≥ min.
        expect(
          find.byKey(const Key('scenario_comparison_empty')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'AC #5 — 3 ids mais 0 scénario présent → empty state, CTA retour',
      (tester) async {
        await tester.pumpWidget(
          _buildRouter(
            scenarios: [],
            tier: SubscriptionTier.paid,
            initialLocation: '/simulator/compare?ids=X,Y,Z',
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('scenario_comparison_empty')),
          findsOneWidget,
        );
        expect(
          find.text(
            'Sélectionnez 2 ou 3 scénarios pour lancer une comparaison.',
          ),
          findsOneWidget,
        );

        await tester.tap(find.text('Retour aux scénarios'));
        await tester.pumpAndSettle();
        expect(find.text('simulator-stub'), findsOneWidget);
      },
    );
  });
}
