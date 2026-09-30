import type {CallableRequest, HttpsError} from "firebase-functions/v2/https";
import {afterEach, beforeEach, describe, expect, it, vi} from "vitest";

import {
  assertCanOpenCheckout,
  buildCheckoutSessionParams,
  createCheckoutSession,
  parseCheckoutRequest,
  parsePlanSelection,
  PLAN_LEVEL_METADATA_KEY,
  RC_APP_USER_ID_METADATA_KEY,
  type CheckoutConfig,
} from "../callable/create_checkout_session";
import {STAGING_ORIGIN} from "../utils/db_router";

import {
  FakeFirestore,
  fakeAdminFirestoreHolder,
  fakeStagingFirestoreHolder,
} from "./helpers/fake_firestore";

// Faux Stripe (même patron que manage_subscription.test.ts) : capture la clé du
// constructeur et les appels à `checkout.sessions.create`, pour prouver qu'un
// refus intervient AVANT tout appel Stripe.
const stripeMock = vi.hoisted(() => ({
  keys: [] as string[],
  create: vi.fn(),
}));
vi.mock("stripe", () => ({
  default: class FakeStripe {
    readonly checkout = {sessions: {create: stripeMock.create}};

    constructor(key: string) {
      stripeMock.keys.push(key);
    }
  },
}));

vi.mock("firebase-admin", async () => {
  const {makeFakeAdminModule} = await import("./helpers/fake_firestore");
  return makeFakeAdminModule();
});

/** Les six offres configurées — l'état « tout est ouvert » côté Stripe. */
const config: CheckoutConfig = {
  prices: {
    pro_monthly: "price_pro_monthly",
    pro_annual: "price_pro_annual",
    max_monthly: "price_max_monthly",
    max_annual: "price_max_annual",
    ultra_monthly: "price_ultra_monthly",
    ultra_annual: "price_ultra_annual",
  },
  baseUrl: "https://app.test",
};

/** Capture le code + message d'une HttpsError (le code est le contrat client). */
function thrownBy(fn: () => unknown): {code: string; message: string} {
  try {
    fn();
  } catch (e) {
    const err = e as HttpsError;
    return {code: err.code, message: err.message};
  }
  throw new Error("expected the call to throw");
}

describe("parseCheckoutRequest — shim de rétrocompatibilité", () => {
  it("★ forme LEGACY {plan:'monthly'} → Pro mensuel (builds mobiles déjà installées)", () => {
    // Le déploiement des Functions est partagé prod/staging et les builds des
    // stores ne peuvent pas être forcées à jour : cette forme DOIT continuer de
    // fonctionner, et viser le palier Pro.
    expect(parseCheckoutRequest({plan: "monthly"})).toEqual({
      level: "pro",
      period: "monthly",
    });
  });

  it("★ forme LEGACY {plan:'annual'} → Pro annuel", () => {
    expect(parseCheckoutRequest({plan: "annual"})).toEqual({
      level: "pro",
      period: "annual",
    });
  });

  it("nouvelle forme {level, period} → telle quelle", () => {
    expect(parseCheckoutRequest({level: "ultra", period: "annual"})).toEqual({
      level: "ultra",
      period: "annual",
    });
  });

  it("level absent + period présent → Pro (défaut du palier)", () => {
    expect(parseCheckoutRequest({period: "monthly"})).toEqual({
      level: "pro",
      period: "monthly",
    });
  });

  it("period ET plan fournis → period gagne (le client récent affiche period)", () => {
    expect(
      parseCheckoutRequest({level: "pro", period: "annual", plan: "monthly"}),
    ).toEqual({level: "pro", period: "annual"});
  });

  it("payload vide → invalid-argument", () => {
    expect(thrownBy(() => parseCheckoutRequest({})).code).toBe(
      "invalid-argument",
    );
  });

  it("palier inconnu → invalid-argument (jamais deviné)", () => {
    expect(
      thrownBy(() => parseCheckoutRequest({level: "platinum", period: "monthly"}))
        .code,
    ).toBe("invalid-argument");
  });

  it("périodicité inconnue → invalid-argument", () => {
    expect(
      thrownBy(() => parseCheckoutRequest({level: "pro", period: "weekly"})).code,
    ).toBe("invalid-argument");
  });

  it("★ bout en bout : payload legacy → session sur le price PRO (aucun changement facturant)", () => {
    // La preuve qui compte : une build mobile déjà installée envoie {plan} et
    // obtient exactement la session qu'elle obtenait avant FEAT-056 — même
    // price Stripe, même metadata RevenueCat.
    for (const period of ["monthly", "annual"] as const) {
      const selection = parseCheckoutRequest({plan: period});
      const params = buildCheckoutSessionParams({
        uid: "legacy-mobile-user",
        level: selection.level,
        period: selection.period,
        config,
      });
      expect(params.line_items).toEqual([
        {price: `price_pro_${period}`, quantity: 1},
      ]);
      expect(params.metadata?.[RC_APP_USER_ID_METADATA_KEY]).toBe(
        "legacy-mobile-user",
      );
      expect(params.metadata?.[PLAN_LEVEL_METADATA_KEY]).toBe("pro");
    }
  });
});

