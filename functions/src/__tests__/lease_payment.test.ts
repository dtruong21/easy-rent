/**
 * createLease / updateLease — FEAT-036 (nonRecoverableChargesCents).
 *
 * `firebase-admin` est mocké par un mini Firestore en mémoire (docs stockés
 * dans une Map par path) suffisant pour couvrir ce que `lease_payment.ts`
 * consomme réellement : `db.doc/collection`, `runTransaction`
 * (get/set/update), `FieldValue.serverTimestamp/increment`. Les callables
 * sont invoqués via `CallableFunction.run(request)` (API firebase-functions
 * v2), sans emulator.
 *
 * Portée FEAT-036 uniquement : validation/écriture de
 * `nonRecoverableChargesCents` sur `createLease`/`updateLease`, et
 * non-régression de `chargesAmountCents` (part récupérable, inchangée).
 */

import type {CallableRequest} from "firebase-functions/v2/https";
import {beforeEach, describe, expect, it, vi} from "vitest";

// ---------------------------------------------------------------------------
// Mock firebase-admin — mini Firestore en mémoire, seulement ce dont
// lease_payment.ts a besoin (doc/collection/runTransaction/FieldValue).
// `vi.mock` factories sont hoisted en haut du fichier : le store et les
// helpers doivent l'être aussi (`vi.hoisted`) pour rester accessibles ici
// ET dans le corps des tests plus bas.
// ---------------------------------------------------------------------------
type FakeDoc = Record<string, unknown>;

const {store, makeRef, makeSnap} = vi.hoisted(() => {
  type FakeDocH = Record<string, unknown>;
  const storeH = new Map<string, FakeDocH>();

  function makeRefH(path: string) {
    return {
      id: path.split("/").pop() as string,
      path,
    };
  }

  function makeSnapH(path: string) {
    const data = storeH.get(path);
    return {
      exists: data !== undefined,
      data: () => data,
    };
  }

  return {store: storeH, makeRef: makeRefH, makeSnap: makeSnapH};
});

vi.mock("firebase-admin", () => {
  const fakeFirestore = () => ({
    collection: (name: string) => ({
      doc: (id?: string) =>
        makeRef(`${name}/${id ?? `auto-${Math.random()}`}`),
    }),
    doc: (path: string) => makeRef(path),
    runTransaction: async (
      cb: (tx: {
        get: (ref: {path: string}) => Promise<ReturnType<typeof makeSnap>>;
        set: (ref: {path: string}, data: FakeDoc) => void;
        update: (ref: {path: string}, data: FakeDoc) => void;
      }) => Promise<unknown>,
    ) => {
      const tx = {
        get: (ref: {path: string}) => Promise.resolve(makeSnap(ref.path)),
        set: (ref: {path: string}, data: FakeDoc) => {
          store.set(ref.path, {...data});
        },
        update: (ref: {path: string}, data: FakeDoc) => {
          const existing = store.get(ref.path) ?? {};
          const merged = {...existing};
          for (const [k, v] of Object.entries(data)) {
            if (
              v !== null &&
              typeof v === "object" &&
              "__increment" in (v as Record<string, unknown>)
            ) {
              const base = typeof merged[k] === "number" ? merged[k] : 0;
              merged[k] = base + (v as {__increment: number}).__increment;
            } else {
              merged[k] = v;
            }
          }
          store.set(ref.path, merged);
        },
      };
      return cb(tx);
    },
  });

  return {
    firestore: Object.assign(fakeFirestore, {
      FieldValue: {
        serverTimestamp: () => "__server-timestamp__",
        increment: (n: number) => ({__increment: n}),
      },
    }),
  };
});

// Import après le mock (hoisted par vitest de toute façon, mais explicite).
import {createLease, updateLease} from "../callable/lease_payment";

const LANDLORD_UID = "landlord-1";

type AuthData = NonNullable<CallableRequest["auth"]>;

/**
 * Construit un `CallableRequest<T>` minimal pour `CallableFunction.run(...)`.
 * `rawRequest`/`token`/`acceptsStreaming` sont hors-sujet pour ces tests
 * (seul `data`/`auth.uid` sont lus par les handlers) : cast ciblé sur ces
 * champs uniquement.
 */
function callableRequest<T>(uid: string, data: T): CallableRequest<T> {
  return {
    data,
    auth: {uid, token: {} as AuthData["token"], rawToken: ""},
    rawRequest: {} as CallableRequest<T>["rawRequest"],
    acceptsStreaming: false,
  };
}

function seedProperty(id: string, landlordId = LANDLORD_UID) {
  store.set(`properties/${id}`, {
    landlordId,
    deletedAt: null,
    name: "Appartement Test",
    address: "1 rue de Test",
    activeLeaseCount: 0,
  });
}

