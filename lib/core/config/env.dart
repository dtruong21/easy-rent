/// Variables d'environnement Baillan.
///
/// Post FEAT-019 (migration Firebase) : on conserve uniquement
/// `APP_ENV` pour distinguer prod / dev (le projet Firebase reste le même,
/// la séparation se fait via `(default)` vs `dev` Firestore database).
///
/// Valeurs Firebase (apiKey, projectId, etc.) sont dans
/// `lib/firebase_options.dart` (publiques par design).
///
/// Injecter via `--dart-define-from-file=dart-defines.json` :
/// ```json
/// { "APP_ENV": "prod" }
/// ```
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
  static const String publicAppUrl = String.fromEnvironment(
    'APP_PUBLIC_URL',
    defaultValue: 'https://easy-rent-54cd4.web.app',
  );

  /// `true` si on tourne en environnement de prod.
  static bool get isProd => appEnv == 'prod';

  /// `true` si on tourne en environnement de dev/staging.
  static bool get isDev => !isProd;
}
