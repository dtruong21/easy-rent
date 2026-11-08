// Générateur du miroir TypeScript de la table de droits (FEAT-056, plan §2.2).
//
//   node functions/tool/gen_entitlements.mjs
//
// Lit `config/entitlements.json` (SOURCE CANONIQUE UNIQUE) et écrit
// `functions/src/entitlements/plan_matrix.generated.ts`. Son jumeau Dart est
// `tool/gen_entitlements.dart` : les deux appliquent EXACTEMENT les mêmes
// validations et embarquent le même `sourceSha`, ce que
// `scripts/check-entitlements-parity.sh` vérifie en CI.
//
// Pourquoi générer plutôt qu'importer le JSON (`resolveJsonModule`) : le
// fichier canonique est HORS `functions/`, donc hors `rootDir` et hors du
// bundle déployé. Un `import` remonterait au-dessus de rootDir et casserait le
// build déployable.
//
// Le fichier émis doit passer `npm run lint` (eslint : double quotes, indent 2,
// comma-dangle always-multiline, object-curly-spacing never, eol-last) ET
// `npm run build` (tsc strict + noUncheckedIndexedAccess).

import {createHash} from "node:crypto";
import {mkdirSync, readFileSync, writeFileSync} from "node:fs";
import path from "node:path";
import {fileURLToPath} from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(HERE, "..", "..");
const SOURCE = path.join(REPO_ROOT, "config", "entitlements.json");
const OUT = path.join(
  REPO_ROOT,
  "functions",
  "src",
  "entitlements",
  "plan_matrix.generated.ts",
);

const ANONYMOUS_KEY = "anonymous";
const FREE_KEY = "free";
const ANONYMOUS_RANK = 0;
const FREE_RANK = 1;

const ENFORCEMENTS = new Set(["server", "client", "none"]);
const UNITS = new Set(["count", "bytes"]);
const STATUSES = new Set(["shipped", "planned"]);
const PLACEHOLDER_MARKERS = ["DÉFINIR", "DEFINIR", "TODO", "FIXME"];
const RESERVED_IDS = new Set([
  "values", "index", "name", "hashCode", "runtimeType", "toString",
  "noSuchMethod", "id", "default", "new", "class", "enum", "const", "var",
  "null", "true", "false",
]);
const IDENT_RE = /^[a-z][A-Za-z0-9]*$/;

function fail(message) {
  console.error(`❌ config/entitlements.json invalide : ${message}`);
  process.exit(1);
}

function requireNonEmptyString(value, at) {
  if (typeof value !== "string" || value.trim() === "") {
    fail(`${at} : chaîne non vide attendue`);
  }
  const upper = value.toUpperCase();
  for (const marker of PLACEHOLDER_MARKERS) {
    if (upper.includes(marker)) {
      fail(
        `${at} : marqueur de config incomplète "${marker}" — le générateur ` +
          "refuse de produire un miroir à trous",
      );
    }
  }
  return value;
}

function requireIdent(value, at) {
  const s = requireNonEmptyString(value, at);
  if (!IDENT_RE.test(s)) {
    fail(`${at} : identifiant lowerCamelCase attendu, reçu "${s}"`);
  }
  if (RESERVED_IDS.has(s)) fail(`${at} : identifiant réservé "${s}"`);
  return s;
}

function requireBool(value, at) {
  if (typeof value !== "boolean") fail(`${at} : booléen attendu`);
  return value;
}

function requireEnum(value, allowed, at) {
  const s = requireNonEmptyString(value, at);
  if (!allowed.has(s)) {
    fail(`${at} : valeur inconnue "${s}" (attendu : ${[...allowed].join(" | ")})`);
  }
  return s;
}

