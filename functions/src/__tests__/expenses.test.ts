import {Timestamp} from "firebase-admin/firestore";
import type {CallableRequest} from "firebase-functions/v2/https";
import {HttpsError} from "firebase-functions/v2/https";
import {beforeEach, describe, expect, it, vi} from "vitest";

import {
  createExpense,
  deriveExpenseCategory,
  deriveExpensePeriodYear,
  NATURE_DEFAULT_CATEGORY,
  updateExpense,
} from "../callable/expenses";

import {FakeFirestore, fakeAdminFirestoreHolder} from "./helpers/fake_firestore";

// ----------------------------------------------------------------------------
// Mock `firebase-admin` — cf. helpers/fake_firestore.ts pour la justification
// (pas de harness émulateur Firestore dans ce repo, pattern déjà unitaire
// pour finalize_anonymous_upgrade.test.ts).
//
// Le factory de `vi.mock` est hoisted par vitest au-dessus des imports : il
// ne peut donc pas fermer sur une variable locale du fichier de test. On
// délègue à `makeFakeAdminModule()` (import dynamique interne, résolu APRÈS
// le hoisting du mock) qui lit `fakeAdminFirestoreHolder.db` à l'exécution.
// ----------------------------------------------------------------------------
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

// ============================================================================
// Fonctions pures
// ============================================================================
describe("deriveExpenseCategory", () => {
  it("dérive la catégorie par défaut quand aucune category n'est fournie", () => {
    expect(deriveExpenseCategory("condo_charges", null)).toEqual({
      category: "recoverable",
      categoryOverridden: false,
    });
    expect(deriveExpenseCategory("property_tax", null)).toEqual({
      category: "non_recoverable",
      categoryOverridden: false,
    });
  });

  it("accepte une category explicite identique au défaut sans override", () => {
    expect(deriveExpenseCategory("condo_charges", "recoverable")).toEqual({
      category: "recoverable",
      categoryOverridden: false,
    });
  });

  it("accepte une category explicite identique au défaut sur une nature VERROUILLÉE sans lever (property_tax)", () => {
    // Cas discriminant : `requestedCategory === rule.category` doit court-
    // circuiter AVANT toute vérification de `locked` — même sur une nature
    // verrouillée, fournir explicitement le défaut ne doit jamais lever.
    expect(deriveExpenseCategory("property_tax", "non_recoverable")).toEqual({
      category: "non_recoverable",
      categoryOverridden: false,
    });
  });

  it("refuse l'override sur une nature verrouillée (property_tax)", () => {
    expect(() =>
      deriveExpenseCategory("property_tax", "recoverable"),
    ).toThrowError(HttpsError);
    try {
      deriveExpenseCategory("property_tax", "recoverable");
      expect.fail("should have thrown");
    } catch (err) {
      expect(err).toBeInstanceOf(HttpsError);
      expect((err as HttpsError).code).toBe("failed-precondition");
      expect((err as HttpsError).message).toBe("category_locked_for_nature");
    }
  });

  it("refuse l'override sur insurance_pno", () => {
    expect(() =>
      deriveExpenseCategory("insurance_pno", "recoverable"),
    ).toThrowError(HttpsError);
  });

  it("refuse l'override sur management_fees", () => {
    expect(() =>
      deriveExpenseCategory("management_fees", "recoverable"),
    ).toThrowError(HttpsError);
  });

  it("accepte l'override sur une nature ajustable (works) et trace categoryOverridden", () => {
    expect(deriveExpenseCategory("works", "recoverable")).toEqual({
      category: "recoverable",
      categoryOverridden: true,
    });
  });

  it("accepte l'override sur repair_maintenance", () => {
    expect(deriveExpenseCategory("repair_maintenance", "recoverable")).toEqual({
      category: "recoverable",
      categoryOverridden: true,
    });
  });

  it("accepte l'override sur other", () => {
    expect(deriveExpenseCategory("other", "recoverable")).toEqual({
      category: "recoverable",
      categoryOverridden: true,
    });
  });

  it("NATURE_DEFAULT_CATEGORY couvre les 7 natures avec les bons verrous", () => {
    expect(NATURE_DEFAULT_CATEGORY.condo_charges.locked).toBe(false);
    expect(NATURE_DEFAULT_CATEGORY.property_tax.locked).toBe(true);
    expect(NATURE_DEFAULT_CATEGORY.insurance_pno.locked).toBe(true);
    expect(NATURE_DEFAULT_CATEGORY.management_fees.locked).toBe(true);
    expect(NATURE_DEFAULT_CATEGORY.works.locked).toBe(false);
    expect(NATURE_DEFAULT_CATEGORY.repair_maintenance.locked).toBe(false);
    expect(NATURE_DEFAULT_CATEGORY.other.locked).toBe(false);
  });
});

