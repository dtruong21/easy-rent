/// Tests widget de l'écran d'achat des apps iOS/Android sur `/pro`
/// (FEAT-044e lot 3) : [ProStorePaywall] monté par [ProPricingPage] quand
/// l'app est une app store ET que l'achat intégré est actif.
///
/// Le faux service journalise les appels ([FakeStoreBillingService.calls]) ;
/// le palier du compte est un flux broadcast piloté par le test (`tier`).
///
/// `pumpAndSettle` n'est utilisé que sur des vues sans animation : la vue
/// « Activation en cours… » et les chargements montrent un
/// `CircularProgressIndicator` qui anime sans fin (→ `pump` seulement).
library;

import 'dart:async';

import 'package:easyrent/core/config/store_billing.dart';
import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:easyrent/features/auth/data/landlord_tier_repository.dart';
import 'package:easyrent/features/auth/domain/subscription_tier.dart';
import 'package:easyrent/features/paid_plan/domain/store_billing_models.dart';
import 'package:easyrent/features/paid_plan/data/store_billing_service.dart';
import 'package:easyrent/features/paid_plan/presentation/pro_pricing_page.dart';
import 'package:easyrent/features/paid_plan/presentation/widgets/plan_card.dart';
import 'package:easyrent/features/paid_plan/presentation/widgets/pro_store_paywall.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fake_store_billing_service.dart';

/// Repository d'auth réduit à `currentUser` (le reste n'est jamais appelé).
class _FakeAuthRepo implements AuthRepository {
  _FakeAuthRepo(this.currentUser);

