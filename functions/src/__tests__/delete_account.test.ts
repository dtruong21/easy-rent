import * as fs from "node:fs";
import {resolve} from "node:path";

import {Timestamp} from "firebase-admin/firestore";
import {logger} from "firebase-functions/v2";
import type {CallableRequest} from "firebase-functions/v2/https";
import {afterEach, beforeEach, describe, expect, it, vi} from "vitest";

import {
  deleteAccount,
  hasWebBilling,
  PURGED_COLLECTIONS,
  RETAINED_COLLECTIONS,
} from "../callable/delete_account";
import {EXPORTED_COLLECTIONS} from "../callable/export_account_data";
import {storeOf} from "../http/revenuecat_webhook";

import {
  FakeAuthAdmin,
  FakeFirestore,
  FakeStorage,
  fakeAdminFirestoreHolder,
  fakeStagingFirestoreHolder,
} from "./helpers/fake_firestore";

// Faux Stripe : `deleteAccount` doit résilier l'abonnement AVANT toute purge.
// Le holder est `vi.hoisted` car le factory de `vi.mock` est hoisted au-dessus
// des imports. La fausse classe capture la clé passée au constructeur pour
// prouver quel environnement (live/test) a été visé.
const stripeMock = vi.hoisted(() => ({
  keys: [] as string[],
  search: vi.fn(),
  cancel: vi.fn(),
}));
vi.mock("stripe", () => ({
  default: class FakeStripe {
    readonly subscriptions = {
      search: stripeMock.search,
      cancel: stripeMock.cancel,
    };

    constructor(key: string) {
      stripeMock.keys.push(key);
    }
  },
}));

const LIVE_KEY = "sk_live_fake";
const TEST_KEY = "sk_test_fake";
const PROD_ORIGIN = "https://app.baillan.com";

/** Doc landlord d'un abonné facturé par Stripe (web) — forme écrite par le webhook. */
const WEB_BILLING = {
  proStore: "web",
  entitlements: {
    pro: {
      active: true,
      store: "web",
      productId: "prod_pro_monthly",
      willRenew: true,
      lastEventAtMs: 1,
    },
  },
};

// Cf. expenses.test.ts pour la justification du import() dynamique interne
// (le factory `vi.mock` est hoisted au-dessus des imports du fichier).
vi.mock("firebase-admin", async () => {
  const {makeFakeAdminModule} = await import("./helpers/fake_firestore");
  return makeFakeAdminModule();
});

let fakeDb: FakeFirestore;
let fakeStagingDb: FakeFirestore;
let fakeStorage: FakeStorage;
let fakeAuth: FakeAuthAdmin;

const LANDLORD_A = "landlord-a";
const LANDLORD_B = "landlord-b";

/** Epoch secondes d'une authentification "fraîche" (à l'instant). */
const FRESH_AUTH_TIME = () => Math.floor(Date.now() / 1000);
/** Epoch secondes d'une authentification vieille d'une heure. */
const STALE_AUTH_TIME = () => Math.floor(Date.now() / 1000) - 3600;

function makeRequest(
  uid: string | null,
  {
    authTime = FRESH_AUTH_TIME(),
    signInProvider = "password",
    origin,
  }: {authTime?: number; signInProvider?: string; origin?: string} = {},
): CallableRequest {
  return {
    data: {},
    auth: uid ?
      {
        uid,
        token: {
          auth_time: authTime,
          firebase: {sign_in_provider: signInProvider},
        } as never,
        rawToken: "",
      } :
      undefined,
    // Web : Origin présent. Mobile : aucun en-tête `origin`.
    rawRequest: {headers: origin === undefined ? {} : {origin}} as never,
  } as CallableRequest;
}

/** Jeu de données complet pour un landlord (toutes les collections). */
function seedLandlordDataset(
  uid: string,
  suffix: string,
  landlordExtra: Record<string, unknown> = {},
) {
  fakeDb.seed(`landlords/${uid}`, {
    id: uid,
    email: `${uid}@x.fr`,
    ...landlordExtra,
  });
  fakeDb.seed(`paid_plan_interest/${uid}`, {uid, features: ["reminders"]});
  fakeDb.seed(`properties/prop-${suffix}`, {landlordId: uid, name: "Bien"});
  fakeDb.seed(`tenants/ten-${suffix}`, {landlordId: uid, lastName: "Doe"});
  fakeDb.seed(`leases/lease-${suffix}`, {landlordId: uid, status: "active"});
  fakeDb.seed(`payments/pay-${suffix}`, {landlordId: uid, amountCents: 100});
  fakeDb.seed(`documents/doc-${suffix}`, {landlordId: uid, legalHold: true});
  fakeDb.seed(`expenses/exp-${suffix}`, {landlordId: uid, amountCents: 500});
  fakeDb.seed(`investment_scenarios/sc-${suffix}`, {landlordId: uid});
  fakeDb.seed(`support_requests/sup-${suffix}`, {landlordId: uid});
  // Documents figés (FEAT-033 / FEAT-037) : portent noms et adresses.
  fakeDb.seed(`charge_statements/cs-${suffix}`, {
    landlordId: uid,
    landlordFullName: "Jeanne Martin",
    tenantFullName: "Paul Durand",
  });
  fakeDb.seed(`etat_des_lieux/edl-${suffix}`, {
    landlordId: uid,
    landlordAddress: "1 rue de la Paix, 75002 Paris",
    propertyAddress: "2 rue des Lilas, 69003 Lyon",
  });
  fakeDb.seed(`receipts/rcpt-${suffix}`, {
    landlordId: uid,
    receiptNumber: `2026-${suffix}`,
    amountCents: 70000,
  });
}

