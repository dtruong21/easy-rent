import 'package:flutter/foundation.dart';

import 'env.dart';

/// Vrai dans les apps iOS/Android distribuées par l'App Store et Google Play.
/// Tout achat numérique doit y passer par l'achat intégré du store (App Store
/// 3.1.1, règle Paiements de Google Play) : Stripe, les prix et le changement
/// d'offre n'y sont jamais proposés, ni aucun lien vers le site pour acheter.
/// Le web garde le parcours Stripe.
bool get isStoreApp =>
    debugIsStoreAppOverride ??
    (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android));

/// Forçage pour les tests (flutter_test simule Android par défaut).
@visibleForTesting
bool? debugIsStoreAppOverride;

/// Clé SDK RevenueCat de [platform], ou `null` si absente ou si la plateforme
/// n'a pas d'achat intégré. Valeurs par défaut : dart-defines ; injectables
/// pour les tests.
String? revenueCatApiKeyFor(
  TargetPlatform platform, {
  String appleKey = Env.revenueCatAppleApiKey,
  String googleKey = Env.revenueCatGoogleApiKey,
}) {
  final key = switch (platform) {
    TargetPlatform.iOS => appleKey,
    TargetPlatform.android => googleKey,
    _ => '',
  }.trim();
  return key.isEmpty ? null : key;
}

/// FEAT-044e — achat intégré actif : app store + `IAP_ENABLED` + clé
/// RevenueCat de la plateforme. Clé absente : achat coupé (log `severe` au
/// démarrage par `storeBillingSessionSyncProvider`), jamais de crash.
bool get isInAppPurchaseEnabled =>
    debugInAppPurchaseEnabledOverride ??
    (isStoreApp &&
        Env.iapEnabled &&
        revenueCatApiKeyFor(defaultTargetPlatform) != null);

/// Forçage pour les tests.
@visibleForTesting
bool? debugInAppPurchaseEnabledOverride;

/// Prédicat UNIQUE des textes d'incitation (« Passez à Pro… », CTA vers
/// `/pro`) : vrai sur le web (Stripe) et dans une app store dont l'achat
/// intégré est actif ; faux dans une app store sans achat intégré (App Store
/// 3.1.1, règle Paiements de Google Play).
bool get canOfferUpgrade => !isStoreApp || isInAppPurchaseEnabled;
