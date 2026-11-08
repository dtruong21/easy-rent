/**
 * OWASP-02 — les callables métier exigent un compte « de confiance » (email
 * vérifié, Google/Apple, ou anonyme confirmé) ; seules les callables du droit
 * RGPD et de l'upgrade anonyme en sont exemptées.
 *
 * Le comportement fin du helper vit dans `require_verified_uid.test.ts` ; ce
 * fichier prouve qu'il est BRANCHÉ sur chaque callable :
 *   - une parité fichier ↔ liste interdit d'ajouter une callable sans la
 *     classer (gardée / exemptée), comme PURGED_COLLECTIONS pour la purge ;
 *   - chaque callable gardée refuse un compte non vérifié AVANT tout travail.
 */
import * as fs from "node:fs";
import {resolve} from "node:path";

import type {
  CallableFunction,
  CallableRequest,
} from "firebase-functions/v2/https";
import {beforeEach, describe, expect, it, vi} from "vitest";

import {
  finalizeChargeRegularization,
  markChargeStatementAsSent,
  voidChargeStatement,
} from "../callable/charge_statements";
import {createCheckoutSession} from "../callable/create_checkout_session";
import {
  createDocument,
  getDocumentDownloadUrl,
  updateDocumentCategory,
} from "../callable/documents";
import {createEtatDesLieux} from "../callable/etat_des_lieux";
import {createExpense, updateExpense} from "../callable/expenses";
import {finalizeAnonymousUpgrade} from "../callable/finalize_anonymous_upgrade";
import {
  createLease,
  createPayment,
  updateLease,
  updatePayment,
} from "../callable/lease_payment";
import {manageSubscription} from "../callable/manage_subscription";
import {createProperty, createTenant} from "../callable/property_tenant";
import {
  generateReceipt,
  markReceiptAsSent,
  voidReceipt,
} from "../callable/receipts";
import {createScenario} from "../callable/scenarios";
import {softDeleteEntity} from "../callable/soft_delete";

import {
  FakeAuthAdmin,
  FakeFirestore,
  fakeAdminFirestoreHolder,
  fakeStagingFirestoreHolder,
} from "./helpers/fake_firestore";

// Cf. expenses.test.ts pour la justification du import() dynamique interne.
vi.mock("firebase-admin", async () => {
  const {makeFakeAdminModule} = await import("./helpers/fake_firestore");
  return makeFakeAdminModule();
});

const UID = "landlord-a";

/** Callables métier : TOUTES doivent refuser un compte non vérifié. */
const GUARDED: Record<string, CallableFunction<unknown, unknown>> = {
  createProperty,
  createTenant,
  createLease,
  updateLease,
  createPayment,
  updatePayment,
  softDeleteEntity,
  generateReceipt,
  voidReceipt,
  markReceiptAsSent,
  createDocument,
  getDocumentDownloadUrl,
  updateDocumentCategory,
  createExpense,
  updateExpense,
  createScenario,
  createCheckoutSession,
  manageSubscription,
  createEtatDesLieux,
  finalizeChargeRegularization,
  voidChargeStatement,
  markChargeStatementAsSent,
};

/**
 * Callables VOLONTAIREMENT exemptées :
 *  - `deleteAccount` / `exportAccountData` : droits RGPD (art. 17 / 15-20),
 *    qui doivent rester exerçables même par un compte jamais vérifié ;
 *  - `finalizeAnonymousUpgrade` : appelée par `linkAnonymousWithEmailPassword`
 *    AVANT l'envoi de l'email de vérification — le compte est donc non
 *    vérifié par construction à ce moment-là.
 */
const EXEMPT = [
  "deleteAccount",
  "exportAccountData",
  "finalizeAnonymousUpgrade",
] as const;

let fakeDb: FakeFirestore;
let fakeAuth: FakeAuthAdmin;

beforeEach(() => {
  fakeDb = new FakeFirestore();
  fakeAuth = new FakeAuthAdmin();
  fakeAdminFirestoreHolder.db = fakeDb;
  fakeAdminFirestoreHolder.authAdmin = fakeAuth;
  fakeStagingFirestoreHolder.db = new FakeFirestore("staging");
});

function makeRequest(
  token: Record<string, unknown>,
  data: unknown = {},
): CallableRequest {
  return {
    data,
    auth: {uid: UID, token: token as never, rawToken: ""},
    rawRequest: {headers: {}} as never,
  } as CallableRequest;
}

