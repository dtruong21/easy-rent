/**
 * Filet d'exécution de la garde de parité, côté serveur (FEAT-056, plan §2.2
 * et §10.2). Symétrique de `test/unit/plan_matrix_parity_test.dart` — MÊME
 * fichier source, mêmes assertions.
 *
 * `scripts/check-entitlements-parity.sh` prouve que le miroir TS est bien la
 * sortie du générateur. Ce test prouve que cette sortie dit bien ce que dit
 * `config/entitlements.json` : il relit le JSON BRUT depuis le disque, sans
 * réutiliser le parseur du générateur.
 */

import {createHash} from "crypto";
import {existsSync, readFileSync} from "fs";
import path from "path";

import {describe, expect, it} from "vitest";

import {
  ANONYMOUS_KEY,
  FEATURE_IDS,
  FREE_KEY,
  LEVELS,
  PLAN_MATRIX_SCHEMA_VERSION,
  PLAN_MATRIX_SOURCE_SHA,
  QUOTA_IDS,
  errorCodeFor,
  featureEnforcement,
  hasFeature,
  isFeatureShipped,
  isPurchasable,
  levelForRcEntitlement,
  minLevelFor,
  minLevelForQuota,
  quotaEnforcement,
  quotaLimit,
  quotaUnit,
  rankOf,
} from "../entitlements/plan_matrix.generated";

/** Clés de palier effectif attendues dans chaque quota. */
const PLAN_KEYS = ["anonymous", "free", "pro", "max", "ultra"];

/**
 * Remonte depuis le cwd (= `functions/` sous vitest) jusqu'à trouver la
 * source canonique. Pas de `__dirname`/`import.meta` : le premier n'existe
 * pas en ESM, le second casse `tsc --module commonjs`.
 */
function findSource(): string {
  let dir = process.cwd();
  for (let i = 0; i < 6; i++) {
    const candidate = path.join(dir, "config", "entitlements.json");
    if (existsSync(candidate)) return candidate;
    dir = path.dirname(dir);
  }
  throw new Error("config/entitlements.json introuvable en remontant depuis le cwd");
}

const SOURCE = findSource();
const RAW_BYTES = readFileSync(SOURCE);
const CONFIG = JSON.parse(RAW_BYTES.toString("utf8")) as Record<string, unknown>;

function asObject(value: unknown): Record<string, unknown> {
  return value as Record<string, unknown>;
}

function withoutNotes(value: unknown): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [key, v] of Object.entries(asObject(value))) {
    if (!key.startsWith("_")) out[key] = v;
  }
  return out;
}

describe("plan_matrix.generated.ts ↔ config/entitlements.json", () => {
  it("sourceSha correspond au JSON réellement présent", () => {
    const actual = createHash("sha256").update(RAW_BYTES).digest("hex");
    expect(PLAN_MATRIX_SOURCE_SHA).toBe(actual);
  });

  it("schemaVersion identique", () => {
    expect(PLAN_MATRIX_SCHEMA_VERSION).toBe(CONFIG.schemaVersion);
  });

  it("paliers : mêmes ids, mêmes rangs, mêmes champs", () => {
    const rawLevels = (CONFIG.levels as unknown[])
      .map(asObject)
      .sort((a, b) => (a.rank as number) - (b.rank as number));

    expect(LEVELS.length).toBe(rawLevels.length);
    rawLevels.forEach((raw, i) => {
      const gen = LEVELS[i];
      expect(gen).toBeDefined();
      if (!gen) return;
      expect(gen.id).toBe(raw.id);
      expect(gen.rank).toBe(raw.rank);
      expect(gen.rcEntitlementId).toBe(raw.rcEntitlementId);
      const stripe = asObject(raw.stripePriceParam);
      expect(gen.stripePriceParamMonthly).toBe(stripe.monthly);
      expect(gen.stripePriceParamAnnual).toBe(stripe.annual);
      const price = asObject(raw.priceLabel);
      expect(gen.priceLabelMonthly).toBe(price.monthly);
      expect(gen.priceLabelAnnual).toBe(price.annual);
      expect(gen.purchasable).toBe(raw.purchasable);
      expect(gen.priceIndicative).toBe(raw.priceIndicative);
      expect(gen.recommended).toBe(raw.recommended);
    });
  });

  it("quotas : mêmes ids, mêmes métadonnées, mêmes valeurs par palier", () => {
    const rawQuotas = withoutNotes(CONFIG.quotas);
    expect([...QUOTA_IDS].sort()).toEqual(Object.keys(rawQuotas).sort());

    for (const quota of QUOTA_IDS) {
      const raw = asObject(rawQuotas[quota]);
      expect(errorCodeFor(quota)).toBe(raw.errorCode);
      expect(quotaUnit(quota)).toBe(raw.unit);
      expect(quotaEnforcement(quota)).toBe(raw.enforcement);

      const values = asObject(raw.values);
      // Une valeur par PALIER EFFECTIF (pas par classe d'accès) : sans cela
      // les trois paliers payants partageraient forcément le même plafond.
      expect(Object.keys(values).sort()).toEqual([...PLAN_KEYS].sort());
      for (const key of PLAN_KEYS) {
        expect(quotaLimit(key, quota)).toBe(values[key]);
      }
    }
  });

  it("features : mêmes ids, mêmes minLevel/status/enforcement", () => {
    const rawFeatures = withoutNotes(CONFIG.features);
    expect([...FEATURE_IDS].sort()).toEqual(Object.keys(rawFeatures).sort());

    for (const feature of FEATURE_IDS) {
      const raw = asObject(rawFeatures[feature]);
      expect(minLevelFor(feature)).toBe(raw.minLevel);
      expect(featureEnforcement(feature)).toBe(raw.enforcement);
      expect(isFeatureShipped(feature)).toBe(raw.status === "shipped");
    }
  });
});

