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
 *   - landlords : suppression de compte → cascade gérée séparément (RGPD)
 *   - investment_scenarios : autorisé
 *   - expenses : autorisé, aucune garde métier propre (FEAT-041a). Le
 *     justificatif lié (`documentId`) sous `legalHold` reste protégé de
 *     son côté — soft-delete d'une dépense n'efface pas son document.
 *   - receipts, payments : refuse (immuables ou via flow dédié)
 *
 * Idempotent : si `deletedAt` est déjà non-null, retourne {alreadyDeleted: true}.
 */

import * as admin from "firebase-admin";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {
  asBag,
  dataOrFail,
  requireAuthUid,
  requireString,
} from "../utils/callable_helpers";

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

    const db = admin.firestore();
    const ref = db.doc(`${collection}/${id}`);

    return await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const doc = dataOrFail(snap, `${collection}/${id} not found`);

      if (doc.landlordId !== uid) {
        throw new HttpsError(
          "permission-denied",
          "not owner of this resource",
        );
      }

      if (doc.deletedAt != null) {
        return {alreadyDeleted: true};
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

      // FEAT-044 : pré-lecture du compteur de biens du bailleur AVANT toute
      // écriture (Firestore impose reads-before-writes en transaction) — permet
      // de clamper le décrément à 0 plus bas. `null` = compteur absent (legacy).
      let landlordPropCount: number | null = null;
      if (collection === "properties") {
        const lsnap = await tx.get(db.doc(`landlords/${uid}`));
        const ldata = (lsnap.data() ?? {}) as Record<string, unknown>;
        landlordPropCount =
          typeof ldata.activePropertiesCount === "number" ?
            ldata.activePropertiesCount :
            null;
      }

      tx.update(ref, {
        deletedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
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
            activeLeaseCount: admin.firestore.FieldValue.increment(-1),
          });
          tx.update(db.doc(`tenants/${tenantId}`), {
            activeLeaseCount: admin.firestore.FieldValue.increment(-1),
          });
        }
      }

      // FEAT-044 : soft-delete d'un bien → libère un slot du plafond free-tier
      // (miroir de l'incrément de createProperty). Sans ça le compteur ne ferait
      // que croître et un free resterait bloqué après avoir archivé un bien.
      // Décrément CLAMPÉ à 0 : on écrit la valeur relue en transaction moins 1,
      // et seulement si elle est > 0 — jamais de valeur négative (qui rouvrirait
      // le gate). Compteur absent (compte legacy) → on ne touche à rien :
      // createProperty le sèmera correctement au prochain create via recompte.
      // `uid` = propriétaire (vérifié plus haut) = landlords/{uid}. Idempotent
      // via le court-circuit `deletedAt != null` ci-dessus.
      if (
        collection === "properties" &&
        landlordPropCount !== null &&
        landlordPropCount > 0
      ) {
        tx.update(db.doc(`landlords/${uid}`), {
          activePropertiesCount: landlordPropCount - 1,
        });
      }

      return {alreadyDeleted: false};
    });
  },
);
