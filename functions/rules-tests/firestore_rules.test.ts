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
  "charge_statements",
  "etat_des_lieux",
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
    // FEAT-044e — liste blanche sandbox, lue uniquement par les Functions.
    await db.doc("_ops/sandboxAllowlist").set({uids: [LANDLORD_A]});
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

/**
 * Token d'un compte email/mot de passe DONT L'EMAIL EST VÉRIFIÉ (OWASP-02) :
 * les rules exigent `email_verified == true` ou un provider Google/Apple pour
 * tout chemin « compte complet » ; sans ces claims, `authenticatedContext(uid)`
 * représenterait un compte non vérifié. Les cas non vérifié / Google / Apple /
 * anonyme sont testés explicitement dans le bloc « OWASP-02 » en fin de fichier.
 */
const VERIFIED_TOKEN = {
  email_verified: true,
  firebase: {sign_in_provider: "password"},
} as const;

const asVerifiedUid = (uid: string) =>
  env.authenticatedContext(uid, VERIFIED_TOKEN).firestore();
const asOwnerA = () => asVerifiedUid(LANDLORD_A);
const asOtherB = () => asVerifiedUid(LANDLORD_B);

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

describe("charge_statements — immuables & owner-scoped (FEAT-033)", () => {
  it("le propriétaire lit son décompte", async () => {
    await assertSucceeds(asOwnerA().doc("charge_statements/doc-a").get());
  });
  it("un autre compte ne lit pas le décompte d'autrui", async () => {
    await assertFails(asOtherB().doc("charge_statements/doc-a").get());
  });
  it("un autre compte ne peut lister les décomptes d'un UID orphelin", async () => {
    await assertFails(
      asOtherB().collection("charge_statements").where("landlordId", "==", "deleted-account-uid").get(),
    );
  });
  it("le client ne peut PAS créer un décompte (CF exclusive)", async () => {
    await assertFails(
      asOwnerA().collection("charge_statements").add({landlordId: LANDLORD_A}),
    );
  });
  it("le client ne peut PAS modifier ni supprimer un décompte", async () => {
    await assertFails(asOwnerA().doc("charge_statements/doc-a").update({balanceCents: 0}));
    await assertFails(asOwnerA().doc("charge_statements/doc-a").delete());
  });
});

describe("etat_des_lieux — immuables & owner-scoped (FEAT-037)", () => {
  it("le propriétaire lit son état des lieux", async () => {
    await assertSucceeds(asOwnerA().doc("etat_des_lieux/doc-a").get());
  });
  it("un autre compte ne lit pas l'état des lieux d'autrui", async () => {
    await assertFails(asOtherB().doc("etat_des_lieux/doc-a").get());
  });
  it("un autre compte ne peut lister les états des lieux d'un UID orphelin", async () => {
    await assertFails(
      asOtherB().collection("etat_des_lieux").where("landlordId", "==", "deleted-account-uid").get(),
    );
  });
  it("le client ne peut PAS créer un état des lieux (CF exclusive)", async () => {
    await assertFails(
      asOwnerA().collection("etat_des_lieux").add({landlordId: LANDLORD_A}),
    );
  });
  it("le client ne peut PAS modifier ni supprimer un état des lieux", async () => {
    await assertFails(asOwnerA().doc("etat_des_lieux/doc-a").update({roomsCount: 0}));
    await assertFails(asOwnerA().doc("etat_des_lieux/doc-a").delete());
  });
});

