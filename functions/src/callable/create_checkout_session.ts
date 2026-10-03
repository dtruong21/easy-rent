/**
 * createCheckoutSession — crée une Stripe Checkout Session pour un abonnement
 * Baillan sur le WEB (FEAT-044, ADR 0002 §Amendement 2026-07-20 ; élargi aux
 * trois paliers par FEAT-056 §4).
 *
 * Architecture « RevenueCat = plan de gestion » (approche A) :
 *   web → Stripe Checkout (cette fonction) → Stripe → RevenueCat (ingestion via
 *   compte connecté + External Purchase Tracking) → webhook `revenueCatWebhook`
 *   → landlords/{uid}.subscriptionTier + planLevel.
 *
 * Le LIEN vers le bon compte se fait par la **metadata** : l'App User ID
 * RevenueCat (= UID Firebase) est posé sur la Checkout Session **ET** sur la
 * subscription (`subscription_data.metadata`) — RevenueCat lit ce champ pour
 * associer l'abonnement Stripe au compte. Le nom du champ
 * ([RC_APP_USER_ID_METADATA_KEY]) DOIT correspondre EXACTEMENT à celui configuré
 * côté dashboard RevenueCat.
 *
 * Cette fonction ne fait qu' INITIER le paiement ; elle n'accorde aucun droit.
 * Le déverrouillage reste 100 % serveur-autoritaire via le webhook RevenueCat.
 */

import {defineSecret, defineString} from "firebase-functions/params";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import Stripe from "stripe";

import {resolvePlan} from "../entitlements/plan";
import {levelSpec, type LevelId} from "../entitlements/plan_matrix.generated";
import {
  isBillingPeriod,
  readPriceTable,
  resolvePriceIdOrThrow,
  type BillingPeriod,
  type PriceTable,
} from "../entitlements/stripe_prices";
import {asBag, requireVerifiedUid} from "../utils/callable_helpers";
import {dbForRequest} from "../utils/db_router";
import {resolveStripeKeyOrThrow, stripeEnvForOrigin} from "../utils/stripe_env";

/** Clé secrète Stripe LIVE (serveur uniquement) — servie aux origines prod. */
const stripeSecret = defineSecret("STRIPE_SECRET_KEY");

/**
 * Clé secrète Stripe TEST — servie au staging et à l'émulateur (issue #138).
 * Sans elle, un appel non-prod est refusé : il n'y a aucun repli sur la live.
 */
const stripeTestSecret = defineSecret("STRIPE_SECRET_KEY_TEST");

// Price IDs : plus de `defineString` local. Les six paramètres (3 paliers × 2
// périodicités) sont déclarés une seule fois dans `entitlements/stripe_prices`,
// à partir des noms portés par la table canonique — même registre que
// `manageSubscription/change_plan`, pour qu'un changement de palier ne puisse
// pas viser un price différent de celui vendu au checkout.

/** Base URL web pour les redirections success/cancel. */
const webAppBaseUrl = defineString("WEB_APP_BASE_URL", {
  default: "https://baillan.com",
});

/**
 * Nom du champ metadata que RevenueCat lit pour lier l'abonnement Stripe à
 * l'App User ID (= UID Firebase). ⚠️ DOIT correspondre au champ configuré dans
 * le dashboard RevenueCat (intégration Stripe).
 */
export const RC_APP_USER_ID_METADATA_KEY = "rc_app_user_id";

/**
 * Palier acheté, posé en metadata pour le support et le rapprochement
 * Stripe ↔ RevenueCat. **Jamais une source de vérité du droit** : le droit
 * vient exclusivement de l'entitlement RevenueCat (ADR 0002).
 */
export const PLAN_LEVEL_METADATA_KEY = "baillan_plan_level";

/** Offre visée : un palier commercial et une périodicité. */
export interface PlanSelection {
  readonly level: LevelId;
  readonly period: BillingPeriod;
}

export interface CheckoutConfig {
  /** Les six price IDs, indexés `${level}_${period}`. */
  readonly prices: PriceTable;
  readonly baseUrl: string;
}

