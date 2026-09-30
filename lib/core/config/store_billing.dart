import 'package:flutter/foundation.dart';

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
