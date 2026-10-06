/**
 * Filet de réconciliation des entitlements (FEAT-044, étendu multi-paliers par
 * FEAT-056 §7 / §10.2).
 *
 * Deux familles de cas :
 *   - non-régression : expiration confirmée → `free`, renouvellement manqué →
 *     `renewed`, et surtout **jamais de `free → paid` par ce chemin** ;
 *   - nouveauté FEAT-056 : un `PRODUCT_CHANGE` manqué laisse une échéance dans
 *     le futur, donc invisible pour l'ancien filtre. Le cron doit corriger le
 *     PALIER d'un compte déjà payant, dans les deux sens.
 */

import {Timestamp} from "firebase-admin/firestore";
import {afterEach, beforeEach, describe, expect, it, vi} from "vitest";

import {rcEntitlementIdFor} from "../entitlements/plan";
import {
  entitlementStatesFromSubscriber,
  reconcileExpiredEntitlements,
  reconcileLandlord,
  runReconcileEntitlements,
  type EntitlementStatesFetcher,
} from "../scheduled/reconcile_entitlements";
import {SANDBOX_ALLOWLIST_DOC} from "../utils/sandbox_allowlist";

import {FakeFirestore, fakeAdminFirestoreHolder} from "./helpers/fake_firestore";

vi.mock("firebase-admin", async () => {
  const {makeFakeAdminModule} = await import("./helpers/fake_firestore");
  return makeFakeAdminModule();
});

let fakeDb: FakeFirestore;

const NOW = Date.UTC(2026, 5, 15);
const IN_30D = NOW + 30 * 24 * 3600 * 1000;
const IN_60D = NOW + 60 * 24 * 3600 * 1000;
const AGO_1D = NOW - 24 * 3600 * 1000;

/** État brut d'un palier tel que stocké dans la map `entitlements`. */
function state(over: Record<string, unknown> = {}) {
  return {
    active: true,
    expiresAt: new Date(IN_30D),
    willRenew: true,
    productId: "pro_monthly",
    store: "web",
    lastEventAtMs: AGO_1D,
    ...over,
  };
}

/**
 * Abonné actif. Sans `entitlements`, c'est exactement la forme d'un doc
 * d'AVANT FEAT-056 — le cas le plus fréquent en production.
 */
function seedActivePro(
  uid: string,
  expiresMs: number,
  over: Record<string, unknown> = {},
) {
  fakeDb.seed(`landlords/${uid}`, {
    id: uid,
    landlordId: uid,
    isAnonymous: false,
    subscriptionTier: "paid",
    proEntitlementActive: true,
    proWillRenew: true,
    proExpiresAt: new Date(expiresMs),
    deletedAt: null,
    ...over,
  });
}

beforeEach(() => {
  fakeDb = new FakeFirestore();
  fakeAdminFirestoreHolder.db = fakeDb;
});

