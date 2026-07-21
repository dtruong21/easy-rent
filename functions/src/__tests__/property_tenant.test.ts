import type {CallableRequest} from "firebase-functions/v2/https";
import {beforeEach, describe, expect, it, vi} from "vitest";

import {createProperty, createTenant} from "../callable/property_tenant";
import {softDeleteEntity} from "../callable/soft_delete";

import {FakeFirestore, fakeAdminFirestoreHolder} from "./helpers/fake_firestore";

// Cf. expenses.test.ts pour la justification du import() dynamique interne.
vi.mock("firebase-admin", async () => {
  const {makeFakeAdminModule} = await import("./helpers/fake_firestore");
  return makeFakeAdminModule();
});

let fakeDb: FakeFirestore;

function makeRequest(uid: string | null, data: unknown): CallableRequest {
  return {
    data,
    auth: uid ? {uid, token: {} as never, rawToken: ""} : undefined,
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

  it("paid → illimité (crée même au-delà de 2)", async () => {
    seedLandlord("paid", 50);
    const res = await createProperty.run(makeRequest(UID, validPayload()));
    expect((res as {propertyId: string}).propertyId).toBeTruthy();
    expect(fakeDb.peek(`landlords/${UID}`)?.activePropertiesCount).toBe(51);
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

  it("paid → illimité", async () => {
    seedLandlordTenants("paid", 99);
    const res = await createTenant.run(makeRequest(UID, tenantPayload()));
    expect((res as {tenantId: string}).tenantId).toBeTruthy();
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
