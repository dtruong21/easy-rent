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
 * Pour chaque landlord expiré, on relit d'abord l'utilisateur Auth : s'il
 * porte un fournisseur lié (`providerData` non vide — email/Google/Apple),
 * c'est un compte déjà upgradé (ex. `finalizeAnonymousUpgrade` interrompu
 * après le `link` mais avant `isAnonymous: false`) et il est IGNORÉ sans rien
 * toucher. Sinon :
 *   (a) supprime l'utilisateur Firebase Auth (`admin.auth().deleteUser`)
 *   (b) supprime les objets Storage `documents/{uid}/**` (OWASP-04)
 *   (c) supprime les `investment_scenarios` où `landlordId == uid`
 *   (d) supprime `paid_plan_interest/{uid}` si présent
 *   (e) supprime `landlords/{uid}`
 *
 * Batch de 100 max par run (tient large dans les quotas Blaze — 540k
 * invocations/jour gratuites — et limite le risque de timeout sur un run
 * avec beaucoup d'expirés d'un coup). Un run qui traite exactement 100
 * landlords laissera le reste pour le run du lendemain — acceptable : ce
 * sont des comptes sans activité depuis >14 jours, un délai de purge
 * supplémentaire d'un jour n'a aucun impact utilisateur ni RGPD (l'anonyme
 * n'a jamais donné de consentement à conserver, mais rien n'impose non plus
 * une purge à la milliseconde près).
 *
 * `timeoutSeconds: 300` : chaque compte liste/supprime en plus des objets
 * GCS ; 100 comptes dépassent largement les 60 s par défaut.
 */

import * as admin from "firebase-admin";
import {Timestamp} from "firebase-admin/firestore";
import {logger} from "firebase-functions/v2";
import {onSchedule} from "firebase-functions/v2/scheduler";

const BATCH_SIZE = 100;

export const cleanupExpiredAnon = onSchedule(
  {
    schedule: "0 3 * * *",
    timeZone: "Europe/Paris",
    region: "europe-west1",
    timeoutSeconds: 300,
  },
  async () => {
    await cleanupExpiredAnonImpl(admin.firestore(), Timestamp.now());
  },
);

/**
 * Logique pure, testable avec le FakeFirestore (convention repo — cf.
 * `purgeExpiredReceiptsImpl`). Retourne le décompte purgés / en échec ; les
 * comptes ignorés car déjà liés (cf. `purgeLandlord`) ne comptent dans aucun
 * des deux, ils sont seulement journalisés.
 */
export async function cleanupExpiredAnonImpl(
  db: admin.firestore.Firestore,
  now: Timestamp,
): Promise<{purged: number; failed: number}> {
  const expiredSnap = await db
    .collection("landlords")
    .where("isAnonymous", "==", true)
    .where("anonExpiresAt", "<=", now)
    .limit(BATCH_SIZE)
    .get();

  if (expiredSnap.empty) {
    logger.info("cleanupExpiredAnon: no expired anonymous landlords");
    return {purged: 0, failed: 0};
  }

  logger.info(
    `cleanupExpiredAnon: purging ${expiredSnap.size} expired anonymous landlords`,
  );

  let purged = 0;
  let failed = 0;
  let skipped = 0;

  for (const doc of expiredSnap.docs) {
    const uid = doc.id;
    try {
      const outcome = await purgeLandlord(db, uid);
      if (outcome === "skipped") {
        skipped++;
      } else {
        purged++;
      }
    } catch (err) {
      failed++;
      logger.error(`cleanupExpiredAnon: failed to purge uid=${uid}`, err);
    }
  }

  logger.info(
    `cleanupExpiredAnon: done (purged=${purged}, failed=${failed}, ` +
      `skipped=${skipped})`,
  );
  return {purged, failed};
}

function errorCode(err: unknown): unknown {
  return typeof err === "object" && err !== null && "code" in err ?
    (err as {code: unknown}).code :
    undefined;
}

