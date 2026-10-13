/**
 * Lien compte Baillan ↔ client Stripe, et inventaire des abonnements Stripe
 * d'un compte (#207).
 *
 * Pourquoi un client Stripe par compte, enregistré côté serveur : la recherche
 * Stripe par metadata (Search API) est à **cohérence différée** — un abonnement
 * tout juste payé peut rester invisible plusieurs minutes. Une résiliation ou
 * une suppression de compte lancée dans cet intervalle ne trouvait rien, et le
 * client restait prélevé. La liste des abonnements **d'un client**
 * (`subscriptions.list`) est, elle, cohérente dès l'écriture.
 *
 * Frontière de sécurité : `stripe_customers/{uid}` n'est écrit que par
 * `createCheckoutSession` (Admin SDK), à partir de la réponse de Stripe, et
 * reste refusé à tout client par les Security Rules. Un utilisateur ne peut
 * donc pas y faire pointer son compte vers le client Stripe d'autrui.
 */

import type * as admin from "firebase-admin";
import {FieldValue} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import type Stripe from "stripe";

/**
 * Nom du champ metadata que RevenueCat lit pour lier l'abonnement Stripe à
 * l'App User ID (= UID Firebase). ⚠️ DOIT correspondre au champ configuré dans
 * le dashboard RevenueCat (intégration Stripe).
 */
export const RC_APP_USER_ID_METADATA_KEY = "rc_app_user_id";

/** Singleton par compte : `stripe_customers/{uid}` → `{customerId, createdAt}`. */
export const STRIPE_CUSTOMERS_COLLECTION = "stripe_customers";

/** Taille de page maximale des API Stripe de liste et de recherche. */
const PAGE_SIZE = 100;

/**
 * Défense en profondeur avant interpolation de l'UID dans la requête Stripe
 * Search : un UID Firebase est alphanumérique URL-safe, donc ne contient jamais
 * l'apostrophe qui casserait le littéral `'...'` de la query (seul métacaractère
 * dangereux). Tout UID hors de cette forme est rejeté — l'interpolation n'est
 * donc jamais injectable. Fonction pure exportée pour être testée : c'est la
 * garantie « injection impossible » qui repose dessus.
 */
export function assertSafeUid(uid: string): void {
  if (!/^[A-Za-z0-9_-]+$/.test(uid)) {
    throw new HttpsError("invalid-argument", "malformed uid");
  }
}

function customerIdOf(data: Record<string, unknown> | undefined): string | null {
  const id = data?.customerId;
  return typeof id === "string" && id.length > 0 ? id : null;
}

/** Client Stripe enregistré pour ce compte, ou `null` (jamais passé au paiement). */
export async function readStripeCustomerId(
  db: admin.firestore.Firestore,
  uid: string,
): Promise<string | null> {
  const snap = await db.doc(`${STRIPE_CUSTOMERS_COLLECTION}/${uid}`).get();
  return customerIdOf(snap.data());
}

/**
 * `true` si Stripe répond que l'objet visé n'existe pas (ou plus). Avec
 * `param`, exige en plus que l'erreur porte sur CE paramètre — pour ne pas
 * confondre un client supprimé avec un price mal configuré.
 */
export function isStripeResourceMissing(err: unknown, param?: string): boolean {
  if (typeof err !== "object" || err === null) return false;
  const e = err as {code?: unknown; param?: unknown};
  return (
    e.code === "resource_missing" && (param === undefined || e.param === param)
  );
}

/**
 * Rend le client Stripe du compte, en le créant à la première ouverture de
 * paiement. `staleCustomerId` : identifiant enregistré que Stripe ne connaît
 * plus (client supprimé depuis le tableau de bord) — il est alors remplacé.
 */
export async function ensureStripeCustomer(args: {
  db: admin.firestore.Firestore;
  stripe: Stripe;
  uid: string;
  email: string | null;
  staleCustomerId?: string;
}): Promise<string> {
  const {db, stripe, uid, email, staleCustomerId} = args;
  const ref = db.doc(`${STRIPE_CUSTOMERS_COLLECTION}/${uid}`);
  const usable = (data: Record<string, unknown> | undefined): string | null => {
    const id = customerIdOf(data);
    return id !== null && id !== staleCustomerId ? id : null;
  };

  const existing = usable((await ref.get()).data());
  if (existing !== null) {
    // Les reçus Stripe partent à l'adresse du client : y reporter l'email
    // courant du compte. Au mieux — un échec ne bloque pas l'achat.
    if (email) {
      await stripe.customers.update(existing, {email}).catch(() => undefined);
    }
    return existing;
  }

  const created = await stripe.customers.create({
    ...(email ? {email} : {}),
    metadata: {[RC_APP_USER_ID_METADATA_KEY]: uid},
  });
  // Deux ouvertures de paiement simultanées : le premier client enregistré
  // gagne, pour que toutes les sessions visent le même.
  const kept = await db.runTransaction(async (tx) => {
    const winner = usable((await tx.get(ref)).data());
    if (winner !== null) return winner;
    tx.set(ref, {
      customerId: created.id,
      createdAt: FieldValue.serverTimestamp(),
    });
    return created.id;
  });
  if (kept !== created.id) {
    // Client créé en trop : vide, mais il porte l'email — on ne le laisse pas
    // traîner chez Stripe. Au mieux.
    await stripe.customers.del(created.id).catch(() => undefined);
  }
  return kept;
}

