/**
 * createLease / updateLease — FEAT-036 (nonRecoverableChargesCents) +
 * FEAT-042 (chargeMode).
 *
 * `firebase-admin` est mocké par un mini Firestore en mémoire (docs stockés
 * dans une Map par path) suffisant pour couvrir ce que `lease_payment.ts`
 * consomme réellement : `db.doc/collection`, `runTransaction`
 * (get/set/update), `FieldValue.serverTimestamp/increment`. Les callables
 * sont invoqués via `CallableFunction.run(request)` (API firebase-functions
 * v2), sans emulator.
 *
 * Portée FEAT-036 : validation/écriture de `nonRecoverableChargesCents` sur
 * `createLease`/`updateLease`, et non-régression de `chargesAmountCents`
 * (part récupérable, inchangée).
 *
 * Portée FEAT-042 : `resolveChargeMode` (cohérence type de bail ↔ mode de
 * charges) et son intégration dans `createLease`/`updateLease`, y compris la
 * coercion à jour de `leaseType` et le forçage `nonRecoverableChargesCents=0`
 * en mode forfait (un forfait ne se ventile pas).
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

// Sous-ensemble d'agrégation count() utilisé par createLease (fail-closed).
interface CountQuery {
  where(field: string, op: string, value: unknown): CountQuery;
  count(): {get(): Promise<{data(): {count: number}}>};
}

const {store, makeRef, makeSnap, makeColl} = vi.hoisted(() => {
  type FakeDocH = Record<string, unknown>;
  const storeH = new Map<string, FakeDocH>();

  function makeSnapH(path: string) {
    const data = storeH.get(path);
    return {exists: data !== undefined, data: () => data};
  }

  function makeRefH(path: string) {
    return {
      id: path.split("/").pop() as string,
      path,
      // FEAT-044 : createLease lit landlordRef.get() (hors transaction).
      get: () => Promise.resolve(makeSnapH(path)),
    };
  }

  // FEAT-044 : query minimale `where(...).count().get()` sur le store.
  function makeQueryH(
    name: string,
    filters: ReadonlyArray<readonly [string, unknown]>,
  ): CountQuery {
    return {
      where: (field: string, _op: string, value: unknown) =>
        makeQueryH(name, [...filters, [field, value]]),
      count: () => ({
        get: () => {
          const prefix = `${name}/`;
          let n = 0;
          for (const [path, data] of storeH.entries()) {
            if (!path.startsWith(prefix)) continue;
            if (path.slice(prefix.length).includes("/")) continue;
            if (filters.every(([f, v]) => data[f] === v)) n++;
          }
          return Promise.resolve({data: () => ({count: n})});
        },
      }),
    };
  }

  function makeCollH(name: string) {
    return {
      doc: (id?: string) =>
        makeRefH(`${name}/${id ?? `auto-${Math.random()}`}`),
      where: (field: string, _op: string, value: unknown) =>
        makeQueryH(name, [[field, value]]),
    };
  }

  return {
    store: storeH,
    makeRef: makeRefH,
    makeSnap: makeSnapH,
    makeColl: makeCollH,
  };
});

vi.mock("firebase-admin", () => {
  const fakeFirestore = () => ({
    collection: (name: string) => makeColl(name),
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
import {
  createLease,
  resolveChargeMode,
  updateLease,
} from "../callable/lease_payment";

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

// FEAT-044 : createLease exige désormais un doc landlord (gate + compteur).
// Seedé en 'paid' (illimité) par défaut → le gate n'interfère PAS avec les
// tests existants ; les tests de gating dédiés surchargent en 'free'.
function seedLandlord(overrides: FakeDoc = {}) {
  store.set(`landlords/${LANDLORD_UID}`, {
    id: LANDLORD_UID,
    landlordId: LANDLORD_UID,
    deletedAt: null,
    subscriptionTier: "paid",
    activeLeasesCount: 0,
    ...overrides,
  });
}

beforeEach(() => {
  store.clear();
  seedProperty("prop-1");
  seedTenant("tenant-1");
  seedLandlord();
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

// ============================================================================
// FEAT-042 — resolveChargeMode (unit, pas de Firestore)
// ============================================================================
describe("resolveChargeMode", () => {
  it("nu (unfurnished) → provisions, même si forfait est demandé", () => {
    expect(resolveChargeMode("unfurnished", undefined)).toBe("provisions");
    expect(resolveChargeMode("unfurnished", null)).toBe("provisions");
    expect(resolveChargeMode("unfurnished", "provisions")).toBe("provisions");
  });

  it("nu (unfurnished) rejette un forfait explicite", () => {
    expect(() => resolveChargeMode("unfurnished", "forfait")).toThrow();
    try {
      resolveChargeMode("unfurnished", "forfait");
      expect.fail("should have thrown");
    } catch (e) {
      expect(e).toMatchObject({code: "invalid-argument"});
    }
  });

  it("mobilité (mobility) → forfait, même si provisions est demandé", () => {
    expect(resolveChargeMode("mobility", undefined)).toBe("forfait");
    expect(resolveChargeMode("mobility", null)).toBe("forfait");
    expect(resolveChargeMode("mobility", "forfait")).toBe("forfait");
  });

  it("mobilité (mobility) rejette des provisions explicites", () => {
    try {
      resolveChargeMode("mobility", "provisions");
      expect.fail("should have thrown");
    } catch (e) {
      expect(e).toMatchObject({code: "invalid-argument"});
    }
  });

  it("meublé (furnished) → provisions par défaut, forfait si demandé", () => {
    expect(resolveChargeMode("furnished", undefined)).toBe("provisions");
    expect(resolveChargeMode("furnished", null)).toBe("provisions");
    expect(resolveChargeMode("furnished", "provisions")).toBe("provisions");
    expect(resolveChargeMode("furnished", "forfait")).toBe("forfait");
  });

  it("étudiant (student) → provisions par défaut, forfait si demandé", () => {
    expect(resolveChargeMode("student", undefined)).toBe("provisions");
    expect(resolveChargeMode("student", null)).toBe("provisions");
    expect(resolveChargeMode("student", "provisions")).toBe("provisions");
    expect(resolveChargeMode("student", "forfait")).toBe("forfait");
  });

  it("rejette une valeur de chargeMode inconnue pour un type libre", () => {
    try {
      resolveChargeMode("furnished", "gratuit");
      expect.fail("should have thrown");
    } catch (e) {
      expect(e).toMatchObject({code: "invalid-argument"});
    }
  });
});

// ============================================================================
// FEAT-042 — createLease : persistance du chargeMode + forfait ⇒ non-récup=0
// ============================================================================
describe("createLease — chargeMode (FEAT-042)", () => {
  it("bail nu : persiste provisions par défaut (chargeMode absent)", async () => {
    const result = (await createLease.run(
      callableRequest(LANDLORD_UID, {
        ...baseCreateLeaseData,
        leaseType: "unfurnished",
      }),
    )) as {leaseId: string};

    const doc = store.get(`leases/${result.leaseId}`);
    expect(doc?.chargeMode).toBe("provisions");
  });

  it("bail nu : rejette un chargeMode=forfait explicite", async () => {
    await expect(
      createLease.run(
        callableRequest(LANDLORD_UID, {
          ...baseCreateLeaseData,
          leaseType: "unfurnished",
          chargeMode: "forfait",
        }),
      ),
    ).rejects.toMatchObject({code: "invalid-argument"});
  });

  it("bail mobilité : persiste forfait par défaut", async () => {
    const result = (await createLease.run(
      callableRequest(LANDLORD_UID, {
        ...baseCreateLeaseData,
        leaseType: "mobility",
      }),
    )) as {leaseId: string};

    const doc = store.get(`leases/${result.leaseId}`);
    expect(doc?.chargeMode).toBe("forfait");
  });

  it("bail meublé : persiste le mode choisi (forfait)", async () => {
    const result = (await createLease.run(
      callableRequest(LANDLORD_UID, {
        ...baseCreateLeaseData,
        leaseType: "furnished",
        chargeMode: "forfait",
      }),
    )) as {leaseId: string};

    const doc = store.get(`leases/${result.leaseId}`);
    expect(doc?.chargeMode).toBe("forfait");
  });

  it("bail meublé sans chargeMode fourni : défaut provisions", async () => {
    const result = (await createLease.run(
      callableRequest(LANDLORD_UID, {
        ...baseCreateLeaseData,
        leaseType: "furnished",
      }),
    )) as {leaseId: string};

    const doc = store.get(`leases/${result.leaseId}`);
    expect(doc?.chargeMode).toBe("provisions");
  });

  it("forfait ⇒ nonRecoverableChargesCents forcé à 0, quelle que soit la valeur envoyée", async () => {
    const result = (await createLease.run(
      callableRequest(LANDLORD_UID, {
        ...baseCreateLeaseData,
        leaseType: "mobility",
        nonRecoverableChargesCents: 4200,
      }),
    )) as {leaseId: string};

    const doc = store.get(`leases/${result.leaseId}`);
    expect(doc?.chargeMode).toBe("forfait");
    expect(doc?.nonRecoverableChargesCents).toBe(0);
  });

  it("provisions : nonRecoverableChargesCents reste écrit tel quel", async () => {
    const result = (await createLease.run(
      callableRequest(LANDLORD_UID, {
        ...baseCreateLeaseData,
        leaseType: "furnished",
        chargeMode: "provisions",
        nonRecoverableChargesCents: 1234,
      }),
    )) as {leaseId: string};

    const doc = store.get(`leases/${result.leaseId}`);
    expect(doc?.chargeMode).toBe("provisions");
    expect(doc?.nonRecoverableChargesCents).toBe(1234);
  });
});

// ============================================================================
// FEAT-042 — updateLease : coercition chargeMode sur changement de leaseType
// ============================================================================
describe("updateLease — chargeMode coercition (FEAT-042)", () => {
  it("meublé forfait → mobilité : coerce et conserve forfait", async () => {
    seedLease("lease-1", {leaseType: "furnished", chargeMode: "forfait"});

    await updateLease.run(
      callableRequest(LANDLORD_UID, {
        id: "lease-1",
        patch: {leaseType: "mobility"},
      }),
    );

    const doc = store.get("leases/lease-1");
    expect(doc?.leaseType).toBe("mobility");
    expect(doc?.chargeMode).toBe("forfait");
  });

  it("meublé forfait → nu : coerce vers provisions", async () => {
    seedLease("lease-1", {leaseType: "furnished", chargeMode: "forfait"});

    await updateLease.run(
      callableRequest(LANDLORD_UID, {
        id: "lease-1",
        patch: {leaseType: "unfurnished"},
      }),
    );

    const doc = store.get("leases/lease-1");
    expect(doc?.leaseType).toBe("unfurnished");
    expect(doc?.chargeMode).toBe("provisions");
  });

  it("mobilité → nu : coerce vers provisions (sans chargeMode explicite)", async () => {
    seedLease("lease-1", {leaseType: "mobility", chargeMode: "forfait"});

    await updateLease.run(
      callableRequest(LANDLORD_UID, {
        id: "lease-1",
        patch: {leaseType: "unfurnished"},
      }),
    );

    const doc = store.get("leases/lease-1");
    expect(doc?.chargeMode).toBe("provisions");
  });

  it("nu (chargeMode legacy null) → mobilité : coerce vers forfait", async () => {
    seedLease("lease-1", {leaseType: "unfurnished", chargeMode: null});

    await updateLease.run(
      callableRequest(LANDLORD_UID, {
        id: "lease-1",
        patch: {leaseType: "mobility"},
      }),
    );

    const doc = store.get("leases/lease-1");
    expect(doc?.chargeMode).toBe("forfait");
  });

  it("chargeMode explicite incompatible avec le nouveau leaseType est rejeté", async () => {
    seedLease("lease-1", {leaseType: "furnished", chargeMode: "provisions"});

    await expect(
      updateLease.run(
        callableRequest(LANDLORD_UID, {
          id: "lease-1",
          patch: {leaseType: "mobility", chargeMode: "provisions"},
        }),
      ),
    ).rejects.toMatchObject({code: "invalid-argument"});
  });

  it("changer uniquement chargeMode (meublé provisions → forfait) sans toucher leaseType", async () => {
    seedLease("lease-1", {leaseType: "furnished", chargeMode: "provisions"});

    await updateLease.run(
      callableRequest(LANDLORD_UID, {
        id: "lease-1",
        patch: {chargeMode: "forfait"},
      }),
    );

    const doc = store.get("leases/lease-1");
    expect(doc?.leaseType).toBe("furnished");
    expect(doc?.chargeMode).toBe("forfait");
  });

  it("patch sans leaseType ni chargeMode : chargeMode existant inchangé", async () => {
    seedLease("lease-1", {leaseType: "furnished", chargeMode: "forfait"});

    await updateLease.run(
      callableRequest(LANDLORD_UID, {
        id: "lease-1",
        patch: {rentAmountCents: 90000},
      }),
    );

    const doc = store.get("leases/lease-1");
    expect(doc?.chargeMode).toBe("forfait");
  });

  it("forfait ⇒ nonRecoverableChargesCents forcé à 0 (coercion via leaseType)", async () => {
    seedLease("lease-1", {
      leaseType: "furnished",
      chargeMode: "provisions",
      nonRecoverableChargesCents: 2500,
    });

    await updateLease.run(
      callableRequest(LANDLORD_UID, {
        id: "lease-1",
        patch: {leaseType: "mobility"},
      }),
    );

    const doc = store.get("leases/lease-1");
    expect(doc?.chargeMode).toBe("forfait");
    expect(doc?.nonRecoverableChargesCents).toBe(0);
  });

  it("forfait ⇒ nonRecoverableChargesCents forcé à 0 même si envoyé explicitement dans le patch", async () => {
    seedLease("lease-1", {leaseType: "mobility", chargeMode: "forfait"});

    await updateLease.run(
      callableRequest(LANDLORD_UID, {
        id: "lease-1",
        patch: {nonRecoverableChargesCents: 999},
      }),
    );

    const doc = store.get("leases/lease-1");
    expect(doc?.nonRecoverableChargesCents).toBe(0);
  });

  it("mobilité legacy (chargeMode absent) : mode effectif forfait → force nonRecoverableChargesCents=0 + backfill chargeMode", async () => {
    // Bail legacy pré-042 : leaseType mobility mais aucun chargeMode persisté
    // (undefined). Un patch qui ne touche ni leaseType ni chargeMode doit
    // quand même dériver le mode effectif (forfait) et neutraliser la
    // ventilation, tout en matérialisant le mode par backfill lazy.
    seedLease("lease-1", {leaseType: "mobility"});
    // Sanity : le seed n'a effectivement pas de chargeMode persisté.
    expect(store.get("leases/lease-1")?.chargeMode).toBeUndefined();

    await updateLease.run(
      callableRequest(LANDLORD_UID, {
        id: "lease-1",
        patch: {nonRecoverableChargesCents: 999},
      }),
    );

    const doc = store.get("leases/lease-1");
    expect(doc?.nonRecoverableChargesCents).toBe(0);
    expect(doc?.chargeMode).toBe("forfait");
  });

  it("meublé legacy (chargeMode null) patché : reste provisions (backfill) + ventilation conservée", async () => {
    // Bail legacy meublé sans mode explicite (null) : le mode libre par
    // défaut est provisions. Un patch qui ne touche ni leaseType ni
    // chargeMode ne doit pas forcer la ventilation à 0, et doit backfill
    // provisions.
    seedLease("lease-1", {
      leaseType: "furnished",
      chargeMode: null,
      nonRecoverableChargesCents: 1200,
    });

    await updateLease.run(
      callableRequest(LANDLORD_UID, {
        id: "lease-1",
        patch: {rentAmountCents: 90000},
      }),
    );

    const doc = store.get("leases/lease-1");
    expect(doc?.chargeMode).toBe("provisions");
    // Ventilation conservée : provisions ne force pas la part non récup à 0.
    expect(doc?.nonRecoverableChargesCents).toBe(1200);
    expect(doc?.rentAmountCents).toBe(90000);
  });

  it("invalid-argument rejeté ne modifie pas le doc (leaseType inconnu)", async () => {
    seedLease("lease-1", {leaseType: "furnished", chargeMode: "provisions"});

    await expect(
      updateLease.run(
        callableRequest(LANDLORD_UID, {
          id: "lease-1",
          patch: {leaseType: "commercial"},
        }),
      ),
    ).rejects.toMatchObject({code: "invalid-argument"});

    const doc = store.get("leases/lease-1");
    expect(doc?.leaseType).toBe("furnished");
    expect(doc?.chargeMode).toBe("provisions");
  });
});

describe("createLease / updateLease — plafond de baux actifs (FEAT-044)", () => {
  it("free AU plafond (2 baux actifs) → createLease refusé", async () => {
    seedLandlord({subscriptionTier: "free", activeLeasesCount: 2});
    await expect(
      createLease.run(callableRequest(LANDLORD_UID, {...baseCreateLeaseData})),
    ).rejects.toMatchObject({
      code: "resource-exhausted",
      message: "lease_limit_reached",
    });
  });

  it("free sous le plafond → createLease OK + incrémente activeLeasesCount", async () => {
    seedLandlord({subscriptionTier: "free", activeLeasesCount: 1});
    const res = (await createLease.run(
      callableRequest(LANDLORD_UID, {...baseCreateLeaseData}),
    )) as {leaseId: string};
    expect(res.leaseId).toBeTruthy();
    expect(store.get(`landlords/${LANDLORD_UID}`)?.activeLeasesCount).toBe(2);
  });

  it("bail créé INACTIF (terminated) → pas de gate ni d'incrément", async () => {
    seedLandlord({subscriptionTier: "free", activeLeasesCount: 2});
    const res = (await createLease.run(
      callableRequest(LANDLORD_UID, {
        ...baseCreateLeaseData,
        status: "terminated",
      }),
    )) as {leaseId: string};
    expect(res.leaseId).toBeTruthy();
    expect(store.get(`landlords/${LANDLORD_UID}`)?.activeLeasesCount).toBe(2);
  });

  it("FAIL-CLOSED : compteur absent + 2 baux actifs existants → refusé", async () => {
    // landlord free SANS activeLeasesCount (legacy) → recompte live = 2 → refus.
    store.set(`landlords/${LANDLORD_UID}`, {
      id: LANDLORD_UID,
      landlordId: LANDLORD_UID,
      subscriptionTier: "free",
      deletedAt: null,
    });
    seedLease("l-old-1", {status: "active"});
    seedLease("l-old-2", {status: "active"});
    await expect(
      createLease.run(callableRequest(LANDLORD_UID, {...baseCreateLeaseData})),
    ).rejects.toMatchObject({code: "resource-exhausted"});
  });

  it("réactivation (terminated→active) AU plafond → updateLease refusé", async () => {
    seedLandlord({subscriptionTier: "free", activeLeasesCount: 2});
    seedLease("lease-1", {status: "terminated"});
    await expect(
      updateLease.run(
        callableRequest(LANDLORD_UID, {
          id: "lease-1",
          patch: {status: "active"},
        }),
      ),
    ).rejects.toMatchObject({code: "resource-exhausted"});
  });

  it("désactivation (active→terminated) → décrémente activeLeasesCount (clampé)", async () => {
    seedLandlord({subscriptionTier: "free", activeLeasesCount: 2});
    seedLease("lease-1", {status: "active"});
    const res = (await updateLease.run(
      callableRequest(LANDLORD_UID, {
        id: "lease-1",
        patch: {status: "terminated"},
      }),
    )) as {updated: boolean};
    expect(res.updated).toBe(true);
    expect(store.get(`landlords/${LANDLORD_UID}`)?.activeLeasesCount).toBe(1);
  });
});
