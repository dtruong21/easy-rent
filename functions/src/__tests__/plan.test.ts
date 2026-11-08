/**
 * Résolution du palier effectif et lecture des plafonds (FEAT-056, §10.2).
 *
 * Deux propriétés valent la totalité de ce fichier :
 *   - un compte payant d'AVANT FEAT-056 (pas de `planLevel`) se dérive en `pro`
 *     et n'est JAMAIS traité comme non payant (invariant I3) — depuis PR-7 il
 *     hérite donc des plafonds Pro, qui sont finis, et non plus d'un accès
 *     illimité ;
 *   - un `planLevel` que le serveur ne connaît pas ne doit JAMAIS faire
 *     retomber un abonné en `anonymous` (invariant I4).
 */

import {describe, expect, it} from "vitest";

import {errorCodeFor, quotaLimit, resolvePlan} from "../entitlements/plan";

describe("resolvePlan", () => {
  it("tier absent / illisible → anonymous (défaut serveur fail-closed)", () => {
    expect(resolvePlan(undefined)).toEqual({
      tier: "anonymous",
      levelId: null,
      key: "anonymous",
    });
    expect(resolvePlan({})).toEqual({
      tier: "anonymous",
      levelId: null,
      key: "anonymous",
    });
    expect(resolvePlan({subscriptionTier: 42})).toEqual({
      tier: "anonymous",
      levelId: null,
      key: "anonymous",
    });
    expect(resolvePlan({subscriptionTier: "premium"})).toEqual({
      tier: "anonymous",
      levelId: null,
      key: "anonymous",
    });
  });

  it("free → clé free, aucun palier commercial (I1)", () => {
    expect(resolvePlan({subscriptionTier: "free"})).toEqual({
      tier: "free",
      levelId: null,
      key: "free",
    });
  });

  it("planLevel est IGNORÉ tant que le compte n'est pas payant (I1)", () => {
    // Défense en profondeur : les rules gèlent déjà `planLevel` côté client,
    // mais un doc incohérent ne doit pas offrir Ultra à un compte free.
    expect(resolvePlan({subscriptionTier: "free", planLevel: "ultra"})).toEqual({
      tier: "free",
      levelId: null,
      key: "free",
    });
    expect(
      resolvePlan({subscriptionTier: "anonymous", planLevel: "ultra"}),
    ).toEqual({tier: "anonymous", levelId: null, key: "anonymous"});
  });

  it("paid SANS planLevel → pro (I3 : abonnés d'avant FEAT-056)", () => {
    expect(resolvePlan({subscriptionTier: "paid"})).toEqual({
      tier: "paid",
      levelId: "pro",
      key: "pro",
    });
    expect(resolvePlan({subscriptionTier: "paid", planLevel: null})).toEqual({
      tier: "paid",
      levelId: "pro",
      key: "pro",
    });
  });

  it("paid avec planLevel connu → ce palier", () => {
    for (const level of ["pro", "max", "ultra"] as const) {
      expect(resolvePlan({subscriptionTier: "paid", planLevel: level})).toEqual({
        tier: "paid",
        levelId: level,
        key: level,
      });
    }
  });

  it("paid avec planLevel INCONNU → pro, jamais anonymous (I4)", () => {
    // Le pire échec possible serait de verrouiller le client qui paie le plus
    // cher. On retombe sur le plus bas palier PAYANT, pas sur `anonymous`.
    const plan = resolvePlan({subscriptionTier: "paid", planLevel: "quantum"});
    expect(plan.tier).toBe("paid");
    expect(plan.levelId).toBe("pro");
    expect(plan.key).toBe("pro");
  });
});

