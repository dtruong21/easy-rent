/**
 * createLease / updateLease / createPayment / updatePayment — callables.
 *
 * Réplique des triggers Postgres SECURITY DEFINER :
 *   - assert_lease_ownership_consistency : property + tenant doivent
 *     appartenir au même landlord que le lease.
 *   - assert_payment_lease_ownership : payment.lease doit appartenir
 *     au même landlord que le payment.
 *
 * Inclut la snapshot des dénormalisations (FEAT-019 data model §2.2)
 * pour que la liste des cards charge en 1 query sans join client-side.
 *
 * activeLeaseCount maintenu transactionnellement à la création d'un lease
 * actif et au changement de status via updateLease ; la soft-delete est
 * gérée par softDeleteEntity (qui décrémente côté trigger ultérieurement).
 */

import * as admin from "firebase-admin";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {
  asBag,
  assertOwnedAndActive,
  dataOrFail,
  optionalInt,
  optionalNumber,
  optionalString,
  optionalTimestamp,
  requireAuthUid,
  requireBool,
  requireInt,
  requireString,
  toTimestamp,
} from "../utils/callable_helpers";

const LEASE_TYPES = new Set([
  "unfurnished",
  "furnished",
  "mobility",
  "student",
]);
const LEASE_STATUSES = new Set(["active", "terminated", "archived"]);
const PAYMENT_METHODS = new Set([
  "virement",
  "cheque",
  "especes",
  "prelevement",
  "autre",
]);

const IRL_QUARTER_RE = /^T[1-4]-\d{4}$/;

// ============================================================================
// createLease
// ============================================================================
export const createLease = onCall(
  {region: "europe-west1"},
  async (request) => {
    const uid = requireAuthUid(request);
    const data = asBag(request.data);

    const propertyId = requireString(data.propertyId, "propertyId");
    const tenantId = requireString(data.tenantId, "tenantId");
    const rentAmountCents = requireInt(
      data.rentAmountCents,
      "rentAmountCents",
      {min: 1},
    );
    const chargesAmountCents = requireInt(
      data.chargesAmountCents ?? 0,
      "chargesAmountCents",
      {min: 0},
    );
    const startDate = toTimestamp(data.startDate, "startDate");
    const endDate = optionalTimestamp(data.endDate, "endDate");
    const status = requireString(data.status ?? "active", "status");
    if (!LEASE_STATUSES.has(status)) {
      throw new HttpsError("invalid-argument", `invalid status: ${status}`);
    }
    const leaseType = requireString(data.leaseType, "leaseType");
    if (!LEASE_TYPES.has(leaseType)) {
      throw new HttpsError(
        "invalid-argument",
        `invalid leaseType: ${leaseType}`,
      );
    }
    const paymentDay = requireInt(data.paymentDay, "paymentDay", {
      min: 1,
      max: 28,
    });
    const paymentMethod = requireString(data.paymentMethod, "paymentMethod");
    if (!PAYMENT_METHODS.has(paymentMethod)) {
      throw new HttpsError(
        "invalid-argument",
        `invalid paymentMethod: ${paymentMethod}`,
      );
    }
    const depositAmountCents = optionalInt(
      data.depositAmountCents,
      "depositAmountCents",
      {min: 0},
    );
    const irlIndexValue = optionalNumber(data.irlIndexValue, "irlIndexValue");
    const irlQuarterRef = optionalString(data.irlQuarterRef, "irlQuarterRef");
    if (irlQuarterRef !== null && !IRL_QUARTER_RE.test(irlQuarterRef)) {
      throw new HttpsError(
        "invalid-argument",
        "irlQuarterRef format T[1-4]-YYYY",
      );
    }
    const agencyFeesCents = requireInt(
      data.agencyFeesCents ?? 0,
      "agencyFeesCents",
      {min: 0},
    );
    const solidarityClause = requireBool(
      data.solidarityClause,
      "solidarityClause",
    );
    const entryInventoryDone = requireBool(
      data.entryInventoryDone,
      "entryInventoryDone",
    );

    const db = admin.firestore();
    const leaseRef = db.collection("leases").doc();
    const propertyRef = db.doc(`properties/${propertyId}`);
    const tenantRef = db.doc(`tenants/${tenantId}`);

    return await db.runTransaction(async (tx) => {
      const [propertySnap, tenantSnap] = await Promise.all([
        tx.get(propertyRef),
        tx.get(tenantRef),
      ]);

      const property = dataOrFail(propertySnap, "property not found");
      assertOwnedAndActive(property, uid, "property");
      const tenant = dataOrFail(tenantSnap, "tenant not found");
      assertOwnedAndActive(tenant, uid, "tenant");

      const now = admin.firestore.FieldValue.serverTimestamp();
      tx.set(leaseRef, {
        id: leaseRef.id,
        landlordId: uid,
        propertyId,
        tenantId,
        propertyName: property.name,
        propertyAddress: property.address,
        tenantFirstName: tenant.firstName,
        tenantLastName: tenant.lastName,
        tenantEmail: tenant.email,
        rentAmountCents,
        chargesAmountCents,
        startDate,
        endDate,
        status,
        leaseType,
        depositAmountCents,
        paymentDay,
        paymentMethod,
        irlIndexValue,
        irlQuarterRef,
        agencyFeesCents,
        solidarityClause,
        entryInventoryDone,
        createdAt: now,
        updatedAt: now,
        deletedAt: null,
      });

      if (status === "active") {
        tx.update(propertyRef, {
          activeLeaseCount: admin.firestore.FieldValue.increment(1),
        });
        tx.update(tenantRef, {
          activeLeaseCount: admin.firestore.FieldValue.increment(1),
        });
      }

      return {leaseId: leaseRef.id};
    });
  },
);

