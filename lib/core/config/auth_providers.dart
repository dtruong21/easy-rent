import 'package:flutter/foundation.dart';

/// Fournisseurs de connexion proposés en v1 (décision du 2026-10-03).
///
/// - Email / mot de passe : partout.
/// - Google : web et Android. Masqué sur iOS : la règle App Store 4.8 impose
///   une option équivalente respectueuse de la vie privée (« Se connecter avec
///   Apple ») dès qu'une connexion tierce est proposée. Apple n'arrivant
///   qu'après la v1, l'app iOS reste en email / mot de passe seul, cas
///   explicitement exempté par la 4.8.
/// - Apple : masqué partout jusqu'après la v1 (la capacité Sign in with Apple
///   n'est pas configurée dans le projet iOS). Le code reste en place pour le
///   réactiver : passer [isAppleSignInOffered] à vrai, et rendre Google sur iOS
///   en même temps.
///
/// Seuls les points d'entrée (connexion, inscription, passage d'un essai
/// anonyme à un compte complet) sont filtrés : la ré-authentification d'un
/// compte existant reste possible avec son fournisseur.
bool get isGoogleSignInOffered =>
    debugGoogleSignInOfferedOverride ?? !_isIosApp;

/// Voir [isGoogleSignInOffered].
bool get isAppleSignInOffered => debugAppleSignInOfferedOverride ?? false;

bool get _isIosApp => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// Forçage pour les tests.
@visibleForTesting
bool? debugGoogleSignInOfferedOverride;

/// Forçage pour les tests (scénarios Apple conservés pour la réactivation).
@visibleForTesting
bool? debugAppleSignInOfferedOverride;
