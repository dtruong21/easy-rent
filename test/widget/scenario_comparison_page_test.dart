/// Tests widget pour [ScenarioComparisonPage] (FEAT-055).
///
/// Couvre les AC #1, #2, #5 : rendu paid + KPIs, gate free/anon, résilience
/// aux ids manquants (soft-delete en cours de session).
library;

import 'package:easyrent/core/config/store_billing.dart';
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

  group('ScenarioComparisonPage — responsive mobile (cartes, 2026-07-26)', () {
    testWidgets(
      'téléphone 390 px — toutes les valeurs des 2 scénarios visibles '
      'sans interaction (pas de dépliage)',
      (tester) async {
        tester.view.physicalSize = const Size(390, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

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

        // Plus aucun ExpansionTile : rien à déplier pour voir les valeurs.
        expect(find.byType(ExpansionTile), findsNothing);

        // Une Card par KPI (6), chacune listant les 2 scénarios d'emblée.
        expect(find.byType(Card), findsNWidgets(6));

        // Les 6 libellés KPI sont visibles sans interaction.
        for (final label in const [
          'Rendement brut',
          'Rendement net',
          'Cash-flow mensuel',
          'Coût total crédit',
          'Apport requis',
          "Effort d'épargne",
        ]) {
          expect(find.text(label), findsOneWidget);
        }

        // Le nom de chaque scénario apparaît une fois par carte KPI (6),
        // « Bravo » apparaît en plus une fois dans la rangée de chips
        // d'en-tête (nom seul, pas de scénario de référence) : 6 + 1 = 7.
        // « Alpha » (référence) porte le suffixe « · Référence » dans la
        // chip d'en-tête (chaîne composée, ne matche pas 'Alpha' seul) : 6.
        expect(find.text('Alpha'), findsNWidgets(6));
        expect(find.text('Bravo'), findsNWidgets(7));

        // Puce de référence (rangée de chips d'en-tête) toujours visible
        // sans interaction — « Alpha · Référence ».
        expect(find.textContaining('Référence'), findsOneWidget);

        expect(tester.takeException(), isNull);
      },
    );

    for (final width in const [360.0, 390.0, 768.0, 1280.0]) {
      for (final scenarioCount in const [2, 3]) {
        testWidgets(
          'largeur ${width.toInt()} px, $scenarioCount scénarios → aucun '
          'scroll horizontal ni overflow',
          (tester) async {
            tester.view.physicalSize = Size(width, 1400);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            final scenarios = [
              _scenario(id: 'A', name: 'Alpha'),
              _scenario(id: 'B', name: 'Bravo'),
              if (scenarioCount == 3) _scenario(id: 'C', name: 'Charlie'),
            ];
            final ids = scenarios.map((s) => s.id).join(',');

            await tester.pumpWidget(
              _buildRouter(
                scenarios: scenarios,
                tier: SubscriptionTier.paid,
                initialLocation: '/simulator/compare?ids=$ids',
              ),
            );
            await tester.pumpAndSettle();

            // Aucune exception de rendu (débordement RenderFlex, etc.).
            expect(tester.takeException(), isNull);

            // Aucun scroll horizontal résiduel (le scroll vertical de la
            // page reste normal, seul scrollDirection == Axis.horizontal
            // est prohibé).
            expect(
              find.byWidgetPredicate(
                (w) =>
                    w is SingleChildScrollView &&
                    w.scrollDirection == Axis.horizontal,
              ),
              findsNothing,
            );
          },
        );
      }
    }
  });

  group('ScenarioComparisonPage — app store (iOS/Android)', () {
    setUp(() => debugIsStoreAppOverride = true);
    tearDown(() => debugIsStoreAppOverride = false);

    testWidgets(
      'free tier → écran verrouillé sans CTA vers /pro (aucun achat hors store)',
      (tester) async {
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
        expect(find.text('Passer à Pro'), findsNothing);
        expect(find.byType(FilledButton), findsNothing);
      },
    );

    testWidgets('achat intégré actif → CTA vers /pro présent', (tester) async {
      debugInAppPurchaseEnabledOverride = true;
      addTearDown(() => debugInAppPurchaseEnabledOverride = null);

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
      expect(find.text('Passer à Pro'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
    });
  });
}
