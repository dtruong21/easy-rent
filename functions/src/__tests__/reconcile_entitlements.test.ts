import {beforeEach, describe, expect, it, vi} from "vitest";

import {
  reconcileExpiredEntitlements,
  reconcileLandlord,
  type ProExpiryFetcher,
} from "../scheduled/reconcile_entitlements";

import {FakeFirestore, fakeAdminFirestoreHolder} from "./helpers/fake_firestore";

vi.mock("firebase-admin", async () => {
  const {makeFakeAdminModule} = await import("./helpers/fake_firestore");
  return makeFakeAdminModule();
});

let fakeDb: FakeFirestore;

const NOW = Date.UTC(2026, 5, 15);
const IN_30D = NOW + 30 * 24 * 3600 * 1000;
const AGO_1D = NOW - 24 * 3600 * 1000;

function seedActivePro(uid: string, expiresMs: number) {
  fakeDb.seed(`landlords/${uid}`, {
    id: uid,
    landlordId: uid,
    isAnonymous: false,
    subscriptionTier: "paid",
    proEntitlementActive: true,
    proWillRenew: true,
    proExpiresAt: new Date(expiresMs),
    deletedAt: null,
  });
}

beforeEach(() => {
  fakeDb = new FakeFirestore();
  fakeAdminFirestoreHolder.db = fakeDb;
});

describe("reconcileLandlord", () => {
  it("RevenueCat ne montre plus d'entitlement (null) → downgrade en free", async () => {
    seedActivePro("u1", AGO_1D);
    expect(await reconcileLandlord(fakeDb, "u1", null, NOW)).toBe("downgraded");
    const doc = fakeDb.peek("landlords/u1");
    expect(doc?.subscriptionTier).toBe("free");
    expect(doc?.proEntitlementActive).toBe(false);
    expect(doc?.proWillRenew).toBe(false);
  });

  it("RevenueCat montre une échéance passée → downgrade", async () => {
    seedActivePro("u1", AGO_1D);
    expect(await reconcileLandlord(fakeDb, "u1", AGO_1D, NOW)).toBe("downgraded");
    expect(fakeDb.peek("landlords/u1")?.subscriptionTier).toBe("free");
  });

  it("RevenueCat montre une échéance future (renouvellement manqué) → renewed", async () => {
    seedActivePro("u1", AGO_1D);
    expect(await reconcileLandlord(fakeDb, "u1", IN_30D, NOW)).toBe("renewed");
    const doc = fakeDb.peek("landlords/u1");
    expect(doc?.subscriptionTier).toBe("paid");
    expect(doc?.proExpiresAt).toEqual(new Date(IN_30D));
  });

  it("déjà inactif + RevenueCat null → unchanged", async () => {
    fakeDb.seed("landlords/u1", {
      id: "u1",
      subscriptionTier: "free",
      proEntitlementActive: false,
    });
    expect(await reconcileLandlord(fakeDb, "u1", null, NOW)).toBe("unchanged");
  });
});

describe("reconcileExpiredEntitlements", () => {
  it("ne traite que les échéances dépassées et corrige selon RevenueCat", async () => {
    seedActivePro("expired-gone", AGO_1D); // dépassé, RC dit null → downgrade
    seedActivePro("expired-renewed", AGO_1D); // dépassé, RC dit futur → renewed
    seedActivePro("still-active", IN_30D); // pas encore dû → ignoré

    const fetcher: ProExpiryFetcher = (uid) => {
      if (uid === "expired-gone") return Promise.resolve(null);
      if (uid === "expired-renewed") return Promise.resolve(IN_30D);
      // still-active est filtré avant tout fetch → ne devrait jamais arriver.
      return Promise.reject(new Error(`ne devrait pas fetch ${uid}`));
    };

    const res = await reconcileExpiredEntitlements(fakeDb, fetcher, NOW);
    expect(res).toEqual({checked: 2, downgraded: 1, renewed: 1, failed: 0});

    expect(fakeDb.peek("landlords/expired-gone")?.subscriptionTier).toBe("free");
    expect(fakeDb.peek("landlords/expired-renewed")?.subscriptionTier).toBe("paid");
    expect(fakeDb.peek("landlords/still-active")?.subscriptionTier).toBe("paid");
  });

  it("un échec de fetch est compté sans bloquer les autres", async () => {
    seedActivePro("ok", AGO_1D);
    seedActivePro("boom", AGO_1D);
    const fetcher: ProExpiryFetcher = (uid) => {
      if (uid === "boom") return Promise.reject(new Error("RevenueCat API 500"));
      return Promise.resolve(null);
    };
    const res = await reconcileExpiredEntitlements(fakeDb, fetcher, NOW);
    expect(res.failed).toBe(1);
    expect(res.downgraded).toBe(1);
    expect(fakeDb.peek("landlords/ok")?.subscriptionTier).toBe("free");
    // 'boom' reste inchangé → sera retenté au prochain run.
    expect(fakeDb.peek("landlords/boom")?.subscriptionTier).toBe("paid");
  });
});
