import {beforeEach, describe, expect, it, vi} from "vitest";

import {levelForRcEntitlement, rcEntitlementIdFor} from "../entitlements/plan";
import {
  applyRevenueCatEvent,
  decideEntitlement,
  isAuthorizedWebhook,
  storeOf,
  type RcEvent,
} from "../http/revenuecat_webhook";

import {FakeFirestore, fakeAdminFirestoreHolder} from "./helpers/fake_firestore";

vi.mock("firebase-admin", async () => {
  const {makeFakeAdminModule} = await import("./helpers/fake_firestore");
  return makeFakeAdminModule();
});

let fakeDb: FakeFirestore;

/**
 * Entitlement RevenueCat du palier `pro`, ÉPINGLÉ ICI EN DUR.
 *
 * Un seul `l` — typo historique **load-bearing** : c'est la clé effective des
 * abonnés existants. La renommer (dashboard RC ou table) ferait passer tous
 * leurs events par `levelForRcEntitlement() → null → ignored` : plus aucune
 * expiration ni renouvellement appliqué, silencieusement. Le test
 * « la table connaît cet entitlement » ci-dessous est le garde-fou : il casse
 * bruyamment si quelqu'un « corrige » la faute de frappe.
 */
const PRO_RC_ENTITLEMENT_ID = "Bailan Pro";

const UID = "landlord-pro";
const NOW = Date.UTC(2026, 5, 15); // 2026-06-15
const IN_30D = NOW + 30 * 24 * 3600 * 1000;
const IN_60D = NOW + 60 * 24 * 3600 * 1000;
const AGO_1D = NOW - 24 * 3600 * 1000;

function seedFullLandlord(extra: Record<string, unknown> = {}) {
  fakeDb.seed(`landlords/${UID}`, {
    id: UID,
    landlordId: UID,
    isAnonymous: false,
    subscriptionTier: "free",
    deletedAt: null,
    ...extra,
  });
}

function evt(overrides: Partial<RcEvent> = {}): RcEvent {
  return {
    type: "INITIAL_PURCHASE",
    app_user_id: UID,
    product_id: "pro_monthly",
    entitlement_ids: [PRO_RC_ENTITLEMENT_ID],
    store: "APP_STORE",
    expiration_at_ms: IN_30D,
    event_timestamp_ms: NOW,
    ...overrides,
  };
}

beforeEach(() => {
  fakeDb = new FakeFirestore();
  fakeAdminFirestoreHolder.db = fakeDb;
});

describe("decideEntitlement", () => {
  it("events accordant renouvelables → actif + willRenew", () => {
    for (const t of [
      "INITIAL_PURCHASE",
      "RENEWAL",
      "UNCANCELLATION",
      "PRODUCT_CHANGE",
      "SUBSCRIPTION_EXTENDED",
    ]) {
      expect(decideEntitlement(t, IN_30D, NOW)).toEqual({
        active: true,
        willRenew: true,
      });
    }
  });

  it("NON_RENEWING_PURCHASE → actif, ne se renouvelle pas", () => {
    expect(decideEntitlement("NON_RENEWING_PURCHASE", null, NOW)).toEqual({
      active: true,
      willRenew: false,
    });
  });

  it("CANCELLATION → actif jusqu'à l'échéance, willRenew false", () => {
    expect(decideEntitlement("CANCELLATION", IN_30D, NOW)).toEqual({
      active: true,
      willRenew: false,
    });
    expect(decideEntitlement("CANCELLATION", AGO_1D, NOW)).toEqual({
      active: false,
      willRenew: false,
    });
  });

  it("BILLING_ISSUE → actif pendant la grâce", () => {
    expect(decideEntitlement("BILLING_ISSUE", IN_30D, NOW).active).toBe(true);
    expect(decideEntitlement("BILLING_ISSUE", AGO_1D, NOW).active).toBe(false);
  });

  it("EXPIRATION / SUBSCRIPTION_PAUSED → inactif", () => {
    expect(decideEntitlement("EXPIRATION", AGO_1D, NOW).active).toBe(false);
    expect(decideEntitlement("SUBSCRIPTION_PAUSED", IN_30D, NOW).active).toBe(false);
  });

  it("TRANSFER / type inconnu → null (no-op)", () => {
    expect(decideEntitlement("TRANSFER", IN_30D, NOW)).toBeNull();
    expect(decideEntitlement("WHATEVER", IN_30D, NOW)).toBeNull();
  });
});

