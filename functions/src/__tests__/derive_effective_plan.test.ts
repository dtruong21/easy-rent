/**
 * `deriveEffectivePlan` — la fonction la plus money-critical de FEAT-056
 * (plan §3.3 W3, §10.2). Elle est la SEULE définition du « palier servi »,
 * partagée par le webhook (temps réel) et par le cron (réconciliation) : c'est
 * ce partage qui garantit qu'aucun désaccord n'est possible entre les deux.
 *
 * L'échec qu'elle prévient a un coût direct : facturer Ultra en servant Pro,
 * ou verrouiller un abonné qui paie.
 */

import {describe, expect, it} from "vitest";

import {
  type EntitlementState,
  type EntitlementStates,
  deriveEffectivePlan,
  hasEntitlementStates,
  legacyStates,
  parseEntitlementStates,
} from "../entitlements/plan";

const NOW = Date.UTC(2026, 5, 15);
const IN_30D = NOW + 30 * 24 * 3600 * 1000;
const IN_60D = NOW + 60 * 24 * 3600 * 1000;
const AGO_1D = NOW - 24 * 3600 * 1000;

function st(over: Partial<EntitlementState> = {}): EntitlementState {
  return {
    active: true,
    expiresAtMs: IN_30D,
    willRenew: true,
    productId: "p",
    store: "web",
    lastEventAtMs: AGO_1D,
    ...over,
  };
}

describe("deriveEffectivePlan", () => {
  it("aucun palier → inactif, aucun niveau", () => {
    expect(deriveEffectivePlan({}, NOW)).toEqual({
      active: false,
      levelId: null,
      state: null,
    });
  });

  it("aucun palier ACTIF → inactif", () => {
    const states: EntitlementStates = {
      pro: st({active: false}),
      ultra: st({active: false}),
    };
    expect(deriveEffectivePlan(states, NOW).active).toBe(false);
  });

  it("un seul palier actif → ce palier", () => {
    const eff = deriveEffectivePlan({pro: st()}, NOW);
    expect(eff.active).toBe(true);
    expect(eff.levelId).toBe("pro");
    expect(eff.state?.expiresAtMs).toBe(IN_30D);
  });

  it("🔴 deux paliers actifs → rang MAXIMAL (W3)", () => {
    // Downgrade différé Apple/Google : le client garde Ultra jusqu'à la fin de
    // la période déjà payée, même si Pro est déjà actif pour la suivante.
    const states: EntitlementStates = {
      pro: st({expiresAtMs: IN_60D}),
      ultra: st({expiresAtMs: IN_30D}),
    };
    const eff = deriveEffectivePlan(states, NOW);
    expect(eff.levelId).toBe("ultra");
    // L'ordre d'insertion de la map ne doit rien changer.
    const reversed: EntitlementStates = {
      ultra: st({expiresAtMs: IN_30D}),
      pro: st({expiresAtMs: IN_60D}),
    };
    expect(deriveEffectivePlan(reversed, NOW).levelId).toBe("ultra");
  });

  it("les trois paliers actifs → ultra", () => {
    const states: EntitlementStates = {pro: st(), max: st(), ultra: st()};
    expect(deriveEffectivePlan(states, NOW).levelId).toBe("ultra");
  });

  it("actif mais ÉCHU → ignoré (le cron n'a pas encore nettoyé)", () => {
    const states: EntitlementStates = {
      pro: st(),
      ultra: st({expiresAtMs: AGO_1D}),
    };
    expect(deriveEffectivePlan(states, NOW).levelId).toBe("pro");
  });

  it("échéance EXACTEMENT à `now` → échu (borne stricte)", () => {
    expect(deriveEffectivePlan({pro: st({expiresAtMs: NOW})}, NOW).active).toBe(
      false,
    );
  });

  it("expiresAtMs null (pas d'échéance connue) → considéré actif", () => {
    const eff = deriveEffectivePlan({pro: st({expiresAtMs: null})}, NOW);
    expect(eff.active).toBe(true);
    expect(eff.levelId).toBe("pro");
  });

  it("l'état renvoyé est bien celui du palier effectif", () => {
    const states: EntitlementStates = {
      pro: st({store: "web", productId: "pro_monthly"}),
      ultra: st({store: "app_store", productId: "ultra_yearly"}),
    };
    const eff = deriveEffectivePlan(states, NOW);
    // Les champs pro* du doc reflètent CET état — pas celui du dernier event.
    expect(eff.state?.store).toBe("app_store");
    expect(eff.state?.productId).toBe("ultra_yearly");
  });
});

describe("legacyStates / parseEntitlementStates", () => {
  it("doc payant sans map → palier pro reconstitué depuis les champs pro*", () => {
    const states = legacyStates({
      proEntitlementActive: true,
      proExpiresAt: new Date(IN_30D),
      proWillRenew: true,
      proProductId: "pro_monthly",
      proStore: "web",
      proLastEventAtMs: AGO_1D,
    });
    expect(states.pro).toEqual({
      active: true,
      expiresAtMs: IN_30D,
      willRenew: true,
      productId: "pro_monthly",
      store: "web",
      lastEventAtMs: AGO_1D,
    });
    expect(deriveEffectivePlan(states, NOW).levelId).toBe("pro");
  });

  it("doc non payant sans map → aucun état", () => {
    expect(legacyStates({proEntitlementActive: false})).toEqual({});
    expect(legacyStates({})).toEqual({});
    expect(legacyStates(undefined)).toEqual({});
  });

  it("la map présente prime sur le repli legacy", () => {
    const landlord = {
      proEntitlementActive: true,
      proExpiresAt: new Date(IN_30D),
      entitlements: {
        ultra: {
          active: true,
          expiresAt: new Date(IN_60D),
          willRenew: true,
          productId: "ultra_yearly",
          store: "web",
          lastEventAtMs: 7,
        },
      },
    };
    expect(hasEntitlementStates(landlord)).toBe(true);
    const states = parseEntitlementStates(landlord);
    expect(states.pro).toBeUndefined();
    expect(deriveEffectivePlan(states, NOW).levelId).toBe("ultra");
  });

  it("un palier INCONNU stocké dans la map est ignoré (W5)", () => {
    // Un palier retiré de la table (ou écrit par erreur) ne doit jamais
    // accorder d'accès : la table est la seule autorité sur ce qui existe.
    const states = parseEntitlementStates({
      entitlements: {
        quantum: {active: true, expiresAt: new Date(IN_60D), lastEventAtMs: 1},
      },
    });
    expect(states).toEqual({});
    expect(deriveEffectivePlan(states, NOW).active).toBe(false);
  });

  it("une map vide ne retombe PAS sur le repli legacy", () => {
    // `entitlements: {}` est un état matérialisé — « aucun palier » — et non
    // une absence d'information. Y répondre par le repli legacy ressusciterait
    // un accès révoqué.
    const states = parseEntitlementStates({
      proEntitlementActive: true,
      proExpiresAt: new Date(IN_30D),
      entitlements: {},
    });
    expect(states).toEqual({});
  });
});
