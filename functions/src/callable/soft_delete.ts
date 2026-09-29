/**
 * softDeleteEntity — callable unique pour le soft-delete protégé.
 *
 * Mime les RPC Postgres `soft_delete_property/tenant/lease/payment/document/...`
 * qui posaient `deleted_at = NOW()` via SECURITY DEFINER avec gardes métier.
 *
 * Couvre toutes les collections soft-deletables. Les Security Rules
 * interdisent l'écriture directe de `deletedAt` côté client (pas dans
 * preservesImmutables) — donc c'est le seul chemin.
 *
 * Gardes :
 *   - properties / tenants : refuse si activeLeaseCount > 0 (RESTRICT)
 *   - documents : refuse si legalHold = true (rétention légale)
 *   - leases : autorisé (les payments restent visibles) ; si le bail était
 *     ACTIF, décrémente le activeLeaseCount du bien ET du locataire parents.
 *
 * FEAT-044 : soft-delete d'un bien / locataire / bail ACTIF décrémente aussi
 * (clampé à 0) le compteur de plan correspondant du bailleur
 * (activePropertiesCount / activeTenantsCount / activeLeasesCount).
 *   - landlords : suppression de compte → cascade gérée séparément (RGPD)
 *   - investment_scenarios : autorisé
 *   - expenses : autorisé, aucune garde métier propre (FEAT-041a). Le
 *     justificatif lié (`documentId`) sous `legalHold` reste protégé de
 *     son côté — soft-delete d'une dépense n'efface pas son document.
 *   - receipts, payments : refuse (immuables ou via flow dédié)
 *
 * Idempotent : si `deletedAt` est déjà non-null, retourne {alreadyDeleted: true}.
 *
 * **Nettoyage Storage (documents)** : le soft-delete d'un document SANS
 * `legalHold` supprime aussi l'objet Storage — ici, côté serveur. Le client
 * ne peut PAS le faire : `storage.rules` pose `allow update, delete: if false`
 * sur `documents/{landlordId}/**`. Tant que ce nettoyage vivait dans
 * `documents_repository.dart`, il échouait donc silencieusement et chaque
 * document supprimé laissait son fichier dans le bucket — coût facturé, et
 * surtout trou RGPD sur le droit à l'effacement. L'Admin SDK, lui, outrepasse
 * les Storage Rules. Cf. `resolveRealSize()` dans documents.ts pour le même
 * pattern côté création.
 */

import {FieldValue} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {
  asBag,
  dataOrFail,
  requireAuthUid,
  requireString,
} from "../utils/callable_helpers";
import {dbForRequest} from "../utils/db_router";
import {deleteStorageObject} from "../utils/storage_cleanup";

const SOFT_DELETABLE: ReadonlySet<string> = new Set([
  "properties",
  "tenants",
  "leases",
  "documents",
  "investment_scenarios",
  "expenses",
]);

