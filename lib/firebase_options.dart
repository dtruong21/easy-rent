// Firebase configuration Baillan. (FEAT-019).
//
// Généré manuellement à partir de `firebase apps:sdkconfig WEB` car
// `flutterfire configure` est interactif. À régénérer si on ajoute des
// plateformes (iOS / Android) — typiquement via :
//   `dart pub global activate flutterfire_cli && flutterfire configure
//    --project easy-rent-54cd4`
//
// L'`apiKey` Firebase Web est PUBLIQUE (équivalent du anon key Supabase).
// La sécurité passe par les Firestore Rules + Storage Rules + App Check,
// pas par le secret de la clé. Safe à committer.
//
// Voir docs/SECURITY.md pour la distinction clés publiques vs secrets.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  const DefaultFirebaseOptions._();

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.android:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        throw UnsupportedError(
          'DefaultFirebaseOptions: plateforme non encore configurée — '
          'lancer `flutterfire configure --project easy-rent-54cd4`.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCe_O2IKxorDgg3SykE8mIdyVlpYSOYuC4',
    appId: '1:60344304540:web:f39549b928edf6d52d7e59',
    messagingSenderId: '60344304540',
    projectId: 'easy-rent-54cd4',
    authDomain: 'easy-rent-54cd4.firebaseapp.com',
    storageBucket: 'easy-rent-54cd4.firebasestorage.app',
    measurementId: 'G-BLM5KC5DVK',
  );
}
