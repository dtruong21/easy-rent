/// Variables d'environnement Baillan.
///
/// Post FEAT-019 (migration Firebase) : on conserve uniquement `APP_ENV`
/// pour distinguer prod / dev.
///
/// ⚠️ `APP_ENV` pilote des comportements applicatifs (SEO `noindex`, URLs
/// publiques, bandeaux de dev) ET, depuis l'**ADR 0003**, la **base Firestore**
/// utilisée : prod → `(default)`, staging déployé → base nommée `dev`
/// (isolation des données). Le **projet Firebase** (`easy-rent-54cd4`), l'**Auth**
/// et le **Storage** restent partagés entre prod et staging.
///
/// Le routage de la base ne se fait PAS via `Env.isProd` en dur dans le code
/// applicatif : il est centralisé dans `firestoreProvider`
/// ([lib/core/config/firestore_provider.dart]). Ne jamais appeler
/// `FirebaseFirestore.instance` directement dans un repo/provider.
///
/// L'émulateur local reste l'environnement le plus isolé (Firestore + Auth +
/// Functions locaux) — voir [Env.useFirebaseEmulator] et `docs/ENVIRONMENTS.md`.
///
/// Valeurs Firebase (apiKey, projectId, etc.) sont dans
/// `lib/firebase_options.dart` (publiques par design).
///
/// Injecter via `--dart-define-from-file=dart-defines.json` :
/// ```json
/// { "APP_ENV": "prod" }
/// ```
library;

import 'package:flutter/foundation.dart' show kDebugMode, kReleaseMode;

class Env {
  const Env._();

