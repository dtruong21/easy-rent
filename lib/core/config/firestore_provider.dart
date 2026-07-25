import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'env.dart';

/// Identifiant de la base Firestore nommée utilisée par l'environnement de
/// staging déployé (ADR 0003 — isolation prod/staging). Voir `firebase.json`
/// (bloc `firestore`) où cette base est déclarée à côté de `(default)`.
const String kDevDatabaseId = 'dev';

/// Instance Firestore à utiliser dans TOUT le code applicatif (ADR 0003).
///
/// **Ne JAMAIS appeler `FirebaseFirestore.instance` directement dans un repo /
/// provider** — passer par ce provider, sinon l'isolation prod/staging fuit
/// (un check CI l'interdit, cf. jalon 4 de l'ADR).
///
/// **Fail-safe vers `(default)` = prod**, exactement comme le backend
/// (`dbForRequest`). On ne route vers la base `dev` que sur un signal POSITIF et
/// non ambigu — un build **WEB de staging** (`APP_ENV=dev`, posé explicitement
/// par `deploy.yml`) :
/// - **Prod**, **émulateur local**, et surtout **TOUT build mobile** →
///   `(default)`. Le garde `kIsWeb` est critique : la commande de release mobile
///   documentée (`docs/MOBILE.md`) ne passe pas `APP_ENV`, donc `APP_ENV`
///   retombe sur son défaut `'dev'` — sans ce garde, une release mobile
///   enverrait les vrais utilisateurs vers la base `dev` de staging.
/// - **Staging web déployé** (`stage.baillan.com`, `APP_ENV=dev`, non-émulateur)
///   → base nommée [`dev`](kDevDatabaseId), séparée de la prod.
///
/// Conséquence assumée : il n'existe pas d'isolation `dev` pour le **mobile**
/// (mobile → toujours `(default)`). L'ADR 0003 cible le staging web ; l'émulateur
/// reste le bac à sable mobile.
///
/// Rules et indexes sont identiques sur les deux bases (déployés ensemble via
/// `firebase deploy --only firestore`), donc la sécurité est la même partout.
final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  final useDevDatabase = kIsWeb && Env.isDev && !Env.useFirebaseEmulator;
  if (!useDevDatabase) {
    return FirebaseFirestore.instance;
  }
  return FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: kDevDatabaseId,
  );
});