/**
 * Ferme les sessions de paiement encore ouvertes du client. Une page Stripe
 * restée ouverte reste payable ~24 h : après la suppression du compte, elle
 * créerait un abonnement que plus personne ne pourrait résilier.
 *
 * À appeler AVANT [listSubscriptionsForUid] : une session payée entre-temps
 * n'est plus « ouverte », et son abonnement apparaît alors dans la liste.
 */
export async function expireOpenCheckoutSessions(
  stripe: Stripe,
  customerId: string,
): Promise<void> {
  let hasMore = true;
  while (hasMore) {
    let page: Stripe.ApiList<Stripe.Checkout.Session>;
    try {
      page = await stripe.checkout.sessions.list({
        customer: customerId,
        status: "open",
        limit: PAGE_SIZE,
      });
    } catch (err) {
      // Client supprimé côté Stripe : plus aucune session payable.
      if (isStripeResourceMissing(err)) return;
      throw err;
    }
    for (const session of page.data) {
      try {
        await stripe.checkout.sessions.expire(session.id);
      } catch (err) {
        // Payée ou expirée entre-temps : plus rien à fermer. Dans le doute
        // (relecture impossible, toujours ouverte), l'erreur remonte.
        const current = await stripe.checkout.sessions
          .retrieve(session.id)
          .catch(() => null);
        if (current === null || current.status === "open") throw err;
      }
    }
    // Une page vide ne fait plus avancer : on s'arrête, quoi que dise Stripe.
    hasMore = page.has_more === true && page.data.length > 0;
  }
}

/**
 * Tous les abonnements Stripe d'un compte, tous statuts confondus.
 *
 * - Par le client enregistré (`customerId`) : liste cohérente dès l'écriture.
 *   Un client supprimé côté Stripe ne porte plus d'abonnement : ignoré.
 * - Par la metadata `rc_app_user_id` (Search, cohérence différée) : filet pour
 *   les abonnements souscrits avant l'enregistrement du client.
 *
 * Les deux sources sont paginées jusqu'au bout et dédoublonnées. Pour un même
 * abonnement, la version de la liste fait foi : celle de la recherche peut
 * dater (un `cancel_at_period_end` périmé ferait croire une résiliation déjà
 * programmée).
 */
export async function listSubscriptionsForUid(
  stripe: Stripe,
  uid: string,
  customerId: string | null,
): Promise<Stripe.Subscription[]> {
  assertSafeUid(uid);
  const byId = new Map<string, Stripe.Subscription>();

  if (customerId !== null) {
    try {
      let startingAfter: string | undefined;
      do {
        const page = await stripe.subscriptions.list({
          customer: customerId,
          status: "all",
          limit: PAGE_SIZE,
          ...(startingAfter === undefined ? {} : {starting_after: startingAfter}),
        });
        for (const sub of page.data) byId.set(sub.id, sub);
        startingAfter = page.has_more ? page.data.at(-1)?.id : undefined;
      } while (startingAfter !== undefined);
    } catch (err) {
      // Seul un CLIENT introuvable est toléré ; un curseur de pagination
      // introuvable donnerait une liste partielle.
      if (
        !isStripeResourceMissing(err) ||
        isStripeResourceMissing(err, "starting_after")
      ) {
        throw err;
      }
    }
  }

  let nextPage: string | undefined;
  do {
    const page = await stripe.subscriptions.search({
      query: `metadata['${RC_APP_USER_ID_METADATA_KEY}']:'${uid}'`,
      limit: PAGE_SIZE,
      ...(nextPage === undefined ? {} : {page: nextPage}),
    });
    for (const sub of page.data) {
      if (!byId.has(sub.id)) byId.set(sub.id, sub);
    }
    nextPage = page.has_more ? (page.next_page ?? undefined) : undefined;
  } while (nextPage !== undefined);

  return [...byId.values()];
}
