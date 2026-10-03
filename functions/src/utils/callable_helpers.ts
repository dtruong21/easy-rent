/**
 * Helpers de typage pour les Callables (input validation + Firestore doc reads).
 *
 * Les Callable Cloud Functions reçoivent `request.data` typé `unknown`/`any`
 * — donc toute déstructuration sans validation runtime déclenche les
 * @typescript-eslint/no-unsafe-* rules. Ce module fournit une trousse de
 * helpers typés qui retournent des `unknown` puis valident, gardant le
 * code des handlers propre et type-safe.
 */

import * as admin from "firebase-admin";
import type {DocumentSnapshot} from "firebase-admin/firestore";
import {Timestamp} from "firebase-admin/firestore";
import {logger} from "firebase-functions/v2";
import {HttpsError} from "firebase-functions/v2/https";
import type {CallableRequest} from "firebase-functions/v2/https";

/** Cast input → bag typé. À utiliser comme première ligne d'un handler. */
export function asBag(input: unknown): Record<string, unknown> {
  if (input == null || typeof input !== "object") return {};
  return input as Record<string, unknown>;
}

export function requireAuthUid<T = unknown>(request: CallableRequest<T>): string {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "sign-in required");
  }
  return request.auth.uid;
}

/** Providers dont l'email est vérifié par le fournisseur d'identité. */
const TRUSTED_EMAIL_PROVIDERS: ReadonlySet<string> = new Set([
  "google.com",
  "apple.com",
]);

/** Code d'erreur renvoyé aux comptes dont l'email n'est pas vérifié. */
export const EMAIL_NOT_VERIFIED = "email_not_verified";

/**
 * OWASP-02 — comme [requireAuthUid], mais exige en plus un compte « de
 * confiance », miroir serveur de `isFullyAuthed()` des Firestore rules. Sont
 * acceptés :
 *   - un compte dont l'email est vérifié (`email_verified` du token) ;
 *   - un compte Google / Apple (email vérifié par le fournisseur) ;
 *   - un compte ANONYME (essai sans compte) — ses limites sont portées par les
 *     paliers / quotas, pas par cette garde.
 * Sinon : `failed-precondition` / `email_not_verified`. Fail-closed : un token
 * sans claim `firebase` ou `email_verified` est traité comme non vérifié.
 *
 * Le claim `sign_in_provider == 'anonymous'` reste porté par les tokens émis
 * AVANT un linkWithCredential/Provider (upgrade d'essai) : il ne prouve pas que
 * le compte est toujours anonyme. Or `finalizeAnonymousUpgrade` ne vérifie pas
 * l'email — sans confirmation, un compte lié à une adresse (éventuellement celle
 * d'un tiers) et jamais vérifié garderait un accès complet en conservant son
 * token. On confirme donc l'état AUTORITATIF côté Admin SDK : vrai anonyme ⇔
 * aucun provider lié ; sinon l'email doit être vérifié ou le provider de
 * confiance. Le coût (un `getUser`) ne concerne que ces tokens « anonymous ».
 *
 * À appeler en PREMIÈRE ligne des callables métier. Exemptées volontairement :
 * `deleteAccount`, `exportAccountData` (droits RGPD, accessibles à un compte non
 * vérifié) et `finalizeAnonymousUpgrade` (appelée AVANT l'email de vérification
 * lors du passage anonyme → compte complet) — elles gardent `requireAuthUid`.
 */
export async function requireVerifiedUid<T = unknown>(
  request: CallableRequest<T>,
): Promise<string> {
  const uid = requireAuthUid(request);
  const token = request.auth?.token;
  const provider = token?.firebase?.sign_in_provider;

  if (provider === "anonymous") {
    await assertAnonymousClaimIsTrusted(uid);
    return uid;
  }
  if (
    token?.email_verified === true ||
    (typeof provider === "string" && TRUSTED_EMAIL_PROVIDERS.has(provider))
  ) {
    return uid;
  }
  throw new HttpsError("failed-precondition", EMAIL_NOT_VERIFIED);
}

/**
 * Confirme, via Admin SDK, qu'un token au claim « anonymous » appartient bien à
 * un compte anonyme pur, ou à un compte upgradé dont l'email est de confiance.
 */
async function assertAnonymousClaimIsTrusted(uid: string): Promise<void> {
  let record: {
    providerData: ReadonlyArray<{providerId: string}>;
    emailVerified: boolean;
  };
  try {
    record = await admin.auth().getUser(uid);
  } catch (err) {
    const code =
      typeof err === "object" && err !== null && "code" in err ?
        (err as {code: unknown}).code :
        undefined;
    if (code === "auth/user-not-found") {
      // Compte supprimé (ex. purge d'un essai expiré) : token orphelin.
      throw new HttpsError("unauthenticated", "account no longer exists");
    }
    // Fail-closed, sans donnée personnelle dans le log (ni uid, ni email).
    logger.error(
      `requireVerifiedUid: account lookup failed (${
        typeof code === "string" ? code : "unknown"
      })`,
    );
    throw new HttpsError("internal", "account lookup failed — retry");
  }

  if (record.providerData.length === 0) return; // anonyme pur
  if (record.emailVerified) return;
  if (record.providerData.some((p) => TRUSTED_EMAIL_PROVIDERS.has(p.providerId))) {
    return;
  }
  throw new HttpsError("failed-precondition", EMAIL_NOT_VERIFIED);
}

