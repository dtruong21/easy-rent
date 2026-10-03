import type {CallableRequest, HttpsError} from "firebase-functions/v2/https";
import {afterEach, beforeEach, describe, expect, it, vi} from "vitest";

import {
  assertSafeUid,
  manageSubscription,
  parseAction,
  pickManageableSubscription,
  pickSubscriptionItem,
  planLevelChange,
  planSubscriptionUpdate,
  type ManageableSubscriptionLike,
} from "../callable/manage_subscription";
import {
  levelForPriceId,
  resolvePriceIdOrThrow,
  type PriceTable,
} from "../entitlements/stripe_prices";
import {STAGING_ORIGIN} from "../utils/db_router";

import {
  FakeFirestore,
  fakeAdminFirestoreHolder,
  fakeStagingFirestoreHolder,
} from "./helpers/fake_firestore";
import {VERIFIED_TOKEN} from "./helpers/verified_token";

// Faux Stripe (même patron que delete_account.test.ts) : la fausse classe
// capture la clé passée au constructeur pour prouver l'environnement visé
// (live/test) — ou qu'aucun client Stripe n'a été construit.
const stripeMock = vi.hoisted(() => ({
  keys: [] as string[],
  search: vi.fn(),
  update: vi.fn(),
}));
vi.mock("stripe", () => ({
  default: class FakeStripe {
    readonly subscriptions = {
      search: stripeMock.search,
      update: stripeMock.update,
    };

    constructor(key: string) {
      stripeMock.keys.push(key);
    }
  },
}));

// `dbForRequest` (appel sans Origin) lit `admin.firestore()` : cf.
// delete_account.test.ts pour le import() dynamique interne.
vi.mock("firebase-admin", async () => {
  const {makeFakeAdminModule} = await import("./helpers/fake_firestore");
  return makeFakeAdminModule();
});

function sub(
  over: Partial<ManageableSubscriptionLike> & {id: string},
): ManageableSubscriptionLike {
  return {
    status: "active",
    cancel_at_period_end: false,
    created: 1_700_000_000,
    ...over,
  };
}

function thrownBy(fn: () => unknown): {code: string; message: string} {
  try {
    fn();
  } catch (e) {
    const err = e as HttpsError;
    return {code: err.code, message: err.message};
  }
  throw new Error("expected the call to throw");
}

const prices: PriceTable = {
  pro_monthly: "price_pro_monthly",
  pro_annual: "price_pro_annual",
  max_monthly: "price_max_monthly",
  max_annual: "price_max_annual",
  ultra_monthly: "price_ultra_monthly",
  ultra_annual: "price_ultra_annual",
};

describe("planSubscriptionUpdate", () => {
  it("cancel alors que l'abonnement se renouvelle → programme la résiliation", () => {
    const r = planSubscriptionUpdate({
      action: "cancel",
      currentCancelAtPeriodEnd: false,
    });
    expect(r).toEqual({targetCancelAtPeriodEnd: true, noop: false});
  });

  it("cancel alors que déjà programmé → noop (idempotence)", () => {
    const r = planSubscriptionUpdate({
      action: "cancel",
      currentCancelAtPeriodEnd: true,
    });
    expect(r.noop).toBe(true);
  });

  it("reactivate alors que résiliation programmée → retire la programmation", () => {
    const r = planSubscriptionUpdate({
      action: "reactivate",
      currentCancelAtPeriodEnd: true,
    });
    expect(r).toEqual({targetCancelAtPeriodEnd: false, noop: false});
  });

  it("reactivate alors que déjà renouvelable → noop (idempotence)", () => {
    const r = planSubscriptionUpdate({
      action: "reactivate",
      currentCancelAtPeriodEnd: false,
    });
    expect(r.noop).toBe(true);
  });
});

describe("parseAction (validation d'entrée)", () => {
  it("'cancel' et 'reactivate' passent", () => {
    expect(parseAction("cancel")).toBe("cancel");
    expect(parseAction("reactivate")).toBe("reactivate");
  });

  it("'change_plan' passe (FEAT-056)", () => {
    expect(parseAction("change_plan")).toBe("change_plan");
  });

  it("action inconnue → invalid-argument", () => {
    expect(() => parseAction("delete")).toThrowError(/action must be/);
  });

  it("valeur non-string (absente) → rejetée", () => {
    expect(() => parseAction(undefined)).toThrow();
    expect(() => parseAction(42)).toThrow();
  });
});