beforeEach(() => {
  fakeDb = new FakeFirestore();
  fakeStagingDb = new FakeFirestore("staging");
  fakeStorage = new FakeStorage();
  fakeAuth = new FakeAuthAdmin();
  fakeAdminFirestoreHolder.db = fakeDb;
  fakeStagingFirestoreHolder.db = fakeStagingDb;
  fakeAdminFirestoreHolder.storage = fakeStorage;
  fakeAdminFirestoreHolder.authAdmin = fakeAuth;

  // Par défaut : secrets posés, l'utilisateur n'a AUCUN abonnement Stripe —
  // les tests de purge existants restent centrés sur la purge.
  vi.stubEnv("STRIPE_SECRET_KEY", LIVE_KEY);
  vi.stubEnv("STRIPE_SECRET_KEY_TEST", TEST_KEY);
  stripeMock.keys.length = 0;
  stripeMock.search.mockReset().mockResolvedValue({data: []});
  stripeMock.cancel.mockReset().mockResolvedValue({});
});

afterEach(() => {
  vi.unstubAllEnvs();
  // Espions `logger` (et autres `vi.spyOn`) restaurés même si une assertion a
  // échoué avant leur `mockRestore()` : aucun espion ne fuit dans le test suivant.
  vi.restoreAllMocks();
});

