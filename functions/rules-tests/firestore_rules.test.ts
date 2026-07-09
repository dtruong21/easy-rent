/**
 * Tests des Firestore Security Rules — exécutés contre l'émulateur :
 *
 *   npm run test:rules   (depuis functions/ — wrappe firebase emulators:exec)
 *
 * NB : le script épingle `npx firebase-tools@13` — les CLI >= 14 exigent un
 * JDK >= 21 (la machine de dev est en JDK 17) ; l'émulateur Firestore lancé
 * (jar v1.19) est le même. Repasser sur la CLI globale une fois JDK >= 21
 * installé.
 *
 * Créés suite à l'audit FEAT-045 (finding H1) : les rules `list` étaient
 * `isSignedIn()` sur 8 collections — les rules n'étant PAS des filtres,
 * n'importe quel compte signé (même anonyme) pouvait requêter les données
 * d'un AUTRE landlord en fournissant son UID
 * (`where('landlordId','==',cible)`). Les rules exigent désormais que toute
 * query `list` porte la contrainte `landlordId == request.auth.uid`.
 *
 * Cas particulièrement sensible : les quittances d'un compte SUPPRIMÉ
 * (FEAT-045) restent stockées 5 ans (rétention légale) avec un `landlordId`
 * orphelin — la promesse « archivée et inaccessible » du flux de suppression
 * repose sur le scoping de ces rules (aucun tiers ne doit pouvoir les lire).
 */

import {readFileSync} from "node:fs";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import type {RulesTestEnvironment} from "@firebase/rules-unit-testing";
import {afterAll, beforeAll, describe, it} from "vitest";

const LANDLORD_A = "landlord-a";
const LANDLORD_B = "landlord-b";

/** Collections multi-tenant portant un champ landlordId (hors singletons). */
const LANDLORD_SCOPED_COLLECTIONS = [
  "properties",
  "tenants",
  "leases",
  "payments",
  "receipts",
  "documents",
  "expenses",
  "investment_scenarios",
] as const;

let env: RulesTestEnvironment;

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-easyrent",
    firestore: {rules: readFileSync("../firestore.rules", "utf8")},
  });

  // Seed Admin (rules désactivées) : un doc par collection pour landlord A.
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const collection of LANDLORD_SCOPED_COLLECTIONS) {
      await db.doc(`${collection}/doc-a`).set({
        landlordId: LANDLORD_A,
        deletedAt: null,
        name: "seed",
      });
    }
    // Quittance « orpheline » : compte landlord A supprimé (FEAT-045), la
    // quittance est conservée pour rétention légale.
    await db.doc("receipts/orphan-receipt").set({
      landlordId: "deleted-account-uid",
      tenantName: "Locataire X",
      amountCents: 70000,
      accountDeletedAt: new Date(),
    });

    // FEAT-044 : landlord A « complet » avec 2 biens comptabilisés — support
    // des tests d'immutabilité du compteur / gating.
    await db.doc("landlords/landlord-a").set({
      id: LANDLORD_A,
      email: "a@example.com",
      fullName: "Landlord A",
      isAnonymous: false,
      subscriptionTier: "free",
      rgpdConsentAt: new Date(),
      rgpdConsentVersion: "v2-2026-07",
      activePropertiesCount: 2,
      activeTenantsCount: 3,
      activeLeasesCount: 1,
      createdAt: new Date(),
      deletedAt: null,
    });
  });
});

afterAll(async () => {
  await env.cleanup();
});

const asOwnerA = () => env.authenticatedContext(LANDLORD_A).firestore();
const asOtherB = () => env.authenticatedContext(LANDLORD_B).firestore();

describe("list — scoping owner obligatoire (audit FEAT-045 H1)", () => {
  for (const collection of LANDLORD_SCOPED_COLLECTIONS) {
    it(`${collection} : un AUTRE compte signé ne peut pas requêter les docs du landlord A`, async () => {
      await assertFails(
        asOtherB()
          .collection(collection)
          .where("landlordId", "==", LANDLORD_A)
          .get(),
      );
    });

    it(`${collection} : une query SANS contrainte landlordId est refusée`, async () => {
      await assertFails(asOtherB().collection(collection).get());
    });

    it(`${collection} : le propriétaire liste ses propres docs`, async () => {
      await assertSucceeds(
        asOwnerA()
          .collection(collection)
          .where("landlordId", "==", LANDLORD_A)
          .get(),
      );
    });
  }
});

