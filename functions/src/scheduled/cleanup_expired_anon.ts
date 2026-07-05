/**
 * cleanupExpiredAnon — cron quotidien qui purge les comptes anonymes expirés.
 *
 * BAILLAN-M1 : les sessions Firebase Anonymous Auth expirent après 14 jours
 * glissants d'inactivité (`landlords.anonExpiresAt`, renouvelé côté client à
 * chaque activité meaningful — cf. `anon_expiry_renewer.dart`). Ce cron
 * découvre les comptes qui n'ont eu AUCUNE activité depuis leur expiration
 * et les supprime intégralement (Auth + Firestore).
 *
 * Déclenchement : Cloud Scheduler, tous les jours à 03:00 Europe/Paris —
 * heure creuse, hors fenêtre d'usage typique d'un bailleur FR.
 *
 * Pour chaque landlord expiré :
 *   (a) supprime les `investment_scenarios` où `landlordId == uid`
 *   (b) supprime `paid_plan_interest/{uid}` si présent
 *   (c) supprime `landlords/{uid}`
 *   (d) supprime l'utilisateur Firebase Auth (`admin.auth().deleteUser`)
 *
 * Batch de 100 max par run (tient large dans les quotas Blaze — 540k
 * invocations/jour gratuites — et limite le risque de timeout sur un run
 * avec beaucoup d'expirés d'un coup). Un run qui traite exactement 100
 * landlords laissera le reste pour le run du lendemain — acceptable : ce
 * sont des comptes sans activité depuis >14 jours, un délai de purge
 * supplémentaire d'un jour n'a aucun impact utilisateur ni RGPD (l'anonyme
 * n'a jamais donné de consentement à conserver, mais rien n'impose non plus
 * une purge à la milliseconde près).
 */

import * as admin from "firebase-admin";
import {logger} from "firebase-functions/v2";
import {onSchedule} from "firebase-functions/v2/scheduler";

const BATCH_SIZE = 100;

export const cleanupExpiredAnon = onSchedule(
  {
    schedule: "0 3 * * *",
    timeZone: "Europe/Paris",
    region: "europe-west1",
  },
  async () => {
    const db = admin.firestore();
    const now = admin.firestore.Timestamp.now();

    const expiredSnap = await db
      .collection("landlords")
      .where("isAnonymous", "==", true)
      .where("anonExpiresAt", "<=", now)
      .limit(BATCH_SIZE)
      .get();

    if (expiredSnap.empty) {
      logger.info("cleanupExpiredAnon: no expired anonymous landlords");
      return;
    }

    logger.info(
      `cleanupExpiredAnon: purging ${expiredSnap.size} expired anonymous landlords`,
    );

    let purged = 0;
    let failed = 0;

    for (const doc of expiredSnap.docs) {
      const uid = doc.id;
      try {
        await purgeLandlord(db, uid);
        purged++;
      } catch (err) {
        failed++;
        logger.error(`cleanupExpiredAnon: failed to purge uid=${uid}`, err);
      }
    }

    logger.info(`cleanupExpiredAnon: done (purged=${purged}, failed=${failed})`);
  },
);

async function purgeLandlord(
  db: admin.firestore.Firestore,
  uid: string,
): Promise<void> {
  // Ordre CRITIQUE : Auth SUPPRIMÉ EN PREMIER, Firestore ENSUITE.
  //
  // Si on nettoie Firestore d'abord et que `admin.auth().deleteUser` échoue,
  // le compte Auth reste orphelin — le prochain run du cron ne le voit
  // plus car la query s'appuie sur `landlords where isAnonymous=true` qui
  // vient d'être vidé. En supprimant Auth d'abord, un échec laisse
  // Firestore intact et le prochain run retrouvera + retentera.
  //
  // (a) suppression du compte Firebase Auth. Idempotent : un
  // 'user-not-found' signifie qu'il a déjà été supprimé — on continue
  // vers le nettoyage Firestore.
  try {
    await admin.auth().deleteUser(uid);
  } catch (err) {
    const code =
      typeof err === "object" && err !== null && "code" in err
        ? (err as {code: unknown}).code
        : undefined;
    if (code === "auth/user-not-found") {
      logger.info(
        `cleanupExpiredAnon: Auth user uid=${uid} already deleted, ` +
          "proceeding with Firestore cleanup",
      );
    } else {
      // Vrai échec : on abort — le cron retentera au prochain run car les
      // docs Firestore restent (isAnonymous=true, anonExpiresAt<now).
      logger.error(
        `cleanupExpiredAnon: deleteUser failed for uid=${uid} — ` +
          "aborting Firestore cleanup for retry next run",
        err,
      );
      throw err;
    }
  }

  // (b) scénarios simulateur du landlord.
  const scenariosSnap = await db
    .collection("investment_scenarios")
    .where("landlordId", "==", uid)
    .get();
  const batch = db.batch();
  for (const scenarioDoc of scenariosSnap.docs) {
    batch.delete(scenarioDoc.ref);
  }

  // (c) intérêt Plan Pro, si présent.
  batch.delete(db.doc(`paid_plan_interest/${uid}`));

  // (d) doc landlord lui-même.
  batch.delete(db.doc(`landlords/${uid}`));

  await batch.commit();

  // Audit RGPD art. 30 (registre des traitements) — log par UID des
  // suppressions réussies pour tracer les purges automatiques.
  logger.info(`cleanupExpiredAnon: purged expired anon uid=${uid}`);
}
