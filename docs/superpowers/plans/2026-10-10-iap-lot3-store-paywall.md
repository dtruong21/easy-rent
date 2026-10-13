# FEAT-044e lot 3 — Achat intégré : écran d'achat des apps — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dans les apps iOS/Android, quand l'achat intégré est actif, la page `/pro` vend Pro (mensuel et annuel) aux prix du store, attend l'activation par le serveur, permet de restaurer et de gérer son abonnement — toujours derrière `IAP_ENABLED`, coupé par défaut.

**Architecture:** Spec : [`docs/superpowers/specs/2026-10-05-iap-revenuecat-mobile-design.md`](../specs/2026-10-05-iap-revenuecat-mobile-design.md) §1, §3 et « Points hérités du lot 2 ». Le serveur reste la seule vérité : un achat réussi n'accorde rien dans l'app, l'écran attend que `landlordTierProvider` passe en Pro (écrit par le webhook RevenueCat). Le service garantit lui-même le rattachement RevenueCat ↔ compte Firebase juste avant chaque achat ou restauration. L'écran est un widget à part (`ProStorePaywall`), branché dans `ProPricingPage` à la place du message neutre.

**Tech Stack:** Flutter 3 / Dart ≥ 3.11, Riverpod 2.6, `purchases_flutter` 10.15.2 (isolé dans `RevenueCatStoreBillingService`), `url_launcher`, `go_router`, `flutter_test` + `firebase_auth_mocks`.

## Global Constraints

