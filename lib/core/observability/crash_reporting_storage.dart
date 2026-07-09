import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _log = Logger('CrashReportingStorage');

/// Persiste le consentement au rapport d'incident (Firebase Crashlytics) via
/// [SharedPreferences]. **Opt-in** : l'absence de valeur = refus (`false`).
///
/// Clé : `crash_reporting_enabled` (bool). Préférence locale à l'appareil
/// (pas de synchronisation entre appareils). Sans objet sur le web (Crashlytics
/// n'a pas d'implémentation web) mais la clé reste lisible sans erreur.
class CrashReportingStorage {
  static const _key = 'crash_reporting_enabled';

  /// Lit le consentement stocké. Retourne `null` si l'utilisateur n'a jamais
  /// choisi — traité comme refus (opt-in désactivé par défaut).
  Future<bool?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getBool(_key);
    _log.fine('CrashReportingStorage.read() → $value');
    return value;
  }

  /// Persiste le choix explicite de l'utilisateur.
  Future<void> write(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, enabled);
    _log.fine('CrashReportingStorage.write($enabled)');
  }
}