/**
 * Palier visé par défaut quand la requête n'en nomme aucun. C'est la clé du
 * shim de rétrocompatibilité : avant FEAT-056, il n'existait qu'une offre
 * payante, et elle est devenue `pro` à l'identique (mêmes quotas, mêmes prix,
 * mêmes price IDs Stripe).
 */
const DEFAULT_LEVEL: LevelId = "pro";

/** Valide un id de palier reçu du client. */
function parseLevel(value: unknown): LevelId {
  const spec = typeof value === "string" ? levelSpec(value) : null;
  if (spec === null) {
    throw new HttpsError(
      "invalid-argument",
      "level doit valoir 'pro', 'max' ou 'ultra'",
    );
  }
  return spec.id;
}

/** Valide une périodicité reçue du client. */
function parsePeriod(value: unknown): BillingPeriod {
  if (!isBillingPeriod(value)) {
    throw new HttpsError(
      "invalid-argument",
      "period doit valoir 'monthly' ou 'annual'",
    );
  }
  return value;
}

/**
 * PURE — forme STRICTE de la sélection d'offre : `{level, period}`, les deux
 * obligatoires. Utilisée par les appels qui n'ont aucun client historique à
 * ménager (`manageSubscription/change_plan`).
 */
export function parsePlanSelection(data: Record<string, unknown>): PlanSelection {
  return {level: parseLevel(data.level), period: parsePeriod(data.period)};
}

/**
 * PURE — normalisation de la requête de checkout, **shim de
 * rétrocompatibilité inclus**.
 *
 * ```
 * { level: 'pro'|'max'|'ultra', period: 'monthly'|'annual' }   // nouvelle forme
 * { plan: 'monthly'|'annual' }  ==  { level: 'pro', period: <plan> }  // legacy
 * ```
 *
 * Ce shim n'est **pas optionnel** : le déploiement des Functions est partagé
 * entre prod et staging (ADR 0003), et les builds mobiles déjà installées —
 * qu'on ne peut pas forcer à se mettre à jour — continueront d'envoyer
 * `{plan}` pendant des semaines. Le retirer est une PR dédiée, conditionnée à
 * une version plancher mobile effectivement diffusée.
 */
export function parseCheckoutRequest(
  data: Record<string, unknown>,
): PlanSelection {
  const level = data.level === undefined || data.level === null ?
    DEFAULT_LEVEL :
    parseLevel(data.level);
  // `period` d'abord, `plan` en repli : un client récent qui enverrait les deux
  // (par prudence) n'obtient pas une périodicité différente de celle affichée.
  const rawPeriod = data.period ?? data.plan;
  return {level, period: parsePeriod(rawPeriod)};
}

/**
 * PURE — refuse d'ouvrir une Checkout Session à un compte DÉJÀ payant
 * (FEAT-056 §4.4).
 *
 * Sans cette garde, un abonné qui repasse par `/pro` créerait une **seconde**
 * subscription Stripe : double prélèvement, deux entitlements RevenueCat en
 * concurrence, et un remboursement à faire à la main. Le changement de palier
 * a son propre chemin (`manageSubscription/change_plan`), qui modifie
 * l'abonnement existant au lieu d'en créer un.
 *
 * OWASP-01 — doc landlord ABSENT de la base routée → refus
 * (`failed-precondition` / `landlord_not_found`). Un compte qui n'a pas de doc
 * dans l'environnement visé n'y existe pas : ce n'est pas « un compte gratuit ».
 * Le laisser passer permettait à un compte de l'AUTRE environnement (compte prod
 * sur le checkout staging, en Stripe test) d'ouvrir une session de test, dont
 * l'achat visait ensuite le doc prod. Aucun client légitime n'est bloqué : un
 * compte réel a toujours son doc dans sa base (créé à l'inscription).
 */
export function assertCanOpenCheckout(
  landlord: Record<string, unknown> | null,
): void {
  if (landlord === null) {
    throw new HttpsError("failed-precondition", "landlord_not_found");
  }
  if (resolvePlan(landlord).tier === "paid") {
    throw new HttpsError(
      "failed-precondition",
      "already_subscribed_use_change_plan",
    );
  }
}

