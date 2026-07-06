import 'package:flutter/material.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'locale_storage.dart';

/// Provider du storage [LocaleStorage].
final localeStorageProvider = Provider<LocaleStorage>((ref) => LocaleStorage());

/// Notifier qui gère la [Locale] choisie par l'utilisateur et la persiste.
///
/// Démarre sur `null` (= suit le système, résolu par
/// `MaterialApp.localeResolutionCallback`) puis charge la préférence
/// stockée. Même compromis que `ThemeModeNotifier` (FEAT-023) : la lecture
/// localStorage est quasi-immédiate sur le web, le premier frame suit le
/// système au pire.
class LocaleNotifier extends StateNotifier<Locale?> {
  LocaleNotifier(this._storage) : super(null) {
    _load();
  }

  final LocaleStorage _storage;

  Future<void> _load() async {
    final stored = await _storage.read();
    if (stored != null && mounted) {
      state = Locale(stored);
    }
  }

  /// Change la langue et la persiste. `null` = réinitialise sur « Système ».
  Future<void> setLocale(Locale? locale) async {
    state = locale;
    await _storage.write(locale?.languageCode);
  }
}

/// Provider de la [Locale] utilisateur (Système / Français / English).
///
/// `null` = suit le système (résolution via `localeResolutionCallback` dans
/// `main.dart`). Watché par [MaterialApp.router] — PAS autoDispose : vivant
/// toute la session.
///
/// Usage :
/// ```dart
/// final locale = ref.watch(localeProvider);
/// ref.read(localeProvider.notifier).setLocale(const Locale('en'));
/// ```
final localeProvider = StateNotifierProvider<LocaleNotifier, Locale?>(
  (ref) => LocaleNotifier(ref.read(localeStorageProvider)),
);
