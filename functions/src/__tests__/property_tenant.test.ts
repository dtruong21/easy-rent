import type {CallableRequest} from "firebase-functions/v2/https";
import {beforeEach, describe, expect, it, vi} from "vitest";

import {createProperty, createTenant} from "../callable/property_tenant";
import {softDeleteEntity} from "../callable/soft_delete";

import {
  FakeFirestore,
  fakeAdminFirestoreHolder,
  fakeStagingFirestoreHolder,
} from "./helpers/fake_firestore";
import {VERIFIED_TOKEN} from "./helpers/verified_token";

// Cf. expenses.test.ts pour la justification du import() dynamique interne.
vi.mock("firebase-admin", async () => {
  const {makeFakeAdminModule} = await import("./helpers/fake_firestore");
  return makeFakeAdminModule();
});

let fakeDb: FakeFirestore;
let fakeStagingDb: FakeFirestore;

function makeRequest(uid: string | null, data: unknown): CallableRequest {
  return {
    data,
    auth: uid ? {uid, token: VERIFIED_TOKEN, rawToken: ""} : undefined,
    rawRequest: {} as never,
  } as CallableRequest;
}

const UID = "landlord-a";

/** Payload minimal valide (champs requis par la validation CF). */
function validPayload(extra: Record<string, unknown> = {}) {
  return {
    name: "Appartement Bastille",
    address: "12 rue de la Roquette",
    type: "appartement",
    hasElevator: false,
    furnished: false,
    isNewProperty: false,
    ...extra,
  };
}

function seedLandlord(tier: string, count: number | undefined) {
  const data: Record<string, unknown> = {
    id: UID,
    landlordId: UID,
    subscriptionTier: tier,
    deletedAt: null,
  };
  if (count !== undefined) data.activePropertiesCount = count;
  fakeDb.seed(`landlords/${UID}`, data);
}

/** Bien actif (non soft-deleted, sans bail actif) appartenant à [UID]. */
function seedProperty(id: string) {
  fakeDb.seed(`properties/${id}`, {
    id,
    landlordId: UID,
    name: "Bien legacy",
    type: "appartement",
    deletedAt: null,
    activeLeaseCount: 0,
  });
}

beforeEach(() => {
  fakeDb = new FakeFirestore();
  fakeAdminFirestoreHolder.db = fakeDb;
  // Base `staging` fraîche à chaque test (vide → un appel mobile dont le
  // landlord est en prod retombe sur la prod, comme avant le routage par compte).
  fakeStagingDb = new FakeFirestore();
  fakeStagingFirestoreHolder.db = fakeStagingDb;
});

