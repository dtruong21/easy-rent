import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/chart_format.dart';

final _log = Logger('ChartFormatStorage');

/// Persiste le [ChartFormat] du graphique loyers via [SharedPreferences]
/// (localStorage sur le web — préférence locale au navigateur).
class ChartFormatStorage {
  static const _key = 'chart_format_monthly';

  /// Lit le format stocké. Retourne `null` si absent ou inconnu.
  Future<ChartFormat?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final format = ChartFormat.fromName(prefs.getString(_key));
    _log.fine('ChartFormatStorage.read() → $format');
    return format;
  }

  /// Persiste le format choisi.
  Future<void> write(ChartFormat format) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, format.name);
    _log.fine('ChartFormatStorage.write(${format.name})');
  }
}

/// Provider du storage [ChartFormatStorage].
final chartFormatStorageProvider = Provider<ChartFormatStorage>(
  (ref) => ChartFormatStorage(),
);

/// Notifier qui gère le [ChartFormat] du graphique loyers et le persiste.
///
/// Démarre sur [ChartFormat.bars] puis charge la préférence stockée (même
/// compromis que `ThemeModeNotifier` : lecture localStorage quasi-immédiate,
/// le premier frame affiche les barres au pire).
class ChartFormatNotifier extends StateNotifier<ChartFormat> {
  ChartFormatNotifier(this._storage) : super(ChartFormat.bars) {
    _load();
  }

  final ChartFormatStorage _storage;

  Future<void> _load() async {
    final stored = await _storage.read();
    if (stored != null && mounted) {
      state = stored;
    }
  }

  /// Change le format et le persiste en [SharedPreferences].
  Future<void> setFormat(ChartFormat format) async {
    state = format;
    await _storage.write(format);
  }
}

/// Provider du [ChartFormat] du graphique « Loyers » (période variable).
final chartFormatProvider =
    StateNotifierProvider<ChartFormatNotifier, ChartFormat>(
      (ref) => ChartFormatNotifier(ref.read(chartFormatStorageProvider)),
    );
