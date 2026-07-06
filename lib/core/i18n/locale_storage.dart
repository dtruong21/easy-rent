import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _log = Logger('LocaleStorage');

/// Locales supportées par l'app (FEAT-043). Calque de `AppLocalizations
/// .supportedLocales`, dupliqué ici pour éviter une dépendance de ce
/// fichier bas-niveau vers le code généré `app_localizations.dart`.
const supportedLocaleCodes = <String>{'fr', 'en'};

/// Persiste la préférence de langue choisie par l'utilisateur via
/// [SharedPreferences] (localStorage sur le web — préférence locale au
/// navigateur, pas de synchronisation entre appareils).
///
/// Clé utilisée : `app_locale` (valeurs : `fr` / `en`, absent = système).
/// Même pattern que `ThemeModeStorage` (FEAT-023).
class LocaleStorage {
  static const _key = 'app_locale';

  /// Lit le code de langue stocké. Retourne `null` si aucune valeur n'est
  /// persistée ou si la valeur est inconnue (= suit le système).
  Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key);
    if (value == null) return null;

    if (!supportedLocaleCodes.contains(value)) {
      _log.fine('LocaleStorage.read() → valeur inconnue "$value", ignorée');
      return null;
    }
    _log.fine('LocaleStorage.read() → $value');
    return value;
  }

  /// Persiste le code de langue choisi. `null` = réinitialise (suit le
  /// système).
  Future<void> write(String? languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    if (languageCode == null) {
      await prefs.remove(_key);
      _log.fine('LocaleStorage.write(null) → préférence effacée (système)');
      return;
    }
    await prefs.setString(_key, languageCode);
    _log.fine('LocaleStorage.write($languageCode)');
  }
}
