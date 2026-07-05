import type {CallableRequest} from "firebase-functions/v2/https";
import {HttpsError} from "firebase-functions/v2/https";
import {beforeEach, describe, expect, it, vi} from "vitest";

import {softDeleteEntity} from "../callable/soft_delete";

import {FakeFirestore, fakeAdminFirestoreHolder} from "./helpers/fake_firestore";

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
    auth: uid ? {uid, token: {} as never, rawToken: ""} : undefined,
    rawRequest: {} as never,
  } as CallableRequest;
}

const LANDLORD_A = "landlord-a";
const LANDLORD_B = "landlord-b";

beforeEach(() => {
  fakeDb = new FakeFirestore();
  fakeAdminFirestoreHolder.db = fakeDb;
});

describe("softDeleteEntity('expenses')", () => {
  function seedExpense(id: string, extra: Record<string, unknown> = {}) {
    fakeDb.seed(`expenses/${id}`, {
      id,
      landlordId: LANDLORD_A,
      propertyId: "prop-1",
      amountCents: 10000,
      deletedAt: null,
      updatedAt: new Date("2026-01-01T00:00:00Z"),
      ...extra,
    });
  }

  it("accepte 'expenses' comme collection soft-deletable", async () => {
    seedExpense("exp-1");

    const result = await softDeleteEntity.run(
      makeRequest(LANDLORD_A, {collection: "expenses", id: "exp-1"}),
    );
    expect(result.alreadyDeleted).toBe(false);
    expect(fakeDb.peek("expenses/exp-1")?.deletedAt).toBeInstanceOf(Date);
  });

  it("refuse si l'appelant n'est pas le propriétaire", async () => {
    seedExpense("exp-1");

    await expect(
      softDeleteEntity.run(
        makeRequest(LANDLORD_B, {collection: "expenses", id: "exp-1"}),
      ),
    ).rejects.toMatchObject({code: "permission-denied"});
  });

  it("est idempotent (deuxième appel → alreadyDeleted: true)", async () => {
    seedExpense("exp-1");

    await softDeleteEntity.run(
      makeRequest(LANDLORD_A, {collection: "expenses", id: "exp-1"}),
    );
    const second = await softDeleteEntity.run(
      makeRequest(LANDLORD_A, {collection: "expenses", id: "exp-1"}),
    );
    expect(second.alreadyDeleted).toBe(true);
  });

  it("n'a aucune garde métier propre (pas de blocage sur activeLeaseCount/legalHold)", async () => {
    // Contrairement à properties/tenants (activeLeaseCount) et documents
    // (legalHold), une expense n'a pas de garde propre — cf. plan §b.
    seedExpense("exp-1", {activeLeaseCount: 5, legalHold: true});

    const result = await softDeleteEntity.run(
      makeRequest(LANDLORD_A, {collection: "expenses", id: "exp-1"}),
    );
    expect(result.alreadyDeleted).toBe(false);
  });

  it("refuse une collection non listée dans SOFT_DELETABLE", async () => {
    await expect(
      softDeleteEntity.run(
        makeRequest(LANDLORD_A, {collection: "receipts", id: "r-1"}),
      ),
    ).rejects.toThrowError(HttpsError);
  });

  it("le documentId (justificatif) lié à une dépense soft-deleted n'est pas touché — legalHold survit", async () => {
    seedExpense("exp-1", {documentId: "doc-1"});
    fakeDb.seed("documents/doc-1", {
      id: "doc-1",
      landlordId: LANDLORD_A,
      legalHold: true,
      deletedAt: null,
    });

    await softDeleteEntity.run(
      makeRequest(LANDLORD_A, {collection: "expenses", id: "exp-1"}),
    );

    // La dépense est soft-deleted...
    expect(fakeDb.peek("expenses/exp-1")?.deletedAt).toBeInstanceOf(Date);
    // ... mais le document justificatif reste totalement intact (legalHold
    // toujours true, deletedAt toujours null) — softDeleteEntity('expenses')
    // ne touche jamais `documents` (aucune cascade).
    const doc = fakeDb.peek("documents/doc-1");
    expect(doc?.legalHold).toBe(true);
    expect(doc?.deletedAt).toBeNull();

    // Tenter de soft-delete le document lui-même reste refusé (comportement
    // documents déjà existant, non régressé par FEAT-041a).
    await expect(
      softDeleteEntity.run(
        makeRequest(LANDLORD_A, {collection: "documents", id: "doc-1"}),
      ),
    ).rejects.toMatchObject({
      code: "failed-precondition",
      message: "document_under_legal_hold",
    });
  });
});