describe("createProperty — gating free-tier (FEAT-044)", () => {
  it("free sous le plafond → crée le bien et incrémente le compteur", async () => {
    seedLandlord("free", 0);

    const res = await createProperty.run(makeRequest(UID, validPayload()));

    const propertyId = (res as {propertyId: string}).propertyId;
    expect(propertyId).toBeTruthy();
    const prop = fakeDb.peek(`properties/${propertyId}`);
    expect(prop?.landlordId).toBe(UID);
    expect(prop?.name).toBe("Appartement Bastille");
    expect(prop?.type).toBe("appartement");
    expect(prop?.id).toBe(propertyId);
    expect(prop?.deletedAt).toBeNull();
    expect(prop?.activeLeaseCount).toBe(0);
    // compteur landlord incrémenté 0 -> 1
    expect(fakeDb.peek(`landlords/${UID}`)?.activePropertiesCount).toBe(1);
  });

  it("free à 1 bien (sous plafond 2) → crée, compteur -> 2", async () => {
    seedLandlord("free", 1);
    await createProperty.run(makeRequest(UID, validPayload()));
    expect(fakeDb.peek(`landlords/${UID}`)?.activePropertiesCount).toBe(2);
  });

  it("free AU plafond (2) → refus resource-exhausted, rien créé", async () => {
    seedLandlord("free", 2);

    await expect(
      createProperty.run(makeRequest(UID, validPayload())),
    ).rejects.toMatchObject({
      code: "resource-exhausted",
      message: "property_limit_reached",
    });
    // compteur inchangé, aucun bien créé
    expect(fakeDb.peek(`landlords/${UID}`)?.activePropertiesCount).toBe(2);
  });

  it("paid (→ pro) : crée au-delà du plafond free, mais reste borné à 5", async () => {
    // PR-7 : les paliers payants ne sont plus illimités. Un doc `paid` sans
    // `planLevel` se dérive en `pro` → plafond 5.
    seedLandlord("paid", 4);
    const res = await createProperty.run(makeRequest(UID, validPayload()));
    expect((res as {propertyId: string}).propertyId).toBeTruthy();
    expect(fakeDb.peek(`landlords/${UID}`)?.activePropertiesCount).toBe(5);
  });

  it("paid (→ pro) AU plafond (5) → refus resource-exhausted", async () => {
    seedLandlord("paid", 5);
    await expect(
      createProperty.run(makeRequest(UID, validPayload())),
    ).rejects.toMatchObject({
      code: "resource-exhausted",
      message: "property_limit_reached",
    });
    expect(fakeDb.peek(`landlords/${UID}`)?.activePropertiesCount).toBe(5);
  });

  it("anonymous → refus même à 0 bien (registre réservé aux comptes)", async () => {
    seedLandlord("anonymous", 0);
    await expect(
      createProperty.run(makeRequest(UID, validPayload())),
    ).rejects.toMatchObject({code: "resource-exhausted"});
  });

  it("compteur absent + 0 bien (legacy) → recompte 0, crée, sème le compteur à 1", async () => {
    seedLandlord("free", undefined);
    const res = await createProperty.run(makeRequest(UID, validPayload()));
    expect((res as {propertyId: string}).propertyId).toBeTruthy();
    // compteur semé via recompte live (0) + 1
    expect(fakeDb.peek(`landlords/${UID}`)?.activePropertiesCount).toBe(1);
  });

  it("FAIL-CLOSED : compteur absent + 2 biens existants (legacy) → refus", async () => {
    // Régression du finding HIGH : sans recompte, un compteur absent lu comme
    // 0 laisserait un free déjà à 2 biens en créer 2 de plus.
    seedLandlord("free", undefined);
    seedProperty("p-legacy-1");
    seedProperty("p-legacy-2");
    await expect(
      createProperty.run(makeRequest(UID, validPayload())),
    ).rejects.toMatchObject({code: "resource-exhausted"});
  });

  it("tier inconnu → traité comme le plus restrictif (refus)", async () => {
    seedLandlord("mystery", 0);
    await expect(
      createProperty.run(makeRequest(UID, validPayload())),
    ).rejects.toMatchObject({code: "resource-exhausted"});
  });

  it("landlord introuvable → not-found", async () => {
    // pas de seed landlord
    await expect(
      createProperty.run(makeRequest(UID, validPayload())),
    ).rejects.toMatchObject({code: "not-found"});
  });

  it("non authentifié → unauthenticated", async () => {
    await expect(
      createProperty.run(makeRequest(null, validPayload())),
    ).rejects.toMatchObject({code: "unauthenticated"});
  });

  it("type invalide → invalid-argument (pas de bien créé)", async () => {
    seedLandlord("free", 0);
    await expect(
      createProperty.run(makeRequest(UID, validPayload({type: "chateau"}))),
    ).rejects.toMatchObject({code: "invalid-argument"});
    expect(fakeDb.peek(`landlords/${UID}`)?.activePropertiesCount).toBe(0);
  });

  it("name vide → invalid-argument", async () => {
    seedLandlord("free", 0);
    await expect(
      createProperty.run(makeRequest(UID, validPayload({name: ""}))),
    ).rejects.toMatchObject({code: "invalid-argument"});
  });
});