- Interrupteur `IAP_ENABLED` coupé (défaut) : **comportement actuel strictement inchangé** dans les apps (`/pro` = message neutre `txt_pro_store_app_unavailable`, aucune offre, aucun prix). Le web ne change jamais (parcours Stripe).
- Dans les apps, **Pro uniquement** (mensuel et annuel). **Max et Ultra ne sont pas affichés** (décision Daki 2026-10-10 : pas de contenu « bientôt » dans les apps, App Store 2.1). Aucun prix web (`PlanMatrix.priceLabel*`), aucun lien ni mention du site pour acheter (App Store 3.1.1, Paiements Google Play).
- Prix affichés = `ProStorePackage.priceString` lu dans le store. Jamais de prix en dur.
- **Le serveur seul accorde le droit.** Après un achat ou une restauration réussis, l'écran affiche « Activation en cours… » et observe `planEntitlementProvider` ; il ne débloque rien lui-même. Au-delà de **60 secondes** (`kStoreActivationTimeout`) : message rassurant + « Restaurer les achats » + « Réessayer ». « Réessayer » relance l'attente, **jamais un second achat**.
- Compte **déjà Pro ou plus** (toute origine : web, store, liste blanche) : « Vous êtes déjà abonné », **aucun bouton d'achat**.
- **Aucun bouton d'achat tant que le palier du compte n'est pas connu** (`landlordTierProvider` en chargement) : indicateur de chargement, et l'offre du store n'est pas demandée.
- `purchase` et `restore` reçoivent l'**uid Firebase** et garantissent `Purchases.appUserID == uid` avant d'agir ; sinon `PurchaseFailed('not_logged_in')` / `RestoreOutcome.error`. Un achat ne part jamais sur un identifiant RevenueCat anonyme.
- Issues d'achat : `PurchaseSucceeded` → activation ; `PurchaseCancelled` → retour silencieux ; `PurchasePending` → « Achat en attente de validation » ; `PurchaseFailed` → message d'erreur, boutons réactivés.
- Mentions App Store 3.1.2 sur l'écran d'achat : renouvellement automatique, résiliation dans les réglages du store, liens vers `/terms` et `/privacy`.
- `package:purchases_flutter` reste importé dans `lib/` **uniquement** par `lib/features/paid_plan/data/revenuecat_store_billing_service.dart`.
- Dans un `ConsumerState`, **ne jamais lire `ref` ni `context` après un `await`** sans avoir capturé les valeurs avant, et tester `mounted` avant tout `setState` / snackbar / navigation.
- L'entitlement RevenueCat s'appelle `"Bailan Pro"` (un seul `l`, typo load-bearing) : ne jamais le renommer. Ce lot n'en dépend pas.
- Textes FR et EN (`lib/l10n/app_fr.arb`, `lib/l10n/app_en.arb` = gabarit avec `@`descriptions préfixées « FEAT-044e — ») ; `flutter gen-l10n` après modification. « App Store » et « Google Play » sont des noms propres : constantes Dart, pas de traduction.
- Outillage : `export PATH=/opt/homebrew/bin:$PATH` ; `flutter analyze` sans aucun problème ; `dart format lib test` (jamais `dart format .`) ; ne jamais committer `*.g.dart`, `*.freezed.dart`, `build/`, `firebase.altports.local.json` ; ne jamais `git add -A`. Un build Android local réécrit `android/gradle.properties` : `git checkout -- android/gradle.properties`.
- Branche `feat/044e-iap-store-paywall` (déjà créée depuis `develop`). Commits en français, suffixés de `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

---

## File Structure

| Fichier | Rôle |
|---|---|
| `lib/features/paid_plan/data/store_billing_service.dart` (modif) | `purchase(package, uid:)`, `restore(uid:)` |
| `lib/features/paid_plan/data/revenuecat_store_billing_service.dart` (modif) | rattachement avant achat ; mapping pur `proOfferFromOffering` / `packageForPeriod` |
| `lib/features/paid_plan/domain/store_names.dart` (nouveau) | noms des stores, URL de gestion de repli |
| `lib/features/paid_plan/application/store_offer_provider.dart` (nouveau) | `storeProOfferProvider` |
| `lib/features/paid_plan/presentation/widgets/pro_store_paywall.dart` (nouveau) | états et actions de l'écran d'achat |
| `lib/features/paid_plan/presentation/widgets/pro_store_paywall_views.dart` (nouveau) | vues sans état (offres, activation, déjà abonné, indisponible, mentions) |
| `lib/features/paid_plan/presentation/pro_pricing_page.dart` (modif) | aiguillage app store : paywall si achat actif, sinon message neutre |
| `lib/features/paid_plan/presentation/widgets/subscription_section.dart` (modif) | bouton « Gérer dans {store} » |
| `lib/features/profile/presentation/profile_page.dart` (modif) | `proUpsellVisible` tient compte de l'achat intégré |
| `test/helpers/fake_store_billing_service.dart` (modif) | nouvelles signatures, `purchaseGate`, compteur d'offres |
| Tests | `test/unit/revenuecat_store_billing_service_test.dart`, `test/unit/store_names_test.dart`, `test/widget/pro_store_paywall_test.dart`, `test/widget/subscription_section_test.dart`, `test/widget/profile_page_test.dart`, `test/widget/pro_pricing_page_test.dart` |
| Docs | spec (déjà amendée), `docs/state/routes/account.md`, `docs/state/FEATURES.md`, `docs/state/CHANGELOG.md`, `docs/MOBILE.md`, `docs/STORE_COMPLIANCE.md` |

---

### Task 1: Service — rattachement garanti avant achat, mapping des offres testé

**Files:**
- Modify: `lib/features/paid_plan/data/store_billing_service.dart`
- Modify: `lib/features/paid_plan/data/revenuecat_store_billing_service.dart`
- Create: `lib/features/paid_plan/domain/store_names.dart`
- Modify: `test/helpers/fake_store_billing_service.dart`
- Test: `test/unit/revenuecat_store_billing_service_test.dart` (modif), `test/unit/store_names_test.dart` (nouveau)

**Interfaces:**
- Consumes: l'existant du lot 2 (`StoreBillingService`, `ProStoreOffer`, `ProStorePackage`, `StoreBillingPeriod`, `PurchaseOutcome`, `RestoreOutcome`, `errorCodeOrNull`, `purchaseOutcomeForError`, `restoreOutcomeFor`).
- Produces:
  - `Future<PurchaseOutcome> purchase(ProStorePackage package, {required String uid})` et `Future<RestoreOutcome> restore({required String uid})` sur `StoreBillingService`.
  - `ProStoreOffer? proOfferFromOffering(Offering? current)` et `Package? packageForPeriod(Offering? current, StoreBillingPeriod period)` (`@visibleForTesting`, dans le fichier RevenueCat).
  - `store_names.dart` : `const String kAppStoreName = 'App Store';` `const String kGooglePlayName = 'Google Play';` `String storeNameForPlatform(TargetPlatform platform)` ; `String storeNameForProStore(String? proStore)` ; `Uri storeManagementFallbackUri(String? proStore)`.
  - `FakeStoreBillingService` : `calls` contient `'purchase:monthly:u1'` / `'purchase:annual:u1'` / `'restore:u1'` ; `Completer<void>? purchaseGate` ; `int offerCalls`.

- [ ] **Step 1: Écrire les tests qui échouent**

Dans `test/unit/revenuecat_store_billing_service_test.dart` :
1. Mettre à jour les appels existants du groupe « achat intégré coupé » : `service.purchase(…, uid: 'u1')` et `service.restore(uid: 'u1')` (mêmes attentes : `PurchaseFailed('not_configured')`, `RestoreOutcome.error`).
2. Ajouter le groupe suivant (les constructeurs du SDK sont positionnels — vérifiés dans `~/.pub-cache/hosted/pub.dev/purchases_flutter-10.15.2/lib/models/`) :

```dart
  group('mapping de l\'offre RevenueCat', () {
    const context = PresentedOfferingContext('default', null, null);
    Package pkg(String id, PackageType type, String price) => Package(
      id,
      type,
      StoreProduct(id, '', 'Pro', 1, price, 'EUR'),
      context,
    );
    final monthly = pkg(r'$rc_monthly', PackageType.monthly, '8,49 €');
    final annual = pkg(r'$rc_annual', PackageType.annual, '84,99 €');
    Offering offering({Package? m, Package? a}) => Offering(
      'default',
      '',
      const {},
      [?m, ?a],
      monthly: m,
      annual: a,
    );

    test('mensuel et annuel → prix du store, sans inversion', () {
      final offer = proOfferFromOffering(offering(m: monthly, a: annual))!;
      expect(offer.monthly!.period, StoreBillingPeriod.monthly);
      expect(offer.monthly!.priceString, '8,49 €');
      expect(offer.annual!.period, StoreBillingPeriod.annual);
      expect(offer.annual!.priceString, '84,99 €');
    });

    test('offre partielle → seule la formule présente', () {
      final offer = proOfferFromOffering(offering(a: annual))!;
      expect(offer.monthly, isNull);
      expect(offer.annual!.priceString, '84,99 €');
    });

    test('aucune offre courante → null', () {
      expect(proOfferFromOffering(null), isNull);
    });

    test('packageForPeriod rend le bon package', () {
      final current = offering(m: monthly, a: annual);
      expect(
        packageForPeriod(current, StoreBillingPeriod.monthly)!.identifier,
        r'$rc_monthly',
      );
      expect(
        packageForPeriod(current, StoreBillingPeriod.annual)!.identifier,
        r'$rc_annual',
      );
      expect(packageForPeriod(null, StoreBillingPeriod.monthly), isNull);
    });
  });
```

Créer `test/unit/store_names_test.dart` :

```dart
import 'package:easyrent/features/paid_plan/domain/store_names.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('nom du store selon la plateforme', () {
    expect(storeNameForPlatform(TargetPlatform.iOS), 'App Store');
    expect(storeNameForPlatform(TargetPlatform.android), 'Google Play');
  });

  test('nom du store d\'origine de l\'abonnement', () {
    expect(storeNameForProStore('app_store'), 'App Store');
    expect(storeNameForProStore('play_store'), 'Google Play');
  });

  test('URL de gestion de repli, par store d\'origine', () {
    expect(
      storeManagementFallbackUri('app_store').toString(),
      'https://apps.apple.com/account/subscriptions',
    );
    expect(
      storeManagementFallbackUri('play_store').toString(),
      'https://play.google.com/store/account/subscriptions',
    );
  });
}
```

- [ ] **Step 2: Vérifier qu'ils échouent**

Run: `flutter test test/unit/revenuecat_store_billing_service_test.dart test/unit/store_names_test.dart`
Expected: échec de compilation (signatures `uid:`, `proOfferFromOffering`, `packageForPeriod`, `store_names.dart`).

- [ ] **Step 3: Implémenter**

`store_billing_service.dart` — remplacer les deux méthodes :

```dart
  /// Achète [package] pour le compte [uid]. Garantit d'abord que
  /// l'utilisateur RevenueCat est [uid] (jamais d'achat sur un identifiant
  /// anonyme) ; sinon `PurchaseFailed('not_logged_in')`. Ne lève jamais.
  Future<PurchaseOutcome> purchase(
    ProStorePackage package, {
    required String uid,
  });

  /// Restaure les achats du compte store pour [uid] (même garantie de
  /// rattachement que [purchase]). Ne lève jamais.
  Future<RestoreOutcome> restore({required String uid});
