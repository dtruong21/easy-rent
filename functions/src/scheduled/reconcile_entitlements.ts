/**
 * reconcileEntitlements — filet de sécurité des events webhook manqués
 * (FEAT-044, ADR 0002 ; étendu multi-paliers par FEAT-056 §7).
 *
 * Un webhook RevenueCat peut être perdu (panne, 5xx non retenté à temps). Sans
 * réconciliation, un compte resterait `paid` après une expiration, `free` après
 * un renouvellement — ou, depuis FEAT-056, **servi au mauvais palier** après un
 * `PRODUCT_CHANGE` manqué. Ce dernier cas est le plus coûteux : l'échéance
 * reste dans le futur, donc rien ne signale l'anomalie, et on peut facturer
 * Ultra en servant Pro pendant des semaines.
 *
 * Ce cron quotidien re-interroge l'API REST RevenueCat pour TOUS les comptes
 * `proEntitlementActive == true` et recalcule le palier effectif avec la MÊME
 * `deriveEffectivePlan` que le webhook — une seule définition du palier servi,
 * donc aucun désaccord possible entre le temps réel et le filet.
 *
 * Invariant de sécurité (révisé par FEAT-056) : le cron ne fait **jamais**
 * passer `free → paid` (`if (!wasActive) return "unchanged"` reste la première
 * branche). Il peut en revanche CORRIGER le palier d'un compte déjà payant,
 * dans les deux sens : c'est une correction appuyée sur la source de vérité
 * (API RC authentifiée), pas un octroi d'accès. Refuser cette correction
 * laisserait durablement sous-servi un client qui paie.
 *
 * On requête `proEntitlementActive == true` (ensemble borné = base d'abonnés)
 * → **aucun index composite requis**. Le coeur (`reconcileExpiredEntitlements`)
 * prend un *fetcher* injectable → testable sans appel réseau. La clé secrète v2
 * (`REVENUECAT_API_KEY`) n'est lue qu'en prod.
 *
 * ⚠️ ADR 0003 : ce cron tourne sur `(default)` (exception documentée de
 * `scripts/check-db-isolation.sh`) — un abonnement de test staging n'est donc
 * PAS réconcilié automatiquement. Comportement assumé, à vérifier à la main
 * pendant la recette.
 */

import * as admin from "firebase-admin";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {defineSecret} from "firebase-functions/params";
import {logger} from "firebase-functions/v2";
import {onSchedule} from "firebase-functions/v2/scheduler";

import {
  type EntitlementState,
  type EntitlementStates,
  type LevelId,
  deriveEffectivePlan,
  parseEntitlementStates,
  rcEntitlementIdFor,
  resolvePlan,
  tsToMillis,
} from "../entitlements/plan";
import {LEVELS} from "../entitlements/plan_matrix.generated";

/** Clé secrète v2 de l'API REST RevenueCat (serveur uniquement). */
const revenueCatApiKey = defineSecret("REVENUECAT_API_KEY");

// DETTE EXPLICITE : au-delà de ce lot, la réconciliation ne couvre plus toute
// la base. Ajouter alors une pagination par curseur `__name__` persistée dans
// un doc de contrôle (`_ops/reconcileCursor`). Inutile au volume actuel.
const BATCH_SIZE = 200;

/**
 * État des entitlements d'un abonné vu par RevenueCat, re-clé vers NOS ids de
 * palier. Un palier absent de la map = non accordé par RevenueCat.
 */
export type EntitlementStatesFetcher = (
  uid: string,
) => Promise<Partial<Record<LevelId, {expiresMs: number | null}>>>;

/** Issue de la réconciliation d'un compte (pour log/tests). */
export type ReconcileOutcome =
  | "unchanged"
  | "renewed"
  | "level_changed"
  | "downgraded_free";

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
 * Recompose la map d'état à partir de ce que rapporte RevenueCat, en
 * CONSERVANT les métadonnées que l'API REST ne porte pas (`productId`,
 * `store`, `lastEventAtMs` — écrites par le webhook). RevenueCat fait foi sur
 * l'activité et l'échéance ; un palier qu'il ne rapporte plus devient inactif.
 */
export function reconcileStates(
  current: EntitlementStates,
  rc: Partial<Record<LevelId, {expiresMs: number | null}>>,
  nowMs: number,
): EntitlementStates {
  const next: EntitlementStates = {};
  for (const level of LEVELS) {
    const cur = current[level.id];
    const reported = rc[level.id];
    if (cur === undefined && reported === undefined) continue;
    const active =
      reported !== undefined &&
      reported.expiresMs !== null &&
      reported.expiresMs > nowMs;
    const state: EntitlementState = {
      active,
      expiresAtMs:
        reported !== undefined ? reported.expiresMs : cur?.expiresAtMs ?? null,
      willRenew: active,
      productId: cur?.productId ?? null,
      store: cur?.store ?? null,
      lastEventAtMs: cur?.lastEventAtMs ?? 0,
    };
    next[level.id] = state;
  }
  return next;
}

/**
 * Corrige un compte d'après l'état rapporté par RevenueCat.
 *
 * Première branche inchangée et non négociable : un compte non actif n'est
 * JAMAIS promu ici — seul le webhook accorde un accès payant.
 */
