/**
 * generateReceipt / voidReceipt / markReceiptAsSent — callables.
 *
 * Réplique de l'Edge Function Supabase `generate-receipt` + des RPC
 * `void_receipt()` et `mark_receipt_as_sent()`. Garde la même surface API
 * et les mêmes invariants loi 6 juillet 1989 :
 *   - receipt immutable une fois créé (Rules `update,delete: if false`)
 *   - voiding non destructif (flags `isVoided` + `voidedAt` + `voidedReason`)
 *   - sent_at idempotent — overwrite autorisé sur un même email
 *
 * Cost-minimisation :
 *   - memory: 256 MiB (pdf-lib pure JS, ~30 MiB peak)
 *   - concurrency: 80 (multiplexing pour amortir le cold start)
 *   - PDF stocké dans le bucket Firebase Storage par défaut, path
 *     `receipts/{landlordId}/{receiptId}.pdf` — règles Storage interdisent
 *     la lecture par d'autres landlords.
 */

import * as admin from "firebase-admin";
import {logger} from "firebase-functions/v2";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {computeDocumentType, generateReceiptPdf} from "../pdf/layout";
import type {DocumentType} from "../pdf/layout";
import {
  asBag,
  dataOrFail,
  optionalString,
  optionalTimestamp,
  requireAuthUid,
  requireString,
} from "../utils/callable_helpers";

const PDF_URL_EXPIRY_SECONDS = 5 * 60; // 5 minutes

interface LeaseShape {
  landlordId: string;
  rentAmountCents: number;
  chargesAmountCents: number;
  propertyName: string;
  propertyAddress: string;
  tenantFirstName: string;
  tenantLastName: string;
  deletedAt: unknown;
}

interface PaymentShape {
  id: string;
  landlordId: string;
  leaseId: string;
  rentAmountCents: number;
  chargesAmountCents: number;
  periodStart: admin.firestore.Timestamp;
  periodEnd: admin.firestore.Timestamp;
  paidAt: admin.firestore.Timestamp;
  deletedAt: unknown;
}

function asLease(data: Record<string, unknown>): LeaseShape {
  return {
    landlordId: String(data.landlordId ?? ""),
    rentAmountCents: Number(data.rentAmountCents ?? 0),
    chargesAmountCents: Number(data.chargesAmountCents ?? 0),
    propertyName: String(data.propertyName ?? ""),
    propertyAddress: String(data.propertyAddress ?? ""),
    tenantFirstName: String(data.tenantFirstName ?? ""),
    tenantLastName: String(data.tenantLastName ?? ""),
    deletedAt: data.deletedAt,
  };
}

function asPayment(
  id: string,
  data: Record<string, unknown>,
): PaymentShape {
  return {
    id,
    landlordId: String(data.landlordId ?? ""),
    leaseId: String(data.leaseId ?? ""),
    rentAmountCents: Number(data.rentAmountCents ?? 0),
    chargesAmountCents: Number(data.chargesAmountCents ?? 0),
    periodStart: data.periodStart as admin.firestore.Timestamp,
    periodEnd: data.periodEnd as admin.firestore.Timestamp,
    paidAt: data.paidAt as admin.firestore.Timestamp,
    deletedAt: data.deletedAt,
  };
}

function isoDateUtc(ts: admin.firestore.Timestamp): string {
  return ts.toDate().toISOString().slice(0, 10);
}