describe("deleteAccount", () => {
  it("refuse un appel non authentifié", async () => {
    await expect(
      deleteAccount.run(makeRequest(null)),
    ).rejects.toMatchObject({code: "unauthenticated"});
  });

  it("★ OWASP-02 : compte email/mot de passe NON vérifié → suppression autorisée (droit RGPD)", async () => {
    // `makeRequest` ne pose volontairement pas `email_verified` : le token est
    // celui d'un compte jamais vérifié (ex. inscrit avec l'adresse d'un tiers).
    // deleteAccount est EXEMPTÉE de `requireVerifiedUid` — le droit à
    // l'effacement (art. 17) doit rester exerçable.
    seedLandlordDataset(LANDLORD_A, "a1");

    await deleteAccount.run(
      makeRequest(LANDLORD_A, {signInProvider: "password"}),
    );

    expect(fakeDb.peek(`landlords/${LANDLORD_A}`)).toBeUndefined();
    expect(fakeDb.peek("properties/prop-a1")).toBeUndefined();
    expect(fakeAuth.deletedUids).toContain(LANDLORD_A);
  });

  it("refuse un token non-anonyme trop ancien (recent-login-required)", async () => {
    seedLandlordDataset(LANDLORD_A, "a1");

    await expect(
      deleteAccount.run(
        makeRequest(LANDLORD_A, {authTime: STALE_AUTH_TIME()}),
      ),
    ).rejects.toMatchObject({
      code: "failed-precondition",
      message: "recent-login-required",
    });

    // Rien n'a été touché : ni Firestore, ni Storage, ni Auth.
    expect(fakeDb.peek(`landlords/${LANDLORD_A}`)).toBeDefined();
    expect(fakeDb.peek("properties/prop-a1")).toBeDefined();
    expect(fakeStorage.deletedPrefixes).toHaveLength(0);
    expect(fakeAuth.deletedUids).toHaveLength(0);
  });

  it("purge toutes les collections du landlord + singletons + Storage + Auth", async () => {
    seedLandlordDataset(LANDLORD_A, "a1");

    const result = await deleteAccount.run(makeRequest(LANDLORD_A));

    expect(result).toMatchObject({deleted: true, receiptsRetained: 1});
    for (const path of [
      `landlords/${LANDLORD_A}`,
      `paid_plan_interest/${LANDLORD_A}`,
      "properties/prop-a1",
      "tenants/ten-a1",
      "leases/lease-a1",
      "payments/pay-a1",
      "documents/doc-a1",
      "expenses/exp-a1",
      "investment_scenarios/sc-a1",
      "support_requests/sup-a1",
      "charge_statements/cs-a1",
      "etat_des_lieux/edl-a1",
    ]) {
      expect(fakeDb.peek(path), path).toBeUndefined();
    }
    expect(fakeStorage.deletedPrefixes).toEqual([
      `documents/${LANDLORD_A}/`,
    ]);
    expect(fakeAuth.deletedUids).toEqual([LANDLORD_A]);
  });

  it("CONSERVE les quittances (rétention légale 5 ans) avec stamp de purge différée", async () => {
    seedLandlordDataset(LANDLORD_A, "a1");

    await deleteAccount.run(makeRequest(LANDLORD_A));

    const receipt = fakeDb.peek("receipts/rcpt-a1");
    expect(receipt).toBeDefined();
    expect(receipt?.receiptNumber).toBe("2026-a1");
    expect(receipt?.amountCents).toBe(70000);
    expect(receipt?.accountDeletedAt).toBeInstanceOf(Date);
    expect(receipt?.retentionUntil).toBeInstanceOf(Timestamp);
    // retentionUntil ≈ maintenant + 5 ans (tolérance 1 jour).
    const fiveYearsMs = 5 * 365.25 * 24 * 60 * 60 * 1000;
    const delta = Math.abs(
      (receipt?.retentionUntil as Timestamp).toMillis() -
        (Date.now() + fiveYearsMs),
    );
    expect(delta).toBeLessThan(24 * 60 * 60 * 1000);
  });

  it("ne touche JAMAIS aux données d'un autre landlord", async () => {
    seedLandlordDataset(LANDLORD_A, "a1");
    seedLandlordDataset(LANDLORD_B, "b1");

    await deleteAccount.run(makeRequest(LANDLORD_A));

    expect(fakeDb.peek(`landlords/${LANDLORD_B}`)).toBeDefined();
    expect(fakeDb.peek("properties/prop-b1")).toBeDefined();
    expect(fakeDb.peek("charge_statements/cs-b1")).toBeDefined();
    expect(fakeDb.peek("etat_des_lieux/edl-b1")).toBeDefined();
    expect(fakeDb.peek("receipts/rcpt-b1")?.accountDeletedAt).toBeUndefined();
    expect(fakeAuth.deletedUids).not.toContain(LANDLORD_B);
    expect(fakeStorage.deletedPrefixes).not.toContain(
      `documents/${LANDLORD_B}/`,
    );
  });

  it("accepte une session anonyme sans exigence de fraîcheur (aucun credential à re-présenter)", async () => {
    fakeDb.seed(`landlords/${LANDLORD_A}`, {id: LANDLORD_A, isAnonymous: true});
    fakeDb.seed("investment_scenarios/sc-anon", {landlordId: LANDLORD_A});

    const result = await deleteAccount.run(
      makeRequest(LANDLORD_A, {
        authTime: STALE_AUTH_TIME(),
        signInProvider: "anonymous",
      }),
    );

    expect(result).toMatchObject({deleted: true, receiptsRetained: 0});
    expect(fakeDb.peek(`landlords/${LANDLORD_A}`)).toBeUndefined();
    expect(fakeDb.peek("investment_scenarios/sc-anon")).toBeUndefined();
    expect(fakeAuth.deletedUids).toEqual([LANDLORD_A]);
  });

  it("REFUSE l'exemption anonyme si le compte a été upgradé par linking (claim périmé, audit M1)", async () => {
    // Un token émis AVANT linkAnonymousWithGoogle porte encore
    // sign_in_provider='anonymous' — mais le compte a un provider lié :
    // la garde de fraîcheur doit s'appliquer.
    seedLandlordDataset(LANDLORD_A, "a1");
    fakeAuth.providerDataByUid.set(LANDLORD_A, [{providerId: "google.com"}]);

    await expect(
      deleteAccount.run(
        makeRequest(LANDLORD_A, {
          authTime: STALE_AUTH_TIME(),
          signInProvider: "anonymous",
        }),
      ),
    ).rejects.toMatchObject({
      code: "failed-precondition",
      message: "recent-login-required",
    });

    expect(fakeDb.peek(`landlords/${LANDLORD_A}`)).toBeDefined();
    expect(fakeAuth.deletedUids).toHaveLength(0);
  });

  it("compte upgradé + token frais → purge acceptée (la garde ne bloque que le périmé)", async () => {
    seedLandlordDataset(LANDLORD_A, "a1");
    fakeAuth.providerDataByUid.set(LANDLORD_A, [{providerId: "google.com"}]);

    const result = await deleteAccount.run(
      makeRequest(LANDLORD_A, {signInProvider: "anonymous"}),
    );

    expect(result).toMatchObject({deleted: true});
    expect(fakeAuth.deletedUids).toEqual([LANDLORD_A]);
  });

  it("échec getUser (hors user-not-found) → fail-closed en 'internal', rien n'est purgé", async () => {
    seedLandlordDataset(LANDLORD_A, "a1");
    fakeAuth.getUserError = {code: "auth/internal-error"};

    await expect(
      deleteAccount.run(
        makeRequest(LANDLORD_A, {signInProvider: "anonymous"}),
      ),
    ).rejects.toMatchObject({code: "internal"});

    expect(fakeDb.peek(`landlords/${LANDLORD_A}`)).toBeDefined();
    expect(fakeAuth.deletedUids).toHaveLength(0);
  });

  it("est idempotent : un second appel sur un compte déjà purgé réussit", async () => {
    seedLandlordDataset(LANDLORD_A, "a1");

    await deleteAccount.run(makeRequest(LANDLORD_A));
    const second = await deleteAccount.run(makeRequest(LANDLORD_A));

    expect(second).toMatchObject({deleted: true});
  });

  it("tolère un user Auth déjà supprimé (auth/user-not-found)", async () => {
    seedLandlordDataset(LANDLORD_A, "a1");
    fakeAuth.deleteUserError = {code: "auth/user-not-found"};

    const result = await deleteAccount.run(makeRequest(LANDLORD_A));

    expect(result).toMatchObject({deleted: true});
    expect(fakeDb.peek(`landlords/${LANDLORD_A}`)).toBeUndefined();
  });

  it("relaie un échec Auth inattendu en 'internal' — données purgées, retry possible", async () => {
    seedLandlordDataset(LANDLORD_A, "a1");
    fakeAuth.deleteUserError = {code: "auth/internal-error"};

    await expect(
      deleteAccount.run(makeRequest(LANDLORD_A)),
    ).rejects.toMatchObject({code: "internal"});

    // La purge Firestore a bien eu lieu AVANT l'échec Auth : l'utilisateur
    // (toujours titulaire de son compte Auth) peut relancer la suppression.
    expect(fakeDb.peek(`landlords/${LANDLORD_A}`)).toBeUndefined();
    expect(fakeDb.peek("receipts/rcpt-a1")?.accountDeletedAt).toBeInstanceOf(
      Date,
    );
  });

  it("relaie un échec Storage en 'internal' — le compte Auth survit pour retry", async () => {
    seedLandlordDataset(LANDLORD_A, "a1");
    fakeStorage.deleteFilesError = new Error("gcs unavailable");

    await expect(
      deleteAccount.run(makeRequest(LANDLORD_A)),
    ).rejects.toMatchObject({code: "internal"});

    expect(fakeAuth.deletedUids).toHaveLength(0);
  });

  it("purge par pages une collection volumineuse (> PURGE_PAGE_SIZE docs)", async () => {
    fakeDb.seed(`landlords/${LANDLORD_A}`, {id: LANDLORD_A});
    for (let i = 0; i < 450; i++) {
      fakeDb.seed(`payments/pay-${i}`, {landlordId: LANDLORD_A});
    }

    await deleteAccount.run(makeRequest(LANDLORD_A));

    expect(fakeDb.peek("payments/pay-0")).toBeUndefined();
    expect(fakeDb.peek("payments/pay-449")).toBeUndefined();
  });

  it("purge par pages décomptes de charges et états des lieux (> PURGE_PAGE_SIZE docs)", async () => {
    fakeDb.seed(`landlords/${LANDLORD_A}`, {id: LANDLORD_A});
    for (let i = 0; i < 450; i++) {
      fakeDb.seed(`charge_statements/cs-${i}`, {landlordId: LANDLORD_A});
      fakeDb.seed(`etat_des_lieux/edl-${i}`, {landlordId: LANDLORD_A});
    }
    fakeDb.seed("charge_statements/cs-other", {landlordId: LANDLORD_B});
    fakeDb.seed("etat_des_lieux/edl-other", {landlordId: LANDLORD_B});

    await deleteAccount.run(makeRequest(LANDLORD_A));

    for (const path of [
      "charge_statements/cs-0",
      "charge_statements/cs-449",
      "etat_des_lieux/edl-0",
      "etat_des_lieux/edl-449",
    ]) {
      expect(fakeDb.peek(path), path).toBeUndefined();
    }
    expect(fakeDb.peek("charge_statements/cs-other")).toBeDefined();
    expect(fakeDb.peek("etat_des_lieux/edl-other")).toBeDefined();
  });

  it("les décomptes de charges et états des lieux sont HARD-DELETE (jamais stampés pour rétention)", async () => {
    seedLandlordDataset(LANDLORD_A, "a1");

    await deleteAccount.run(makeRequest(LANDLORD_A));

    // Aucun résidu, pas même un doc marqué `retentionUntil` : le cron de purge
    // ne lit que `receipts`, un doc stampé ici resterait donc éternellement.
    expect(fakeDb.peek("charge_statements/cs-a1")).toBeUndefined();
    expect(fakeDb.peek("etat_des_lieux/edl-a1")).toBeUndefined();
  });

  it("un retry après une purge interrompue (Storage KO) termine l'effacement des nouveaux types", async () => {
    seedLandlordDataset(LANDLORD_A, "a1");
    fakeStorage.deleteFilesError = new Error("gcs unavailable");
    await expect(
      deleteAccount.run(makeRequest(LANDLORD_A)),
    ).rejects.toMatchObject({code: "internal"});
    expect(fakeDb.peek("charge_statements/cs-a1")).toBeUndefined();

    // Résidu laissé entre-temps (ex. doc recréé) : le retry le purge aussi.
    fakeDb.seed("etat_des_lieux/edl-late", {landlordId: LANDLORD_A});
    fakeStorage.deleteFilesError = null;
    const result = await deleteAccount.run(makeRequest(LANDLORD_A));

    expect(result).toMatchObject({deleted: true});
    expect(fakeDb.peek("etat_des_lieux/edl-late")).toBeUndefined();
    expect(fakeAuth.deletedUids).toEqual([LANDLORD_A]);
  });

  it("stampe par chunks un volume de quittances > PURGE_PAGE_SIZE", async () => {
    fakeDb.seed(`landlords/${LANDLORD_A}`, {id: LANDLORD_A});
    for (let i = 0; i < 450; i++) {
      fakeDb.seed(`receipts/rcpt-${i}`, {landlordId: LANDLORD_A});
    }

    const result = await deleteAccount.run(makeRequest(LANDLORD_A));

    expect(result).toMatchObject({receiptsRetained: 450});
    expect(fakeDb.peek("receipts/rcpt-0")?.accountDeletedAt).toBeInstanceOf(
      Date,
    );
    expect(fakeDb.peek("receipts/rcpt-449")?.accountDeletedAt).toBeInstanceOf(
      Date,
    );
  });
});

