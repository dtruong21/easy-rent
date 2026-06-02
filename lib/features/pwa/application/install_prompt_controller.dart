import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:logging/logging.dart';

import '../data/install_prompt_js_bridge_interface.dart';
import '../data/install_prompt_storage.dart';

part 'install_prompt_controller.freezed.dart';

final _log = Logger('InstallPromptController');

/// État du prompt d'installation PWA.
@freezed
sealed class InstallPromptState with _$InstallPromptState {
  /// Banner masqué (standalone, dismissed récemment, ou navigateur non supporté).
  const factory InstallPromptState.hidden() = _Hidden;

  /// Banner visible avec prompt natif disponible (Chrome/Edge).
  const factory InstallPromptState.visibleNative() = _VisibleNative;

  /// Banner visible avec instructions manuelles (iOS Safari).
  const factory InstallPromptState.visibleIos() = _VisibleIos;

  /// Prompt en cours de déclenchement.
  const factory InstallPromptState.triggering() = _Triggering;

  /// App installée avec succès.
  const factory InstallPromptState.installed() = _Installed;
}

// ---------------------------------------------------------------------------
// Controller (StateNotifier)
// ---------------------------------------------------------------------------

/// Contrôleur du prompt d'installation PWA.
///
/// Logique de visibilité :
/// - Si standalone → hidden.
/// - Si dismissed il y a <30 jours → hidden.
/// - Si Chrome/Edge avec deferred → visibleNative.
/// - Si iOS Safari → visibleIos.
/// - Sinon → hidden (Firefox desktop, etc.).
///
/// Au 1er login, on force l'affichage si `first_login_seen` n'est pas stocké.
class InstallPromptController extends StateNotifier<InstallPromptState> {
  InstallPromptController(this._storage)
    : super(const InstallPromptState.hidden());

  final InstallPromptStorage _storage;

  /// Évalue l'état initial au démarrage / 1er login.
  ///
  /// [isFirstLogin] : `true` si l'utilisateur vient de se connecter pour la
  /// première fois dans cette session.
  Future<void> evaluate({bool isFirstLogin = false}) async {
    // Déjà installée en mode standalone → toujours caché.
    if (InstallPromptJsBridge.isStandalone) {
      _log.fine('evaluate: standalone → hidden');
      state = const InstallPromptState.hidden();
      return;
    }

    // Au 1er login, forcer l'affichage si pas encore vu.
    if (isFirstLogin) {
      final seen = await _storage.isFirstLoginSeen();
      if (!seen) {
        await _storage.markFirstLoginSeen();
        _log.fine('evaluate: 1er login non vu → force visible');
        state = _computeVisibleState();
        return;
      }
    }

    // Sinon, suivre la logique standard : dismissed récemment ?
    final dismissed = await _storage.isDismissedRecently();
    if (dismissed) {
      _log.fine('evaluate: dismissed récemment → hidden');
      state = const InstallPromptState.hidden();
      return;
    }

    state = _computeVisibleState();
    _log.fine('evaluate: state = $state');
  }

  /// Déclenche le prompt natif du navigateur.
  Future<void> trigger() async {
    state = const InstallPromptState.triggering();
    final accepted = await InstallPromptJsBridge.trigger();
    if (accepted) {
      _log.info('PWA installée par l\'utilisateur');
      state = const InstallPromptState.installed();
    } else {
      _log.fine('Prompt décliné — dismiss');
      await dismiss();
    }
  }

  /// Dismiss le banner et persiste le timestamp.
  Future<void> dismiss() async {
    await _storage.saveDismissedAt(DateTime.now());
    state = const InstallPromptState.hidden();
    _log.fine('Install prompt dismissed');
  }

  // --------------------------------------------------------------------------
  InstallPromptState _computeVisibleState() {
    if (InstallPromptJsBridge.hasDeferred) {
      return const InstallPromptState.visibleNative();
    }
    if (InstallPromptJsBridge.isIos) {
      return const InstallPromptState.visibleIos();
    }
    return const InstallPromptState.hidden();
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

/// Provider du storage des préférences PWA.
final installPromptStorageProvider = Provider<InstallPromptStorage>(
  (_) => InstallPromptStorage(),
);

/// Provider du contrôleur du prompt d'installation.
final installPromptControllerProvider =
    StateNotifierProvider<InstallPromptController, InstallPromptState>(
      (ref) => InstallPromptController(ref.read(installPromptStorageProvider)),
    );
