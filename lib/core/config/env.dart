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

  /// `true` si on tourne en environnement de prod.
  static bool get isProd => appEnv == 'prod';

  /// `true` si on tourne en environnement de dev/staging.
  static bool get isDev => !isProd;
}