describe("storeOf", () => {
  it("mappe les stores RevenueCat", () => {
    expect(storeOf("APP_STORE")).toBe("app_store");
    expect(storeOf("PLAY_STORE")).toBe("play_store");
    expect(storeOf("STRIPE")).toBe("web");
    expect(storeOf("RC_BILLING")).toBe("web");
    expect(storeOf("PROMOTIONAL")).toBe("promo");
    expect(storeOf(null)).toBeNull();
  });
});

describe("isAuthorizedWebhook", () => {
  it("accepte le bon secret, rejette le reste", () => {
    expect(isAuthorizedWebhook("s3cr3t", "s3cr3t")).toBe(true);
    expect(isAuthorizedWebhook("wrong", "s3cr3t")).toBe(false);
    expect(isAuthorizedWebhook("", "s3cr3t")).toBe(false);
    expect(isAuthorizedWebhook(undefined, "s3cr3t")).toBe(false);
    expect(isAuthorizedWebhook("s3cr3t", "")).toBe(false);
  });
});

describe("applyRevenueCatEvent", () => {
  it("INITIAL_PURCHASE pro → landlord passe PAID + champs pro*", async () => {
    seedFullLandlord();
    const outcome = await applyRevenueCatEvent(fakeDb, evt(), NOW);
    expect(outcome).toBe("applied");

    const doc = fakeDb.peek(`landlords/${UID}`);
    expect(doc?.subscriptionTier).toBe("paid");
    expect(doc?.proEntitlementActive).toBe(true);
    expect(doc?.proStore).toBe("app_store");
    expect(doc?.proProductId).toBe("pro_monthly");
    expect(doc?.proWillRenew).toBe(true);
    expect(doc?.proExpiresAt).toEqual(new Date(IN_30D));
    expect(doc?.proSince).toBeInstanceOf(Date); // serverTimestamp résolu
    expect(doc?.proLastEventAtMs).toBe(NOW);
  });

  it("EXPIRATION → landlord repasse FREE", async () => {
    seedFullLandlord({
      subscriptionTier: "paid",
      proEntitlementActive: true,
      proSince: new Date(AGO_1D),
      proLastEventAtMs: AGO_1D,
    });
    const outcome = await applyRevenueCatEvent(
      fakeDb,
      evt({type: "EXPIRATION", expiration_at_ms: AGO_1D, event_timestamp_ms: NOW}),
      NOW,
    );
    expect(outcome).toBe("applied");
    const doc = fakeDb.peek(`landlords/${UID}`);
    expect(doc?.subscriptionTier).toBe("free");
    expect(doc?.proEntitlementActive).toBe(false);
    // proSince conservé (audit).
    expect(doc?.proSince).toEqual(new Date(AGO_1D));
  });

  it("CANCELLATION avec échéance future → reste PAID, willRenew false", async () => {
    seedFullLandlord({subscriptionTier: "paid", proEntitlementActive: true});
    await applyRevenueCatEvent(
      fakeDb,
      evt({type: "CANCELLATION", event_timestamp_ms: NOW}),
      NOW,
    );
    const doc = fakeDb.peek(`landlords/${UID}`);
    expect(doc?.subscriptionTier).toBe("paid");
    expect(doc?.proWillRenew).toBe(false);
  });

  it("event d'un AUTRE entitlement → ignoré, tier inchangé", async () => {
    seedFullLandlord();
    const outcome = await applyRevenueCatEvent(
      fakeDb,
      evt({entitlement_ids: ["some_other_entitlement"]}),
      NOW,
    );
    expect(outcome).toBe("ignored");
    expect(fakeDb.peek(`landlords/${UID}`)?.subscriptionTier).toBe("free");
  });

  it("event TEST (config webhook) → ignoré", async () => {
    seedFullLandlord();
    expect(await applyRevenueCatEvent(fakeDb, evt({type: "TEST"}), NOW)).toBe(
      "ignored",
    );
  });

  it("app_user_id anonyme RevenueCat → ignoré", async () => {
    const outcome = await applyRevenueCatEvent(
      fakeDb,
      evt({app_user_id: "$RCAnonymousID:abc123"}),
      NOW,
    );
    expect(outcome).toBe("ignored");
  });

  it("landlord inexistant → no_landlord, rien écrit", async () => {
    const outcome = await applyRevenueCatEvent(fakeDb, evt(), NOW);
    expect(outcome).toBe("no_landlord");
    expect(fakeDb.peek(`landlords/${UID}`)).toBeUndefined();
  });

  it("landlord ANONYME → ignoré (un anon ne peut pas être payant)", async () => {
    seedFullLandlord({isAnonymous: true, subscriptionTier: "anonymous"});
    const outcome = await applyRevenueCatEvent(fakeDb, evt(), NOW);
    expect(outcome).toBe("ignored");
    expect(fakeDb.peek(`landlords/${UID}`)?.subscriptionTier).toBe("anonymous");
  });

  it("event antérieur au dernier appliqué → stale, pas d'écrasement", async () => {
    // Déjà expiré via un event à NOW ; un RENEWAL retardé (timestamp passé)
    // ne doit PAS re-basculer en paid.
    seedFullLandlord({
      subscriptionTier: "free",
      proEntitlementActive: false,
      proLastEventAtMs: NOW,
    });
    const outcome = await applyRevenueCatEvent(
      fakeDb,
      evt({type: "RENEWAL", event_timestamp_ms: AGO_1D}),
      NOW,
    );
    expect(outcome).toBe("stale");
    expect(fakeDb.peek(`landlords/${UID}`)?.subscriptionTier).toBe("free");
  });

  it("idempotent : rejouer le même event donne le même état", async () => {
    seedFullLandlord();
    await applyRevenueCatEvent(fakeDb, evt(), NOW);
    const after1 = {...fakeDb.peek(`landlords/${UID}`)};
    const outcome2 = await applyRevenueCatEvent(fakeDb, evt(), NOW);
    expect(outcome2).toBe("applied");
    const after2 = fakeDb.peek(`landlords/${UID}`);
    expect(after2?.subscriptionTier).toBe("paid");
    expect(after2?.proExpiresAt).toEqual(after1.proExpiresAt);
    expect(after2?.proLastEventAtMs).toBe(NOW);
  });
});