describe("reconcileLandlord — non-régression palier unique", () => {
  it("RevenueCat ne montre plus aucun entitlement → downgrade en free", async () => {
    seedActivePro("u1", AGO_1D);
    expect(await reconcileLandlord(fakeDb, "u1", {}, NOW)).toBe(
      "downgraded_free",
    );
    const doc = fakeDb.peek("landlords/u1");
    expect(doc?.subscriptionTier).toBe("free");
    expect(doc?.proEntitlementActive).toBe(false);
    expect(doc?.proWillRenew).toBe(false);
    expect(doc?.planLevel).toBeNull();
  });

  it("RevenueCat montre une échéance passée → downgrade", async () => {
    seedActivePro("u1", AGO_1D);
    expect(
      await reconcileLandlord(fakeDb, "u1", {pro: {expiresMs: AGO_1D}}, NOW),
    ).toBe("downgraded_free");
    expect(fakeDb.peek("landlords/u1")?.subscriptionTier).toBe("free");
  });

  it("échéance future (renouvellement manqué) → renewed, reste paid", async () => {
    seedActivePro("u1", AGO_1D);
    expect(
      await reconcileLandlord(fakeDb, "u1", {pro: {expiresMs: IN_30D}}, NOW),
    ).toBe("renewed");
    const doc = fakeDb.peek("landlords/u1");
    expect(doc?.subscriptionTier).toBe("paid");
    expect(doc?.planLevel).toBe("pro");
    expect(doc?.proExpiresAt).toEqual(Timestamp.fromMillis(IN_30D));
  });

  it("rien n'a bougé → unchanged", async () => {
    seedActivePro("u1", IN_30D);
    expect(
      await reconcileLandlord(fakeDb, "u1", {pro: {expiresMs: IN_30D}}, NOW),
    ).toBe("unchanged");
    expect(fakeDb.peek("landlords/u1")?.subscriptionTier).toBe("paid");
  });

  it("🔴 compte NON actif + RevenueCat actif → unchanged, AUCUNE écriture", async () => {
    // Invariant de sécurité : aucun chemin automatique free → paid hors
    // webhook. Un cron qui pourrait promouvoir accorderait un accès payant
    // sans qu'aucun paiement ne l'ait déclenché.
    fakeDb.seed("landlords/u1", {
      id: "u1",
      subscriptionTier: "free",
      proEntitlementActive: false,
    });
    expect(
      await reconcileLandlord(fakeDb, "u1", {ultra: {expiresMs: IN_60D}}, NOW),
    ).toBe("unchanged");
    const doc = fakeDb.peek("landlords/u1");
    expect(doc?.subscriptionTier).toBe("free");
    expect(doc?.planLevel).toBeUndefined();
    expect(doc?.entitlements).toBeUndefined();
  });
});

describe("reconcileLandlord — correction de palier (FEAT-056)", () => {
  it("🔴 paid/pro alors que RevenueCat dit ultra → level_changed (montée)", async () => {
    // `PRODUCT_CHANGE` manqué : l'échéance reste dans le futur, donc l'ancien
    // filtre « échéance dépassée » ne voyait rien. On facturait Ultra en
    // servant Pro.
    seedActivePro("u1", IN_30D, {
      planLevel: "pro",
      entitlements: {pro: state()},
    });

    expect(
      await reconcileLandlord(fakeDb, "u1", {ultra: {expiresMs: IN_60D}}, NOW),
    ).toBe("level_changed");

    const doc = fakeDb.peek("landlords/u1");
    expect(doc?.subscriptionTier).toBe("paid");
    expect(doc?.planLevel).toBe("ultra");
    const states = doc?.entitlements as Record<string, Record<string, unknown>>;
    expect(states.pro?.active).toBe(false);
    expect(states.ultra?.active).toBe(true);
  });

  it("🔴 paid/ultra alors que RevenueCat ne montre que pro → level_changed, PAS free", async () => {
    seedActivePro("u1", IN_60D, {
      planLevel: "ultra",
      entitlements: {
        pro: state({active: false}),
        ultra: state({expiresAt: new Date(IN_60D)}),
      },
    });

    expect(
      await reconcileLandlord(fakeDb, "u1", {pro: {expiresMs: IN_30D}}, NOW),
    ).toBe("level_changed");

    const doc = fakeDb.peek("landlords/u1");
    expect(doc?.subscriptionTier).toBe("paid"); // surtout pas `free`
    expect(doc?.planLevel).toBe("pro");
    expect(doc?.proExpiresAt).toEqual(Timestamp.fromMillis(IN_30D));
  });

  it("chevauchement : deux paliers actifs → le rang le plus élevé gagne", async () => {
    seedActivePro("u1", IN_30D, {
      planLevel: "pro",
      entitlements: {pro: state()},
    });

    expect(
      await reconcileLandlord(
        fakeDb,
        "u1",
        {pro: {expiresMs: IN_30D}, ultra: {expiresMs: IN_60D}},
        NOW,
      ),
    ).toBe("level_changed");

    const doc = fakeDb.peek("landlords/u1");
    expect(doc?.planLevel).toBe("ultra");
    const states = doc?.entitlements as Record<string, Record<string, unknown>>;
    expect(states.pro?.active).toBe(true); // le palier bas reste actif
    expect(states.ultra?.active).toBe(true);
  });

  it("les métadonnées absentes de l'API REST sont conservées", async () => {
    // L'API subscriber ne renvoie ni product_id ni store : les écraser
    // perdrait l'information de support (« abonné via l'App Store ? »).
    seedActivePro("u1", AGO_1D, {
      planLevel: "pro",
      entitlements: {
        pro: state({
          store: "app_store",
          productId: "pro_yearly",
          lastEventAtMs: 42,
        }),
      },
    });

    await reconcileLandlord(fakeDb, "u1", {pro: {expiresMs: IN_30D}}, NOW);

    const states = fakeDb.peek("landlords/u1")?.entitlements as Record<
      string,
      Record<string, unknown>
    >;
    expect(states.pro?.store).toBe("app_store");
    expect(states.pro?.productId).toBe("pro_yearly");
    expect(states.pro?.lastEventAtMs).toBe(42);
  });

  it("🔴 compte legacy sans map : réconcilié comme pro, sans perte d'accès", async () => {
    seedActivePro("legacy", AGO_1D, {proStore: "web"});
    expect(
      await reconcileLandlord(fakeDb, "legacy", {pro: {expiresMs: IN_30D}}, NOW),
    ).toBe("renewed");
    const doc = fakeDb.peek("landlords/legacy");
    expect(doc?.subscriptionTier).toBe("paid");
    expect(doc?.planLevel).toBe("pro");
    const states = doc?.entitlements as Record<string, Record<string, unknown>>;
    expect(states.pro?.active).toBe(true);
    expect(states.pro?.store).toBe("web"); // repris des champs pro* legacy
  });
});

