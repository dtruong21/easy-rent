/**
 * purgeExpiredReceipts — cron quotidien qui purge les quittances archivées
 * dont l'échéance de rétention est passée (RGPD art. 5.1.e — limitation de la
 * conservation).
 *
 * À la suppression d'un compte (FEAT-045), `deleteAccount` CONSERVE les
 * quittances 5 ans et pose sur chacune `retentionUntil` (= suppression + 5 ans)
 * via `stampRetainedReceipts`. Ce cron exécute la purge promise à l'échéance.
 *
 * Base `(default)` via `admin.firestore()` direct : les crons sont l'exception
 * documentée à l'isolation ADR 0003 (pas de `request` porteur d'Origin, donc
 * pas de `dbForRequest`). Même patron que `cleanupExpiredAnon`.
 *
 * Sécurité : seules les quittances d'un compte supprimé portent
 * `retentionUntil`. Une quittance de compte actif n'a pas le champ et n'est
 * jamais retournée par `where("retentionUntil", "<=", now)`.
 *
 * Idempotent : supprimer un doc déjà parti est un no-op ; un run borné par
 * MAX_DELETES_PER_RUN laisse le reste au lendemain (horizon 5 ans, sans enjeu).
 */

import * as admin from "firebase-admin";
import {Timestamp} from "firebase-admin/firestore";
import {logger} from "firebase-functions/v2";
import {onSchedule} from "firebase-functions/v2/scheduler";

type Firestore = admin.firestore.Firestore;

const PAGE_SIZE = 400;
const MAX_DELETES_PER_RUN = 2000; // 5 pages — large devant tout volume réaliste

/**
 * Logique pure, testable avec le FakeFirestore (convention repo — cf.
 * reconcileExpiredEntitlements). Retourne le nombre de quittances purgées.
 */
export async function purgeExpiredReceiptsImpl(
  db: Firestore,
  now: Timestamp,
): Promise<number> {
  let purged = 0;

  while (purged < MAX_DELETES_PER_RUN) {
    const snap = await db
      .collection("receipts")
      .where("retentionUntil", "<=", now)
      .limit(PAGE_SIZE)
      .get();

    if (snap.empty) break;

    const batch = db.batch();
    for (const doc of snap.docs) batch.delete(doc.ref);
    await batch.commit();
    purged += snap.size;

    if (snap.size < PAGE_SIZE) break; // dernière page
  }

  if (purged === 0) {
    logger.info("purgeExpiredReceipts: no expired receipts");
  } else {
    logger.info(`purgeExpiredReceipts: purged ${purged} expired receipts`);
  }
  return purged;
}

export const purgeExpiredReceipts = onSchedule(
  {schedule: "0 3 * * *", timeZone: "Europe/Paris", region: "europe-west1"},
  async () => {
    await purgeExpiredReceiptsImpl(
      admin.firestore(),
      Timestamp.now(),
    );
  },
);