describe("deriveExpensePeriodYear", () => {
  const expenseDate = Timestamp.fromDate(new Date("2026-01-15T00:00:00Z"));
  const periodStart = Timestamp.fromDate(new Date("2025-06-01T00:00:00Z"));

  it("priorise periodYear explicite si fourni", () => {
    expect(
      deriveExpensePeriodYear({periodYear: 2024, periodStart, expenseDate}),
    ).toBe(2024);
  });

  it("retombe sur l'année de periodStart si periodYear absent", () => {
    expect(
      deriveExpensePeriodYear({periodYear: null, periodStart, expenseDate}),
    ).toBe(2025);
  });

  it("retombe sur l'année de expenseDate si ni periodYear ni periodStart", () => {
    expect(
      deriveExpensePeriodYear({periodYear: null, periodStart: null, expenseDate}),
    ).toBe(2026);
  });

  it("cas bord d'année : periodStart 2024-12-31T23:00:00Z est traité en UTC (getUTCFullYear)", () => {
    // 2024-12-31T23:00:00Z reste le 31/12/2024 en UTC (pas de bascule en
    // 2025) : on documente explicitement que la dérivation utilise
    // `getUTCFullYear()` et non l'heure locale du serveur (qui pourrait
    // faire basculer sur 2025 selon le fuseau d'exécution).
    const edgePeriodStart = Timestamp.fromDate(
      new Date("2024-12-31T23:00:00Z"),
    );
    expect(
      deriveExpensePeriodYear({
        periodYear: null,
        periodStart: edgePeriodStart,
        expenseDate,
      }),
    ).toBe(2024);
  });

  it("cas bord d'année : expenseDate 2024-12-31T23:00:00Z (sans periodStart) reste 2024 en UTC", () => {
    const edgeExpenseDate = Timestamp.fromDate(
      new Date("2024-12-31T23:00:00Z"),
    );
    expect(
      deriveExpensePeriodYear({
        periodYear: null,
        periodStart: null,
        expenseDate: edgeExpenseDate,
      }),
    ).toBe(2024);
  });
});