describe("reconcileExpiredEntitlements", () => {
  it("réconcilie TOUS les actifs, échéance future comprise", async () => {
    // FEAT-056 : le filtre « ne traiter que les échéances dépassées » est
    // supprimé — c'était le seul moyen d'attraper un PRODUCT_CHANGE manqué.
    seedActivePro("expired-gone", AGO_1D);
    seedActivePro("expired-renewed", AGO_1D);
    seedActivePro("level-drift", IN_30D, {
      planLevel: "pro",
      entitlements: {pro: state()},
    });

    const fetcher: EntitlementStatesFetcher = (uid) => {
      if (uid === "expired-gone") return Promise.resolve({});
      if (uid === "expired-renewed") {
        return Promise.resolve({pro: {expiresMs: IN_30D}});
      }
      return Promise.resolve({ultra: {expiresMs: IN_60D}});
    };

    const res = await reconcileExpiredEntitlements(fakeDb, fetcher, NOW);
    expect(res).toEqual({
      checked: 3,
      downgradedFree: 1,
      levelChanged: 1,
      renewed: 1,
      failed: 0,
    });

    expect(fakeDb.peek("landlords/expired-gone")?.subscriptionTier).toBe("free");
    expect(fakeDb.peek("landlords/expired-renewed")?.subscriptionTier).toBe(
      "paid",
    );
    expect(fakeDb.peek("landlords/level-drift")?.planLevel).toBe("ultra");
  });

  it("un échec de fetch est compté sans bloquer les autres", async () => {
    seedActivePro("ok", AGO_1D);
    seedActivePro("boom", AGO_1D);
    const fetcher: EntitlementStatesFetcher = (uid) => {
      if (uid === "boom") return Promise.reject(new Error("RevenueCat API 500"));
      return Promise.resolve({});
    };
    const res = await reconcileExpiredEntitlements(fakeDb, fetcher, NOW);
    expect(res.failed).toBe(1);
    expect(res.downgradedFree).toBe(1);
    expect(fakeDb.peek("landlords/ok")?.subscriptionTier).toBe("free");
    // 'boom' reste inchangé → sera retenté au prochain run.
    expect(fakeDb.peek("landlords/boom")?.subscriptionTier).toBe("paid");
  });
});

