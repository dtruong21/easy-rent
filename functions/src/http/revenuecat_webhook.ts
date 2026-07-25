/**
 * revenueCatWebhook — récepteur HTTP des events RevenueCat (FEAT-044, ADR 0002).
 *
 * **Première fonction `onRequest` du codebase.** RevenueCat POSTe ici à chaque
 * changement d'abonnement ; on en déduit l'état de l'entitlement `pro` et on
 * écrit `landlords/{uid}.subscriptionTier` (+ champs `pro*` de cache/affichage).
 * C'est le SEUL nouvel écrivain autoritaire du tier — les règles Firestore
 * restent inchangées (tier client-immuable ; l'Admin SDK ici les bypasse).
 *
 * Robustesse :
 *   - **Auth** : header `Authorization` comparé (temps constant) au secret
 *     partagé configuré côté dashboard RevenueCat ET dans Secret Manager
 *     (`firebase functions:secrets:set REVENUECAT_WEBHOOK_AUTH`). Non signé → 401.
 *   - **Idempotence + ordre** : on ignore un event plus ancien que le dernier
 *     appliqué (`proLastEventAtMs`) — évite qu'un RENEWAL retardé écrase une
 *     EXPIRATION plus récente. Re-jouer le même event est sans effet (writes
 *     déclaratifs).
 *   - **Réponse** : toujours 2xx après traitement (RevenueCat retente sur
 *     non-2xx) ; 500 seulement sur erreur inattendue (pour déclencher le retry).
 *
 * Le filet de sécurité (events manqués) est le job `reconcileEntitlements`.
 */

import {timingSafeEqual} from "crypto";

import * as admin from "firebase-admin";
import {defineSecret} from "firebase-functions/params";
import {logger} from "firebase-functions/v2";
import {onRequest} from "firebase-functions/v2/https";

import {dbForLandlordUid} from "../utils/db_router";

/** Secret partagé du header Authorization du webhook RevenueCat. */
const webhookAuth = defineSecret("REVENUECAT_WEBHOOK_AUTH");

/** L'entitlement RevenueCat qui déverrouille Baillan Pro. */
export const PRO_ENTITLEMENT_ID = "Bailan Pro";

/** Types d'events RevenueCat qui ACCORDENT l'accès (renouvelable). */
const GRANTING_RENEWABLE = new Set([
  "INITIAL_PURCHASE",
  "RENEWAL",
  "UNCANCELLATION",
  "PRODUCT_CHANGE",
  "SUBSCRIPTION_EXTENDED",
]);

/** Forme minimale d'un event RevenueCat (champs consommés ici). */
export interface RcEvent {
  type?: string;
  app_user_id?: string;
  product_id?: string | null;
  entitlement_ids?: string[] | null;
  entitlement_id?: string | null;
  store?: string | null;
  expiration_at_ms?: number | null;
  event_timestamp_ms?: number | null;
}

export type RcOutcome =
  | "applied"
  | "ignored"
  | "stale"
  | "no_landlord";

interface Decision {
  active: boolean;
  willRenew: boolean;
}

/**
 * Décide si l'entitlement est actif d'après le type d'event et l'expiration.
 * Pur (aucune E/S) — testé exhaustivement. `null` = event non pertinent pour
 * l'état d'accès (TRANSFER, inconnu) → no-op, la réconciliation fait foi.
 */
export function decideEntitlement(
  type: string,
  expirationMs: number | null,
  nowMs: number,
): Decision | null {
  if (GRANTING_RENEWABLE.has(type)) return {active: true, willRenew: true};

  // Accès à vie / achat non renouvelable : actif, ne se renouvelle pas.
  if (type === "NON_RENEWING_PURCHASE") return {active: true, willRenew: false};

  // Auto-renouvellement coupé, mais accès conservé jusqu'à l'échéance.
  if (type === "CANCELLATION") {
    return {active: expirationMs === null || expirationMs > nowMs, willRenew: false};
  }

  // Échec de paiement : accès maintenu pendant le délai de grâce (l'échéance
  // reflète la fin de grâce) ; peut encore se renouveler si résolu.
  if (type === "BILLING_ISSUE") {
    return {active: expirationMs === null || expirationMs > nowMs, willRenew: true};
  }

  // Fin d'accès.
  if (type === "EXPIRATION" || type === "SUBSCRIPTION_PAUSED") {
    return {active: false, willRenew: false};
  }

  return null;
}

/** Normalise le store RevenueCat vers nos valeurs `proStore`. */
export function storeOf(rcStore: string | null | undefined): string | null {
  switch (rcStore) {
    case "APP_STORE":
    case "MAC_APP_STORE":
      return "app_store";
    case "PLAY_STORE":
      return "play_store";
    case "STRIPE":
    case "RC_BILLING":
      return "web";
    case "PROMOTIONAL":
      return "promo";
    default:
      return rcStore ? rcStore.toLowerCase() : null;
  }
}