  static const String appEnv = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'dev',
  );

  /// URL publique de l'app web (sans slash final).
  ///
  /// Sert de fallback aux liens email Firebase (vérification, reset password)
  /// quand `Uri.base.origin` n'est pas résoluble — c'est-à-dire sur les
  /// builds mobiles iOS/Android (FEAT-024) : les pages /login et
  /// /reset-password restent hébergées par l'app web. Sur le web, l'origin
  /// courant (prod ou channel staging) reste prioritaire.
  ///
  /// ⚠️ Ce domaine DOIT figurer dans les **domaines autorisés** de Firebase
  /// Auth (Console → Authentication → Settings), sinon les liens email
  /// (vérification, reset password) et les connexions Google/Apple échouent.
  static const String publicAppUrl = String.fromEnvironment(
    'APP_PUBLIC_URL',
    defaultValue: 'https://baillan.com',
  );

  /// `true` si on tourne en environnement de prod.
  static bool get isProd => appEnv == 'prod';

  /// `true` si on tourne en environnement de dev/staging.
  static bool get isDev => !isProd;

  /// Flag opt-in brut du branchement émulateurs Firebase (dart-define).
  /// NE PAS lire directement — passer par [useFirebaseEmulator], qui ajoute le
  /// garde-fou release.
  static const bool _useEmulatorFlag = bool.fromEnvironment(
    'USE_FIREBASE_EMULATOR',
    defaultValue: false,
  );

  /// `true` uniquement en build DEBUG **et** avec `USE_FIREBASE_EMULATOR=true`.
  ///
  /// Double garde-fou volontaire : le `kDebugMode` garantit qu'un build
  /// release ou profile ne branchera JAMAIS les émulateurs, même si le
  /// dart-define fuit dans la commande de build. Sans ça, un build de prod
  /// avec le flag activé pointerait les vrais utilisateurs vers un backend
  /// local inexistant (app cassée). C'est un toggle de dev pur.
  static bool get useFirebaseEmulator => kDebugMode && _useEmulatorFlag;

  static const bool _mobileStagingFlag = bool.fromEnvironment(
    'MOBILE_STAGING',
    defaultValue: false,
  );

  /// Build de test mobile (Firebase Test Lab) sur la base `staging`.
  ///
  /// Double garde, comme [useFirebaseEmulator] : `kReleaseMode` garantit qu'un
  /// build publié sur les stores ne vise JAMAIS staging, même si le
  /// dart-define fuit dans la commande de release.
  static bool get useMobileStaging => !kReleaseMode && _mobileStagingFlag;

  static const String _testAutoLoginEmail = String.fromEnvironment(
    'TEST_AUTO_LOGIN_EMAIL',
  );
  static const String _testAutoLoginPassword = String.fromEnvironment(
    'TEST_AUTO_LOGIN_PASSWORD',
  );

  /// Compte de test staging-only pour la connexion automatique du build Test
  /// Lab (Robo ne sait pas remplir un formulaire Flutter). `null` hors build
  /// de test ou si l'un des deux champs est vide. Fourni au build par
  /// `dart-defines.testlab.json` (gitignoré) — jamais commité.
  static ({String email, String password})? get testAutoLoginCredentials {
    if (!useMobileStaging) return null;
    if (_testAutoLoginEmail.isEmpty || _testAutoLoginPassword.isEmpty) {
      return null;
    }
    return (email: _testAutoLoginEmail, password: _testAutoLoginPassword);
  }

  /// Hôte des émulateurs Firebase. Défaut `127.0.0.1` (PAS `localhost`) :
  /// sur le web, Chromium résout `localhost` en IPv6 `::1`, or les émulateurs
  /// firebase-tools n'écoutent que sur l'IPv4 `127.0.0.1` — l'app tombait alors
  /// silencieusement sur le backend PROD (login en `invalid-credential`).
  /// `127.0.0.1` force l'IPv4 et marche partout (web/desktop/simulateur iOS).
  /// L'émulateur **Android** doit utiliser `10.0.2.2` (alias de la machine hôte
  /// vu depuis la VM) : `--dart-define=FIREBASE_EMULATOR_HOST=10.0.2.2`.
  static const String firebaseEmulatorHost = String.fromEnvironment(
    'FIREBASE_EMULATOR_HOST',
    defaultValue: '127.0.0.1',
  );

  /// Ports des émulateurs — défauts firebase-tools (alignés sur
  /// `tool/seed/seed_tiers.mjs`). Surchargeables par dart-define quand un autre
  /// projet local occupe déjà les ports par défaut.
  static const int firestoreEmulatorPort = int.fromEnvironment(
    'FIRESTORE_EMULATOR_PORT',
    defaultValue: 8080,
  );
  static const int authEmulatorPort = int.fromEnvironment(
    'AUTH_EMULATOR_PORT',
    defaultValue: 9099,
  );
  static const int functionsEmulatorPort = int.fromEnvironment(
    'FUNCTIONS_EMULATOR_PORT',
    defaultValue: 5001,
  );
  static const int storageEmulatorPort = int.fromEnvironment(
    'STORAGE_EMULATOR_PORT',
    defaultValue: 9199,
  );

  /// `true` si le checkout Stripe / les CTA « S'abonner » à Baillan Pro
  /// sont activés. **Défaut `false`** : MVP freemium web (~1 mois de test,
  /// juillet 2026) — le fondateur n'a pas encore de micro-entreprise pour
  /// encaisser via Stripe.
  ///
  /// Ce flag NE supprime AUCUN code paid-plan (checkout, gestion
  /// d'abonnement, repos Stripe/RevenueCat) : il gate uniquement l'UI qui
  /// mène au paiement (`ProPricingPage`, upsell `/profile`). La page `/pro`
  /// reste atteignable à `false` mais affiche un état « bientôt disponible »
  /// + capture d'intérêt (`paid_plan_interest`) au lieu du bouton Stripe —
  /// jamais d'impasse.
  ///
  /// **Politique par environnement** (pilotée par `.github/workflows/deploy.yml`,
  /// sortie `subscriptions_enabled` de `determine-env`) :
  /// - **staging** (`develop` → app.staging.baillan.com) : `true` — le parcours
  ///   d'abonnement reste ouvert pour poursuivre le développement.
  /// - **production** (`main` → baillan.com) : `false` — fermé pendant la beta
  ///   v1 freemium, ouverture prévue ~2026-08-25.
  ///
  /// Le `defaultValue: false` ci-dessous est le **mode d'échec sûr** : un build
  /// sans dart-define (tests, build local, CI amputée de la sortie) reste
  /// fermé. La prod ne peut donc pas s'ouvrir par oubli, seulement par choix
  /// explicite.
  ///
  /// **Ouverture du Pro en prod** : passer la ligne `subscriptions_enabled=false`
  /// de la branche prod de `deploy.yml` à `true`. Aucun changement de code Dart.
  static const bool subscriptionsEnabled = bool.fromEnvironment(
    'SUBSCRIPTIONS_ENABLED',
    defaultValue: false,
  );
}
