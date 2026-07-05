/**
 * setUpdatedAt — filet de sécurité pour le timestamp updatedAt.
 *
 * Réplique du trigger Postgres `set_updated_at` qui posait
 * `NEW.updated_at = NOW()` à chaque UPDATE. Côté Flutter on enverra
 * normalement `updatedAt: FieldValue.serverTimestamp()` sur tout write,
 * mais si un appel direct (admin SDK, console, migration data) oublie,
 * ce trigger rattrape.
 *
 * Anti-boucle infinie : on écrit serverTimestamp uniquement si
 * `after.updatedAt <= before.updatedAt` — quand le client a déjà posé
 * une nouvelle valeur, l'écart est ≥ 1 ms et on no-op.
 */

import * as admin from "firebase-admin";
import {logger} from "firebase-functions/v2";
import {onDocumentUpdated} from "firebase-functions/v2/firestore";

type Timestampish = {toMillis: () => number} | null | undefined;

function toMillis(t: unknown): number {
  if (
    t &&
    typeof (t as Timestampish)?.toMillis === "function"
  ) {
    return (t as {toMillis: () => number}).toMillis();
  }
  return 0;
}

export function makeSetUpdatedAt(collection: string) {
  return onDocumentUpdated(
    {document: `${collection}/{id}`, region: "europe-west1"},
    async (event) => {
      const change = event.data;
      if (!change) return;
      const before = change.before.data();
      const after = change.after.data();
      if (!before || !after) return;

      const beforeMs = toMillis(before.updatedAt);
      const afterMs = toMillis(after.updatedAt);

      // Le client a déjà avancé updatedAt → no-op (et coupe la boucle).
      if (afterMs > beforeMs) return;

      try {
        await change.after.ref.update({
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } catch (err) {
        logger.warn(`setUpdatedAt(${collection}) failed`, {
          id: event.params.id,
          err,
        });
      }
    },
  );
}

export const setUpdatedAtLandlords = makeSetUpdatedAt("landlords");
export const setUpdatedAtProperties = makeSetUpdatedAt("properties");
export const setUpdatedAtTenants = makeSetUpdatedAt("tenants");
export const setUpdatedAtLeases = makeSetUpdatedAt("leases");
export const setUpdatedAtPayments = makeSetUpdatedAt("payments");
export const setUpdatedAtDocuments = makeSetUpdatedAt("documents");
export const setUpdatedAtInvestmentScenarios = makeSetUpdatedAt(
  "investment_scenarios",
);
// Pas de setUpdatedAt pour receipts : champ updatedAt absent (immuable).