  @override
  final User? currentUser;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _free = LandlordTierSnapshot(tier: SubscriptionTier.free);
const _pro = LandlordTierSnapshot(
  tier: SubscriptionTier.paid,
  planLevel: 'pro',
  proStore: 'app_store',
);

// Prix volontairement différents des prix web (7,99 € / 79 €).
const _offer = ProStoreOffer(
  monthly: ProStorePackage(
    period: StoreBillingPeriod.monthly,
    priceString: '8,49 €',
  ),
  annual: ProStorePackage(
    period: StoreBillingPeriod.annual,
    priceString: '84,99 €',
  ),
);

Finder _key(String key) => find.byKey(Key(key));

void main() {
  late FakeStoreBillingService fake;
  late StreamController<LandlordTierSnapshot?> tier;

  setUp(() {
    debugIsStoreAppOverride = true;
    debugInAppPurchaseEnabledOverride = true;
    fake = FakeStoreBillingService()..offer = _offer;
    tier = StreamController<LandlordTierSnapshot?>.broadcast();
  });

  tearDown(() async {
    debugIsStoreAppOverride = false;
    debugInAppPurchaseEnabledOverride = null;
    await tier.close();
  });

  /// Monte `/pro` dans une fenêtre haute (tout est visible sans défiler),
  /// puis, si [snapshot] est fourni, l'émet comme palier du compte. Le
  /// `pumpWidget` passe AVANT `tier.add` : le provider doit déjà être abonné
  /// au flux broadcast.
  Future<void> mount(
    WidgetTester tester, {
    LandlordTierSnapshot? snapshot,
  }) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: '/pro',
      routes: [
        GoRoute(path: '/pro', builder: (_, _) => const ProPricingPage()),
        GoRoute(
          path: '/profile',
          builder: (_, _) => const Text('profile-page'),
        ),
        GoRoute(path: '/terms', builder: (_, _) => const Text('terms-page')),
        GoRoute(
          path: '/privacy',
          builder: (_, _) => const Text('privacy-page'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storeBillingServiceProvider.overrideWithValue(fake),
          landlordTierProvider.overrideWith((ref) => tier.stream),
          authRepositoryProvider.overrideWithValue(
            _FakeAuthRepo(MockUser(uid: 'u1', isEmailVerified: true)),
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
    if (snapshot == null) return;
    tier.add(snapshot);
    await tester.pump();
    await tester.pumpAndSettle();
  }

  /// Laisse l'appel asynchrone du faux (purchase / restore) se résoudre puis
  /// reconstruit. Sans `pumpAndSettle` : la vue d'activation anime sans fin.
  Future<void> afterAction(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  List<String> purchaseCalls() =>
      fake.calls.where((c) => c.startsWith('purchase')).toList();

  /// Les trois boutons de l'écran d'offres sont désactivés (`onPressed` nul).
  void expectOfferButtons(WidgetTester tester, {required bool enabled}) {
    for (final key in [
      'btn_store_buy_annual',
      'btn_store_buy_monthly',
      'btn_store_restore',
    ]) {
      final button = tester.widget<ButtonStyleButton>(_key(key));
      expect(
        button.onPressed != null,
        enabled,
        reason: '$key ${enabled ? 'actif' : 'désactivé'}',
      );
    }
  }

  testWidgets('offres : prix du store, restauration, mentions légales, '
      'ni Max/Ultra ni prix web', (tester) async {
    await mount(tester, snapshot: _free);

    expect(
      find.descendant(
        of: _key('btn_store_buy_monthly'),
        matching: find.textContaining('8,49 €'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _key('btn_store_buy_annual'),
        matching: find.textContaining('84,99 €'),
      ),
      findsOneWidget,
    );
    expect(_key('btn_store_restore'), findsOneWidget);
    expect(_key('txt_store_legal_notice'), findsOneWidget);
    expect(_key('link_store_terms'), findsOneWidget);
    expect(_key('link_store_privacy'), findsOneWidget);
    // Mention App Store 3.1.2 : le store de la plateforme courante (Android
    // dans flutter_test) est nommé, jamais traduit.
    expect(
      tester.widget<Text>(_key('txt_store_legal_notice')).data,
      allOf(contains('Google Play'), contains('renouvellement automatique')),
    );
    // L'annuel est proposé avant le mensuel.
    expect(
      tester.getTopLeft(_key('btn_store_buy_annual')).dy,
      lessThan(tester.getTopLeft(_key('btn_store_buy_monthly')).dy),
    );

    // Pro uniquement, aucun prix web, aucune carte de la page web.
    expect(_key('plan_card_max'), findsNothing);
    expect(_key('plan_card_ultra'), findsNothing);
    expect(find.byType(PlanCard), findsNothing);
    expect(find.textContaining('Bientôt disponible'), findsNothing);
    // Aucun texte de l'écran (titre de la barre compris) ne nomme Max/Ultra.
    expect(find.text('Baillan Pro'), findsOneWidget);
    expect(find.textContaining('Max'), findsNothing);
    expect(find.textContaining('Ultra'), findsNothing);
    expect(find.textContaining('7,99'), findsNothing);
    expect(find.textContaining('79 €'), findsNothing);
    expect(_key('txt_pro_store_app_unavailable'), findsNothing);
  });

  testWidgets('achat mensuel réussi : activation, puis abonné quand le '
      'serveur accorde le droit', (tester) async {
    await mount(tester, snapshot: _free);

    await tester.tap(_key('btn_store_buy_monthly'));
    await afterAction(tester);

    expect(fake.calls, contains('purchase:monthly:u1'));
    expect(_key('txt_store_activating'), findsOneWidget);
    expect(_key('btn_store_buy_monthly'), findsNothing);

    tier.add(_pro);
    await tester.pump();

    expect(_key('txt_store_already_subscribed'), findsOneWidget);
    expect(_key('txt_store_activating'), findsNothing);
    expect(_key('btn_store_buy_monthly'), findsNothing);
    expect(_key('btn_store_buy_annual'), findsNothing);
  });

  testWidgets('achat annuel : purchase avec la formule annuelle', (
    tester,
  ) async {
    await mount(tester, snapshot: _free);

    await tester.tap(_key('btn_store_buy_annual'));
    await afterAction(tester);

    expect(purchaseCalls(), ['purchase:annual:u1']);
  });

  testWidgets('activation trop longue : message, Restaurer, Réessayer sans '
      'jamais racheter', (tester) async {
    await mount(tester, snapshot: _free);
    await tester.tap(_key('btn_store_buy_monthly'));
    await afterAction(tester);
    expect(_key('txt_store_activating'), findsOneWidget);

    await tester.pump(kStoreActivationTimeout + const Duration(seconds: 1));

    expect(_key('txt_store_activation_delayed'), findsOneWidget);
    expect(_key('btn_store_activation_restore'), findsOneWidget);
    expect(_key('btn_store_activation_retry'), findsOneWidget);
    expect(_key('txt_store_activating'), findsNothing);

    // « Réessayer » relance l'attente, pas un achat.
    await tester.tap(_key('btn_store_activation_retry'));
    await tester.pump();
    expect(_key('txt_store_activating'), findsOneWidget);
    expect(_key('txt_store_activation_delayed'), findsNothing);
    expect(purchaseCalls(), ['purchase:monthly:u1']);

    await tester.pump(kStoreActivationTimeout + const Duration(seconds: 1));
    expect(_key('txt_store_activation_delayed'), findsOneWidget);

    await tester.tap(_key('btn_store_activation_restore'));
    await afterAction(tester);
    expect(fake.calls, contains('restore:u1'));
    expect(purchaseCalls(), ['purchase:monthly:u1']);
  });

  testWidgets('achat annulé : retour silencieux, offres actives', (
    tester,
  ) async {
    fake.purchaseOutcome = const PurchaseCancelled();
    await mount(tester, snapshot: _free);

    await tester.tap(_key('btn_store_buy_annual'));
    await afterAction(tester);

    expect(purchaseCalls(), ['purchase:annual:u1']);
    expect(find.byType(SnackBar), findsNothing);
    expect(_key('txt_store_activating'), findsNothing);
    expectOfferButtons(tester, enabled: true);
  });

  testWidgets('achat en attente : snackbar, offres toujours là', (
    tester,
  ) async {
    fake.purchaseOutcome = const PurchasePending();
    await mount(tester, snapshot: _free);

    await tester.tap(_key('btn_store_buy_monthly'));
    await afterAction(tester);

    expect(_key('snackbar_store_purchase_pending'), findsOneWidget);
    expect(_key('txt_store_activating'), findsNothing);
    expectOfferButtons(tester, enabled: true);
  });

  testWidgets('achat en erreur : snackbar, boutons réactivés', (tester) async {
    fake.purchaseOutcome = const PurchaseFailed('networkError');
    await mount(tester, snapshot: _free);

    await tester.tap(_key('btn_store_buy_monthly'));
    await afterAction(tester);

    expect(_key('snackbar_store_purchase_error'), findsOneWidget);
    expect(_key('txt_store_activating'), findsNothing);
    expectOfferButtons(tester, enabled: true);
  });

  testWidgets('achat en cours : tous les boutons désactivés jusqu\'au '
      'retour du store', (tester) async {
    final gate = Completer<void>();
    fake
      ..purchaseGate = gate
      ..purchaseOutcome = const PurchaseCancelled();
    await mount(tester, snapshot: _free);
    expectOfferButtons(tester, enabled: true);

    await tester.tap(_key('btn_store_buy_monthly'));
    await tester.pump();

    expect(purchaseCalls(), ['purchase:monthly:u1']);
    expectOfferButtons(tester, enabled: false);

    gate.complete();
    await afterAction(tester);

    expectOfferButtons(tester, enabled: true);
  });

  testWidgets('démontage pendant l\'achat : aucune erreur quand le store '
      'répond', (tester) async {
    final gate = Completer<void>();
    fake.purchaseGate = gate; // issue par défaut : PurchaseSucceeded
    await mount(tester, snapshot: _free);

    await tester.tap(_key('btn_store_buy_monthly'));
    await tester.pump();
    expect(purchaseCalls(), ['purchase:monthly:u1']);

    await tester.pumpWidget(const SizedBox());
    gate.complete();
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('restaurer : rien à restaurer → snackbar', (tester) async {
    await mount(tester, snapshot: _free);

    await tester.tap(_key('btn_store_restore'));
    await afterAction(tester);

    expect(fake.calls, contains('restore:u1'));
    expect(_key('snackbar_store_restore_nothing'), findsOneWidget);
    expectOfferButtons(tester, enabled: true);
  });

  testWidgets('restaurer : erreur → snackbar', (tester) async {
    fake.restoreOutcome = RestoreOutcome.error;
    await mount(tester, snapshot: _free);

    await tester.tap(_key('btn_store_restore'));
    await afterAction(tester);

    expect(_key('snackbar_store_restore_error'), findsOneWidget);
    expectOfferButtons(tester, enabled: true);
  });

  testWidgets('restaurer : succès → activation en cours', (tester) async {
    fake.restoreOutcome = RestoreOutcome.success;
    await mount(tester, snapshot: _free);

    await tester.tap(_key('btn_store_restore'));
    await afterAction(tester);

    expect(_key('txt_store_activating'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(purchaseCalls(), isEmpty);
  });

  testWidgets('offre indisponible : message, puis Réessayer relit l\'offre', (
    tester,
  ) async {
    fake.offer = null;
    await mount(tester, snapshot: _free);

    expect(_key('txt_store_offer_unavailable'), findsOneWidget);
    expect(_key('btn_store_offer_retry'), findsOneWidget);
    expect(_key('btn_store_buy_monthly'), findsNothing);
    expect(fake.offerCalls, 1);

    fake.offer = _offer;
    await tester.tap(_key('btn_store_offer_retry'));
    await tester.pumpAndSettle();

    expect(_key('btn_store_buy_monthly'), findsOneWidget);
    expect(_key('btn_store_buy_annual'), findsOneWidget);
    expect(_key('txt_store_offer_unavailable'), findsNothing);
    expect(fake.offerCalls, 2);
  });

  testWidgets('offre partielle (annuel seul) : un seul bouton d\'achat', (
    tester,
  ) async {
    fake.offer = const ProStoreOffer(
      annual: ProStorePackage(
        period: StoreBillingPeriod.annual,
        priceString: '84,99 €',
      ),
    );
    await mount(tester, snapshot: _free);

    expect(_key('btn_store_buy_annual'), findsOneWidget);
    expect(_key('btn_store_buy_monthly'), findsNothing);
    expect(_key('txt_store_offer_unavailable'), findsNothing);
  });

  testWidgets('déjà Pro à l\'ouverture : aucun achat, offre jamais demandée, '
      'Gérer mène au profil', (tester) async {
    await mount(
      tester,
      snapshot: const LandlordTierSnapshot(
        tier: SubscriptionTier.paid,
        planLevel: 'pro',
        proStore: 'web',
      ),
    );

    expect(_key('txt_store_already_subscribed'), findsOneWidget);
    expect(_key('btn_store_buy_monthly'), findsNothing);
    expect(_key('btn_store_buy_annual'), findsNothing);
    expect(_key('btn_store_restore'), findsNothing);
    expect(fake.offerCalls, 0);

    await tester.tap(_key('btn_store_manage_subscription'));
    await tester.pumpAndSettle();

    expect(find.text('profile-page'), findsOneWidget);
  });

  testWidgets('liens légaux : conditions et confidentialité', (tester) async {
    await mount(tester, snapshot: _free);
    await tester.tap(_key('link_store_terms'));
    await tester.pumpAndSettle();
    expect(find.text('terms-page'), findsOneWidget);

    await mount(tester, snapshot: _free);
    await tester.tap(_key('link_store_privacy'));
    await tester.pumpAndSettle();
    expect(find.text('privacy-page'), findsOneWidget);
  });

  testWidgets('interrupteur coupé : message neutre, aucun achat, aucun appel', (
    tester,
  ) async {
    debugInAppPurchaseEnabledOverride = false;
    await mount(tester, snapshot: _free);

    expect(_key('txt_pro_store_app_unavailable'), findsOneWidget);
    expect(find.text('Baillan Pro, Max & Ultra'), findsOneWidget);
    expect(_key('btn_store_buy_monthly'), findsNothing);
    expect(_key('btn_store_buy_annual'), findsNothing);
    expect(_key('btn_store_restore'), findsNothing);
    expect(fake.calls, isEmpty);
  });

  testWidgets('palier en chargement : ni achat ni « déjà abonné », offre '
      'non demandée', (tester) async {
    await mount(tester); // aucun tier.add
    await tester.pump();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(_key('btn_store_buy_monthly'), findsNothing);
    expect(_key('btn_store_buy_annual'), findsNothing);
    expect(_key('btn_store_restore'), findsNothing);
    expect(_key('txt_store_already_subscribed'), findsNothing);
    expect(fake.offerCalls, 0);
  });

  testWidgets('palier en erreur : ni achat ni offre demandée, message et '
      'Réessayer', (tester) async {
    await mount(tester);
    tier.addError(StateError('x'));
    await tester.pump();

    expect(_key('btn_store_buy_monthly'), findsNothing);
    expect(_key('btn_store_buy_annual'), findsNothing);
    expect(_key('btn_store_restore'), findsNothing);
    expect(_key('txt_store_offer_unavailable'), findsOneWidget);
    expect(_key('btn_store_offer_retry'), findsOneWidget);
    expect(fake.offerCalls, 0);
  });

  testWidgets('palier en erreur : Réessayer relit le palier puis affiche '
      'les offres', (tester) async {
    await mount(tester);
    tier.addError(StateError('x'));
    await tester.pump();

    await tester.tap(_key('btn_store_offer_retry'));
    await tester.pump();
    // Relu mais pas encore connu : chargement, toujours aucun achat.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(_key('btn_store_buy_monthly'), findsNothing);
    expect(fake.offerCalls, 0);

    tier.add(_free);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(_key('btn_store_buy_monthly'), findsOneWidget);
    expect(_key('btn_store_buy_annual'), findsOneWidget);
    expect(fake.offerCalls, 1);
  });

  testWidgets('double appui dans la même frame : un seul achat', (
    tester,
  ) async {
    fake.purchaseGate = Completer<void>();
    await mount(tester, snapshot: _free);
    // Deux appuis AVANT toute reconstruction : `onPressed` lu une fois, appelé
    // deux fois (annuel puis mensuel) sans `pump` entre les deux.
    final annual = tester
        .widget<ButtonStyleButton>(_key('btn_store_buy_annual'))
        .onPressed!;
    final monthly = tester
        .widget<ButtonStyleButton>(_key('btn_store_buy_monthly'))
        .onPressed!;

    annual();
    monthly();
    annual();
    await tester.pump();

    expect(purchaseCalls(), ['purchase:annual:u1']);

    fake.purchaseGate!.complete();
    await afterAction(tester);
  });

  testWidgets('double appui sur Restaurer dans la même frame : une seule '
      'restauration', (tester) async {
    await mount(tester, snapshot: _free);
    final restore = tester
        .widget<ButtonStyleButton>(_key('btn_store_restore'))
        .onPressed!;

    restore();
    restore();
    await afterAction(tester);

    expect(fake.calls.where((c) => c.startsWith('restore')), ['restore:u1']);
  });
}
