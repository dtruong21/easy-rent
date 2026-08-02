/**
 * Purge Storage au soft-delete d'un document.
 *
 * Contexte du bug corrigé : `storage.rules` pose `allow delete: if false` sur
 * `documents/{landlordId}/**`, donc le nettoyage qui vivait côté client
 * (`documents_repository.dart`) était TOUJOURS refusé et avalé par un catch.
 * Chaque document supprimé laissait son fichier dans le bucket — coût facturé
 * et droit à l'effacement RGPD non honoré. Le nettoyage vit désormais dans le
 * callable, où l'Admin SDK outrepasse les Storage Rules.
 */

import type {CallableRequest} from "firebase-functions/v2/https";
import {beforeEach, describe, expect, it, vi} from "vitest";

import {softDeleteEntity} from "../callable/soft_delete";

import {
  FakeFirestore,
  FakeStorage,
  fakeAdminFirestoreHolder,
} from "./helpers/fake_firestore";

// Cf. expenses.test.ts pour la justification du pattern de mock hoisted.
vi.mock("firebase-admin", async () => {
  const {makeFakeAdminModule} = await import("./helpers/fake_firestore");
  return makeFakeAdminModule();
});

let fakeDb: FakeFirestore;
let fakeStorage: FakeStorage;

function makeRequest(uid: string | null, data: unknown): CallableRequest {
  return {
    data,
    auth: uid ? {uid, token: {} as never, rawToken: ""} : undefined,
    rawRequest: {} as never,
  } as CallableRequest;
}

const LANDLORD_A = "landlord-a";
const LANDLORD_B = "landlord-b";
const STORAGE_PATH = `documents/${LANDLORD_A}/doc-1.pdf`;

beforeEach(() => {
  fakeDb = new FakeFirestore();
  fakeStorage = new FakeStorage();
  fakeAdminFirestoreHolder.db = fakeDb;
  fakeAdminFirestoreHolder.storage = fakeStorage;
});

function seedDocument(id: string, extra: Record<string, unknown> = {}) {
  fakeDb.seed(`documents/${id}`, {
    id,
    landlordId: LANDLORD_A,
    leaseId: "lease-1",
    propertyId: null,
    category: "autre",
    filename: "quittance.pdf",
    storagePath: STORAGE_PATH,
    mimeType: "application/pdf",
    sizeBytes: 1024,
    legalHold: false,
    deletedAt: null,
    ...extra,
  });
}

function callSoftDelete(uid = LANDLORD_A, id = "doc-1") {
  return softDeleteEntity.run(
    makeRequest(uid, {collection: "documents", id}),
  );
}

describe("softDeleteEntity('documents') — purge Storage", () => {
  it("document sans legalHold → l'objet Storage est supprimé", async () => {
    seedDocument("doc-1");

    const result = await callSoftDelete();

    expect(result.alreadyDeleted).toBe(false);
    expect(result.storageDeleted).toBe(true);
    expect(fakeStorage.deletedPaths).toContain(STORAGE_PATH);
    expect(fakeDb.peek("documents/doc-1")?.deletedAt).toBeInstanceOf(Date);
  });

  it("document SOUS legalHold → refus, et l'objet est CONSERVÉ", async () => {
    seedDocument("doc-1", {legalHold: true});

    await expect(callSoftDelete()).rejects.toMatchObject({
      code: "failed-precondition",
      message: "document_under_legal_hold",
    });
    // Rétention légale : le fichier doit survivre.
    expect(fakeStorage.deletedPaths).not.toContain(STORAGE_PATH);
    expect(fakeDb.peek("documents/doc-1")?.deletedAt).toBeNull();
  });

  it("non-propriétaire → refus, et l'objet est CONSERVÉ", async () => {
    seedDocument("doc-1");

    await expect(callSoftDelete(LANDLORD_B)).rejects.toMatchObject({
      code: "permission-denied",
    });
    expect(fakeStorage.deletedPaths).toEqual([]);
  });

  it("storagePath absent du doc → pas de purge, pas de crash", async () => {
    seedDocument("doc-1", {storagePath: null});

    const result = await callSoftDelete();

    expect(result.alreadyDeleted).toBe(false);
    expect(result.storageDeleted).toBe(false);
    expect(fakeStorage.deletedPaths).toEqual([]);
  });

  // ------------------------------------------------------------ idempotence
  it("2e appel sur un doc déjà supprimé → RATTRAPE une purge ratée", async () => {
    // C'est le scénario de rattrapage : la 1re purge échoue (GCS down), le
    // document est quand même soft-deleted. Un rejeu doit re-tenter la purge,
    // sinon le fichier reste stranded pour toujours.
    seedDocument("doc-1");
    fakeStorage.deleteError = new Error("GCS down");

    const first = await callSoftDelete();
    expect(first.alreadyDeleted).toBe(false);
    expect(first.storageDeleted).toBe(false); // purge ratée
    expect(fakeStorage.deletedPaths).toEqual([]);

    // GCS revient : le rejeu purge pour de bon.
    fakeStorage.deleteError = null;
    const second = await callSoftDelete();
    expect(second.alreadyDeleted).toBe(true);
    expect(second.storageDeleted).toBe(true);
    expect(fakeStorage.deletedPaths).toContain(STORAGE_PATH);
  });

  it("purge ratée → le soft-delete Firestore reste committé (pas de throw)", async () => {
    seedDocument("doc-1");
    fakeStorage.deleteError = new Error("GCS down");

    const result = await callSoftDelete();

    // Le document est bien supprimé côté Firestore : rendre une erreur ferait
    // croire au client que rien n'a été fait.
    expect(result.storageDeleted).toBe(false);
    expect(fakeDb.peek("documents/doc-1")?.deletedAt).toBeInstanceOf(Date);
  });

  it("objet déjà absent du bucket → succès (ignoreNotFound)", async () => {
    seedDocument("doc-1");
    fakeStorage.existingPaths = new Set(); // rien dans le bucket

    const result = await callSoftDelete();

    expect(result.storageDeleted).toBe(true);
  });

  // -------------------------------------------------- non-régression autres
  it("collection non-documents → aucune purge Storage", async () => {
    fakeDb.seed("expenses/exp-1", {
      id: "exp-1",
      landlordId: LANDLORD_A,
      storagePath: STORAGE_PATH, // piège : ne doit PAS être purgé
      deletedAt: null,
    });

    const result = await softDeleteEntity.run(
      makeRequest(LANDLORD_A, {collection: "expenses", id: "exp-1"}),
    );

    expect(result.alreadyDeleted).toBe(false);
    expect(result.storageDeleted).toBe(false);
    expect(fakeStorage.deletedPaths).toEqual([]);
  });
});
