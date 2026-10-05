/**
 * revenueCatWebhook — récepteur HTTP des events RevenueCat (FEAT-044, ADR 0002).
 *
 * **Première fonction `onRequest` du codebase.** RevenueCat POSTe ici à chaque
 * changement d'abonnement ; on en déduit l'état des entitlements et on écrit
 * `landlords/{uid}.subscriptionTier` (+ `planLevel`, la map `entitlements`, et
 * les champs `pro*` de cache/affichage). C'est le SEUL écrivain autoritaire du
 * droit — les règles Firestore gèlent tous ces champs côté client ; l'Admin SDK
 * ici les bypasse.
 *
 * FEAT-056 — multi-paliers : un event ne décrit QUE les entitlements qu'il
 * mentionne, jamais l'état global de l'abonné. On conserve donc un état PAR
 * PALIER (`entitlements.<level>`) et on en dérive le palier servi. Sans cet
 * état, une EXPIRATION sur Pro reçue après un achat d'Ultra rétrograderait un
 * client qui a payé — c'est exactement le cas du downgrade différé Apple/Google.
 *
 * Robustesse :
 *   - **Routage prod/staging (OWASP-01)** : la base est choisie par
 *     `event.environment` (`SANDBOX` → `staging`, `PRODUCTION` → `(default)`,
 *     autre → ignoré), jamais par « la base qui porte le doc » : un achat en
 *     mode test ne peut ainsi jamais accorder un palier sur un compte prod.
 *   - **Auth** : header `Authorization` comparé (temps constant) au secret
 *     partagé configuré côté dashboard RevenueCat ET dans Secret Manager
 *     (`firebase functions:secrets:set REVENUECAT_WEBHOOK_AUTH`). Non signé → 401.
 *   - **Idempotence + ordre** : on ignore un event plus ancien que le dernier
 *     appliqué **sur le palier concerné** (`entitlements.<lvl>.lastEventAtMs`)
 *     — évite qu'un RENEWAL retardé écrase une EXPIRATION plus récente, sans
 *     jeter pour autant un event frais portant sur un autre palier. Re-jouer le
 *     même event est sans effet (writes déclaratifs).
 *   - **Réponse** : toujours 2xx après traitement (RevenueCat retente sur
 *     non-2xx) ; 500 seulement sur erreur inattendue (pour déclencher le retry).
 *
 * Le filet de sécurité (events manqués) est le job `reconcileEntitlements`.
 */

import {timingSafeEqual} from "crypto";

import type * as admin from "firebase-admin";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {defineSecret} from "firebase-functions/params";
import {logger} from "firebase-functions/v2";
import {onRequest} from "firebase-functions/v2/https";

import {
  type EntitlementState,
  type EntitlementStates,
  type LevelId,
  deriveEffectivePlan,
  hasEntitlementStates,
  levelForRcEntitlement,
  parseEntitlementStates,
} from "../entitlements/plan";
import {firestoreForEnv} from "../utils/db_router";
import {readSandboxAllowlist} from "../utils/sandbox_allowlist";

/** Secret partagé du header Authorization du webhook RevenueCat. */
const webhookAuth = defineSecret("REVENUECAT_WEBHOOK_AUTH");

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
  /**
   * Environnement de l'achat, posé par RevenueCat sur chaque event :
   * `"PRODUCTION"` ou `"SANDBOX"` (achat en mode test : Stripe test, sandbox
   * Apple, licence de test Google). C'est le SEUL critère de routage prod /
   * staging du webhook — cf. [handleRevenueCatEvent].
   */
  environment?: string | null;
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
 * Paliers CONCERNÉS par un event (§3.2). Un entitlement inconnu de la table est
 * **ignoré, jamais deviné** (W5) : un entitlement de test RevenueCat ne doit
 * pas pouvoir accorder Ultra.
 */
export function affectedLevels(event: RcEvent): LevelId[] {
  const levels: LevelId[] = [];
  for (const rcId of entitlementIdsOf(event)) {
    const level = levelForRcEntitlement(rcId);
    if (level !== null && !levels.includes(level)) levels.push(level);
  }
  return levels;
}

/** Sérialise la map d'état pour Firestore (échéances → Timestamp). */
function toFirestoreStates(
  states: EntitlementStates,
): Record<string, Record<string, unknown>> {
  const out: Record<string, Record<string, unknown>> = {};
  for (const [levelId, state] of Object.entries(states)) {
    if (!state) continue;
    out[levelId] = {
      active: state.active,
      expiresAt:
        state.expiresAtMs === null ?
          null :
          Timestamp.fromMillis(state.expiresAtMs),
      willRenew: state.willRenew,
      productId: state.productId,
      store: state.store,
      lastEventAtMs: state.lastEventAtMs,
    };
  }
  return out;
}

