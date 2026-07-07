// Exporte le bon service selon la plateforme cible.
// - Web : implémentation Web Share API (`dart:js_interop` + `package:web`).
// - VM : partage natif share_plus sur Android/iOS (FEAT-024),
//   no-op sûr ailleurs (tests, desktop).
//
// Exporte également [webShareServiceProvider] pour que les tests puissent
// l'overrider sans importer directement l'une des implémentations.
export 'web_share_service_io.dart'
    if (dart.library.js_interop) 'web_share_service.dart'
    show webShareServiceProvider;

export 'web_share_service_interface.dart'
    show
        WebShareService,
        ShareAbortedException,
        ShareNotSupportedException,
        ShareReceiptException;
