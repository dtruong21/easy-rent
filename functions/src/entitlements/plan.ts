/**
 * Résolution du palier effectif et des plafonds côté serveur (FEAT-056, §5.1).
 *
 * **Logique PURE, aucune E/S — volontairement.** Les points de gating tournent
 * déjà à l'intérieur de transactions où le snapshot `landlords` est lu
 * (`property_tenant.ts`, `lease_payment.ts`) ; un helper `assertQuota(db, uid)`
 * ferait une seconde lecture, hors transaction pour `documents.ts` et en
 * violation du contrat transactionnel ailleurs. On substitue donc du calcul,
 * pas de l'I/O — d'où aussi aucun accès Firestore direct ici (ADR 0003).
 * (Ne pas réintroduire le nom littéral de l'API dans ce commentaire :
 * `scripts/check-db-isolation.sh` grep le fichier et le compte comme une
 * violation, commentaire ou non.)
 *
 * Le modèle (plan §1.2, Option B) :
 *   - `subscriptionTier ∈ {anonymous, free, paid}` = **classe d'accès**,
 *     inchangée, ce que savent lire les clients déjà déployés ;
 *   - `planLevel ∈ {pro, max, ultra} | null` = **palier commercial**, additif.
 *
 * Les plafonds se lisent TOUJOURS sur le palier effectif dérivé du couple,
 * jamais sur `subscriptionTier` seul : indexer sur la classe d'accès forcerait
 * Pro, Max et Ultra à partager les mêmes quotas, ce qui rendrait la
 * différenciation commerciale inexprimable.
 */

import {
  ANONYMOUS_KEY,
  FREE_KEY,
  LEVELS,
  type LevelId,
  type PlanKey,
  type QuotaId,
  errorCodeFor,
  levelForRcEntitlement,
  levelSpec,
  quotaLimit as matrixQuotaLimit,
  rankOf,
} from "./plan_matrix.generated";

export {errorCodeFor, levelForRcEntitlement};
export type {LevelId, PlanKey, QuotaId};

/** Classe d'accès stockée dans `landlords/{uid}.subscriptionTier`. */
export type AccessTier = "anonymous" | "free" | "paid";

/** Palier effectif d'un compte : classe d'accès + palier commercial. */
export interface ResolvedPlan {
  /** Classe d'accès (valeur normalisée de `subscriptionTier`). */
  readonly tier: AccessTier;
  /** Palier commercial, non-null SSI `tier === "paid"` (invariant I1). */
  readonly levelId: LevelId | null;
  /** Clé d'indexation de la table de droits. */
  readonly key: PlanKey;
}

/**
 * Palier de repli des abonnés antérieurs à FEAT-056 : un doc `paid` sans
 * `planLevel` (invariant I3), et tout `planLevel` inconnu du serveur (I4).
 * Le plus BAS des paliers payants — on ne sur-sert jamais par accident.
 */
const LEGACY_PAID_LEVEL: LevelId = "pro";

/**
 * Dérive le palier effectif depuis les données brutes du doc landlord.
 *
 * Défaut sécuritaire : `anonymous` si `subscriptionTier` est absent, illisible
 * ou inconnu. C'est un défaut **serveur** de dernier recours (sur-restreindre
 * est correct ici), à ne pas confondre avec le fail-UP du client, qui, lui,
 * doit sur-autoriser pour ne jamais verrouiller un abonné qui paie.
 *
 * Remplace le `typeof landlord.subscriptionTier === "string" ? … : "anonymous"`
 * qui était recopié dans les cinq points de gating.
 */
export function resolvePlan(
  landlord: Record<string, unknown> | null | undefined,
): ResolvedPlan {
  const rawTier = landlord?.subscriptionTier;
  const tier: AccessTier =
    rawTier === "paid" || rawTier === "free" ? rawTier : ANONYMOUS_KEY;

  if (tier !== "paid") {
    return {tier, levelId: null, key: tier === "free" ? FREE_KEY : ANONYMOUS_KEY};
  }

  const rawLevel = landlord?.planLevel;
  const known =
    typeof rawLevel === "string" ? levelSpec(rawLevel)?.id ?? null : null;
  const levelId = known ?? LEGACY_PAID_LEVEL;
  return {tier, levelId, key: levelId};
}

/**
 * Plafond du quota pour ce palier. `null` = illimité.
 *
 * Les call sites gardent leur propre `throw` : les codes d'erreur
 * (`property_limit_reached`, …) sont un contrat déjà mappé côté Flutter, et
 * les remonter dans un helper les rendrait plus faciles à casser par
 * inadvertance.
 */
export function quotaLimit(plan: ResolvedPlan, quota: QuotaId): number | null {
  return matrixQuotaLimit(plan.key, quota);
}

// ============================================================================
// État par palier (`landlords/{uid}.entitlements`) — FEAT-056 §1.3, §3.3
// ============================================================================

/**
 * État d'UN palier. Représentation interne : les échéances sont en
 * millisecondes epoch, la conversion depuis/vers `Timestamp` reste chez les
 * appelants (webhook, cron) pour que ce module ne dépende d'aucun SDK.
 */
