/// Tests widget de [ProPricingPage] (`/pro`, FEAT-056 PR-6 — 4 offres).
///
/// `Env.subscriptionsEnabled` est un `bool.fromEnvironment` (même pattern
/// que `Env.isProd`) : sa valeur est figée à la compilation et ne peut pas
/// être basculée à l'exécution dans un même run de tests. Ce fichier couvre
/// donc l'état **par défaut `false`** (freemium MVP), qui est celui exercé
/// par `flutter test` en CI : les 3 offres payantes (Pro compris) affichent
/// « Bientôt disponible » + capture d'intérêt au lieu d'un bouton de
/// paiement. Le chemin `true` (Pro achetable) est couvert séparément par les
/// tests de non-purchasabilité de Max/Ultra, qui restent vrais quel que soit
/// `subscriptionsEnabled` (gate par palier, indépendant du gate global) —
/// voir le groupe « Max/Ultra jamais achetables ».
library;

import 'package:easyrent/core/config/store_billing.dart';
import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/core/ui/breakpoints.dart';
import 'package:easyrent/features/auth/data/landlord_tier_repository.dart';
import 'package:easyrent/features/auth/domain/subscription_tier.dart';
import 'package:easyrent/features/paid_plan/application/current_billing_period_provider.dart';
import 'package:easyrent/features/paid_plan/data/paid_plan_interest_repository.dart';
import 'package:easyrent/features/paid_plan/presentation/pro_pricing_page.dart';
import 'package:easyrent/features/paid_plan/presentation/widgets/plan_comparison_table.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FakePaidPlanInterestRepo implements PaidPlanInterestRepository {
  List<String>? capturedFeatures;
  Exception? error;

  @override
  Future<void> markInterest({
    required List<String> features,
    String? email,
  }) async {
    if (error != null) throw error!;
    capturedFeatures = features;
  }
}

Widget _buildPage({
  required SubscriptionTier tier,
  String? planLevel,
  PaidPlanInterestRepository? paidPlanRepo,
  List<Override> extraOverrides = const [],
}) => ProviderScope(
  overrides: [
    ...extraOverrides,
    landlordTierProvider.overrideWith(
      (ref) =>
          Stream.value(LandlordTierSnapshot(tier: tier, planLevel: planLevel)),
    ),
    paidPlanInterestRepositoryProvider.overrideWithValue(
      paidPlanRepo ?? _FakePaidPlanInterestRepo(),
    ),
  ],
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    locale: const Locale('fr'),
    supportedLocales: supportedLocales,
    home: const ProPricingPage(),
  ),
);

