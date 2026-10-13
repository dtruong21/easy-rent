import type {HttpsError} from "firebase-functions/v2/https";
import {describe, expect, it} from "vitest";

import {
  buildScenarioDocument,
  parseScenarioInputs,
} from "../callable/scenarios";
import {errorCodeFor, quotaLimit, resolvePlan} from "../entitlements/plan";
import {quotaEnforcement} from "../entitlements/plan_matrix.generated";

function thrownBy(fn: () => unknown): {code: string; message: string} {
  try {
    fn();
  } catch (e) {
    const err = e as HttpsError;
    return {code: err.code, message: err.message};
  }
  throw new Error("expected the call to throw");
}

/** Payload minimal accepté (miroir du chemin client du simulateur). */
const minimal = {
  name: "Studio Lyon 7",
  purchasePriceCents: 15_000_000,
  monthlyRentHcCents: 65_000,
};

describe("parseScenarioInputs — la callable est la seule gardienne de la forme", () => {
  it("payload minimal → défauts appliqués (miroir des défauts Dart)", () => {
    const inputs = parseScenarioInputs({...minimal});
    expect(inputs.name).toBe("Studio Lyon 7");
    expect(inputs.notes).toBeNull();
    expect(inputs.notaryFeesCents).toBe(0);
    expect(inputs.worksInitialCents).toBe(0);
    expect(inputs.isNewProperty).toBe(false);
    expect(inputs.downPaymentCents).toBe(0);
    expect(inputs.loanPrincipalCents).toBe(0);
    expect(inputs.loanRateBps).toBe(0);
    // 20 ans — défaut historique du simulateur.
    expect(inputs.loanDurationMonths).toBe(240);
  });

  it("payload complet → valeurs conservées", () => {
    const inputs = parseScenarioInputs({
      ...minimal,
      notes: "  bien vu  ",
      notaryFeesCents: 1_200_000,
      worksInitialCents: 500_000,
      isNewProperty: true,
      downPaymentCents: 3_000_000,
      loanPrincipalCents: 12_000_000,
      loanRateBps: 320,
      loanDurationMonths: 300,
      propertyTaxAnnualCents: 90_000,
      insurancePnoAnnualCents: 15_000,
      condoFeesNonRecoverableCents: 60_000,
    });
    expect(inputs.notes).toBe("bien vu");
    expect(inputs.isNewProperty).toBe(true);
    expect(inputs.loanDurationMonths).toBe(300);
    expect(inputs.condoFeesNonRecoverableCents).toBe(60_000);
  });

  it("nom vide / blanc → invalid-argument (contrainte reprise de la rule)", () => {
    expect(thrownBy(() => parseScenarioInputs({...minimal, name: "   "})).code)
      .toBe("invalid-argument");
    expect(() => parseScenarioInputs({...minimal, name: ""})).toThrow();
  });

  it("nom > 120 caractères → invalid-argument (contrainte reprise de la rule)", () => {
    expect(
      thrownBy(() => parseScenarioInputs({...minimal, name: "x".repeat(121)}))
        .code,
    ).toBe("invalid-argument");
    expect(() =>
      parseScenarioInputs({...minimal, name: "x".repeat(120)}),
    ).not.toThrow();
  });

  it("montants obligatoires manquants ou négatifs → invalid-argument", () => {
    expect(() => parseScenarioInputs({name: "A", monthlyRentHcCents: 1})).toThrow();
    expect(() => parseScenarioInputs({name: "A", purchasePriceCents: 1})).toThrow();
    expect(() =>
      parseScenarioInputs({...minimal, purchasePriceCents: -1}),
    ).toThrow();
    expect(() =>
      parseScenarioInputs({...minimal, monthlyRentHcCents: -1}),
    ).toThrow();
  });

  it("montant non entier → invalid-argument", () => {
    expect(() =>
      parseScenarioInputs({...minimal, purchasePriceCents: 1.5}),
    ).toThrow();
  });

  it("le client ne peut pas se choisir un landlordId ni un id", () => {
    // Les champs d'identité ne sont pas lus du payload : ils viennent de
    // l'UID authentifié et de la référence Firestore allouée côté serveur.
    const inputs = parseScenarioInputs({
      ...minimal,
      landlordId: "victime",
      id: "forge",
      deletedAt: null,
    });
    expect(Object.keys(inputs)).not.toContain("landlordId");
    expect(Object.keys(inputs)).not.toContain("id");
  });
});

