import type {CallableRequest} from "firebase-functions/v2/https";
import {beforeEach, describe, expect, it, vi} from "vitest";

import {updateDocumentCategory} from "../callable/documents";

import {FakeFirestore, fakeAdminFirestoreHolder} from "./helpers/fake_firestore";
import {VERIFIED_TOKEN} from "./helpers/verified_token";

// Cf. documents.test.ts / expenses.test.ts pour la justification du mock hoisted.
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
const LANDLORD_B = "landlord-b";

/** Sème un document actif appartenant à [landlordId]. */
function seedDocument(
  id: string,
  {
    landlordId = LANDLORD_A,
    category = "autre",
    legalHold = false,
    deletedAt = null as string | null,
  } = {},
) {
  fakeDb.seed(`documents/${id}`, {
    id,
    landlordId,
    category,
    legalHold,
    storagePath: `documents/${landlordId}/${id}.pdf`,
    filename: `${id}.pdf`,
    mimeType: "application/pdf",
    sizeBytes: 1024,
    deletedAt,
  });
}

beforeEach(() => {
  fakeDb = new FakeFirestore();
  fakeAdminFirestoreHolder.db = fakeDb;
});

describe("updateDocumentCategory", () => {
  it("reclasse un document libre — legalHold reste false", async () => {
    seedDocument("doc-1", {category: "autre", legalHold: false});

    const result = await updateDocumentCategory.run(
      makeRequest(LANDLORD_A, {
        documentId: "doc-1",
        category: "attestation_assurance",
      }),
    );

    expect(result).toMatchObject({
      documentId: "doc-1",
      category: "attestation_assurance",
      legalHold: false,
    });
    const stored = fakeDb.peek("documents/doc-1");
    expect(stored?.category).toBe("attestation_assurance");
    expect(stored?.legalHold).toBe(false);
  });

  it("reclasser vers une catégorie sous rétention pose legalHold=true", async () => {
    seedDocument("doc-1", {category: "autre", legalHold: false});

    const result = await updateDocumentCategory.run(
      makeRequest(LANDLORD_A, {documentId: "doc-1", category: "bail_signe"}),
    );

    expect(result.legalHold).toBe(true);
    const stored = fakeDb.peek("documents/doc-1");
    expect(stored?.category).toBe("bail_signe");
    expect(stored?.legalHold).toBe(true);
  });

  it("refuse de reclasser un document DÉJÀ sous legalHold (rétention légale)", async () => {
    seedDocument("doc-1", {category: "bail_signe", legalHold: true});

    await expect(
      updateDocumentCategory.run(
        makeRequest(LANDLORD_A, {documentId: "doc-1", category: "autre"}),
      ),
    ).rejects.toMatchObject({code: "failed-precondition"});

    // Inchangé : la catégorie protégée n'a pas bougé.
    const stored = fakeDb.peek("documents/doc-1");
    expect(stored?.category).toBe("bail_signe");
    expect(stored?.legalHold).toBe(true);
  });

  it("refuse si le document appartient à un autre bailleur", async () => {
    seedDocument("doc-1", {landlordId: LANDLORD_A});

    await expect(
      updateDocumentCategory.run(
        makeRequest(LANDLORD_B, {
          documentId: "doc-1",
          category: "attestation_assurance",
        }),
      ),
    ).rejects.toMatchObject({code: "permission-denied"});
  });

  it("refuse si le document est supprimé", async () => {
    seedDocument("doc-1", {deletedAt: "2026-01-01T00:00:00.000Z"});

    await expect(
      updateDocumentCategory.run(
        makeRequest(LANDLORD_A, {
          documentId: "doc-1",
          category: "attestation_assurance",
        }),
      ),
    ).rejects.toMatchObject({code: "failed-precondition"});
  });

  it("refuse une catégorie inconnue", async () => {
    seedDocument("doc-1");

    await expect(
      updateDocumentCategory.run(
        makeRequest(LANDLORD_A, {documentId: "doc-1", category: "inconnue"}),
      ),
    ).rejects.toMatchObject({code: "invalid-argument"});
  });

  it("refuse un document introuvable", async () => {
    await expect(
      updateDocumentCategory.run(
        makeRequest(LANDLORD_A, {
          documentId: "nope",
          category: "attestation_assurance",
        }),
      ),
    ).rejects.toThrow();
  });

  it("refuse un appel non authentifié", async () => {
    seedDocument("doc-1");

    await expect(
      updateDocumentCategory.run(
        makeRequest(null, {
          documentId: "doc-1",
          category: "attestation_assurance",
        }),
      ),
    ).rejects.toThrow();
  });
});
