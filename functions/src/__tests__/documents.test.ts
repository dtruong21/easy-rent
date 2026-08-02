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

/**
 * Landlord propriétaire des documents. Semé en **`paid`** par défaut (dérivé en
 * `pro` : 50 documents, 10 Mio par fichier) → le gating de quota (FEAT-044)
 * n'interfère PAS avec les tests de validation ci-dessous, qui ne sèment aucun
 * document et restent sous la taille max. Même convention que
 * `lease_payment.test.ts`. Les tests de quota re-sèment le tier voulu.
 */
function seedLandlord(
  tier = "paid",
  landlordId = LANDLORD_A,
) {
  fakeDb.seed(`landlords/${landlordId}`, {
    id: landlordId,
    landlordId,
    subscriptionTier: tier,
    deletedAt: null,
  });
}

/** N documents ACTIFS appartenant à [landlordId] (pour saturer le quota). */
function seedDocuments(count: number, landlordId = LANDLORD_A) {
  for (let i = 0; i < count; i++) {
    fakeDb.seed(`documents/doc-seed-${i}`, {
      id: `doc-seed-${i}`,
      landlordId,
      deletedAt: null,
    });
  }
}

beforeEach(() => {
  fakeDb = new FakeFirestore();
  fakeStorage = new FakeStorage();
  fakeAdminFirestoreHolder.db = fakeDb;
  fakeAdminFirestoreHolder.storage = fakeStorage;
  seedLandlord();
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

// ==========================================================================
// Gating free/Pro du quota documentaire (matrice free/Pro 2026-07-20)
// ==========================================================================
describe("createDocument — gating quota documents (FEAT-044)", () => {
  /** Appel valide minimal (bail possédé par LANDLORD_A). */
  function callCreate() {
    seedLease("lease-1", LANDLORD_A, "prop-1");
    return createDocument.run(
      makeRequest(LANDLORD_A, {
        ...baseInput,
        leaseId: "lease-1",
        category: "bail_signe",
      }),
    );
  }

  it("free SOUS le plafond (9/10) → crée le document", async () => {
    seedLandlord("free");
    seedDocuments(9);
    const result = await callCreate();
    expect(result.documentId).toBeTruthy();
  });

  it("free AU plafond (10/10) → refus resource-exhausted, rien créé", async () => {
    seedLandlord("free");
    seedDocuments(10);
    await expect(callCreate()).rejects.toMatchObject({
      code: "resource-exhausted",
      message: "document_limit_reached",
    });
  });

  it("paid (→ pro) : crée au-delà de 10, mais reste borné à 50", async () => {
    // PR-7 : les paliers payants ne sont plus illimités. Un doc `paid` sans
    // `planLevel` se dérive en `pro` → plafond 50 documents.
    seedLandlord("paid");
    seedDocuments(49);
    const result = await callCreate();
    expect(result.documentId).toBeTruthy();
  });

  it("paid (→ pro) AU plafond (50/50) → refus resource-exhausted", async () => {
    seedLandlord("paid");
    seedDocuments(50);
    await expect(callCreate()).rejects.toMatchObject({
      code: "resource-exhausted",
      message: "document_limit_reached",
    });
  });

  it("anonymous → refus même à 0 document (registre réservé aux comptes)", async () => {
    seedLandlord("anonymous");
    await expect(callCreate()).rejects.toMatchObject({
      code: "resource-exhausted",
    });
  });

  it("les documents SOFT-DELETED ne comptent pas dans le quota", async () => {
    seedLandlord("free");
    seedDocuments(9);
    // 3 docs supprimés : ne doivent pas saturer le plafond.
    for (let i = 0; i < 3; i++) {
      fakeDb.seed(`documents/deleted-${i}`, {
        id: `deleted-${i}`,
        landlordId: LANDLORD_A,
        deletedAt: new Date(),
      });
    }
    const result = await callCreate();
    expect(result.documentId).toBeTruthy();
  });

  it("les documents d'un AUTRE landlord ne comptent pas", async () => {
    seedLandlord("free");
    seedDocuments(20, LANDLORD_B); // saturerait si compté à tort
    const result = await callCreate();
    expect(result.documentId).toBeTruthy();
  });

  it("landlord inexistant → not-found (fail-closed)", async () => {
    // 'ghost' n'a aucun doc landlords/ → le gate refuse avant tout le reste.
    // storagePath aligné sur son uid pour passer la validation de préfixe.
    seedLease("lease-1", "ghost", "prop-1");
    await expect(
      createDocument.run(
        makeRequest("ghost", {
          ...baseInput,
          storagePath: "documents/ghost/doc-1.pdf",
          leaseId: "lease-1",
          category: "bail_signe",
        }),
      ),
    ).rejects.toMatchObject({code: "not-found"});
  });
});

// ==========================================================================
// FEAT-056 — quota documentaire résolu sur le PALIER EFFECTIF. Additif : les
// cas free/paid/anonymous ci-dessus restent la référence de non-régression.
// ==========================================================================
describe("createDocument — palier effectif (FEAT-056)", () => {
  /** Landlord payant avec un palier commercial explicite. */
  function seedPlan(tier: string, planLevel: string | null) {
    const data: Record<string, unknown> = {
      id: LANDLORD_A,
      landlordId: LANDLORD_A,
      subscriptionTier: tier,
      deletedAt: null,
    };
    if (planLevel !== null) data.planLevel = planLevel;
    fakeDb.seed(`landlords/${LANDLORD_A}`, data);
  }

  function callCreate() {
    seedLease("lease-1", LANDLORD_A, "prop-1");
    return createDocument.run(
      makeRequest(LANDLORD_A, {
        ...baseInput,
        leaseId: "lease-1",
        category: "bail_signe",
      }),
    );
  }

  it("paid SANS planLevel (abonné d'avant FEAT-056) → servi aux plafonds pro", async () => {
    // I3 : dérivation en `pro`, donc 50 documents — plus illimité depuis PR-7.
    seedPlan("paid", null);
    seedDocuments(49);
    const result = await callCreate();
    expect(result.documentId).toBeTruthy();

    fakeDb = new FakeFirestore();
    fakeAdminFirestoreHolder.db = fakeDb;
    seedPlan("paid", null);
    seedDocuments(50);
    await expect(callCreate()).rejects.toMatchObject({
      code: "resource-exhausted",
      message: "document_limit_reached",
    });
  });

  it("chaque palier payant est servi par SA propre clé de table", async () => {
    // Plafonds différenciés (50 / 150 / illimité) : à 50 documents, pro refuse
    // et max accepte. Un gating indexé sur la classe d'accès `paid` rendrait
    // les trois paliers indiscernables — ce test le détecte.
    const documentLimits: Array<[string, number | null]> = [
      ["pro", 50],
      ["max", 150],
      ["ultra", null],
    ];
    for (const [level, limit] of documentLimits) {
      // Juste SOUS le plafond (ou très haut si illimité) → passe.
      fakeDb = new FakeFirestore();
      fakeAdminFirestoreHolder.db = fakeDb;
      seedPlan("paid", level);
      seedDocuments(limit === null ? 400 : limit - 1);
      const result = await callCreate();
      expect(result.documentId).toBeTruthy();

      if (limit === null) continue; // ultra : aucun plafond à franchir
      // AU plafond → refus.
      fakeDb = new FakeFirestore();
      fakeAdminFirestoreHolder.db = fakeDb;
      seedPlan("paid", level);
      seedDocuments(limit);
      await expect(callCreate()).rejects.toMatchObject({
        code: "resource-exhausted",
        message: "document_limit_reached",
      });
    }
  });

  it("planLevel inconnu sur un compte payant → servi comme pro (I4)", async () => {
    seedPlan("paid", "quantum");
    seedDocuments(49);
    const result = await callCreate();
    expect(result.documentId).toBeTruthy();

    fakeDb = new FakeFirestore();
    fakeAdminFirestoreHolder.db = fakeDb;
    seedPlan("paid", "quantum");
    seedDocuments(50);
    await expect(callCreate()).rejects.toMatchObject({
      code: "resource-exhausted",
      message: "document_limit_reached",
    });
  });

  it("planLevel posé sur un compte FREE ne débloque rien", async () => {
    seedPlan("free", "ultra");
    seedDocuments(10);
    await expect(callCreate()).rejects.toMatchObject({
      code: "resource-exhausted",
      message: "document_limit_reached",
    });
  });
});

// ==========================================================================
// PR-7b — `documentMaxBytes` câblé sur la table. Quota de TAILLE (unit
// `bytes`), à ne jamais confondre avec le compteur `documents` ci-dessus : ces
// tests ne sèment AUCUN document et ne jouent que sur `sizeBytes`.
// ==========================================================================
describe("createDocument — taille max par fichier (PR-7b)", () => {
  const MIB = 1024 * 1024;

  function seedPlan(tier: string, planLevel: string | null) {
    const data: Record<string, unknown> = {
      id: LANDLORD_A,
      landlordId: LANDLORD_A,
      subscriptionTier: tier,
      deletedAt: null,
    };
    if (planLevel !== null) data.planLevel = planLevel;
    fakeDb.seed(`landlords/${LANDLORD_A}`, data);
  }

  /** Nombre de docs Firestore écrits sous `documents/` (aucun seed ici). */
  function writtenDocumentCount(): number {
    return [...fakeDb.store.keys()].filter((k) => k.startsWith("documents/"))
      .length;
  }

  /** Upload d'un fichier de [sizeBytes] octets par LANDLORD_A. */
  function callCreate(sizeBytes: number) {
    seedLease("lease-1", LANDLORD_A, "prop-1");
    return createDocument.run(
      makeRequest(LANDLORD_A, {
        ...baseInput,
        sizeBytes,
        leaseId: "lease-1",
        category: "bail_signe",
      }),
    );
  }

  // Les trois régimes de la grille : 10 Mio (free & pro), 25 Mio (max),
  // 50 Mio (ultra). Chaque palier accepte PILE son plafond et refuse un octet
  // de plus — c'est la borne exacte qui prouve que la table est bien lue.
  const regimes: Array<[string, string | null, number]> = [
    ["free", null, 10 * MIB],
    ["paid", "pro", 10 * MIB],
    ["paid", "max", 25 * MIB],
    ["paid", "ultra", 50 * MIB],
  ];

  for (const [tier, planLevel, limitBytes] of regimes) {
    const label = planLevel ?? tier;
    const mib = limitBytes / MIB;

    it(`${label} : un fichier de PILE ${mib} Mio passe`, async () => {
      seedPlan(tier, planLevel);
      const result = await callCreate(limitBytes);
      expect(result.documentId).toBeTruthy();
    });

    it(`${label} : un octet au-dessus de ${mib} Mio → file_too_large`, async () => {
      seedPlan(tier, planLevel);
      await expect(callCreate(limitBytes + 1)).rejects.toMatchObject({
        code: "resource-exhausted",
        message: "file_too_large",
      });
      // Aucun document Firestore ne doit avoir été écrit.
      expect(writtenDocumentCount()).toBe(0);
    });
  }

  it("le refus porte le plafond APPLICABLE À L'APPELANT, pas un plafond global", async () => {
    // C'est la donnée dont le client a besoin pour écrire « votre palier
    // accepte N Mo » sans redupliquer la grille côté Dart.
    // 20 Mio : trop gros pour Pro (10), accepté par Max (25) → upsell Max.
    seedPlan("paid", "pro");
    await expect(callCreate(20 * MIB)).rejects.toMatchObject({
      message: "file_too_large",
      details: {limitBytes: 10 * MIB, sizeBytes: 20 * MIB, upgradeTo: "max"},
    });

    // 30 Mio : Max (25) ne suffit plus non plus → le plus petit palier
    // suffisant est Ultra, jamais un palier qui ne débloquerait rien.

    fakeDb = new FakeFirestore();
    fakeAdminFirestoreHolder.db = fakeDb;
    seedPlan("paid", "max");
    await expect(callCreate(30 * MIB)).rejects.toMatchObject({
      message: "file_too_large",
      details: {limitBytes: 25 * MIB, sizeBytes: 30 * MIB, upgradeTo: "ultra"},
    });
  });

  it("aucun palier ne suffit → upgradeTo null (ne jamais vendre un palier inutile)", async () => {
    seedPlan("paid", "pro");
    await expect(callCreate(80 * MIB)).rejects.toMatchObject({
      message: "file_too_large",
      details: {limitBytes: 10 * MIB, upgradeTo: null},
    });
  });

  it("un abonné legacy (paid sans planLevel) est borné à 10 Mio, comme pro", async () => {
    seedPlan("paid", null);
    const ok = await callCreate(10 * MIB);
    expect(ok.documentId).toBeTruthy();

    fakeDb = new FakeFirestore();
    fakeAdminFirestoreHolder.db = fakeDb;
    seedPlan("paid", null);
    await expect(callCreate(10 * MIB + 1)).rejects.toMatchObject({
      code: "resource-exhausted",
      message: "file_too_large",
    });
  });

  it("le plafond de NOMBRE est évalué avant celui de TAILLE", async () => {
    // Un free saturé qui envoie un fichier trop gros doit s'entendre dire que
    // son quota de documents est atteint — motif actionnable (supprimer ou
    // passer payant) — plutôt que « fichier trop volumineux ».
    seedPlan("free", null);
    seedDocuments(10);
    await expect(callCreate(50 * MIB)).rejects.toMatchObject({
      code: "resource-exhausted",
      message: "document_limit_reached",
    });
  });

  it("anonymous : refusé sur le NOMBRE, pas sur la taille", async () => {
    // `documentMaxBytes` vaut 0 pour anonymous : sans l'ordre ci-dessus, un
    // compte anonyme s'entendrait répondre « fichier trop volumineux » pour un
    // fichier de 1 Ko, alors que le vrai motif est que le registre est réservé
    // aux comptes.
    seedPlan("anonymous", null);
    await expect(callCreate(1024)).rejects.toMatchObject({
      code: "resource-exhausted",
      message: "document_limit_reached",
    });
  });

  it("sizeBytes non entier ou nul reste un invalid-argument (validation de forme)", async () => {
    seedPlan("paid", "ultra");
    await expect(callCreate(0)).rejects.toMatchObject({
      code: "invalid-argument",
    });
    seedPlan("paid", "ultra");
    await expect(
      createDocument.run(
        makeRequest(LANDLORD_A, {
          ...baseInput,
          sizeBytes: "beaucoup",
          leaseId: "lease-1",
          category: "bail_signe",
        }),
      ),
    ).rejects.toMatchObject({code: "invalid-argument"});
  });
});
