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
 * OWASP-01 : les entitlements issus d'achats SANDBOX sont écartés du fetcher
 * ([entitlementStatesFromSubscriber]) — ce cron opère sur `(default)` et peut
 * prolonger / monter de palier un compte déjà payant : il ne doit jamais le
 * faire d'après un achat de test.
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
/**
 * État d'un palier rapporté par RevenueCat.
 *
 * `sandboxShadowed` : l'entitlement de ce palier pointe vers un achat SANDBOX
 * (#209). RevenueCat ne rapporte qu'UN produit par entitlement — celui dont
 * l'échéance est la plus lointaine : un achat de test plus long masque alors un
 * vrai abonnement prod. L'état prod du palier est donc INCONNU ici : le cron
 * garde l'état enregistré (tenu à jour par les events PRODUCTION du webhook)
 * au lieu de rétrograder le compte chaque nuit.
 */
export interface RcReportedState {
  expiresMs: number | null;
  sandboxShadowed?: true;
}

export type EntitlementStatesFetcher = (
  uid: string,
) => Promise<Partial<Record<LevelId, RcReportedState>>>;

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
  rc: Partial<Record<LevelId, RcReportedState>>,
  nowMs: number,
): EntitlementStates {
  const next: EntitlementStates = {};
  for (const level of LEVELS) {
    const cur = current[level.id];
    const reported = rc[level.id];
    if (cur === undefined && reported === undefined) continue;
    if (reported?.sandboxShadowed) {
      // État prod masqué par un achat sandbox (#209) : on garde l'état
      // enregistré, en ne le laissant actif que jusqu'à SON échéance — un
      // achat sandbox n'accorde ni ne prolonge jamais rien (OWASP-01).
      if (cur === undefined) continue;
      const stillActive =
        cur.active && cur.expiresAtMs !== null && cur.expiresAtMs > nowMs;
      next[level.id] = {
        ...cur,
        active: stillActive,
        willRenew: stillActive && cur.willRenew,
      };
      continue;
    }
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
 * Forme minimale de `subscriber` dans la réponse de l'API REST RevenueCat v1
 * (`GET /v1/subscribers/{app_user_id}`), limitée aux champs consommés ici.
 */
export interface RcSubscriber {
  entitlements?: Record<
    string,
    {expires_date?: string | null; product_identifier?: string | null}
  >;
  /** Clé = identifiant de produit ; `is_sandbox` = achat en mode test. */
  subscriptions?: Record<string, {is_sandbox?: boolean}>;
}

/**
 * PURE — états rapportés par RevenueCat, re-clés vers NOS ids de palier.
 *
 * Ne retient que les entitlements déclarés dans la table (W5 : un entitlement
 * étranger n'accorde jamais rien). Un entitlement sans `expires_date` (accès à
 * vie) est traité comme non actif : comportement conservé à l'identique d'avant
 * FEAT-056, le produit ne vend aucun accès à vie.
 *
 * OWASP-01 — un entitlement adossé à un achat SANDBOX (`is_sandbox === true`
 * sur son produit) n'accorde ni ne prolonge RIEN : il est rapporté
 * `sandboxShadowed` et le cron garde l'état enregistré (#209). L'API mélange
 * achats prod et sandbox pour un même App User ID ; or ce cron opère sur
 * `(default)` (prod) et peut, sur un compte déjà payant, PROLONGER une échéance
 * ou MONTER de palier d'après ce qu'elle rapporte. Sans ce filtre, un achat
 * Stripe test (staging) ferait donc grimper un compte prod. Un produit absent
 * de `subscriptions` est traité comme prod : seul un `is_sandbox: true`
 * explicite écarte l'entitlement, pour ne pas rétrograder un client qui paie
 * sur une réponse d'API incomplète.
 */
export function entitlementStatesFromSubscriber(
  subscriber: RcSubscriber | undefined,
): Partial<Record<LevelId, RcReportedState>> {
  const entitlements = subscriber?.entitlements ?? {};
  const subscriptions = subscriber?.subscriptions ?? {};
  const states: Partial<Record<LevelId, RcReportedState>> = {};
  for (const level of LEVELS) {
    const rcId = rcEntitlementIdFor(level.id);
    if (rcId === null) continue; // palier sans entitlement RC créé
    const ent = entitlements[rcId];
    if (!ent || !ent.expires_date) continue;
    const productId = ent.product_identifier;
    if (productId && subscriptions[productId]?.is_sandbox === true) {
      // Jamais accordé ni prolongé ; l'état prod du palier est inconnu (#209).
      states[level.id] = {expiresMs: null, sandboxShadowed: true};
      continue;
    }
    const ms = Date.parse(ent.expires_date);
    states[level.id] = {expiresMs: Number.isNaN(ms) ? null : ms};
  }
  return states;
}

/**
 * Fetcher de production : API REST RevenueCat v1 (subscriber). La logique de
 * tri (entitlements connus, achats sandbox écartés) vit dans
 * [entitlementStatesFromSubscriber], pure et testée.
 */
function makeRevenueCatFetcher(apiKey: string): EntitlementStatesFetcher {
  return async (uid) => {
    const resp = await fetch(
      `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(uid)}`,
      {headers: {Authorization: `Bearer ${apiKey}`}},
    );
    if (!resp.ok) throw new Error(`RevenueCat API ${resp.status}`);
    const body = (await resp.json()) as {subscriber?: RcSubscriber};
    return entitlementStatesFromSubscriber(body.subscriber);
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
