import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'crash_reporting_service.dart';
import 'crash_reporting_storage.dart';

/// Provider du storage [CrashReportingStorage].
final crashReportingStorageProvider = Provider<CrashReportingStorage>(
  (ref) => CrashReportingStorage(),
);

/// Consentement au rapport d'incident (Crashlytics), **opt-in / défaut
/// `false`**. La collecte réelle est pilotée ici : chaque changement persiste
/// le choix ET appelle [CrashReportingService.setEnabled] (no-op sur le web).
///
/// Le boot applique séparément la valeur persistée dans `main()`, afin que le
/// consentement soit respecté même si la page de réglage n'est jamais ouverte.
class CrashReportingNotifier extends StateNotifier<bool> {
  CrashReportingNotifier(this._storage) : super(false) {
    _load();
  }

  final CrashReportingStorage _storage;

  Future<void> _load() async {
    final stored = await _storage.read();
    if (stored != null && mounted) {
      state = stored;
    }
  }

  /// Enregistre le consentement : met à jour l'état, persiste, et applique la
  /// collecte à Crashlytics.
  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    await _storage.write(enabled);
    await CrashReportingService.setEnabled(enabled);
  }
}

/// Consentement au rapport d'incident (Profil → Confidentialité, mobile only).
///
/// Usage :
/// ```dart
/// final enabled = ref.watch(crashReportingProvider);
/// ref.read(crashReportingProvider.notifier).setEnabled(true);
/// ```
final crashReportingProvider =
    StateNotifierProvider<CrashReportingNotifier, bool>(
      (ref) => CrashReportingNotifier(ref.read(crashReportingStorageProvider)),
    );
