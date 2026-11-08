import type {CallableRequest} from "firebase-functions/v2/https";
import {beforeEach, describe, expect, it, vi} from "vitest";

import {softDeleteEntity} from "../callable/soft_delete";

import {FakeFirestore, fakeAdminFirestoreHolder} from "./helpers/fake_firestore";
import {VERIFIED_TOKEN} from "./helpers/verified_token";

// Cf. expenses.test.ts pour la justification du import() dynamique interne
// (le factory `vi.mock` est hoisted au-dessus des imports du fichier).
vi.mock("firebase-admin", async () => {
  const {makeFakeAdminModule} = await import("./helpers/fake_firestore");
  return makeFakeAdminModule();
});

let fakeDb: FakeFirestore;

function makeRequest(uid: string | null, data: unknown): CallableRequest {
  return {
    data,
    auth: uid ? {uid, token: VERIFIED_TOKEN, rawToken: ""} : undefined,
    rawRequest: {} as never,
  } as CallableRequest;
}

const LANDLORD_A = "landlord-a";

beforeEach(() => {
  fakeDb = new FakeFirestore();
  fakeAdminFirestoreHolder.db = fakeDb;
});

/**
 * Régression : soft-delete d'un bail. `softDeleteEntity('leases')` doit
 * décrémenter le `activeLeaseCount` dénormalisé du bien ET du locataire
 * parents — miroir exact de l'incrément de createLease — mais UNIQUEMENT
 * pour un bail actif (un bail terminé/archivé a déjà été décompté lors de sa
 * transition de status). Sans ce décompte, le compteur restait gonflé et le
 * bien devenait indéfiniment non-supprimable (garde RESTRICT du soft-delete
 * properties/tenants).
 */
describe("softDeleteEntity('leases') — décompte activeLeaseCount", () => {
  function seedLease(id: string, extra: Record<string, unknown> = {}) {
    fakeDb.seed(`leases/${id}`, {
      id,
      landlordId: LANDLORD_A,
      propertyId: "prop-1",
      tenantId: "tenant-1",
      status: "active",
      deletedAt: null,
      updatedAt: new Date("2026-01-01T00:00:00Z"),
      ...extra,
    });
  }

  function seedParents(propertyCount: number, tenantCount: number) {
    fakeDb.seed("properties/prop-1", {
      id: "prop-1",
      landlordId: LANDLORD_A,
      activeLeaseCount: propertyCount,
      deletedAt: null,
    });
    fakeDb.seed("tenants/tenant-1", {
      id: "tenant-1",
      landlordId: LANDLORD_A,
      activeLeaseCount: tenantCount,
      deletedAt: null,
    });
  }

  it("décrémente le bien ET le locataire quand le bail était actif", async () => {
    seedLease("lease-1");
    seedParents(1, 1);

    const result = await softDeleteEntity.run(
      makeRequest(LANDLORD_A, {collection: "leases", id: "lease-1"}),
    );

    expect(result.alreadyDeleted).toBe(false);
    expect(fakeDb.peek("leases/lease-1")?.deletedAt).toBeInstanceOf(Date);
    expect(fakeDb.peek("properties/prop-1")?.activeLeaseCount).toBe(0);
    expect(fakeDb.peek("tenants/tenant-1")?.activeLeaseCount).toBe(0);
  });

  it("ne décrémente PAS un bail terminé (déjà décompté à la transition)", async () => {
    seedLease("lease-1", {status: "terminated"});
    seedParents(2, 2);

    await softDeleteEntity.run(
      makeRequest(LANDLORD_A, {collection: "leases", id: "lease-1"}),
    );

    expect(fakeDb.peek("leases/lease-1")?.deletedAt).toBeInstanceOf(Date);
    expect(fakeDb.peek("properties/prop-1")?.activeLeaseCount).toBe(2);
    expect(fakeDb.peek("tenants/tenant-1")?.activeLeaseCount).toBe(2);
  });

  it("ne décrémente PAS un bail archivé", async () => {
    seedLease("lease-1", {status: "archived"});
    seedParents(1, 1);

    await softDeleteEntity.run(
      makeRequest(LANDLORD_A, {collection: "leases", id: "lease-1"}),
    );

    expect(fakeDb.peek("properties/prop-1")?.activeLeaseCount).toBe(1);
    expect(fakeDb.peek("tenants/tenant-1")?.activeLeaseCount).toBe(1);
  });

  it("est idempotent : un 2ᵉ appel ne re-décrémente pas", async () => {
    seedLease("lease-1");
    seedParents(1, 1);

    await softDeleteEntity.run(
      makeRequest(LANDLORD_A, {collection: "leases", id: "lease-1"}),
    );
    const second = await softDeleteEntity.run(
      makeRequest(LANDLORD_A, {collection: "leases", id: "lease-1"}),
    );

    expect(second.alreadyDeleted).toBe(true);
    // Le court-circuit `deletedAt != null` retourne avant tout décompte :
    // le compteur reste à 0, il ne descend pas à -1.
    expect(fakeDb.peek("properties/prop-1")?.activeLeaseCount).toBe(0);
    expect(fakeDb.peek("tenants/tenant-1")?.activeLeaseCount).toBe(0);
  });
});