// ============================================================================
// FEAT-056 — multi-paliers. Les cas ci-dessus (palier unique) restent la
// référence de non-régression : un abonné actuel ne doit rien voir changer.
// ============================================================================

describe("résolution d'entitlement (W5)", () => {
  it("la table connaît l'entitlement historique — et lui seul", () => {
    // Garde-fou R4 : si ce test casse, quelqu'un a « corrigé » la typo
    // « Bailan » → tous les events des abonnés existants seraient ignorés.
    expect(levelForRcEntitlement(PRO_RC_ENTITLEMENT_ID)).toBe("pro");
    expect(rcEntitlementIdFor("pro")).toBe(PRO_RC_ENTITLEMENT_ID);
    expect(levelForRcEntitlement("Baillan Pro")).toBeNull();
    expect(levelForRcEntitlement("rc_test_entitlement")).toBeNull();
  });

  it("un entitlement inconnu n'accorde RIEN, même mélangé au nôtre", async () => {
    // L'event porte un entitlement étranger EN PLUS du nôtre : seul le palier
    // connu est touché, l'inconnu n'est jamais deviné ni normalisé.
    seedFullLandlord();
    const outcome = await applyRevenueCatEvent(
      fakeDb,
      evt({entitlement_ids: ["rc_test_entitlement", PRO_RC_ENTITLEMENT_ID]}),
      NOW,
    );
    expect(outcome).toBe("applied");
    const doc = fakeDb.peek(`landlords/${UID}`);
    expect(doc?.planLevel).toBe("pro");
    expect(Object.keys(doc?.entitlements as object)).toEqual(["pro"]);
  });

  it("un event portant UNIQUEMENT un entitlement inconnu → ignoré", async () => {
    seedFullLandlord({subscriptionTier: "paid", proEntitlementActive: true});
    // ⚠️ Ce décor doit rester une chaîne qui n'existera JAMAIS dans
    // `config/entitlements.json`. Il valait « Baillan Ultra » tant qu'Ultra
    // n'avait pas d'entitlement RevenueCat ; le jour où on lui en a attribué
    // un, le test s'est mis à échouer alors que le comportement visé — un
    // entitlement étranger ne révoque rien — n'avait pas bougé.
    const outcome = await applyRevenueCatEvent(
      fakeDb,
      evt({
        type: "EXPIRATION",
        entitlement_ids: ["not-a-baillan-entitlement"],
      }),
      NOW,
    );
    expect(outcome).toBe("ignored");
    // L'abonné garde son accès : un entitlement étranger ne révoque rien.
    expect(fakeDb.peek(`landlords/${UID}`)?.subscriptionTier).toBe("paid");
  });
});

