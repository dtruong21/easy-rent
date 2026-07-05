import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/chart_period.dart';

final _log = Logger('ChartPeriodStorage');

/// Persiste le [ChartPeriod] du graphique loyers via [SharedPreferences]
/// (localStorage sur le web — préférence locale au navigateur).
class ChartPeriodStorage {
  static const _key = 'chart_period_monthly';

  /// Lit la période stockée. Retourne `null` si absente ou inconnue.
  Future<ChartPeriod?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final period = ChartPeriod.fromName(prefs.getString(_key));
    _log.fine('ChartPeriodStorage.read() → $period');
    return period;
  }

  /// Persiste la période choisie.
  Future<void> write(ChartPeriod period) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, period.name);
    _log.fine('ChartPeriodStorage.write(${period.name})');
  }
}

/// Provider du storage [ChartPeriodStorage].
final chartPeriodStorageProvider = Provider<ChartPeriodStorage>(
  (ref) => ChartPeriodStorage(),
);

/// Notifier qui gère le [ChartPeriod] du graphique loyers et le persiste.
///
/// Démarre sur [ChartPeriod.m6] puis charge la préférence stockée (même
/// compromis que `ThemeModeNotifier` : lecture localStorage quasi-immédiate,
/// le premier frame affiche 6 mois au pire).
class ChartPeriodNotifier extends StateNotifier<ChartPeriod> {
  ChartPeriodNotifier(this._storage) : super(ChartPeriod.m6) {
    _load();
  }

  final ChartPeriodStorage _storage;

  Future<void> _load() async {
    final stored = await _storage.read();
    if (stored != null && mounted) {
      state = stored;
    }
  }

  /// Change la période et la persiste en [SharedPreferences].
  Future<void> setPeriod(ChartPeriod period) async {
    state = period;
    await _storage.write(period);
  }
}

/// Provider du [ChartPeriod] du graphique « Loyers ».
final chartPeriodProvider =
    StateNotifierProvider<ChartPeriodNotifier, ChartPeriod>(
      (ref) => ChartPeriodNotifier(ref.read(chartPeriodStorageProvider)),
    );
