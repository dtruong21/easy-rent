import {describe, expect, it} from "vitest";

import {
  selectPriceTable,
  type PriceTable,
} from "../entitlements/stripe_prices";

// Reliquat de #138 (suivi #207) : un price ID n'existe que dans le mode Stripe
// où il a été créé. La table de prix suit donc le mode de la clé — prix live
// pour la prod, prix `…_TEST` pour le staging / l'émulateur.
describe("selectPriceTable — prix par environnement Stripe", () => {
  const live: PriceTable = {
    pro_monthly: "price_live_pro_m",
    pro_annual: "price_live_pro_a",
  };

  it("live → uniquement les prix canoniques (jamais un prix de test)", () => {
    const table = selectPriceTable("live", live, {
      pro_monthly: "price_test_pro_m",
    });
    expect(table.pro_monthly).toBe("price_live_pro_m");
    expect(table.pro_annual).toBe("price_live_pro_a");
  });

  it("test → les prix …_TEST quand ils sont posés", () => {
    const table = selectPriceTable("test", live, {
      pro_monthly: "price_test_pro_m",
      pro_annual: "price_test_pro_a",
    });
    expect(table.pro_monthly).toBe("price_test_pro_m");
    expect(table.pro_annual).toBe("price_test_pro_a");
  });

  it("test → repli transitoire sur le prix canonique, offre par offre", () => {
    // Aujourd'hui (aucune clé live), les paramètres canoniques portent des
    // prix de test : le staging doit marcher sans reconfiguration.
    const table = selectPriceTable("test", live, {
      pro_monthly: "price_test_pro_m",
      pro_annual: "   ",
    });
    expect(table.pro_monthly).toBe("price_test_pro_m");
    expect(table.pro_annual).toBe("price_live_pro_a");
  });

  it("test sans aucun prix de test ni canonique → offre vide (price_not_configured en aval)", () => {
    const table = selectPriceTable("test", {}, {});
    expect(table.max_monthly ?? "").toBe("");
  });
});
