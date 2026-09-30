/// Tests widget pour la modal de limite de scénarios atteinte (BAILLAN-M1).
library;

import 'package:easyrent/core/config/store_billing.dart';
import 'package:easyrent/features/auth/application/auth_session_provider.dart';
import 'package:easyrent/features/auth/data/landlord_tier_repository.dart';
import 'package:easyrent/features/auth/domain/session_state.dart';
import 'package:easyrent/features/auth/domain/subscription_tier.dart';
import 'package:easyrent/features/paid_plan/data/paid_plan_interest_repository.dart';
import 'package:easyrent/features/simulator/application/scenario_limit_controller.dart';
import 'package:easyrent/features/simulator/data/investment_scenario_repository.dart';
import 'package:easyrent/features/simulator/domain/investment_scenario.dart';
import 'package:easyrent/features/simulator/presentation/simulator_page.dart';
import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

InvestmentScenario _scenario(String id) => InvestmentScenario(
  id: id,
  landlordId: 'lld-1',
  name: 'Scénario $id',
  purchasePriceCents: 20000000,
  monthlyRentHcCents: 80000,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

class _FakeScenarioRepo implements InvestmentScenarioRepository {
  final List<InvestmentScenario> scenarios;
  _FakeScenarioRepo(this.scenarios);

  @override
  Future<List<InvestmentScenario>> list() async => scenarios;

  @override
  Future<InvestmentScenario> getById(String id) => throw UnimplementedError();

  @override
  Future<InvestmentScenario> create({
    required String name,
    required int purchasePriceCents,
    int notaryFeesCents = 0,
    int worksInitialCents = 0,
    bool isNewProperty = false,
    int downPaymentCents = 0,
    int loanPrincipalCents = 0,
    int loanRateBps = 0,
    int loanDurationMonths = 240,
    required int monthlyRentHcCents,
    int propertyTaxAnnualCents = 0,
    int insurancePnoAnnualCents = 0,
    int condoFeesNonRecoverableCents = 0,
    String? notes,
  }) async {
    throw StateError('create should not be reached when limit is hit');
  }

  @override
  Future<InvestmentScenario> update(InvestmentScenario scenario) =>
      throw UnimplementedError();

  @override
  Future<void> softDelete(String id) => throw UnimplementedError();
}

class _FakeListNotifier extends InvestmentScenariosListNotifier {
  _FakeListNotifier(this._scenarios);
  final List<InvestmentScenario> _scenarios;

  @override
  Future<List<InvestmentScenario>> build() async => _scenarios;
}

class _FakePaidPlanInterestRepo implements PaidPlanInterestRepository {
  List<String>? capturedFeatures;

  @override
  Future<void> markInterest({
    required List<String> features,
    String? email,
  }) async {
    capturedFeatures = features;
  }
}

Widget _buildPage({
  required SubscriptionTier tier,
  required List<InvestmentScenario> scenarios,
  required PaidPlanInterestRepository paidPlanRepo,
}) {
  final fakeRepo = _FakeScenarioRepo(scenarios);
  final router = GoRouter(
    initialLocation: '/simulator',
    routes: [
      GoRoute(
        path: '/simulator',
        builder: (context, state) => const SimulatorPage(),
      ),
      GoRoute(
        path: '/signup',
        builder: (context, state) => const Scaffold(body: Text('Signup')),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: Text('Landing')),
      ),
      GoRoute(
        path: '/pro',
        builder: (context, state) => const Scaffold(body: Text('Pro')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      investmentScenarioRepositoryProvider.overrideWithValue(fakeRepo),
      investmentScenariosListProvider.overrideWith(
        () => _FakeListNotifier(scenarios),
      ),
      // scenarioCountProvider est passé en StreamProvider Firestore
      // direct (fix HIGH cross-tab bypass). Les tests overrident le
      // stream avec la longueur de la liste fournie.
      scenarioCountProvider.overrideWith(
        (ref) => Stream.value(scenarios.length),
      ),
      sessionStateProvider.overrideWithValue(
        tier == SubscriptionTier.anonymous
            ? SessionState.anonymous
            : SessionState.fullyAuthenticated,
      ),
      landlordTierProvider.overrideWith(
        (ref) => Stream.value(LandlordTierSnapshot(tier: tier)),
      ),
      paidPlanInterestRepositoryProvider.overrideWithValue(paidPlanRepo),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: supportedLocales,
      locale: const Locale('fr'),
    ),
  );
}

Future<void> _fillMinimalForm(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('field_purchase_price')),
    '200000',
  );
  await tester.enterText(find.byKey(const Key('field_monthly_rent')), '800');
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  group('ScenarioLimitReachedModal — tier anonymous', () {
    testWidgets(
      '1 scénario déjà sauvegardé + tentative de save → modal signup CTA',
      (tester) async {
        final paidPlanRepo = _FakePaidPlanInterestRepo();
        await tester.pumpWidget(
          _buildPage(
            tier: SubscriptionTier.anonymous,
            scenarios: [_scenario('s1')],
            paidPlanRepo: paidPlanRepo,
          ),
        );
        await tester.pumpAndSettle();

        await _fillMinimalForm(tester);
        await tester.ensureVisible(
          find.byKey(const Key('save_scenario_button')),
        );
        await tester.tap(find.byKey(const Key('save_scenario_button')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('scenario_limit_reached_modal')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('scenario_limit_signup_cta')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('scenario_limit_signup_cta')));
        await tester.pumpAndSettle();

        expect(find.text('Signup'), findsOneWidget);
      },
    );
  });

  group('ScenarioLimitReachedModal — tier free', () {
    testWidgets(
      '3 scénarios déjà sauvegardés + tentative de save → modal Passer à Pro CTA',
      (tester) async {
        // Depuis FEAT-044e (75fcbd3), le CTA free renvoie directement vers le
        // checkout Stripe (`/pro`, `scenario_limit_upgrade_cta`) — plus de
        // capture d'intérêt via PaidPlanInterestRepository sur cette modal.
        final paidPlanRepo = _FakePaidPlanInterestRepo();
        await tester.pumpWidget(
          _buildPage(
            tier: SubscriptionTier.free,
            scenarios: [_scenario('s1'), _scenario('s2'), _scenario('s3')],
            paidPlanRepo: paidPlanRepo,
          ),
        );
        await tester.pumpAndSettle();

        await _fillMinimalForm(tester);
        await tester.ensureVisible(
          find.byKey(const Key('save_scenario_button')),
        );
        await tester.tap(find.byKey(const Key('save_scenario_button')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('scenario_limit_reached_modal')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('scenario_limit_upgrade_cta')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('scenario_limit_upgrade_cta')));
        await tester.pumpAndSettle();

        // Modal fermée + navigation vers /pro (checkout Stripe).
        expect(
          find.byKey(const Key('scenario_limit_reached_modal')),
          findsNothing,
        );
        expect(find.text('Pro'), findsOneWidget);
      },
    );
  });

  group('Sous la limite — aucune modal', () {
    testWidgets('tier free avec 2 scénarios → save procède normalement', (
      tester,
    ) async {
      final paidPlanRepo = _FakePaidPlanInterestRepo();
      await tester.pumpWidget(
        _buildPage(
          tier: SubscriptionTier.free,
          scenarios: [_scenario('s1'), _scenario('s2')],
          paidPlanRepo: paidPlanRepo,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('scenario_limit_reached_modal')),
        findsNothing,
      );
    });
  });

  group('ScenarioLimitReachedModal — app store (iOS/Android)', () {
    setUp(() => debugIsStoreAppOverride = true);
    tearDown(() => debugIsStoreAppOverride = false);

    Future<void> triggerLimit(
      WidgetTester tester, {
      required SubscriptionTier tier,
      required List<InvestmentScenario> scenarios,
    }) async {
      await tester.pumpWidget(
        _buildPage(
          tier: tier,
          scenarios: scenarios,
          paidPlanRepo: _FakePaidPlanInterestRepo(),
        ),
      );
      await tester.pumpAndSettle();
      await _fillMinimalForm(tester);
      await tester.ensureVisible(find.byKey(const Key('save_scenario_button')));
      await tester.tap(find.byKey(const Key('save_scenario_button')));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'tier free → modal sans CTA vers /pro, avec bouton de fermeture',
      (tester) async {
        await triggerLimit(
          tester,
          tier: SubscriptionTier.free,
          scenarios: [_scenario('s1'), _scenario('s2'), _scenario('s3')],
        );

        expect(
          find.byKey(const Key('scenario_limit_reached_modal')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('scenario_limit_upgrade_cta')),
          findsNothing,
        );
        expect(find.text('Passer à Pro'), findsNothing);
        // La modale garde son message et sa fermeture.
        expect(find.text('Limite atteinte'), findsOneWidget);
        expect(find.text('Plus tard'), findsOneWidget);

        await tester.tap(find.text('Plus tard'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('scenario_limit_reached_modal')),
          findsNothing,
        );
      },
    );

    testWidgets('tier paid Pro (15/15) → aucun CTA « Passer à Max »', (
      tester,
    ) async {
      await triggerLimit(
        tester,
        tier: SubscriptionTier.paid,
        scenarios: [for (var i = 0; i < 15; i++) _scenario('s$i')],
      );

      expect(
        find.byKey(const Key('scenario_limit_reached_modal')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('scenario_limit_upgrade_cta')), findsNothing);
      expect(find.textContaining('Passer à'), findsNothing);
      expect(find.text('Plus tard'), findsOneWidget);
    });

    testWidgets('tier anonymous → CTA « Créer un compte » inchangé', (
      tester,
    ) async {
      await triggerLimit(
        tester,
        tier: SubscriptionTier.anonymous,
        scenarios: [_scenario('s1')],
      );

      expect(
        find.byKey(const Key('scenario_limit_signup_cta')),
        findsOneWidget,
      );
    });
  });
}