describe("FEAT-044 — gating création de biens (rules)", () => {
  const asUid = asVerifiedUid;

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
  const asUid = asVerifiedUid;
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

/**
 * investment_scenarios — écritures.
 *
 * Le list-scoping est déjà couvert plus haut (LANDLORD_SCOPED_COLLECTIONS) ;
 * ce bloc couvre create/update/delete, qui ne l'étaient pas.
 *
 * Particularité historique (#156) : c'était la SEULE collection métier dont la
 * création restait ouverte au client (`allow create: if isSignedIn() && …`) au
 * lieu d'être CF-exclusive, et volontairement ouverte aux comptes ANONYMES
 * (`isSignedIn()`, pas `isFullyAuthed()`) — le simulateur est la seule surface
 * accessible sans compte complet (BAILLAN-M1).
 *
 * FEAT-056 (PR-2b) a refermé cette porte : `allow create: if false`. Le
 * simulateur reste ouvert aux anonymes, mais via la Callable `createScenario`,
 * qui seule sait appliquer le plafond de scénarios du palier. Les cas de
 * création ci-dessous sont donc TOUS devenus des refus — ils sont conservés (et
 * les deux « autorisé » retournés en `assertFails`) parce qu'ils restent la
 * non-régression du deny : si la rule redevenait permissive, ils repasseraient
 * au rouge.
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
    // La validation de FORME que ces cas exerçaient (id ≠ docId, nom vide, nom
    // > 120, schemaVersion, scenarioJson) vit désormais dans
    // `parseScenarioInputs` — couverte par
    // functions/src/__tests__/scenarios.test.ts. Ici, tout create client est
    // refusé quelle que soit la forme du payload : c'est exactement le contrat
    // que ces tests figent.
    it("le propriétaire crée un scénario valide → REFUSÉ depuis PR-2b (CF-exclusive)", async () => {
      // Ce cas était un `assertSucceeds` avant FEAT-056. C'est LE test qui
      // repasse au rouge si `allow create` redevenait permissif.
      await assertFails(
        asOwnerA()
          .doc("investment_scenarios/s-ok")
          .set(validScenario(LANDLORD_A, "s-ok")),
      );
    });

    it("un compte ANONYME crée un scénario → REFUSÉ depuis PR-2b (passe par la callable)", async () => {
      // Le simulateur reste ouvert aux anonymes, mais leur plafond (1 scénario)
      // n'est vérifiable que côté serveur : le write direct est fermé.
      const anon = env
        .authenticatedContext("anon-1", {
          firebase: {sign_in_provider: "anonymous"},
        })
        .firestore();
      await assertFails(
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

// ==========================================================================
// OWASP-02 — email vérifié exigé côté serveur
//
// Avant ce correctif, seul le client Flutter imposait la vérification d'email
// (routeur + déconnexion forcée dans LoginController) : un compte
// email/mot de passe jamais vérifié — éventuellement créé avec l'adresse d'un
// tiers — utilisait tout le produit via le SDK/REST. Les rules exigent
// désormais `email_verified == true` OU un provider Google/Apple (dont
// l'email est vérifié par le fournisseur d'identité).
//
// Exceptions volontaires :
//   - la CRÉATION du doc `landlords/{uid}` par son propriétaire reste ouverte
//     à un compte non vérifié : `signUpWithPassword` écrit ce doc AVANT
//     d'envoyer l'email de vérification puis de déconnecter l'utilisateur ;
//   - les comptes ANONYMES (essai sans compte) gardent exactement leur
//     comportement : leurs chemins sont régis par des rules dédiées.
// ==========================================================================
describe("OWASP-02 — email vérifié exigé par les rules", () => {
  const ctx = (uid: string, token: Record<string, unknown>) =>
    env.authenticatedContext(uid, token).firestore();
  const asUnverified = (uid: string) =>
    ctx(uid, {email_verified: false, firebase: {sign_in_provider: "password"}});
  const asVerified = (uid: string) =>
    ctx(uid, {email_verified: true, firebase: {sign_in_provider: "password"}});
  // Google / Apple : on retire volontairement `email_verified` (false / absent)
  // pour prouver que c'est bien le PROVIDER qui ouvre l'accès.
  const asGoogle = (uid: string) =>
    ctx(uid, {email_verified: false, firebase: {sign_in_provider: "google.com"}});
  const asApple = (uid: string) =>
    ctx(uid, {firebase: {sign_in_provider: "apple.com"}});
  const asAnonymous = (uid: string) =>
    ctx(uid, {firebase: {sign_in_provider: "anonymous"}});

  /** Provisioning « compte complet » (miroir de signUpWithPassword). */
  const signupDoc = (uid: string, over: Record<string, unknown> = {}) => ({
    id: uid,
    email: `${uid}@example.com`,
    fullName: "Nouveau Bailleur",
    isAnonymous: false,
    subscriptionTier: "free",
    rgpdConsentAt: new Date(),
    rgpdConsentVersion: "v2-2026-07",
    activePropertiesCount: 0,
    activeTenantsCount: 0,
    activeLeasesCount: 0,
    createdAt: new Date(),
    deletedAt: null,
    ...over,
  });

  const FULL_ACCOUNTS = ["o2-unverified", "o2-verified", "o2-google", "o2-apple"];
  const ANON = "o2-anon";

  beforeAll(async () => {
    await env.withSecurityRulesDisabled(async (c) => {
      const db = c.firestore();
      for (const uid of FULL_ACCOUNTS) {
        await db.doc(`landlords/${uid}`).set(signupDoc(uid));
        await db.doc(`properties/prop-${uid}`).set({
          id: `prop-${uid}`,
          landlordId: uid,
          name: "Bien",
          createdAt: new Date("2026-01-01"),
          deletedAt: null,
          activeLeaseCount: 0,
        });
        await db.doc(`investment_scenarios/scn-${uid}`).set({
          id: `scn-${uid}`,
          landlordId: uid,
          name: "Scénario",
          schemaVersion: 1,
          scenarioJson: {purchasePriceCents: 1000000},
          createdAt: new Date("2026-01-01"),
          deletedAt: null,
        });
      }
      await db.doc(`landlords/${ANON}`).set({
        id: ANON,
        email: null,
        fullName: "",
        isAnonymous: true,
        subscriptionTier: "anonymous",
        anonExpiresAt: new Date(Date.now() + 7 * 24 * 3600 * 1000),
        rgpdConsentAt: null,
        createdAt: new Date("2026-01-01"),
        deletedAt: null,
      });
      await db.doc(`investment_scenarios/scn-${ANON}`).set({
        id: `scn-${ANON}`,
        landlordId: ANON,
        name: "Scénario anonyme",
        schemaVersion: 1,
        scenarioJson: {purchasePriceCents: 1000000},
        createdAt: new Date("2026-01-01"),
        deletedAt: null,
      });
    });
  });

  // --- Création du doc landlord à l'inscription (AVANT vérification) -----
  describe("inscription — création de landlords/{uid}", () => {
    it("★ compte email/mot de passe NON vérifié crée son propre doc → autorisé", async () => {
      await assertSucceeds(
        asUnverified("o2-new-unverified")
          .doc("landlords/o2-new-unverified")
          .set(signupDoc("o2-new-unverified"), {merge: true}),
      );
    });

    it("compte vérifié / Google / Apple crée son doc → autorisé", async () => {
      await assertSucceeds(
        asVerified("o2-new-verified")
          .doc("landlords/o2-new-verified")
          .set(signupDoc("o2-new-verified")),
      );
      await assertSucceeds(
        asGoogle("o2-new-google")
          .doc("landlords/o2-new-google")
          .set(signupDoc("o2-new-google")),
      );
      await assertSucceeds(
        asApple("o2-new-apple")
          .doc("landlords/o2-new-apple")
          .set(signupDoc("o2-new-apple")),
      );
    });

    it("non vérifié : créer le doc d'AUTRUI → refusé", async () => {
      await assertFails(
        asUnverified("o2-new-x")
          .doc("landlords/o2-victim")
          .set(signupDoc("o2-victim")),
      );
    });

    it("non vérifié : les contraintes de champs restent celles d'aujourd'hui", async () => {
      // tier payant auto-déclaré
      await assertFails(
        asUnverified("o2-new-paid")
          .doc("landlords/o2-new-paid")
          .set(signupDoc("o2-new-paid", {subscriptionTier: "paid"})),
      );
      // pas de consentement RGPD
      await assertFails(
        asUnverified("o2-new-norgpd")
          .doc("landlords/o2-new-norgpd")
          .set(signupDoc("o2-new-norgpd", {rgpdConsentVersion: ""})),
      );
      // planLevel auto-attribué
      await assertFails(
        asUnverified("o2-new-plan")
          .doc("landlords/o2-new-plan")
          .set(signupDoc("o2-new-plan", {planLevel: "ultra"})),
      );
    });
  });

  // --- Compte NON vérifié : plus rien d'autre n'est accessible -----------
  describe("compte email/mot de passe non vérifié", () => {
    const U = "o2-unverified";

    it("ne lit pas son doc landlord", async () => {
      await assertFails(asUnverified(U).doc(`landlords/${U}`).get());
    });

    it("claim `email_verified` ABSENT (fail-closed) → refusé comme non vérifié", async () => {
      await assertFails(
        ctx(U, {firebase: {sign_in_provider: "password"}})
          .doc(`landlords/${U}`)
          .get(),
      );
    });

    it("ne met pas à jour son doc landlord", async () => {
      await assertFails(
        asUnverified(U).doc(`landlords/${U}`).update({fullName: "Autre nom"}),
      );
    });

    it("ne liste ni ne lit ses données métier", async () => {
      await assertFails(
        asUnverified(U).collection("properties").where("landlordId", "==", U).get(),
      );
      await assertFails(asUnverified(U).doc(`properties/prop-${U}`).get());
    });

    it("ne modifie pas un bien", async () => {
      await assertFails(
        asUnverified(U).doc(`properties/prop-${U}`).update({name: "Renommé"}),
      );
    });

    it("n'écrit pas paid_plan_interest", async () => {
      await assertFails(
        asUnverified(U).doc(`paid_plan_interest/${U}`).set({features: ["a"]}),
      );
    });

    it("ne modifie pas un scénario d'investissement", async () => {
      await assertFails(
        asUnverified(U)
          .doc(`investment_scenarios/scn-${U}`)
          .update({name: "Renommé"}),
      );
    });
  });

  // --- Comptes de confiance : vérifié, Google, Apple ---------------------
  describe.each([
    ["email vérifié", "o2-verified", asVerified],
    ["Google (email_verified absent/false)", "o2-google", asGoogle],
    ["Apple (email_verified absent)", "o2-apple", asApple],
  ] as const)("compte de confiance — %s", (_label, uid, as) => {
    it("lit et met à jour son doc landlord", async () => {
      await assertSucceeds(as(uid).doc(`landlords/${uid}`).get());
      await assertSucceeds(
        as(uid).doc(`landlords/${uid}`).update({fullName: "Nom modifié"}),
      );
    });

    it("liste et lit ses données métier", async () => {
      await assertSucceeds(
        as(uid).collection("properties").where("landlordId", "==", uid).get(),
      );
      await assertSucceeds(as(uid).doc(`properties/prop-${uid}`).get());
    });

    it("modifie un bien, un scénario, écrit paid_plan_interest", async () => {
      await assertSucceeds(
        as(uid).doc(`properties/prop-${uid}`).update({name: "Renommé"}),
      );
      await assertSucceeds(
        as(uid).doc(`investment_scenarios/scn-${uid}`).update({name: "Renommé"}),
      );
      await assertSucceeds(
        as(uid).doc(`paid_plan_interest/${uid}`).set({features: ["a"]}),
      );
    });

    it("cross-user : ne lit toujours pas les données d'un autre bailleur", async () => {
      await assertFails(as(uid).doc("properties/doc-a").get());
      await assertFails(
        as(uid).collection("properties").where("landlordId", "==", LANDLORD_A).get(),
      );
    });
  });

  // --- Anonyme : comportement strictement inchangé ------------------------
  describe("compte anonyme — comportement inchangé", () => {
    it("lit son doc landlord et liste ses scénarios", async () => {
      await assertSucceeds(asAnonymous(ANON).doc(`landlords/${ANON}`).get());
      await assertSucceeds(
        asAnonymous(ANON)
          .collection("investment_scenarios")
          .where("landlordId", "==", ANON)
          .get(),
      );
    });

    it("renouvelle anonExpiresAt (update anonyme)", async () => {
      await assertSucceeds(
        asAnonymous(ANON)
          .doc(`landlords/${ANON}`)
          .update({anonExpiresAt: new Date(Date.now() + 24 * 3600 * 1000)}),
      );
    });

    it("modifie son scénario (simulateur)", async () => {
      await assertSucceeds(
        asAnonymous(ANON)
          .doc(`investment_scenarios/scn-${ANON}`)
          .update({name: "Renommé"}),
      );
    });

    it("provisionne son doc landlord anonyme", async () => {
      await assertSucceeds(
        asAnonymous("o2-anon-new")
          .doc("landlords/o2-anon-new")
          .set({
            id: "o2-anon-new",
            email: null,
            fullName: "",
            isAnonymous: true,
            subscriptionTier: "anonymous",
            anonExpiresAt: new Date(Date.now() + 7 * 24 * 3600 * 1000),
            rgpdConsentAt: null,
            deletedAt: null,
          }),
      );
    });

    it("n'accède toujours pas aux chemins « compte complet »", async () => {
      await assertFails(
        asAnonymous(ANON).doc(`paid_plan_interest/${ANON}`).set({features: ["a"]}),
      );
      await assertFails(
        asAnonymous(ANON).doc(`properties/prop-${ANON}`).update({name: "x"}),
      );
    });
  });
});

