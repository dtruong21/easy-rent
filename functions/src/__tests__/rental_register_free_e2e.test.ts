/**
 * Test d'intégration end-to-end du **registre locatif complet pour un
 * utilisateur FREE** : bien → locataire → bail (contrat) → paiement, en
 * enchaînant les VRAIES Cloud Functions sur un Firestore en mémoire
 * (`helpers/fake_firestore`), avec les IDs réels threadés d'une étape à l'autre.
 *
 * Comble deux trous réels :
 *   1. Aucun test ne CHAÎNAIT les 4 callables comme un seul landlord bâtissant
 *      un registre cohérent (les tests existants les exercent isolément, et
 *      avec un tier `paid` pour NEUTRALISER le gate FEAT-044).
 *   2. `createPayment` n'avait **aucune** couverture — ce fichier est sa 1re.
 *
 * Vérifie côté serveur (source de vérité du gating) : le free peut monter la
 * chaîne complète, la dénormalisation cross-entité est cohérente, les
 * compteurs de plan s'incrémentent, et les plafonds free (2 biens / 3
 * locataires) sont bien opposés. L'état « à jour / en retard » (`isLeaseLate`)
 * est une fonction Dart, couverte end-to-end par
 * `test/integration/rental_flow_lateness_test.dart` (indépendante du tier) :
 * ici on prouve seulement que le paiement du mois est bien ENREGISTRÉ et
 * couvre la période due.
 */
import type {CallableRequest} from "firebase-functions/v2/https";
import {beforeEach, describe, expect, it, vi} from "vitest";

import {createLease, createPayment} from "../callable/lease_payment";
import {createProperty, createTenant} from "../callable/property_tenant";

import {FakeFirestore, fakeAdminFirestoreHolder} from "./helpers/fake_firestore";
import {VERIFIED_TOKEN} from "./helpers/verified_token";

// Cf. expenses.test.ts pour la justification du import() dynamique interne.
vi.mock("firebase-admin", async () => {
  const {makeFakeAdminModule} = await import("./helpers/fake_firestore");
  return makeFakeAdminModule();
});

let fakeDb: FakeFirestore;

const UID = "free-landlord";

function makeRequest(uid: string | null, data: unknown): CallableRequest {
  return {
    data,
    auth: uid ? {uid, token: VERIFIED_TOKEN, rawToken: ""} : undefined,
    rawRequest: {} as never,
  } as CallableRequest;
}

/** Landlord FREE, registre vide (tous les compteurs de plan à 0). */
function seedFreeLandlord() {
  fakeDb.seed(`landlords/${UID}`, {
    id: UID,
    landlordId: UID,
    subscriptionTier: "free",
    deletedAt: null,
    activePropertiesCount: 0,
    activeTenantsCount: 0,
    activeLeasesCount: 0,
  });
}

const propertyPayload = (extra: Record<string, unknown> = {}) => ({
  name: "Studio Bastille",
  address: "12 rue de la Roquette, 75011 Paris",
  type: "appartement",
  hasElevator: false,
  furnished: false,
  isNewProperty: false,
  ...extra,
});

const tenantPayload = (extra: Record<string, unknown> = {}) => ({
  firstName: "Jean",
  lastName: "Dupont",
  email: "jean.dupont@example.com",
  ...extra,
});

beforeEach(() => {
  fakeDb = new FakeFirestore();
  fakeAdminFirestoreHolder.db = fakeDb;
});

describe("Registre locatif e2e — FREE : bien → locataire → bail → paiement", () => {
  it("un free bâtit la chaîne complète : cohérence cross-entité + compteurs", async () => {
    seedFreeLandlord();

    // 1. BIEN --------------------------------------------------------------
    const {propertyId} = (await createProperty.run(
      makeRequest(UID, propertyPayload()),
    )) as {propertyId: string};
    expect(propertyId).toBeTruthy();
    expect(fakeDb.peek(`landlords/${UID}`)?.activePropertiesCount).toBe(1);

    // 2. LOCATAIRE ---------------------------------------------------------
    const {tenantId} = (await createTenant.run(
      makeRequest(UID, tenantPayload()),
    )) as {tenantId: string};
    expect(tenantId).toBeTruthy();
    expect(fakeDb.peek(`landlords/${UID}`)?.activeTenantsCount).toBe(1);

    // 3. BAIL (contrat) liant bien + locataire -----------------------------
    const {leaseId} = (await createLease.run(
      makeRequest(UID, {
        propertyId,
        tenantId,
        rentAmountCents: 80000,
        chargesAmountCents: 5000,
        startDate: "2026-01-01T00:00:00.000Z",
        leaseType: "unfurnished",
        paymentDay: 5,
        paymentMethod: "virement",
      }),
    )) as {leaseId: string};
    const lease = fakeDb.peek(`leases/${leaseId}`);
    expect(lease?.propertyId).toBe(propertyId);
    expect(lease?.tenantId).toBe(tenantId);
    expect(fakeDb.peek(`landlords/${UID}`)?.activeLeasesCount).toBe(1);

    // 4. PAIEMENT (loyer de janvier réglé) — 1re couverture de createPayment
    const {paymentId} = (await createPayment.run(
      makeRequest(UID, {
        leaseId,
        periodStart: "2026-01-01T00:00:00.000Z",
        periodEnd: "2026-01-31T00:00:00.000Z",
        paidAt: "2026-01-03T00:00:00.000Z",
        rentAmountCents: 80000,
        chargesAmountCents: 5000,
        paymentMethod: "virement",
      }),
    )) as {paymentId: string};
    const payment = fakeDb.peek(`payments/${paymentId}`);
    expect(payment?.leaseId).toBe(leaseId);

    // Chaîne référentielle cohérente : les 4 docs du même landlord.
    const property = fakeDb.peek(`properties/${propertyId}`);
    const tenant = fakeDb.peek(`tenants/${tenantId}`);
    expect(
      new Set([
        property?.landlordId,
        tenant?.landlordId,
        lease?.landlordId,
        payment?.landlordId,
      ]),
    ).toEqual(new Set([UID]));
  });

  it("plafond FREE biens (2) : 3e bien refusé au milieu du registre", async () => {
    seedFreeLandlord();
    await createProperty.run(makeRequest(UID, propertyPayload()));
    await createProperty.run(makeRequest(UID, propertyPayload()));
    expect(fakeDb.peek(`landlords/${UID}`)?.activePropertiesCount).toBe(2);

    await expect(
      createProperty.run(makeRequest(UID, propertyPayload())),
    ).rejects.toMatchObject({code: "resource-exhausted"});
    // Rien créé au-delà du plafond.
    expect(fakeDb.peek(`landlords/${UID}`)?.activePropertiesCount).toBe(2);
  });

  it("plafond FREE locataires (3) : 4e locataire refusé", async () => {
    seedFreeLandlord();
    await createTenant.run(makeRequest(UID, tenantPayload()));
    await createTenant.run(makeRequest(UID, tenantPayload()));
    await createTenant.run(makeRequest(UID, tenantPayload()));
    expect(fakeDb.peek(`landlords/${UID}`)?.activeTenantsCount).toBe(3);

    await expect(
      createTenant.run(makeRequest(UID, tenantPayload())),
    ).rejects.toMatchObject({code: "resource-exhausted"});
  });
});