// Sans cette étape, supprimer son compte laissait l'abonnement Stripe (web)
// actif : l'utilisateur continuait d'être facturé pour un compte inexistant.
describe("deleteAccount — résiliation de l'abonnement Stripe", () => {
  const activeSub = {id: "sub_active", status: "active"};
  const canceledSub = {id: "sub_old", status: "canceled"};

  it("web prod : résilie l'abonnement actif (pas le canceled) avec la clé LIVE, puis purge", async () => {
    seedLandlordDataset(LANDLORD_A, "a1", WEB_BILLING);
    stripeMock.search.mockResolvedValue({data: [activeSub, canceledSub]});

    const result = await deleteAccount.run(
      makeRequest(LANDLORD_A, {origin: PROD_ORIGIN}),
    );

    expect(stripeMock.keys).toEqual([LIVE_KEY]);
    // Recherche par metadata uid — jamais d'identifiant fourni par le client.
    expect(stripeMock.search).toHaveBeenCalledWith(
      expect.objectContaining({
        query: `metadata['rc_app_user_id']:'${LANDLORD_A}'`,
      }),
    );
    expect(stripeMock.cancel).toHaveBeenCalledTimes(1);
    expect(stripeMock.cancel).toHaveBeenCalledWith("sub_active");
    expect(result).toMatchObject({deleted: true});
    expect(fakeDb.peek(`landlords/${LANDLORD_A}`)).toBeUndefined();
    expect(fakeAuth.deletedUids).toEqual([LANDLORD_A]);
  });

  it("résilie aussi trialing / past_due / unpaid, ignore incomplete_expired", async () => {
    seedLandlordDataset(LANDLORD_A, "a1", WEB_BILLING);
    stripeMock.search.mockResolvedValue({
      data: [
        {id: "sub_trial", status: "trialing"},
        {id: "sub_due", status: "past_due"},
        {id: "sub_unpaid", status: "unpaid"},
        {id: "sub_exp", status: "incomplete_expired"},
      ],
    });

    await deleteAccount.run(makeRequest(LANDLORD_A, {origin: PROD_ORIGIN}));

    const cancelledIds = (stripeMock.cancel.mock.calls as string[][])
      .map(([id]) => id)
      .sort();
    expect(cancelledIds).toEqual([
      "sub_due",
      "sub_trial",
      "sub_unpaid",
    ]);
  });

  it("mobile (sans Origin) + compte en base staging → clé TEST", async () => {
    // Le doc landlord n'existe que dans la fausse base staging : c'est ce que
    // `dbForRequest` interprète comme « compte de staging ».
    fakeStagingDb.seed(`landlords/${LANDLORD_A}`, {
      id: LANDLORD_A,
      ...WEB_BILLING,
    });
    fakeStagingDb.seed("properties/prop-s1", {landlordId: LANDLORD_A});
    stripeMock.search.mockResolvedValue({data: [activeSub]});

    const result = await deleteAccount.run(makeRequest(LANDLORD_A));

    expect(stripeMock.keys).toEqual([TEST_KEY]);
    expect(stripeMock.cancel).toHaveBeenCalledWith("sub_active");
    expect(result).toMatchObject({deleted: true});
    expect(fakeStagingDb.peek(`landlords/${LANDLORD_A}`)).toBeUndefined();
  });

  it("mobile (sans Origin) + compte en base prod → clé LIVE", async () => {
    seedLandlordDataset(LANDLORD_A, "a1", WEB_BILLING);
    stripeMock.search.mockResolvedValue({data: [activeSub]});

    await deleteAccount.run(makeRequest(LANDLORD_A));

    expect(stripeMock.keys).toEqual([LIVE_KEY]);
    expect(stripeMock.cancel).toHaveBeenCalledWith("sub_active");
  });

  it("aucun abonnement → aucun cancel, purge effectuée", async () => {
    seedLandlordDataset(LANDLORD_A, "a1", WEB_BILLING);

    const result = await deleteAccount.run(
      makeRequest(LANDLORD_A, {origin: PROD_ORIGIN}),
    );

    expect(stripeMock.search).toHaveBeenCalledTimes(1);
    expect(stripeMock.cancel).not.toHaveBeenCalled();
    expect(result).toMatchObject({deleted: true});
    expect(fakeDb.peek(`landlords/${LANDLORD_A}`)).toBeUndefined();
  });

  it("cancel qui échoue → 'internal' et RIEN n'est purgé (l'utilisateur peut relancer)", async () => {
    seedLandlordDataset(LANDLORD_A, "a1", WEB_BILLING);
    stripeMock.search.mockResolvedValue({data: [activeSub]});
    stripeMock.cancel.mockRejectedValue(new Error("stripe unavailable"));

    await expect(
      deleteAccount.run(makeRequest(LANDLORD_A, {origin: PROD_ORIGIN})),
    ).rejects.toMatchObject({code: "internal"});

    expect(fakeDb.peek(`landlords/${LANDLORD_A}`)).toBeDefined();
    expect(fakeDb.peek("properties/prop-a1")).toBeDefined();
    expect(fakeDb.peek("receipts/rcpt-a1")?.accountDeletedAt).toBeUndefined();
    expect(fakeStorage.deletedPrefixes).toHaveLength(0);
    expect(fakeAuth.deletedUids).toHaveLength(0);
  });

  it("ne journalise jamais la clé Stripe ni le message brut de l'erreur", async () => {
    seedLandlordDataset(LANDLORD_A, "a1", WEB_BILLING);
    stripeMock.search.mockResolvedValue({data: [activeSub]});
    // Une erreur Stripe peut citer un fragment de clé dans son message.
    stripeMock.cancel.mockRejectedValue(
      Object.assign(new Error(`Invalid API Key provided: ${LIVE_KEY}`), {
        type: "StripeAuthenticationError",
        statusCode: 401,
      }),
    );
    const logged: unknown[] = [];
    const spies = (["error", "info", "warn"] as const).map((level) =>
      vi.spyOn(logger, level).mockImplementation((...args: unknown[]) => {
        logged.push(args);
      }),
    );

    await expect(
      deleteAccount.run(makeRequest(LANDLORD_A, {origin: PROD_ORIGIN})),
    ).rejects.toMatchObject({code: "internal"});
    spies.forEach((spy) => spy.mockRestore());

    const blob = JSON.stringify(logged);
    expect(blob).toContain(LANDLORD_A);
    expect(blob).toContain("StripeAuthenticationError");
    expect(blob).not.toContain(LIVE_KEY);
    expect(blob).not.toContain("Invalid API Key");
  });

  it("recherche Stripe en échec → 'internal' et RIEN n'est purgé", async () => {
    seedLandlordDataset(LANDLORD_A, "a1", WEB_BILLING);
    stripeMock.search.mockRejectedValue(new Error("stripe unavailable"));

    await expect(
      deleteAccount.run(makeRequest(LANDLORD_A, {origin: PROD_ORIGIN})),
    ).rejects.toMatchObject({code: "internal"});

    expect(fakeDb.peek(`landlords/${LANDLORD_A}`)).toBeDefined();
    expect(fakeAuth.deletedUids).toHaveLength(0);
  });

  // Décision utilisateur (2026-09-30) : la clé suit la SEULE base routée,
  // jamais l'Origin. L'allowlist d'origines refusait l'URL Firebase Hosting de
  // prod (page de suppression déclarée aux stores) → boucle « session trop
  // ancienne » ; et localhost obtenait la clé TEST contre la base de prod.
  it("Origin inconnu (URL Firebase Hosting de prod) + base prod → clé LIVE, abonnement résilié", async () => {
    seedLandlordDataset(LANDLORD_A, "a1", WEB_BILLING);
    stripeMock.search.mockResolvedValue({data: [activeSub]});

    const result = await deleteAccount.run(
      makeRequest(LANDLORD_A, {origin: "https://easy-rent-54cd4.web.app"}),
    );

    expect(stripeMock.keys).toEqual([LIVE_KEY]);
    expect(stripeMock.cancel).toHaveBeenCalledWith("sub_active");
    expect(result).toMatchObject({deleted: true});
    expect(fakeDb.peek(`landlords/${LANDLORD_A}`)).toBeUndefined();
  });

  it("Origin localhost + base prod → clé LIVE (la base décide, pas l'Origin)", async () => {
    seedLandlordDataset(LANDLORD_A, "a1", WEB_BILLING);
    stripeMock.search.mockResolvedValue({data: [activeSub]});

    await deleteAccount.run(
      makeRequest(LANDLORD_A, {origin: "http://localhost:5000"}),
    );

    expect(stripeMock.keys).toEqual([LIVE_KEY]);
    expect(stripeMock.cancel).toHaveBeenCalledWith("sub_active");
  });

  it("Origin staging → base staging → clé TEST (#138 : jamais la live)", async () => {
    fakeStagingDb.seed(`landlords/${LANDLORD_A}`, {
      id: LANDLORD_A,
      ...WEB_BILLING,
    });
    stripeMock.search.mockResolvedValue({data: [activeSub]});

    const result = await deleteAccount.run(
      makeRequest(LANDLORD_A, {origin: "https://app.staging.baillan.com"}),
    );

    expect(stripeMock.keys).toEqual([TEST_KEY]);
    expect(stripeMock.cancel).toHaveBeenCalledWith("sub_active");
    expect(result).toMatchObject({deleted: true});
    expect(fakeStagingDb.peek(`landlords/${LANDLORD_A}`)).toBeUndefined();
  });

  it("uid malformé (apostrophe) → invalid-argument, jamais interpolé dans la requête Stripe, rien n'est purgé", async () => {
    const evilUid = "x' OR metadata['a']:'b";
    fakeDb.seed(`landlords/${evilUid}`, {id: evilUid, ...WEB_BILLING});

    await expect(
      deleteAccount.run(makeRequest(evilUid, {origin: PROD_ORIGIN})),
    ).rejects.toMatchObject({code: "invalid-argument"});

    expect(stripeMock.search).not.toHaveBeenCalled();
    expect(fakeDb.peek(`landlords/${evilUid}`)).toBeDefined();
    expect(fakeAuth.deletedUids).toHaveLength(0);
  });

  it("émulateur Functions → aucun appel Stripe, purge effectuée", async () => {
    seedLandlordDataset(LANDLORD_A, "a1", WEB_BILLING);
    vi.stubEnv("FUNCTIONS_EMULATOR", "true");
    stripeMock.search.mockResolvedValue({data: [activeSub]});

    const result = await deleteAccount.run(makeRequest(LANDLORD_A));

    expect(stripeMock.keys).toHaveLength(0);
    expect(stripeMock.search).not.toHaveBeenCalled();
    expect(stripeMock.cancel).not.toHaveBeenCalled();
    expect(result).toMatchObject({deleted: true});
    expect(fakeDb.peek(`landlords/${LANDLORD_A}`)).toBeUndefined();
  });
});