```

`revenuecat_store_billing_service.dart` — ajouter, près des autres fonctions pures :

```dart
/// PURE — offre Pro lue dans l'offering courant, prix du store.
@visibleForTesting
ProStoreOffer? proOfferFromOffering(Offering? current) {
  if (current == null) return null;
  ProStorePackage? map(StoreBillingPeriod period) {
    final package = packageForPeriod(current, period);
    return package == null
        ? null
        : ProStorePackage(
            period: period,
            priceString: package.storeProduct.priceString,
          );
  }

  return ProStoreOffer(
    monthly: map(StoreBillingPeriod.monthly),
    annual: map(StoreBillingPeriod.annual),
  );
}

/// PURE — package RevenueCat de [period] dans l'offering courant.
@visibleForTesting
Package? packageForPeriod(Offering? current, StoreBillingPeriod period) =>
    switch (period) {
      StoreBillingPeriod.monthly => current?.monthly,
      StoreBillingPeriod.annual => current?.annual,
    };
```

et dans la classe : une méthode privée, puis `fetchProOffer`, `purchase`, `restore` réécrites :

```dart
  /// `true` si l'utilisateur RevenueCat est [uid] (rattache au besoin).
  Future<bool> _ensureLoggedIn(String uid) async {
    try {
      if (await Purchases.appUserID != uid) await Purchases.logIn(uid);
      return true;
    } catch (e, st) {
      _log.warning('rattachement RevenueCat impossible avant achat', e, st);
      return false;
    }
  }

  @override
  Future<ProStoreOffer?> fetchProOffer() async {
    if (!_configured) return null;
    try {
      return proOfferFromOffering((await Purchases.getOfferings()).current);
    } catch (e, st) {
      _log.warning('offres RevenueCat indisponibles', e, st);
      return null;
    }
  }

  @override
  Future<PurchaseOutcome> purchase(
    ProStorePackage package, {
    required String uid,
  }) async {
    if (!_configured) return const PurchaseFailed('not_configured');
    if (!await _ensureLoggedIn(uid)) {
      return const PurchaseFailed('not_logged_in');
    }
    try {
      final pkg = packageForPeriod(
        (await Purchases.getOfferings()).current,
        package.period,
      );
      if (pkg == null) return const PurchaseFailed('package_unavailable');
      await Purchases.purchase(PurchaseParams.package(pkg));
      return const PurchaseSucceeded();
    } catch (e, st) {
      // Jamais d'exception vers l'appelant : le bouton d'achat resterait figé.
      final code = e is PlatformException ? errorCodeOrNull(e) : null;
      final outcome = code == null
          ? const PurchaseFailed('unknown')
          : purchaseOutcomeForError(code);
      if (outcome is PurchaseFailed) {
        _log.warning('achat RevenueCat échoué', e, st);
      }
      return outcome;
    }
  }

  @override
  Future<RestoreOutcome> restore({required String uid}) async {
    if (!_configured) return RestoreOutcome.error;
    if (!await _ensureLoggedIn(uid)) return RestoreOutcome.error;
    try {
      final info = await Purchases.restorePurchases();
      return restoreOutcomeFor(
        activeEntitlements: info.entitlements.active.length,
      );
    } catch (e, st) {
      _log.warning('restauration RevenueCat échouée', e, st);
      return RestoreOutcome.error;
    }
  }
```

`store_names.dart` :

```dart
import 'package:flutter/foundation.dart';

/// Noms des stores (noms propres, non traduits) et page de gestion des
/// abonnements, FEAT-044e.
const String kAppStoreName = 'App Store';
const String kGooglePlayName = 'Google Play';

/// Store de la plateforme courante (écran d'achat).
String storeNameForPlatform(TargetPlatform platform) =>
    platform == TargetPlatform.iOS ? kAppStoreName : kGooglePlayName;

/// Store d'ORIGINE d'un abonnement (`landlords.proStore`) : « Gérer » pointe
/// vers le store où l'achat a été fait, pas vers la plateforme courante.
String storeNameForProStore(String? proStore) =>
    proStore == 'play_store' ? kGooglePlayName : kAppStoreName;

/// Page de gestion des abonnements du store d'origine, quand RevenueCat ne
/// fournit pas d'URL (service non configuré, web).
Uri storeManagementFallbackUri(String? proStore) => Uri.parse(
  proStore == 'play_store'
      ? 'https://play.google.com/store/account/subscriptions'
      : 'https://apps.apple.com/account/subscriptions',
);
```

`test/helpers/fake_store_billing_service.dart` — remplacer `fetchProOffer`, `purchase`, `restore` et ajouter les deux champs :

```dart
  /// Retient `purchase` jusqu'à sa complétion (tests « achat en cours »).
  Completer<void>? purchaseGate;
  int offerCalls = 0;

  @override
  Future<ProStoreOffer?> fetchProOffer() async {
    offerCalls++;
    calls.add('fetchProOffer');
    return offer;
  }

  @override
  Future<PurchaseOutcome> purchase(
    ProStorePackage package, {
    required String uid,
  }) async {
    calls.add('purchase:${package.period.name}:$uid');
    if (purchaseGate != null) await purchaseGate!.future;
    return purchaseOutcome;
  }

  @override
  Future<RestoreOutcome> restore({required String uid}) async {
    calls.add('restore:$uid');
    return restoreOutcome;
  }