/** Fraîcheur maximale de l'authentification pour un compte non-anonyme. */
export const RECENT_AUTH_MAX_AGE_SECONDS = 5 * 60;

/**
 * Rejette si un compte NON-anonyme présente un token d'auth trop vieux
 * (> RECENT_AUTH_MAX_AGE_SECONDS). Un compte anonyme (confirmé AUTORITATIVEMENT
 * via Admin SDK `providerData`, car le claim `sign_in_provider` reste
 * "anonymous" sur les tokens émis avant un upgrade par linking) est exempté.
 */
export async function assertRecentAuthForNonAnonymousAccount(
  request: CallableRequest,
  uid: string,
): Promise<void> {
  const token = request.auth?.token;
  let isAnonymous = token?.firebase?.sign_in_provider === "anonymous";
  if (isAnonymous) {
    try {
      const userRecord = await admin.auth().getUser(uid);
      isAnonymous = userRecord.providerData.length === 0;
    } catch (err) {
      const code =
        typeof err === "object" && err !== null && "code" in err ?
          (err as {code: unknown}).code :
          undefined;
      if (code !== "auth/user-not-found") {
        logger.error(`assertRecentAuth: getUser failed for uid=${uid}`, err);
        throw new HttpsError("internal", "account lookup failed — retry");
      }
    }
  }
  if (!isAnonymous) {
    const authTime =
      typeof token?.auth_time === "number" ? token.auth_time : 0;
    const ageSeconds = Date.now() / 1000 - authTime;
    if (ageSeconds > RECENT_AUTH_MAX_AGE_SECONDS) {
      throw new HttpsError("failed-precondition", "recent-login-required");
    }
  }
}

export function requireString(value: unknown, name: string): string {
  if (typeof value !== "string" || value.length === 0) {
    throw new HttpsError(
      "invalid-argument",
      `${name} must be a non-empty string`,
    );
  }
  return value;
}

export function optionalString(value: unknown, name: string): string | null {
  if (value == null) return null;
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${name} must be a string`);
  }
  return value;
}

export function requireInt(
  value: unknown,
  name: string,
  opts?: {min?: number; max?: number},
): number {
  if (typeof value !== "number" || !Number.isInteger(value)) {
    throw new HttpsError("invalid-argument", `${name} must be an integer`);
  }
  if (opts?.min !== undefined && value < opts.min) {
    throw new HttpsError("invalid-argument", `${name} must be >= ${opts.min}`);
  }
  if (opts?.max !== undefined && value > opts.max) {
    throw new HttpsError("invalid-argument", `${name} must be <= ${opts.max}`);
  }
  return value;
}

export function optionalInt(
  value: unknown,
  name: string,
  opts?: {min?: number; max?: number},
): number | null {
  if (value == null) return null;
  return requireInt(value, name, opts);
}

export function optionalNumber(value: unknown, name: string): number | null {
  if (value == null) return null;
  if (typeof value !== "number") {
    throw new HttpsError("invalid-argument", `${name} must be a number`);
  }
  return value;
}

export function requireBool(value: unknown, _name: string): boolean {
  return value === true;
}

export function toTimestamp(value: unknown, name: string): Timestamp {
  if (value instanceof Timestamp) return value;
  if (typeof value === "string") {
    const d = new Date(value);
    if (Number.isNaN(d.getTime())) {
      throw new HttpsError("invalid-argument", `${name} not a valid date`);
    }
    return Timestamp.fromDate(d);
  }
  if (typeof value === "number") {
    return Timestamp.fromMillis(value);
  }
  throw new HttpsError("invalid-argument", `${name} must be a date`);
}

export function optionalTimestamp(
  value: unknown,
  name: string,
): Timestamp | null {
  if (value == null) return null;
  return toTimestamp(value, name);
}

/**
 * Lit les données d'un snapshot en garantissant un type Record (vs DocumentData
 * qui est `any`). Throw si le doc n'existe pas.
 */
export function dataOrFail(
  snap: DocumentSnapshot,
  notFoundMessage: string,
): Record<string, unknown> {
  if (!snap.exists) {
    throw new HttpsError("not-found", notFoundMessage);
  }
  const d = snap.data();
  if (!d) throw new HttpsError("internal", "empty doc data");
  return d as Record<string, unknown>;
}

/**
 * Vérifie l'ownership et le non-deleted d'une ressource (équivalent commun
 * aux RLS Postgres "USING landlord_id = auth.uid() AND deleted_at IS NULL").
 */
export function assertOwnedAndActive(
  data: Record<string, unknown>,
  uid: string,
  what: string,
): void {
  if (data.landlordId !== uid) {
    throw new HttpsError("permission-denied", `not owner of ${what}`);
  }
  if (data.deletedAt != null) {
    throw new HttpsError("failed-precondition", `${what} is deleted`);
  }
}