// Contrôleur : la suppression d'un compte ne doit pas dépendre de la config
// Stripe quand le compte n'a jamais été facturé par Stripe. Un secret mal posé
// (ex. clé test dans le slot live) ne doit bloquer QUE les comptes facturés web.
describe("deleteAccount — la résiliation Stripe ne vise que les comptes facturés sur le web", () => {
  const MISCONFIGURED_LIVE = "sk_test_COLLEE_DANS_LE_SLOT_LIVE";

  it("compte gratuit + secrets mal configurés → aucun appel Stripe, suppression réussie", async () => {
    seedLandlordDataset(LANDLORD_A, "a1", {
      subscriptionTier: "free",
      proStore: null,
    });
    vi.stubEnv("STRIPE_SECRET_KEY", MISCONFIGURED_LIVE);
    vi.stubEnv("STRIPE_SECRET_KEY_TEST", "");

    const result = await deleteAccount.run(
      makeRequest(LANDLORD_A, {origin: PROD_ORIGIN}),
    );

    expect(stripeMock.keys).toHaveLength(0);
    expect(stripeMock.search).not.toHaveBeenCalled();
    expect(result).toMatchObject({deleted: true});
    expect(fakeDb.peek(`landlords/${LANDLORD_A}`)).toBeUndefined();
    expect(fakeAuth.deletedUids).toEqual([LANDLORD_A]);
  });

  it("abonné App Store / Play Store (aucune facturation web) → Stripe non sollicité", async () => {
    seedLandlordDataset(LANDLORD_A, "a1", {
      proStore: "app_store",
      entitlements: {pro: {active: true, store: "app_store"}},
    });
    vi.stubEnv("STRIPE_SECRET_KEY", MISCONFIGURED_LIVE);

    const result = await deleteAccount.run(makeRequest(LANDLORD_A));

    expect(stripeMock.keys).toHaveLength(0);
    expect(result).toMatchObject({deleted: true});
  });

  it("doc landlord absent (relance après une suppression déjà menée à terme) → Stripe non sollicité", async () => {
    // Aucun doc landlord dans aucune base : `dbForLandlordUid` retombe sur la
    // prod, où il n'y a plus rien à résilier.
    vi.stubEnv("STRIPE_SECRET_KEY", "");
    vi.stubEnv("STRIPE_SECRET_KEY_TEST", "");

    const result = await deleteAccount.run(makeRequest(LANDLORD_A));

    expect(stripeMock.keys).toHaveLength(0);
    expect(result).toMatchObject({deleted: true});
    expect(fakeAuth.deletedUids).toEqual([LANDLORD_A]);
  });

  it("proStore 'web' seul (doc d'avant les paliers, sans map entitlements) → chemin Stripe", async () => {
    seedLandlordDataset(LANDLORD_A, "a1", {proStore: "web"});
    stripeMock.search.mockResolvedValue({
      data: [{id: "sub_legacy", status: "active"}],
    });

    await deleteAccount.run(makeRequest(LANDLORD_A, {origin: PROD_ORIGIN}));

    expect(stripeMock.keys).toEqual([LIVE_KEY]);
    expect(stripeMock.cancel).toHaveBeenCalledWith("sub_legacy");
  });

  it("proStore null mais un entitlement web EXPIRÉ dans la map → chemin Stripe", async () => {
    // Le webhook garde l'état expiré dans `entitlements` tandis que `proStore`
    // (miroir du palier effectif) redevient null : Stripe peut encore facturer
    // (past_due/unpaid) et doit être résilié.
    seedLandlordDataset(LANDLORD_A, "a1", {
      proStore: null,
      entitlements: {pro: {active: false, store: "web", expiresAt: new Date(0)}},
    });
    stripeMock.search.mockResolvedValue({
      data: [{id: "sub_due", status: "past_due"}],
    });

    await deleteAccount.run(makeRequest(LANDLORD_A, {origin: PROD_ORIGIN}));

    expect(stripeMock.keys).toEqual([LIVE_KEY]);
    expect(stripeMock.cancel).toHaveBeenCalledWith("sub_due");
  });

  it("compte web + clé de mode incorrect → 'internal' (pas 'failed-precondition'), journalisé, rien purgé", async () => {
    // Le client mappe TOUT `failed-precondition` sur « reconnectez-vous » : une
    // erreur de configuration serveur ne doit pas le déclencher.
    seedLandlordDataset(LANDLORD_A, "a1", WEB_BILLING);
    vi.stubEnv("STRIPE_SECRET_KEY", MISCONFIGURED_LIVE);
    const logged: unknown[] = [];
    const spy = vi.spyOn(logger, "error").mockImplementation(
      (...args: unknown[]) => {
        logged.push(args);
      },
    );

    await expect(
      deleteAccount.run(makeRequest(LANDLORD_A, {origin: PROD_ORIGIN})),
    ).rejects.toMatchObject({
      code: "internal",
      message: "subscription cancel failed — retry",
    });
    spy.mockRestore();

    const blob = JSON.stringify(logged);
    expect(blob).toContain(LANDLORD_A);
    expect(blob).toContain("stripe_key_mode_mismatch_live");
    expect(blob).not.toContain(MISCONFIGURED_LIVE);
    expect(stripeMock.keys).toHaveLength(0);
    expect(fakeDb.peek(`landlords/${LANDLORD_A}`)).toBeDefined();
    expect(fakeAuth.deletedUids).toHaveLength(0);
  });

  it("compte web staging (mobile) + clé test absente → 'internal' journalisé, rien purgé", async () => {
    fakeStagingDb.seed(`landlords/${LANDLORD_A}`, {
      id: LANDLORD_A,
      ...WEB_BILLING,
    });
    vi.stubEnv("STRIPE_SECRET_KEY_TEST", "");
    const logged: unknown[] = [];
    const spy = vi.spyOn(logger, "error").mockImplementation(
      (...args: unknown[]) => {
        logged.push(args);
      },
    );

    await expect(
      deleteAccount.run(makeRequest(LANDLORD_A)),
    ).rejects.toMatchObject({code: "internal"});
    spy.mockRestore();

    expect(JSON.stringify(logged)).toContain("stripe_test_key_not_configured");
    expect(fakeStagingDb.peek(`landlords/${LANDLORD_A}`)).toBeDefined();
  });

  it("erreur non-Stripe → journal avec son `name`, jamais son message", async () => {
    seedLandlordDataset(LANDLORD_A, "a1", WEB_BILLING);
    stripeMock.search.mockRejectedValue(
      new TypeError(`fetch failed near ${LIVE_KEY}`),
    );
    const logged: unknown[] = [];
    vi.spyOn(logger, "error").mockImplementation((...args: unknown[]) => {
      logged.push(args);
    });

    await expect(
      deleteAccount.run(makeRequest(LANDLORD_A, {origin: PROD_ORIGIN})),
    ).rejects.toMatchObject({code: "internal"});

    const blob = JSON.stringify(logged);
    expect(blob).toContain("TypeError");
    expect(blob).not.toContain("fetch failed");
    expect(blob).not.toContain(LIVE_KEY);
  });

  it("lecture du doc landlord en échec → 'internal', journalisée comme telle (pas comme un échec Stripe), rien purgé", async () => {
    seedLandlordDataset(LANDLORD_A, "a1", WEB_BILLING);
    const realDoc = fakeDb.doc.bind(fakeDb);
    vi.spyOn(fakeDb, "doc").mockImplementation((path: string) =>
      path === `landlords/${LANDLORD_A}` ?
        ({
          get: () => Promise.reject(new Error("firestore unavailable")),
        } as unknown as ReturnType<typeof realDoc>) :
        realDoc(path),
    );
    const logged: unknown[] = [];
    vi.spyOn(logger, "error").mockImplementation((...args: unknown[]) => {
      logged.push(args);
    });

    await expect(
      deleteAccount.run(makeRequest(LANDLORD_A, {origin: PROD_ORIGIN})),
    ).rejects.toMatchObject({code: "internal"});

    const blob = JSON.stringify(logged);
    expect(blob).toContain("billing lookup failed");
    expect(blob).not.toContain("Stripe cancellation failed");
    expect(blob).not.toContain("firestore unavailable");
    expect(stripeMock.keys).toHaveLength(0);
    expect(fakeDb.peek(`landlords/${LANDLORD_A}`)).toBeDefined();
    expect(fakeAuth.deletedUids).toHaveLength(0);
  });
});