const UNVERIFIED = {
  email_verified: false,
  firebase: {sign_in_provider: "password"},
};

describe("parité — toute callable est classée (gardée ou exemptée)", () => {
  it("les callables du dossier callable/ = GUARDED ∪ EXEMPT", () => {
    const dir = resolve(__dirname, "../callable");
    const exported: string[] = [];
    for (const file of fs.readdirSync(dir)) {
      if (!file.endsWith(".ts")) continue;
      const src = fs.readFileSync(resolve(dir, file), "utf8");
      for (const m of src.matchAll(/export const (\w+) = onCall\(/g)) {
        exported.push(m[1]);
      }
    }
    expect(exported.sort()).toEqual(
      [...Object.keys(GUARDED), ...EXEMPT].sort(),
    );
  });
});

describe("callables métier — compte NON vérifié refusé avant tout travail", () => {
  for (const [name, fn] of Object.entries(GUARDED)) {
    it(`${name} → failed-precondition / email_not_verified`, async () => {
      await expect(fn.run(makeRequest(UNVERIFIED))).rejects.toMatchObject({
        code: "failed-precondition",
        message: "email_not_verified",
      });
      // Aucune écriture n'a eu lieu.
      expect(fakeDb.peek(`landlords/${UID}`)).toBeUndefined();
    });
  }

  it("token d'un anonyme UPGRADÉ en email/mot de passe non vérifié (claim périmé) → refusé", async () => {
    fakeAuth.providerDataByUid.set(UID, [{providerId: "password"}]);
    fakeAuth.emailVerifiedByUid.set(UID, false);
    await expect(
      createProperty.run(
        makeRequest({firebase: {sign_in_provider: "anonymous"}}),
      ),
    ).rejects.toMatchObject({
      code: "failed-precondition",
      message: "email_not_verified",
    });
  });
});

describe("comptes de confiance — non-régression", () => {
  it("Google (email_verified false) passe la garde de createProperty", async () => {
    // Payload volontairement invalide : l'erreur doit venir de la VALIDATION
    // (garde franchie), pas de `email_not_verified`.
    await expect(
      createProperty.run(
        makeRequest({
          email_verified: false,
          firebase: {sign_in_provider: "google.com"},
        }),
      ),
    ).rejects.toMatchObject({code: "invalid-argument"});
  });

  it("★ l'ESSAI ANONYME garde son comportement : createScenario fonctionne pour un anonyme pur", async () => {
    fakeDb.seed(`landlords/${UID}`, {
      id: UID,
      isAnonymous: true,
      subscriptionTier: "anonymous",
      deletedAt: null,
    });
    const res = (await createScenario.run(
      makeRequest(
        {firebase: {sign_in_provider: "anonymous"}},
        {
          name: "Studio Lyon 7",
          purchasePriceCents: 15_000_000,
          monthlyRentHcCents: 65_000,
        },
      ),
    )) as {scenarioId: string};
    expect(typeof res.scenarioId).toBe("string");
    expect(fakeDb.peek(`investment_scenarios/${res.scenarioId}`)).toBeDefined();
  });
});

describe("callables exemptées — restent accessibles à un compte non vérifié", () => {
  it("★ finalizeAnonymousUpgrade : l'upgrade email/mot de passe (avant vérification) aboutit", async () => {
    // Séquence réelle de linkAnonymousWithEmailPassword : le provider est
    // lié (providerData non vide), l'email n'est PAS encore vérifié, et le
    // token porte encore le claim « anonymous ».
    fakeAuth.providerDataByUid.set(UID, [{providerId: "password"}]);
    fakeAuth.emailVerifiedByUid.set(UID, false);
    fakeDb.seed(`landlords/${UID}`, {
      id: UID,
      email: null,
      fullName: "",
      isAnonymous: true,
      subscriptionTier: "anonymous",
      deletedAt: null,
    });

    const res = await finalizeAnonymousUpgrade.run(
      makeRequest(
        {firebase: {sign_in_provider: "anonymous"}},
        {rgpdConsent: true, rgpdConsentVersion: "v2-2026-07"},
      ),
    );

    expect(res).toEqual({ok: true, tier: "free"});
    expect(fakeDb.peek(`landlords/${UID}`)).toMatchObject({
      isAnonymous: false,
      subscriptionTier: "free",
    });
  });
});
