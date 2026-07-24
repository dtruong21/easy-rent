/**
 * Routage de la base Firestore par environnement (ADR 0003 — isolation
 * prod/staging). Prod (`baillan.com`) → base `(default)` ; staging déployé
 * (`stage.baillan.com`) → base nommée `dev`, physiquement séparée.
 *
 * Deux entrées selon la nature de l'appel :
 * - **Callables** (navigateur) → routage par l'en-tête **Origin** ([dbForRequest]).
 * - **Webhook RevenueCat** (server-to-server, sans Origin) → routage par la base
 *   qui contient réellement le doc landlord ([dbForLandlordUid]). C'est plus
 *   robuste que la metadata `env` prescrite par l'ADR : ça ne dépend d'aucune
 *   config RevenueCat/Stripe et reste correct même si la propagation de metadata
 *   change (voir l'amendement dans l'ADR 0003).
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
 * `firebase.json` (bloc `firestore`) et au `kDevDatabaseId` Flutter
 * (`lib/core/config/firestore_provider.dart`).
 */
export const DEV_DATABASE_ID = "dev";

/** Origin du site staging — la SEULE origine routée vers la base `dev`. */
export const STAGING_ORIGIN = "https://stage.baillan.com";

/**
 * Base Firestore pour un drapeau env.
 *
 * Le chemin `(default)` passe par `admin.firestore()` — et non `getFirestore()`
 * — car c'est le seam que tout le code et les tests (`vi.mock("firebase-admin")`)
 * utilisent déjà pour la base par défaut : back-compat totale, comportement prod
 * strictement identique. La base nommée `dev` n'a pas d'équivalent namespacé,
 * d'où `getFirestore(id)`.
 */
export function firestoreForEnv(isDev: boolean): Firestore {
  return isDev ? getFirestore(DEV_DATABASE_ID) : admin.firestore();
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
 * Base Firestore pour une requête callable, routée par l'Origin du navigateur.
 * Un client non-navigateur pourrait forger l'Origin, mais il ne routerait que
 * SES propres écritures vers `dev` (les rules d'ownership s'appliquent sur les
 * deux bases) — pas d'impact cross-user.
 */
export function dbForRequest(request: CallableRequest): Firestore {
  const origin = request.rawRequest?.headers?.origin;
  return firestoreForEnv(isStagingOrigin(origin));
}

/**
 * Base Firestore contenant le doc `landlords/{uid}`, pour les flux
 * server-to-server SANS Origin (webhook RevenueCat). Cherche d'abord la prod
 * `(default)` — fail-safe : un vrai compte prod ne doit jamais être écrit dans
 * `dev` —, puis `dev`. Un uid ne vit que dans UNE base (l'utilisateur s'est
 * inscrit sur prod OU staging), donc la 1re base qui porte le doc est la bonne.
 * Absent des deux → `(default)` (le webhook renverra `no_landlord`).
 *
 * ⚠️ Discipline : pour tester un paiement sur staging, utiliser un compte
 * JAMAIS utilisé en prod — sinon son doc existe aussi en `(default)` et le
 * webhook, qui teste prod d'abord, basculerait le compte prod.
 */
export async function dbForLandlordUid(uid: string): Promise<Firestore> {
  const prod = firestoreForEnv(false);
  if (!uid) return prod;
  const prodSnap = await prod.doc(`landlords/${uid}`).get();
  if (prodSnap.exists) return prod;
  const dev = firestoreForEnv(true);
  const devSnap = await dev.doc(`landlords/${uid}`).get();
  return devSnap.exists ? dev : prod;
}
