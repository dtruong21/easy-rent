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
 *   - leases : autorisé (les payments restent visibles)
 *   - landlords : suppression de compte → cascade gérée séparément (RGPD)
 *   - investment_scenarios : autorisé
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

      tx.update(ref, {
        deletedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return {alreadyDeleted: false};
    });
  },
);