/** Comparaison à temps constant (évite les attaques par timing sur le secret). */
export function isAuthorizedWebhook(
  header: string | undefined,
  secret: string,
): boolean {
  if (!header || !secret) return false;
  const a = Buffer.from(header);
  const b = Buffer.from(secret);
  return a.length === b.length && timingSafeEqual(a, b);
}

function entitlementIdsOf(event: RcEvent): string[] {
  if (Array.isArray(event.entitlement_ids)) return event.entitlement_ids;
  if (event.entitlement_id) return [event.entitlement_id];
  return [];
}

/**
 * Applique un event RevenueCat au doc `landlords/{app_user_id}`. Idempotent et
 * transactionnel. Retourne l'issue pour le log/tests. Aucune exception pour un
 * event bénin (non pertinent, landlord absent, stale) — seule une vraie panne
 * Firestore remonte (→ 500 → retry RevenueCat).
 */
export async function applyRevenueCatEvent(
  db: admin.firestore.Firestore,
  event: RcEvent,
  nowMs: number,
): Promise<RcOutcome> {
  const type = event.type ?? "";

  // Event de test envoyé par RevenueCat à la config du webhook.
  if (type === "TEST") return "ignored";

  // Uniquement les events concernant NOTRE entitlement.
  if (!entitlementIdsOf(event).includes(PRO_ENTITLEMENT_ID)) return "ignored";

  const uid = event.app_user_id ?? "";
  // App User ID anonyme RevenueCat (logIn non appelé) → non mappable.
  if (!uid || uid.startsWith("$RCAnonymousID:")) return "ignored";

  const decision = decideEntitlement(type, event.expiration_at_ms ?? null, nowMs);
  if (decision === null) return "ignored";

  const ref = db.doc(`landlords/${uid}`);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return "no_landlord";
    const data = snap.data() ?? {};

    // Un anonyme ne peut pas être payant (le registre est réservé aux comptes).
    if (data.isAnonymous === true) return "ignored";

    // Garde-fou d'ordre : ignorer un event antérieur au dernier appliqué.
    const eventTs = event.event_timestamp_ms ?? 0;
    const lastTs = typeof data.proLastEventAtMs === "number" ? data.proLastEventAtMs : 0;
    if (eventTs < lastTs) return "stale";

    const active = decision.active;
    tx.update(ref, {
      subscriptionTier: active ? "paid" : "free",
      proEntitlementActive: active,
      proStore: storeOf(event.store),
      proProductId: event.product_id ?? null,
      proExpiresAt:
        typeof event.expiration_at_ms === "number"
          ? admin.firestore.Timestamp.fromMillis(event.expiration_at_ms)
          : null,
      proWillRenew: decision.willRenew,
      // proSince : posé à la 1re activation, conservé ensuite (audit).
      proSince: active
        ? (data.proSince ?? admin.firestore.FieldValue.serverTimestamp())
        : (data.proSince ?? null),
      proLastEventAtMs: eventTs,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return "applied";
  });
}

export const revenueCatWebhook = onRequest(
  {secrets: [webhookAuth]},
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).send("method not allowed");
      return;
    }
    const secret = webhookAuth.value().trim();

    // Cloud Run v2 can overwrite req.headers.authorization with its own
    // routing audience URL. Fall back to rawHeaders to recover the real
    // Authorization value sent by RevenueCat.
    let authorized = isAuthorizedWebhook(req.headers.authorization, secret);
    if (!authorized) {
      const raw = req.rawHeaders;
      for (let i = 0; i < raw.length; i += 2) {
        if (raw[i]?.toLowerCase() === "authorization") {
          if (isAuthorizedWebhook(raw[i + 1], secret)) {
            authorized = true;
            break;
          }
        }
      }
    }

    if (!authorized) {
      logger.warn("revenueCatWebhook: unauthorized request rejected");
      res.status(401).send("unauthorized");
      return;
    }

    const body = req.body as {event?: RcEvent} | undefined;
    const event = body?.event ?? {};
    if (!event.type) {
      res.status(400).send("missing event");
      return;
    }

    try {
      // ADR 0003 : le webhook n'a pas d'Origin (server-to-server). On route vers
      // la base qui contient réellement le doc landlord (prod d'abord, puis dev)
      // — un abonnement de test créé depuis staging bascule alors le tier dans
      // `dev`, pas en prod.
      const db = await dbForLandlordUid(event.app_user_id ?? "");
      const outcome = await applyRevenueCatEvent(db, event, Date.now());
      logger.info(
        `revenueCatWebhook: ${event.type} app_user_id=${event.app_user_id} ` +
          `→ ${outcome}`,
      );
      res.status(200).send("ok");
    } catch (err) {
      // Panne inattendue → 500 pour que RevenueCat retente.
      logger.error("revenueCatWebhook: unexpected error", err);
      res.status(500).send("error");
    }
  },
);