// OWASP-01 — le cron ne doit ni accorder, ni prolonger, ni monter de palier à
// partir d'un achat SANDBOX. L'API REST RevenueCat mélange achats prod et
// sandbox pour un même App User ID : `subscriptions[<produit>].is_sandbox`
// est le seul marqueur. Le cron n'opère que sur la base `(default)` — une
// entrée sandbox n'a rien à y faire.
describe("entitlementStatesFromSubscriber — achats sandbox ignorés (OWASP-01)", () => {
  const PRO_ID = rcEntitlementIdFor("pro") as string;
  const ULTRA_ID = rcEntitlementIdFor("ultra") as string;
  const iso = (ms: number) => new Date(ms).toISOString();

  it("entitlement adossé à un achat PRODUCTION → retenu", () => {
    const states = entitlementStatesFromSubscriber({
      entitlements: {
        [PRO_ID]: {expires_date: iso(IN_30D), product_identifier: "pro_monthly"},
      },
      subscriptions: {pro_monthly: {is_sandbox: false}},
    });
    expect(states).toEqual({pro: {expiresMs: IN_30D}});
  });

  it("entitlement adossé à un achat SANDBOX → masqué, sans échéance (jamais accordé/prolongé)", () => {
    const states = entitlementStatesFromSubscriber({
      entitlements: {
        [PRO_ID]: {expires_date: iso(IN_60D), product_identifier: "pro_monthly"},
      },
      subscriptions: {pro_monthly: {is_sandbox: true}},
    });
    expect(states).toEqual({pro: {expiresMs: null, sandboxShadowed: true}});
  });

  it("prod + sandbox sur deux paliers → seul le palier prod est retenu", () => {
    const states = entitlementStatesFromSubscriber({
      entitlements: {
        [PRO_ID]: {expires_date: iso(IN_30D), product_identifier: "pro_monthly"},
        [ULTRA_ID]: {
          expires_date: iso(IN_60D),
          product_identifier: "ultra_monthly",
        },
      },
      subscriptions: {
        pro_monthly: {is_sandbox: false},
        ultra_monthly: {is_sandbox: true},
      },
    });
    expect(states).toEqual({
      pro: {expiresMs: IN_30D},
      ultra: {expiresMs: null, sandboxShadowed: true},
    });
  });

  it("produit absent de `subscriptions` → traité comme prod (aucune rétrogradation à l'aveugle)", () => {
    const states = entitlementStatesFromSubscriber({
      entitlements: {
        [PRO_ID]: {expires_date: iso(IN_30D), product_identifier: "pro_monthly"},
      },
    });
    expect(states).toEqual({pro: {expiresMs: IN_30D}});
  });

  it("entitlement étranger ou sans échéance → ignoré (inchangé)", () => {
    const states = entitlementStatesFromSubscriber({
      entitlements: {
        "Unknown Entitlement": {expires_date: iso(IN_30D)},
        [PRO_ID]: {expires_date: null},
      },
    });
    expect(states).toEqual({});
  });

  it("subscriber absent → aucun état", () => {
    expect(entitlementStatesFromSubscriber(undefined)).toEqual({});
    expect(entitlementStatesFromSubscriber({})).toEqual({});
  });

  it("★ bout en bout : un Ultra sandbox ne monte pas un compte prod Pro et ne prolonge rien", async () => {
    seedActivePro("prod-pro", IN_30D);
    const body = {
      entitlements: {
        [PRO_ID]: {expires_date: iso(IN_30D), product_identifier: "pro_monthly"},
        [ULTRA_ID]: {
          expires_date: iso(IN_60D),
          product_identifier: "ultra_monthly",
        },
      },
      subscriptions: {
        pro_monthly: {is_sandbox: false},
        ultra_monthly: {is_sandbox: true},
      },
    };
    const res = await reconcileExpiredEntitlements(
      fakeDb,
      () => Promise.resolve(entitlementStatesFromSubscriber(body)),
      NOW,
    );
    expect(res.levelChanged).toBe(0);
    const doc = fakeDb.peek("landlords/prod-pro");
    expect(doc?.subscriptionTier).toBe("paid");
    expect(doc?.planLevel).not.toBe("ultra");
  });
});

