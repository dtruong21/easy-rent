import {Timestamp} from "firebase-admin/firestore";
import {logger} from "firebase-functions/v2";
import type {CallableRequest} from "firebase-functions/v2/https";
import {afterEach, beforeEach, describe, expect, it, vi} from "vitest";

import {deleteAccount} from "../callable/delete_account";

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
function seedLandlordDataset(uid: string, suffix: string) {
  fakeDb.seed(`landlords/${uid}`, {id: uid, email: `${uid}@x.fr`});
  fakeDb.seed(`paid_plan_interest/${uid}`, {uid, features: ["reminders"]});
  fakeDb.seed(`properties/prop-${suffix}`, {landlordId: uid, name: "Bien"});
  fakeDb.seed(`tenants/ten-${suffix}`, {landlordId: uid, lastName: "Doe"});
  fakeDb.seed(`leases/lease-${suffix}`, {landlordId: uid, status: "active"});
  fakeDb.seed(`payments/pay-${suffix}`, {landlordId: uid, amountCents: 100});
  fakeDb.seed(`documents/doc-${suffix}`, {landlordId: uid, legalHold: true});
  fakeDb.seed(`expenses/exp-${suffix}`, {landlordId: uid, amountCents: 500});
  fakeDb.seed(`investment_scenarios/sc-${suffix}`, {landlordId: uid});
  fakeDb.seed(`support_requests/sup-${suffix}`, {landlordId: uid});
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
});

describe("deleteAccount", () => {
  it("refuse un appel non authentifié", async () => {
    await expect(
      deleteAccount.run(makeRequest(null)),
    ).rejects.toMatchObject({code: "unauthenticated"});
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
    seedLandlordDataset(LANDLORD_A, "a1");
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
    seedLandlordDataset(LANDLORD_A, "a1");
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
    fakeStagingDb.seed(`landlords/${LANDLORD_A}`, {id: LANDLORD_A});
    fakeStagingDb.seed("properties/prop-s1", {landlordId: LANDLORD_A});
    stripeMock.search.mockResolvedValue({data: [activeSub]});

    const result = await deleteAccount.run(makeRequest(LANDLORD_A));

    expect(stripeMock.keys).toEqual([TEST_KEY]);
    expect(stripeMock.cancel).toHaveBeenCalledWith("sub_active");
    expect(result).toMatchObject({deleted: true});
    expect(fakeStagingDb.peek(`landlords/${LANDLORD_A}`)).toBeUndefined();
  });

  it("mobile (sans Origin) + compte en base prod → clé LIVE", async () => {
    seedLandlordDataset(LANDLORD_A, "a1");
    stripeMock.search.mockResolvedValue({data: [activeSub]});

    await deleteAccount.run(makeRequest(LANDLORD_A));

    expect(stripeMock.keys).toEqual([LIVE_KEY]);
    expect(stripeMock.cancel).toHaveBeenCalledWith("sub_active");
  });

  it("aucun abonnement → aucun cancel, purge effectuée", async () => {
    seedLandlordDataset(LANDLORD_A, "a1");

    const result = await deleteAccount.run(
      makeRequest(LANDLORD_A, {origin: PROD_ORIGIN}),
    );

    expect(stripeMock.search).toHaveBeenCalledTimes(1);
    expect(stripeMock.cancel).not.toHaveBeenCalled();
    expect(result).toMatchObject({deleted: true});
    expect(fakeDb.peek(`landlords/${LANDLORD_A}`)).toBeUndefined();
  });

  it("cancel qui échoue → 'internal' et RIEN n'est purgé (l'utilisateur peut relancer)", async () => {
    seedLandlordDataset(LANDLORD_A, "a1");
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
    seedLandlordDataset(LANDLORD_A, "a1");
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
    seedLandlordDataset(LANDLORD_A, "a1");
    stripeMock.search.mockRejectedValue(new Error("stripe unavailable"));

    await expect(
      deleteAccount.run(makeRequest(LANDLORD_A, {origin: PROD_ORIGIN})),
    ).rejects.toMatchObject({code: "internal"});

    expect(fakeDb.peek(`landlords/${LANDLORD_A}`)).toBeDefined();
    expect(fakeAuth.deletedUids).toHaveLength(0);
  });

  it("Origin inattendu → failed-precondition origin_not_allowed, rien n'est purgé", async () => {
    seedLandlordDataset(LANDLORD_A, "a1");

    await expect(
      deleteAccount.run(makeRequest(LANDLORD_A, {origin: "https://evil.tld"})),
    ).rejects.toMatchObject({
      code: "failed-precondition",
      message: "origin_not_allowed",
    });

    expect(stripeMock.search).not.toHaveBeenCalled();
    expect(fakeDb.peek(`landlords/${LANDLORD_A}`)).toBeDefined();
    expect(fakeAuth.deletedUids).toHaveLength(0);
  });

  it("uid malformé (apostrophe) → invalid-argument, jamais interpolé dans la requête Stripe, rien n'est purgé", async () => {
    const evilUid = "x' OR metadata['a']:'b";
    fakeDb.seed(`landlords/${evilUid}`, {id: evilUid});

    await expect(
      deleteAccount.run(makeRequest(evilUid, {origin: PROD_ORIGIN})),
    ).rejects.toMatchObject({code: "invalid-argument"});

    expect(stripeMock.search).not.toHaveBeenCalled();
    expect(fakeDb.peek(`landlords/${evilUid}`)).toBeDefined();
    expect(fakeAuth.deletedUids).toHaveLength(0);
  });

  it("émulateur Functions → aucun appel Stripe, purge effectuée", async () => {
    seedLandlordDataset(LANDLORD_A, "a1");
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