describe("_ops — configuration serveur, aucun accès client (FEAT-044e)", () => {
  it("un compte (même listé) ne lit pas la liste blanche sandbox", async () => {
    await assertFails(asOwnerA().doc("_ops/sandboxAllowlist").get());
  });
  it("un compte ne peut pas s'ajouter à la liste", async () => {
    await assertFails(
      asOwnerA().doc("_ops/sandboxAllowlist").set({uids: [LANDLORD_A]}),
    );
  });
  it("un compte ne peut pas créer d'autre document _ops", async () => {
    await assertFails(asOwnerA().doc("_ops/autre").set({x: 1}));
  });
  it("un autre compte ne lit ni ne liste _ops", async () => {
    await assertFails(asOtherB().doc("_ops/sandboxAllowlist").get());
    await assertFails(asOtherB().collection("_ops").get());
  });
  it("un compte ne peut pas supprimer la liste", async () => {
    await assertFails(asOwnerA().doc("_ops/sandboxAllowlist").delete());
  });
  it("un non-authentifié ne lit ni n'écrit _ops", async () => {
    const db = env.unauthenticatedContext().firestore();
    await assertFails(db.doc("_ops/sandboxAllowlist").get());
    await assertFails(db.doc("_ops/sandboxAllowlist").set({uids: ["x"]}));
  });
});
