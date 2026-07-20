import {beforeEach, describe, expect, it, vi} from "vitest";

import {
  applyRevenueCatEvent,
  decideEntitlement,
  isAuthorizedWebhook,
  PRO_ENTITLEMENT_ID,
  storeOf,
  type RcEvent,
} from "../http/revenuecat_webhook";

import {FakeFirestore, fakeAdminFirestoreHolder} from "./helpers/fake_firestore";

vi.mock("firebase-admin", async () => {
  const {makeFakeAdminModule} = await import("./helpers/fake_firestore");
  return makeFakeAdminModule();
});

let fakeDb: FakeFirestore;

const UID = "landlord-pro";
const NOW = Date.UTC(2026, 5, 15); // 2026-06-15
const IN_30D = NOW + 30 * 24 * 3600 * 1000;
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
    entitlement_ids: [PRO_ENTITLEMENT_ID],
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
