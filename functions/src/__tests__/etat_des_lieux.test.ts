import {Timestamp} from "firebase-admin/firestore";
import type {CallableRequest} from "firebase-functions/v2/https";
import {beforeEach, describe, expect, it, vi} from "vitest";

import {createEtatDesLieux, validateRooms} from "../callable/etat_des_lieux";

import {FakeFirestore, fakeAdminFirestoreHolder} from "./helpers/fake_firestore";

// Mock firebase-admin (cf. helpers/fake_firestore.ts)
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
// validateRooms
// ============================================================================
describe("validateRooms", () => {
  it("accepte un tableau valide de pièces avec éléments", () => {
    const rooms = validateRooms([
      {
        name: "Salon",
        elements: [
          {name: "Canapé", condition: "bon", comment: "Léger scratch"},
          {name: "Table", condition: "neuf", comment: null},
        ],
      },
    ]);
    expect(rooms).toHaveLength(1);
    expect(rooms[0].name).toBe("Salon");
    expect(rooms[0].elements).toHaveLength(2);
    expect(rooms[0].elements[0].comment).toBe("Léger scratch");
  });

  it("rejette une condition invalide", () => {
    expect(() =>
      validateRooms([
        {
          name: "Salon",
          elements: [{name: "Canapé", condition: "parfait", comment: null}],
        },
      ]),
    ).toThrow();
  });

  it("rejette quand rooms n'est pas un array", () => {
    expect(() => validateRooms({name: "Salon"})).toThrow();
  });
});

// ============================================================================
// createEtatDesLieux
// ============================================================================
interface CreateResult {
  etatDesLieuxId: string;
}

describe("createEtatDesLieux", () => {
  const LANDLORD = "landlord-a";
  const iso = (d: string) => `${d}T00:00:00.000Z`;

  function seedBase() {
    fakeDb.seed("landlords/landlord-a", {fullName: "Jean Bailleur"});
    fakeDb.seed("leases/lease-1", {
      landlordId: LANDLORD,
      propertyId: "prop-1",
      tenantFirstName: "Marie",
      tenantLastName: "Dupont",
      propertyAddress: "10 rue de la Paix",
      deletedAt: null,
    });
  }

  it("happy path: crée un EDL immuable avec parties figées depuis le bail", async () => {
    seedBase();
    const res = (await createEtatDesLieux.run(
      makeRequest(LANDLORD, {
        leaseId: "lease-1",
        type: "entree",
        date: iso("2025-09-15"),
        keysCount: 2,
        rooms: [
          {
            name: "Salon",
            elements: [
              {name: "Canapé", condition: "bon", comment: null},
              {name: "Table", condition: "neuf", comment: "Rayée"},
            ],
          },
          {
            name: "Chambre",
            elements: [{name: "Lit", condition: "moyen", comment: null}],
          },
        ],
        meterReadings: {
          waterIndex: "001234",
          electricityIndex: "009876",
          gasIndex: null,
        },
        generalComment: "État général correct",
      }),
    )) as CreateResult;

    expect(res.etatDesLieuxId).toBeDefined();
    const stored = (await fakeDb.doc(`etat_des_lieux/${res.etatDesLieuxId}`).get()).data();
    expect(stored?.id).toBe(res.etatDesLieuxId);
    expect(stored?.landlordId).toBe(LANDLORD);
    expect(stored?.leaseId).toBe("lease-1");
    expect(stored?.propertyId).toBe("prop-1");
    expect(stored?.type).toBe("entree");
    expect(stored?.tenantFullName).toBe("Marie Dupont");
    expect(stored?.propertyAddress).toBe("10 rue de la Paix");
    expect(stored?.landlordFullName).toBe("Jean Bailleur");
    expect(stored?.keysCount).toBe(2);
    expect(stored?.rooms).toHaveLength(2);
    expect(stored?.meterReadings?.waterIndex).toBe("001234");
    expect(stored?.generalComment).toBe("État général correct");
    expect(stored?.schemaVersion).toBe(1);
    expect(stored?.createdAt).toBeDefined();
  });

  it("refuse un bail non possédé", async () => {
    seedBase();
    fakeDb.seed("landlords/autre", {fullName: "Un Autre"});
    await expect(
      createEtatDesLieux.run(
        makeRequest("autre", {
          leaseId: "lease-1",
          type: "entree",
          date: iso("2025-09-15"),
          keysCount: 1,
          rooms: [],
          meterReadings: {},
          generalComment: null,
        }),
      ),
    ).rejects.toMatchObject({code: "permission-denied"});
  });

  it("refuse un bail supprimé", async () => {
    seedBase();
    fakeDb.seed("leases/lease-1", {
      landlordId: LANDLORD,
      propertyId: "prop-1",
      tenantFirstName: "Marie",
      tenantLastName: "Dupont",
      propertyAddress: "10 rue de la Paix",
      deletedAt: Timestamp.fromDate(new Date(iso("2025-01-01"))),
    });

    await expect(
      createEtatDesLieux.run(
        makeRequest(LANDLORD, {
          leaseId: "lease-1",
          type: "entree",
          date: iso("2025-09-15"),
          keysCount: 1,
          rooms: [],
          meterReadings: {},
          generalComment: null,
        }),
      ),
    ).rejects.toMatchObject({code: "failed-precondition", message: "lease is deleted"});
  });

  it("refuse type invalide", async () => {
    seedBase();
    await expect(
      createEtatDesLieux.run(
        makeRequest(LANDLORD, {
          leaseId: "lease-1",
          type: "invalid_type",
          date: iso("2025-09-15"),
          keysCount: 1,
          rooms: [],
          meterReadings: {},
          generalComment: null,
        }),
      ),
    ).rejects.toMatchObject({code: "invalid-argument"});
  });

  it("refuse une condition d'élément hors enum", async () => {
    seedBase();
    await expect(
      createEtatDesLieux.run(
        makeRequest(LANDLORD, {
          leaseId: "lease-1",
          type: "entree",
          date: iso("2025-09-15"),
          keysCount: 1,
          rooms: [
            {
              name: "Salon",
              elements: [{name: "Canapé", condition: "parfait", comment: null}],
            },
          ],
          meterReadings: {},
          generalComment: null,
        }),
      ),
    ).rejects.toMatchObject({code: "invalid-argument"});
  });

  it("refuse keysCount < 0", async () => {
    seedBase();
    await expect(
      createEtatDesLieux.run(
        makeRequest(LANDLORD, {
          leaseId: "lease-1",
          type: "entree",
          date: iso("2025-09-15"),
          keysCount: -1,
          rooms: [],
          meterReadings: {},
          generalComment: null,
        }),
      ),
    ).rejects.toMatchObject({code: "invalid-argument"});
  });

  it("non authentifié → throw", async () => {
    seedBase();
    await expect(
      createEtatDesLieux.run(
        makeRequest(null, {
          leaseId: "lease-1",
          type: "entree",
          date: iso("2025-09-15"),
          keysCount: 1,
          rooms: [],
          meterReadings: {},
          generalComment: null,
        }),
      ),
    ).rejects.toThrow();
  });
});