describe("assertSafeUid (garde anti-injection Search)", () => {
  it("UID alphanumérique/URL-safe → OK", () => {
    expect(() => assertSafeUid("abc123DEF_-")).not.toThrow();
  });

  it("UID contenant une apostrophe (casse le littéral Search) → rejeté", () => {
    expect(() => assertSafeUid("a' OR '1'='1")).toThrowError(/malformed uid/);
  });

  it("UID vide ou avec métacaractères/espace → rejeté", () => {
    expect(() => assertSafeUid("")).toThrow();
    expect(() => assertSafeUid("a b")).toThrow();
    expect(() => assertSafeUid("a\n")).toThrow();
    expect(() => assertSafeUid("a:b")).toThrow();
  });
});

describe("pickManageableSubscription", () => {
  it("aucun abonnement (user mobile / terminé) → null", () => {
    expect(pickManageableSubscription([])).toBeNull();
  });

  it("uniquement des statuts non gérables → null", () => {
    const subs = [
      sub({id: "s1", status: "canceled"}),
      sub({id: "s2", status: "incomplete_expired"}),
    ];
    expect(pickManageableSubscription(subs)).toBeNull();
  });

  it("un seul abonnement actif → le retourne avec son cancel_at_period_end", () => {
    const subs = [sub({id: "s1", status: "active", cancel_at_period_end: true})];
    expect(pickManageableSubscription(subs)).toEqual({
      id: "s1",
      cancel_at_period_end: true,
      items: [],
    });
  });

  it("trialing seul → gérable", () => {
    const subs = [sub({id: "s1", status: "trialing"})];
    expect(pickManageableSubscription(subs)?.id).toBe("s1");
  });

  it("mélange actif/past_due/canceled → ignore canceled, prend le plus récent des gérables", () => {
    const subs = [
      sub({id: "old", status: "active", created: 1_000}),
      sub({id: "dead", status: "canceled", created: 9_999}),
      sub({id: "recent", status: "past_due", created: 5_000}),
    ];
    expect(pickManageableSubscription(subs)?.id).toBe("recent");
  });

  it("remonte les lignes de facturation (nécessaires au change_plan)", () => {
    const subs = [
      sub({
        id: "s1",
        items: [{id: "si_1", price: {id: "price_pro_monthly"}}],
      }),
    ];
    expect(pickManageableSubscription(subs)?.items).toEqual([
      {id: "si_1", price: {id: "price_pro_monthly"}},
    ]);
  });
});

describe("pickSubscriptionItem", () => {
  it("une seule ligne → la retourne", () => {
    const item = {id: "si_1", price: {id: "price_pro_monthly"}};
    expect(pickSubscriptionItem([item])).toEqual(item);
  });

  it("zéro ligne → failed-precondition (on ne devine pas)", () => {
    const err = thrownBy(() => pickSubscriptionItem([]));
    expect(err.code).toBe("failed-precondition");
    expect(err.message).toBe("unsupported_subscription_shape");
  });

  it("plusieurs lignes → refus plutôt que repricer la mauvaise", () => {
    expect(
      thrownBy(() =>
        pickSubscriptionItem([
          {id: "si_1", price: {id: "price_pro_monthly"}},
          {id: "si_2", price: {id: "price_addon"}},
        ]),
      ).message,
    ).toBe("unsupported_subscription_shape");
  });
});

