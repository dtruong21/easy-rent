import {describe, expect, it} from "vitest";

import {
  buildCheckoutSessionParams,
  RC_APP_USER_ID_METADATA_KEY,
  type CheckoutConfig,
} from "../callable/create_checkout_session";

const config: CheckoutConfig = {
  priceMonthly: "price_monthly_123",
  priceAnnual: "price_annual_456",
  baseUrl: "https://app.test",
};

describe("buildCheckoutSessionParams", () => {
  it("mode subscription + bon price mensuel", () => {
    const p = buildCheckoutSessionParams({uid: "u1", plan: "monthly", config});
    expect(p.mode).toBe("subscription");
    expect(p.line_items).toEqual([{price: "price_monthly_123", quantity: 1}]);
  });

  it("plan annuel → price annuel", () => {
    const p = buildCheckoutSessionParams({uid: "u1", plan: "annual", config});
    expect(p.line_items?.[0]).toMatchObject({price: "price_annual_456"});
  });

  it("★ App User ID (UID) posé en metadata de la SESSION ET de la subscription", () => {
    // Le linchpin RevenueCat : sans la metadata aux deux endroits, l'abonnement
    // Stripe ne serait pas rattaché au bon compte.
    const p = buildCheckoutSessionParams({uid: "landlord-42", plan: "monthly", config});
    expect(p.metadata?.[RC_APP_USER_ID_METADATA_KEY]).toBe("landlord-42");
    const subMeta = p.subscription_data?.metadata as Record<string, unknown>;
    expect(subMeta[RC_APP_USER_ID_METADATA_KEY]).toBe("landlord-42");
    // client_reference_id en ceinture+bretelles.
    expect(p.client_reference_id).toBe("landlord-42");
  });

  it("success/cancel URLs dérivées du base URL (avec placeholder session)", () => {
    const p = buildCheckoutSessionParams({uid: "u1", plan: "monthly", config});
    expect(p.success_url).toBe(
      "https://app.test/pro/success?session_id={CHECKOUT_SESSION_ID}",
    );
    expect(p.cancel_url).toBe("https://app.test/pro/cancel");
  });

  it("email client inclus si fourni, absent sinon", () => {
    expect(
      buildCheckoutSessionParams({
        uid: "u1",
        plan: "monthly",
        config,
        customerEmail: "jean@example.com",
      }).customer_email,
    ).toBe("jean@example.com");
    expect(
      buildCheckoutSessionParams({uid: "u1", plan: "monthly", config})
        .customer_email,
    ).toBeUndefined();
  });
});
