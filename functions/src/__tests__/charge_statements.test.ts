import {Timestamp} from "firebase-admin/firestore";
import type {CallableRequest} from "firebase-functions/v2/https";
import {HttpsError} from "firebase-functions/v2/https";
import {beforeEach, describe, expect, it, vi} from "vitest";

import {
  finalizeChargeRegularization,
  sumProvisionsOverlap,
  validateLineItems,
} from "../callable/charge_statements";

import {FakeFirestore, fakeAdminFirestoreHolder} from "./helpers/fake_firestore";

// ----------------------------------------------------------------------------
// Mock `firebase-admin` — cf. helpers/fake_firestore.ts pour la justification
// (pas de harness émulateur Firestore dans ce repo, pattern déjà unitaire
// pour finalize_anonymous_upgrade.test.ts / expenses.test.ts).
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

beforeEach(() => {
  fakeDb = new FakeFirestore();
  fakeAdminFirestoreHolder.db = fakeDb;
});

// ============================================================================
// sumProvisionsOverlap
// ============================================================================
describe("sumProvisionsOverlap", () => {
  const ts = (iso: string) => Timestamp.fromDate(new Date(iso));
  const pay = (start: string, end: string, chargesCents: number) => ({
    chargesAmountCents: chargesCents,
    periodStart: ts(start),
    periodEnd: ts(end),
  });

  it("somme les chargesAmountCents des paiements recouvrant la période", () => {
    const total = sumProvisionsOverlap(
      [
        pay("2025-01-01", "2025-01-31", 10000), // dans la période
        pay("2025-12-01", "2025-12-31", 10000), // dans la période
        pay("2024-12-01", "2024-12-31", 9999), // hors période
      ],
      ts("2025-01-01"),
      ts("2025-12-31"),
    );
    expect(total).toBe(20000);
  });

  it("inclut un paiement qui chevauche partiellement une borne", () => {
    const total = sumProvisionsOverlap(
      [pay("2024-12-15", "2025-01-15", 5000)],
      ts("2025-01-01"),
      ts("2025-12-31"),
    );
    expect(total).toBe(5000);
  });
});

// ============================================================================
// validateLineItems
// ============================================================================
describe("validateLineItems", () => {
  const li = (amountCents: number) => ({
    expenseId: "e1",
    nature: "condo_charges",
    notes: "",
    amountCents,
    expenseDate: "2025-06-01T00:00:00.000Z",
  });

  it("accepte quand la somme des lignes == total", () => {
    expect(() => validateLineItems([li(600), li(400)], 1000)).not.toThrow();
  });

  it("rejette quand la somme diverge du total", () => {
    expect(() => validateLineItems([li(600), li(400)], 999)).toThrow(HttpsError);
  });

  it("rejette un amountCents négatif", () => {
    expect(() => validateLineItems([li(-1)], -1)).toThrow(HttpsError);
  });
});

// ============================================================================
// finalizeChargeRegularization
// ============================================================================
interface FinalizeResult {
  statementId: string;
  balanceCents: number;
  direction: string;
}