describe("parsePlanSelection — forme stricte (change_plan)", () => {
  it("exige level ET period", () => {
    expect(parsePlanSelection({level: "max", period: "monthly"})).toEqual({
      level: "max",
      period: "monthly",
    });
    expect(thrownBy(() => parsePlanSelection({period: "monthly"})).code).toBe(
      "invalid-argument",
    );
    expect(thrownBy(() => parsePlanSelection({level: "max"})).code).toBe(
      "invalid-argument",
    );
  });

  it("n'accepte PAS la forme legacy {plan} (aucun client historique à ménager)", () => {
    expect(thrownBy(() => parsePlanSelection({plan: "monthly"})).code).toBe(
      "invalid-argument",
    );
  });
});

describe("buildCheckoutSessionParams — les 6 combinaisons", () => {
  it("Pro mensuel et Pro annuel visent le bon price", () => {
    expect(
      buildCheckoutSessionParams({
        uid: "u1",
        level: "pro",
        period: "monthly",
        config,
      }).line_items,
    ).toEqual([{price: "price_pro_monthly", quantity: 1}]);
    expect(
      buildCheckoutSessionParams({
        uid: "u1",
        level: "pro",
        period: "annual",
        config,
      }).line_items?.[0],
    ).toMatchObject({price: "price_pro_annual"});
  });

  it("mode subscription", () => {
    const p = buildCheckoutSessionParams({
      uid: "u1",
      level: "pro",
      period: "monthly",
      config,
    });
    expect(p.mode).toBe("subscription");
  });

  it("★ App User ID (UID) posé en metadata de la SESSION ET de la subscription", () => {
    // Le linchpin RevenueCat : sans la metadata aux deux endroits, l'abonnement
    // Stripe ne serait pas rattaché au bon compte.
    const p = buildCheckoutSessionParams({
      uid: "landlord-42",
      level: "pro",
      period: "monthly",
      config,
    });
    expect(p.metadata?.[RC_APP_USER_ID_METADATA_KEY]).toBe("landlord-42");
    const subMeta = p.subscription_data?.metadata as Record<string, unknown>;
    expect(subMeta[RC_APP_USER_ID_METADATA_KEY]).toBe("landlord-42");
    // client_reference_id en ceinture+bretelles.
    expect(p.client_reference_id).toBe("landlord-42");
  });

  it("palier posé en metadata (support + rapprochement Stripe ↔ RC)", () => {
    const p = buildCheckoutSessionParams({
      uid: "u1",
      level: "pro",
      period: "annual",
      config,
    });
    expect(p.metadata?.[PLAN_LEVEL_METADATA_KEY]).toBe("pro");
    const subMeta = p.subscription_data?.metadata as Record<string, unknown>;
    expect(subMeta[PLAN_LEVEL_METADATA_KEY]).toBe("pro");
  });

  it("success/cancel URLs dérivées du base URL, success porte le palier", () => {
    const p = buildCheckoutSessionParams({
      uid: "u1",
      level: "pro",
      period: "monthly",
      config,
    });
    expect(p.success_url).toBe(
      "https://app.test/pro/success?session_id={CHECKOUT_SESSION_ID}&level=pro",
    );
    expect(p.cancel_url).toBe("https://app.test/pro/cancel");
  });

  it("email client inclus si fourni, absent sinon", () => {
    expect(
      buildCheckoutSessionParams({
        uid: "u1",
        level: "pro",
        period: "monthly",
        config,
        customerEmail: "jean@example.com",
      }).customer_email,
    ).toBe("jean@example.com");
    expect(
      buildCheckoutSessionParams({
        uid: "u1",
        level: "pro",
        period: "monthly",
        config,
      }).customer_email,
    ).toBeUndefined();
  });
});

