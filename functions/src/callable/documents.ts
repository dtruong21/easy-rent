/**
 * createDocument + getDocumentDownloadUrl + updateDocumentCategory — callables.
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

import {errorCodeFor, quotaLimit, resolvePlan} from "../entitlements/plan";
import {minLevelForQuota} from "../entitlements/plan_matrix.generated";
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

const DOWNLOAD_URL_EXPIRY_SECONDS = 5 * 60;

/**
 * Lit la taille RÉELLE de l'objet Storage.
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

  if (realSize < 1) {
    // L'objet orphelin est purgé par le `catch` de `createDocument`, qui
    // couvre TOUS les refus (pas seulement la taille) — cf. son commentaire.
    logger.warn("createDocument: empty object rejected", {uid, storagePath});
    throw new HttpsError("invalid-argument", "document_empty");
  }

  // Le plafond HAUT n'est volontairement PLUS appliqué ici. Depuis FEAT-056 il
  // dépend du palier de l'appelant (`documentMaxBytes` : 10 Mio free et Pro,
  // 25 Mio Max, 50 Mio Ultra), donc il ne peut être tranché qu'avec la limite
  // renvoyée par `assertDocumentQuota` — voir `assertRealSizeWithinPlan`. Cette
  // fonction ne garde que le refus de FORME (objet vide), indépendant du palier.
  return realSize;
}

/**
 * Gating du stockage documentaire par palier — le stockage a un coût réel,
 * donc le volume est plafonné hors paliers payants.
 *
 * DEUX quotas indépendants sont appliqués ici, sur un SEUL read du doc
 * landlord :
 *   1. `documents` — NOMBRE de documents actifs (unit `count`) ;
 *   2. `documentMaxBytes` — TAILLE du fichier courant (unit `bytes`).
 * Les deux familles ne se comparent ni ne s'additionnent jamais (cf. `unit`
 * dans la table) : 50 documents et 10 Mio sont des grandeurs sans rapport.
 *
 * **Comptage live** pour le quota n°1 (pas de compteur dénormalisé comme
 * properties/tenants) : le volume est borné et surtout le soft-delete est
 * universel (`softDeleteEntity`) — sans compteur, il n'y a rien à décrémenter
 * donc aucune dérive possible. L'UI empêche déjà l'upload au plafond ; ce gate
 * est la defense-in-depth et la SOURCE DE VÉRITÉ.
 *
 * ORDRE des deux refus : le nombre d'abord. Un compte `anonymous` est plafonné
 * à 0 sur les DEUX quotas ; le refuser sur la taille lui répondrait
 * « fichier trop volumineux » là où le vrai motif est que le registre est
 * réservé aux comptes. Le motif le plus explicable prime sur la requête
 * d'agrégation économisée.
 *
 * FEAT-056 : les deux plafonds viennent de la table générée, résolus sur le
 * palier effectif (subscriptionTier + planLevel), plus d'une constante locale.
 *
 * Cette fonction applique le quota n°1 et RENVOIE le plafond n°2, qu'elle ne
 * peut pas appliquer elle-même : depuis la purge Storage (#156) la taille de
 * référence n'est plus celle que le client déclare mais celle que
 * `resolveRealSize()` lit dans le bucket, plus loin dans le flux. La renvoyer
 * évite un second read du doc landlord.
 *
 * @returns le plafond de taille en octets applicable à l'appelant (`null` =
 *          illimité), à passer à `assertRealSizeWithinPlan`.
 */
async function assertDocumentQuota(
  db: admin.firestore.Firestore,
  uid: string,
): Promise<number | null> {
  const landlordSnap = await db.doc(`landlords/${uid}`).get();
  if (!landlordSnap.exists) {
    throw new HttpsError("not-found", "landlord not found");
  }
  const landlord = (landlordSnap.data() ?? {}) as Record<string, unknown>;
  const plan = resolvePlan(landlord);

  // 1. Nombre de documents actifs.
  const countLimit = quotaLimit(plan, "documents");
  if (countLimit !== null) {
    const agg = await db
      .collection("documents")
      .where("landlordId", "==", uid)
      .where("deletedAt", "==", null)
      .count()
      .get();
    if (agg.data().count >= countLimit) {
      throw new HttpsError("resource-exhausted", errorCodeFor("documents"));
    }
  }

  // 2. Taille du fichier — résolue ici (un seul read landlord), appliquée plus
  // loin sur la taille RÉELLE lue dans Storage.
  return quotaLimit(plan, "documentMaxBytes");
}