// ============================================================================
// generateReceipt
// ============================================================================
export const generateReceipt = onCall(
  {region: "europe-west1", memory: "256MiB", concurrency: 80},
  async (request) => {
    const uid = requireAuthUid(request);
    const data = asBag(request.data);

    const leaseId = requireString(data.leaseId, "leaseId");
    const explicitPaymentIds = Array.isArray(data.paymentIds)
      ? data.paymentIds.map((v, i) => requireString(v, `paymentIds[${i}]`))
      : null;
    const periodStart = optionalTimestamp(data.periodStart, "periodStart");
    const periodEnd = optionalTimestamp(data.periodEnd, "periodEnd");

    const hasExplicit = explicitPaymentIds !== null;
    const hasPeriod = periodStart !== null && periodEnd !== null;
    if (hasExplicit && hasPeriod) {
      throw new HttpsError(
        "invalid-argument",
        "provide either paymentIds or (periodStart + periodEnd), not both",
      );
    }
    if (!hasExplicit && !hasPeriod) {
      throw new HttpsError(
        "invalid-argument",
        "provide either paymentIds or (periodStart + periodEnd)",
      );
    }
    if (
      periodStart !== null &&
      periodEnd !== null &&
      periodEnd.toMillis() <= periodStart.toMillis()
    ) {
      throw new HttpsError(
        "invalid-argument",
        "periodEnd must be after periodStart",
      );
    }

    const db = admin.firestore();

    // 1. Load landlord (for legal fields fullName + address)
    const landlordSnap = await db.doc(`landlords/${uid}`).get();
    const landlordData = dataOrFail(landlordSnap, "landlord not found");
    const landlordFullName = String(landlordData.fullName ?? "").trim();
    const landlordAddress = String(landlordData.address ?? "").trim();
    const missing: string[] = [];
    if (landlordFullName.length === 0) missing.push("fullName");
    if (landlordAddress.length === 0) missing.push("address");
    if (missing.length > 0) {
      throw new HttpsError(
        "failed-precondition",
        "profile_incomplete",
        {missing},
      );
    }

    // 2. Load lease + ownership
    const leaseSnap = await db.doc(`leases/${leaseId}`).get();
    const lease = asLease(dataOrFail(leaseSnap, "lease not found"));
    if (lease.landlordId !== uid) {
      throw new HttpsError("permission-denied", "lease not owned");
    }
    if (lease.deletedAt != null) {
      throw new HttpsError("failed-precondition", "lease is deleted");
    }

    // 3. Resolve payments (mode 1 ids OR mode 2 period range)
    let paymentDocs: PaymentShape[] = [];
    if (explicitPaymentIds !== null) {
      const refs = explicitPaymentIds.map((pid) => db.doc(`payments/${pid}`));
      const snaps = await db.getAll(...refs);
      for (const snap of snaps) {
        if (!snap.exists) {
          throw new HttpsError("not-found", "payment not found");
        }
        const p = asPayment(snap.id, snap.data() as Record<string, unknown>);
        if (p.landlordId !== uid || p.deletedAt != null) {
          throw new HttpsError(
            "permission-denied",
            "payment not owned or deleted",
          );
        }
        if (p.leaseId !== leaseId) {
          throw new HttpsError(
            "failed-precondition",
            "payments must belong to the same lease",
          );
        }
        paymentDocs.push(p);
      }
    } else if (periodStart !== null && periodEnd !== null) {
      const q = await db
        .collection("payments")
        .where("landlordId", "==", uid)
        .where("leaseId", "==", leaseId)
        .where("deletedAt", "==", null)
        .where("periodStart", ">=", periodStart)
        .where("periodStart", "<=", periodEnd)
        .get();
      if (q.empty) {
        throw new HttpsError(
          "failed-precondition",
          "no active payments found for this period",
        );
      }
      paymentDocs = q.docs.map((d) =>
        asPayment(d.id, d.data() as Record<string, unknown>),
      );
    }

    const firstPayment = paymentDocs[0];
    if (!firstPayment) {
      throw new HttpsError(
        "failed-precondition",
        "no active payments found for this receipt",
      );
    }

    // 4. Totals + period bounds + lastPaidAt
    let rentCents = 0;
    let chargesCents = 0;
    let lastPaidAtMs = 0;
    let earliestStart = firstPayment.periodStart;
    let latestEnd = firstPayment.periodEnd;

    for (const p of paymentDocs) {
      rentCents += p.rentAmountCents;
      chargesCents += p.chargesAmountCents;
      const paidMs = p.paidAt.toMillis();
      if (paidMs > lastPaidAtMs) lastPaidAtMs = paidMs;
      if (p.periodStart.toMillis() < earliestStart.toMillis()) {
        earliestStart = p.periodStart;
      }
      if (p.periodEnd.toMillis() > latestEnd.toMillis()) {
        latestEnd = p.periodEnd;
      }
    }
    const totalCents = rentCents + chargesCents;

    const documentType: DocumentType = computeDocumentType(
      totalCents,
      lease.rentAmountCents,
      lease.chargesAmountCents,
    );

    // 5. Generate PDF
    const receiptRef = db.collection("receipts").doc();
    const receiptId = receiptRef.id;
    const generatedAt = new Date();

    let pdfBytes: Uint8Array;
    try {
      pdfBytes = await generateReceiptPdf({
        receiptId,
        documentType,
        landlordFullName,
        landlordAddress,
        tenantFirstName: lease.tenantFirstName,
        tenantLastName: lease.tenantLastName,
        propertyAddress: lease.propertyAddress,
        periodStart: isoDateUtc(earliestStart),
        periodEnd: isoDateUtc(latestEnd),
        rentCents,
        chargesCents,
        totalCents,
        lastPaidAt: new Date(lastPaidAtMs).toISOString(),
        generatedAt,
      });
    } catch (err) {
      logger.error("generateReceiptPdf failed", {uid, receiptId, err});
      throw new HttpsError("internal", "pdf_generation_failed");
    }

    // 6. Upload to Storage
    const pdfPath = `receipts/${uid}/${receiptId}.pdf`;
    const bucket = admin.storage().bucket();
    try {
      await bucket.file(pdfPath).save(Buffer.from(pdfBytes), {
        contentType: "application/pdf",
        resumable: false,
        metadata: {
          metadata: {landlordId: uid, receiptId, documentType},
        },
      });
    } catch (err) {
      logger.error("storage upload failed", {uid, pdfPath, err});
      throw new HttpsError("internal", "storage_upload_failed");
    }

    // 7. Write receipt doc
    const paymentIds = paymentDocs.map((p) => p.id);
    const generatedAtTs = admin.firestore.Timestamp.fromDate(generatedAt);
    try {
      await receiptRef.set({
        id: receiptId,
        landlordId: uid,
        leaseId,
        paymentIds,
        propertyName: lease.propertyName,
        propertyAddress: lease.propertyAddress,
        landlordFullName,
        tenantFullName: `${lease.tenantFirstName} ${lease.tenantLastName}`,
        periodStart: earliestStart,
        periodEnd: latestEnd,
        rentCents,
        chargesCents,
        totalCents,
        documentType,
        pdfPath,
        generatedAt: generatedAtTs,
        createdAt: generatedAtTs,
        isVoided: false,
        voidedAt: null,
        voidedReason: null,
        isStale: false,
        sentAt: null,
        sentToEmail: null,
      });
    } catch (err) {
      logger.error("[orphan-pdf] receipt doc write failed", {
        uid,
        pdfPath,
        err,
      });
      throw new HttpsError("internal", "receipt_persist_failed");
    }

    // 8. Signed URL for immediate download
    const [pdfUrl] = await bucket.file(pdfPath).getSignedUrl({
      action: "read",
      expires: Date.now() + PDF_URL_EXPIRY_SECONDS * 1000,
    });
    const pdfUrlExpiresAt = new Date(
      Date.now() + PDF_URL_EXPIRY_SECONDS * 1000,
    ).toISOString();

    logger.info("receipt generated", {uid, receiptId, documentType, totalCents});

    return {
      receiptId,
      documentType,
      totalCents,
      pdfUrl,
      pdfUrlExpiresAt,
      periodStart: isoDateUtc(earliestStart),
      periodEnd: isoDateUtc(latestEnd),
    };
  },
);