/**
 * Applique un event RevenueCat au doc `landlords/{app_user_id}`. Idempotent et
 * transactionnel. Retourne l'issue pour le log/tests. Aucune exception pour un
 * event bénin (non pertinent, landlord absent, stale) — seule une vraie panne
 * Firestore remonte (→ 500 → retry RevenueCat).
 *
 * FEAT-056 — invariants multi-paliers (money-critical) :
 *   W1 un event ne modifie QUE les paliers qu'il mentionne. Sinon une
 *      EXPIRATION Pro effacerait un Ultra actif → abonné payant verrouillé.
 *   W2 la garde d'ordre est PAR PALIER. Deux paliers ont des cycles de vie
 *      indépendants ; une garde globale jetterait comme « stale » un event
 *      parfaitement frais concernant l'autre palier.
 *   W3 le palier servi = max(rang) parmi les actifs → jamais « facturé Ultra,
 *      servi Pro ».
 *   W4 `subscriptionTier == paid` ⟺ au moins un palier actif.
 *   W6 `proSince` n'est jamais réécrit après la première activation.
 *   W7 rejouer un event ne change rien (writes déclaratifs).
 */
export async function applyRevenueCatEvent(
  db: admin.firestore.Firestore,
  event: RcEvent,
  nowMs: number,
): Promise<RcOutcome> {
  const type = event.type ?? "";

  // Event de test envoyé par RevenueCat à la config du webhook.
  if (type === "TEST") return "ignored";

  // Uniquement les events concernant un de NOS entitlements (W5).
  const affected = affectedLevels(event);
  if (affected.length === 0) return "ignored";

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

    const eventTs = event.event_timestamp_ms ?? 0;
    const previousLastTs =
      typeof data.proLastEventAtMs === "number" ? data.proLastEventAtMs : 0;

    // Doc sans map `entitlements` (tous les abonnés d'avant FEAT-056) : la
    // seule information d'ordre disponible est le `proLastEventAtMs` global.
    // On l'utilise comme plancher pour TOUS les paliers, sinon la garde
    // d'ordre disparaîtrait le temps que la map se matérialise.
    const orderFloor = hasEntitlementStates(data) ? 0 : previousLastTs;

    const states: EntitlementStates = {...parseEntitlementStates(data)};
    let applied = 0;
    for (const levelId of affected) {
      const lastTs = states[levelId]?.lastEventAtMs ?? orderFloor;
      if (eventTs < lastTs) continue; // stale SUR CE PALIER seulement (W2)
      const next: EntitlementState = {
        active: decision.active,
        expiresAtMs:
          typeof event.expiration_at_ms === "number" ?
            event.expiration_at_ms :
            null,
        willRenew: decision.willRenew,
        productId: event.product_id ?? null,
        store: storeOf(event.store),
        lastEventAtMs: eventTs,
      };
      states[levelId] = next;
      applied++;
    }
    if (applied === 0) return "stale";

    const eff = deriveEffectivePlan(states, nowMs);
    const effExpiresAtMs = eff.state?.expiresAtMs ?? null;

    tx.update(ref, {
      entitlements: toFirestoreStates(states),
      subscriptionTier: eff.active ? "paid" : "free",
      planLevel: eff.levelId,
      proEntitlementActive: eff.active,
      // Les champs pro* restent le MIROIR du palier effectif : c'est ce qui
      // permet aux clients déjà déployés (et au cron) de continuer à
      // fonctionner sans rien connaître des paliers.
      proStore: eff.state?.store ?? null,
      proProductId: eff.state?.productId ?? null,
      proExpiresAt:
        effExpiresAtMs === null ?
          null :
          Timestamp.fromMillis(effExpiresAtMs),
      proWillRenew: eff.state?.willRenew ?? false,
      // proSince : posé à la 1re activation, conservé ensuite (audit, W6).
      proSince: eff.active ?
        (data.proSince ?? FieldValue.serverTimestamp()) :
        (data.proSince ?? null),
      // Plus une garde d'ordre (elle est par palier désormais) mais un repère
      // de diagnostic — et un champ que les rules gèlent déjà : le supprimer
      // ferait échouer l'update client de TOUS les comptes.
      proLastEventAtMs: Math.max(previousLastTs, eventTs),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return "applied";
  });
}

