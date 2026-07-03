import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _log = Logger('RailExpandedStorage');

/// Persiste l'état déplié/replié du rail de navigation (desktop, ≥600 px) via
/// [SharedPreferences] — préférence locale au navigateur/appareil.
///
/// Clé : `nav_rail_expanded`. Sans objet sur mobile (<600 px : NavigationBar).
class RailExpandedStorage {
  static const _key = 'nav_rail_expanded';

  /// Lit l'état stocké. Retourne `null` si l'utilisateur n'a jamais choisi.
  Future<bool?> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key);
  }

  /// Persiste le choix déplié (`true`) / replié (`false`).
  Future<void> write(bool expanded) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, expanded);
    _log.fine('RailExpandedStorage.write($expanded)');
  }
}

/// Provider du storage [RailExpandedStorage].
final railExpandedStorageProvider = Provider<RailExpandedStorage>(
  (ref) => RailExpandedStorage(),
);

/// Notifier de l'état déplié/replié du rail, persisté.
///
/// Démarre replié (`false` : rail compact, icônes + libellés courts) puis
/// charge la préférence stockée. Replié par défaut = un maximum de place au
/// contenu ; l'utilisateur déplie via le bouton menu (icône + libellé au
/// large, façon sidebar Gmail/Linear).
class RailExpandedNotifier extends StateNotifier<bool> {
  RailExpandedNotifier(this._storage) : super(false) {
    _load();
  }

  final RailExpandedStorage _storage;

  Future<void> _load() async {
    final stored = await _storage.read();
    if (stored != null && mounted) state = stored;
  }

  /// Bascule déplié ↔ replié et persiste.
  Future<void> toggle() async {
    state = !state;
    await _storage.write(state);
  }
}

/// Provider de l'état déplié/replié du rail de navigation.
final railExpandedProvider = StateNotifierProvider<RailExpandedNotifier, bool>(
  (ref) => RailExpandedNotifier(ref.read(railExpandedStorageProvider)),
);