describe("sémantique de la table", () => {
  it("rangs des classes non payantes", () => {
    expect(rankOf(ANONYMOUS_KEY)).toBe(0);
    expect(rankOf(FREE_KEY)).toBe(1);
    for (const level of LEVELS) expect(rankOf(level.id)).toBeGreaterThan(1);
  });

  it("palier inconnu → quota 0 (fail-closed, jamais illimité)", () => {
    for (const quota of QUOTA_IDS) expect(quotaLimit("quantum", quota)).toBe(0);
    expect(rankOf("quantum")).toBe(0);
    expect(isPurchasable("quantum")).toBe(false);
  });

  it("entitlement RevenueCat \"Bailan Pro\" (typo historique) résout vers pro", () => {
    // R4 : cette chaîne est la clé effective des abonnés existants. La
    // « corriger » ferait ignorer silencieusement TOUS leurs events (W5).
    expect(levelForRcEntitlement("Bailan Pro")).toBe("pro");
    expect(levelForRcEntitlement("Baillan Pro")).toBeNull();
    expect(levelForRcEntitlement("inconnu")).toBeNull();
  });

  it("une feature \"planned\" est refusée à TOUS les paliers, Ultra inclus", () => {
    const top = LEVELS[LEVELS.length - 1];
    expect(top).toBeDefined();
    if (!top) return;
    for (const feature of FEATURE_IDS) {
      if (isFeatureShipped(feature)) continue;
      expect(hasFeature(top.id, feature)).toBe(false);
    }
  });

  it("hasFeature suit le rang pour une feature livrée", () => {
    for (const feature of FEATURE_IDS) {
      if (!isFeatureShipped(feature)) continue;
      expect(hasFeature(minLevelFor(feature), feature)).toBe(true);
      expect(hasFeature(FREE_KEY, feature)).toBe(false);
      expect(hasFeature(ANONYMOUS_KEY, feature)).toBe(false);
    }
  });

  it("un palier vendable a toujours un entitlement RevenueCat", () => {
    for (const level of LEVELS) {
      if (!level.purchasable) continue;
      expect(level.rcEntitlementId).not.toBeNull();
    }
  });

  it("minLevelForQuota rend le plus petit palier suffisant", () => {
    const quota = "documentMaxBytes";
    for (const level of LEVELS) {
      const limit = quotaLimit(level.id, quota);
      if (limit === null) continue;
      const resolved = minLevelForQuota(quota, limit);
      expect(resolved).not.toBeNull();
      if (resolved) {
        expect(rankOf(resolved)).toBeLessThanOrEqual(rankOf(level.id));
      }
    }
    const top = LEVELS[LEVELS.length - 1];
    if (top) {
      const topLimit = quotaLimit(top.id, quota);
      // Au-delà du plafond du palier le plus élevé : aucun upsell possible.
      if (topLimit !== null) {
        expect(minLevelForQuota(quota, topLimit + 1)).toBeNull();
      }
    }
  });
});
