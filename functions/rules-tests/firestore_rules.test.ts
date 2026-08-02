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
    // FEAT-056 (PR-2b) : scénario complet (avec createdAt) — support du test
    // de non-régression « l'update client reste autorisé après le passage de
    // `create` à `if false` ». Le doc `doc-a` seedé ci-dessus n'a pas de
    // createdAt, que `preservesImmutables` compare.
    await db.doc("investment_scenarios/scn-editable").set({
      id: "scn-editable",
      landlordId: LANDLORD_A,
      name: "Scénario existant",
      schemaVersion: 1,
      scenarioJson: {purchasePriceCents: 15000000},
      createdAt: new Date(),
      deletedAt: null,
    });

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

  // FEAT-044f (audit sécurité) : les champs `pro*` (entitlement RevenueCat)
  // sont écrits EXCLUSIVEMENT par le webhook/reconcile via Admin SDK. Un
  // propriétaire ne doit pas pouvoir les muter côté client — sinon il neutralise
  // le backstop `reconcileEntitlements` ou bloque les futurs events du webhook.
  it("mutation client de proEntitlementActive → refusée (backstop reconcile)", async () => {
    await assertFails(
      asOwnerA()
        .doc("landlords/landlord-a")
        .update({proEntitlementActive: true}),
    );
  });

  it("mutation client de proExpiresAt → refusée (filtre reconcile)", async () => {
    await assertFails(
      asOwnerA()
        .doc("landlords/landlord-a")
        .update({proExpiresAt: new Date("2099-01-01")}),
    );
  });

  it("mutation client de proLastEventAtMs → refusée (garde d'ordre webhook)", async () => {
    await assertFails(
      asOwnerA()
        .doc("landlords/landlord-a")
        .update({proLastEventAtMs: 9999999999999}),
    );
  });
});

// ==========================================================================
// FEAT-056 — `planLevel` et `entitlements` client-immuables.
//
// Le passage à trois paliers AUGMENTE l'enjeu de cette immuabilité : hier,
// forcer `subscriptionTier: 'paid'` était le seul gain possible ; demain,
// `planLevel: 'ultra'` est un gain gradué, donc une cible plus attractive.
// Un client n'a JAMAIS besoin d'écrire son palier — même l'affichage optimiste
// post-checkout doit attendre le webhook plutôt que peindre un état.
// ==========================================================================
describe("FEAT-056 — palier commercial et entitlements (rules)", () => {
  const PAID_UID = "landlord-paid-056";
  const asUid = (uid: string) => env.authenticatedContext(uid).firestore();
  const asAnon = (uid: string) =>
    env
      .authenticatedContext(uid, {
        firebase: {sign_in_provider: "anonymous"},
      })
      .firestore();

  /** Provisioning client valide (miroir de auth_repository.dart). */
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

  beforeAll(async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      // Abonné Ultra « post-FEAT-056 » : porte planLevel ET la map d'état.
      await ctx.firestore().doc(`landlords/${PAID_UID}`).set({
        id: PAID_UID,
        email: "paid@example.com",
        fullName: "Landlord Payant",
        isAnonymous: false,
        subscriptionTier: "paid",
        planLevel: "ultra",
        entitlements: {
          ultra: {
            active: true,
            expiresAt: new Date("2027-01-01"),
            willRenew: true,
            productId: "ultra_yearly",
            store: "web",
            lastEventAtMs: 1750000000000,
          },
        },
        proEntitlementActive: true,
        rgpdConsentAt: new Date(),
        rgpdConsentVersion: "v2-2026-07",
        createdAt: new Date(),
        deletedAt: null,
      });
    });
  });

  // --- UPDATE ------------------------------------------------------------
  it("s'auto-attribuer planLevel:'ultra' → refusé (CRITIQUE)", async () => {
    await assertFails(
      asOwnerA().doc("landlords/landlord-a").update({planLevel: "ultra"}),
    );
  });

  it("modifier son propre planLevel quand on est déjà payant → refusé", async () => {
    await assertFails(
      asUid(PAID_UID).doc(`landlords/${PAID_UID}`).update({planLevel: "pro"}),
    );
  });

  it("effacer son planLevel → refusé", async () => {
    await assertFails(
      asUid(PAID_UID).doc(`landlords/${PAID_UID}`).update({planLevel: null}),
    );
  });

  it("écrire la map entitlements → refusé", async () => {
    await assertFails(
      asOwnerA()
        .doc("landlords/landlord-a")
        .update({
          entitlements: {
            ultra: {active: true, expiresAt: new Date("2099-01-01")},
          },
        }),
    );
  });

  it("altérer une entitlements existante → refusé", async () => {
    await assertFails(
      asUid(PAID_UID)
        .doc(`landlords/${PAID_UID}`)
        .update({
          entitlements: {
            ultra: {
              active: true,
              expiresAt: new Date("2099-01-01"), // échéance repoussée
              willRenew: true,
              productId: "ultra_yearly",
              store: "web",
              lastEventAtMs: 1750000000000,
            },
          },
        }),
    );
  });

  it("subscriptionTier reste immuable, quelle que soit la valeur visée", async () => {
    await assertFails(
      asOwnerA().doc("landlords/landlord-a").update({subscriptionTier: "paid"}),
    );
    await assertFails(
      asUid(PAID_UID)
        .doc(`landlords/${PAID_UID}`)
        .update({subscriptionTier: "free"}),
    );
  });

  // --- NON-RÉGRESSION : un doc payant doit rester éditable -----------------
  it("update de profil sur un doc PORTANT planLevel + entitlements → autorisé", async () => {
    // Si ce test casse, tout abonné payant devient incapable de modifier son
    // profil : la panne la plus visible que ces deux lignes pourraient causer.
    await assertSucceeds(
      asUid(PAID_UID)
        .doc(`landlords/${PAID_UID}`)
        .update({fullName: "Landlord Payant 2"}),
    );
  });

  it("update de profil sur un doc SANS planLevel (legacy) → autorisé", async () => {
    // Le `.get(…, null)` doit tolérer l'absence du champ, sinon tous les
    // comptes d'avant FEAT-056 seraient bloqués.
    await assertSucceeds(
      asOwnerA().doc("landlords/landlord-a").update({fullName: "Landlord A3"}),
    );
  });

  // --- CREATE ------------------------------------------------------------
  it("provisioning avec planLevel non nul → refusé", async () => {
    await assertFails(
      asUid("lld-056-a")
        .doc("landlords/lld-056-a")
        .set(landlordDoc("lld-056-a", {planLevel: "ultra"})),
    );
  });

  it("provisioning avec une map entitlements → refusé", async () => {
    await assertFails(
      asUid("lld-056-b")
        .doc("landlords/lld-056-b")
        .set(
          landlordDoc("lld-056-b", {
            entitlements: {ultra: {active: true}},
          }),
        ),
    );
  });

  it("provisioning sans planLevel → toujours autorisé (non-régression)", async () => {
    await assertSucceeds(
      asUid("lld-056-c").doc("landlords/lld-056-c").set(landlordDoc("lld-056-c")),
    );
  });

  it("provisioning ANONYME avec planLevel → refusé", async () => {
    await assertFails(
      asAnon("anon-056")
        .doc("landlords/anon-056")
        .set({
          id: "anon-056",
          email: null,
          fullName: "",
          isAnonymous: true,
          subscriptionTier: "anonymous",
          anonExpiresAt: new Date(Date.now() + 7 * 24 * 3600 * 1000),
          rgpdConsentAt: null,
          deletedAt: null,
          planLevel: "ultra",
        }),
    );
  });

  // --- CROSS-USER --------------------------------------------------------
  it("cross-user : lire le doc payant d'autrui → refusé", async () => {
    await assertFails(asOtherB().doc(`landlords/${PAID_UID}`).get());
  });

  it("cross-user : écrire le planLevel d'autrui → refusé", async () => {
    await assertFails(
      asOtherB().doc(`landlords/${PAID_UID}`).update({planLevel: "pro"}),
    );
  });
});