describe("cycle de vie du compteur (create ↔ soft-delete)", () => {
  it("soft-delete d'un bien décrémente activePropertiesCount → slot libéré", async () => {
    seedLandlord("free", 0);

    // free crée 2 biens (au plafond)
    const p1 = await createProperty.run(makeRequest(UID, validPayload()));
    await createProperty.run(makeRequest(UID, validPayload()));
    expect(fakeDb.peek(`landlords/${UID}`)?.activePropertiesCount).toBe(2);

    // 3ᵉ refusé (au plafond)
    await expect(
      createProperty.run(makeRequest(UID, validPayload())),
    ).rejects.toMatchObject({code: "resource-exhausted"});

    // archive le 1er → compteur revient à 1
    const id1 = (p1 as {propertyId: string}).propertyId;
    await softDeleteEntity.run(
      makeRequest(UID, {collection: "properties", id: id1}),
    );
    expect(fakeDb.peek(`landlords/${UID}`)?.activePropertiesCount).toBe(1);

    // et un nouveau bien passe de nouveau
    const p3 = await createProperty.run(makeRequest(UID, validPayload()));
    expect((p3 as {propertyId: string}).propertyId).toBeTruthy();
    expect(fakeDb.peek(`landlords/${UID}`)?.activePropertiesCount).toBe(2);
  });

  it("double soft-delete du même bien ne décrémente qu'une fois (idempotent)", async () => {
    seedLandlord("free", 0);
    const p1 = await createProperty.run(makeRequest(UID, validPayload()));
    const id1 = (p1 as {propertyId: string}).propertyId;

    await softDeleteEntity.run(
      makeRequest(UID, {collection: "properties", id: id1}),
    );
    const second = await softDeleteEntity.run(
      makeRequest(UID, {collection: "properties", id: id1}),
    );
    expect((second as {alreadyDeleted: boolean}).alreadyDeleted).toBe(true);
    // décrémenté une seule fois : 1 -> 0, pas -1
    expect(fakeDb.peek(`landlords/${UID}`)?.activePropertiesCount).toBe(0);
  });

  it("CLAMP : soft-delete d'un bien avec compteur landlord absent → jamais négatif", async () => {
    // Régression du finding MEDIUM : décrément blind increment(-1) sur compteur
    // absent (legacy) l'aurait poussé à -1, rouvrant le gate.
    fakeDb.seed(`landlords/${UID}`, {
      id: UID,
      landlordId: UID,
      subscriptionTier: "free",
      deletedAt: null,
    });
    seedProperty("p-1");

    await softDeleteEntity.run(
      makeRequest(UID, {collection: "properties", id: "p-1"}),
    );

    // le bien est soft-deleted, le compteur absent n'est PAS écrit à -1
    expect(fakeDb.peek("properties/p-1")?.deletedAt).toBeInstanceOf(Date);
    expect(
      fakeDb.peek(`landlords/${UID}`)?.activePropertiesCount,
    ).toBeUndefined();
  });
});

