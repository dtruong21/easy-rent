import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'view_mode.dart';
import 'view_mode_storage.dart';

/// Provider du storage [ViewModeStorage].
final viewModeStorageProvider = Provider<ViewModeStorage>(
  (ref) => ViewModeStorage(),
);

/// Notifier qui gère le [ViewMode] d'une page et le persiste.
class ViewModeNotifier extends StateNotifier<ViewMode> {
  ViewModeNotifier(this.pageKey, this._storage) : super(ViewMode.card) {
    _load();
  }

  /// Identifiant de la page (ex : `'leases'`, `'properties'`).
  final String pageKey;

  final ViewModeStorage _storage;

  Future<void> _load() async {
    final stored = await _storage.read(pageKey);
    if (stored != null && mounted) {
      state = stored;
    }
  }

  /// Change le mode et le persiste en [SharedPreferences].
  Future<void> setMode(ViewMode mode) async {
    state = mode;
    await _storage.write(pageKey, mode);
  }
}

/// Provider family du [ViewModeNotifier] par [pageKey].
///
/// Usage :
/// ```dart
/// final mode = ref.watch(viewModeProvider('leases'));
/// ref.read(viewModeProvider('leases').notifier).setMode(ViewMode.table);
/// ```
final viewModeProvider = StateNotifierProvider.family
    .autoDispose<ViewModeNotifier, ViewMode, String>(
      (ref, pageKey) =>
          ViewModeNotifier(pageKey, ref.read(viewModeStorageProvider)),
    );