async function purgeLandlord(
  db: admin.firestore.Firestore,
  uid: string,
): Promise<"purged" | "skipped"> {
  // (0) garde-fou : ne JAMAIS purger un compte qui n'est plus anonyme.
  // `landlords.isAnonymous` peut être périmé : si `finalizeAnonymousUpgrade`
  // échoue après avoir lié l'email/Google au compte Auth, le doc garde
  // `isAnonymous: true` + `anonExpiresAt` expiré alors que l'utilisateur est
  // devenu un vrai compte — supprimer Auth + Storage + Firestore détruirait
  // ses données. Une relecture Auth (source de vérité) tranche.
  //   - `auth/user-not-found` : Auth déjà supprimé (run précédent interrompu
  //     plus loin) → on continue pour terminer Storage + Firestore.
  //   - `providerData` non vide : compte lié → on ignore, rien n'est touché.
  //   - autre erreur : on remonte, échec par compte comme pour `deleteUser`
  //     (journalisé par l'appelant, retentative au prochain run).
  let authUserExists = true;
  try {
    const user = await admin.auth().getUser(uid);
    if (user.providerData.length > 0) {
      logger.warn(
        `cleanupExpiredAnon: skipping uid=${uid} — account is linked ` +
          "(non-empty providerData), no longer anonymous",
      );
      return "skipped";
    }
  } catch (err) {
    if (errorCode(err) !== "auth/user-not-found") {
      throw err;
    }
    authUserExists = false;
    logger.info(
      `cleanupExpiredAnon: Auth user uid=${uid} not found, ` +
        "proceeding with Storage + Firestore cleanup",
    );
  }

  // Ordre CRITIQUE : Auth SUPPRIMÉ EN PREMIER, Firestore ENSUITE.
  //
  // Si on nettoie Firestore d'abord et que `admin.auth().deleteUser` échoue,
  // le compte Auth reste orphelin — le prochain run du cron ne le voit
  // plus car la query s'appuie sur `landlords where isAnonymous=true` qui
  // vient d'être vidé. En supprimant Auth d'abord, un échec laisse
  // Firestore intact et le prochain run retrouvera + retentera.
  //
  // (a) suppression du compte Firebase Auth (sauté si `getUser` vient de
  // confirmer qu'il n'existe plus). Idempotent : un 'user-not-found' tardif
  // (course avec une autre suppression) est aussi toléré.
  if (authUserExists) {
    try {
      await admin.auth().deleteUser(uid);
    } catch (err) {
      if (errorCode(err) === "auth/user-not-found") {
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
  }

  // (b) fichiers Storage `documents/{uid}/**` (OWASP-04). Même style que
  // l'étape (d) de `deleteAccount`. Le `/` final est indispensable : sans lui
  // le préfixe `documents/anon-1` purgerait aussi `documents/anon-10/…`.
  //
  // AVANT la suppression du doc landlord (e) : si le bucket est indisponible
  // l'erreur remonte, le doc landlord — la clé de découverte de ce cron — reste
  // en place et le run suivant retente (Auth, déjà supprimé, renverra
  // `user-not-found`, toléré plus haut). Les anonymes n'ont plus le droit
  // d'écrire dans Storage ; ces objets sont ceux déposés avant le durcissement
  // des règles.
  await admin.storage().bucket().deleteFiles({prefix: `documents/${uid}/`});

  // (c) scénarios simulateur du landlord.
  const scenariosSnap = await db
    .collection("investment_scenarios")
    .where("landlordId", "==", uid)
    .get();
  const batch = db.batch();
  for (const scenarioDoc of scenariosSnap.docs) {
    batch.delete(scenarioDoc.ref);
  }

  // (d) intérêt Plan Pro, si présent.
  batch.delete(db.doc(`paid_plan_interest/${uid}`));

  // (e) doc landlord lui-même.
  batch.delete(db.doc(`landlords/${uid}`));

  await batch.commit();

  // Audit RGPD art. 30 (registre des traitements) — log par UID des
  // suppressions réussies pour tracer les purges automatiques.
  logger.info(`cleanupExpiredAnon: purged expired anon uid=${uid}`);
  return "purged";
}
