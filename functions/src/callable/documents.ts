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
 *
 * v3 (durcissement taille) : le `sizeBytes` du payload n'est plus lu. La
 * taille persistée et plafonnée est celle lue sur l'objet Storage via
 * `getMetadata()` — cf. `resolveRealSize()` pour le raisonnement complet
 * (coût, divergence déclaré/réel, nettoyage de l'orphelin).
 */

import * as admin from "firebase-admin";
import {logger} from "firebase-functions/v2";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {
  asBag,
  dataOrFail,
  optionalString,
  requireAuthUid,
  requireString,
} from "../utils/callable_helpers";
import {dbForRequest} from "../utils/db_router";
import {deleteStorageObject} from "../utils/storage_cleanup";

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

/**
 * Lit la taille RÉELLE de l'objet Storage et applique le plafond.
 *
 * **Pourquoi** : le `sizeBytes` du payload est déclaré par le client et
 * n'engage que lui. Il est persisté tel quel dans Firestore et sommé côté
 * client (`DocumentsQuota.totalBytes`, seuil d'alerte 100 Mo) — un client
 * modifié pouvait donc fausser ce total. La taille réelle est la seule
 * source de vérité.
 *
 * **Coût : zéro aller-retour supplémentaire.** `getMetadata()` REMPLACE le
 * `exists()` qui était déjà fait ici — un 404 GCS vaut « pas d'objet », ce
 * qui est exactement le garde-fou anti-doc-fantôme d'avant. Même nombre
 * d'appels Storage qu'avant ce changement.
 *
 * **Divergence déclaré/réel : on accepte, sur la seule foi du réel.** On ne
 * refuse PAS un écart. Refuser n'apporterait aucune sécurité (le réel est
 * de toute façon la valeur contrôlée et persistée) mais transformerait tout
 * écart légitime — retry qui ré-uploade un objet légèrement différent,
 * transformation côté SDK — en échec dur sur un upload dont l'utilisateur a
 * DÉJÀ payé la bande passante. Le `sizeBytes` déclaré devient purement
 * indicatif : il est ignoré, jamais persisté.
 *
 * **Refus ⇒ l'objet est supprimé** par le `catch` de `createDocument`, qui
 * couvre tous les motifs de refus (pas seulement la taille) : sans ça on
 * laisserait des octets facturés sans document Firestore en face. Le
 * rollback client de `documents_repository.dart` ne peut pas le faire —
 * `storage.rules` interdit le `delete` client sur ce préfixe.
 *
 * Note : le plafond est DÉJÀ appliqué à l'upload par `storage.rules`
 * (`request.resource.size <= 10 MiB`), qui reste la première ligne de
 * défense. Ce contrôle est la ceinture qui double les bretelles — il rend
 * `sizeBytes` fiable et couvre le cas où les règles seraient mal déployées
 * (le bucket est partagé prod/staging et `storage.rules` n'est PAS déployé
 * par la CI — cf. ADR 0003).
 *
 * @returns la taille réelle en octets, à persister.
 */
async function resolveRealSize(
  storagePath: string,
  uid: string,
): Promise<number> {
  const file = admin.storage().bucket().file(storagePath);

  let rawSize: unknown;
  try {
    const [metadata] = await file.getMetadata();
    rawSize = metadata.size;
  } catch (err) {
    // 404 GCS = aucun objet à ce path → même refus qu'avant (doc fantôme).
    if ((err as {code?: unknown})?.code === 404) {
      throw new HttpsError(
        "failed-precondition",
        "no file at storagePath — upload first",
      );
    }
    logger.error("createDocument: getMetadata failed", {uid, storagePath, err});
    throw new HttpsError("internal", "storage_metadata_failed");
  }

  // GCS renvoie `size` en string (API JSON) ; on tolère aussi un number.
  const realSize = typeof rawSize === "string" ? Number(rawSize) : rawSize;
  if (typeof realSize !== "number" || !Number.isFinite(realSize)) {
    logger.error("createDocument: unreadable object size", {
      uid,
      storagePath,
      rawSize,
    });
    throw new HttpsError("internal", "storage_metadata_failed");
  }

  if (realSize < 1 || realSize > MAX_BYTES) {
    // L'objet orphelin est purgé par le `catch` de `createDocument`, qui
    // couvre TOUS les refus (pas seulement la taille) — cf. son commentaire.
    logger.warn("createDocument: object rejected on real size", {
      uid,
      storagePath,
      realSize,
      maxBytes: MAX_BYTES,
    });
    throw new HttpsError(
      "invalid-argument",
      realSize < 1 ? "document_empty" : "document_too_large",
    );
  }

  return realSize;
}

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
    // `data.sizeBytes` est volontairement IGNORÉ : la taille déclarée par le
    // client n'engage que lui. La valeur persistée vient de `resolveRealSize()`
    // (métadonnées Storage) plus bas. Le champ reste accepté dans le payload
    // pour rétrocompat — les clients déployés l'envoient encore.

    // Path doit commencer par documents/{uid}/ pour matcher les Storage Rules.
    const expectedPrefix = `documents/${uid}/`;
    if (!storagePath.startsWith(expectedPrefix)) {
      throw new HttpsError(
        "invalid-argument",
        `storagePath must be under ${expectedPrefix}`,
      );
    }

    const db = dbForRequest(request);

    // À partir d'ici, l'objet est DÉJÀ dans le bucket (le client uploade avant
    // d'appeler) et le préfixe `documents/{uid}/` est vérifié : tout refus doit
    // emporter l'objet avec lui, sinon on facture des octets qu'aucun document
    // Firestore ne référence — invisibles dans l'app, donc jamais nettoyés.
    //
    // Le client ne peut pas s'en charger (`storage.rules` lui interdit
    // `delete`), d'où ce rollback côté serveur qui couvre TOUS les refus :
    // quota, ownership lease/bien, taille, échec de persistance.
    //
    // Contrepartie assumée sur les erreurs transitoires (`internal`) : on
    // purge quand même. L'utilisateur devra re-uploader — ce que le client
    // fait déjà de toute façon, puisqu'il traite tout échec de `createDocument`
    // comme un échec d'upload complet. Mieux vaut ça qu'un orphelin silencieux.
    try {
      // Gating free/Pro AVANT tout travail coûteux (lookups cross-entity +
      // accès Storage) : un compte au plafond est refusé immédiatement.
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

      // Vérifie que le fichier est bien uploadé ET lit sa taille réelle (un
      // 404 vaut « doc fantôme »). Source de vérité du plafond de taille.
      const sizeBytes = await resolveRealSize(storagePath, uid);

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
    } catch (err) {
      // Best-effort et idempotent : le refus prime sur l'échec de purge.
      await deleteStorageObject(storagePath, uid);
      throw err;
    }
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
