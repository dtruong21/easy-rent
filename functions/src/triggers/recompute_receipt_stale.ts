/**
 * recomputeReceiptStale — trigger sur payments.
 *
 * Réplique du trigger Postgres `tr_03_set_receipt_stale_on_payment_archive`
 * qui (sur UPDATE OF deleted_at sur payments) recalculait `receipts.is_stale`
 * pour toutes les quittances référençant ce paiement.
 *
 * Règle métier : une quittance est `isStale=true` ssi ≥ 1 paiement parmi
 * `paymentIds` a `deletedAt != null`. Indispensable pour l'audit (loi 1989) :
 * une quittance émise sur un paiement ensuite annulé est révisée.
 *
 * Trigger : onDocumentUpdated payments/{id}. On déclenche le recompute
 * uniquement quand `deletedAt` change (true → false ou false → true).
 */

import * as admin from "firebase-admin";
import {logger} from "firebase-functions/v2";
import {onDocumentUpdated} from "firebase-functions/v2/firestore";

function toMillisOrNull(t: unknown): number | null {
  if (t == null) return null;
  if (typeof (t as {toMillis?: () => number})?.toMillis === "function") {
    return (t as {toMillis: () => number}).toMillis();
  }
  return null;
}

export const recomputeReceiptStale = onDocumentUpdated(
  {document: "payments/{paymentId}", region: "europe-west1"},
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;

    const beforeDel = toMillisOrNull(before.deletedAt);
    const afterDel = toMillisOrNull(after.deletedAt);

    // Pas de changement de soft-delete → rien à faire.
    if ((beforeDel == null) === (afterDel == null)) return;

    const paymentId = event.params.paymentId;
    const db = admin.firestore();

    const affected = await db
      .collection("receipts")
      .where("paymentIds", "array-contains", paymentId)
      .get();

    if (affected.empty) return;

    // Pour chaque receipt impactée, recalcule isStale en lisant tous ses payments.
    const tasks = affected.docs.map(async (receipt) => {
      const paymentIds = (receipt.data().paymentIds as string[]) ?? [];
      if (paymentIds.length === 0) return;

      const paymentSnaps = await db.getAll(
        ...paymentIds.map((pid) => db.doc(`payments/${pid}`)),
      );
      const anyDeleted = paymentSnaps.some(
        (s) => s.exists && s.data()?.deletedAt != null,
      );
      if (receipt.data().isStale === anyDeleted) return;

      await receipt.ref.update({isStale: anyDeleted});
      logger.info("receipt isStale updated", {
        receiptId: receipt.id,
        isStale: anyDeleted,
      });
    });

    await Promise.all(tasks);
  },
);