function seedTenant(id: string, landlordId = LANDLORD_UID) {
  store.set(`tenants/${id}`, {
    landlordId,
    deletedAt: null,
    firstName: "Jean",
    lastName: "Dupont",
    email: "jean.dupont@example.com",
    activeLeaseCount: 0,
  });
}

function seedLease(id: string, overrides: FakeDoc = {}) {
  store.set(`leases/${id}`, {
    id,
    landlordId: LANDLORD_UID,
    propertyId: "prop-1",
    tenantId: "tenant-1",
    rentAmountCents: 80000,
    chargesAmountCents: 5000,
    nonRecoverableChargesCents: 0,
    status: "active",
    deletedAt: null,
    ...overrides,
  });
}

const baseCreateLeaseData = {
  propertyId: "prop-1",
  tenantId: "tenant-1",
  rentAmountCents: 80000,
  chargesAmountCents: 5000,
  startDate: "2026-01-01T00:00:00.000Z",
  leaseType: "unfurnished",
  paymentDay: 5,
  paymentMethod: "virement",
  solidarityClause: true,
  entryInventoryDone: true,
};

beforeEach(() => {
  store.clear();
  seedProperty("prop-1");
  seedTenant("tenant-1");
});

describe("createLease — nonRecoverableChargesCents (FEAT-036)", () => {
  it("écrit le champ quand une valeur valide est fournie", async () => {
    const result = (await createLease.run(
      callableRequest(LANDLORD_UID, {
        ...baseCreateLeaseData,
        nonRecoverableChargesCents: 1500,
      }),
    )) as {leaseId: string};

    const doc = store.get(`leases/${result.leaseId}`);
    expect(doc?.nonRecoverableChargesCents).toBe(1500);
  });

  it("applique le défaut 0 quand le champ est absent", async () => {
    const result = (await createLease.run(
      callableRequest(LANDLORD_UID, {...baseCreateLeaseData}),
    )) as {leaseId: string};

    const doc = store.get(`leases/${result.leaseId}`);
    expect(doc?.nonRecoverableChargesCents).toBe(0);
  });

  it("rejette une valeur négative", async () => {
    await expect(
      createLease.run(
        callableRequest(LANDLORD_UID, {
          ...baseCreateLeaseData,
          nonRecoverableChargesCents: -100,
        }),
      ),
    ).rejects.toMatchObject({code: "invalid-argument"});
  });

  it("non-régression : chargesAmountCents (récupérable) reste écrit à l'identique", async () => {
    const result = (await createLease.run(
      callableRequest(LANDLORD_UID, {
        ...baseCreateLeaseData,
        chargesAmountCents: 7500,
        nonRecoverableChargesCents: 2000,
      }),
    )) as {leaseId: string};

    const doc = store.get(`leases/${result.leaseId}`);
    expect(doc?.chargesAmountCents).toBe(7500);
    expect(doc?.nonRecoverableChargesCents).toBe(2000);
  });
});

describe("updateLease — nonRecoverableChargesCents (FEAT-036)", () => {
  it("écrit un patch valide", async () => {
    seedLease("lease-1");

    const result = (await updateLease.run(
      callableRequest(LANDLORD_UID, {
        id: "lease-1",
        patch: {nonRecoverableChargesCents: 3000},
      }),
    )) as {updated: boolean};

    expect(result.updated).toBe(true);
    const doc = store.get("leases/lease-1");
    expect(doc?.nonRecoverableChargesCents).toBe(3000);
  });

  it("rejette un patch négatif avec invalid-argument", async () => {
    seedLease("lease-1");

    await expect(
      updateLease.run(
        callableRequest(LANDLORD_UID, {
          id: "lease-1",
          patch: {nonRecoverableChargesCents: -1},
        }),
      ),
    ).rejects.toMatchObject({code: "invalid-argument"});

    // Le doc ne doit pas avoir été modifié par le patch rejeté.
    const doc = store.get("leases/lease-1");
    expect(doc?.nonRecoverableChargesCents).toBe(0);
  });

  it("rejette un patch non-entier avec invalid-argument", async () => {
    seedLease("lease-1");

    await expect(
      updateLease.run(
        callableRequest(LANDLORD_UID, {
          id: "lease-1",
          patch: {nonRecoverableChargesCents: 12.5},
        }),
      ),
    ).rejects.toMatchObject({code: "invalid-argument"});
  });

  it("non-régression : chargesAmountCents continue d'être patchable normalement", async () => {
    seedLease("lease-1");

    await updateLease.run(
      callableRequest(LANDLORD_UID, {
        id: "lease-1",
        patch: {chargesAmountCents: 6000},
      }),
    );

    const doc = store.get("leases/lease-1");
    expect(doc?.chargesAmountCents).toBe(6000);
    // nonRecoverableChargesCents n'est pas touché par ce patch.
    expect(doc?.nonRecoverableChargesCents).toBe(0);
  });
});