export interface EntitlementState {
  /** RevenueCat accorde-t-il ce palier ? */
  readonly active: boolean;
  /** Échéance, `null` = pas d'échéance connue. */
  readonly expiresAtMs: number | null;
  /** Renouvellement automatique encore armé. */
  readonly willRenew: boolean;
  /** Product id du store, pour le support. */
  readonly productId: string | null;
  /** Store normalisé (`app_store` | `play_store` | `web` | `promo`). */
  readonly store: string | null;
  /** Garde d'ordre PAR PALIER (W2) : horodatage du dernier event appliqué. */
  readonly lastEventAtMs: number;
}

/** Map d'état, indexée par palier. Un palier absent = jamais accordé. */
export type EntitlementStates = Partial<Record<LevelId, EntitlementState>>;

/** Palier effectif d'un compte, dérivé de sa map d'état. */
export interface EffectivePlan {
  /** Au moins un palier actif et non échu. */
  readonly active: boolean;
  /** Palier de rang le plus élevé parmi les actifs (W3), `null` si aucun. */
  readonly levelId: LevelId | null;
  /** État de ce palier — c'est lui que reflètent les champs `pro*`. */
  readonly state: EntitlementState | null;
}

/** Millisecondes epoch depuis un Timestamp Firestore, une Date, ou un nombre. */
export function tsToMillis(value: unknown): number | null {
  if (value == null) return null;
  if (typeof value === "number") return value;
  if (value instanceof Date) return value.getTime();
  const maybe = value as {toMillis?: () => number; toDate?: () => Date};
  if (typeof maybe.toMillis === "function") return maybe.toMillis();
  if (typeof maybe.toDate === "function") return maybe.toDate().getTime();
  return null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function toState(raw: Record<string, unknown>): EntitlementState {
  return {
    active: raw.active === true,
    expiresAtMs: tsToMillis(raw.expiresAt),
    willRenew: raw.willRenew === true,
    productId: typeof raw.productId === "string" ? raw.productId : null,
    store: typeof raw.store === "string" ? raw.store : null,
    lastEventAtMs:
      typeof raw.lastEventAtMs === "number" ? raw.lastEventAtMs : 0,
  };
}

/**
 * État de repli pour un doc antérieur à FEAT-056 : aucun n'a de map
 * `entitlements`. Appliqué **en lecture seule** — jamais de batch de migration,
 * ce qui est précisément ce qui rend sûr le déploiement Functions partagé
 * prod/staging (§3.4).
 *
 * Un compte payant legacy est réputé porter le palier `pro`, avec l'échéance et
 * le store déjà présents dans les champs `pro*`.
 */
export function legacyStates(
  landlord: Record<string, unknown> | null | undefined,
): EntitlementStates {
  if (landlord?.proEntitlementActive !== true) return {};
  return {
    pro: {
      active: true,
      expiresAtMs: tsToMillis(landlord.proExpiresAt),
      willRenew: landlord.proWillRenew !== false,
      productId:
        typeof landlord.proProductId === "string" ? landlord.proProductId : null,
      store: typeof landlord.proStore === "string" ? landlord.proStore : null,
      lastEventAtMs:
        typeof landlord.proLastEventAtMs === "number" ?
          landlord.proLastEventAtMs :
          0,
    },
  };
}

/** La map `entitlements` est-elle matérialisée sur ce doc ? */
export function hasEntitlementStates(
  landlord: Record<string, unknown> | null | undefined,
): boolean {
  return isRecord(landlord?.entitlements);
}

/**
 * Lit la map d'état d'un doc landlord, avec repli sur l'état legacy. Ignore
 * les paliers inconnus de la table (W5 : un entitlement étranger ou retiré ne
 * doit jamais accorder d'accès).
 */
export function parseEntitlementStates(
  landlord: Record<string, unknown> | null | undefined,
): EntitlementStates {
  const raw = landlord?.entitlements;
  if (!isRecord(raw)) return legacyStates(landlord);
  const states: EntitlementStates = {};
  for (const level of LEVELS) {
    const entry = raw[level.id];
    if (isRecord(entry)) states[level.id] = toState(entry);
  }
  return states;
}

/**
 * Palier effectif = **rang maximal parmi les paliers actifs et non échus**
 * (W3). Fonction pure PARTAGÉE par le webhook et le cron : c'est la garantie
 * qu'il n'existe qu'une seule définition du palier servi, donc aucun désaccord
 * possible entre le temps réel et le filet de réconciliation.
 *
 * Un palier marqué `active` mais dont l'échéance est passée ne compte pas — la
 * dérivation est donc déjà correcte même si le cron n'est pas encore passé
 * nettoyer l'état.
 */
export function deriveEffectivePlan(
  states: EntitlementStates,
  nowMs: number,
): EffectivePlan {
  let bestId: LevelId | null = null;
  let bestState: EntitlementState | null = null;
  for (const level of LEVELS) {
    const state = states[level.id];
    if (!state?.active) continue;
    if (state.expiresAtMs !== null && state.expiresAtMs <= nowMs) continue;
    if (bestId === null || rankOf(level.id) > rankOf(bestId)) {
      bestId = level.id;
      bestState = state;
    }
  }
  return {active: bestId !== null, levelId: bestId, state: bestState};
}

/** Entitlement RevenueCat d'un palier, `null` s'il n'en a pas encore. */
export function rcEntitlementIdFor(levelId: LevelId): string | null {
  return levelSpec(levelId)?.rcEntitlementId ?? null;
}