```

Adapter tout appelant ou faux existant (`grep -rn "\.purchase(\|\.restore(\|implements StoreBillingService" lib test`).

- [ ] **Step 4: Vérifier**

Run: `flutter test test/unit/revenuecat_store_billing_service_test.dart test/unit/store_names_test.dart test/unit/store_billing_session_sync_test.dart && dart format lib test && flutter analyze && grep -rln "package:purchases_flutter" lib`
Expected: PASS ; « No issues found! » ; le `grep` ne liste que `lib/features/paid_plan/data/revenuecat_store_billing_service.dart`.

- [ ] **Step 5: Commit**

```bash
git add lib/features/paid_plan/data/store_billing_service.dart lib/features/paid_plan/data/revenuecat_store_billing_service.dart lib/features/paid_plan/domain/store_names.dart test/helpers/fake_store_billing_service.dart test/unit/revenuecat_store_billing_service_test.dart test/unit/store_names_test.dart
git commit -m "feat(iap): rattachement RevenueCat garanti avant achat, mapping des offres testé (FEAT-044e lot 3)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Écran d'achat des apps sur `/pro`

**Files:**
- Create: `lib/features/paid_plan/application/store_offer_provider.dart`
- Create: `lib/features/paid_plan/presentation/widgets/pro_store_paywall.dart`
- Create: `lib/features/paid_plan/presentation/widgets/pro_store_paywall_views.dart`
- Modify: `lib/features/paid_plan/presentation/pro_pricing_page.dart` (branche `if (isStoreApp)` de `build`, et commentaire de classe)
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_fr.arb`
- Test: `test/widget/pro_store_paywall_test.dart` (nouveau) ; `test/widget/pro_pricing_page_test.dart` doit rester vert sans modification d'assertions

**Interfaces:**
- Consumes: `StoreBillingService.fetchProOffer()` / `purchase(package, uid:)` / `restore(uid:)`, `storeBillingServiceProvider`, `FakeStoreBillingService` (Task 1) ; `storeNameForPlatform` (Task 1) ; `isStoreApp`, `isInAppPurchaseEnabled`, `debugIsStoreAppOverride`, `debugInAppPurchaseEnabledOverride` (`lib/core/config/store_billing.dart`) ; `planEntitlementProvider`, `landlordTierProvider`, `LandlordTierSnapshot` (`lib/features/auth/data/landlord_tier_repository.dart`) ; `PlanLevel.pro` ; `authRepositoryProvider` (`currentUser?.uid`) ; `proPricingBulletsFor(context, 'pro')` et `proPricingTaglineFor(context, 'pro')` (`pro_pricing_copy.dart`) ; routes `/terms`, `/privacy`, `/profile`.
- Produces: `storeProOfferProvider` (`FutureProvider.autoDispose<ProStoreOffer?>`) ; `const Duration kStoreActivationTimeout = Duration(seconds: 60);` ; `class ProStorePaywall extends ConsumerStatefulWidget` ; clés de test listées au Step 1.

- [ ] **Step 1: Textes** — ajouter (EN avec `@description` « FEAT-044e — … », FR). Réutiliser une clé existante si le même libellé existe déjà (`grep` dans `app_fr.arb`, ex. `commonRetry`) :

| Clé | FR | EN |
|---|---|---|
| `storePaywallHeadline` | Passez à Baillan Pro | Upgrade to Baillan Pro |
| `storeBuyMonthlyButton` (`price` String) | S'abonner — {price} / mois | Subscribe — {price} / month |
| `storeBuyAnnualButton` (`price` String) | S'abonner — {price} / an | Subscribe — {price} / year |
| `storeRestoreButton` | Restaurer les achats | Restore purchases |
| `storeLegalNotice` (`store` String) | Abonnement à renouvellement automatique. Le paiement est débité sur votre compte {store} à la confirmation de l'achat. L'abonnement se renouvelle pour la même durée, sauf résiliation au moins 24 heures avant la fin de la période en cours. Vous gérez et résiliez votre abonnement dans les réglages de votre compte {store}. | Auto-renewing subscription. Payment is charged to your {store} account at confirmation of purchase. The subscription renews for the same duration unless cancelled at least 24 hours before the end of the current period. You manage and cancel your subscription in your {store} account settings. |
| `storeTermsLink` | Conditions d'utilisation | Terms of use |
| `storePrivacyLink` | Politique de confidentialité | Privacy policy |
| `storeOfferUnavailable` | Les offres ne sont pas disponibles pour le moment. | Plans are not available right now. |
| `storeActivatingTitle` | Activation en cours… | Activating… |
| `storeActivatingBody` | Votre achat est confirmé. Nous activons votre abonnement, cela prend quelques secondes. | Your purchase is confirmed. We're activating your subscription — this takes a few seconds. |
| `storeActivationDelayedBody` | L'activation prend plus de temps que prévu. Votre achat est bien enregistré auprès du store. | Activation is taking longer than expected. Your purchase is recorded with the store. |
| `storeAlreadySubscribed` | Vous êtes déjà abonné. | You're already subscribed. |
| `storeManageSubscriptionButton` | Gérer mon abonnement | Manage my subscription |
| `storePurchasePending` | Achat en attente de validation. Votre abonnement s'activera dès qu'il sera approuvé. | Purchase pending approval. Your subscription will activate once it's approved. |
| `storePurchaseError` | L'achat n'a pas abouti. Vérifiez votre connexion et réessayez. | The purchase didn't go through. Check your connection and try again. |
| `storeRestoreNothing` | Aucun achat à restaurer sur ce compte. | No purchase to restore on this account. |
| `storeRestoreError` | La restauration a échoué. Réessayez dans un instant. | Restore failed. Try again in a moment. |

Clés de test du widget : `btn_store_buy_monthly`, `btn_store_buy_annual`, `btn_store_restore`, `txt_store_legal_notice`, `link_store_terms`, `link_store_privacy`, `txt_store_offer_unavailable`, `btn_store_offer_retry`, `txt_store_activating`, `txt_store_activation_delayed`, `btn_store_activation_restore`, `btn_store_activation_retry`, `txt_store_already_subscribed`, `btn_store_manage_subscription`, snackbars `snackbar_store_purchase_pending`, `snackbar_store_purchase_error`, `snackbar_store_restore_nothing`, `snackbar_store_restore_error`.

- [ ] **Step 2: Écrire les tests qui échouent** — `test/widget/pro_store_paywall_test.dart`. Montage commun :

```dart
// setUp : debugIsStoreAppOverride = true ; debugInAppPurchaseEnabledOverride = true
// tearDown : debugIsStoreAppOverride = false ; debugInAppPurchaseEnabledOverride = null
//
// final tier = StreamController<LandlordTierSnapshot?>.broadcast();
// ProviderScope(overrides: [
//   storeBillingServiceProvider.overrideWithValue(fake),          // FakeStoreBillingService
//   landlordTierProvider.overrideWith((ref) => tier.stream),
//   authRepositoryProvider.overrideWithValue(_FakeAuthRepo(MockUser(uid: 'u1', isEmailVerified: true))),
//   paidPlanInterestRepositoryProvider.overrideWithValue(...),     // comme pro_pricing_page_test.dart
// ], child: MaterialApp.router(routerConfig: GoRouter(initialLocation: '/pro', routes: [
//   GoRoute(path: '/pro', builder: (_, _) => const ProPricingPage()),
//   GoRoute(path: '/profile', builder: (_, _) => const Text('profile-page')),
//   GoRoute(path: '/terms', builder: (_, _) => const Text('terms-page')),
//   GoRoute(path: '/privacy', builder: (_, _) => const Text('privacy-page')),
// ]), locale fr, delegates…))
//
// `_FakeAuthRepo` : `implements AuthRepository` avec `final User? currentUser` et
// `noSuchMethod` (même faux que test/unit/store_billing_session_sync_test.dart).
// Ordre : pumpWidget D'ABORD (le provider s'abonne au flux broadcast), puis tier.add(…), puis pump.
// Compte gratuit : tier.add(const LandlordTierSnapshot(tier: SubscriptionTier.free)) puis pump.
// Compte Pro : tier.add(const LandlordTierSnapshot(tier: SubscriptionTier.paid, planLevel: 'pro', proStore: 'app_store')).
// Offre par défaut du faux : ProStoreOffer(
//   monthly: ProStorePackage(period: StoreBillingPeriod.monthly, priceString: '8,49 €'),
//   annual: ProStorePackage(period: StoreBillingPeriod.annual, priceString: '84,99 €')).
//   (prix volontairement différents des prix web 7,99 € / 79 €.)
```

Cas à écrire (un `testWidgets` chacun, assertions exactes) :

1. **Offres** : compte gratuit → `btn_store_buy_monthly` contient « 8,49 € », `btn_store_buy_annual` contient « 84,99 € », `btn_store_restore`, `txt_store_legal_notice`, `link_store_terms`, `link_store_privacy` présents ; **aucune** carte `plan_card_max` / `plan_card_ultra`, aucun texte « Bientôt disponible », aucun « 7,99 » ni « 79 € » ; `txt_pro_store_app_unavailable` absent.
2. **Achat mensuel réussi** : tap `btn_store_buy_monthly` → `fake.calls` contient `'purchase:monthly:u1'` ; `txt_store_activating` visible ; puis `tier.add(snapshot Pro)` + pump → `txt_store_already_subscribed` visible, plus aucun `btn_store_buy_*`.
3. **Achat annuel** : tap `btn_store_buy_annual` → `'purchase:annual:u1'`.
4. **Activation trop longue** : après un achat réussi, `await tester.pump(kStoreActivationTimeout + const Duration(seconds: 1))` → `txt_store_activation_delayed`, `btn_store_activation_restore`, `btn_store_activation_retry` ; tap « Réessayer » → retour à `txt_store_activating` et **aucun** nouvel appel `purchase` ; nouveau délai → tap `btn_store_activation_restore` → `'restore:u1'`.
5. **Achat annulé** (`fake.purchaseOutcome = const PurchaseCancelled()`) → offres toujours affichées, aucun snackbar, boutons actifs.
6. **Achat en attente** (`PurchasePending`) → `snackbar_store_purchase_pending`, offres toujours là.
7. **Achat en erreur** (`PurchaseFailed('networkError')`) → `snackbar_store_purchase_error`, boutons réactivés.
8. **Achat en cours** : `fake.purchaseGate = Completer()` ; tap achat → les deux boutons d'achat et « Restaurer » ont `onPressed == null` ; compléter → réactivés ou activation.
9. **Démontage pendant l'achat** : gate posé, tap, `pumpWidget(const SizedBox())`, compléter le gate → `tester.takeException()` est `null`.
10. **Restaurer — rien** (`RestoreOutcome.nothingToRestore`) → `snackbar_store_restore_nothing` ; **erreur** → `snackbar_store_restore_error` ; **succès** → `txt_store_activating`.
11. **Offre indisponible** (`fake.offer = null`) → `txt_store_offer_unavailable` + `btn_store_offer_retry` ; poser une offre puis tap « Réessayer » → boutons d'achat, `fake.offerCalls == 2`.
12. **Offre partielle** (annuel seul) → `btn_store_buy_annual` présent, `btn_store_buy_monthly` absent.
13. **Déjà Pro à l'ouverture** (snapshot Pro, `proStore: 'web'`) → `txt_store_already_subscribed`, aucun bouton d'achat, `fake.offerCalls == 0` ; tap `btn_store_manage_subscription` → `profile-page`.
14. **Liens légaux** : tap `link_store_terms` → `terms-page` ; (nouveau montage) tap `link_store_privacy` → `privacy-page`.
15. **Interrupteur coupé** (`debugInAppPurchaseEnabledOverride = false`) → `txt_pro_store_app_unavailable` présent, aucun `btn_store_buy_*`, `fake.calls` vide.
16. **Palier en chargement** (aucun `tier.add` après `pumpWidget`) → aucun `btn_store_buy_*`, aucun `txt_store_already_subscribed`, `fake.offerCalls == 0`.

- [ ] **Step 3: Vérifier qu'ils échouent**

Run: `flutter gen-l10n && flutter test test/widget/pro_store_paywall_test.dart`
Expected: échec de compilation (`pro_store_paywall.dart` absent).

- [ ] **Step 4: Implémenter**

`store_offer_provider.dart` :

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/store_billing_service.dart';
import '../domain/store_billing_models.dart';

/// Offre Pro du store (FEAT-044e), relue à chaque ouverture de l'écran
/// d'achat. `null` = indisponible.
final storeProOfferProvider = FutureProvider.autoDispose<ProStoreOffer?>(
  (ref) => ref.read(storeBillingServiceProvider).fetchProOffer(),
);
```