describe("finalizeChargeRegularization", () => {
  const OWNER = "landlord-a";
  const iso = (d: string) => `${d}T00:00:00.000Z`;

  function seedBase() {
    fakeDb.seed("landlords/landlord-a", {fullName: "Jean Bailleur", address: "1 rue A"});
    fakeDb.seed("leases/lease-1", {
      landlordId: OWNER,
      propertyId: "prop-1",
      leaseType: "unfurnished",
      chargeMode: "provisions",
      tenantFirstName: "Marie",
      tenantLastName: "Loc",
      propertyName: "Studio",
      propertyAddress: "2 rue B",
      deletedAt: null,
    });
    fakeDb.seed("payments/p1", {
      landlordId: OWNER,
      leaseId: "lease-1",
      deletedAt: null,
      chargesAmountCents: 12000,
      periodStart: Timestamp.fromDate(new Date(iso("2025-06-01"))),
      periodEnd: Timestamp.fromDate(new Date(iso("2025-06-30"))),
    });
  }

  it("recalcule provisions serveur et crée le doc figé", async () => {
    seedBase();
    const res = (await finalizeChargeRegularization.run(
      makeRequest(OWNER, {
        leaseId: "lease-1",
        periodStart: iso("2025-01-01"),
        periodEnd: iso("2025-12-31"),
        actualExpensesCents: 15000,
        actualExpensesSource: "manual",
        lineItems: [],
      }),
    )) as FinalizeResult;

    expect(res.balanceCents).toBe(3000); // 15000 - 12000
    expect(res.direction).toBe("dueByTenant");

    const stored = (await fakeDb.doc(`charge_statements/${res.statementId}`).get()).data();
    expect(stored?.provisionsCollectedCents).toBe(12000);
    expect(stored?.actualExpensesCents).toBe(15000);
    expect(stored?.leaseId).toBe("lease-1");
    expect(stored?.landlordId).toBe(OWNER);
    expect(stored?.isVoided).toBe(false);
  });

  it("ignore toute valeur de provisions envoyée par le client", async () => {
    seedBase();
    const res = (await finalizeChargeRegularization.run(
      makeRequest(OWNER, {
        leaseId: "lease-1",
        periodStart: iso("2025-01-01"),
        periodEnd: iso("2025-12-31"),
        actualExpensesCents: 15000,
        actualExpensesSource: "manual",
        lineItems: [],
        provisionsCollectedCents: 999999, // doit être ignoré
      }),
    )) as FinalizeResult;

    const stored = (await fakeDb.doc(`charge_statements/${res.statementId}`).get()).data();
    expect(stored?.provisionsCollectedCents).toBe(12000);
  });

  it("refuse un bail non possédé", async () => {
    seedBase();
    fakeDb.seed("landlords/intrus", {fullName: "Un Intrus", address: "9 rue C"});
    await expect(
      finalizeChargeRegularization.run(
        makeRequest("intrus", {
          leaseId: "lease-1",
          periodStart: iso("2025-01-01"),
          periodEnd: iso("2025-12-31"),
          actualExpensesCents: 100,
          actualExpensesSource: "manual",
          lineItems: [],
        }),
      ),
    ).rejects.toMatchObject({code: "permission-denied"});
  });

  it("refuse un bail au forfait (gate légal)", async () => {
    seedBase();
    fakeDb.seed("leases/lease-1", {
      landlordId: OWNER,
      propertyId: "prop-1",
      leaseType: "furnished",
      chargeMode: "forfait",
      tenantFirstName: "Marie",
      tenantLastName: "Loc",
      propertyName: "Studio",
      propertyAddress: "2 rue B",
      deletedAt: null,
    });

    await expect(
      finalizeChargeRegularization.run(
        makeRequest(OWNER, {
          leaseId: "lease-1",
          periodStart: iso("2025-01-01"),
          periodEnd: iso("2025-12-31"),
          actualExpensesCents: 100,
          actualExpensesSource: "manual",
          lineItems: [],
        }),
      ),
    ).rejects.toMatchObject({
      code: "failed-precondition",
      message: "charge_regularization_not_applicable",
    });
  });

  it("refuse un profil bailleur incomplet", async () => {
    seedBase();
    fakeDb.seed("landlords/landlord-a", {fullName: "", address: ""});

    await expect(
      finalizeChargeRegularization.run(
        makeRequest(OWNER, {
          leaseId: "lease-1",
          periodStart: iso("2025-01-01"),
          periodEnd: iso("2025-12-31"),
          actualExpensesCents: 100,
          actualExpensesSource: "manual",
          lineItems: [],
        }),
      ),
    ).rejects.toMatchObject({code: "failed-precondition", message: "profile_incomplete"});
  });

  it("refuse periodEnd <= periodStart", async () => {
    seedBase();
    await expect(
      finalizeChargeRegularization.run(
        makeRequest(OWNER, {
          leaseId: "lease-1",
          periodStart: iso("2025-12-31"),
          periodEnd: iso("2025-01-01"),
          actualExpensesCents: 100,
          actualExpensesSource: "manual",
          lineItems: [],
        }),
      ),
    ).rejects.toMatchObject({code: "invalid-argument"});
  });

  it("valide les lineItems et persiste le détail quand actualExpensesSource=expenses", async () => {
    seedBase();
    const res = (await finalizeChargeRegularization.run(
      makeRequest(OWNER, {
        leaseId: "lease-1",
        periodStart: iso("2025-01-01"),
        periodEnd: iso("2025-12-31"),
        actualExpensesCents: 1000,
        actualExpensesSource: "expenses",
        lineItems: [
          {
            expenseId: "exp-1",
            nature: "condo_charges",
            notes: "",
            amountCents: 600,
            expenseDate: iso("2025-06-01"),
          },
          {
            expenseId: "exp-2",
            nature: "works",
            notes: "toiture",
            amountCents: 400,
            expenseDate: iso("2025-07-01"),
          },
        ],
      }),
    )) as FinalizeResult;

    const stored = (await fakeDb.doc(`charge_statements/${res.statementId}`).get()).data();
    expect(stored?.lineItems).toHaveLength(2);
    expect((stored?.lineItems as Array<{amountCents: number}>)[0]?.amountCents).toBe(600);
  });

  it("refuse quand la somme des lineItems diverge du total (source=expenses)", async () => {
    seedBase();
    await expect(
      finalizeChargeRegularization.run(
        makeRequest(OWNER, {
          leaseId: "lease-1",
          periodStart: iso("2025-01-01"),
          periodEnd: iso("2025-12-31"),
          actualExpensesCents: 1000,
          actualExpensesSource: "expenses",
          lineItems: [
            {
              expenseId: "exp-1",
              nature: "condo_charges",
              notes: "",
              amountCents: 600,
              expenseDate: iso("2025-06-01"),
            },
          ],
        }),
      ),
    ).rejects.toMatchObject({code: "invalid-argument"});
  });
});
