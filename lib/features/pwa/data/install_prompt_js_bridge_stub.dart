/// Stub du JS bridge pour les plateformes non-web (tests unitaires VM).
///
/// Remplace [install_prompt_js_bridge.dart] sur les plateformes où
/// `dart:js_interop` n'est pas disponible.
class InstallPromptJsBridge {
  InstallPromptJsBridge._();

  static void captureDeferred() {}
  static bool get hasDeferred => false;
  static bool get isStandalone => false;
  static bool get isIos => false;
  static Future<bool> trigger() async => false;
}