describe("createTenant — gating free-tier (FEAT-044)", () => {
  const tenantPayload = (extra: Record<string, unknown> = {}) => ({
    firstName: "Jean",
    lastName: "Dupont",
    email: "jean.dupont@example.com",
    ...extra,
  });

  function seedTenantDoc(id: string) {
    fakeDb.seed(`tenants/${id}`, {
      id,
      landlordId: UID,
      firstName: "Legacy",
      lastName: "Tenant",
      email: "legacy@example.com",
      deletedAt: null,
      activeLeaseCount: 0,
    });
  }

  function seedLandlordTenants(tier: string, count: number | undefined) {
    const data: Record<string, unknown> = {
      id: UID,
      landlordId: UID,
      subscriptionTier: tier,
      deletedAt: null,
    };
    if (count !== undefined) data.activeTenantsCount = count;
    fakeDb.seed(`landlords/${UID}`, data);
  }

  it("free sous le plafond (3) → crée + incrémente activeTenantsCount", async () => {
    seedLandlordTenants("free", 2);
    const res = await createTenant.run(makeRequest(UID, tenantPayload()));
    const tenantId = (res as {tenantId: string}).tenantId;
    expect(tenantId).toBeTruthy();
    expect(fakeDb.peek(`tenants/${tenantId}`)?.landlordId).toBe(UID);
    expect(fakeDb.peek(`landlords/${UID}`)?.activeTenantsCount).toBe(3);
  });

  it("free AU plafond (3) → refus resource-exhausted", async () => {
    seedLandlordTenants("free", 3);
    await expect(
      createTenant.run(makeRequest(UID, tenantPayload())),
    ).rejects.toMatchObject({
      code: "resource-exhausted",
      message: "tenant_limit_reached",
    });
  });

  it("paid (→ pro) : crée au-delà du plafond free, mais reste borné à 8", async () => {
    seedLandlordTenants("paid", 7);
    const res = await createTenant.run(makeRequest(UID, tenantPayload()));
    expect((res as {tenantId: string}).tenantId).toBeTruthy();
    expect(fakeDb.peek(`landlords/${UID}`)?.activeTenantsCount).toBe(8);
  });

  it("paid (→ pro) AU plafond (8) → refus resource-exhausted", async () => {
    seedLandlordTenants("paid", 8);
    await expect(
      createTenant.run(makeRequest(UID, tenantPayload())),
    ).rejects.toMatchObject({
      code: "resource-exhausted",
      message: "tenant_limit_reached",
    });
  });

  it("anonymous → refus", async () => {
    seedLandlordTenants("anonymous", 0);
    await expect(
      createTenant.run(makeRequest(UID, tenantPayload())),
    ).rejects.toMatchObject({code: "resource-exhausted"});
  });

  it("FAIL-CLOSED : compteur absent + 3 locataires existants → refus", async () => {
    seedLandlordTenants("free", undefined);
    seedTenantDoc("t-1");
    seedTenantDoc("t-2");
    seedTenantDoc("t-3");
    await expect(
      createTenant.run(makeRequest(UID, tenantPayload())),
    ).rejects.toMatchObject({code: "resource-exhausted"});
  });

  it("email invalide → invalid-argument", async () => {
    seedLandlordTenants("free", 0);
    await expect(
      createTenant.run(makeRequest(UID, tenantPayload({email: "pasunemail"}))),
    ).rejects.toMatchObject({code: "invalid-argument"});
  });
});

describe("softDeleteEntity — décréments landlord (FEAT-044 tenant + bail)", () => {
  it("soft-delete d'un locataire décrémente activeTenantsCount (clampé)", async () => {
    fakeDb.seed(`landlords/${UID}`, {
      id: UID,
      landlordId: UID,
      subscriptionTier: "free",
      activeTenantsCount: 2,
      deletedAt: null,
    });
    fakeDb.seed("tenants/t-1", {
      id: "t-1",
      landlordId: UID,
      deletedAt: null,
      activeLeaseCount: 0,
    });
    await softDeleteEntity.run(
      makeRequest(UID, {collection: "tenants", id: "t-1"}),
    );
    expect(fakeDb.peek(`landlords/${UID}`)?.activeTenantsCount).toBe(1);
  });

  it("soft-delete d'un bail ACTIF décrémente activeLeasesCount du bailleur", async () => {
    fakeDb.seed(`landlords/${UID}`, {
      id: UID,
      landlordId: UID,
      subscriptionTier: "free",
      activeLeasesCount: 2,
      deletedAt: null,
    });
    seedProperty("p-1");
    fakeDb.seed("tenants/t-1", {
      id: "t-1",
      landlordId: UID,
      deletedAt: null,
      activeLeaseCount: 1,
    });
    fakeDb.seed("leases/l-1", {
      id: "l-1",
      landlordId: UID,
      propertyId: "p-1",
      tenantId: "t-1",
      status: "active",
      deletedAt: null,
    });
    await softDeleteEntity.run(
      makeRequest(UID, {collection: "leases", id: "l-1"}),
    );
    expect(fakeDb.peek(`landlords/${UID}`)?.activeLeasesCount).toBe(1);
  });

  it("soft-delete d'un bail TERMINÉ ne touche pas activeLeasesCount", async () => {
    fakeDb.seed(`landlords/${UID}`, {
      id: UID,
      landlordId: UID,
      subscriptionTier: "free",
      activeLeasesCount: 2,
      deletedAt: null,
    });
    fakeDb.seed("leases/l-1", {
      id: "l-1",
      landlordId: UID,
      propertyId: "p-1",
      tenantId: "t-1",
      status: "terminated",
      deletedAt: null,
    });
    await softDeleteEntity.run(
      makeRequest(UID, {collection: "leases", id: "l-1"}),
    );
    expect(fakeDb.peek(`landlords/${UID}`)?.activeLeasesCount).toBe(2);
  });
});