export async function reconcileLandlord(
  db: admin.firestore.Firestore,
  uid: string,
  rcStates: Partial<Record<LevelId, {expiresMs: number | null}>>,
  nowMs: number,
): Promise<ReconcileOutcome> {
  const ref = db.doc(`landlords/${uid}`);
  const snap = await ref.get();
  const data = snap.data() ?? {};
  const wasActive = data.proEntitlementActive === true;
  if (!wasActive) return "unchanged"; // upgrade = ressort du webhook, pas d'ici

  const previousLevel = resolvePlan(data).levelId;
  const previousExpiryMs = tsToMillis(data.proExpiresAt);

  const states = reconcileStates(parseEntitlementStates(data), rcStates, nowMs);
  const eff = deriveEffectivePlan(states, nowMs);

  // Échéance à refléter dans `proExpiresAt` : celle du palier effectif ; à
  // défaut celle du palier précédent (qui vient d'expirer) ; à défaut on
  // conserve la valeur existante plutôt que d'effacer une info d'audit.
  const fallbackExpiryMs =
    previousLevel !== null ? states[previousLevel]?.expiresAtMs ?? null : null;
  const effExpiryMs = eff.state?.expiresAtMs ?? fallbackExpiryMs;

  const patch: Record<string, unknown> = {
    entitlements: toFirestoreStates(states),
    subscriptionTier: eff.active ? "paid" : "free",
    planLevel: eff.levelId,
    proEntitlementActive: eff.active,
    proWillRenew: eff.state?.willRenew ?? false,
    proExpiresAt:
      effExpiryMs !== null ?
        Timestamp.fromMillis(effExpiryMs) :
        (data.proExpiresAt ?? null),
    updatedAt: FieldValue.serverTimestamp(),
  };
  await ref.update(patch);

  if (!eff.active) return "downgraded_free";
  if (eff.levelId !== previousLevel) {
    // Toute correction de palier par le cron signale un webhook manqué : c'est
    // un problème d'intégration à investiguer, pas une routine.
    logger.warn(
      `reconcileEntitlements: level_changed ${previousLevel ?? "?"}→` +
        `${eff.levelId ?? "?"} uid=${uid} (webhook PRODUCT_CHANGE manqué ?)`,
    );
    return "level_changed";
  }
  if (effExpiryMs !== null && effExpiryMs !== previousExpiryMs) return "renewed";
  return "unchanged";
}

/**
 * Coeur du cron : re-vérifie TOUS les comptes actifs (plus seulement ceux dont
 * l'échéance est dépassée — un `PRODUCT_CHANGE` manqué laisse une échéance
 * future et serait invisible autrement). Testable via `fetchStates` injecté.
 */
export async function reconcileExpiredEntitlements(
  db: admin.firestore.Firestore,
  fetchStates: EntitlementStatesFetcher,
  nowMs: number,
  limit = BATCH_SIZE,
): Promise<{
  checked: number;
  downgradedFree: number;
  levelChanged: number;
  renewed: number;
  failed: number;
}> {
  const snap = await db
    .collection("landlords")
    .where("proEntitlementActive", "==", true)
    .limit(limit)
    .get();

  let checked = 0;
  let downgradedFree = 0;
  let levelChanged = 0;
  let renewed = 0;
  let failed = 0;

  for (const doc of snap.docs) {
    checked++;
    const uid = doc.id;
    try {
      const rcStates = await fetchStates(uid);
      const outcome = await reconcileLandlord(db, uid, rcStates, nowMs);
      if (outcome === "downgraded_free") downgradedFree++;
      else if (outcome === "level_changed") levelChanged++;
      else if (outcome === "renewed") renewed++;
    } catch (err) {
      failed++;
      logger.error(`reconcileEntitlements: failed uid=${uid}`, err);
    }
  }

  return {checked, downgradedFree, levelChanged, renewed, failed};
}

/**
 * Fetcher de production : API REST RevenueCat v1 (subscriber).
 *
 * Ne retient que les entitlements déclarés dans la table, re-clés vers nos ids
 * de palier — un entitlement étranger n'accorde jamais rien (W5). Un
 * entitlement sans `expires_date` (accès à vie) est traité comme non actif :
 * comportement conservé à l'identique d'avant FEAT-056, le produit ne vend
 * aucun accès à vie.
 */
function makeRevenueCatFetcher(apiKey: string): EntitlementStatesFetcher {
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
    const entitlements = body.subscriber?.entitlements ?? {};
    const states: Partial<Record<LevelId, {expiresMs: number | null}>> = {};
    for (const level of LEVELS) {
      const rcId = rcEntitlementIdFor(level.id);
      if (rcId === null) continue; // palier sans entitlement RC créé
      const ent = entitlements[rcId];
      if (!ent || !ent.expires_date) continue;
      const ms = Date.parse(ent.expires_date);
      states[level.id] = {expiresMs: Number.isNaN(ms) ? null : ms};
    }
    return states;
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
        `downgradedFree=${res.downgradedFree} levelChanged=${res.levelChanged} ` +
        `renewed=${res.renewed} failed=${res.failed}`,
    );
  },
);
