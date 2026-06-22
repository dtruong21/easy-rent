// Exporte le bon service selon la plateforme cible.
// - Web : implémentation réelle avec `dart:js_interop` et `package:web`.
// - VM (tests, desktop non-web) : stub no-op.
//
// Exporte également [webShareServiceProvider] pour que les tests puissent
// l'overrider sans importer directement stub ou web impl.
export 'web_share_service_stub.dart'
    if (dart.library.js_interop) 'web_share_service.dart'
    show webShareServiceProvider;

export 'web_share_service_interface.dart'
    show
        WebShareService,
        ShareAbortedException,
        ShareNotSupportedException,
        ShareReceiptException;