describe("planLevelChange", () => {
  it("Pro → Ultra = upgrade", () => {
    expect(
      planLevelChange({
        currentPriceId: "price_pro_monthly",
        targetPriceId: "price_ultra_monthly",
        currentRank: 10,
        targetRank: 30,
      }),
    ).toEqual({noop: false, direction: "upgrade"});
  });

  it("Ultra → Pro = downgrade", () => {
    expect(
      planLevelChange({
        currentPriceId: "price_ultra_monthly",
        targetPriceId: "price_pro_monthly",
        currentRank: 30,
        targetRank: 10,
      }),
    ).toEqual({noop: false, direction: "downgrade"});
  });

  it("même price → noop (aucun appel Stripe, aucun event RC parasite)", () => {
    expect(
      planLevelChange({
        currentPriceId: "price_pro_monthly",
        targetPriceId: "price_pro_monthly",
        currentRank: 10,
        targetRank: 10,
      }),
    ).toEqual({noop: true, direction: "same"});
  });

  it("mensuel → annuel à palier constant : pas un noop, direction 'same'", () => {
    expect(
      planLevelChange({
        currentPriceId: "price_pro_monthly",
        targetPriceId: "price_pro_annual",
        currentRank: 10,
        targetRank: 10,
      }),
    ).toEqual({noop: false, direction: "same"});
  });

  it("price courant inconnu (offre legacy) → changement autorisé, jamais bloqué", () => {
    const r = planLevelChange({
      currentPriceId: null,
      targetPriceId: "price_pro_monthly",
      currentRank: 0,
      targetRank: 10,
    });
    expect(r.noop).toBe(false);
  });
});

describe("levelForPriceId", () => {
  it("retrouve le palier d'un price connu, quelle que soit la périodicité", () => {
    expect(levelForPriceId(prices, "price_pro_annual")).toBe("pro");
    expect(levelForPriceId(prices, "price_ultra_monthly")).toBe("ultra");
  });

  it("price inconnu → null (jamais deviné)", () => {
    expect(levelForPriceId(prices, "price_legacy_2024")).toBeNull();
  });

  it("une entrée vide ne matche pas une chaîne vide", () => {
    expect(levelForPriceId({pro_monthly: ""}, "")).toBeNull();
  });
});

describe("★ change_plan — mêmes gardes serveur que le checkout", () => {
  // Le changement de palier ne doit pas être une porte dérobée vers un palier
  // non vendable : la résolution du price passe par la MÊME fonction que
  // createCheckoutSession.
  it("changer vers Max (purchasable: false) → level_not_purchasable", () => {
    const err = thrownBy(() => resolvePriceIdOrThrow(prices, "max", "monthly"));
    expect(err.code).toBe("failed-precondition");
    expect(err.message).toBe("level_not_purchasable");
  });

  it("changer vers Pro sans price configuré → price_not_configured", () => {
    expect(
      thrownBy(() => resolvePriceIdOrThrow({pro_monthly: ""}, "pro", "monthly"))
        .message,
    ).toBe("price_not_configured");
  });

  it("changer vers Pro annuel configuré → price résolu", () => {
    expect(resolvePriceIdOrThrow(prices, "pro", "annual")).toBe(
      "price_pro_annual",
    );
  });
});