describe("map d'état par palier", () => {
  /** État brut tel que stocké dans `landlords/{uid}.entitlements.<level>`. */
  function state(over: Record<string, unknown> = {}) {
    return {
      active: true,
      expiresAt: new Date(IN_30D),
      willRenew: true,
      productId: "p",
      store: "web",
      lastEventAtMs: NOW,
      ...over,
    };
  }

  it("un event matérialise la map et pose planLevel", async () => {
    seedFullLandlord();
    await applyRevenueCatEvent(fakeDb, evt(), NOW);
    const doc = fakeDb.peek(`landlords/${UID}`);
    expect(doc?.planLevel).toBe("pro");
    const states = doc?.entitlements as Record<string, Record<string, unknown>>;
    expect(states.pro).toMatchObject({
      active: true,
      willRenew: true,
      productId: "pro_monthly",
      store: "app_store",
      lastEventAtMs: NOW,
    });
    expect(states.pro?.expiresAt).toEqual(new Date(IN_30D));
  });

  it("EXPIRATION du dernier palier → free, planLevel null, proSince gardé", async () => {
    seedFullLandlord({
      subscriptionTier: "paid",
      proEntitlementActive: true,
      planLevel: "pro",
      proSince: new Date(AGO_1D),
      entitlements: {pro: state({lastEventAtMs: AGO_1D})},
    });
    const outcome = await applyRevenueCatEvent(
      fakeDb,
      evt({type: "EXPIRATION", expiration_at_ms: AGO_1D}),
      NOW,
    );
    expect(outcome).toBe("applied");
    const doc = fakeDb.peek(`landlords/${UID}`);
    expect(doc?.subscriptionTier).toBe("free");
    expect(doc?.planLevel).toBeNull();
    expect(doc?.proEntitlementActive).toBe(false);
    expect(doc?.proSince).toEqual(new Date(AGO_1D)); // W6
  });

  it("🔴 EXPIRATION Pro sur un compte ULTRA actif → reste ultra (W1)", async () => {
    // Chevauchement de downgrade différé : l'event ne mentionne que Pro. S'il
    // touchait l'état global, on verrouillerait un client qui a payé Ultra
    // jusqu'à la fin de sa période.
    seedFullLandlord({
      subscriptionTier: "paid",
      proEntitlementActive: true,
      planLevel: "ultra",
      entitlements: {
        pro: state({lastEventAtMs: AGO_1D}),
        ultra: state({expiresAt: new Date(IN_60D), lastEventAtMs: AGO_1D}),
      },
    });

    const outcome = await applyRevenueCatEvent(
      fakeDb,
      evt({type: "EXPIRATION", expiration_at_ms: AGO_1D}),
      NOW,
    );

    expect(outcome).toBe("applied");
    const doc = fakeDb.peek(`landlords/${UID}`);
    expect(doc?.subscriptionTier).toBe("paid");
    expect(doc?.planLevel).toBe("ultra"); // W3 : max(rang) parmi les actifs
    const states = doc?.entitlements as Record<string, Record<string, unknown>>;
    expect(states.pro?.active).toBe(false); // seul Pro a bougé
    expect(states.ultra?.active).toBe(true);
    // Les champs pro* reflètent le palier EFFECTIF, pas l'event reçu.
    expect(doc?.proExpiresAt).toEqual(new Date(IN_60D));
    expect(doc?.proEntitlementActive).toBe(true);
  });

  it("🔴 arrivée DÉSORDONNÉE sur deux paliers → garde d'ordre par palier (W2)", async () => {
    // Ultra acheté à T2 (déjà appliqué), puis l'EXPIRATION de Pro datée T1
    // arrive en retard. Une garde d'ordre GLOBALE la jetterait comme stale
    // alors qu'elle concerne un autre palier — et Pro resterait actif à tort.
    const T0 = NOW - 3 * 3600 * 1000;
    const T1 = NOW - 2 * 3600 * 1000;
    const T2 = NOW - 1 * 3600 * 1000;
    seedFullLandlord({
      subscriptionTier: "paid",
      proEntitlementActive: true,
      planLevel: "ultra",
      proLastEventAtMs: T2,
      entitlements: {
        pro: state({lastEventAtMs: T0}),
        ultra: state({expiresAt: new Date(IN_60D), lastEventAtMs: T2}),
      },
    });

    const outcome = await applyRevenueCatEvent(
      fakeDb,
      evt({
        type: "EXPIRATION",
        expiration_at_ms: AGO_1D,
        event_timestamp_ms: T1,
      }),
      NOW,
    );

    expect(outcome).toBe("applied");
    const doc = fakeDb.peek(`landlords/${UID}`);
    expect(doc?.planLevel).toBe("ultra");
    const states = doc?.entitlements as Record<string, Record<string, unknown>>;
    expect(states.pro?.active).toBe(false);
    expect(states.ultra?.active).toBe(true);
    // Le repère global ne recule jamais.
    expect(doc?.proLastEventAtMs).toBe(T2);
  });

  it("event stale SUR SON PALIER → aucune écriture", async () => {
    seedFullLandlord({
      subscriptionTier: "paid",
      proEntitlementActive: true,
      planLevel: "pro",
      entitlements: {pro: state({lastEventAtMs: NOW})},
    });
    const outcome = await applyRevenueCatEvent(
      fakeDb,
      evt({type: "EXPIRATION", event_timestamp_ms: AGO_1D}),
      NOW,
    );
    expect(outcome).toBe("stale");
    expect(fakeDb.peek(`landlords/${UID}`)?.subscriptionTier).toBe("paid");
  });

  it("un palier actif mais ÉCHU ne compte pas dans la dérivation", async () => {
    seedFullLandlord({
      subscriptionTier: "paid",
      proEntitlementActive: true,
      planLevel: "ultra",
      entitlements: {
        // Ultra jamais nettoyé par le cron : marqué actif, mais échu.
        ultra: state({expiresAt: new Date(AGO_1D), lastEventAtMs: AGO_1D}),
      },
    });
    const outcome = await applyRevenueCatEvent(
      fakeDb,
      evt({type: "RENEWAL", expiration_at_ms: IN_30D}),
      NOW,
    );
    expect(outcome).toBe("applied");
    const doc = fakeDb.peek(`landlords/${UID}`);
    expect(doc?.planLevel).toBe("pro"); // ultra échu → ignoré
    expect(doc?.subscriptionTier).toBe("paid");
  });
});

