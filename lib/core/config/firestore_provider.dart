import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
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
/// Routage :
/// - **Émulateur local** (`Env.useFirebaseEmulator`) → base `(default)` sur
///   l'émulateur. Le workflow local (seed `tool/seed/seed_tiers.mjs`, ports)
///   reste inchangé — l'isolation ne concerne que les environnements déployés.
/// - **Prod** (`baillan.com`, `Env.isProd`) → base `(default)`.
/// - **Staging déployé** (`stage.baillan.com`) → base nommée [`dev`](kDevDatabaseId),
///   physiquement séparée de la prod : plus aucune donnée de test ne pollue
///   `(default)`.
///
/// Rules et indexes sont identiques sur les deux bases (déployés ensemble via
/// `firebase deploy --only firestore`), donc la sécurité est la même partout.
final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  if (Env.useFirebaseEmulator || Env.isProd) {
    return FirebaseFirestore.instance;
  }
  return FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: kDevDatabaseId,
  );
});
