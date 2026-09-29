import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'env.dart';

/// Identifiant de la base Firestore nommée utilisée par l'environnement de
/// staging déployé (ADR 0003 — isolation prod/staging). Voir `firebase.json`
/// (bloc `firestore`) où cette base est déclarée à côté de `(default)`.
///
/// Nom `staging` (et non `dev`) : Firestore impose un id de base de **4-63
/// caractères** — `dev` (3 car.) est rejeté à la création.
const String kStagingDatabaseId = 'staging';

/// Choix de la base (ADR 0003 + build Test Lab). L'émulateur est prioritaire ;
/// sinon `staging` pour le web de staging (`APP_ENV=dev`) ou pour le build de
/// test mobile (`MOBILE_STAGING`, ignoré en release) ; sinon `(default)`.
bool shouldUseStagingDatabase({
  required bool isWeb,
  required bool isDev,
  required bool useEmulator,
  required bool useMobileStaging,
}) {
  if (useEmulator) return false;
  return (isWeb && isDev) || useMobileStaging;
}

/// Instance Firestore à utiliser dans TOUT le code applicatif (ADR 0003).
///
/// **Ne JAMAIS appeler `FirebaseFirestore.instance` directement dans un repo /
/// provider** — passer par ce provider, sinon l'isolation prod/staging fuit
/// (un check CI l'interdit, cf. jalon 4 de l'ADR).
///
/// **Fail-safe vers `(default)` = prod**, exactement comme le backend
/// (`dbForRequest`). On ne route vers la base `staging` que sur un signal
/// POSITIF et non ambigu :
/// - **Staging web déployé** (`app.staging.baillan.com`, `APP_ENV=dev`,
///   non-émulateur) → base nommée [`staging`](kStagingDatabaseId), séparée de la prod. Le garde
///   `kIsWeb` est critique : la commande de release mobile documentée
///   (`docs/MOBILE.md`) ne passe pas `APP_ENV`, donc `APP_ENV` retombe sur son
///   défaut `'dev'` — sans ce garde, une release mobile enverrait les vrais
///   utilisateurs vers la base `staging`.
/// - **Build de test mobile** (`MOBILE_STAGING=true`, Firebase Test Lab) →
///   `staging` aussi. Le flag est ignoré en release (`Env.useMobileStaging`
///   vérifie `kReleaseMode`), donc un build publié sur les stores ne peut pas
///   y aboutir. Le mobile vise `staging` UNIQUEMENT dans ce build de test.
/// - **Prod**, **émulateur local** (prioritaire sur tout le reste) et tout autre
///   build mobile → `(default)`.
///
/// Rules et indexes sont identiques sur les deux bases (déployés ensemble via
/// `firebase deploy --only firestore`), donc la sécurité est la même partout.
final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  final useStaging = shouldUseStagingDatabase(
    isWeb: kIsWeb,
    isDev: Env.isDev,
    useEmulator: Env.useFirebaseEmulator,
    useMobileStaging: Env.useMobileStaging,
  );
  if (!useStaging) {
    return FirebaseFirestore.instance;
  }
  return FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: kStagingDatabaseId,
  );
});