// #209 — RevenueCat ne rapporte qu'UN produit par entitlement (l'échéance la
// plus lointaine) : un achat sandbox plus long masque un vrai abonnement prod.
// Avant : le palier disparaissait de la réponse et le compte payant était
// rétrogradé chaque nuit. Désormais : l'état enregistré est gardé.
describe("reconcile — palier prod masqué par un achat sandbox (#209)", () => {
  const PRO_ID = rcEntitlementIdFor("pro") as string;
  const iso = (ms: number) => new Date(ms).toISOString();
  const shadowedBody = {
    entitlements: {
      [PRO_ID]: {expires_date: iso(IN_60D), product_identifier: "pro_sandbox"},
    },
    subscriptions: {pro_sandbox: {is_sandbox: true}},
  };

  it("compte prod payant encore dans sa période → reste payant, échéance inchangée", async () => {
    seedActivePro("prod-pro", IN_30D);

    const res = await reconcileExpiredEntitlements(
      fakeDb,
      () => Promise.resolve(entitlementStatesFromSubscriber(shadowedBody)),
      NOW,
    );

    expect(res.downgradedFree).toBe(0);
    const doc = fakeDb.peek("landlords/prod-pro");
    expect(doc?.subscriptionTier).toBe("paid");
    expect(doc?.proEntitlementActive).toBe(true);
    // Jamais prolongé jusqu'à l'échéance sandbox (IN_60D).
    expect((doc?.proExpiresAt as {toMillis(): number}).toMillis()).toBe(IN_30D);
  });

  it("échéance prod enregistrée dépassée → rétrogradé (le sandbox ne prolonge rien)", async () => {
    seedActivePro("prod-pro", AGO_1D);

    const res = await reconcileExpiredEntitlements(
      fakeDb,
      () => Promise.resolve(entitlementStatesFromSubscriber(shadowedBody)),
      NOW,
    );

    expect(res.downgradedFree).toBe(1);
    expect(fakeDb.peek("landlords/prod-pro")?.subscriptionTier).toBe("free");
  });
});

// FEAT-044e — un uid de la liste blanche sandbox (compte de démo App Review,
// testeurs) : son achat sandbox vaut un vrai droit, pour le cron aussi.
describe("reconcile — uid de la liste blanche sandbox (FEAT-044e)", () => {
  const PRO_ID = rcEntitlementIdFor("pro") as string;
  const iso = (ms: number) => new Date(ms).toISOString();
  const sandboxBody = {
    entitlements: {
      [PRO_ID]: {expires_date: iso(IN_60D), product_identifier: "pro_sandbox"},
    },
    subscriptions: {pro_sandbox: {is_sandbox: true}},
  };

  it("sandboxAllowed → entitlement sandbox rapporté comme un vrai droit", () => {
    expect(
      entitlementStatesFromSubscriber(sandboxBody, {sandboxAllowed: true}),
    ).toEqual({pro: {expiresMs: IN_60D}});
  });

  it("sans option → masqué (comportement #209 inchangé)", () => {
    expect(entitlementStatesFromSubscriber(sandboxBody)).toEqual({
      pro: {expiresMs: null, sandboxShadowed: true},
    });
  });

  it("bout en bout : uid listé → échéance sandbox reprise (prolongée)", async () => {
    seedActivePro("review-demo", IN_30D);

    await reconcileExpiredEntitlements(
      fakeDb,
      () =>
        Promise.resolve(
          entitlementStatesFromSubscriber(sandboxBody, {sandboxAllowed: true}),
        ),
      NOW,
    );

    const doc = fakeDb.peek("landlords/review-demo");
    expect(doc?.subscriptionTier).toBe("paid");
    expect((doc?.proExpiresAt as {toMillis(): number}).toMillis()).toBe(IN_60D);
  });
});

