// Exporte le bon JS bridge selon la plateforme cible.
// - Web : implémentation réelle avec `dart:js_interop`.
// - VM (tests, desktop) : stub no-op.
export 'install_prompt_js_bridge_stub.dart'
    if (dart.library.js_interop) 'install_prompt_js_bridge.dart';
