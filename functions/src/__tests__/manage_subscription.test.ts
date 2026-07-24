import {describe, expect, it} from "vitest";

import {
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