// ============================================================================
// updateLease — champs mutables uniquement (propertyId/tenantId immuables)
// ============================================================================
const LEASE_MUTABLE_FIELDS = new Set([
  "rentAmountCents",
  "chargesAmountCents",
  "endDate",
  "status",
  "leaseType",
  "depositAmountCents",
  "paymentDay",
  "paymentMethod",
  "irlIndexValue",
  "irlQuarterRef",
  "agencyFeesCents",
  "solidarityClause",
  "entryInventoryDone",
]);

export const updateLease = onCall(
  {region: "europe-west1"},
  async (request) => {
    const uid = requireAuthUid(request);
    const data = asBag(request.data);
    const id = requireString(data.id, "id");
    const patch = asBag(data.patch);

    const cleanPatch: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(patch)) {
      if (!LEASE_MUTABLE_FIELDS.has(k)) {
        throw new HttpsError(
          "invalid-argument",
          `field ${k} is immutable or unknown`,
        );
      }
      if (k === "endDate") {
        cleanPatch[k] = v == null ? null : toTimestamp(v, "endDate");
      } else {
        cleanPatch[k] = v;
      }
    }
    if (cleanPatch.status !== undefined) {
      if (
        typeof cleanPatch.status !== "string" ||
        !LEASE_STATUSES.has(cleanPatch.status)
      ) {
        throw new HttpsError("invalid-argument", "invalid status");
      }
    }

    const db = admin.firestore();
    const leaseRef = db.doc(`leases/${id}`);

    return await db.runTransaction(async (tx) => {
      const snap = await tx.get(leaseRef);
      const lease = dataOrFail(snap, "lease not found");
      assertOwnedAndActive(lease, uid, "lease");

      const oldStatus = typeof lease.status === "string" ? lease.status : "";
      const newStatusUnknown = cleanPatch.status;
      const newStatus =
        typeof newStatusUnknown === "string" ? newStatusUnknown : oldStatus;
      const wasActive = oldStatus === "active";
      const isActive = newStatus === "active";
      const delta = isActive === wasActive ? 0 : isActive ? 1 : -1;

      tx.update(leaseRef, {
        ...cleanPatch,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      if (delta !== 0) {
        const propertyId = lease.propertyId;
        const tenantId = lease.tenantId;
        if (typeof propertyId === "string" && typeof tenantId === "string") {
          tx.update(db.doc(`properties/${propertyId}`), {
            activeLeaseCount: admin.firestore.FieldValue.increment(delta),
          });
          tx.update(db.doc(`tenants/${tenantId}`), {
            activeLeaseCount: admin.firestore.FieldValue.increment(delta),
          });
        }
      }

      return {updated: true};
    });
  },
);

// ============================================================================
// createPayment — cross-entity (lease ownership)
// ============================================================================
export const createPayment = onCall(
  {region: "europe-west1"},
  async (request) => {
    const uid = requireAuthUid(request);
    const data = asBag(request.data);

    const leaseId = requireString(data.leaseId, "leaseId");
    const periodStart = toTimestamp(data.periodStart, "periodStart");
    const periodEnd = toTimestamp(data.periodEnd, "periodEnd");
    const paidAt = toTimestamp(data.paidAt, "paidAt");
    const rentAmountCents = requireInt(
      data.rentAmountCents,
      "rentAmountCents",
      {min: 1},
    );
    const chargesAmountCents = requireInt(
      data.chargesAmountCents ?? 0,
      "chargesAmountCents",
      {min: 0},
    );
    const paymentMethod = requireString(data.paymentMethod, "paymentMethod");
    if (!PAYMENT_METHODS.has(paymentMethod)) {
      throw new HttpsError("invalid-argument", "invalid paymentMethod");
    }
    const notes = optionalString(data.notes, "notes");
    const reference = optionalString(data.reference, "reference");

    const db = admin.firestore();
    const leaseRef = db.doc(`leases/${leaseId}`);
    const paymentRef = db.collection("payments").doc();

    return await db.runTransaction(async (tx) => {
      const leaseSnap = await tx.get(leaseRef);
      const lease = dataOrFail(leaseSnap, "lease not found");
      assertOwnedAndActive(lease, uid, "lease");

      const now = admin.firestore.FieldValue.serverTimestamp();
      tx.set(paymentRef, {
        id: paymentRef.id,
        landlordId: uid,
        leaseId,
        propertyName: lease.propertyName,
        tenantLastName: lease.tenantLastName,
        periodStart,
        periodEnd,
        paidAt,
        rentAmountCents,
        chargesAmountCents,
        paymentMethod,
        notes,
        reference,
        createdAt: now,
        updatedAt: now,
        deletedAt: null,
      });

      return {paymentId: paymentRef.id};
    });
  },
);

// ============================================================================
// updatePayment — champs mutables uniquement
// ============================================================================
const PAYMENT_MUTABLE_FIELDS = new Set([
  "paidAt",
  "paymentMethod",
  "notes",
  "reference",
]);

export const updatePayment = onCall(
  {region: "europe-west1"},
  async (request) => {
    const uid = requireAuthUid(request);
    const data = asBag(request.data);
    const id = requireString(data.id, "id");
    const patch = asBag(data.patch);

    const cleanPatch: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(patch)) {
      if (!PAYMENT_MUTABLE_FIELDS.has(k)) {
        throw new HttpsError(
          "invalid-argument",
          `field ${k} immutable/unknown`,
        );
      }
      if (k === "paidAt") {
        cleanPatch[k] = toTimestamp(v, "paidAt");
      } else {
        cleanPatch[k] = v;
      }
    }
    if (cleanPatch.paymentMethod !== undefined) {
      if (
        typeof cleanPatch.paymentMethod !== "string" ||
        !PAYMENT_METHODS.has(cleanPatch.paymentMethod)
      ) {
        throw new HttpsError("invalid-argument", "invalid paymentMethod");
      }
    }

    const db = admin.firestore();
    const ref = db.doc(`payments/${id}`);
    const snap = await ref.get();
    const p = dataOrFail(snap, "payment not found");
    assertOwnedAndActive(p, uid, "payment");

    await ref.update({
      ...cleanPatch,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {updated: true};
  },
);