// ============================================================================
// FEAT-056 — le plafond se résout sur le PALIER EFFECTIF, pas sur la classe
// d'accès. Ces cas s'ajoutent aux précédents ; aucun d'eux ne les remplace :
// le freemium doit se comporter EXACTEMENT comme avant.
// ============================================================================
describe("createProperty / createTenant — palier effectif (FEAT-056)", () => {
  function seedPlan(
    tier: string,
    planLevel: string | null,
    counts: Record<string, number>,
  ) {
    const data: Record<string, unknown> = {
      id: UID,
      landlordId: UID,
      subscriptionTier: tier,
      deletedAt: null,
      ...counts,
    };
    if (planLevel !== null) data.planLevel = planLevel;
    fakeDb.seed(`landlords/${UID}`, data);
  }

  it("paid SANS planLevel (abonné d'avant FEAT-056) → servi aux plafonds pro", async () => {
    // I3 : la dérivation vaut `pro`, donc plafond 5 — plus illimité depuis PR-7.
    seedPlan("paid", null, {activePropertiesCount: 4});
    const res = await createProperty.run(makeRequest(UID, validPayload()));
    expect((res as {propertyId: string}).propertyId).toBeTruthy();

    fakeDb = new FakeFirestore();
    fakeAdminFirestoreHolder.db = fakeDb;
    seedPlan("paid", null, {activePropertiesCount: 5});
    await expect(
      createProperty.run(makeRequest(UID, validPayload())),
    ).rejects.toMatchObject({
      code: "resource-exhausted",
      message: "property_limit_reached",
    });
  });

  it("chaque palier payant est servi par SA propre clé de table", async () => {
    // Les plafonds DIFFÈRENT entre paliers (5 / 15 / illimité) : un compte à 5
    // biens est refusé en pro et accepté en max. Un gating indexé sur la classe
    // d'accès `paid` donnerait le même verdict aux trois — ce test le détecte.
    const propertyLimits: Array<[string, number | null]> = [
      ["pro", 5],
      ["max", 15],
      ["ultra", null],
    ];
    for (const [level, limit] of propertyLimits) {
      // Juste SOUS le plafond du palier (ou très haut si illimité) → passe.
      fakeDb = new FakeFirestore();
      fakeAdminFirestoreHolder.db = fakeDb;
      seedPlan("paid", level, {activePropertiesCount: limit === null ? 500 : limit - 1});
      const res = await createProperty.run(makeRequest(UID, validPayload()));
      expect((res as {propertyId: string}).propertyId).toBeTruthy();

      if (limit === null) continue; // ultra : aucun plafond à franchir
      // AU plafond du palier → refus.
      fakeDb = new FakeFirestore();
      fakeAdminFirestoreHolder.db = fakeDb;
      seedPlan("paid", level, {activePropertiesCount: limit});
      await expect(
        createProperty.run(makeRequest(UID, validPayload())),
      ).rejects.toMatchObject({
        code: "resource-exhausted",
        message: "property_limit_reached",
      });
    }
  });

  it("planLevel inconnu sur un compte payant → servi comme pro, pas verrouillé", async () => {
    // Fail-UP (I4) : le pire échec serait de traiter en anonyme un abonné qui
    // paie parce que le serveur ne connaît pas encore son palier. Il obtient le
    // plafond pro (5) — au-dessus de free (2), en-dessous de max.
    seedPlan("paid", "quantum", {activePropertiesCount: 4});
    const res = await createProperty.run(makeRequest(UID, validPayload()));
    expect((res as {propertyId: string}).propertyId).toBeTruthy();

    fakeDb = new FakeFirestore();
    fakeAdminFirestoreHolder.db = fakeDb;
    seedPlan("paid", "quantum", {activePropertiesCount: 5});
    await expect(
      createProperty.run(makeRequest(UID, validPayload())),
    ).rejects.toMatchObject({code: "resource-exhausted"});
  });

  it("planLevel posé sur un compte FREE ne débloque rien", async () => {
    seedPlan("free", "ultra", {activePropertiesCount: 2});
    await expect(
      createProperty.run(makeRequest(UID, validPayload())),
    ).rejects.toMatchObject({
      code: "resource-exhausted",
      message: "property_limit_reached",
    });
  });

  it("createTenant : même dérivation (paid legacy → plafonds pro)", async () => {
    seedPlan("paid", null, {activeTenantsCount: 7});
    const res = await createTenant.run(
      makeRequest(UID, {
        firstName: "Jean",
        lastName: "Dupont",
        email: "jean@example.com",
      }),
    );
    expect((res as {tenantId: string}).tenantId).toBeTruthy();

    fakeDb = new FakeFirestore();
    fakeAdminFirestoreHolder.db = fakeDb;
    seedPlan("paid", null, {activeTenantsCount: 8});
    await expect(
      createTenant.run(
        makeRequest(UID, {
          firstName: "Jean",
          lastName: "Dupont",
          email: "jean@example.com",
        }),
      ),
    ).rejects.toMatchObject({
      code: "resource-exhausted",
      message: "tenant_limit_reached",
    });
  });

  it("createTenant : planLevel sur compte free ne débloque rien", async () => {
    seedPlan("free", "max", {activeTenantsCount: 3});
    await expect(
      createTenant.run(
        makeRequest(UID, {
          firstName: "Jean",
          lastName: "Dupont",
          email: "jean@example.com",
        }),
      ),
    ).rejects.toMatchObject({
      code: "resource-exhausted",
      message: "tenant_limit_reached",
    });
  });
});