// ============================================================================
// createExpense
// ============================================================================
describe("createExpense", () => {
  function seedProperty(id: string, landlordId: string, extra: Record<string, unknown> = {}) {
    fakeDb.seed(`properties/${id}`, {
      id,
      landlordId,
      name: "Appartement Centre",
      deletedAt: null,
      ...extra,
    });
  }

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
      tenantLastName: "Martin",
      deletedAt: null,
      ...extra,
    });
  }

  function seedDocument(id: string, landlordId: string, extra: Record<string, unknown> = {}) {
    fakeDb.seed(`documents/${id}`, {
      id,
      landlordId,
      deletedAt: null,
      ...extra,
    });
  }

  const baseInput = {
    propertyId: "prop-1",
    amountCents: 45000,
    expenseDate: "2026-03-15T00:00:00Z",
    nature: "works",
  };

  it("refuse si non authentifié", async () => {
    await expect(
      createExpense.run(makeRequest(null, baseInput)),
    ).rejects.toThrowError(HttpsError);
  });

  it("crée une dépense quand le bien appartient au landlord (ownership OK)", async () => {
    seedProperty("prop-1", LANDLORD_A);

    const result = await createExpense.run(
      makeRequest(LANDLORD_A, baseInput),
    );

    expect(result.expenseId).toBeTruthy();
    expect(result.category).toBe("non_recoverable"); // works, pas d'override
    expect(result.categoryOverridden).toBe(false);

    const stored = fakeDb.peek(`expenses/${result.expenseId}`);
    expect(stored).toBeDefined();
    expect(stored?.landlordId).toBe(LANDLORD_A);
    expect(stored?.propertyId).toBe("prop-1");
    expect(stored?.deletedAt).toBeNull();
  });

  it("refuse la création si le bien appartient à un autre landlord (ownership KO)", async () => {
    seedProperty("prop-1", LANDLORD_B);

    await expect(
      createExpense.run(makeRequest(LANDLORD_A, baseInput)),
    ).rejects.toMatchObject({code: "permission-denied"});
  });

  it("refuse la création si le bien n'existe pas", async () => {
    await expect(
      createExpense.run(makeRequest(LANDLORD_A, baseInput)),
    ).rejects.toMatchObject({code: "not-found"});
  });

  it("accepte un leaseId cohérent avec propertyId", async () => {
    seedProperty("prop-1", LANDLORD_A);
    seedLease("lease-1", LANDLORD_A, "prop-1");

    const result = await createExpense.run(
      makeRequest(LANDLORD_A, {...baseInput, leaseId: "lease-1"}),
    );

    const stored = fakeDb.peek(`expenses/${result.expenseId}`);
    expect(stored?.leaseId).toBe("lease-1");
    expect(stored?.tenantLastName).toBe("Martin");
  });

  it("refuse un leaseId qui n'appartient pas au landlord", async () => {
    seedProperty("prop-1", LANDLORD_A);
    seedLease("lease-1", LANDLORD_B, "prop-1");

    await expect(
      createExpense.run(
        makeRequest(LANDLORD_A, {...baseInput, leaseId: "lease-1"}),
      ),
    ).rejects.toMatchObject({code: "permission-denied"});
  });

  it("refuse un leaseId dont le propertyId ne correspond pas (incohérence)", async () => {
    seedProperty("prop-1", LANDLORD_A);
    seedProperty("prop-2", LANDLORD_A);
    seedLease("lease-1", LANDLORD_A, "prop-2"); // bail lié à un AUTRE bien

    await expect(
      createExpense.run(
        makeRequest(LANDLORD_A, {...baseInput, leaseId: "lease-1"}),
      ),
    ).rejects.toMatchObject({
      code: "failed-precondition",
      message: "lease_property_mismatch",
    });
  });

  it("dérive category='recoverable' par défaut pour condo_charges", async () => {
    seedProperty("prop-1", LANDLORD_A);

    const result = await createExpense.run(
      makeRequest(LANDLORD_A, {
        ...baseInput,
        nature: "condo_charges",
        periodStart: "2025-01-01T00:00:00Z",
        periodEnd: "2025-12-31T00:00:00Z",
      }),
    );

    expect(result.category).toBe("recoverable");
    expect(result.categoryOverridden).toBe(false);
  });

  it("refuse l'override client vers 'recoverable' sur une nature verrouillée", async () => {
    seedProperty("prop-1", LANDLORD_A);

    await expect(
      createExpense.run(
        makeRequest(LANDLORD_A, {
          ...baseInput,
          nature: "property_tax",
          category: "recoverable",
        }),
      ),
    ).rejects.toMatchObject({
      code: "failed-precondition",
      message: "category_locked_for_nature",
    });
  });

  it("accepte l'override client sur une nature ajustable et trace categoryOverridden", async () => {
    seedProperty("prop-1", LANDLORD_A);

    const result = await createExpense.run(
      makeRequest(LANDLORD_A, {
        ...baseInput,
        nature: "works",
        category: "recoverable",
        periodStart: "2025-01-01T00:00:00Z",
        periodEnd: "2025-12-31T00:00:00Z",
      }),
    );

    expect(result.category).toBe("recoverable");
    expect(result.categoryOverridden).toBe(true);
  });

  it("exige periodStart/periodEnd si la catégorie est recoverable", async () => {
    seedProperty("prop-1", LANDLORD_A);

    await expect(
      createExpense.run(
        makeRequest(LANDLORD_A, {...baseInput, nature: "condo_charges"}),
      ),
    ).rejects.toMatchObject({code: "invalid-argument"});
  });

  it("n'exige pas periodStart/periodEnd si la catégorie est non_recoverable", async () => {
    seedProperty("prop-1", LANDLORD_A);

    const result = await createExpense.run(
      makeRequest(LANDLORD_A, {...baseInput, nature: "property_tax"}),
    );
    expect(result.category).toBe("non_recoverable");
  });

  it("dérive periodYear depuis periodStart si non fourni", async () => {
    seedProperty("prop-1", LANDLORD_A);

    const result = await createExpense.run(
      makeRequest(LANDLORD_A, {
        ...baseInput,
        nature: "condo_charges",
        periodStart: "2025-06-01T00:00:00Z",
        periodEnd: "2025-12-31T00:00:00Z",
      }),
    );
    const stored = fakeDb.peek(`expenses/${result.expenseId}`);
    expect(stored?.periodYear).toBe(2025);
  });

  it("dérive periodYear depuis expenseDate si periodStart absent (non-récupérable)", async () => {
    seedProperty("prop-1", LANDLORD_A);

    const result = await createExpense.run(
      makeRequest(LANDLORD_A, {...baseInput, nature: "property_tax"}),
    );
    const stored = fakeDb.peek(`expenses/${result.expenseId}`);
    expect(stored?.periodYear).toBe(2026); // baseInput.expenseDate = 2026-03-15
  });

  it("snapshot propertyName et tenantLastName à la création", async () => {
    seedProperty("prop-1", LANDLORD_A, {name: "Studio Bastille"});
    seedLease("lease-1", LANDLORD_A, "prop-1", {tenantLastName: "Durand"});

    const result = await createExpense.run(
      makeRequest(LANDLORD_A, {...baseInput, leaseId: "lease-1"}),
    );
    const stored = fakeDb.peek(`expenses/${result.expenseId}`);
    expect(stored?.propertyName).toBe("Studio Bastille");
    expect(stored?.tenantLastName).toBe("Durand");
  });

  it("pose deletedAt=null et createdAt/updatedAt serveur à la création", async () => {
    seedProperty("prop-1", LANDLORD_A);

    const result = await createExpense.run(
      makeRequest(LANDLORD_A, baseInput),
    );
    const stored = fakeDb.peek(`expenses/${result.expenseId}`);
    expect(stored?.deletedAt).toBeNull();
    expect(stored?.createdAt).toBeInstanceOf(Date);
    expect(stored?.updatedAt).toBeInstanceOf(Date);
  });

  it("valide l'ownership du documentId fourni (OK)", async () => {
    seedProperty("prop-1", LANDLORD_A);
    seedDocument("doc-1", LANDLORD_A);

    const result = await createExpense.run(
      makeRequest(LANDLORD_A, {...baseInput, documentId: "doc-1"}),
    );
    const stored = fakeDb.peek(`expenses/${result.expenseId}`);
    expect(stored?.documentId).toBe("doc-1");
  });

  it("refuse un documentId qui n'appartient pas au landlord", async () => {
    seedProperty("prop-1", LANDLORD_A);
    seedDocument("doc-1", LANDLORD_B);

    await expect(
      createExpense.run(
        makeRequest(LANDLORD_A, {...baseInput, documentId: "doc-1"}),
      ),
    ).rejects.toMatchObject({code: "permission-denied"});
  });

  it("refuse un documentId inexistant", async () => {
    seedProperty("prop-1", LANDLORD_A);

    await expect(
      createExpense.run(
        makeRequest(LANDLORD_A, {...baseInput, documentId: "doc-ghost"}),
      ),
    ).rejects.toMatchObject({code: "not-found"});
  });
});