describe("🔴 compte legacy (aucune map `entitlements`)", () => {
  it("un RENEWAL matérialise la map sans rétrograder l'abonné", async () => {
    // Cas le plus fréquent en production : doc payant d'avant FEAT-056.
    seedFullLandlord({
      subscriptionTier: "paid",
      proEntitlementActive: true,
      proWillRenew: true,
      proExpiresAt: new Date(IN_30D),
      proStore: "web",
      proProductId: "pro_monthly",
      proSince: new Date(AGO_1D),
      proLastEventAtMs: AGO_1D,
    });

    const outcome = await applyRevenueCatEvent(
      fakeDb,
      evt({type: "RENEWAL", expiration_at_ms: IN_60D}),
      NOW,
    );

    expect(outcome).toBe("applied");
    const doc = fakeDb.peek(`landlords/${UID}`);
    expect(doc?.subscriptionTier).toBe("paid"); // jamais de rétrogradation
    expect(doc?.planLevel).toBe("pro"); // grandfathering (I3)
    const states = doc?.entitlements as Record<string, Record<string, unknown>>;
    expect(states.pro?.active).toBe(true);
    expect(states.pro?.expiresAt).toEqual(new Date(IN_60D));
    expect(doc?.proSince).toEqual(new Date(AGO_1D)); // W6
  });

  it("la garde d'ordre globale tient tant que la map n'existe pas", async () => {
    // Sans repli sur `proLastEventAtMs`, un event ancien serait ré-appliqué
    // (le palier n'ayant encore aucun `lastEventAtMs` propre) et pourrait
    // ressusciter un abonnement expiré.
    seedFullLandlord({
      subscriptionTier: "free",
      proEntitlementActive: false,
      proLastEventAtMs: NOW,
    });
    const outcome = await applyRevenueCatEvent(
      fakeDb,
      evt({type: "RENEWAL", event_timestamp_ms: AGO_1D}),
      NOW,
    );
    expect(outcome).toBe("stale");
    expect(fakeDb.peek(`landlords/${UID}`)?.subscriptionTier).toBe("free");
  });

  it("un compte legacy NON payant ne se voit rien matérialiser à tort", async () => {
    seedFullLandlord({subscriptionTier: "free", proEntitlementActive: false});
    await applyRevenueCatEvent(
      fakeDb,
      evt({type: "EXPIRATION", expiration_at_ms: AGO_1D}),
      NOW,
    );
    const doc = fakeDb.peek(`landlords/${UID}`);
    expect(doc?.subscriptionTier).toBe("free");
    expect(doc?.planLevel).toBeNull();
  });
});
