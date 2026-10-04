/**
 * Routage de la base Firestore par environnement (ADR 0003 — isolation
 * prod/staging). Prod (app : `app.baillan.com`) → base `(default)` ; staging
 * déployé (app : `app.staging.baillan.com`) → base nommée `staging`, séparée.
 *
 * Deux entrées selon la nature de l'appel :
 * - **Callables** ([dbForRequest]) : web (Origin présent) → routage par
 *   l'en-tête **Origin** ; mobile (Origin absent ou vide) → routage par la base
 *   qui porte le doc landlord ([dbForLandlordUid], prod d'abord).
 * - **Webhook RevenueCat** (server-to-server, sans Origin) → routage par
 *   l'`environment` de l'event (`SANDBOX` → `staging`, `PRODUCTION` →
 *   `(default)`), via [firestoreForEnv] — jamais par la base qui porte le doc :
 *   ce routage-là laissait un achat de test accorder un palier sur un compte
 *   prod (OWASP-01, cf. `handleRevenueCatEvent`).
 *
 * ⚠️ Ne JAMAIS appeler `admin.firestore()` / `getFirestore()` sans passer par
 * ce module dans le code qui écrit des données par requête utilisateur — sinon
 * l'isolation fuit (un check CI l'interdit, jalon 4 de l'ADR). Les crons
 * (`onSchedule`) et triggers Firestore restent sur `(default)` volontairement.
 */

import * as admin from "firebase-admin";
import {getFirestore} from "firebase-admin/firestore";
import type {Firestore} from "firebase-admin/firestore";
import type {CallableRequest} from "firebase-functions/v2/https";

/**
 * Identifiant de la base Firestore nommée du staging. DOIT correspondre à
 * `firebase.json` (bloc `firestore`) et au `kStagingDatabaseId` Flutter
 * (`lib/core/config/firestore_provider.dart`). Nom `staging` (et non `dev`) :
 * Firestore impose un id de base de 4-63 caractères.
 */
export const STAGING_DATABASE_ID = "staging";

/** Origin du site staging — la SEULE origine routée vers la base `staging`. */
export const STAGING_ORIGIN = "https://app.staging.baillan.com";

/**
 * Base Firestore de l'environnement : `staging` si [isStaging], sinon la prod
 * `(default)`.
 *
 * Le chemin `(default)` passe par `admin.firestore()` — et non `getFirestore()`
 * — car c'est le seam que tout le code et les tests (`vi.mock("firebase-admin")`)
 * utilisent déjà pour la base par défaut : back-compat totale, comportement prod
 * strictement identique. La base nommée `staging` n'a pas d'équivalent
 * namespacé, d'où `getFirestore(id)`.
 */
export function firestoreForEnv(isStaging: boolean): Firestore {
  return isStaging ? getFirestore(STAGING_DATABASE_ID) : admin.firestore();
}

/**
 * `true` uniquement si l'origine correspond EXACTEMENT au staging. Tout le
 * reste (prod, Origin absent, Origin inattendu) → `false` → base `(default)`.
 * Fail-safe volontaire vers la prod : jamais mal-router un vrai appel prod.
 */
export function isStagingOrigin(origin: unknown): boolean {
  return origin === STAGING_ORIGIN;
}

/**
 * Base Firestore pour une requête callable.
 *
 * - **Web** (Origin présent) : routage par l'Origin, inchangé — seul le
 *   staging web va vers `staging`, tout le reste vers `(default)`.
 * - **Mobile** (Origin absent ou vide — une app native n'en envoie pas) :
 *   routage par la base qui porte le doc landlord ([dbForLandlordUid]), prod
 *   d'abord. Un vrai utilisateur mobile a son compte en prod → prod ; le
 *   compte de test du build Test Lab n'existe qu'en staging → staging.
 *
 * Un client non-navigateur pourrait forger l'Origin, mais il ne routerait que
 * SES propres écritures : les callables restent bornées à `request.auth.uid`
 * par leurs propres contrôles (`requireAuthUid`, `landlordId === uid`) — pas
 * d'impact cross-user.
 */
export async function dbForRequest(
  request: CallableRequest,
): Promise<Firestore> {
  const origin = request.rawRequest?.headers?.origin;
  if (typeof origin === "string" && origin.length > 0) {
    return firestoreForEnv(isStagingOrigin(origin));
  }
  return dbForLandlordUid(request.auth?.uid ?? "");
}

/**
 * Base Firestore contenant le doc `landlords/{uid}`, pour les callables mobiles
 * ([dbForRequest]) — un client natif n'envoie pas d'Origin. Cherche d'abord la
 * prod `(default)` — fail-safe : un vrai compte prod ne doit jamais être écrit
 * dans `staging` —, puis `staging`. Absent des deux → `(default)`.
 *
 * ⚠️ N'est PLUS utilisé par le webhook RevenueCat (routé par `event.environment`,
 * OWASP-01) : « la base qui porte le doc » n'est pas une garde d'environnement —
 * un même uid peut exister dans les deux bases (Auth partagée).
 */
export async function dbForLandlordUid(uid: string): Promise<Firestore> {
  const prod = firestoreForEnv(false);
  if (!uid) return prod;
  const prodSnap = await prod.doc(`landlords/${uid}`).get();
  if (prodSnap.exists) return prod;
  const staging = firestoreForEnv(true);
  const stagingSnap = await staging.doc(`landlords/${uid}`).get();
  return stagingSnap.exists ? staging : prod;
}
