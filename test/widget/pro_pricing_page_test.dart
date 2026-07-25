/// Tests widget de [ProPricingPage] (`/pro`).
///
/// `Env.subscriptionsEnabled` est un `bool.fromEnvironment` (même pattern
/// que `Env.isProd`, cf. `test/widget/profile_page_test.dart` — « APP_ENV
/// absent en test → défaut 'dev' ») : sa valeur est figée à la compilation
/// et ne peut pas être basculée à l'exécution dans un même run de tests.
/// Ce fichier couvre donc l'état **par défaut `false`** (freemium MVP,
/// juillet 2026 — cf. `lib/core/config/env.dart`), qui est celui exercé par
/// `flutter test` en CI : checkout Stripe masqué, capture d'intérêt
/// affichée à la place. Le chemin `true` (bouton « S'abonner » → Stripe,
/// inchangé depuis FEAT-044e) redevient actif dès que le flag est activé au
/// build (`--dart-define=SUBSCRIPTIONS_ENABLED=true`) — pas de nouvelle
/// branche de code, seule cette condition en dépend
/// (`lib/features/paid_plan/presentation/pro_pricing_page.dart`).
library;

import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/features/auth/data/landlord_tier_repository.dart';
import 'package:easyrent/features/auth/domain/subscription_tier.dart';
import 'package:easyrent/features/paid_plan/application/paid_plan_interest_controller.dart';
import 'package:easyrent/features/paid_plan/data/paid_plan_interest_repository.dart';
import 'package:easyrent/features/paid_plan/presentation/pro_pricing_page.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
  required PaidPlanInterestRepository paidPlanRepo,
}) => ProviderScope(
  overrides: [
    landlordTierProvider.overrideWith(
      (ref) => Stream.value(LandlordTierSnapshot(tier: tier)),
    ),
    paidPlanInterestRepositoryProvider.overrideWithValue(paidPlanRepo),
  ],
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    locale: const Locale('fr'),
    supportedLocales: supportedLocales,
    home: const ProPricingPage(),
  ),
);

void main() {
  group('ProPricingPage — subscriptionsEnabled=false (défaut freemium)', () {
    testWidgets(
      'tier free — pas de bouton Stripe, badge + notify-me affichés',
      (tester) async {
        await tester.pumpWidget(
          _buildPage(
            tier: SubscriptionTier.free,
            paidPlanRepo: _FakePaidPlanInterestRepo(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('btn_pro_subscribe')), findsNothing);
        expect(find.text('S\'abonner'), findsNothing);
        expect(
          find.byKey(const Key('txt_pro_coming_soon_badge')),
          findsOneWidget,
        );
        expect(find.text('Bientôt disponible'), findsOneWidget);
        expect(find.byKey(const Key('btn_pro_notify_me')), findsOneWidget);
        expect(find.text('Me prévenir du lancement'), findsOneWidget);
      },
    );

    testWidgets(
      'tap notify-me → markInterest(pro_pricing_page) + bouton verrouillé',
      (tester) async {
        final repo = _FakePaidPlanInterestRepo();
        await tester.pumpWidget(
          _buildPage(tier: SubscriptionTier.free, paidPlanRepo: repo),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn_pro_notify_me')));
        await tester.pumpAndSettle();

        expect(repo.capturedFeatures, [proPricingInterestKey]);
        expect(find.text('Vous serez prévenu au lancement'), findsOneWidget);

        final btn = tester.widget<FilledButton>(
          find.byKey(const Key('btn_pro_notify_me')),
        );
        expect(btn.onPressed, isNull);
      },
    );

    testWidgets('erreur repo → pas de faux succès, bouton retentable', (
      tester,
    ) async {
      final repo = _FakePaidPlanInterestRepo()
        ..error = Exception('permission-denied');
      await tester.pumpWidget(
        _buildPage(tier: SubscriptionTier.free, paidPlanRepo: repo),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_pro_notify_me')));
      await tester.pumpAndSettle();

      expect(find.text('Me prévenir du lancement'), findsOneWidget);
      expect(
        find.textContaining('Impossible d\'enregistrer votre intérêt'),
        findsOneWidget,
      );

      final btn = tester.widget<FilledButton>(
        find.byKey(const Key('btn_pro_notify_me')),
      );
      expect(btn.onPressed, isNotNull);
    });

    testWidgets(
      'tier paid — « Abonnement actif », ni bouton Stripe ni notify-me',
      (tester) async {
        await tester.pumpWidget(
          _buildPage(
            tier: SubscriptionTier.paid,
            paidPlanRepo: _FakePaidPlanInterestRepo(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Abonnement actif'), findsOneWidget);
        expect(find.byKey(const Key('btn_pro_subscribe')), findsNothing);
        expect(find.byKey(const Key('btn_pro_notify_me')), findsNothing);
      },
    );
  });
}