`pro_store_paywall.dart` :

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../auth/data/landlord_tier_repository.dart';
import '../../../auth/domain/plan_level.dart';
import '../../application/store_offer_provider.dart';
import '../../data/store_billing_service.dart';
import '../../domain/store_billing_models.dart';
import 'pro_store_paywall_views.dart';

/// Délai au-delà duquel l'activation est signalée comme lente.
const Duration kStoreActivationTimeout = Duration(seconds: 60);

enum _Phase { offers, activating, delayed }

/// Écran d'achat des apps iOS/Android (FEAT-044e) — corps de `/pro` quand
/// l'achat intégré est actif.
///
/// Le serveur seul accorde le droit : après un achat ou une restauration
/// réussis, l'écran attend que [planEntitlementProvider] passe en Pro (écrit
/// par le webhook RevenueCat). Il ne débloque jamais rien lui-même, et
/// « Réessayer » relance l'attente, jamais un second achat.
class ProStorePaywall extends ConsumerStatefulWidget {
  const ProStorePaywall({super.key});

  @override
  ConsumerState<ProStorePaywall> createState() => _ProStorePaywallState();
}

class _ProStorePaywallState extends ConsumerState<ProStorePaywall> {
  _Phase _phase = _Phase.offers;
  bool _busy = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startActivation() {
    _timer?.cancel();
    setState(() => _phase = _Phase.activating);
    _timer = Timer(kStoreActivationTimeout, () {
      if (mounted && _phase == _Phase.activating) {
        setState(() => _phase = _Phase.delayed);
      }
    });
  }