/**
 * Applique le plafond de taille du palier à la taille RÉELLE de l'objet.
 *
 * Séparé de `assertDocumentQuota` parce que les deux valeurs n'arrivent pas au
 * même moment : le plafond vient du doc landlord (avant les lookups d'ownership),
 * la taille vient des métadonnées Storage (après). Pur et exporté, donc testable
 * sans Firestore ni bucket.
 *
 * `details` porte le plafond APPLICABLE À L'APPELANT et le plus petit palier qui
 * accepterait ce fichier, pour que le client compose un message utile sans
 * dupliquer la grille. `upgradeTo` vaut `null` quand aucun palier ne suffit — on
 * ne propose jamais une montée en gamme qui ne débloquerait rien.
 */
export function assertRealSizeWithinPlan(
  sizeBytes: number,
  byteLimit: number | null,
): void {
  if (byteLimit !== null && sizeBytes > byteLimit) {
    throw new HttpsError(
      "resource-exhausted",
      errorCodeFor("documentMaxBytes"),
      {
        limitBytes: byteLimit,
        sizeBytes,
        upgradeTo: minLevelForQuota("documentMaxBytes", sizeBytes),
      },
    );
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
    //
    // C'est aussi ce qui rend le plafond PAR PALIER de FEAT-056 réellement
    // contraignant : appliqué à une taille déclarée, un client modifié pouvait
    // annoncer 1 Ko et téléverser 40 Mio.

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
      // Gating par palier AVANT tout travail coûteux (lookups cross-entity +
      // accès Storage) : un compte au plafond est refusé immédiatement. Le
      // plafond de TAILLE est seulement résolu ici — il s'applique plus bas, à
      // la taille réelle de l'objet (FEAT-056 × purge Storage #156).
      const maxBytesForPlan = await assertDocumentQuota(db, uid);

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

      // Plafond de taille du palier, appliqué à la taille RÉELLE. Un refus ici
      // emporte l'objet avec lui via le `catch` ci-dessous.
      assertRealSizeWithinPlan(sizeBytes, maxBytesForPlan);

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

// ============================================================================
// updateDocumentCategory — reclasse un document (seule mutation autorisée
// après création ; les Rules bloquent tout update direct client).
//
// La `category` est le SEUL champ mutable d'un document (les 5 colonnes
// immuables de `tr_01b_protect_immutable_documents` — landlordId, storagePath,
// filename, mimeType, sizeBytes — restent figées). Recalcule `legalHold` depuis
// la nouvelle catégorie, comme `createDocument`.
//
// Garde-fou rétention : un document DÉJÀ sous `legalHold` (bail signé, état des
// lieux, justificatif de dépense) ne peut être reclassé — le sortir de sa
// catégorie protégée casserait la rétention légale (5 ans loi 1989 / 10 ans
// comptable). Même logique que `softDeleteEntity`, qui refuse la suppression
// d'un document sous `legalHold` (code `document_under_legal_hold`).
// ============================================================================
export const updateDocumentCategory = onCall(
  {region: "europe-west1"},
  async (request) => {
    const uid = requireAuthUid(request);
    const data = asBag(request.data);
    const documentId = requireString(data.documentId, "documentId");
    const category = requireString(data.category, "category");
    if (!ALLOWED_CATEGORIES.has(category)) {
      throw new HttpsError("invalid-argument", `invalid category: ${category}`);
    }

    const db = dbForRequest(request);
    const ref = db.doc(`documents/${documentId}`);
    const snap = await ref.get();
    const doc = dataOrFail(snap, "document not found");
    if (doc.landlordId !== uid) {
      throw new HttpsError("permission-denied", "not owner");
    }
    if (doc.deletedAt != null) {
      throw new HttpsError("failed-precondition", "document is deleted");
    }
    if (doc.legalHold === true) {
      throw new HttpsError("failed-precondition", "document_under_legal_hold");
    }

    const legalHold = LEGAL_HOLD_CATEGORIES.has(category);
    await ref.update({
      category,
      legalHold,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {documentId, category, legalHold};
  },
);