// Parité export ↔ effacement (RGPD art. 15/20 vs art. 17, OWASP-05) : toute
// collection que `exportAccountData` sait lire contient des données du
// bailleur — elle doit être soit purgée, soit explicitement retenue. Ce test
// aurait attrapé `charge_statements` (FEAT-033) et `etat_des_lieux` (FEAT-037),
// exportés mais jamais effacés.
describe("parité export ↔ effacement du compte", () => {
  const exported = Object.values(EXPORTED_COLLECTIONS);

  it("toute collection exportée est purgée OU explicitement retenue", () => {
    const covered = new Set([...PURGED_COLLECTIONS, ...RETAINED_COLLECTIONS]);
    const uncovered = exported.filter((name) => !covered.has(name));

    expect(
      uncovered,
      `exportées mais ni purgées ni retenues : ${uncovered.join(", ")}`,
    ).toEqual([]);
  });

  it("une collection ne peut pas être à la fois purgée et retenue", () => {
    const both = PURGED_COLLECTIONS.filter((name) =>
      RETAINED_COLLECTIONS.includes(name),
    );
    expect(both).toEqual([]);
  });

  it("seules les quittances sont retenues (rétention légale 5 ans)", () => {
    expect([...RETAINED_COLLECTIONS]).toEqual(["receipts"]);
  });

  it("toute collection de premier niveau des Security Rules est exportée ou est un singleton purgé", () => {
    // Filet en amont de la parité : une collection ajoutée aux Rules mais
    // oubliée dans l'export échapperait au test précédent.
    const rules = fs.readFileSync(
      resolve(__dirname, "../../../firestore.rules"),
      "utf8",
    );
    const topLevel = [...rules.matchAll(/^ {4}match \/(\w+)\/\{/gm)].map(
      (m) => m[1],
    );
    // Singletons clés par uid (purgés explicitement par deleteAccount, étape c).
    const singletons = ["landlords", "paid_plan_interest"];
    // Configuration serveur globale (FEAT-044e `_ops/sandboxAllowlist`) : aucune
    // donnée de bailleur, refusée à tout client — rien à exporter ni à purger.
    const globalConfig = ["_ops"];
    const known = new Set([...exported, ...singletons, ...globalConfig]);

    expect(topLevel.length).toBeGreaterThan(10); // le scan a bien lu les Rules
    const unknown = topLevel.filter((name) => !known.has(name));
    expect(
      unknown,
      `collections des Rules ni exportées ni singletons : ${unknown.join(", ")}`,
    ).toEqual([]);
  });
});

describe("hasWebBilling", () => {
  it("doc absent / vide → false", () => {
    expect(hasWebBilling(undefined)).toBe(false);
    expect(hasWebBilling(null)).toBe(false);
    expect(hasWebBilling({})).toBe(false);
  });

  it("proStore 'web' → true", () => {
    expect(hasWebBilling({proStore: "web"})).toBe(true);
  });

  it("proStore d'un store mobile ou null → false", () => {
    expect(hasWebBilling({proStore: "app_store"})).toBe(false);
    expect(hasWebBilling({proStore: "play_store"})).toBe(false);
    expect(hasWebBilling({proStore: "promo"})).toBe(false);
    expect(hasWebBilling({proStore: null})).toBe(false);
  });

  it("n'importe quel palier de la map entitlements en 'web' (actif OU expiré) → true", () => {
    expect(
      hasWebBilling({
        proStore: null,
        entitlements: {
          pro: {active: false, store: "web"},
        },
      }),
    ).toBe(true);
    expect(
      hasWebBilling({
        proStore: "app_store",
        entitlements: {
          pro: {active: true, store: "app_store"},
          max: {active: false, store: "web"},
        },
      }),
    ).toBe(true);
  });

  it("entitlements sans aucun palier web → false", () => {
    expect(
      hasWebBilling({
        entitlements: {
          pro: {active: true, store: "play_store"},
          max: {active: false, store: null},
        },
      }),
    ).toBe(false);
  });

  it("formes inattendues → false, jamais d'exception", () => {
    expect(hasWebBilling({entitlements: "web"})).toBe(false);
    expect(hasWebBilling({entitlements: null})).toBe(false);
    expect(hasWebBilling({entitlements: {pro: null}})).toBe(false);
    expect(hasWebBilling({entitlements: {pro: "web"}})).toBe(false);
    expect(hasWebBilling({proStore: 42})).toBe(false);
  });

  // Verrou anti-dérive avec le SEUL écrivain de `proStore` / `entitlements.*.store`
  // (le webhook RevenueCat) : si `storeOf` renomme sa valeur « web », ce test
  // casse au lieu de laisser des abonnés Stripe non résiliés en silence.
  it("reconnaît les valeurs que le webhook écrit pour Stripe / RC Billing", () => {
    for (const rcStore of ["STRIPE", "RC_BILLING"]) {
      const store = storeOf(rcStore);
      expect(hasWebBilling({proStore: store}), rcStore).toBe(true);
      expect(hasWebBilling({entitlements: {pro: {store}}}), rcStore).toBe(true);
    }
    for (const rcStore of ["APP_STORE", "MAC_APP_STORE", "PLAY_STORE", "PROMOTIONAL"]) {
      expect(hasWebBilling({proStore: storeOf(rcStore)}), rcStore).toBe(false);
    }
  });
});
