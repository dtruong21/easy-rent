import {beforeEach, describe, expect, it, vi} from "vitest";

import {purgeExpiredReceiptsImpl} from "../scheduled/purge_expired_receipts";

import {
  FakeFirestore,
  fakeAdminFirestoreHolder,
} from "./helpers/fake_firestore";

vi.mock("firebase-admin", async () => {
  const {makeFakeAdminModule} = await import("./helpers/fake_firestore");
  return makeFakeAdminModule();
});

let fakeDb: FakeFirestore;

/** Invoque la logique pure avec le fake db et « maintenant ». */
function runCron(): Promise<number> {
  return purgeExpiredReceiptsImpl(
    fakeDb as never,
    new Date() as never,
  );
}

const PAST = new Date(Date.now() - 1000);
const FUTURE = new Date(Date.now() + 100 * 365 * 24 * 60 * 60 * 1000);

function seedReceipt(id: string, retentionUntil?: Date) {
  fakeDb.seed(`receipts/${id}`, {
    id,
    landlordId: "l1",
    ...(retentionUntil ? {retentionUntil} : {}),
  });
}

beforeEach(() => {
  fakeDb = new FakeFirestore();
  fakeAdminFirestoreHolder.db = fakeDb;
});

describe("purgeExpiredReceipts", () => {
  it("supprime les quittances dont retentionUntil est passé", async () => {
    seedReceipt("r1", PAST);
    seedReceipt("r2", PAST);

    await runCron();

    expect(fakeDb.peek("receipts/r1")).toBeUndefined();
    expect(fakeDb.peek("receipts/r2")).toBeUndefined();
  });

  it("épargne les quittances dont retentionUntil est futur", async () => {
    seedReceipt("r-future", FUTURE);

    await runCron();

    expect(fakeDb.peek("receipts/r-future")).toBeDefined();
  });

  it("épargne les quittances sans retentionUntil (compte actif)", async () => {
    seedReceipt("r-active"); // pas de champ retentionUntil

    await runCron();

    expect(fakeDb.peek("receipts/r-active")).toBeDefined();
  });

  it("purge au-delà d'une page (pagination multi-batch)", async () => {
    for (let i = 0; i < 405; i++) seedReceipt(`r${i}`, PAST);

    await runCron();

    expect(fakeDb.peek("receipts/r0")).toBeUndefined();
    expect(fakeDb.peek("receipts/r404")).toBeUndefined();
  });

  it("run sans donnée ne lève pas", async () => {
    await expect(runCron()).resolves.not.toThrow();
  });
});