  void _snack(String key, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(key: Key(key), content: Text(message)));
  }

  Future<void> _buy(ProStorePackage package) async {
    // `ref` et `context` lus AVANT tout await.
    final service = ref.read(storeBillingServiceProvider);
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    final l10n = context.l10n;
    if (uid == null) {
      _snack('snackbar_store_purchase_error', l10n.storePurchaseError);
      return;
    }
    setState(() => _busy = true);
    final outcome = await service.purchase(package, uid: uid);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (outcome) {
      case PurchaseSucceeded():
        _startActivation();
      case PurchaseCancelled():
        break;
      case PurchasePending():
        _snack('snackbar_store_purchase_pending', l10n.storePurchasePending);
      case PurchaseFailed():
        _snack('snackbar_store_purchase_error', l10n.storePurchaseError);
    }
  }

  Future<void> _restore() async {
    final service = ref.read(storeBillingServiceProvider);
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    final l10n = context.l10n;
    if (uid == null) {
      _snack('snackbar_store_restore_error', l10n.storeRestoreError);
      return;
    }
    setState(() => _busy = true);
    final outcome = await service.restore(uid: uid);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (outcome) {
      case RestoreOutcome.success:
        _startActivation();
      case RestoreOutcome.nothingToRestore:
        _snack('snackbar_store_restore_nothing', l10n.storeRestoreNothing);
      case RestoreOutcome.error:
        _snack('snackbar_store_restore_error', l10n.storeRestoreError);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Palier pas encore connu : ni offre ni bouton (un abonné ne doit jamais
    // voir, même un instant, de quoi acheter une seconde fois).
    final tier = ref.watch(landlordTierProvider);
    if (tier.isLoading && !tier.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }
    // Déjà Pro (toute origine) : aucun achat proposé. C'est aussi ce qui
    // termine l'attente d'activation.
    if (ref.watch(planEntitlementProvider).atLeast(PlanLevel.pro)) {
      _timer?.cancel();
      _phase = _Phase.offers;
      return StoreAlreadySubscribedView(
        onManage: () => context.go('/profile'),
      );
    }
    return switch (_phase) {
      _Phase.activating => const StoreActivatingView(),
      _Phase.delayed => StoreActivationDelayedView(
        busy: _busy,
        onRestore: _restore,
        onRetry: _startActivation,
      ),
      _Phase.offers => ref
          .watch(storeProOfferProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => StoreOfferUnavailableView(
              onRetry: () => ref.invalidate(storeProOfferProvider),
            ),
            data: (offer) =>
                offer == null || (offer.monthly == null && offer.annual == null)
                ? StoreOfferUnavailableView(
                    onRetry: () => ref.invalidate(storeProOfferProvider),
                  )
                : StoreOffersView(
                    offer: offer,
                    busy: _busy,
                    onBuy: _buy,
                    onRestore: _restore,
                  ),
          ),
    };
  }
}
```

`pro_store_paywall_views.dart` — cinq widgets sans état, chacun centré, largeur max 560, dans un `SingleChildScrollView(padding: EdgeInsets.all(24))` :

- `StoreOffersView({required ProStoreOffer offer, required bool busy, required void Function(ProStorePackage) onBuy, required VoidCallback onRestore})` : titre `l10n.storePaywallHeadline` ; accroche `proPricingTaglineFor(context, 'pro')` ; avantages `proPricingBulletsFor(context, 'pro')` (une ligne par avantage, icône `Icons.check`) ; puis, **dans cet ordre** : `FilledButton` `btn_store_buy_annual` (`l10n.storeBuyAnnualButton(offer.annual!.priceString)`) si `offer.annual != null`, `OutlinedButton` `btn_store_buy_monthly` (`l10n.storeBuyMonthlyButton(...)`) si `offer.monthly != null`, `TextButton` `btn_store_restore` (`l10n.storeRestoreButton`) ; les trois avec `onPressed: busy ? null : …` ; puis `StoreLegalNotice()`.
- `StoreLegalNotice()` : `Text(l10n.storeLegalNotice(storeNameForPlatform(defaultTargetPlatform)), key: Key('txt_store_legal_notice'), style: bodySmall)` puis une `Wrap` de deux `TextButton` : `link_store_terms` → `context.push('/terms')`, `link_store_privacy` → `context.push('/privacy')`.
- `StoreActivatingView()` : `CircularProgressIndicator`, `Text(l10n.storeActivatingTitle, key: Key('txt_store_activating'))`, `Text(l10n.storeActivatingBody)`.
- `StoreActivationDelayedView({required bool busy, required VoidCallback onRestore, required VoidCallback onRetry})` : `Text(l10n.storeActivationDelayedBody, key: Key('txt_store_activation_delayed'))`, `FilledButton.tonal` `btn_store_activation_retry` (`l10n.commonRetry`, `onPressed: busy ? null : onRetry`), `TextButton` `btn_store_activation_restore` (`l10n.storeRestoreButton`, `onPressed: busy ? null : onRestore`).
- `StoreAlreadySubscribedView({required VoidCallback onManage})` : icône `Icons.verified_outlined`, `Text(l10n.storeAlreadySubscribed, key: Key('txt_store_already_subscribed'))`, `FilledButton.tonal` `btn_store_manage_subscription` (`l10n.storeManageSubscriptionButton`).
- `StoreOfferUnavailableView({required VoidCallback onRetry})` : `Text(l10n.storeOfferUnavailable, key: Key('txt_store_offer_unavailable'))`, `FilledButton.tonal` `btn_store_offer_retry` (`l10n.commonRetry`).

Aucune de ces vues n'affiche un prix web, Max, Ultra, ni un lien vers le site.

`pro_pricing_page.dart` — dans `build`, remplacer le début de la branche `if (isStoreApp) {` par :

```dart
    if (isStoreApp) {
      return Scaffold(
        appBar: AppAppBar(
          title: l10n.proPricingTitle,
          fallbackRoute: '/profile',
        ),
        body: SafeArea(
          // Achat intégré actif : écran d'achat du store. Sinon message
          // neutre, comme avant FEAT-044e.
          child: isInAppPurchaseEnabled
              ? const ProStorePaywall()
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      l10n.proStoreAppUnavailable,
                      key: const Key('txt_pro_store_app_unavailable'),
                      style: Theme.of(context).textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
        ),
      );
    }
```

(+ import `widgets/pro_store_paywall.dart`.) Mettre à jour le dernier paragraphe du commentaire de classe : dans les apps, message neutre tant que l'achat intégré est coupé ; sinon `ProStorePaywall` (Pro uniquement, prix du store, jamais Max/Ultra ni prix web).

- [ ] **Step 5: Vérifier**

Run: `flutter gen-l10n && flutter test test/widget/pro_store_paywall_test.dart test/widget/pro_pricing_page_test.dart test/widget/pro_pricing_cta_test.dart && dart format lib test && flutter analyze && flutter test`
Expected: tout PASS ; « No issues found! ».

- [ ] **Step 6: Commit**

```bash
git add lib/features/paid_plan/application/store_offer_provider.dart lib/features/paid_plan/presentation/widgets/pro_store_paywall.dart lib/features/paid_plan/presentation/widgets/pro_store_paywall_views.dart lib/features/paid_plan/presentation/pro_pricing_page.dart lib/l10n/app_en.arb lib/l10n/app_fr.arb test/widget/pro_store_paywall_test.dart
git commit -m "feat(iap): écran d'achat des apps sur /pro — offres du store, activation, restauration (FEAT-044e lot 3)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Profil — « Gérer dans le store » et bannière « Passer à Pro » dans les apps

**Files:**
- Modify: `lib/features/paid_plan/presentation/widgets/subscription_section.dart`
- Modify: `lib/features/profile/presentation/profile_page.dart` (`proUpsellVisible` et son appel dans `_ProUpsellCard`)
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_fr.arb`
- Test: `test/widget/subscription_section_test.dart`, `test/widget/profile_page_test.dart`

**Interfaces:**
- Consumes: `StoreBillingService.managementUrl()`, `storeBillingServiceProvider`, `FakeStoreBillingService.management` ; `storeNameForProStore`, `storeManagementFallbackUri` (Task 1) ; `isInAppPurchaseEnabled` ; `url_launcher` (`launchUrl`, `LaunchMode.externalApplication`).
- Produces: clé `btn_subscription_manage_in_store` ; `proUpsellVisible({required bool subscriptionsEnabled, required bool storeApp, required bool inAppPurchaseEnabled, required bool isPaid})`.

- [ ] **Step 1: Texte** — `subscriptionManageInStoreButton` (`store` String) : FR « Gérer dans {store} », EN « Manage in {store} » (description « FEAT-044e — … »).

- [ ] **Step 2: Écrire les tests qui échouent**

`test/widget/subscription_section_test.dart` — les deux tests « proStore == app_store / play_store → message store, aucun bouton » deviennent « … → message store + bouton Gérer » :
- `txt_subscription_manage_on_store` toujours présent ; `btn_subscription_manage_in_store` présent, libellé « Gérer dans App Store » / « Gérer dans Google Play » ; toujours **aucun** bouton Résilier / Réactiver / Changer d'offre.
- Tap, service sans URL (`fake.management = null`) → le lanceur d'URL factice reçoit `https://apps.apple.com/account/subscriptions` (resp. `https://play.google.com/store/account/subscriptions`).
- Tap, `fake.management = Uri.parse('https://example.test/manage')` → cette URL est ouverte.
- Lanceur factice : reprendre le faux `UrlLauncherPlatform` de `test/widget/tenant_card_test.dart` (`_FakeUrlLauncher`, `UrlLauncherPlatform.instance = …`, restauré en `tearDown`). Overrides : ajouter `storeBillingServiceProvider.overrideWithValue(fake)` au montage de ces tests.
- Le groupe existant « app store (iOS/Android) » (`for (final store in ['app_store', 'play_store'])`, ~l.608) doit rester vert : adapter seulement l'assertion « aucun bouton » si elle visait tous les boutons (le bouton « Gérer » est désormais attendu).

`test/widget/profile_page_test.dart` — groupe `proUpsellVisible` : ajouter `inAppPurchaseEnabled:` à chaque appel existant (`false`, attentes inchangées) et deux cas : app store + achat intégré actif + non payant → `true` (même si `subscriptionsEnabled` est `false`) ; app store + achat intégré actif + déjà payant → `false`.

- [ ] **Step 3: Vérifier qu'ils échouent**

Run: `flutter gen-l10n && flutter test test/widget/subscription_section_test.dart test/widget/profile_page_test.dart`
Expected: échec (bouton absent, paramètre inconnu).

- [ ] **Step 4: Implémenter**

`subscription_section.dart` — remplacer le bloc `if (isMobileStore) Text(…)` par :

```dart
        if (isMobileStore) ...[
          Text(
            l10n.subscriptionManageOnStore,
            key: const Key('txt_subscription_manage_on_store'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('btn_subscription_manage_in_store'),
            onPressed: () => _openStoreManagement(ref, snapshot.proStore),
            child: Text(
              l10n.subscriptionManageInStoreButton(
                storeNameForProStore(snapshot.proStore),
              ),
            ),
          ),
        ] else if (snapshot.proWillRenew == false)
```

et ajouter la méthode (aucun `context` ni `ref` après l'`await`) :

```dart
  /// Ouvre la page de gestion de l'abonnement du store D'ORIGINE : l'URL de
  /// RevenueCat si elle est connue, sinon la page générique du store.
  Future<void> _openStoreManagement(WidgetRef ref, String? proStore) async {
    final service = ref.read(storeBillingServiceProvider);
    final uri =
        await service.managementUrl() ?? storeManagementFallbackUri(proStore);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
```

(imports : `package:url_launcher/url_launcher.dart`, `../../data/store_billing_service.dart`, `../../domain/store_names.dart`.) Mettre à jour le commentaire de classe : pour un abonné store, message + bouton « Gérer dans {store} » (store d'origine), sur le web comme dans les apps.

`profile_page.dart` :

```dart
@visibleForTesting
bool proUpsellVisible({
  required bool subscriptionsEnabled,
  required bool storeApp,
  required bool inAppPurchaseEnabled,
  required bool isPaid,
}) => (storeApp ? inAppPurchaseEnabled : subscriptionsEnabled) && !isPaid;
```

et l'appel dans `_ProUpsellCard.build` : ajouter `inAppPurchaseEnabled: isInAppPurchaseEnabled,`. Mettre à jour les deux commentaires voisins (la bannière s'affiche dans une app store dès que l'achat intégré est actif ; sur le web, dès que les abonnements sont ouverts).

- [ ] **Step 5: Vérifier**

Run: `flutter gen-l10n && flutter test test/widget/subscription_section_test.dart test/widget/profile_page_test.dart && dart format lib test && flutter analyze && flutter test`
Expected: tout PASS ; « No issues found! ».

- [ ] **Step 6: Commit**

```bash
git add lib/features/paid_plan/presentation/widgets/subscription_section.dart lib/features/profile/presentation/profile_page.dart lib/l10n/app_en.arb lib/l10n/app_fr.arb test/widget/subscription_section_test.dart test/widget/profile_page_test.dart
git commit -m "feat(iap): « Gérer dans le store » et bannière Pro dans les apps (FEAT-044e lot 3)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Documentation et état

**Files:**
- Modify: `docs/state/routes/account.md`, `docs/state/FEATURES.md`, `docs/state/CHANGELOG.md`, `docs/MOBILE.md`, `docs/STORE_COMPLIANCE.md`

- [ ] **Step 1: `docs/state/routes/account.md`** — ligne `/pro` : dans les apps, message neutre tant que `IAP_ENABLED` est coupé ; sinon `ProStorePaywall` (Pro mensuel/annuel aux prix du store, « Restaurer les achats », « Activation en cours… » jusqu'à ce que le serveur accorde le droit, délai 60 s, « Vous êtes déjà abonné » ; jamais Max/Ultra ni prix web). Ligne `/profile` : bouton « Gérer dans {store} » pour un abonné store ; bannière « Passer à Pro » visible dans une app store quand l'achat intégré est actif.

- [ ] **Step 2: `docs/state/FEATURES.md`** — ligne FEAT-044e : remplacer « lot 3 📋 » par « lot 3 (écran d'achat des apps : offres du store, activation, restauration, gérer dans le store) 🚧 branche `feat/044e-iap-store-paywall` ». Garder la mention que l'interrupteur reste coupé tant que les produits des stores ne sont pas créés (#207).

- [ ] **Step 3: `docs/state/CHANGELOG.md`** — entrée en tête de la période courante `### FEAT-044e lot 3 : achat intégré, écran d'achat des apps (2026-10-10)`, 4 puces : rattachement garanti avant achat (`purchase`/`restore` avec uid) ; écran d'achat sur `/pro` (Pro seul, prix du store, activation attendue du serveur, 60 s) ; profil (« Gérer dans {store} », bannière) ; toujours derrière `IAP_ENABLED` coupé.

- [ ] **Step 4: `docs/MOBILE.md`** — section « Achat intégré (FEAT-044e) » : retirer « Ne pas activer avant le lot 3 » ; écrire que le code est complet et que l'activation n'attend plus que la checklist #207 (produits App Store Connect et Play Console, offre RevenueCat par défaut avec les formules mensuelle et annuelle, compte de démo dans `_ops/sandboxAllowlist`, RevenueCat déclaré comme sous-traitant, build Android release vérifié), puis un build avec `IAP_ENABLED=true` et les clés.

- [ ] **Step 5: `docs/STORE_COMPLIANCE.md`** — ajouter une sous-section datée « Achat intégré (FEAT-044e lot 3) — 2026-10-10 » : 3.1.1 (seul l'achat intégré est proposé dans les apps, aucun prix web) ; 3.1.2 (mentions de renouvellement et de résiliation + liens CGU et confidentialité sur l'écran d'achat, « Restaurer les achats ») ; 2.1 (Max et Ultra non affichés dans les apps) ; 3.1.3(b) (un abonné web retrouve Pro dans l'app : « Vous êtes déjà abonné »).

- [ ] **Step 6: Commit**

```bash
git add docs/state/routes/account.md docs/state/FEATURES.md docs/state/CHANGELOG.md docs/MOBILE.md docs/STORE_COMPLIANCE.md
git commit -m "docs(iap): écran d'achat des apps — état, conformité, activation (FEAT-044e lot 3)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
