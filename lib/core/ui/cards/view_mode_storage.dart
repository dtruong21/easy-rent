import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'view_mode.dart';

final _log = Logger('ViewModeStorage');

/// Persiste le [ViewMode] par page via [SharedPreferences].
///
/// Clé utilisée : `view_mode_{pageKey}` (ex : `view_mode_leases`).
class ViewModeStorage {
  static const _keyPrefix = 'view_mode_';

  /// Lit le [ViewMode] stocké pour la page [pageKey].
  /// Retourne `null` si aucune valeur n'est persistée.
  Future<ViewMode?> read(String pageKey) async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString('$_keyPrefix$pageKey');
    if (value == null) return null;

    final mode = ViewMode.values.where((m) => m.name == value).firstOrNull;
    _log.fine('ViewModeStorage.read($pageKey) → $mode');
    return mode;
  }

  /// Persiste le [ViewMode] pour la page [pageKey].
  Future<void> write(String pageKey, ViewMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_keyPrefix$pageKey', mode.name);
    _log.fine('ViewModeStorage.write($pageKey, ${mode.name})');
  }

  /// Supprime la valeur persistée pour la page [pageKey].
  Future<void> clear(String pageKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_keyPrefix$pageKey');
    _log.fine('ViewModeStorage.clear($pageKey)');
  }
}
