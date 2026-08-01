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

    // Scénarios d'investissement : docs dédiés (ne pas réutiliser `doc-a`,
    // partagé avec les tests de list-scoping) portant la forme COMPLÈTE exigée
    // par la rule create — support des tests update/delete ci-dessous.
    await db.doc("investment_scenarios/scenario-a").set({
      id: "scenario-a",
      landlordId: LANDLORD_A,
      name: "Studio Lyon 3",
      schemaVersion: 1,
      scenarioJson: {purchasePriceCents: 15000000},
      createdAt: new Date("2026-01-01"),
      deletedAt: null,
    });
    await db.doc("investment_scenarios/scenario-deleted").set({
      id: "scenario-deleted",
      landlordId: LANDLORD_A,
      name: "Scénario archivé",
      schemaVersion: 1,
      scenarioJson: {purchasePriceCents: 9000000},
      createdAt: new Date("2026-01-01"),
      deletedAt: new Date("2026-06-01"),
    });
    // Docs jetables, un par test d'écriture NÉGATIF (update/delete refusés).
    //
    // Ces tests tentent des mutations qui doivent échouer. Si la rule régresse,
    // la mutation PASSE et corrompt le doc — avec un doc partagé, le premier
    // test qui régresse (p. ex. `landlordId` réécrit) fait cascader tous les
    // suivants en faux négatifs, et la suite pointe vers le mauvais coupable.
    // Un doc par test garde chaque échec diagnostique.
    for (const id of [
      "scenario-del-owner",
      "scenario-del-other",
      "scenario-upd-other",
      "scenario-upd-landlord",
      "scenario-upd-createdat",
      "scenario-upd-softdelete",
    ]) {
      await db.doc(`investment_scenarios/${id}`).set({
        id,
        landlordId: LANDLORD_A,
        name: "Scénario jetable",
        schemaVersion: 1,
        scenarioJson: {purchasePriceCents: 1000000},
        createdAt: new Date("2026-01-01"),
        deletedAt: null,
      });
    }

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

/**
 * investment_scenarios — écritures.
 *
 * Le list-scoping est déjà couvert plus haut (LANDLORD_SCOPED_COLLECTIONS) ;
 * ce bloc couvre create/update/delete, qui ne l'étaient pas.
 *
 * Particularité : c'est la SEULE collection métier dont la création reste
 * ouverte au client (`allow create: if isSignedIn() && …`) au lieu d'être
 * CF-exclusive — et elle est volontairement ouverte aux comptes ANONYMES
 * (`isSignedIn()`, pas `isFullyAuthed()`) : le simulateur est la seule surface
 * accessible sans compte complet (BAILLAN-M1).
 *
 * Corollaire : c'est aussi la seule collection où le transport client peut
 * diverger des rules sans qu'un backend s'y oppose. Ces tests figent le
 * contrat côté rules ; le pendant côté client vit dans
 * `test/unit/firestore_write_path_conformance_test.dart`.
 */
