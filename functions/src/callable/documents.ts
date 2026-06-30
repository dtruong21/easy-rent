/**
 * createDocument + getDocumentDownloadUrl — callables.
 *
 * Réplique des triggers Postgres `tr_00b_compute_legal_hold` (dérive
 * `legalHold` depuis `category`) et `tr_01b_protect_immutable_documents`
 * (5 colonnes immuables après création).
 *
 * Flow client :
 *   1. Client demande un upload URL signed (PUT) via Storage SDK direct,
 *      ou upload via le SDK Firebase Storage avec auth context (les Storage
 *      Rules autorisent l'écriture si uid == landlordId dans le path).
 *   2. Une fois l'upload réussi, le client appelle `createDocument` avec
 *      le `storagePath` et les métadonnées.
 *   3. Le callable valide lease ownership + calcule `legalHold` + écrit
 *      le doc Firestore.
 *
 * Path Storage : `documents/{landlordId}/{documentId}.{ext}` — règles
 * Storage interdisent la lecture/écriture par d'autres landlords.
 */

import * as admin from "firebase-admin";
import {logger} from "firebase-functions/v2";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {
  asBag,
  dataOrFail,
  requireAuthUid,
  requireInt,
  requireString,
} from "../utils/callable_helpers";

const ALLOWED_CATEGORIES = new Set([
  "bail_signe",
  "etat_des_lieux",
  "attestation_assurance",
  "quittance_scannee",
  "autre",
]);

// Catégories sous rétention légale 5 ans (loi 1989).
const LEGAL_HOLD_CATEGORIES = new Set(["bail_signe", "etat_des_lieux"]);

const ALLOWED_MIME = new Set([
  "application/pdf",
  "image/jpeg",
  "image/png",
  "image/webp",
]);

const MAX_BYTES = 10 * 1024 * 1024; // 10 MiB
const DOWNLOAD_URL_EXPIRY_SECONDS = 5 * 60;

// ============================================================================
// createDocument
// ============================================================================
export const createDocument = onCall(
  {region: "europe-west1"},
  async (request) => {
    const uid = requireAuthUid(request);
    const data = asBag(request.data);

    const leaseId = requireString(data.leaseId, "leaseId");
    const category = requireString(data.category, "category");
    if (!ALLOWED_CATEGORIES.has(category)) {
      throw new HttpsError("invalid-argument", `invalid category: ${category}`);
    }
    const filename = requireString(data.filename, "filename");
    const storagePath = requireString(data.storagePath, "storagePath");
    const mimeType = requireString(data.mimeType, "mimeType");
    if (!ALLOWED_MIME.has(mimeType)) {
      throw new HttpsError("invalid-argument", `invalid mimeType: ${mimeType}`);
    }
    const sizeBytes = requireInt(data.sizeBytes, "sizeBytes", {min: 1, max: MAX_BYTES});

    // Path doit commencer par documents/{uid}/ pour matcher les Storage Rules.
    const expectedPrefix = `documents/${uid}/`;
    if (!storagePath.startsWith(expectedPrefix)) {
      throw new HttpsError(
        "invalid-argument",
        `storagePath must be under ${expectedPrefix}`,
      );
    }

    const db = admin.firestore();

    // Validate lease ownership (cross-entity).
    const leaseSnap = await db.doc(`leases/${leaseId}`).get();
    const lease = dataOrFail(leaseSnap, "lease not found");
    if (lease.landlordId !== uid) {
      throw new HttpsError("permission-denied", "lease not owned");
    }
    if (lease.deletedAt != null) {
      throw new HttpsError("failed-precondition", "lease is deleted");
    }

    // Verify file actually uploaded (else client could register a phantom doc).
    const bucket = admin.storage().bucket();
    const [exists] = await bucket.file(storagePath).exists();
    if (!exists) {
      throw new HttpsError(
        "failed-precondition",
        "no file at storagePath — upload first",
      );
    }

    const legalHold = LEGAL_HOLD_CATEGORIES.has(category);

    const docRef = db.collection("documents").doc();
    const now = admin.firestore.FieldValue.serverTimestamp();
    try {
      await docRef.set({
        id: docRef.id,
        landlordId: uid,
        leaseId,
        category,
        filename,
        storagePath,
        mimeType,
        sizeBytes,
        legalHold,
        uploadedAt: now,
        createdAt: now,
        updatedAt: now,
        deletedAt: null,
      });
    } catch (err) {
      logger.error("createDocument failed", {uid, storagePath, err});
      throw new HttpsError("internal", "document_persist_failed");
    }

    return {documentId: docRef.id, legalHold};
  },
);

// ============================================================================
// getDocumentDownloadUrl — signed URL court-terme pour download
// ============================================================================
export const getDocumentDownloadUrl = onCall(
  {region: "europe-west1"},
  async (request) => {
    const uid = requireAuthUid(request);
    const data = asBag(request.data);
    const documentId = requireString(data.documentId, "documentId");

    const db = admin.firestore();
    const snap = await db.doc(`documents/${documentId}`).get();
    const doc = dataOrFail(snap, "document not found");
    if (doc.landlordId !== uid) {
      throw new HttpsError("permission-denied", "not owner");
    }
    if (doc.deletedAt != null) {
      throw new HttpsError("failed-precondition", "document is deleted");
    }
    const storagePath = String(doc.storagePath ?? "");
    if (!storagePath) {
      throw new HttpsError("internal", "document has no storagePath");
    }

    const [downloadUrl] = await admin
      .storage()
      .bucket()
      .file(storagePath)
      .getSignedUrl({
        action: "read",
        expires: Date.now() + DOWNLOAD_URL_EXPIRY_SECONDS * 1000,
      });

    return {
      downloadUrl,
      downloadUrlExpiresAt: new Date(
        Date.now() + DOWNLOAD_URL_EXPIRY_SECONDS * 1000,
      ).toISOString(),
    };
  },
);