describe("quotaLimit", () => {
  const anonymous = resolvePlan({subscriptionTier: "anonymous"});
  const free = resolvePlan({subscriptionTier: "free"});
  const legacyPaid = resolvePlan({subscriptionTier: "paid"});

  it("anonymous : aucun accès au registre", () => {
    expect(quotaLimit(anonymous, "properties")).toBe(0);
    expect(quotaLimit(anonymous, "tenants")).toBe(0);
    expect(quotaLimit(anonymous, "activeLeases")).toBe(0);
    expect(quotaLimit(anonymous, "documents")).toBe(0);
  });

  it("free : plafonds historiques inchangés (non-régression du freemium)", () => {
    expect(quotaLimit(free, "properties")).toBe(2);
    expect(quotaLimit(free, "tenants")).toBe(3);
    expect(quotaLimit(free, "activeLeases")).toBe(2);
    expect(quotaLimit(free, "documents")).toBe(10);
    expect(quotaLimit(free, "scenarios")).toBe(3);
  });

  it("anonymous : 1 scénario (simulateur en essai)", () => {
    expect(quotaLimit(anonymous, "scenarios")).toBe(1);
  });

  it("un compte payant legacy est servi aux plafonds Pro, désormais FINIS", () => {
    // Arbitrage propriétaire (PR-7) : un doc `paid` sans `planLevel` se dérive
    // en `pro` (I3) et hérite donc de la grille Pro, qui n'est plus illimitée.
    // L'ancienne offre unique l'était ; on ne conserve PAS de palier dérivé
    // « legacy illimité », l'ensemble concerné étant vide en production
    // (SUBSCRIPTIONS_ENABLED=false, aucun abonné réel n'a jamais payé).
    expect(quotaLimit(legacyPaid, "properties")).toBe(5);
    expect(quotaLimit(legacyPaid, "tenants")).toBe(8);
    expect(quotaLimit(legacyPaid, "activeLeases")).toBe(5);
    expect(quotaLimit(legacyPaid, "documents")).toBe(50);
    expect(quotaLimit(legacyPaid, "scenarios")).toBe(15);
  });

  it("le plafond se lit sur le PALIER, pas sur la classe d'accès", () => {
    // Les trois paliers payants portent des plafonds DIFFÉRENTS : c'est la
    // preuve directe que chacun est interrogé par SA propre clé — un gating
    // indexé sur `subscriptionTier` renverrait trois fois la même valeur.
    const keys = (["pro", "max", "ultra"] as const).map((level) =>
      resolvePlan({subscriptionTier: "paid", planLevel: level}).key,
    );
    expect(keys).toEqual(["pro", "max", "ultra"]);

    const plan = (level: "pro" | "max" | "ultra") =>
      resolvePlan({subscriptionTier: "paid", planLevel: level});
    expect(
      (["pro", "max", "ultra"] as const).map((l) =>
        quotaLimit(plan(l), "properties"),
      ),
    ).toEqual([5, 15, null]);
    expect(
      (["pro", "max", "ultra"] as const).map((l) =>
        quotaLimit(plan(l), "tenants"),
      ),
    ).toEqual([8, 20, null]);
    expect(
      (["pro", "max", "ultra"] as const).map((l) =>
        quotaLimit(plan(l), "activeLeases"),
      ),
    ).toEqual([5, 15, null]);
    expect(
      (["pro", "max", "ultra"] as const).map((l) =>
        quotaLimit(plan(l), "documents"),
      ),
    ).toEqual([50, 150, null]);
    expect(
      (["pro", "max", "ultra"] as const).map((l) =>
        quotaLimit(plan(l), "scenarios"),
      ),
    ).toEqual([15, 30, null]);
  });

  it("documentMaxBytes est un quota de TAILLE, jamais un compteur", () => {
    // Unité `bytes` (cf. `unit` dans la table) : ne jamais comparer ni
    // additionner ces valeurs avec les quotas de comptage ci-dessus.
    const plan = (level: "pro" | "max" | "ultra") =>
      resolvePlan({subscriptionTier: "paid", planLevel: level});
    expect(quotaLimit(free, "documentMaxBytes")).toBe(10 * 1024 * 1024);
    expect(quotaLimit(plan("pro"), "documentMaxBytes")).toBe(10 * 1024 * 1024);
    expect(quotaLimit(plan("max"), "documentMaxBytes")).toBe(25 * 1024 * 1024);
    expect(quotaLimit(plan("ultra"), "documentMaxBytes")).toBe(50 * 1024 * 1024);
    // Un abonné legacy est servi comme Pro ici aussi.
    expect(quotaLimit(legacyPaid, "documentMaxBytes")).toBe(10 * 1024 * 1024);
  });
});

describe("errorCodeFor", () => {
  it("les codes d'erreur du contrat client sont figés par la table", () => {
    // Ces chaînes sont mappées côté Flutter : les casser casse l'upsell.
    expect(errorCodeFor("properties")).toBe("property_limit_reached");
    expect(errorCodeFor("tenants")).toBe("tenant_limit_reached");
    expect(errorCodeFor("activeLeases")).toBe("lease_limit_reached");
    expect(errorCodeFor("documents")).toBe("document_limit_reached");
    expect(errorCodeFor("documentMaxBytes")).toBe("file_too_large");
  });
});
