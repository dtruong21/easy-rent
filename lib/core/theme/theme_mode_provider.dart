import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme_mode_storage.dart';

/// Provider du storage [ThemeModeStorage].
final themeModeStorageProvider = Provider<ThemeModeStorage>(
  (ref) => ThemeModeStorage(),
);

/// Notifier qui gère le [ThemeMode] de l'app et le persiste.
///
/// Démarre sur [ThemeMode.system] puis charge la préférence stockée (même
/// compromis que `ViewModeNotifier` : la lecture localStorage est
/// quasi-immédiate sur le web, le premier frame suit le système au pire).
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier(this._storage) : super(ThemeMode.system) {
    _load();
  }

  final ThemeModeStorage _storage;

  Future<void> _load() async {
    final stored = await _storage.read();
    if (stored != null && mounted) {
      state = stored;
    }
  }

  /// Change le mode et le persiste en [SharedPreferences].
  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    await _storage.write(mode);
  }
}

/// Provider du [ThemeMode] utilisateur (Système / Clair / Sombre).
///
/// Watché par [MaterialApp.router] dans `main.dart` — PAS autoDispose :
/// vivant toute la session.
///
/// Usage :
/// ```dart
/// final mode = ref.watch(themeModeProvider);
/// ref.read(themeModeProvider.notifier).setMode(ThemeMode.dark);
/// ```
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
  (ref) => ThemeModeNotifier(ref.read(themeModeStorageProvider)),
);
