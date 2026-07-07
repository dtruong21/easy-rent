import type {CallableRequest} from "firebase-functions/v2/https";
import {beforeEach, describe, expect, it, vi} from "vitest";

import {deleteAccount} from "../callable/delete_account";

import {
  FakeAuthAdmin,
  FakeFirestore,
  FakeStorage,
  fakeAdminFirestoreHolder,
} from "./helpers/fake_firestore";

// Cf. expenses.test.ts pour la justification du import() dynamique interne
// (le factory `vi.mock` est hoisted au-dessus des imports du fichier).
vi.mock("firebase-admin", async () => {
  const {makeFakeAdminModule} = await import("./helpers/fake_firestore");
  return makeFakeAdminModule();
});

let fakeDb: FakeFirestore;
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
  }: {authTime?: number; signInProvider?: string} = {},
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
    rawRequest: {} as never,
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
  fakeStorage = new FakeStorage();
  fakeAuth = new FakeAuthAdmin();
  fakeAdminFirestoreHolder.db = fakeDb;
  fakeAdminFirestoreHolder.storage = fakeStorage;
  fakeAdminFirestoreHolder.authAdmin = fakeAuth;
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
    expect(receipt?.retentionUntil).toBeInstanceOf(Date);
    // retentionUntil ≈ maintenant + 5 ans (tolérance 1 jour).
    const fiveYearsMs = 5 * 365.25 * 24 * 60 * 60 * 1000;
    const delta = Math.abs(
      (receipt?.retentionUntil as Date).getTime() -
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
});