describe("buildScenarioDocument", () => {
  const doc = buildScenarioDocument({
    id: "scn-1",
    landlordId: "landlord-a",
    inputs: parseScenarioInputs({...minimal, loanRateBps: 310}),
    now: "SERVER_TS",
  });

  it("identité et soft-delete posés par le serveur", () => {
    expect(doc.id).toBe("scn-1");
    expect(doc.landlordId).toBe("landlord-a");
    expect(doc.deletedAt).toBeNull();
    expect(doc.createdAt).toBe("SERVER_TS");
    expect(doc.updatedAt).toBe("SERVER_TS");
    expect(doc.schemaVersion).toBe(1);
  });

  it("★ paramètres financiers présents en racine ET dans scenarioJson", () => {
    // Le modèle Dart lit la racine, le schéma FEAT-019 lit scenarioJson :
    // une divergence rendrait illisibles les scénarios créés par la callable.
    const json = doc.scenarioJson as Record<string, unknown>;
    for (const key of [
      "purchasePriceCents",
      "notaryFeesCents",
      "worksInitialCents",
      "isNewProperty",
      "downPaymentCents",
      "loanPrincipalCents",
      "loanRateBps",
      "loanDurationMonths",
      "monthlyRentHcCents",
      "propertyTaxAnnualCents",
      "insurancePnoAnnualCents",
      "condoFeesNonRecoverableCents",
    ]) {
      expect(json[key]).toEqual(doc[key]);
    }
    expect(json.loanRateBps).toBe(310);
  });
});

describe("★ plafond de scénarios — enforcement serveur (PR-2b)", () => {
  it("la table déclare désormais `scenarios` en enforcement serveur", () => {
    // C'était le DERNIER quota appliqué côté client seul. Si ce test casse,
    // c'est que la table est repassée à `client` sans retirer la callable —
    // le plafond redeviendrait contournable en écrivant le doc en direct.
    expect(quotaEnforcement("scenarios")).toBe("server");
  });

  it("les plafonds appliqués viennent de la table, par palier effectif", () => {
    const anonymous = resolvePlan({subscriptionTier: "anonymous"});
    const free = resolvePlan({subscriptionTier: "free"});
    const paidLegacy = resolvePlan({subscriptionTier: "paid"});
    const paid = (level: "pro" | "max" | "ultra") =>
      resolvePlan({subscriptionTier: "paid", planLevel: level});
    expect(quotaLimit(anonymous, "scenarios")).toBe(1);
    expect(quotaLimit(free, "scenarios")).toBe(3);
    // Un abonné d'avant FEAT-056 (paid sans planLevel) se dérive en `pro` et
    // hérite du plafond Pro — fini depuis PR-7, plus illimité.
    expect(paidLegacy.levelId).toBe("pro");
    expect(quotaLimit(paidLegacy, "scenarios")).toBe(15);
    // Seul Ultra est illimité : les paliers payants sont différenciés.
    expect(quotaLimit(paid("pro"), "scenarios")).toBe(15);
    expect(quotaLimit(paid("max"), "scenarios")).toBe(30);
    expect(quotaLimit(paid("ultra"), "scenarios")).toBeNull();
  });

  it("code d'erreur contractuel inchangé", () => {
    expect(errorCodeFor("scenarios")).toBe("scenario_limit_reached");
  });
});
