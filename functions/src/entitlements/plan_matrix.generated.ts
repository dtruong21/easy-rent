// GENERATED — do not edit. Source: config/entitlements.json
// Regenerate: node functions/tool/gen_entitlements.mjs
// Guard: bash scripts/check-entitlements-parity.sh
//
// Miroir TypeScript de la table de droits (FEAT-056). Le jumeau Dart est
// lib/features/auth/domain/plan_matrix.g.dart ; les deux embarquent le
// même sourceSha.

/** Identifiant d'un palier commercial payant. */
export type LevelId = "pro" | "max" | "ultra";

/**
 * Clé de **palier effectif** : classe d'accès non payante, ou palier
 * payant. C'est la seule clé d'indexation de la table — jamais un
 * `subscriptionTier` brut, qui écraserait la différenciation entre
 * paliers payants.
 */
export type PlanKey = "anonymous" | "free" | LevelId;

/** Identifiant d'un quota déclaré dans la table canonique. */
export type QuotaId =
  | "properties"
  | "tenants"
  | "activeLeases"
  | "documents"
  | "scenarios"
  | "documentMaxBytes";

/** Identifiant d'une feature déclarée dans la table canonique. */
export type FeatureId =
  | "chargeRegularization"
  | "scenarioComparison"
  | "prioritySupport"
  | "paymentReminders"
  | "listings"
  | "accountingExport"
  | "collaborators";

/** `server` = une Cloud Function refuse ; `client` = UI seule ; `none` = hors produit. */
export type Enforcement = "server" | "client" | "none";

/** Un palier commercial payant, tel que décrit par la table. */
export interface PlanLevelSpec {
  /** Identifiant interne (valeur stockée dans `landlords/{uid}.planLevel`). */
  readonly id: LevelId;
  /** Rang total. anonymous = 0, free = 1, paliers payants > 1. */
  readonly rank: number;
  /** Entitlement RevenueCat, `null` si pas encore créé au dashboard. */
  readonly rcEntitlementId: string | null;
  /** Nom du paramètre Firebase du price Stripe mensuel. */
  readonly stripePriceParamMonthly: string;
  /** Nom du paramètre Firebase du price Stripe annuel. */
  readonly stripePriceParamAnnual: string;
  /** Prix mensuel affiché (chaîne déjà formatée). */
  readonly priceLabelMonthly: string;
  /** Prix annuel affiché (chaîne déjà formatée). */
  readonly priceLabelAnnual: string;
  /** `false` = palier affiché mais non vendable (aucun chemin de paiement). */
  readonly purchasable: boolean;
  /** `true` = prix annoncé comme indicatif, pas comme tarif ferme. */
  readonly priceIndicative: boolean;
  /** `true` = palier mis en avant sur la page de pricing. */
  readonly recommended: boolean;
}

/** Version de schéma de la table canonique. */
export const PLAN_MATRIX_SCHEMA_VERSION = 1;

/** SHA-256 de config/entitlements.json au moment de la génération. */
export const PLAN_MATRIX_SOURCE_SHA = "9455bd6767a8b1865b9ca7271ec88db71d60fb965893ee8a36f549254925e1c0";

/** Clé de palier des sessions anonymes. */
export const ANONYMOUS_KEY = "anonymous";

/** Clé de palier des comptes complets non payants. */
export const FREE_KEY = "free";

