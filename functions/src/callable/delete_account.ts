/**
 * deleteAccount — suppression de compte in-app (FEAT-045, RGPD art. 17).
 *
 * Exigence bloquante des deux stores : Google Play (« Account deletion »,
 * answer 13327111) et App Store (guideline 5.1.1(v)). Le client (web/iOS/
 * Android) appelle cette callable APRÈS une réauthentification fraîche —
 * et, pour Sign in with Apple, après révocation du token côté client
 * (`revokeTokenWithAuthorizationCode`, exigée par Apple).
 *
 * Purge (Admin SDK — les Security Rules n'autorisent aucun hard-delete
 * client) :
 *   (a) marque les quittances `receipts` du landlord — CONSERVÉES 5 ans
 *       (loi n° 89-462 du 6 juillet 1989 ; docs/LEGAL.md « droit à
 *       l'effacement ») : stamp `accountDeletedAt` + `retentionUntil`
 *       pour la purge différée. Inaccessibles dès la suppression du compte :
 *       `get` ET `list` sont owner-scoped dans firestore.rules (audit
 *       FEAT-045) et l'UID ne résout plus pour personne ;
 *   (b) supprime TOUTES les autres collections du landlord (properties,
 *       tenants, leases, payments, documents — y compris legalHold : le
 *       flux client avertit de télécharger avant —, expenses,
 *       investment_scenarios, support_requests) par pages de 400 ;
 *   (c) supprime les singletons landlords/{uid} + paid_plan_interest/{uid} ;
 *   (d) purge Storage `documents/{uid}/**` ;
 *   (e) supprime le compte Firebase Auth EN DERNIER.
 *
 * Ordre inverse de cleanupExpiredAnon (Auth d'abord) : ici le retry est
 * porté par l'utilisateur encore connecté — si une étape échoue, son compte
 * Auth existe toujours et il peut relancer la suppression (idempotent).
 * Auth en premier l'enfermerait dehors avec des données orphelines.
 *
 * Garde anti-détournement de session : pour un compte non-anonyme, le token
 * doit provenir d'une (ré)authentification récente (`auth_time` < 5 min) —
 * même famille de garde que le `requires-recent-login` du SDK client pour
 * `User.delete()`. Un token volé « vieux » ne peut pas détruire le compte.
 * Les sessions anonymes en sont exemptées (aucun credential à re-présenter ;
 * leur `auth_time` date du jour de création de l'essai) — l'exemption est
 * confirmée par l'état Admin SDK (`providerData` vide), pas par le seul
 * claim `sign_in_provider`, qui reste « anonymous » sur les tokens émis
 * avant un upgrade par linking.
 */

import * as admin from "firebase-admin";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {logger} from "firebase-functions/v2";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {
  assertRecentAuthForNonAnonymousAccount,
  requireAuthUid,
} from "../utils/callable_helpers";
import {dbForRequest} from "../utils/db_router";


/** Rétention légale des quittances : 5 ans (loi 6 juillet 1989 / art. 2224). */
const RECEIPT_RETENTION_MS = 5 * 365.25 * 24 * 60 * 60 * 1000;

/**
 * Collections purgées par requête `landlordId == uid`.
 * `receipts` est volontairement ABSENTE (rétention légale, cf. docblock).
 */
const PURGED_COLLECTIONS: readonly string[] = [
  "properties",
  "tenants",
  "leases",
  "payments",
  "documents",
  "expenses",
  "investment_scenarios",
  "support_requests",
];

/** Pages de purge — sous la limite Firestore de 500 writes par batch. */
const PURGE_PAGE_SIZE = 400;

