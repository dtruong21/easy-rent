import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Bridge JS interop pour capturer l'événement `beforeinstallprompt`.
///
/// Utilise `package:web` (API officielle, remplace `dart:html` legacy).
/// Doit être initialisé le plus tôt possible au démarrage de l'app
/// (avant runApp) pour ne pas rater l'event.
///
/// **iOS Safari** : ne supporte pas `beforeinstallprompt`. Détection via
/// user-agent → affiche des instructions textuelles à la place.
class InstallPromptJsBridge {
  InstallPromptJsBridge._();

  static _BeforeInstallPromptEvent? _deferred;
  static bool _listenerRegistered = false;

  /// Capture l'événement `beforeinstallprompt` pour un usage ultérieur.
  ///
  /// Idempotent — peut être appelé plusieurs fois sans effet de bord.
  static void captureDeferred() {
    if (_listenerRegistered) return;
    _listenerRegistered = true;
    web.window.addEventListener(
      'beforeinstallprompt',
      (web.Event e) {
        e.preventDefault();
        _deferred = e as _BeforeInstallPromptEvent;
      }.toJS,
    );
  }

  /// `true` si un deferred prompt natif est disponible (Chrome/Edge).
  static bool get hasDeferred => _deferred != null;

  /// `true` si l'app est déjà lancée en mode standalone (installée).
  static bool get isStandalone =>
      web.window.matchMedia('(display-mode: standalone)').matches;

  /// `true` si le user-agent indique un appareil iOS.
  static bool get isIos {
    final ua = web.window.navigator.userAgent.toLowerCase();
    return ua.contains('iphone') || ua.contains('ipad');
  }

  /// Déclenche le prompt natif du navigateur.
  ///
  /// Retourne `true` si l'utilisateur a accepté, `false` sinon.
  /// Retourne `false` si aucun deferred prompt n'est disponible.
  static Future<bool> trigger() async {
    final deferred = _deferred;
    if (deferred == null) return false;
    _deferred = null; // Ne peut être utilisé qu'une seule fois.
    deferred.prompt();
    final choice = await deferred.userChoice.toDart;
    // L'objet userChoice est `{ outcome: 'accepted' | 'dismissed' }`.
    // dartify() convertit le JSObject en Map Dart.
    final dartValue = choice.dartify();
    if (dartValue is Map) {
      return dartValue['outcome'] == 'accepted';
    }
    return false;
  }
}

// ---------------------------------------------------------------------------
// Types JS interop
// ---------------------------------------------------------------------------

/// Extension type pour l'événement `beforeinstallprompt` non standard.
extension type _BeforeInstallPromptEvent._(JSObject _) implements web.Event {
  /// Affiche le prompt natif du navigateur.
  external void prompt();

  /// Choix de l'utilisateur : objet `{ outcome: 'accepted' | 'dismissed' }`.
  external JSPromise get userChoice;
}
