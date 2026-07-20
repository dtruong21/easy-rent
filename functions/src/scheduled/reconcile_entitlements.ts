/**
 * reconcileEntitlements — filet de sécurité des events webhook manqués
 * (FEAT-044, ADR 0002).
 *
 * Un webhook RevenueCat peut être perdu (panne, 5xx non retenté à temps). Sans
 * réconciliation, un compte resterait `paid` après une expiration (ou `free`
 * après un renouvellement) manquée. Ce cron quotidien re-vérifie auprès de
 * l'API REST RevenueCat les comptes **actifs dont l'échéance est dépassée** et
 * corrige le tier :
 *   - RevenueCat confirme l'expiration → `free` ;
 *   - RevenueCat montre un renouvellement (échéance future) → on met à jour
 *     `proExpiresAt` et on conserve `paid` (le webhook de RENEWAL a été manqué).
 *
 * On requête `proEntitlementActive == true` (ensemble borné = utilisateurs
 * payants) puis on filtre l'échéance dépassée EN MÉMOIRE — pas de requête de
 * plage, donc **aucun index composite requis**. Le coeur
 * (`reconcileExpiredEntitlements`) prend un *fetcher* injectable → testable sans
 * appel réseau. La clé secrète v2 (`REVENUECAT_API_KEY`) n'est lue qu'en prod.
 */

import * as admin from "firebase-admin";
import {defineSecret} from "firebase-functions/params";
import {logger} from "firebase-functions/v2";
import {onSchedule} from "firebase-functions/v2/scheduler";

import {PRO_ENTITLEMENT_ID} from "../http/revenuecat_webhook";

/** Clé secrète v2 de l'API REST RevenueCat (serveur uniquement). */
const revenueCatApiKey = defineSecret("REVENUECAT_API_KEY");

const BATCH_SIZE = 200;

/**
 * Récupère l'échéance (ms epoch) de l'entitlement `pro` d'un abonné, ou `null`
 * si aucun entitlement `pro` actif. `uid` = App User ID RevenueCat = UID Firebase.
 */
export type ProExpiryFetcher = (uid: string) => Promise<number | null>;

/** Issue de la réconciliation d'un compte (pour log/tests). */
export type ReconcileOutcome = "downgraded" | "renewed" | "unchanged";

/** Millisecondes epoch d'un champ Firestore Timestamp OU Date OU null. */
function tsToMillis(value: unknown): number | null {
  if (value == null) return null;
  if (value instanceof Date) return value.getTime();
  const maybe = value as {toMillis?: () => number; toDate?: () => Date};
  if (typeof maybe.toMillis === "function") return maybe.toMillis();
  if (typeof maybe.toDate === "function") return maybe.toDate().getTime();
  return null;
}

/**
 * Corrige un compte d'après l'échéance rapportée par RevenueCat. Pur/testable.
 * `rcExpiryMs === null` ⇒ plus d'entitlement `pro` actif → `free`.
 */
export async function reconcileLandlord(
  db: admin.firestore.Firestore,
  uid: string,
  rcExpiryMs: number | null,
  nowMs: number,
): Promise<ReconcileOutcome> {
  const ref = db.doc(`landlords/${uid}`);
  const snap = await ref.get();
  const data = snap.data() ?? {};
  const wasActive = data.proEntitlementActive === true;

  // Le `!== null` narrow rcExpiryMs en `number` dans les branches (pas d'assertion).
  if (rcExpiryMs !== null && rcExpiryMs > nowMs) {
    if (!wasActive) return "unchanged"; // upgrade = ressort du webhook, pas d'ici
    // Toujours actif mais l'échéance a bougé (renouvellement webhook manqué).
    await ref.update({
      proExpiresAt: admin.firestore.Timestamp.fromMillis(rcExpiryMs),
      proWillRenew: true,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return "renewed";
  }

  if (wasActive) {
    await ref.update({
      subscriptionTier: "free",
      proEntitlementActive: false,
      proWillRenew: false,
      proExpiresAt:
        rcExpiryMs !== null
          ? admin.firestore.Timestamp.fromMillis(rcExpiryMs)
          : (data.proExpiresAt ?? null),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return "downgraded";
  }

  return "unchanged";
}

/**
 * Coeur du cron : re-vérifie les comptes actifs à échéance dépassée. Testable
 * via `fetchProExpiry` injecté.
 */
export async function reconcileExpiredEntitlements(
  db: admin.firestore.Firestore,
  fetchProExpiry: ProExpiryFetcher,
  nowMs: number,
  limit = BATCH_SIZE,
): Promise<{checked: number; downgraded: number; renewed: number; failed: number}> {
  const snap = await db
    .collection("landlords")
    .where("proEntitlementActive", "==", true)
    .limit(limit)
    .get();

  let checked = 0;
  let downgraded = 0;
  let renewed = 0;
  let failed = 0;

  for (const doc of snap.docs) {
    // Filtre EN MÉMOIRE : ne réconcilier que les échéances dépassées.
    const expMs = tsToMillis(doc.data().proExpiresAt);
    if (expMs !== null && expMs > nowMs) continue;

    checked++;
    const uid = doc.id;
    try {
      const rcExpiryMs = await fetchProExpiry(uid);
      const outcome = await reconcileLandlord(db, uid, rcExpiryMs, nowMs);
      if (outcome === "downgraded") downgraded++;
      else if (outcome === "renewed") renewed++;
    } catch (err) {
      failed++;
      logger.error(`reconcileEntitlements: failed uid=${uid}`, err);
    }
  }

  return {checked, downgraded, renewed, failed};
}

/** Fetcher de production : API REST RevenueCat v1 (subscriber). */
function makeRevenueCatFetcher(apiKey: string): ProExpiryFetcher {
  return async (uid) => {
    const resp = await fetch(
      `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(uid)}`,
      {headers: {Authorization: `Bearer ${apiKey}`}},
    );
    if (!resp.ok) throw new Error(`RevenueCat API ${resp.status}`);
    const body = (await resp.json()) as {
      subscriber?: {
        entitlements?: Record<string, {expires_date?: string | null}>;
      };
    };
    const ent = body.subscriber?.entitlements?.[PRO_ENTITLEMENT_ID];
    if (!ent || !ent.expires_date) return null;
    const ms = Date.parse(ent.expires_date);
    return Number.isNaN(ms) ? null : ms;
  };
}

export const reconcileEntitlements = onSchedule(
  {
    schedule: "30 3 * * *",
    timeZone: "Europe/Paris",
    region: "europe-west1",
    secrets: [revenueCatApiKey],
  },
  async () => {
    const db = admin.firestore();
    const fetcher = makeRevenueCatFetcher(revenueCatApiKey.value());
    const res = await reconcileExpiredEntitlements(db, fetcher, Date.now());
    logger.info(
      `reconcileEntitlements: checked=${res.checked} ` +
        `downgraded=${res.downgraded} renewed=${res.renewed} failed=${res.failed}`,
    );
  },
);