// ============================================================================
// getReceiptPdfUrl — rafraîchit l'URL signée pour un receipt existant
// ============================================================================
export const getReceiptPdfUrl = onCall(
  {region: "europe-west1"},
  async (request) => {
    const uid = requireAuthUid(request);
    const data = asBag(request.data);
    const receiptId = requireString(data.receiptId, "receiptId");

    const db = admin.firestore();
    const ref = db.doc(`receipts/${receiptId}`);
    const snap = await ref.get();
    const r = dataOrFail(snap, "receipt not found");
    if (r.landlordId !== uid) {
      throw new HttpsError("permission-denied", "not owner");
    }
    const pdfPath = String(r.pdfPath ?? "");
    if (!pdfPath) {
      throw new HttpsError("internal", "receipt has no pdfPath");
    }

    const [pdfUrl] = await admin.storage().bucket().file(pdfPath).getSignedUrl({
      action: "read",
      expires: Date.now() + PDF_URL_EXPIRY_SECONDS * 1000,
    });
    return {
      pdfUrl,
      pdfUrlExpiresAt: new Date(
        Date.now() + PDF_URL_EXPIRY_SECONDS * 1000,
      ).toISOString(),
    };
  },
);

// ============================================================================
// voidReceipt
// ============================================================================
export const voidReceipt = onCall(
  {region: "europe-west1"},
  async (request) => {
    const uid = requireAuthUid(request);
    const data = asBag(request.data);
    const receiptId = requireString(data.receiptId, "receiptId");
    const reason = requireString(data.reason, "reason");

    const db = admin.firestore();
    const ref = db.doc(`receipts/${receiptId}`);

    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const r = dataOrFail(snap, "receipt not found");
      if (r.landlordId !== uid) {
        throw new HttpsError("permission-denied", "not owner");
      }
      if (r.isVoided === true) {
        return; // idempotent
      }
      tx.update(ref, {
        isVoided: true,
        voidedAt: admin.firestore.FieldValue.serverTimestamp(),
        voidedReason: reason,
      });
    });

    return {voided: true};
  },
);

// ============================================================================
// markReceiptAsSent
// ============================================================================
export const markReceiptAsSent = onCall(
  {region: "europe-west1"},
  async (request) => {
    const uid = requireAuthUid(request);
    const data = asBag(request.data);
    const receiptId = requireString(data.receiptId, "receiptId");
    const email = optionalString(data.email, "email");

    const db = admin.firestore();
    const ref = db.doc(`receipts/${receiptId}`);

    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const r = dataOrFail(snap, "receipt not found");
      if (r.landlordId !== uid) {
        throw new HttpsError("permission-denied", "not owner");
      }
      if (r.isVoided === true) {
        throw new HttpsError(
          "failed-precondition",
          "cannot mark a voided receipt as sent",
        );
      }
      tx.update(ref, {
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
        sentToEmail: email,
      });
    });

    return {marked: true};
  },
);
