import 'package:flutter/material.dart' show ThemeMode;
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _log = Logger('ThemeModeStorage');

/// Persiste le [ThemeMode] choisi par l'utilisateur via [SharedPreferences]
/// (localStorage sur le web — préférence locale au navigateur, pas de
/// synchronisation entre appareils).
///
/// Clé utilisée : `theme_mode` (valeurs : `system` / `light` / `dark`).
class ThemeModeStorage {
  static const _key = 'theme_mode';

  /// Lit le [ThemeMode] stocké. Retourne `null` si aucune valeur n'est
  /// persistée ou si la valeur est inconnue.
  Future<ThemeMode?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key);
    if (value == null) return null;

    final mode = ThemeMode.values.where((m) => m.name == value).firstOrNull;
    _log.fine('ThemeModeStorage.read() → $mode');
    return mode;
  }

  /// Persiste le [ThemeMode] choisi.
  Future<void> write(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
    _log.fine('ThemeModeStorage.write(${mode.name})');
  }
}