/// Fixe la taille de la fenêtre de test (patron `scenario_comparison_page_test.dart`,
/// FEAT-055) — une largeur généreuse en hauteur pour que les 4 cartes soient
/// visibles sans avoir à faire défiler dans les tests d'interaction (le
/// défilement lui-même est couvert par le groupe « responsive »).
void _setWindowSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  // Arrivée directe sur /pro (URL, rechargement, `go`) : pile vide, rien à
  // dépiler — le bouton retour doit quand même exister (repli /profile).
  testWidgets('arrivée directe par URL → le retour mène au profil', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/pro',
      routes: [
        GoRoute(
          path: '/profile',
          builder: (_, _) => const Text('profil', key: Key('stub_profile')),
        ),
        GoRoute(path: '/pro', builder: (_, _) => const ProPricingPage()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          landlordTierProvider.overrideWith(
            (ref) => Stream.value(
              const LandlordTierSnapshot(tier: SubscriptionTier.free),
            ),
          ),
          paidPlanInterestRepositoryProvider.overrideWithValue(
            _FakePaidPlanInterestRepo(),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          locale: const Locale('fr'),
          supportedLocales: supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('app_bar_back')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('stub_profile')), findsOneWidget);
  });

  group('ProPricingPage — 4 cartes toujours rendues', () {
    testWidgets('Gratuit, Pro, Max, Ultra présentes', (tester) async {
      _setWindowSize(tester, const Size(1280, 2200));
      await tester.pumpWidget(_buildPage(tier: SubscriptionTier.free));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('plan_card_free')), findsOneWidget);
      expect(find.byKey(const Key('plan_card_pro')), findsOneWidget);
      expect(find.byKey(const Key('plan_card_max')), findsOneWidget);
      expect(find.byKey(const Key('plan_card_ultra')), findsOneWidget);
      expect(find.text('Gratuit'), findsWidgets);
      expect(find.text('Pro'), findsWidgets);
      expect(find.text('Max'), findsWidgets);
      expect(find.text('Ultra'), findsWidgets);
    });
  });

  group(
    'ProPricingPage — Max/Ultra jamais achetables (critère testable, plan §2.3-b)',
    () {
      testWidgets(
        'aucun bouton de checkout ni de changement de palier pour Max/Ultra, quel que soit le tier',
        (tester) async {
          _setWindowSize(tester, const Size(1280, 2200));
          for (final tier in [SubscriptionTier.free, SubscriptionTier.paid]) {
            await tester.pumpWidget(
              _buildPage(
                tier: tier,
                planLevel: tier == SubscriptionTier.paid ? 'pro' : null,
              ),
            );
            await tester.pumpAndSettle();

            for (final level in ['max', 'ultra']) {
              expect(
                find.byKey(Key('btn_plan_subscribe_$level')),
                findsNothing,
                reason: 'level=$level, tier=$tier',
              );
              expect(
                find.byKey(Key('btn_plan_change_$level')),
                findsNothing,
                reason: 'level=$level, tier=$tier',
              );
              expect(
                find.byKey(Key('btn_plan_notify_$level')),
                findsOneWidget,
                reason: 'level=$level, tier=$tier',
              );
            }
          }
        },
      );

      testWidgets('badge « Bientôt disponible » sur Max et Ultra', (
        tester,
      ) async {
        _setWindowSize(tester, const Size(1280, 2200));
        await tester.pumpWidget(_buildPage(tier: SubscriptionTier.free));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('badge_plan_coming_soon_max')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('badge_plan_coming_soon_ultra')),
          findsOneWidget,
        );
        expect(find.text('Bientôt disponible'), findsNWidgets(3));
      });

      testWidgets('prix marqué indicatif sur Max et Ultra', (tester) async {
        _setWindowSize(tester, const Size(1280, 2200));
        await tester.pumpWidget(_buildPage(tier: SubscriptionTier.free));
        await tester.pumpAndSettle();

        expect(find.text('(indicatif)'), findsNWidgets(2));
      });
    },
  );

  group(
    'ProPricingPage — subscriptionsEnabled=false (gate global, défaut freemium)',
    () {
      testWidgets(
        'tier free — aucun bouton Stripe sur les 3 offres payantes, notify-me partout',
        (tester) async {
          _setWindowSize(tester, const Size(1280, 2200));
          await tester.pumpWidget(_buildPage(tier: SubscriptionTier.free));
          await tester.pumpAndSettle();

          for (final level in ['pro', 'max', 'ultra']) {
            expect(find.byKey(Key('btn_plan_subscribe_$level')), findsNothing);
            expect(find.byKey(Key('btn_plan_notify_$level')), findsOneWidget);
          }
          expect(find.text('Bientôt disponible'), findsNWidgets(3));
        },
      );

      testWidgets(
        'tap notify-me sur Pro → markInterest(pro_pricing_pro) + bouton verrouillé',
        (tester) async {
          _setWindowSize(tester, const Size(1280, 2200));
          final repo = _FakePaidPlanInterestRepo();
          await tester.pumpWidget(
            _buildPage(tier: SubscriptionTier.free, paidPlanRepo: repo),
          );
          await tester.pumpAndSettle();

          await tester.ensureVisible(
            find.byKey(const Key('btn_plan_notify_pro')),
          );
          await tester.tap(find.byKey(const Key('btn_plan_notify_pro')));
          await tester.pumpAndSettle();

          expect(repo.capturedFeatures, ['pro_pricing_pro']);

          final btn = tester.widget<FilledButton>(
            find.byKey(const Key('btn_plan_notify_pro')),
          );
          expect(btn.onPressed, isNull);
        },
      );

      testWidgets('erreur repo → pas de faux succès, bouton retentable', (
        tester,
      ) async {
        _setWindowSize(tester, const Size(1280, 2200));
        final repo = _FakePaidPlanInterestRepo()
          ..error = Exception('permission-denied');
        await tester.pumpWidget(
          _buildPage(tier: SubscriptionTier.free, paidPlanRepo: repo),
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(
          find.byKey(const Key('btn_plan_notify_max')),
        );
        await tester.tap(find.byKey(const Key('btn_plan_notify_max')));
        await tester.pumpAndSettle();

        final btn = tester.widget<FilledButton>(
          find.byKey(const Key('btn_plan_notify_max')),
        );
        expect(btn.onPressed, isNotNull);
      });

      testWidgets(
        'tier paid Pro — « Votre offre actuelle » sur la carte Pro, jamais de bouton Stripe',
        (tester) async {
          _setWindowSize(tester, const Size(1280, 2200));
          await tester.pumpWidget(
            _buildPage(tier: SubscriptionTier.paid, planLevel: 'pro'),
          );
          await tester.pumpAndSettle();

          expect(find.byKey(const Key('btn_plan_current_pro')), findsOneWidget);
          expect(find.text('Votre offre actuelle'), findsOneWidget);
          expect(find.byKey(const Key('btn_plan_subscribe_pro')), findsNothing);
          expect(find.byKey(const Key('btn_plan_notify_pro')), findsNothing);
          // Vente fermée : pas de passage mensuel ↔ annuel non plus.
          expect(
            find.byKey(const Key('btn_plan_switch_period_pro')),
            findsNothing,
          );
        },
      );

      testWidgets('vente fermée → la périodicité facturée n\'est jamais lue '
          '(aucun appel Stripe pour une visite de /pro)', (tester) async {
        _setWindowSize(tester, const Size(1280, 2200));
        var reads = 0;
        await tester.pumpWidget(
          _buildPage(
            tier: SubscriptionTier.paid,
            planLevel: 'pro',
            extraOverrides: [
              currentBillingPeriodProvider.overrideWith((ref) async {
                reads++;
                return 'monthly';
              }),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(reads, 0);
      });

      testWidgets(
        'tier paid Max — carte Max affiche l\'offre actuelle même si Max est '
        'non purchasable (un abonné voit toujours son propre palier)',
        (tester) async {
          _setWindowSize(tester, const Size(1280, 2200));
          await tester.pumpWidget(
            _buildPage(tier: SubscriptionTier.paid, planLevel: 'max'),
          );
          await tester.pumpAndSettle();

          expect(find.byKey(const Key('btn_plan_current_max')), findsOneWidget);
          expect(
            find.byKey(const Key('badge_plan_coming_soon_max')),
            findsNothing,
          );
        },
      );
    },
  );

  group('ProPricingPage — toggle mensuel/annuel', () {
    testWidgets('bascule sur annuel → prix annuel + badge économie affichés', (
      tester,
    ) async {
      _setWindowSize(tester, const Size(1280, 2200));
      await tester.pumpWidget(_buildPage(tier: SubscriptionTier.free));
      await tester.pumpAndSettle();

      expect(find.text('7,99 €'), findsOneWidget);
      expect(find.text('79 €'), findsNothing);

      await tester.tap(find.byKey(const Key('switch_plan_period')));
      await tester.pumpAndSettle();

      expect(find.text('79 €'), findsOneWidget);
      expect(find.text('7,99 €'), findsNothing);
      expect(find.text('2 mois offerts'), findsWidgets);
    });
  });

  group('ProPricingPage — responsive (FEAT-056 §8.1, patron FEAT-055)', () {
    testWidgets('mobile (< 600px) — cartes empilées, pas de tableau', (
      tester,
    ) async {
      _setWindowSize(tester, const Size(390, 3600));
      await tester.pumpWidget(_buildPage(tier: SubscriptionTier.free));
      await tester.pumpAndSettle();

      expect(find.byType(PlanComparisonTable), findsNothing);
      expect(find.byKey(const Key('plan_card_pro')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tablette (600–1024px) — cartes en grille, pas de tableau', (
      tester,
    ) async {
      _setWindowSize(tester, const Size(800, 3600));
      await tester.pumpWidget(_buildPage(tier: SubscriptionTier.free));
      await tester.pumpAndSettle();

      expect(find.byType(PlanComparisonTable), findsNothing);
      expect(find.byKey(const Key('plan_card_ultra')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'desktop (>= ${Breakpoints.tablet}px) — 4 cartes en ligne + tableau comparatif',
      (tester) async {
        _setWindowSize(tester, const Size(1280, 2200));
        await tester.pumpWidget(_buildPage(tier: SubscriptionTier.free));
        await tester.pumpAndSettle();

        expect(find.byType(PlanComparisonTable), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('ProPricingPage — app store (iOS/Android) : ni prix ni achat', () {
    setUp(() => debugIsStoreAppOverride = true);
    tearDown(() => debugIsStoreAppOverride = false);

    for (final (label, tier, planLevel) in [
      ('free', SubscriptionTier.free, null),
      ('paid pro', SubscriptionTier.paid, 'pro'),
    ]) {
      testWidgets('tier $label — message neutre, aucune carte ni bouton', (
        tester,
      ) async {
        _setWindowSize(tester, const Size(1280, 2200));
        await tester.pumpWidget(_buildPage(tier: tier, planLevel: planLevel));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('txt_pro_store_app_unavailable')),
          findsOneWidget,
        );
        // Arrivée directe : retour de repli vers le profil.
        expect(find.byKey(const Key('app_bar_back')), findsOneWidget);
        expect(
          find.text(
            "Les offres payantes ne sont pas encore proposées dans l'application.",
          ),
          findsOneWidget,
        );

        // Ni cartes d'offres, ni bascule mensuel/annuel, ni tableau comparatif.
        for (final id in ['free', 'pro', 'max', 'ultra']) {
          expect(find.byKey(Key('plan_card_$id')), findsNothing);
        }
        expect(find.byKey(const Key('switch_plan_period')), findsNothing);
        expect(find.byType(PlanComparisonTable), findsNothing);

        // Aucun bouton d'achat / de changement d'offre / de capture d'intérêt.
        for (final id in ['pro', 'max', 'ultra']) {
          expect(find.byKey(Key('btn_plan_subscribe_$id')), findsNothing);
          expect(find.byKey(Key('btn_plan_change_$id')), findsNothing);
          expect(find.byKey(Key('btn_plan_notify_$id')), findsNothing);
        }
        expect(find.byType(FilledButton), findsNothing);

        // Aucun prix (€) ni mention du site web.
        expect(find.textContaining('€'), findsNothing);
        expect(find.textContaining('site'), findsNothing);
        expect(find.textContaining('web'), findsNothing);
      });
    }
  });
}
