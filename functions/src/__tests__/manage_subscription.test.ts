import {describe, expect, it} from "vitest";

import {
  assertSafeUid,
  parseAction,
  pickManageableSubscription,
  planSubscriptionUpdate,
  type ManageableSubscriptionLike,
} from "../callable/manage_subscription";

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
});