export const deleteAccount = onCall(
  {region: "europe-west1", timeoutSeconds: 300},
  async (request) => {
    const uid = requireAuthUid(request);

    // AUDIT FEAT-045 (M1) : le claim `sign_in_provider == 'anonymous'` reste
    // porté par les tokens émis AVANT un linkWithCredential/Provider (upgrade
    // d'essai anonyme → compte complet) — il ne prouve donc PAS que le compte
    // est toujours anonyme. Pour ne pas exempter de la garde de fraîcheur un
    // compte upgradé (qui contient de vraies données), on confirme l'état
    // AUTORITATIF côté Admin SDK : anonyme ⇔ aucun provider lié.
    await assertRecentAuthForNonAnonymousAccount(request, uid);

    const db = dbForRequest(request);

    try {
      // (a) Quittances : rétention légale — stamp, jamais delete.
      const receiptsRetained = await stampRetainedReceipts(db, uid);

      // (b) Purge paginée des collections du landlord.
      let purgedDocs = 0;
      for (const collection of PURGED_COLLECTIONS) {
        purgedDocs += await purgeCollectionByLandlord(db, collection, uid);
      }

      // (c) Singletons (delete idempotent, absent = no-op).
      const singletonBatch = db.batch();
      singletonBatch.delete(db.doc(`paid_plan_interest/${uid}`));
      singletonBatch.delete(db.doc(`landlords/${uid}`));
      await singletonBatch.commit();

      // (d) Fichiers Storage du landlord (documents uploadés).
      await admin
        .storage()
        .bucket()
        .deleteFiles({prefix: `documents/${uid}/`});

      // (e) Compte Firebase Auth EN DERNIER (cf. docblock). Idempotent :
      // 'user-not-found' = déjà supprimé lors d'un run précédent interrompu.
      try {
        await admin.auth().deleteUser(uid);
      } catch (err) {
        const code =
          typeof err === "object" && err !== null && "code" in err ?
            (err as {code: unknown}).code :
            undefined;
        if (code !== "auth/user-not-found") {
          throw err;
        }
      }

      // Audit RGPD art. 30 : trace des suppressions à la demande (aucune
      // donnée personnelle au-delà de l'UID, qui ne résout plus rien).
      logger.info(
        `deleteAccount: purged uid=${uid} ` +
          `(docs=${purgedDocs}, receiptsRetained=${receiptsRetained})`,
      );

      return {deleted: true, receiptsRetained};
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      logger.error(`deleteAccount: purge failed for uid=${uid}`, err);
      throw new HttpsError(
        "internal",
        "account purge failed — retry",
      );
    }
  },
);

/**
 * Marque les quittances du landlord comme archivées suite à la suppression
 * du compte : `accountDeletedAt` (traçabilité RGPD) + `retentionUntil`
 * (échéance de purge pour un futur cron — limitation de conservation,
 * RGPD art. 5.1.e). Retourne le nombre de quittances conservées.
 */
async function stampRetainedReceipts(
  db: admin.firestore.Firestore,
  uid: string,
): Promise<number> {
  const snap = await db
    .collection("receipts")
    .where("landlordId", "==", uid)
    .get();
  if (snap.empty) return 0;

  const accountDeletedAt = FieldValue.serverTimestamp();
  const retentionUntil = Timestamp.fromMillis(
    Date.now() + RECEIPT_RETENTION_MS,
  );

  const docs = snap.docs;
  for (let i = 0; i < docs.length; i += PURGE_PAGE_SIZE) {
    const batch = db.batch();
    for (const doc of docs.slice(i, i + PURGE_PAGE_SIZE)) {
      batch.update(doc.ref, {accountDeletedAt, retentionUntil});
    }
    await batch.commit();
  }
  return docs.length;
}

/**
 * Hard-delete paginé de tous les docs d'une collection appartenant au
 * landlord. Reboucle tant que la requête retourne des docs (les deletes
 * font sortir les docs des pages suivantes — pas de curseur nécessaire).
 */
async function purgeCollectionByLandlord(
  db: admin.firestore.Firestore,
  collection: string,
  uid: string,
): Promise<number> {
  let total = 0;
  for (;;) {
    const snap = await db
      .collection(collection)
      .where("landlordId", "==", uid)
      .limit(PURGE_PAGE_SIZE)
      .get();
    if (snap.empty) return total;

    const batch = db.batch();
    for (const doc of snap.docs) {
      batch.delete(doc.ref);
    }
    await batch.commit();
    total += snap.size;
  }
}
