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
 *   3. Le callable valide lease et/ou property ownership + calcule
 *      `legalHold` + écrit le doc Firestore.
 *
 * Path Storage : `documents/{landlordId}/{documentId}.{ext}` — règles
 * Storage interdisent la lecture/écriture par d'autres landlords.
 *
 * v2 (FEAT-041b, docs/plans/FEAT-041-depenses.md §g) : `leaseId` devient
 * optionnel et `propertyId` apparaît en alternative — une dépense (justificatif
 * `expense_receipt`) peut n'avoir aucun bail (décompte syndic reçu après un
 * départ locataire). Au moins un des deux est requis, appartenant à `uid` ;
 * si les deux sont fournis, `lease.propertyId == propertyId` est exigé.
 * Rétrocompat stricte : un appel avec `leaseId` seul suit exactement le
 * chemin de validation d'avant (tous les uploads de bail existants passent).
 */

import * as admin from "firebase-admin";
import {logger} from "firebase-functions/v2";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {
  asBag,
  dataOrFail,
  optionalString,
  requireAuthUid,
  requireInt,
  requireString,
} from "../utils/callable_helpers";
import {dbForRequest} from "../utils/db_router";


const ALLOWED_CATEGORIES = new Set([
  "bail_signe",
  "etat_des_lieux",
  "attestation_assurance",
  "quittance_scannee",
  "expense_receipt",
  "autre",
]);

// Catégories sous rétention légale 5 ans (loi 1989) / 10 ans (comptable,
// `expense_receipt` — justificatif de dépense, cf. docs/LEGAL.md).
const LEGAL_HOLD_CATEGORIES = new Set([
  "bail_signe",
  "etat_des_lieux",
  "expense_receipt",
]);

const ALLOWED_MIME = new Set([
  "application/pdf",
  "image/jpeg",
  "image/png",
  "image/webp",
]);

const MAX_BYTES = 10 * 1024 * 1024; // 10 MiB
const DOWNLOAD_URL_EXPIRY_SECONDS = 5 * 60;

// Plafond de documents ACTIFS en free — miroir de
// `SubscriptionTier.documentLimit` (lib/features/auth/domain/subscription_tier.dart).
const FREE_DOCUMENT_LIMIT = 10;

/**
 * Plafond du tier. `null` = illimité (paid). Tier inconnu/anonyme → 0
 * (le registre documentaire est réservé aux comptes complets).
 * Miroir de `limitForTier` dans property_tenant.ts.
 */
function limitForTier(tier: string, freeLimit: number): number | null {
  switch (tier) {
    case "paid":
      return null;
    case "free":
      return freeLimit;
    default:
      return 0;
  }
}

/**
 * Gating free/Pro du stockage documentaire (matrice free/Pro 2026-07-20) — le
 * stockage a un coût réel, donc le volume est plafonné en free.
 *
 * **Comptage live** (pas de compteur dénormalisé comme properties/tenants) :
 * le volume est borné (10 en free) et surtout le soft-delete est universel
 * (`softDeleteEntity`) — sans compteur, il n'y a rien à décrémenter donc
 * aucune dérive possible. L'UI empêche déjà l'upload au plafond ; ce gate est
 * la defense-in-depth et la SOURCE DE VÉRITÉ.
 */
async function assertDocumentQuota(
  db: admin.firestore.Firestore,
  uid: string,
): Promise<void> {
  const landlordSnap = await db.doc(`landlords/${uid}`).get();
  if (!landlordSnap.exists) {
    throw new HttpsError("not-found", "landlord not found");
  }
  const landlord = (landlordSnap.data() ?? {}) as Record<string, unknown>;
  const raw = landlord.subscriptionTier;
  const tier = typeof raw === "string" ? raw : "anonymous";
  const limit = limitForTier(tier, FREE_DOCUMENT_LIMIT);
  if (limit === null) return; // paid → illimité

  const agg = await db
    .collection("documents")
    .where("landlordId", "==", uid)
    .where("deletedAt", "==", null)
    .count()
    .get();
  if (agg.data().count >= limit) {
    throw new HttpsError("resource-exhausted", "document_limit_reached");
  }
}

// ============================================================================
// createDocument
// ============================================================================
export const createDocument = onCall(
  {region: "europe-west1"},
  async (request) => {
    const uid = requireAuthUid(request);
    const data = asBag(request.data);

    // v2 (FEAT-041b) : leaseId devient optionnel, propertyId apparaît en
    // alternative — une dépense peut n'avoir aucun bail (décompte syndic
    // reçu après un départ locataire). Au moins un des deux est requis.
    // Rétrocompat stricte : un appel avec leaseId seul suit exactement le
    // chemin de validation d'avant (ownership + non-deleted du bail).
    const leaseId = optionalString(data.leaseId, "leaseId");
    const propertyId = optionalString(data.propertyId, "propertyId");
    if (leaseId === null && propertyId === null) {
      throw new HttpsError(
        "invalid-argument",
        "at least one of leaseId or propertyId is required",
      );
    }
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

    const db = dbForRequest(request);

    // Gating free/Pro AVANT tout travail coûteux (lookups cross-entity + accès
    // Storage) : un compte au plafond est refusé immédiatement.
    await assertDocumentQuota(db, uid);

    // Validate lease ownership (cross-entity) — inchangé si leaseId fourni.
    if (leaseId !== null) {
      const leaseSnap = await db.doc(`leases/${leaseId}`).get();
      const lease = dataOrFail(leaseSnap, "lease not found");
      if (lease.landlordId !== uid) {
        throw new HttpsError("permission-denied", "lease not owned");
      }
      if (lease.deletedAt != null) {
        throw new HttpsError("failed-precondition", "lease is deleted");
      }
      // Si les deux sont fournis, la cohérence lease.propertyId == propertyId
      // est obligatoire (garde-fou cross-entity, pattern createExpense).
      if (propertyId !== null && lease.propertyId !== propertyId) {
        throw new HttpsError(
          "failed-precondition",
          "lease_property_mismatch",
        );
      }
    }

    // Validate property ownership (cross-entity) — nouveau chemin v2.
    if (propertyId !== null) {
      const propertySnap = await db.doc(`properties/${propertyId}`).get();
      const property = dataOrFail(propertySnap, "property not found");
      if (property.landlordId !== uid) {
        throw new HttpsError("permission-denied", "property not owned");
      }
      if (property.deletedAt != null) {
        throw new HttpsError("failed-precondition", "property is deleted");
      }
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
        propertyId,
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

    const db = dbForRequest(request);
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