/**
 * Construit les paramètres de la Checkout Session. Pur/testable — c'est ICI que
 * vit la logique critique : le bon price et l'App User ID posé en metadata aux
 * DEUX endroits que RevenueCat inspecte.
 *
 * Lève avant tout appel Stripe si le palier n'est pas vendable
 * (`level_not_purchasable`) ou si son price n'est pas configuré
 * (`price_not_configured`) — cf. [resolvePriceIdOrThrow].
 */
export function buildCheckoutSessionParams(args: {
  uid: string;
  level: LevelId;
  period: BillingPeriod;
  config: CheckoutConfig;
  customerEmail?: string | null;
}): Stripe.Checkout.SessionCreateParams {
  const {uid, level, period, config, customerEmail} = args;
  const price = resolvePriceIdOrThrow(config.prices, level, period);
  const metadata: Stripe.MetadataParam = {
    [RC_APP_USER_ID_METADATA_KEY]: uid,
    [PLAN_LEVEL_METADATA_KEY]: level,
  };

  const params: Stripe.Checkout.SessionCreateParams = {
    mode: "subscription",
    line_items: [{price, quantity: 1}],
    // `level` permet à /pro/success d'afficher le palier acheté sans attendre
    // le webhook — affichage seulement, jamais un octroi de droit.
    success_url:
      `${config.baseUrl}/pro/success?session_id={CHECKOUT_SESSION_ID}` +
      `&level=${level}`,
    cancel_url: `${config.baseUrl}/pro/cancel`,
    client_reference_id: uid,
    // RevenueCat lit l'App User ID depuis la metadata de la SESSION *et* de la
    // subscription — les deux sont nécessaires (cf. doc RevenueCat).
    metadata,
    subscription_data: {metadata},
  };
  if (customerEmail) params.customer_email = customerEmail;
  return params;
}

export const createCheckoutSession = onCall(
  {secrets: [stripeSecret, stripeTestSecret]},
  async (request) => {
    const uid = await requireVerifiedUid(request);
    const {level, period} = parseCheckoutRequest(asBag(request.data));

    // Garde anti-double-abonnement : lecture du doc landlord AVANT tout appel
    // Stripe. `dbForRequest` route staging/prod (ADR 0003).
    const db = await dbForRequest(request);
    const landlordSnap = await db.doc(`landlords/${uid}`).get();
    assertCanOpenCheckout(
      landlordSnap.exists ?
        ((landlordSnap.data() ?? {}) as Record<string, unknown>) :
        null,
    );

    // Issue #138 : la clé Stripe et les URLs de retour se résolvent par
    // l'Origin de l'appel, jamais par une constante de déploiement. Un appel
    // depuis staging obtient la clé test ; une origine inconnue est refusée.
    const origin = request.rawRequest?.headers?.origin;
    const stripeKey = resolveStripeKeyOrThrow(
      origin,
      stripeSecret.value(),
      stripeTestSecret.value(),
    );

    const config: CheckoutConfig = {
      prices: readPriceTable(),
      // Renvoyer l'utilisateur sur l'hôte d'où il vient : le défaut
      // `WEB_APP_BASE_URL` (prod) expédiait un acheteur parti de staging vers
      // baillan.com après paiement. `origin` est déjà validé ci-dessus.
      baseUrl:
        stripeEnvForOrigin(origin) === "live" ?
          webAppBaseUrl.value() :
          String(origin),
    };
    const email =
      typeof request.auth?.token.email === "string" ?
        request.auth.token.email :
        null;

    const params = buildCheckoutSessionParams({
      uid,
      level,
      period,
      config,
      customerEmail: email,
    });

    const stripe = new Stripe(stripeKey);
    const session = await stripe.checkout.sessions.create(params);

    // L'URL hostée Stripe vers laquelle le client web redirige.
    return {url: session.url, sessionId: session.id, level, period};
  },
);