export const softDeleteEntity = onCall(
  {region: "europe-west1"},
  async (request) => {
    const uid = requireAuthUid(request);
    const data = asBag(request.data);

    const collection = requireString(data.collection, "collection");
    const id = requireString(data.id, "id");

    if (!SOFT_DELETABLE.has(collection)) {
      throw new HttpsError(
        "invalid-argument",
        `collection ${collection} is not soft-deletable via this callable`,
      );
    }

    const db = await dbForRequest(request);
    const ref = db.doc(`${collection}/${id}`);

    // La purge Storage est un effet de BORD : elle ne peut pas vivre dans la
    // transaction (rejouable, et non transactionnelle de toute façon). La
    // transaction se contente donc de remonter le chemin à purger ; l'appel
    // Storage a lieu après le commit.
    const {alreadyDeleted, purgePath} = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const doc = dataOrFail(snap, `${collection}/${id} not found`);

      if (doc.landlordId !== uid) {
        throw new HttpsError(
          "permission-denied",
          "not owner of this resource",
        );
      }

      // Calculé AVANT le court-circuit d'idempotence ci-dessous : un second
      // appel sur un document déjà soft-deleted doit pouvoir RATTRAPER une
      // purge qui avait échoué au premier passage. Sans ça, un échec Storage
      // transitoire stranderait le fichier définitivement.
      // `legalHold` = rétention légale → le fichier doit SURVIVRE, on ne purge
      // jamais (le garde ci-dessous refuse déjà le soft-delete, sauf si le doc
      // était déjà supprimé avant que le legalHold soit posé).
      const rawPath = doc.storagePath;
      const purgePath =
        collection === "documents" &&
        doc.legalHold !== true &&
        typeof rawPath === "string" &&
        rawPath !== "" ?
          rawPath :
          null;

      if (doc.deletedAt != null) {
        return {alreadyDeleted: true, purgePath};
      }

      if (collection === "properties" || collection === "tenants") {
        const count =
          typeof doc.activeLeaseCount === "number" ? doc.activeLeaseCount : 0;
        if (count > 0) {
          throw new HttpsError(
            "failed-precondition",
            `${collection.slice(0, -1)}_has_active_leases`,
          );
        }
      }

      if (collection === "documents" && doc.legalHold === true) {
        throw new HttpsError(
          "failed-precondition",
          "document_under_legal_hold",
        );
      }

      // FEAT-044 : pré-lecture des compteurs du bailleur AVANT toute écriture
      // (Firestore impose reads-before-writes en transaction) — permet de
      // clamper les décréments à 0 plus bas. Chargé dès que le soft-delete
      // libère un slot de plafond : bien, locataire, ou bail ACTIF.
      const freesLandlordSlot =
        collection === "properties" ||
        collection === "tenants" ||
        (collection === "leases" && doc.status === "active");
      let landlordData: Record<string, unknown> = {};
      if (freesLandlordSlot) {
        const lsnap = await tx.get(db.doc(`landlords/${uid}`));
        landlordData = (lsnap.data() ?? {}) as Record<string, unknown>;
      }

      tx.update(ref, {
        deletedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });

      // Soft-delete d'un bail ACTIF : décrémenter le activeLeaseCount
      // dénormalisé du bien ET du locataire parents (miroir exact de
      // l'incrément de createLease / updateLease). Sans ça, le compteur reste
      // gonflé → le bien/locataire devient indéfiniment non-supprimable (garde
      // RESTRICT ci-dessus). Un bail terminé/archivé a déjà été décrémenté lors
      // de sa transition de status (updateLease) : on ne touche qu'aux ACTIFS.
      // Idempotent : le court-circuit `deletedAt != null` ci-dessus empêche
      // tout double décompte sur un second appel.
      if (collection === "leases" && doc.status === "active") {
        const propertyId = doc.propertyId;
        const tenantId = doc.tenantId;
        if (typeof propertyId === "string" && typeof tenantId === "string") {
          tx.update(db.doc(`properties/${propertyId}`), {
            activeLeaseCount: FieldValue.increment(-1),
          });
          tx.update(db.doc(`tenants/${tenantId}`), {
            activeLeaseCount: FieldValue.increment(-1),
          });
        }
      }

      // FEAT-044 : soft-delete d'un bien / locataire / bail actif → libère le
      // slot correspondant du plafond free-tier (miroir des incréments de
      // createProperty / createTenant / createLease). Décrément CLAMPÉ à 0 :
      // on écrit la valeur relue en transaction moins 1, seulement si elle est
      // > 0 — jamais de valeur négative (qui rouvrirait le gate). Compteur
      // absent (compte legacy) → on ne touche à rien : le prochain create le
      // sèmera via recompte. `uid` = propriétaire (vérifié plus haut).
      // Idempotent via le court-circuit `deletedAt != null` ci-dessus.
      const landlordCounterField =
        collection === "properties" ?
          "activePropertiesCount" :
          collection === "tenants" ?
            "activeTenantsCount" :
            collection === "leases" && doc.status === "active" ?
              "activeLeasesCount" :
              null;
      if (landlordCounterField !== null) {
        const cur = landlordData[landlordCounterField];
        if (typeof cur === "number" && cur > 0) {
          tx.update(db.doc(`landlords/${uid}`), {
            [landlordCounterField]: cur - 1,
          });
        }
      }

      return {alreadyDeleted: false, purgePath};
    });

    // Soft-delete Firestore committé. Le fichier peut maintenant partir.
    const storageDeleted =
      purgePath !== null ? await deleteStorageObject(purgePath, uid) : false;

    return {alreadyDeleted, storageDeleted};
  },
);