function isPlainObject(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** Parse + valide la table. Miroir exact de EntitlementsConfig.parse (Dart). */
function parseConfig(raw) {
  if (!isPlainObject(raw)) fail("racine : objet JSON attendu");
  if (!Number.isInteger(raw.schemaVersion)) fail("schemaVersion : entier attendu");

  // --- levels ---------------------------------------------------------------
  if (!Array.isArray(raw.levels) || raw.levels.length === 0) {
    fail("levels : liste non vide attendue");
  }
  const levels = [];
  const seenIds = new Set();
  const seenRanks = new Set();
  const seenRcIds = new Set();
  for (const entry of raw.levels) {
    if (!isPlainObject(entry)) fail("levels[] : objet attendu");
    const id = requireIdent(entry.id, "levels[].id");
    if (seenIds.has(id)) fail(`levels : id dupliqué "${id}"`);
    seenIds.add(id);
    if (!Number.isInteger(entry.rank)) fail(`levels[${id}].rank : entier attendu`);
    if (entry.rank <= FREE_RANK) {
      fail(
        `levels[${id}].rank = ${entry.rank} : un palier payant doit avoir un ` +
          `rang > ${FREE_RANK} (invariant I5 — jamais de palier payant sous ` +
          "le gratuit)",
      );
    }
    if (seenRanks.has(entry.rank)) fail(`levels : rang dupliqué ${entry.rank}`);
    seenRanks.add(entry.rank);

    let rcId = null;
    if (entry.rcEntitlementId !== null && entry.rcEntitlementId !== undefined) {
      rcId = requireNonEmptyString(
        entry.rcEntitlementId,
        `levels[${id}].rcEntitlementId`,
      );
      if (seenRcIds.has(rcId)) {
        fail(`levels : rcEntitlementId dupliqué "${rcId}"`);
      }
      seenRcIds.add(rcId);
    }

    if (!isPlainObject(entry.stripePriceParam)) {
      fail(`levels[${id}].stripePriceParam : objet attendu`);
    }
    if (!isPlainObject(entry.priceLabel)) {
      fail(`levels[${id}].priceLabel : objet attendu`);
    }

    const purchasable = requireBool(entry.purchasable, `levels[${id}].purchasable`);
    if (purchasable && rcId === null) {
      fail(
        `levels[${id}] : purchasable=true sans rcEntitlementId — un palier ` +
          "vendable sans entitlement RevenueCat encaisse sans jamais accorder " +
          "l'accès",
      );
    }

    levels.push({
      id,
      rank: entry.rank,
      rcEntitlementId: rcId,
      stripePriceParamMonthly: requireNonEmptyString(
        entry.stripePriceParam.monthly,
        `levels[${id}].stripePriceParam.monthly`,
      ),
      stripePriceParamAnnual: requireNonEmptyString(
        entry.stripePriceParam.annual,
        `levels[${id}].stripePriceParam.annual`,
      ),
      priceLabelMonthly: requireNonEmptyString(
        entry.priceLabel.monthly,
        `levels[${id}].priceLabel.monthly`,
      ),
      priceLabelAnnual: requireNonEmptyString(
        entry.priceLabel.annual,
        `levels[${id}].priceLabel.annual`,
      ),
      purchasable,
      priceIndicative: requireBool(
        entry.priceIndicative,
        `levels[${id}].priceIndicative`,
      ),
      recommended: requireBool(entry.recommended, `levels[${id}].recommended`),
    });
  }
  levels.sort((a, b) => a.rank - b.rank);

  const expectedKeys = [ANONYMOUS_KEY, FREE_KEY, ...levels.map((l) => l.id)];

  // --- quotas ---------------------------------------------------------------
  if (!isPlainObject(raw.quotas)) fail("quotas : objet attendu");
  const quotas = [];
  for (const [key, spec] of Object.entries(raw.quotas)) {
    if (key.startsWith("_")) continue; // note documentaire
    const id = requireIdent(key, "quotas.<id>");
    if (!isPlainObject(spec)) fail(`quotas.${id} : objet attendu`);
    if (!isPlainObject(spec.values)) fail(`quotas.${id}.values : objet attendu`);

    const present = Object.keys(spec.values);
    const missing = expectedKeys.filter((k) => !present.includes(k));
    if (missing.length > 0) {
      fail(`quotas.${id}.values : paliers manquants ${JSON.stringify(missing.sort())}`);
    }
    const extra = present.filter((k) => !expectedKeys.includes(k));
    if (extra.length > 0) {
      fail(`quotas.${id}.values : paliers inconnus ${JSON.stringify(extra.sort())}`);
    }
    // Ordre déterministe : anonymous, free, puis paliers par rang croissant.
    const values = {};
    for (const k of expectedKeys) {
      const v = spec.values[k];
      if (v !== null && (!Number.isInteger(v) || v < 0)) {
        fail(`quotas.${id}.values.${k} : entier >= 0 ou null attendu`);
      }
      values[k] = v;
    }

    quotas.push({
      id,
      errorCode: requireNonEmptyString(spec.errorCode, `quotas.${id}.errorCode`),
      enforcement: requireEnum(
        spec.enforcement,
        ENFORCEMENTS,
        `quotas.${id}.enforcement`,
      ),
      unit: requireEnum(spec.unit, UNITS, `quotas.${id}.unit`),
      values,
    });
  }
  if (quotas.length === 0) fail("quotas : au moins un quota attendu");

  // --- features -------------------------------------------------------------
  if (!isPlainObject(raw.features)) fail("features : objet attendu");
  const features = [];
  for (const [key, spec] of Object.entries(raw.features)) {
    if (key.startsWith("_")) continue;
    const id = requireIdent(key, "features.<id>");
    if (!isPlainObject(spec)) fail(`features.${id} : objet attendu`);
    const minLevel = requireNonEmptyString(spec.minLevel, `features.${id}.minLevel`);
    if (!seenIds.has(minLevel)) {
      fail(`features.${id}.minLevel : palier inconnu "${minLevel}"`);
    }
    features.push({
      id,
      minLevel,
      enforcement: requireEnum(
        spec.enforcement,
        ENFORCEMENTS,
        `features.${id}.enforcement`,
      ),
      status: requireEnum(spec.status, STATUSES, `features.${id}.status`),
    });
  }

  return {schemaVersion: raw.schemaVersion, levels, quotas, features};
}

/** Littéral TS entre guillemets doubles (règle eslint `quotes`). */
function ts(value) {
  return JSON.stringify(value);
}

function tsNullable(value) {
  return value === null ? "null" : ts(value);
}

/**
 * Union de littéraux, repliée sur plusieurs lignes au-delà de la largeur de
 * confort eslint (`max-len` 100) pour rester lisible en revue.
 */
function union(ids) {
  const flat = ids.map((id) => ts(id)).join(" | ");
  if (flat.length <= 60) return ` ${flat}`;
  return `\n  | ${ids.map((id) => ts(id)).join("\n  | ")}`;
}

function emit(config, sourceSha) {
  const levelIds = config.levels.map((l) => l.id);
  const quotaIds = config.quotas.map((q) => q.id);
  const featureIds = config.features.map((f) => f.id);
  const out = [];
  const w = (line = "") => out.push(line);

  w("// GENERATED — do not edit. Source: config/entitlements.json");
  w("// Regenerate: node functions/tool/gen_entitlements.mjs");
  w("// Guard: bash scripts/check-entitlements-parity.sh");
  w("//");
  w("// Miroir TypeScript de la table de droits (FEAT-056). Le jumeau Dart est");
  w("// lib/features/auth/domain/plan_matrix.g.dart ; les deux embarquent le");
  w("// même sourceSha.");
  w();
  w("/** Identifiant d'un palier commercial payant. */");
  w(`export type LevelId =${union(levelIds)};`);
  w();
  w("/**");
  w(" * Clé de **palier effectif** : classe d'accès non payante, ou palier");
  w(" * payant. C'est la seule clé d'indexation de la table — jamais un");
  w(" * `subscriptionTier` brut, qui écraserait la différenciation entre");
  w(" * paliers payants.");
  w(" */");
  w(`export type PlanKey = ${ts(ANONYMOUS_KEY)} | ${ts(FREE_KEY)} | LevelId;`);
  w();
  w("/** Identifiant d'un quota déclaré dans la table canonique. */");
  w(`export type QuotaId =${union(quotaIds)};`);
  w();
  w("/** Identifiant d'une feature déclarée dans la table canonique. */");
  w(`export type FeatureId =${union(featureIds)};`);
  w();
  w("/** `server` = une Cloud Function refuse ; `client` = UI seule ; `none` = hors produit. */");
  w("export type Enforcement = \"server\" | \"client\" | \"none\";");
  w();
  w("/** Un palier commercial payant, tel que décrit par la table. */");
  w("export interface PlanLevelSpec {");
  w("  /** Identifiant interne (valeur stockée dans `landlords/{uid}.planLevel`). */");
  w("  readonly id: LevelId;");
  w("  /** Rang total. anonymous = 0, free = 1, paliers payants > 1. */");
  w("  readonly rank: number;");
  w("  /** Entitlement RevenueCat, `null` si pas encore créé au dashboard. */");
  w("  readonly rcEntitlementId: string | null;");
  w("  /** Nom du paramètre Firebase du price Stripe mensuel. */");
  w("  readonly stripePriceParamMonthly: string;");
  w("  /** Nom du paramètre Firebase du price Stripe annuel. */");
  w("  readonly stripePriceParamAnnual: string;");
  w("  /** Prix mensuel affiché (chaîne déjà formatée). */");
  w("  readonly priceLabelMonthly: string;");
  w("  /** Prix annuel affiché (chaîne déjà formatée). */");
  w("  readonly priceLabelAnnual: string;");
  w("  /** `false` = palier affiché mais non vendable (aucun chemin de paiement). */");
  w("  readonly purchasable: boolean;");
  w("  /** `true` = prix annoncé comme indicatif, pas comme tarif ferme. */");
  w("  readonly priceIndicative: boolean;");
  w("  /** `true` = palier mis en avant sur la page de pricing. */");
  w("  readonly recommended: boolean;");
  w("}");
  w();
  w("/** Version de schéma de la table canonique. */");
  w(`export const PLAN_MATRIX_SCHEMA_VERSION = ${config.schemaVersion};`);
  w();
  w("/** SHA-256 de config/entitlements.json au moment de la génération. */");
  w(`export const PLAN_MATRIX_SOURCE_SHA = ${ts(sourceSha)};`);
  w();
  w("/** Clé de palier des sessions anonymes. */");
  w(`export const ANONYMOUS_KEY = ${ts(ANONYMOUS_KEY)};`);
  w();
  w("/** Clé de palier des comptes complets non payants. */");
  w(`export const FREE_KEY = ${ts(FREE_KEY)};`);
  w();
  w("/** Paliers payants, par rang croissant. */");
  w("export const LEVELS: readonly PlanLevelSpec[] = [");
  for (const l of config.levels) {
    w("  {");
    w(`    id: ${ts(l.id)},`);
    w(`    rank: ${l.rank},`);
    w(`    rcEntitlementId: ${tsNullable(l.rcEntitlementId)},`);
    w(`    stripePriceParamMonthly: ${ts(l.stripePriceParamMonthly)},`);
    w(`    stripePriceParamAnnual: ${ts(l.stripePriceParamAnnual)},`);
    w(`    priceLabelMonthly: ${ts(l.priceLabelMonthly)},`);
    w(`    priceLabelAnnual: ${ts(l.priceLabelAnnual)},`);
    w(`    purchasable: ${l.purchasable},`);
    w(`    priceIndicative: ${l.priceIndicative},`);
    w(`    recommended: ${l.recommended},`);
    w("  },");
  }
  w("];");
  w();
  w("/** Tous les ids de quota, dans l'ordre de la table. */");
  w(`export const QUOTA_IDS: readonly QuotaId[] = [${quotaIds.map(ts).join(", ")}];`);
  w();
  w("/** Tous les ids de feature, dans l'ordre de la table. */");
  w("export const FEATURE_IDS: readonly FeatureId[] = [");
  for (const id of featureIds) w(`  ${ts(id)},`);
  w("];");
  w();
  w("const RANKS: Readonly<Record<string, number>> = {");
  w(`  ${ts(ANONYMOUS_KEY)}: ${ANONYMOUS_RANK},`);
  w(`  ${ts(FREE_KEY)}: ${FREE_RANK},`);
  for (const l of config.levels) w(`  ${ts(l.id)}: ${l.rank},`);
  w("};");
  w();
  w("const QUOTA_VALUES: Readonly<");
  w("  Record<QuotaId, Readonly<Record<string, number | null>>>");
  w("> = {");
  for (const q of config.quotas) {
    w(`  ${ts(q.id)}: {`);
    for (const [key, value] of Object.entries(q.values)) {
      w(`    ${ts(key)}: ${value === null ? "null" : value},`);
    }
    w("  },");
  }
  w("};");
  w();
  w("const QUOTA_ERROR_CODES: Readonly<Record<QuotaId, string>> = {");
  for (const q of config.quotas) w(`  ${ts(q.id)}: ${ts(q.errorCode)},`);
  w("};");
  w();
  w("const QUOTA_UNITS: Readonly<Record<QuotaId, \"count\" | \"bytes\">> = {");
  for (const q of config.quotas) w(`  ${ts(q.id)}: ${ts(q.unit)},`);
  w("};");
  w();
  w("const QUOTA_ENFORCEMENT: Readonly<Record<QuotaId, Enforcement>> = {");
  for (const q of config.quotas) w(`  ${ts(q.id)}: ${ts(q.enforcement)},`);
  w("};");
  w();
  w("const FEATURE_MIN_LEVEL: Readonly<Record<FeatureId, LevelId>> = {");
  for (const f of config.features) w(`  ${ts(f.id)}: ${ts(f.minLevel)},`);
  w("};");
  w();
  w("const FEATURE_STATUS: Readonly<Record<FeatureId, \"shipped\" | \"planned\">> = {");
  for (const f of config.features) w(`  ${ts(f.id)}: ${ts(f.status)},`);
  w("};");
  w();
  w("const FEATURE_ENFORCEMENT: Readonly<Record<FeatureId, Enforcement>> = {");
  for (const f of config.features) w(`  ${ts(f.id)}: ${ts(f.enforcement)},`);
  w("};");
  w();
  w(STATIC_API);

  return out.join("\n");
}

/**
 * Corps invariant de l'API (§2.4 du plan) — mêmes noms, même sémantique que le
 * miroir Dart, pour que la revue croisée soit triviale.
 */
const STATIC_API = `/** Rang du palier effectif. Clé inconnue → 0 (fail-closed). */
export function rankOf(planKey: string): number {
  return RANKS[planKey] ?? 0;
}

/** Id du palier payant portant exactement ce rang, \`null\` sinon. */
export function levelForRank(rank: number): LevelId | null {
  for (const level of LEVELS) {
    if (level.rank === rank) return level.id;
  }
  return null;
}

/**
 * Plafond du quota pour ce palier effectif. \`null\` = illimité.
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

/** \`count\` ou \`bytes\` — ne jamais additionner les deux familles. */
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

/** \`false\` tant que la feature est annoncée mais pas construite. */
export function isFeatureShipped(feature: FeatureId): boolean {
  return FEATURE_STATUS[feature] === "shipped";
}

/**
 * Ce palier effectif a-t-il droit à cette feature ?
 *
 * Renvoie \`false\` pour une feature \`planned\` QUEL QUE SOIT le palier, y
 * compris le plus élevé : sinon on promet une fonctionnalité inexistante.
 */
export function hasFeature(planKey: string, feature: FeatureId): boolean {
  if (!isFeatureShipped(feature)) return false;
  return rankOf(planKey) >= rankOf(minLevelFor(feature));
}

/**
 * Palier payant correspondant à un entitlement RevenueCat.
 * \`null\` = entitlement étranger → à ignorer, jamais à deviner (W5).
 */
export function levelForRcEntitlement(rcEntitlementId: string): LevelId | null {
  for (const level of LEVELS) {
    if (level.rcEntitlementId === rcEntitlementId) return level.id;
  }
  return null;
}

/** Spécification d'un palier payant, \`null\` si l'id est inconnu. */
export function levelSpec(levelId: string): PlanLevelSpec | null {
  for (const level of LEVELS) {
    if (level.id === levelId) return level;
  }
  return null;
}

/** Ce palier est-il ouvert à la vente ? Id inconnu → \`false\`. */
export function isPurchasable(levelId: string): boolean {
  return levelSpec(levelId)?.purchasable ?? false;
}

/**
 * Plus petit palier payant dont le plafond couvre \`needed\` — sert à l'upsell
 * contextuel. \`null\` si aucun palier ne suffit : ne jamais proposer un palier
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
`;

const bytes = readFileSync(SOURCE);
const sourceSha = createHash("sha256").update(bytes).digest("hex");
const config = parseConfig(JSON.parse(bytes.toString("utf8")));

mkdirSync(path.dirname(OUT), {recursive: true});
writeFileSync(OUT, emit(config, sourceSha), "utf8");
console.log(`✅ ${path.relative(REPO_ROOT, OUT)} (sourceSha ${sourceSha})`);
