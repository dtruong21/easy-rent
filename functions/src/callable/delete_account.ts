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
 * client), précédée d'une résiliation Stripe :
 *   (0) si le compte est facturé sur le WEB (Stripe), résilie IMMÉDIATEMENT
 *       (sans remboursement de la période en cours) son abonnement — sinon
 *       l'utilisateur continuerait d'être facturé pour un compte qui n'existe
 *       plus. « Facturé sur le web » se lit sur le doc landlord de la base
 *       routée ([hasWebBilling]) : un compte gratuit, ou abonné via un store
 *       (IAP, dont le store gère la résiliation), ou déjà purgé (relance) ne
 *       touche PAS Stripe — sa suppression ne dépend donc jamais de la config
 *       des secrets Stripe. Abonnement retrouvé par la metadata
 *       `rc_app_user_id` = uid (aucun identifiant Stripe fourni par le client).
 *       Clé Stripe choisie par la SEULE base routée ([resolveStripeKeyForDb]) :
 *       base `staging` → clé test, sinon clé live — l'Origin n'y joue aucun
 *       rôle (décision 2026-09-30 : l'allowlist d'Origin refusait l'URL
 *       Firebase Hosting de prod, page de suppression déclarée aux stores).
 *       Elle passe AVANT toute purge : si Stripe échoue, rien n'est supprimé,
 *       l'appel échoue en `internal` et l'utilisateur relance. Toute erreur de
 *       configuration (clé absente / de mauvais mode) est journalisée et
 *       renvoyée en `internal` — jamais en `failed-precondition`, que le client
 *       lit comme « reconnectez-vous ». Sautée sur l'émulateur Functions ;
 *   (a) marque les quittances `receipts` du landlord — CONSERVÉES 5 ans
 *       (loi n° 89-462 du 6 juillet 1989 ; docs/LEGAL.md « droit à
 *       l'effacement ») : stamp `accountDeletedAt` + `retentionUntil`
 *       pour la purge différée. Inaccessibles dès la suppression du compte :
 *       `get` ET `list` sont owner-scoped dans firestore.rules (audit
 *       FEAT-045) et l'UID ne résout plus pour personne ;
 *   (b) supprime TOUTES les autres collections du landlord (properties,
 *       tenants, leases, payments, documents — y compris legalHold : le
 *       flux client avertit de télécharger avant —, expenses,
 *       investment_scenarios, support_requests, charge_statements,
 *       etat_des_lieux) par pages de 400 ;
 *   (c) supprime les singletons landlords/{uid} + paid_plan_interest/{uid} ;
 *   (d) purge Storage `documents/{uid}/**` (seul préfixe Storage du produit :
 *       les PDF de décomptes de charges et d'états des lieux sont rendus côté
 *       client, aucun fichier serveur à purger pour eux) ;
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
import {defineSecret} from "firebase-functions/params";
import {logger} from "firebase-functions/v2";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import Stripe from "stripe";

import {
  assertRecentAuthForNonAnonymousAccount,
  requireAuthUid,
} from "../utils/callable_helpers";
import {dbForRequest, STAGING_DATABASE_ID} from "../utils/db_router";
import {resolveStripeKeyForDb} from "../utils/stripe_env";

import {RC_APP_USER_ID_METADATA_KEY} from "./create_checkout_session";
import {assertSafeUid, CANCELABLE_STATUSES} from "./manage_subscription";

/** Clé secrète Stripe live (serveur uniquement) — secret déjà utilisé ailleurs. */
const stripeSecret = defineSecret("STRIPE_SECRET_KEY");

/** Clé secrète Stripe TEST — servie aux comptes staging (issue #138). */
const stripeTestSecret = defineSecret("STRIPE_SECRET_KEY_TEST");

/**
 * Valeur de `proStore` / `entitlements.<palier>.store` écrite par le webhook
 * RevenueCat pour un abonnement Stripe / RC Billing (`storeOf` dans
 * `http/revenuecat_webhook.ts` : STRIPE, RC_BILLING → « web »). Un test
 * verrouille la parité avec `storeOf`.
 */
const WEB_STORE = "web";

/**
 * PURE — le compte est-il (ou a-t-il été) facturé par Stripe ?
 *
 * Deux sources, écrites par le SEUL écrivain du droit (le webhook RevenueCat) :
 *   - `proStore`, miroir du palier effectif : « web » tant qu'un palier web est
 *     actif ;
 *   - la map `entitlements` : les états EXPIRÉS y sont conservés (`store: "web"`
 *     inclus) alors que `proStore` redevient null. Un abonnement web expiré côté
 *     droit peut pourtant encore exister chez Stripe (past_due / unpaid) et
 *     facturer : on regarde donc TOUS les paliers, actifs ou non.
 *
 * Doc absent (relance après une suppression menée à terme) → `false`. Forme
 * inattendue → `false`, jamais d'exception : un doc atypique ne doit pas
 * bloquer la suppression.
 */
export function hasWebBilling(
  landlord: Record<string, unknown> | null | undefined,
): boolean {
  if (landlord === null || landlord === undefined) return false;
  if (landlord.proStore === WEB_STORE) return true;

  const entitlements = landlord.entitlements;
  if (typeof entitlements !== "object" || entitlements === null) return false;
  return Object.values(entitlements).some(
    (state) =>
      typeof state === "object" &&
      state !== null &&
      (state as {store?: unknown}).store === WEB_STORE,
  );
}

/** Rétention légale des quittances : 5 ans (loi 6 juillet 1989 / art. 2224). */
const RECEIPT_RETENTION_MS = 5 * 365.25 * 24 * 60 * 60 * 1000;

/**
 * Collections purgées par requête `landlordId == uid`.
 * `receipts` est volontairement ABSENTE (rétention légale, cf. docblock).
 *
 * Toute collection exportée par `exportAccountData` doit figurer ici OU dans
 * [RETAINED_COLLECTIONS] : un test de parité (delete_account.test.ts) l'impose,
 * pour qu'une future collection ne survive pas silencieusement à la
 * suppression du compte (RGPD art. 17, OWASP-05).
 */
export const PURGED_COLLECTIONS: readonly string[] = [
  "properties",
  "tenants",
  "leases",
  "payments",
  "documents",
  "expenses",
  "investment_scenarios",
  "support_requests",
  // Documents figés (noms, adresses, relevés) : aucune rétention légale ne les
  // couvre côté plateforme (le cron de purge ne lit que `receipts`) — sans
  // hard-delete ici ils survivraient indéfiniment (OWASP-05).
  "charge_statements",
  "etat_des_lieux",
];

/**
 * Collections volontairement CONSERVÉES après la suppression du compte
 * (rétention légale, stampées par [stampRetainedReceipts]). Liste explicite
 * plutôt qu'une absence : le test de parité distingue ainsi « retenue » de
 * « oubliée ».
 */
export const RETAINED_COLLECTIONS: readonly string[] = ["receipts"];

/** Pages de purge — sous la limite Firestore de 500 writes par batch. */
const PURGE_PAGE_SIZE = 400;

export const deleteAccount = onCall(
  {
    region: "europe-west1",
    timeoutSeconds: 300,
    secrets: [stripeSecret, stripeTestSecret],
  },
  async (request) => {
    // OWASP-02 — EXEMPTÉE de `requireVerifiedUid` (volontairement) : le droit à
    // l'effacement (RGPD art. 17) doit rester exerçable par un compte jamais
    // vérifié (ex. inscrit avec l'adresse d'un tiers). Garde de fraîcheur
    // ci-dessous inchangée.
    const uid = requireAuthUid(request);

    // AUDIT FEAT-045 (M1) : le claim `sign_in_provider == 'anonymous'` reste
    // porté par les tokens émis AVANT un linkWithCredential/Provider (upgrade
    // d'essai anonyme → compte complet) — il ne prouve donc PAS que le compte
    // est toujours anonyme. Pour ne pas exempter de la garde de fraîcheur un
    // compte upgradé (qui contient de vraies données), on confirme l'état
    // AUTORITATIF côté Admin SDK : anonyme ⇔ aucun provider lié.
    await assertRecentAuthForNonAnonymousAccount(request, uid);

    const db = await dbForRequest(request);

    // (0) Résiliation Stripe — AVANT toute purge, hors du try/catch de purge :
    // un échec ici ne doit rien avoir supprimé (l'utilisateur relance).
    await cancelStripeSubscriptions(db, uid);

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
 * Résilie immédiatement (sans remboursement) tous les abonnements Stripe
 * gérables d'un compte facturé sur le web. Étape (0) de la suppression : lève
 * AVANT toute purge.
 *
 * - Portée : uniquement si le doc landlord de la base routée montre une
 *   facturation web ([hasWebBilling]) — lu AVANT de construire Stripe ou de
 *   résoudre la clé, pour que la suppression d'un compte gratuit/store ne
 *   dépende jamais de la configuration des secrets Stripe.
 * - Clé : par la SEULE base routée ([resolveStripeKeyForDb]), jamais par
 *   l'Origin — `staging` → test, sinon live.
 * - Recherche par metadata `rc_app_user_id` = uid : le client ne fournit jamais
 *   d'identifiant Stripe, donc ne peut viser l'abonnement d'autrui.
 * - Erreurs : TOUTES journalisées. Le client mappe chaque `failed-precondition`
 *   de deleteAccount sur « session trop ancienne, reconnectez-vous » : une
 *   erreur de configuration serveur (clé absente / de mauvais mode) est donc
 *   renvoyée en `internal`. Seul `invalid-argument` (uid malformé) garde son
 *   code. Le journal ne porte que l'uid, le code et le message des HttpsError —
 *   constantes sans matériel de clé — ou, pour toute autre erreur, son nom et
 *   type/code/statut/requestId (jamais son message).
 */
async function cancelStripeSubscriptions(
  db: admin.firestore.Firestore,
  uid: string,
): Promise<void> {
  if (process.env.FUNCTIONS_EMULATOR === "true") {
    logger.info(
      `deleteAccount: Stripe cancellation skipped on emulator (uid=${uid})`,
    );
    return;
  }

  // Lecture Firestore séparée de l'appel Stripe : son échec doit se lire comme
  // tel dans les journaux, pas comme une résiliation Stripe ratée.
  let landlord: Record<string, unknown> | undefined;
  try {
    landlord = (await db.doc(`landlords/${uid}`).get()).data();
  } catch (err) {
    logger.error(
      `deleteAccount: billing lookup failed for uid=${uid}`,
      describeError(err),
    );
    throw new HttpsError("internal", "billing lookup failed — retry");
  }
  if (!hasWebBilling(landlord)) {
    logger.info(
      `deleteAccount: no web billing, Stripe not called (uid=${uid})`,
    );
    return;
  }

  try {
    // Défense en profondeur avant l'interpolation de l'uid dans la requête de
    // recherche Stripe (même garde que manageSubscription).
    assertSafeUid(uid);

    const stripe = new Stripe(
      resolveStripeKeyForDb(
        db.databaseId === STAGING_DATABASE_ID,
        stripeSecret.value(),
        stripeTestSecret.value(),
      ),
    );

    const search = await stripe.subscriptions.search({
      query: `metadata['${RC_APP_USER_ID_METADATA_KEY}']:'${uid}'`,
      limit: 20,
    });

    let cancelled = 0;
    for (const sub of search.data) {
      if (!CANCELABLE_STATUSES.has(sub.status)) continue;
      // Effet immédiat, sans prorata ni facture finale : aucun remboursement.
      await stripe.subscriptions.cancel(sub.id);
      cancelled++;
    }
    logger.info(
      `deleteAccount: cancelled ${cancelled} Stripe subscription(s) ` +
        `for uid=${uid}`,
    );
  } catch (err) {
    if (err instanceof HttpsError) {
      logger.error(
        `deleteAccount: Stripe step rejected for uid=${uid} ` +
          `(${err.code}: ${err.message})`,
      );
      // `failed-precondition` = « reconnectez-vous » côté app ; ici c'est
      // toujours une erreur de configuration serveur (clé absente / de mauvais
      // mode).
      if (err.code === "failed-precondition") {
        throw new HttpsError("internal", "subscription cancel failed — retry");
      }
      throw err;
    }
    // Ni message ni objet d'erreur brut : une erreur Stripe peut citer un
    // fragment de clé (« Invalid API Key provided: sk_live_****abcd »). Le
    // nom/type/code/statut suffisent à retrouver l'appel via le request id.
    logger.error(
      `deleteAccount: Stripe cancellation failed for uid=${uid}`,
      describeError(err),
    );
    throw new HttpsError("internal", "subscription cancel failed — retry");
  }
}

/**
 * Champs non sensibles d'une erreur, pour le journal : son `name` (classe —
 * seul repère d'une erreur non-Stripe, ex. `TypeError`) et, pour une erreur
 * Stripe, type/code/statut/requestId. JAMAIS `message`, qui peut citer un
 * fragment de clé.
 */
function describeError(err: unknown): Record<string, unknown> {
  if (typeof err !== "object" || err === null) return {};
  const e = err as {
    name?: unknown;
    type?: unknown;
    code?: unknown;
    statusCode?: unknown;
    requestId?: unknown;
  };
  return {
    name: e.name,
    type: e.type,
    code: e.code,
    statusCode: e.statusCode,
    requestId: e.requestId,
  };
}

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