// Décision utilisateur (2026-09-30) : « Résilier » doit marcher depuis les apps
// iOS/Android, qui n'envoient pas d'Origin. Sans Origin, seule la résiliation
// passe (clé choisie par la base du compte) ; réactiver ou changer d'offre
// reste refusé — ce serait un achat hors achat intégré.
describe("manageSubscription — handler (Origin web vs app native)", () => {
  const LIVE_KEY = "sk_live_fake";
  const TEST_KEY = "sk_test_fake";
  const UID = "landlord-a";

  let fakeDb: FakeFirestore;
  let fakeStagingDb: FakeFirestore;

  const renewingSub = {
    id: "sub_1",
    status: "active",
    cancel_at_period_end: false,
    created: 1_700_000_000,
    items: {data: [{id: "si_1", price: {id: "price_pro_monthly"}}]},
  };

  function makeRequest(
    data: Record<string, unknown>,
    origin?: string,
  ): CallableRequest {
    return {
      data,
      auth: {uid: UID, token: VERIFIED_TOKEN, rawToken: ""},
      rawRequest: {headers: origin === undefined ? {} : {origin}} as never,
    } as CallableRequest;
  }

  beforeEach(() => {
    fakeDb = new FakeFirestore();
    fakeStagingDb = new FakeFirestore("staging");
    fakeAdminFirestoreHolder.db = fakeDb;
    fakeStagingFirestoreHolder.db = fakeStagingDb;
    vi.stubEnv("STRIPE_SECRET_KEY", LIVE_KEY);
    vi.stubEnv("STRIPE_SECRET_KEY_TEST", TEST_KEY);
    stripeMock.keys.length = 0;
    stripeMock.search.mockReset().mockResolvedValue({data: [renewingSub]});
    stripeMock.update
      .mockReset()
      .mockImplementation((_id: string, params: {cancel_at_period_end?: boolean}) =>
        Promise.resolve({cancel_at_period_end: params.cancel_at_period_end}),
      );
  });

  afterEach(() => {
    vi.unstubAllEnvs();
  });

  it("cancel sans Origin + compte prod → clé LIVE, cancel_at_period_end: true", async () => {
    fakeDb.seed(`landlords/${UID}`, {id: UID});

    const result = await manageSubscription.run(
      makeRequest({action: "cancel"}),
    );

    expect(stripeMock.keys).toEqual([LIVE_KEY]);
    expect(stripeMock.search).toHaveBeenCalledWith(
      expect.objectContaining({query: `metadata['rc_app_user_id']:'${UID}'`}),
    );
    expect(stripeMock.update).toHaveBeenCalledWith("sub_1", {
      cancel_at_period_end: true,
    });
    expect(result).toEqual({status: "updated", cancelAtPeriodEnd: true});
  });

  it("cancel avec Origin vide + compte staging → clé TEST (#138)", async () => {
    fakeStagingDb.seed(`landlords/${UID}`, {id: UID});

    await manageSubscription.run(makeRequest({action: "cancel"}, ""));

    expect(stripeMock.keys).toEqual([TEST_KEY]);
    expect(stripeMock.update).toHaveBeenCalledWith("sub_1", {
      cancel_at_period_end: true,
    });
  });

  it("cancel sans Origin + compte staging → clé TEST (#138)", async () => {
    fakeStagingDb.seed(`landlords/${UID}`, {id: UID});

    await manageSubscription.run(makeRequest({action: "cancel"}));

    expect(stripeMock.keys).toEqual([TEST_KEY]);
  });

  it("cancel sans Origin + clé de mode incorrect → refus, aucun appel Stripe", async () => {
    fakeDb.seed(`landlords/${UID}`, {id: UID});
    vi.stubEnv("STRIPE_SECRET_KEY", "sk_test_COLLEE_DANS_LE_SLOT_LIVE");

    await expect(
      manageSubscription.run(makeRequest({action: "cancel"})),
    ).rejects.toMatchObject({message: "stripe_key_mode_mismatch_live"});
    expect(stripeMock.keys).toHaveLength(0);
  });

  for (const data of [
    {action: "reactivate"},
    {action: "change_plan", level: "pro", period: "annual"},
  ]) {
    it(`${data.action} sans Origin → origin_not_allowed, Stripe jamais construit`, async () => {
      fakeDb.seed(`landlords/${UID}`, {id: UID});

      await expect(
        manageSubscription.run(makeRequest(data)),
      ).rejects.toMatchObject({
        code: "failed-precondition",
        message: "origin_not_allowed",
      });
      expect(stripeMock.keys).toHaveLength(0);
      expect(stripeMock.search).not.toHaveBeenCalled();
      expect(stripeMock.update).not.toHaveBeenCalled();
    });
  }

  // Chemins web : strictement inchangés (clé par l'Origin).
  it("web : Origin prod → clé LIVE", async () => {
    await manageSubscription.run(
      makeRequest({action: "cancel"}, "https://app.baillan.com"),
    );

    expect(stripeMock.keys).toEqual([LIVE_KEY]);
  });

  it("web : Origin staging → clé TEST", async () => {
    await manageSubscription.run(
      makeRequest({action: "cancel"}, STAGING_ORIGIN),
    );

    expect(stripeMock.keys).toEqual([TEST_KEY]);
  });

  it("web : Origin inattendu → origin_not_allowed, même pour cancel", async () => {
    await expect(
      manageSubscription.run(
        makeRequest({action: "cancel"}, "https://evil.tld"),
      ),
    ).rejects.toMatchObject({
      code: "failed-precondition",
      message: "origin_not_allowed",
    });
    expect(stripeMock.keys).toHaveLength(0);
  });

  it("web : reactivate depuis l'Origin prod → autorisé", async () => {
    stripeMock.search.mockResolvedValue({
      data: [{...renewingSub, cancel_at_period_end: true}],
    });

    const result = await manageSubscription.run(
      makeRequest({action: "reactivate"}, "https://app.baillan.com"),
    );

    expect(stripeMock.keys).toEqual([LIVE_KEY]);
    expect(result).toEqual({status: "updated", cancelAtPeriodEnd: false});
  });
});
