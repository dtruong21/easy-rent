import type {CallableRequest} from "firebase-functions/v2/https";
import {HttpsError} from "firebase-functions/v2/https";
import {beforeEach, describe, expect, it, vi} from "vitest";

import {createDocument} from "../callable/documents";

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

const baseInput = {
  filename: "decompte-syndic.pdf",
  storagePath: STORAGE_PATH,
  mimeType: "application/pdf",
  sizeBytes: 1024,
};

beforeEach(() => {
  fakeDb = new FakeFirestore();
  fakeStorage = new FakeStorage();
  fakeAdminFirestoreHolder.db = fakeDb;
  fakeAdminFirestoreHolder.storage = fakeStorage;
});

function seedLease(
  id: string,
  landlordId: string,
  propertyId: string,
  extra: Record<string, unknown> = {},
) {
  fakeDb.seed(`leases/${id}`, {
    id,
    landlordId,
    propertyId,
    deletedAt: null,
    ...extra,
  });
}

function seedProperty(id: string, landlordId: string, extra: Record<string, unknown> = {}) {
  fakeDb.seed(`properties/${id}`, {
    id,
    landlordId,
    name: "Appartement Centre",
    deletedAt: null,
    ...extra,
  });
}

describe("createDocument — v2 leaseId/propertyId (FEAT-041b)", () => {
  it("refuse si non authentifié", async () => {
    await expect(
      createDocument.run(
        makeRequest(null, {...baseInput, leaseId: "lease-1", category: "bail_signe"}),
      ),
    ).rejects.toThrowError(HttpsError);
  });

  // --------------------------------------------------------------------
  // Rétrocompat stricte : leaseId seul = comportement d'aujourd'hui.
  // --------------------------------------------------------------------
  describe("chemin leaseId seul (rétrocompat)", () => {
    it("crée le document quand le bail appartient au landlord", async () => {
      seedLease("lease-1", LANDLORD_A, "prop-1");

      const result = await createDocument.run(
        makeRequest(LANDLORD_A, {
          ...baseInput,
          leaseId: "lease-1",
          category: "bail_signe",
        }),
      );

      expect(result.documentId).toBeTruthy();
      expect(result.legalHold).toBe(true); // bail_signe = legal hold inchangé

      const stored = fakeDb.peek(`documents/${result.documentId}`);
      expect(stored?.leaseId).toBe("lease-1");
      expect(stored?.propertyId).toBeNull();
      expect(stored?.landlordId).toBe(LANDLORD_A);
    });

    it("refuse si le bail n'appartient pas au landlord", async () => {
      seedLease("lease-1", LANDLORD_B, "prop-1");

      await expect(
        createDocument.run(
          makeRequest(LANDLORD_A, {
            ...baseInput,
            leaseId: "lease-1",
            category: "bail_signe",
          }),
        ),
      ).rejects.toMatchObject({code: "permission-denied"});
    });

    it("refuse si le bail est soft-deleted", async () => {
      seedLease("lease-1", LANDLORD_A, "prop-1", {deletedAt: new Date()});

      await expect(
        createDocument.run(
          makeRequest(LANDLORD_A, {
            ...baseInput,
            leaseId: "lease-1",
            category: "bail_signe",
          }),
        ),
      ).rejects.toMatchObject({code: "failed-precondition"});
    });

    it("refuse si le bail n'existe pas", async () => {
      await expect(
        createDocument.run(
          makeRequest(LANDLORD_A, {
            ...baseInput,
            leaseId: "lease-ghost",
            category: "bail_signe",
          }),
        ),
      ).rejects.toMatchObject({code: "not-found"});
    });
  });

  // --------------------------------------------------------------------
  // Chemin propertyId seul — nouveau v2.
  // --------------------------------------------------------------------
  describe("chemin propertyId seul", () => {
    it("crée le document quand le bien appartient au landlord", async () => {
      seedProperty("prop-1", LANDLORD_A);

      const result = await createDocument.run(
        makeRequest(LANDLORD_A, {
          ...baseInput,
          propertyId: "prop-1",
          category: "expense_receipt",
        }),
      );

      expect(result.documentId).toBeTruthy();
      const stored = fakeDb.peek(`documents/${result.documentId}`);
      expect(stored?.propertyId).toBe("prop-1");
      expect(stored?.leaseId).toBeNull();
    });

    it("refuse si le bien n'appartient pas au landlord", async () => {
      seedProperty("prop-1", LANDLORD_B);

      await expect(
        createDocument.run(
          makeRequest(LANDLORD_A, {
            ...baseInput,
            propertyId: "prop-1",
            category: "expense_receipt",
          }),
        ),
      ).rejects.toMatchObject({code: "permission-denied"});
    });

    it("refuse si le bien est soft-deleted", async () => {
      seedProperty("prop-1", LANDLORD_A, {deletedAt: new Date()});

      await expect(
        createDocument.run(
          makeRequest(LANDLORD_A, {
            ...baseInput,
            propertyId: "prop-1",
            category: "expense_receipt",
          }),
        ),
      ).rejects.toMatchObject({code: "failed-precondition"});
    });

    it("refuse si le bien n'existe pas", async () => {
      await expect(
        createDocument.run(
          makeRequest(LANDLORD_A, {
            ...baseInput,
            propertyId: "prop-ghost",
            category: "expense_receipt",
          }),
        ),
      ).rejects.toMatchObject({code: "not-found"});
    });
  });

  // --------------------------------------------------------------------
  // Les deux fournis — cohérence lease.propertyId == propertyId.
  // --------------------------------------------------------------------
  describe("chemin leaseId + propertyId (les deux)", () => {
    it("accepte quand lease.propertyId == propertyId (cohérence OK)", async () => {
      seedProperty("prop-1", LANDLORD_A);
      seedLease("lease-1", LANDLORD_A, "prop-1");

      const result = await createDocument.run(
        makeRequest(LANDLORD_A, {
          ...baseInput,
          leaseId: "lease-1",
          propertyId: "prop-1",
          category: "expense_receipt",
        }),
      );

      const stored = fakeDb.peek(`documents/${result.documentId}`);
      expect(stored?.leaseId).toBe("lease-1");
      expect(stored?.propertyId).toBe("prop-1");
    });

    it("refuse quand lease.propertyId != propertyId (incohérence)", async () => {
      seedProperty("prop-1", LANDLORD_A);
      seedProperty("prop-2", LANDLORD_A);
      seedLease("lease-1", LANDLORD_A, "prop-2"); // bail lié à un AUTRE bien

      await expect(
        createDocument.run(
          makeRequest(LANDLORD_A, {
            ...baseInput,
            leaseId: "lease-1",
            propertyId: "prop-1",
            category: "expense_receipt",
          }),
        ),
      ).rejects.toMatchObject({
        code: "failed-precondition",
        message: "lease_property_mismatch",
      });
    });
  });

  // --------------------------------------------------------------------
  // Aucun des deux fournis → erreur.
  // --------------------------------------------------------------------
  it("refuse si ni leaseId ni propertyId ne sont fournis", async () => {
    await expect(
      createDocument.run(
        makeRequest(LANDLORD_A, {...baseInput, category: "expense_receipt"}),
      ),
    ).rejects.toMatchObject({code: "invalid-argument"});
  });

  // --------------------------------------------------------------------
  // expense_receipt → legalHold = true dès V1.
  // --------------------------------------------------------------------
  it("legalHold=true pour la catégorie expense_receipt", async () => {
    seedProperty("prop-1", LANDLORD_A);

    const result = await createDocument.run(
      makeRequest(LANDLORD_A, {
        ...baseInput,
        propertyId: "prop-1",
        category: "expense_receipt",
      }),
    );

    expect(result.legalHold).toBe(true);
    const stored = fakeDb.peek(`documents/${result.documentId}`);
    expect(stored?.legalHold).toBe(true);
  });

  it("refuse une catégorie inconnue", async () => {
    seedProperty("prop-1", LANDLORD_A);

    await expect(
      createDocument.run(
        makeRequest(LANDLORD_A, {
          ...baseInput,
          propertyId: "prop-1",
          category: "inconnue",
        }),
      ),
    ).rejects.toMatchObject({code: "invalid-argument"});
  });

  it("refuse si le fichier n'a pas été uploadé (storagePath absent du bucket)", async () => {
    seedProperty("prop-1", LANDLORD_A);
    fakeStorage.existingPaths = new Set(); // aucun fichier "existant"

    await expect(
      createDocument.run(
        makeRequest(LANDLORD_A, {
          ...baseInput,
          propertyId: "prop-1",
          category: "expense_receipt",
        }),
      ),
    ).rejects.toMatchObject({code: "failed-precondition"});
  });
});