// FEAT-044e — câblage RÉEL du passage du cron (`runReconcileEntitlements`) :
// lecture de `_ops/sandboxAllowlist` dans la base du cron, fetcher RevenueCat,
// décision par uid. Seul `fetch` (API RevenueCat) est simulé.
describe("cron — passage complet avec la liste blanche sandbox (FEAT-044e)", () => {
  const PRO_ID = rcEntitlementIdFor("pro") as string;
  const iso = (ms: number) => new Date(ms).toISOString();
  /** Réponse RevenueCat : Pro adossé à un achat SANDBOX échéant à [expMs]. */
  const sandboxSubscriber = (expMs: number) => ({
    subscriber: {
      entitlements: {
        [PRO_ID]: {expires_date: iso(expMs), product_identifier: "pro_sandbox"},
      },
      subscriptions: {pro_sandbox: {is_sandbox: true}},
    },
  });
  const tsMs = (uid: string) =>
    (fakeDb.peek(`landlords/${uid}`)?.proExpiresAt as {toMillis(): number})
      .toMillis();

  let fetchMock: ReturnType<typeof vi.fn>;

  /** Chaque uid reçoit la même réponse RevenueCat. */
  function stubRevenueCat(body: unknown) {
    fetchMock = vi.fn(() =>
      Promise.resolve({ok: true, json: () => Promise.resolve(body)}),
    );
    vi.stubGlobal("fetch", fetchMock);
  }

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("même réponse sandbox : uid listé prolongé, uid non listé masqué", async () => {
    fakeDb.seed(SANDBOX_ALLOWLIST_DOC, {uids: ["review-demo"]});
    seedActivePro("review-demo", IN_30D);
    seedActivePro("prod-pro", IN_30D);
    stubRevenueCat(sandboxSubscriber(IN_60D));

    const res = await runReconcileEntitlements(fakeDb, "sk_test", NOW);

    expect(res.failed).toBe(0);
    expect(tsMs("review-demo")).toBe(IN_60D);
    expect(tsMs("prod-pro")).toBe(IN_30D);
    // La clé API part bien dans l'en-tête, uid encodé dans l'URL.
    expect(fetchMock).toHaveBeenCalledWith(
      "https://api.revenuecat.com/v1/subscribers/review-demo",
      {headers: {Authorization: "Bearer sk_test"}},
    );
  });

  it("achat sandbox expiré : uid listé RETIRÉ, uid non listé inchangé", async () => {
    fakeDb.seed(SANDBOX_ALLOWLIST_DOC, {uids: ["review-demo"]});
    seedActivePro("review-demo", IN_30D);
    seedActivePro("prod-pro", IN_30D);
    stubRevenueCat(sandboxSubscriber(AGO_1D));

    const res = await runReconcileEntitlements(fakeDb, "sk_test", NOW);

    expect(res.downgradedFree).toBe(1);
    expect(fakeDb.peek("landlords/review-demo")?.subscriptionTier).toBe("free");
    expect(fakeDb.peek("landlords/prod-pro")?.subscriptionTier).toBe("paid");
  });

  it("pas de document liste → comportement #209 (masqué)", async () => {
    seedActivePro("review-demo", IN_30D);
    stubRevenueCat(sandboxSubscriber(IN_60D));

    await runReconcileEntitlements(fakeDb, "sk_test", NOW);

    expect(tsMs("review-demo")).toBe(IN_30D);
  });

  it("liste illisible → passage complet sans liste, aucun échec", async () => {
    seedActivePro("review-demo", IN_30D);
    stubRevenueCat(sandboxSubscriber(IN_60D));
    // Seule la lecture de la liste échoue ; le reste de la base fonctionne.
    const flakyDb = new Proxy(fakeDb, {
      get(target, prop) {
        if (prop === "doc") {
          return (path: string) =>
            path === SANDBOX_ALLOWLIST_DOC ?
              {get: () => Promise.reject(new Error("unavailable"))} :
              target.doc(path);
        }
        const value = Reflect.get(target, prop, target) as unknown;
        return typeof value === "function" ?
          (value as (...a: unknown[]) => unknown).bind(target) :
          value;
      },
    });

    const res = await runReconcileEntitlements(
      flakyDb as unknown as typeof fakeDb,
      "sk_test",
      NOW,
    );

    expect(res).toMatchObject({checked: 1, failed: 0});
    expect(tsMs("review-demo")).toBe(IN_30D);
  });
});