describe("★ garde serveur `purchasable` — affiché mais pas achetable", () => {
  // La garantie commerciale vit CÔTÉ SERVEUR, pas dans l'UI : Max et Ultra sont
  // annoncés sur /pro avec un prix indicatif, mais aucun chemin de paiement ne
  // doit exister tant que leurs features ne sont pas construites. Un client
  // patché ou une UI en avance de phase doit se heurter au même mur.
  for (const level of ["max", "ultra"] as const) {
    for (const period of ["monthly", "annual"] as const) {
      it(`${level}/${period} → failed-precondition / level_not_purchasable`, () => {
        const err = thrownBy(() =>
          buildCheckoutSessionParams({uid: "u1", level, period, config}),
        );
        expect(err.code).toBe("failed-precondition");
        expect(err.message).toBe("level_not_purchasable");
      });
    }
  }

  it("le refus tombe AVANT le price (même avec un price configuré)", () => {
    // `config` ci-dessus fournit bien price_max_* : la seule chose qui bloque
    // est le flag `purchasable`, pas une configuration manquante.
    expect(config.prices.max_monthly).toBe("price_max_monthly");
    expect(
      thrownBy(() =>
        buildCheckoutSessionParams({
          uid: "u1",
          level: "max",
          period: "monthly",
          config,
        }),
      ).message,
    ).toBe("level_not_purchasable");
  });

  it("Pro (purchasable: true) passe la garde", () => {
    expect(() =>
      buildCheckoutSessionParams({
        uid: "u1",
        level: "pro",
        period: "monthly",
        config,
      }),
    ).not.toThrow();
  });
});

describe("second verrou — price_not_configured", () => {
  it("price vide sur un palier vendable → failed-precondition / price_not_configured", () => {
    const err = thrownBy(() =>
      buildCheckoutSessionParams({
        uid: "u1",
        level: "pro",
        period: "annual",
        config: {prices: {pro_monthly: "price_pro_monthly", pro_annual: ""},
          baseUrl: "https://app.test"},
      }),
    );
    expect(err.code).toBe("failed-precondition");
    expect(err.message).toBe("price_not_configured");
  });

  it("price absent de la table → même refus (jamais de session sur un price vide)", () => {
    expect(
      thrownBy(() =>
        buildCheckoutSessionParams({
          uid: "u1",
          level: "pro",
          period: "monthly",
          config: {prices: {}, baseUrl: "https://app.test"},
        }),
      ).message,
    ).toBe("price_not_configured");
  });
});

describe("assertCanOpenCheckout — pas de second abonnement", () => {
  it("compte payant → failed-precondition / already_subscribed_use_change_plan", () => {
    const err = thrownBy(() =>
      assertCanOpenCheckout({subscriptionTier: "paid", planLevel: "pro"}),
    );
    expect(err.code).toBe("failed-precondition");
    expect(err.message).toBe("already_subscribed_use_change_plan");
  });

  it("compte payant legacy (sans planLevel) → refusé aussi", () => {
    expect(
      thrownBy(() => assertCanOpenCheckout({subscriptionTier: "paid"})).message,
    ).toBe("already_subscribed_use_change_plan");
  });

  it("compte gratuit ou anonyme → laisse passer", () => {
    expect(() =>
      assertCanOpenCheckout({subscriptionTier: "free"}),
    ).not.toThrow();
    expect(() =>
      assertCanOpenCheckout({subscriptionTier: "anonymous"}),
    ).not.toThrow();
  });

  it("OWASP-01 : doc landlord ABSENT → failed-precondition / landlord_not_found", () => {
    // Un doc absent de la base routée n'est pas « un compte gratuit » : c'est un
    // compte qui n'existe pas dans cet environnement (ex. un compte prod qui
    // ouvre le checkout du staging). Aucune session Stripe pour lui.
    const err = thrownBy(() => assertCanOpenCheckout(null));
    expect(err.code).toBe("failed-precondition");
    expect(err.message).toBe("landlord_not_found");
  });
});