// ============================================================================
// Routage par compte des callables mobiles (build de test Test Lab, ADR 0003) :
// `dbForRequest` sans Origin → base qui porte `landlords/{uid}`. `makeRequest`
// n'envoie aucun en-tête (`rawRequest: {}`), donc c'est un appel « mobile ».
// ============================================================================
describe("createProperty — routage mobile par compte (ADR 0003)", () => {
  it("mobile sans Origin, landlord uniquement en staging → bien écrit en staging, rien en prod", async () => {
    // Le compte de test n'existe que dans la base `staging` (pas en prod).
    fakeStagingDb.seed(`landlords/${UID}`, {
      id: UID,
      landlordId: UID,
      subscriptionTier: "free",
      deletedAt: null,
      activePropertiesCount: 0,
    });

    const res = await createProperty.run(makeRequest(UID, validPayload()));

    const propertyId = (res as {propertyId: string}).propertyId;
    expect(propertyId).toBeTruthy();
    // Le bien et le compteur atterrissent dans la base staging...
    expect(fakeStagingDb.peek(`properties/${propertyId}`)?.landlordId).toBe(UID);
    expect(fakeStagingDb.peek(`landlords/${UID}`)?.activePropertiesCount).toBe(1);
    // ...et RIEN n'est écrit côté prod (ni bien, ni doc landlord).
    expect(fakeDb.peek(`properties/${propertyId}`)).toBeUndefined();
    expect(fakeDb.peek(`landlords/${UID}`)).toBeUndefined();
  });
});