/** Paliers payants, par rang croissant. */
export const LEVELS: readonly PlanLevelSpec[] = [
  {
    id: "pro",
    rank: 10,
    rcEntitlementId: "Bailan Pro",
    stripePriceParamMonthly: "STRIPE_PRICE_PRO_MONTHLY",
    stripePriceParamAnnual: "STRIPE_PRICE_PRO_ANNUAL",
    priceLabelMonthly: "7,99 €",
    priceLabelAnnual: "79 €",
    purchasable: true,
    priceIndicative: false,
    recommended: false,
  },
  {
    id: "max",
    rank: 20,
    rcEntitlementId: "Baillan Max",
    stripePriceParamMonthly: "STRIPE_PRICE_MAX_MONTHLY",
    stripePriceParamAnnual: "STRIPE_PRICE_MAX_ANNUAL",
    priceLabelMonthly: "14,99 €",
    priceLabelAnnual: "149 €",
    purchasable: false,
    priceIndicative: true,
    recommended: true,
  },
  {
    id: "ultra",
    rank: 30,
    rcEntitlementId: "Baillan Ultra",
    stripePriceParamMonthly: "STRIPE_PRICE_ULTRA_MONTHLY",
    stripePriceParamAnnual: "STRIPE_PRICE_ULTRA_ANNUAL",
    priceLabelMonthly: "24,99 €",
    priceLabelAnnual: "249 €",
    purchasable: false,
    priceIndicative: true,
    recommended: false,
  },
];

/** Tous les ids de quota, dans l'ordre de la table. */
export const QUOTA_IDS: readonly QuotaId[] = ["properties", "tenants", "activeLeases", "documents", "scenarios", "documentMaxBytes"];

/** Tous les ids de feature, dans l'ordre de la table. */
export const FEATURE_IDS: readonly FeatureId[] = [
  "chargeRegularization",
  "scenarioComparison",
  "prioritySupport",
  "paymentReminders",
  "listings",
  "accountingExport",
  "collaborators",
];

const RANKS: Readonly<Record<string, number>> = {
  "anonymous": 0,
  "free": 1,
  "pro": 10,
  "max": 20,
  "ultra": 30,
};

const QUOTA_VALUES: Readonly<
  Record<QuotaId, Readonly<Record<string, number | null>>>
> = {
  "properties": {
    "anonymous": 0,
    "free": 2,
    "pro": 5,
    "max": 15,
    "ultra": null,
  },
  "tenants": {
    "anonymous": 0,
    "free": 3,
    "pro": 8,
    "max": 20,
    "ultra": null,
  },
  "activeLeases": {
    "anonymous": 0,
    "free": 2,
    "pro": 5,
    "max": 15,
    "ultra": null,
  },
  "documents": {
    "anonymous": 0,
    "free": 10,
    "pro": 50,
    "max": 150,
    "ultra": null,
  },
  "scenarios": {
    "anonymous": 1,
    "free": 3,
    "pro": 15,
    "max": 30,
    "ultra": null,
  },
  "documentMaxBytes": {
    "anonymous": 0,
    "free": 10485760,
    "pro": 10485760,
    "max": 26214400,
    "ultra": 52428800,
  },
};

const QUOTA_ERROR_CODES: Readonly<Record<QuotaId, string>> = {
  "properties": "property_limit_reached",
  "tenants": "tenant_limit_reached",
  "activeLeases": "lease_limit_reached",
  "documents": "document_limit_reached",
  "scenarios": "scenario_limit_reached",
  "documentMaxBytes": "file_too_large",
};

const QUOTA_UNITS: Readonly<Record<QuotaId, "count" | "bytes">> = {
  "properties": "count",
  "tenants": "count",
  "activeLeases": "count",
  "documents": "count",
  "scenarios": "count",
  "documentMaxBytes": "bytes",
};

const QUOTA_ENFORCEMENT: Readonly<Record<QuotaId, Enforcement>> = {
  "properties": "server",
  "tenants": "server",
  "activeLeases": "server",
  "documents": "server",
  "scenarios": "server",
  "documentMaxBytes": "server",
};

const FEATURE_MIN_LEVEL: Readonly<Record<FeatureId, LevelId>> = {
  "chargeRegularization": "pro",
  "scenarioComparison": "pro",
  "prioritySupport": "max",
  "paymentReminders": "max",
  "listings": "max",
  "accountingExport": "ultra",
  "collaborators": "ultra",
};

const FEATURE_STATUS: Readonly<Record<FeatureId, "shipped" | "planned">> = {
  "chargeRegularization": "shipped",
  "scenarioComparison": "shipped",
  "prioritySupport": "shipped",
  "paymentReminders": "planned",
  "listings": "planned",
  "accountingExport": "planned",
  "collaborators": "planned",
};