/** Valeur d'`environment` sûre à journaliser (JSON, bornée à 32 caractères). */
function environmentForLog(environment: unknown): string {
  return (JSON.stringify(environment ?? null) ?? "null").slice(0, 32);
}

/** Lecteur de la liste blanche sandbox (injectable pour les tests). */
export type SandboxAllowlistReader = () => Promise<ReadonlySet<string>>;

/** Lecteur de production : document `_ops/sandboxAllowlist` de la base prod. */
const readProdSandboxAllowlist: SandboxAllowlistReader = () =>
  readSandboxAllowlist(firestoreForEnv(false));

/**
 * `true` si [uid] est dans la liste blanche sandbox (FEAT-044e). Liste
 * illisible → `false` : règle par défaut (staging), jamais de déblocage prod.
 */
async function isSandboxAllowlisted(
  uid: string,
  read: SandboxAllowlistReader,
): Promise<boolean> {
  try {
    return (await read()).has(uid);
  } catch (err) {
    logger.error(
      "revenueCatWebhook: liste blanche sandbox illisible → staging " +
        `app_user_id=${uid}`,
      err,
    );
    return false;
  }
}

/**
 * Route un event vers la base de SON environnement, puis l'applique.
 *
 * OWASP-01 — un seul projet Firebase héberge prod (`(default)`) et staging
 * (base `staging`), avec une Auth partagée, un checkout staging public en Stripe
 * test et UN seul webhook RevenueCat. Router par « la base qui porte le doc »
 * (prod d'abord) laissait un compte prod payer avec la carte de test publique
 * et obtenir un palier payant en prod. La base est donc choisie par
 * `event.environment`, jamais par le contenu des bases :
 *
 *   - `"SANDBOX"`    → base `staging` UNIQUEMENT — sauf un uid de la liste
 *     blanche sandbox (`_ops/sandboxAllowlist`, FEAT-044e : compte de démo
 *     App Review, testeurs) → base `(default)` UNIQUEMENT ;
 *   - `"PRODUCTION"` → base `(default)` UNIQUEMENT ;
 *   - absent / autre → event ignoré (fail-closed) et journalisé.
 *
 * Aucun repli sur l'autre base : doc absent de la base routée → `no_landlord`
 * (cf. [applyRevenueCatEvent]). Un event SANDBOX visant un compte prod ne
 * modifie donc RIEN, et un event PRODUCTION ne touche jamais le staging.
 *
 * Les events `TEST` (ping de config du dashboard) sont ignorés sans bruit, avant
 * tout routage.
 */
export async function handleRevenueCatEvent(
  event: RcEvent,
  nowMs: number,
  readAllowlist: SandboxAllowlistReader = readProdSandboxAllowlist,
): Promise<RcOutcome> {
  if (event.type === "TEST") return "ignored";

  let isStaging: boolean;
  if (event.environment === "SANDBOX") {
    // Liste lue UNIQUEMENT pour un event SANDBOX : aucun coût sur les achats
    // réels.
    const uid = event.app_user_id ?? "";
    const allowlisted = await isSandboxAllowlisted(uid, readAllowlist);
    if (allowlisted) {
      logger.info(
        "revenueCatWebhook: SANDBOX d'un uid de la liste blanche → prod " +
          `app_user_id=${uid}`,
      );
    }
    isStaging = !allowlisted;
  } else if (event.environment === "PRODUCTION") {
    isStaging = false;
  } else {
    // uid + valeur brute (bornée : l'event est authentifié mais son contenu ne
    // l'est pas) — aucune autre donnée dans le log.
    logger.warn(
      "revenueCatWebhook: environment absent ou inconnu → ignoré " +
        `app_user_id=${event.app_user_id} ` +
        `environment=${environmentForLog(event.environment)}`,
    );
    return "ignored";
  }

  return applyRevenueCatEvent(firestoreForEnv(isStaging), event, nowMs);
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
      // ADR 0003 / OWASP-01 : le webhook n'a pas d'Origin (server-to-server).
      // La base est choisie par `event.environment` (SANDBOX → staging,
      // PRODUCTION → (default)), sans repli sur l'autre base.
      const outcome = await handleRevenueCatEvent(event, Date.now());
      logger.info(
        `revenueCatWebhook: ${event.type} app_user_id=${event.app_user_id} ` +
          `env=${environmentForLog(event.environment)} → ${outcome}`,
      );
      res.status(200).send("ok");
    } catch (err) {
      // Panne inattendue → 500 pour que RevenueCat retente.
      logger.error("revenueCatWebhook: unexpected error", err);
      res.status(500).send("error");
    }
  },
);