// ==========================================================================
// FEAT-056 (PR-2b) — plafond de scénarios enforcé serveur
//
// `investment_scenarios` était le DERNIER quota appliqué par le client seul :
// le simulateur écrivait le document en direct. Le nombre de scénarios devenant
// un différenciateur commercial entre Pro, Max et Ultra, la création passe
// désormais obligatoirement par la Callable `createScenario` (Admin SDK), qui
// applique `quotaLimit(plan, 'scenarios')`. Si `create` redevenait permissif,
// le plafond payant serait contournable en une ligne de client.
// ==========================================================================
describe("FEAT-056 — création de scénarios CF-exclusive (PR-2b)", () => {
  const scenarioDoc = (id: string, landlordId: string) => ({
    id,
    landlordId,
    name: "Scénario forgé",
    schemaVersion: 1,
    scenarioJson: {purchasePriceCents: 15000000},
    deletedAt: null,
    createdAt: new Date(),
  });

  it("★ création d'un scénario en direct (client) refusée — CF-exclusive", async () => {
    await assertFails(
      asOwnerA()
        .doc("investment_scenarios/scn-direct")
        .set(scenarioDoc("scn-direct", LANDLORD_A)),
    );
  });

  it("★ un anonyme ne peut pas non plus créer un scénario en direct", async () => {
    // Le palier anonyme a un plafond de 1 scénario : sans cette rule, il
    // suffirait d'écrire le doc soi-même pour le dépasser.
    const anon = env
      .authenticatedContext("anon-scn", {
        firebase: {sign_in_provider: "anonymous"},
      })
      .firestore();
    await assertFails(
      anon
        .doc("investment_scenarios/scn-anon")
        .set(scenarioDoc("scn-anon", "anon-scn")),
    );
  });

  it("cross-user : créer un scénario au nom d'autrui → refusé", async () => {
    await assertFails(
      asOtherB()
        .doc("investment_scenarios/scn-cross")
        .set(scenarioDoc("scn-cross", LANDLORD_A)),
    );
  });

  it("non-régression : l'update d'un scénario existant reste autorisé", async () => {
    // Seule la CRÉATION passe par la callable ; l'édition d'un scénario déjà
    // compté ne consomme aucun quota et reste un write client direct.
    await assertSucceeds(
      asOwnerA()
        .doc("investment_scenarios/scn-editable")
        .update({name: "Scénario renommé"}),
    );
  });

  it("non-régression : lecture propriétaire inchangée", async () => {
    await assertSucceeds(
      asOwnerA().doc("investment_scenarios/scn-editable").get(),
    );
  });
});
