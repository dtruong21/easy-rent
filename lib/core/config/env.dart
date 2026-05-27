/// Variables d'environnement injectées via `--dart-define-from-file`.
///
/// Exemple :
/// ```
/// flutter run --dart-define-from-file=dart-defines.json
/// ```
class Env {
  const Env._();

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  /// Schéma Postgres utilisé par le client : `public` (PROD) ou `dev` (DEV).
  /// Voir docs/ENVIRONMENTS.md pour la stratégie multi-env.
  static const String supabaseSchema = String.fromEnvironment(
    'SUPABASE_SCHEMA',
    defaultValue: 'public',
  );

  /// Préfixe utilisé pour les chemins Storage : `prod` ou `dev`.
  /// Dérivé du schéma pour cohérence.
  static String get storageEnvPrefix =>
      supabaseSchema == 'public' ? 'prod' : 'dev';

  /// Vrai si on tourne en environnement de prod.
  static bool get isProd => supabaseSchema == 'public';

  /// Vrai si on tourne en environnement de dev/staging.
  static bool get isDev => !isProd;

  /// Vrai si toutes les variables critiques sont configurées.
  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
