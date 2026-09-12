import {Timestamp} from "firebase-admin/firestore";
import type {CallableRequest} from "firebase-functions/v2/https";
import {beforeEach, describe, expect, it, vi} from "vitest";

import {exportAccountData} from "../callable/export_account_data";

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

/** Forme minimale du JSON renvoyé par `exportAccountData`, pour les assertions. */
interface ExportResult {
  account: {id: string} | null;
  paidPlanInterest: {id: string} | null;
  properties: Array<{id: string; name: string; createdAt?: string}>;
  payments: unknown[];
  schemaVersion: number;
  exportedAt: string;
}

let fakeDb: FakeFirestore;
let fakeAuth: FakeAuthAdmin;

const LANDLORD_A = "landlord-a";
const LANDLORD_B = "landlord-b";

const FRESH_AUTH_TIME = () => Math.floor(Date.now() / 1000);
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

beforeEach(() => {
  fakeDb = new FakeFirestore();
  fakeAuth = new FakeAuthAdmin();
  fakeAdminFirestoreHolder.db = fakeDb;
  fakeAdminFirestoreHolder.storage = new FakeStorage();
  fakeAdminFirestoreHolder.authAdmin = fakeAuth;

  fakeDb.seed(`landlords/${LANDLORD_A}`, {id: LANDLORD_A, email: "a@x.fr"});
  fakeDb.seed("properties/pa", {
    landlordId: LANDLORD_A,
    name: "Bien A",
    createdAt: Timestamp.fromDate(new Date("2026-01-01T00:00:00Z")),
  });
  fakeDb.seed("properties/pb", {landlordId: LANDLORD_B, name: "Bien B"});
  fakeDb.seed("payments/paya", {landlordId: LANDLORD_A, amountCents: 80000});
});

describe("exportAccountData", () => {
  it("renvoie les données du bailleur et EXCLUT celles d'un autre (cross-user)", async () => {
    const res = (await exportAccountData.run(
      makeRequest(LANDLORD_A),
    )) as ExportResult;

    expect(res.account?.id).toBe(LANDLORD_A);
    expect(res.properties.map((p) => p.name)).toContain("Bien A");
    expect(res.properties.map((p) => p.name)).not.toContain("Bien B");
    expect(res.payments).toHaveLength(1);
    expect(res.schemaVersion).toBe(1);
    expect(typeof res.exportedAt).toBe("string");
  });

  it("sérialise les Timestamp en chaînes ISO", async () => {
    const res = (await exportAccountData.run(
      makeRequest(LANDLORD_A),
    )) as ExportResult;

    const p = res.properties.find((prop) => prop.id === "pa");
    expect(p?.createdAt).toBe("2026-01-01T00:00:00.000Z");
  });

  it("singletons absents → null, pas d'erreur", async () => {
    const res = (await exportAccountData.run(
      makeRequest(LANDLORD_B),
    )) as ExportResult;

    expect(res.account).toBeNull();
    expect(res.paidPlanInterest).toBeNull();
  });

  it("compte non-anonyme au token trop vieux → recent-login-required", async () => {
    await expect(
      exportAccountData.run(
        makeRequest(LANDLORD_A, {authTime: STALE_AUTH_TIME()}),
      ),
    ).rejects.toMatchObject({
      code: "failed-precondition",
      message: "recent-login-required",
    });
  });

  it("compte anonyme → exempté de la garde de fraîcheur", async () => {
    // Par défaut FakeAuthAdmin.getUser renvoie providerData: [] pour tout uid
    // non renseigné dans providerDataByUid → confirmé anonyme.
    const res = (await exportAccountData.run(
      makeRequest(LANDLORD_A, {
        authTime: STALE_AUTH_TIME(),
        signInProvider: "anonymous",
      }),
    )) as ExportResult;

    expect(res.account?.id).toBe(LANDLORD_A);
  });
});