describe("investment_scenarios — écritures (create/update/delete)", () => {
  const validScenario = (
    uid: string,
    id: string,
    over: Record<string, unknown> = {},
  ) => ({
    id,
    landlordId: uid,
    name: "Studio Lyon 3",
    schemaVersion: 1,
    scenarioJson: {purchasePriceCents: 15000000},
    createdAt: new Date(),
    deletedAt: null,
    ...over,
  });

  describe("create", () => {
    it("le propriétaire crée un scénario valide → autorisé", async () => {
      await assertSucceeds(
        asOwnerA()
          .doc("investment_scenarios/s-ok")
          .set(validScenario(LANDLORD_A, "s-ok")),
      );
    });

    it("un compte ANONYME crée un scénario → autorisé (simulateur ouvert)", async () => {
      const anon = env
        .authenticatedContext("anon-1", {
          firebase: {sign_in_provider: "anonymous"},
        })
        .firestore();
      await assertSucceeds(
        anon
          .doc("investment_scenarios/s-anon")
          .set(validScenario("anon-1", "s-anon")),
      );
    });

    it("un non-authentifié ne peut pas créer", async () => {
      await assertFails(
        env
          .unauthenticatedContext()
          .firestore()
          .doc("investment_scenarios/s-nosign")
          .set(validScenario(LANDLORD_A, "s-nosign")),
      );
    });

    it("créer pour le compte d'AUTRUI → refusé", async () => {
      await assertFails(
        asOtherB()
          .doc("investment_scenarios/s-steal")
          .set(validScenario(LANDLORD_A, "s-steal")),
      );
    });

    it("id du payload ≠ docId → refusé", async () => {
      await assertFails(
        asOwnerA()
          .doc("investment_scenarios/s-mismatch")
          .set(validScenario(LANDLORD_A, "autre-id")),
      );
    });

    it("créer déjà soft-deleted → refusé", async () => {
      await assertFails(
        asOwnerA()
          .doc("investment_scenarios/s-predeleted")
          .set(
            validScenario(LANDLORD_A, "s-predeleted", {deletedAt: new Date()}),
          ),
      );
    });

    it("nom vide → refusé", async () => {
      await assertFails(
        asOwnerA()
          .doc("investment_scenarios/s-noname")
          .set(validScenario(LANDLORD_A, "s-noname", {name: ""})),
      );
    });

    it("nom > 120 caractères → refusé", async () => {
      await assertFails(
        asOwnerA()
          .doc("investment_scenarios/s-longname")
          .set(validScenario(LANDLORD_A, "s-longname", {name: "x".repeat(121)})),
      );
    });

    it("schemaVersion absent / non-int → refusé", async () => {
      await assertFails(
        asOwnerA()
          .doc("investment_scenarios/s-badversion")
          .set(validScenario(LANDLORD_A, "s-badversion", {schemaVersion: "1"})),
      );
    });

    it("schemaVersion <= 0 → refusé", async () => {
      await assertFails(
        asOwnerA()
          .doc("investment_scenarios/s-zeroversion")
          .set(validScenario(LANDLORD_A, "s-zeroversion", {schemaVersion: 0})),
      );
    });

    it("scenarioJson non-map → refusé", async () => {
      await assertFails(
        asOwnerA()
          .doc("investment_scenarios/s-badjson")
          .set(validScenario(LANDLORD_A, "s-badjson", {scenarioJson: "nope"})),
      );
    });
  });

  describe("update", () => {
    it("le propriétaire renomme son scénario → autorisé", async () => {
      await assertSucceeds(
        asOwnerA()
          .doc("investment_scenarios/scenario-a")
          .update({name: "Studio Lyon 3 — révisé"}),
      );
    });

    it("un autre compte ne peut pas modifier le scénario d'autrui", async () => {
      await assertFails(
        asOtherB()
          .doc("investment_scenarios/scenario-upd-other")
          .update({name: "Détourné"}),
      );
    });

    it("muter landlordId (immuable) → refusé", async () => {
      await assertFails(
        asOwnerA()
          .doc("investment_scenarios/scenario-upd-landlord")
          .update({landlordId: LANDLORD_B}),
      );
    });

    it("muter createdAt (immuable) → refusé", async () => {
      await assertFails(
        asOwnerA()
          .doc("investment_scenarios/scenario-upd-createdat")
          .update({createdAt: new Date("2020-01-01")}),
      );
    });

    it("soft-delete via update client → refusé (CF softDeleteEntity only)", async () => {
      await assertFails(
        asOwnerA()
          .doc("investment_scenarios/scenario-upd-softdelete")
          .update({deletedAt: new Date()}),
      );
    });

    it("modifier un scénario déjà soft-deleted → refusé", async () => {
      await assertFails(
        asOwnerA()
          .doc("investment_scenarios/scenario-deleted")
          .update({name: "Ressuscité"}),
      );
    });
  });

  describe("delete", () => {
    it("suppression directe par le propriétaire → refusée (CF-exclusive)", async () => {
      await assertFails(
        asOwnerA().doc("investment_scenarios/scenario-del-owner").delete(),
      );
    });

    it("suppression directe par autrui → refusée", async () => {
      await assertFails(
        asOtherB().doc("investment_scenarios/scenario-del-other").delete(),
      );
    });
  });

  describe("get — non-régression", () => {
    it("le propriétaire lit son scénario", async () => {
      await assertSucceeds(
        asOwnerA().doc("investment_scenarios/scenario-a").get(),
      );
    });

    it("un scénario soft-deleted n'est plus lisible", async () => {
      await assertFails(
        asOwnerA().doc("investment_scenarios/scenario-deleted").get(),
      );
    });
  });
});