// ============================================================================
// updateExpense
// ============================================================================
describe("updateExpense", () => {
  function seedExpense(id: string, extra: Record<string, unknown> = {}) {
    fakeDb.seed(`expenses/${id}`, {
      id,
      landlordId: LANDLORD_A,
      propertyId: "prop-1",
      propertyName: "Appartement Centre",
      leaseId: null,
      tenantLastName: null,
      amountCents: 10000,
      expenseDate: Timestamp.fromDate(new Date("2026-01-01T00:00:00Z")),
      nature: "works",
      category: "non_recoverable",
      categoryOverridden: false,
      periodYear: 2026,
      periodStart: null,
      periodEnd: null,
      documentId: null,
      notes: null,
      createdAt: Timestamp.fromDate(new Date("2026-01-01T00:00:00Z")),
      updatedAt: Timestamp.fromDate(new Date("2026-01-01T00:00:00Z")),
      deletedAt: null,
      ...extra,
    });
    fakeDb.seed("properties/prop-1", {
      id: "prop-1",
      landlordId: LANDLORD_A,
      name: "Appartement Centre",
      deletedAt: null,
    });
  }

  it("refuse un champ immuable (propertyId)", async () => {
    seedExpense("exp-1");

    await expect(
      updateExpense.run(
        makeRequest(LANDLORD_A, {id: "exp-1", patch: {propertyId: "prop-2"}}),
      ),
    ).rejects.toMatchObject({code: "invalid-argument"});
  });

  it("refuse un champ immuable (leaseId)", async () => {
    seedExpense("exp-1");

    await expect(
      updateExpense.run(
        makeRequest(LANDLORD_A, {id: "exp-1", patch: {leaseId: "lease-x"}}),
      ),
    ).rejects.toMatchObject({code: "invalid-argument"});
  });

  it("refuse un champ immuable (landlordId)", async () => {
    seedExpense("exp-1");

    await expect(
      updateExpense.run(
        makeRequest(LANDLORD_A, {id: "exp-1", patch: {landlordId: LANDLORD_B}}),
      ),
    ).rejects.toMatchObject({code: "invalid-argument"});
  });

  it("refuse un champ immuable (createdAt)", async () => {
    seedExpense("exp-1");

    await expect(
      updateExpense.run(
        makeRequest(LANDLORD_A, {
          id: "exp-1",
          patch: {createdAt: "2020-01-01T00:00:00Z"},
        }),
      ),
    ).rejects.toMatchObject({code: "invalid-argument"});
  });

  it("refuse un champ immuable (deletedAt)", async () => {
    seedExpense("exp-1");

    await expect(
      updateExpense.run(
        makeRequest(LANDLORD_A, {
          id: "exp-1",
          patch: {deletedAt: "2026-01-01T00:00:00Z"},
        }),
      ),
    ).rejects.toMatchObject({code: "invalid-argument"});
  });

  it("refuse si l'appelant n'est pas le propriétaire", async () => {
    seedExpense("exp-1");

    await expect(
      updateExpense.run(
        makeRequest(LANDLORD_B, {id: "exp-1", patch: {notes: "hack"}}),
      ),
    ).rejects.toMatchObject({code: "permission-denied"});
  });

  it("met à jour un champ mutable simple (amountCents)", async () => {
    seedExpense("exp-1");

    const result = await updateExpense.run(
      makeRequest(LANDLORD_A, {id: "exp-1", patch: {amountCents: 99900}}),
    );
    expect(result.updated).toBe(true);
    expect(fakeDb.peek("expenses/exp-1")?.amountCents).toBe(99900);
  });

  it("re-dérive category quand nature change et re-applique le verrouillage", async () => {
    seedExpense("exp-1", {nature: "works", category: "non_recoverable"});

    // works -> property_tax : nature verrouillée, pas d'override demandé,
    // doit adopter le défaut non_recoverable sans erreur.
    await updateExpense.run(
      makeRequest(LANDLORD_A, {id: "exp-1", patch: {nature: "property_tax"}}),
    );
    const stored = fakeDb.peek("expenses/exp-1");
    expect(stored?.nature).toBe("property_tax");
    expect(stored?.category).toBe("non_recoverable");
    expect(stored?.categoryOverridden).toBe(false);
  });

  it("re-dérive category DISCRIMINANT : condo_charges/recoverable -> property_tax flippe vers non_recoverable", async () => {
    // Cas discriminant (contrairement à works->property_tax, tous deux
    // non_recoverable) : on part d'une dépense RECOVERABLE (condo_charges,
    // avec période) et on bascule vers une nature verrouillée
    // non_recoverable (property_tax). Si la re-dérivation ne fonctionnait
    // pas, `category` resterait figée à 'recoverable' — ce test le
    // détecterait alors que le test existant works->property_tax ne le
    // peut pas.
    seedExpense("exp-1", {
      nature: "condo_charges",
      category: "recoverable",
      categoryOverridden: false,
      periodStart: Timestamp.fromDate(new Date("2025-01-01T00:00:00Z")),
      periodEnd: Timestamp.fromDate(new Date("2025-12-31T00:00:00Z")),
    });

    await updateExpense.run(
      makeRequest(LANDLORD_A, {id: "exp-1", patch: {nature: "property_tax"}}),
    );
    const stored = fakeDb.peek("expenses/exp-1");
    expect(stored?.nature).toBe("property_tax");
    expect(stored?.category).toBe("non_recoverable");
    expect(stored?.categoryOverridden).toBe(false);
  });

  it("re-dérive category DISCRIMINANT (sens inverse) : works/non_recoverable -> condo_charges flippe vers recoverable (période fournie)", async () => {
    // Sens inverse du cas précédent : nature ajustable non_recoverable ->
    // nature dont le défaut est recoverable. Prouve que la re-dérivation
    // fonctionne dans les deux sens, pas seulement non_recoverable ->
    // non_recoverable.
    seedExpense("exp-1", {
      nature: "works",
      category: "non_recoverable",
      categoryOverridden: false,
    });

    await updateExpense.run(
      makeRequest(LANDLORD_A, {
        id: "exp-1",
        patch: {
          nature: "condo_charges",
          periodStart: "2025-01-01T00:00:00Z",
          periodEnd: "2025-12-31T00:00:00Z",
        },
      }),
    );
    const stored = fakeDb.peek("expenses/exp-1");
    expect(stored?.nature).toBe("condo_charges");
    expect(stored?.category).toBe("recoverable");
    expect(stored?.categoryOverridden).toBe(false);
  });

  it("refuse un override de category incompatible avec la nouvelle nature verrouillée", async () => {
    seedExpense("exp-1", {nature: "works", category: "non_recoverable"});

    await expect(
      updateExpense.run(
        makeRequest(LANDLORD_A, {
          id: "exp-1",
          patch: {nature: "insurance_pno", category: "recoverable"},
        }),
      ),
    ).rejects.toMatchObject({
      code: "failed-precondition",
      message: "category_locked_for_nature",
    });
  });

  it("exige periodStart/periodEnd si la nature change vers recoverable", async () => {
    seedExpense("exp-1", {nature: "works", category: "non_recoverable"});

    await expect(
      updateExpense.run(
        makeRequest(LANDLORD_A, {id: "exp-1", patch: {nature: "condo_charges"}}),
      ),
    ).rejects.toMatchObject({code: "invalid-argument"});
  });

  it("valide l'ownership d'un nouveau documentId", async () => {
    seedExpense("exp-1");
    fakeDb.seed("documents/doc-2", {
      id: "doc-2",
      landlordId: LANDLORD_B,
      deletedAt: null,
    });

    await expect(
      updateExpense.run(
        makeRequest(LANDLORD_A, {id: "exp-1", patch: {documentId: "doc-2"}}),
      ),
    ).rejects.toMatchObject({code: "permission-denied"});
  });

  it("accepte un documentId valide et le persiste", async () => {
    seedExpense("exp-1");
    fakeDb.seed("documents/doc-3", {
      id: "doc-3",
      landlordId: LANDLORD_A,
      deletedAt: null,
    });

    await updateExpense.run(
      makeRequest(LANDLORD_A, {id: "exp-1", patch: {documentId: "doc-3"}}),
    );
    expect(fakeDb.peek("expenses/exp-1")?.documentId).toBe("doc-3");
  });

  it("patch periodStart sans periodYear -> periodYear recalculé depuis periodStart", async () => {
    seedExpense("exp-1", {
      nature: "condo_charges",
      category: "recoverable",
      periodStart: Timestamp.fromDate(new Date("2025-01-01T00:00:00Z")),
      periodEnd: Timestamp.fromDate(new Date("2025-12-31T00:00:00Z")),
      periodYear: 2025,
    });

    // periodEnd existant (2025-12-31) reste > le nouveau periodStart
    // (2025-03-01) : seule periodYear doit se recalculer, sans toucher à
    // periodEnd.
    await updateExpense.run(
      makeRequest(LANDLORD_A, {
        id: "exp-1",
        patch: {periodStart: "2025-03-01T00:00:00Z"},
      }),
    );
    const stored = fakeDb.peek("expenses/exp-1");
    expect(stored?.periodStart).toEqual(
      Timestamp.fromDate(new Date("2025-03-01T00:00:00Z")),
    );
    expect(stored?.periodYear).toBe(2025);
  });

  it("patch periodStart qui change d'année sans periodYear -> periodYear recalculé (nouvelle année)", async () => {
    seedExpense("exp-1", {
      nature: "condo_charges",
      category: "recoverable",
      periodStart: Timestamp.fromDate(new Date("2025-01-01T00:00:00Z")),
      periodEnd: Timestamp.fromDate(new Date("2027-12-31T00:00:00Z")),
      periodYear: 2025,
    });

    await updateExpense.run(
      makeRequest(LANDLORD_A, {
        id: "exp-1",
        patch: {periodStart: "2027-03-01T00:00:00Z"},
      }),
    );
    const stored = fakeDb.peek("expenses/exp-1");
    expect(stored?.periodStart).toEqual(
      Timestamp.fromDate(new Date("2027-03-01T00:00:00Z")),
    );
    expect(stored?.periodYear).toBe(2027);
  });

  it("patch periodYear explicite (2030) -> persisté tel quel (priorité sur periodStart)", async () => {
    seedExpense("exp-1", {
      nature: "condo_charges",
      category: "recoverable",
      periodStart: Timestamp.fromDate(new Date("2025-01-01T00:00:00Z")),
      periodEnd: Timestamp.fromDate(new Date("2025-12-31T00:00:00Z")),
      periodYear: 2025,
    });

    await updateExpense.run(
      makeRequest(LANDLORD_A, {id: "exp-1", patch: {periodYear: 2030}}),
    );
    const stored = fakeDb.peek("expenses/exp-1");
    expect(stored?.periodYear).toBe(2030);
  });

  it("refuse un patch qui rend la dépense recoverable avec periodEnd <= periodStart", async () => {
    seedExpense("exp-1", {
      nature: "condo_charges",
      category: "recoverable",
      periodStart: Timestamp.fromDate(new Date("2025-01-01T00:00:00Z")),
      periodEnd: Timestamp.fromDate(new Date("2025-12-31T00:00:00Z")),
      periodYear: 2025,
    });

    await expect(
      updateExpense.run(
        makeRequest(LANDLORD_A, {
          id: "exp-1",
          patch: {
            periodStart: "2025-06-01T00:00:00Z",
            periodEnd: "2025-01-01T00:00:00Z",
          },
        }),
      ),
    ).rejects.toMatchObject({code: "invalid-argument"});
  });

  it("accepte un patch periodStart/periodEnd valides sur une dépense recoverable et les persiste", async () => {
    seedExpense("exp-1", {
      nature: "condo_charges",
      category: "recoverable",
      periodStart: Timestamp.fromDate(new Date("2025-01-01T00:00:00Z")),
      periodEnd: Timestamp.fromDate(new Date("2025-12-31T00:00:00Z")),
      periodYear: 2025,
    });

    await updateExpense.run(
      makeRequest(LANDLORD_A, {
        id: "exp-1",
        patch: {
          periodStart: "2026-01-01T00:00:00Z",
          periodEnd: "2026-06-30T00:00:00Z",
        },
      }),
    );
    const stored = fakeDb.peek("expenses/exp-1");
    expect(stored?.periodStart).toEqual(
      Timestamp.fromDate(new Date("2026-01-01T00:00:00Z")),
    );
    expect(stored?.periodEnd).toEqual(
      Timestamp.fromDate(new Date("2026-06-30T00:00:00Z")),
    );
  });

  it("re-snapshot propertyName si le nom du bien a changé", async () => {
    seedExpense("exp-1", {propertyName: "Ancien nom"});
    fakeDb.seed("properties/prop-1", {
      id: "prop-1",
      landlordId: LANDLORD_A,
      name: "Nouveau nom",
      deletedAt: null,
    });

    await updateExpense.run(
      makeRequest(LANDLORD_A, {id: "exp-1", patch: {notes: "maj"}}),
    );
    expect(fakeDb.peek("expenses/exp-1")?.propertyName).toBe("Nouveau nom");
  });
});