const FEATURE_ENFORCEMENT: Readonly<Record<FeatureId, Enforcement>> = {
  "chargeRegularization": "client",
  "scenarioComparison": "client",
  "prioritySupport": "none",
  "paymentReminders": "server",
  "listings": "server",
  "accountingExport": "server",
  "collaborators": "server",
};

/** Rang du palier effectif. Clé inconnue → 0 (fail-closed). */
export function rankOf(planKey: string): number {
  return RANKS[planKey] ?? 0;
}

/** Id du palier payant portant exactement ce rang, `null` sinon. */
export function levelForRank(rank: number): LevelId | null {
  for (const level of LEVELS) {
    if (level.rank === rank) return level.id;
  }
  return null;
}

/**
 * Plafond du quota pour ce palier effectif. `null` = illimité.
 * Clé de palier inconnue → 0 (fail-closed : on sur-restreint, jamais
 * l'inverse).
 */
export function quotaLimit(planKey: string, quota: QuotaId): number | null {
  const limit = QUOTA_VALUES[quota][planKey];
  return limit === undefined ? 0 : limit;
}

/** Code d'erreur contractuel du quota (partagé serveur ↔ client). */
export function errorCodeFor(quota: QuotaId): string {
  return QUOTA_ERROR_CODES[quota];
}

/** `count` ou `bytes` — ne jamais additionner les deux familles. */
export function quotaUnit(quota: QuotaId): "count" | "bytes" {
  return QUOTA_UNITS[quota];
}

/** Où le quota est réellement verrouillé. */
export function quotaEnforcement(quota: QuotaId): Enforcement {
  return QUOTA_ENFORCEMENT[quota];
}

/** Palier minimal donnant droit à la feature. */
export function minLevelFor(feature: FeatureId): LevelId {
  return FEATURE_MIN_LEVEL[feature];
}

/** Où la feature est réellement verrouillée. */
export function featureEnforcement(feature: FeatureId): Enforcement {
  return FEATURE_ENFORCEMENT[feature];
}

/** `false` tant que la feature est annoncée mais pas construite. */
export function isFeatureShipped(feature: FeatureId): boolean {
  return FEATURE_STATUS[feature] === "shipped";
}

/**
 * Ce palier effectif a-t-il droit à cette feature ?
 *
 * Renvoie `false` pour une feature `planned` QUEL QUE SOIT le palier, y
 * compris le plus élevé : sinon on promet une fonctionnalité inexistante.
 */
export function hasFeature(planKey: string, feature: FeatureId): boolean {
  if (!isFeatureShipped(feature)) return false;
  return rankOf(planKey) >= rankOf(minLevelFor(feature));
}

/**
 * Palier payant correspondant à un entitlement RevenueCat.
 * `null` = entitlement étranger → à ignorer, jamais à deviner (W5).
 */
export function levelForRcEntitlement(rcEntitlementId: string): LevelId | null {
  for (const level of LEVELS) {
    if (level.rcEntitlementId === rcEntitlementId) return level.id;
  }
  return null;
}

/** Spécification d'un palier payant, `null` si l'id est inconnu. */
export function levelSpec(levelId: string): PlanLevelSpec | null {
  for (const level of LEVELS) {
    if (level.id === levelId) return level;
  }
  return null;
}

/** Ce palier est-il ouvert à la vente ? Id inconnu → `false`. */
export function isPurchasable(levelId: string): boolean {
  return levelSpec(levelId)?.purchasable ?? false;
}

/**
 * Plus petit palier payant dont le plafond couvre `needed` — sert à l'upsell
 * contextuel. `null` si aucun palier ne suffit : ne jamais proposer un palier
 * qui ne débloquerait rien.
 */
export function minLevelForQuota(
  quota: QuotaId,
  needed: number,
): LevelId | null {
  for (const level of LEVELS) {
    const limit = quotaLimit(level.id, quota);
    if (limit === null || limit >= needed) return level.id;
  }
  return null;
}
