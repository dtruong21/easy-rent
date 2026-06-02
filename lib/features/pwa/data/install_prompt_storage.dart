import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _log = Logger('InstallPromptStorage');

/// Persiste l'état du prompt d'installation PWA dans [SharedPreferences].
///
/// Clés utilisées :
/// - `pwa_install_prompt_dismissed_at` : timestamp (ms) du dernier dismiss.
/// - `pwa_install_prompt_first_login_seen` : bool — déjà affiché au 1er login.
class InstallPromptStorage {
  static const _keyDismissedAt = 'pwa_install_prompt_dismissed_at';
  static const _keyFirstLoginSeen = 'pwa_install_prompt_first_login_seen';

  /// Délai avant réaffichage après un dismiss (30 jours).
  static const _reEligibilityDuration = Duration(days: 30);

  /// Enregistre la date du dismiss.
  Future<void> saveDismissedAt(DateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyDismissedAt, now.millisecondsSinceEpoch);
    _log.fine('Install prompt dismissed at: $now');
  }

  /// `true` si le prompt a été dismissé il y a moins de 30 jours.
  Future<bool> isDismissedRecently() async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getInt(_keyDismissedAt);
    if (ts == null) return false;
    final dismissedAt = DateTime.fromMillisecondsSinceEpoch(ts);
    final isRecent =
        DateTime.now().difference(dismissedAt) < _reEligibilityDuration;
    _log.fine('isDismissedRecently=$isRecent');
    return isRecent;
  }

  /// `true` si le banner a déjà été affiché lors du 1er login.
  Future<bool> isFirstLoginSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyFirstLoginSeen) ?? false;
  }

  /// Marque le 1er login comme "vu".
  Future<void> markFirstLoginSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyFirstLoginSeen, true);
    _log.fine('Install prompt first-login-seen marqué');
  }

  /// Réinitialise l'état (utilisé en tests).
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyDismissedAt);
    await prefs.remove(_keyFirstLoginSeen);
  }
}
