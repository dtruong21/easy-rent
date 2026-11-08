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