describe("quittances conservées après suppression de compte (FEAT-045)", () => {
  it("personne ne peut lister les quittances d'un UID orphelin", async () => {
    await assertFails(
      asOtherB()
        .collection("receipts")
        .where("landlordId", "==", "deleted-account-uid")
        .get(),
    );
  });

  it("personne ne peut get une quittance orpheline par son id", async () => {
    await assertFails(asOtherB().doc("receipts/orphan-receipt").get());
  });
});

describe("get — ownership par doc (inchangé, non-régression)", () => {
  it("le propriétaire lit son doc", async () => {
    await assertSucceeds(asOwnerA().doc("receipts/doc-a").get());
  });

  it("un autre compte ne lit pas le doc d'autrui", async () => {
    await assertFails(asOtherB().doc("receipts/doc-a").get());
  });
});

describe("FEAT-044 — gating création de biens (rules)", () => {
  const asUid = (uid: string) => env.authenticatedContext(uid).firestore();

  // Payload de provisioning landlord « compte complet » valide (miroir du
  // chemin client auth_repository.dart) ; `over` surcharge un champ à tester.
  const landlordDoc = (uid: string, over: Record<string, unknown> = {}) => ({
    id: uid,
    email: `${uid}@example.com`,
    fullName: "New Landlord",
    isAnonymous: false,
    subscriptionTier: "free",
    rgpdConsentAt: new Date(),
    rgpdConsentVersion: "v2-2026-07",
    activePropertiesCount: 0,
    createdAt: new Date(),
    deletedAt: null,
    ...over,
  });

  it("création d'un bien en direct (client) refusée — CF-exclusive", async () => {
    await assertFails(
      asOwnerA().doc("properties/p-new").set({
        landlordId: LANDLORD_A,
        deletedAt: null,
        id: "p-new",
        name: "Bien",
        address: "1 rue",
        type: "appartement",
        activeLeaseCount: 0,
      }),
    );
  });

  it("création d'un locataire en direct (client) refusée — CF-exclusive", async () => {
    await assertFails(
      asOwnerA().doc("tenants/t-new").set({
        landlordId: LANDLORD_A,
        deletedAt: null,
        id: "t-new",
        firstName: "Jean",
        lastName: "Dupont",
        email: "jean@example.com",
        activeLeaseCount: 0,
      }),
    );
  });

  it("reset de activeTenantsCount via update → refusé", async () => {
    await assertFails(
      asOwnerA().doc("landlords/landlord-a").update({activeTenantsCount: 0}),
    );
  });

  it("reset de activeLeasesCount via update → refusé", async () => {
    await assertFails(
      asOwnerA().doc("landlords/landlord-a").update({activeLeasesCount: 0}),
    );
  });

  it("provisioning avec subscriptionTier='paid' auto-déclaré → refusé (critique)", async () => {
    await assertFails(
      asUid("lld-paid")
        .doc("landlords/lld-paid")
        .set(landlordDoc("lld-paid", {subscriptionTier: "paid"})),
    );
  });

  it("provisioning avec subscriptionTier='free' → autorisé", async () => {
    await assertSucceeds(
      asUid("lld-free").doc("landlords/lld-free").set(landlordDoc("lld-free")),
    );
  });

  it("provisioning avec activePropertiesCount négatif → refusé", async () => {
    await assertFails(
      asUid("lld-neg")
        .doc("landlords/lld-neg")
        .set(landlordDoc("lld-neg", {activePropertiesCount: -50})),
    );
  });

  it("reset de activePropertiesCount via update → refusé", async () => {
    await assertFails(
      asOwnerA().doc("landlords/landlord-a").update({activePropertiesCount: 0}),
    );
  });

  it("update de profil normal (fullName) → autorisé, compteur préservé", async () => {
    await assertSucceeds(
      asOwnerA().doc("landlords/landlord-a").update({fullName: "Landlord A2"}),
    );
  });
});