describe("createCheckoutSession — handler (OWASP-01 : doc landlord requis)", () => {
  const UID = "landlord-a";
  const LIVE_KEY = "sk_live_fake";
  const TEST_KEY = "sk_test_fake";
  const PROD_ORIGIN = "https://baillan.com";

  let prodDb: FakeFirestore;
  let stagingDb: FakeFirestore;

  function makeRequest(origin?: string): CallableRequest {
    return {
      data: {level: "pro", period: "monthly"},
      auth: {uid: UID, token: {email: "a@example.test"} as never, rawToken: ""},
      rawRequest: {headers: origin === undefined ? {} : {origin}} as never,
    } as CallableRequest;
  }

  beforeEach(() => {
    prodDb = new FakeFirestore();
    stagingDb = new FakeFirestore("staging");
    fakeAdminFirestoreHolder.db = prodDb;
    fakeStagingFirestoreHolder.db = stagingDb;
    vi.stubEnv("STRIPE_SECRET_KEY", LIVE_KEY);
    vi.stubEnv("STRIPE_SECRET_KEY_TEST", TEST_KEY);
    vi.stubEnv("STRIPE_PRICE_PRO_MONTHLY", "price_pro_monthly");
    stripeMock.keys.length = 0;
    stripeMock.create.mockReset().mockResolvedValue({
      url: "https://checkout.stripe.test/s",
      id: "cs_test_1",
    });
  });

  afterEach(() => {
    vi.unstubAllEnvs();
  });

  it("web prod, doc absent de (default) → refus landlord_not_found, AUCUN appel Stripe", async () => {
    // Le compte n'existe que dans la base staging : hors de la base routée.
    stagingDb.seed(`landlords/${UID}`, {id: UID, subscriptionTier: "free"});

    const err = await createCheckoutSession
      .run(makeRequest(PROD_ORIGIN))
      .catch((e: HttpsError) => e);

    expect((err as HttpsError).code).toBe("failed-precondition");
    expect((err as HttpsError).message).toBe("landlord_not_found");
    expect(stripeMock.keys).toEqual([]);
    expect(stripeMock.create).not.toHaveBeenCalled();
  });

  it("web staging, doc absent de staging → refus landlord_not_found, AUCUN appel Stripe", async () => {
    // Compte prod qui tente le checkout de test du staging : il n'a pas de doc
    // dans la base `staging` → refusé avant Stripe.
    prodDb.seed(`landlords/${UID}`, {id: UID, subscriptionTier: "free"});

    const err = await createCheckoutSession
      .run(makeRequest(STAGING_ORIGIN))
      .catch((e: HttpsError) => e);

    expect((err as HttpsError).code).toBe("failed-precondition");
    expect((err as HttpsError).message).toBe("landlord_not_found");
    expect(stripeMock.keys).toEqual([]);
    expect(stripeMock.create).not.toHaveBeenCalled();
  });

  it("app native (sans Origin), aucun doc nulle part → refus landlord_not_found", async () => {
    const err = await createCheckoutSession
      .run(makeRequest())
      .catch((e: HttpsError) => e);

    expect((err as HttpsError).message).toBe("landlord_not_found");
    expect(stripeMock.create).not.toHaveBeenCalled();
  });

  it("web prod, compte gratuit présent → session Stripe créée avec la clé LIVE (inchangé)", async () => {
    prodDb.seed(`landlords/${UID}`, {id: UID, subscriptionTier: "free"});

    const result = (await createCheckoutSession.run(
      makeRequest(PROD_ORIGIN),
    )) as {url: string; sessionId: string};

    expect(stripeMock.keys).toEqual([LIVE_KEY]);
    expect(stripeMock.create).toHaveBeenCalledOnce();
    expect(result.sessionId).toBe("cs_test_1");
    expect(result.url).toBe("https://checkout.stripe.test/s");
  });

  it("web staging, compte présent dans staging → clé TEST (inchangé)", async () => {
    stagingDb.seed(`landlords/${UID}`, {id: UID, subscriptionTier: "free"});

    await createCheckoutSession.run(makeRequest(STAGING_ORIGIN));

    expect(stripeMock.keys).toEqual([TEST_KEY]);
    expect(stripeMock.create).toHaveBeenCalledOnce();
  });

  it("compte déjà payant présent → already_subscribed_use_change_plan (inchangé)", async () => {
    prodDb.seed(`landlords/${UID}`, {
      id: UID,
      subscriptionTier: "paid",
      planLevel: "pro",
    });

    const err = await createCheckoutSession
      .run(makeRequest(PROD_ORIGIN))
      .catch((e: HttpsError) => e);

    expect((err as HttpsError).message).toBe("already_subscribed_use_change_plan");
    expect(stripeMock.create).not.toHaveBeenCalled();
  });
});
