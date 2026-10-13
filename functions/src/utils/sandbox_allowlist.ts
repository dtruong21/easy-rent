/**
 * Liste blanche SANDBOX (FEAT-044e, #209) — uids PROD autorisés à recevoir un
 * droit payant via un achat de TEST.
 *
 * App Review (Apple) et les testeurs Google achètent en SANDBOX sur l'app de
 * PRODUCTION. Sans exception, le webhook route ces achats vers `staging`
 * (OWASP-01) : le compte de démo de la review n'obtient jamais Pro et l'app
 * est refusée. Ce document prod liste les rares comptes pour lesquels un achat
 * sandbox **d'un store mobile** (App Store, Google Play) vaut un vrai droit.
 * Un achat Stripe test (web staging) n'est jamais concerné : mobile = stores
 * via RevenueCat, web = Stripe via RevenueCat. Il est édité à la main (console
 * Firebase) et lu uniquement par les Functions — aucun accès client (règle
 * `_ops`).
 *
 * Fail-closed : une liste illisible vaut « aucun uid » — jamais de déblocage
 * prod par défaut.
 */

import type {Firestore} from "firebase-admin/firestore";
import {logger} from "firebase-functions/v2";

/** Chemin du document, dans la base prod `(default)`. */
export const SANDBOX_ALLOWLIST_DOC = "_ops/sandboxAllowlist";

/** PURE — uids valides du document (`uids: string[]`), sans doublon. */
export function parseSandboxAllowlist(data: unknown): ReadonlySet<string> {
  const raw =
    typeof data === "object" && data !== null ?
      (data as {uids?: unknown}).uids :
      undefined;
  if (!Array.isArray(raw)) return new Set();
  const uids = raw
    .filter((u): u is string => typeof u === "string")
    .map((u) => u.trim())
    .filter((u) => u.length > 0);
  return new Set(uids);
}

/** Lit la liste dans [db] (base prod). Lève si la lecture échoue. */
export async function readSandboxAllowlist(
  db: Firestore,
): Promise<ReadonlySet<string>> {
  const snap = await db.doc(SANDBOX_ALLOWLIST_DOC).get();
  return parseSandboxAllowlist(snap.data());
}

/** Stores RevenueCat des achats intégrés mobiles (en minuscules). */
const MOBILE_STORES: ReadonlySet<string> = new Set([
  "app_store",
  "mac_app_store",
  "play_store",
]);

/**
 * PURE — `true` si [store] est un store mobile (App Store, Google Play) : seuls
 * achats sandbox couverts par la liste. Accepte les deux casses de RevenueCat
 * (`APP_STORE` dans les events du webhook, `app_store` dans l'API v1). Stripe,
 * RC Billing, promo, absent ou inconnu → `false` (fail-closed).
 */
export function isMobileStore(store: unknown): boolean {
  return typeof store === "string" && MOBILE_STORES.has(store.toLowerCase());
}

/**
 * Comme [readSandboxAllowlist], sans jamais lever : en cas d'échec, journalise
 * et rend un ensemble vide (comportement par défaut, fail-closed).
 *
 * @param context Préfixe du log (nom de la fonction appelante).
 */
export async function readSandboxAllowlistOrEmpty(
  db: Firestore,
  context: string,
): Promise<ReadonlySet<string>> {
  try {
    return await readSandboxAllowlist(db);
  } catch (err) {
    logger.error(
      `${context}: liste blanche sandbox illisible → aucun uid appliqué`,
      err,
    );
    return new Set();
  }
}
