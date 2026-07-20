/**
 * createCheckoutSession — crée une Stripe Checkout Session pour l'abonnement
 * Baillan Pro sur le WEB (FEAT-044, ADR 0002 §Amendement 2026-07-20).
 *
 * Architecture « RevenueCat = plan de gestion » (approche A) :
 *   web → Stripe Checkout (cette fonction) → Stripe → RevenueCat (ingestion via
 *   compte connecté + External Purchase Tracking) → webhook `revenueCatWebhook`
 *   → landlords/{uid}.subscriptionTier.
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

import {asBag, requireAuthUid, requireString} from "../utils/callable_helpers";

/** Clé secrète Stripe (serveur uniquement). */
const stripeSecret = defineSecret("STRIPE_SECRET_KEY");
/** Price IDs Stripe des offres Pro (non secrets — configurés au déploiement). */
const priceProMonthly = defineString("STRIPE_PRICE_PRO_MONTHLY");
const priceProAnnual = defineString("STRIPE_PRICE_PRO_ANNUAL");
/** Base URL web pour les redirections success/cancel. */
const webAppBaseUrl = defineString("WEB_APP_BASE_URL", {
  default: "https://easy-rent-54cd4.web.app",
});

/**
 * Nom du champ metadata que RevenueCat lit pour lier l'abonnement Stripe à
 * l'App User ID (= UID Firebase). ⚠️ DOIT correspondre au champ configuré dans
 * le dashboard RevenueCat (intégration Stripe).
 */
export const RC_APP_USER_ID_METADATA_KEY = "rc_app_user_id";

export type PlanId = "monthly" | "annual";

export interface CheckoutConfig {
  priceMonthly: string;
  priceAnnual: string;
  baseUrl: string;
}

/**
 * Construit les paramètres de la Checkout Session. Pur/testable — c'est ICI que
 * vit la logique critique : le bon price et l'App User ID posé en metadata aux
 * DEUX endroits que RevenueCat inspecte.
 */
export function buildCheckoutSessionParams(args: {
  uid: string;
  plan: PlanId;
  config: CheckoutConfig;
  customerEmail?: string | null;
}): Stripe.Checkout.SessionCreateParams {
  const {uid, plan, config, customerEmail} = args;
  const price = plan === "annual" ? config.priceAnnual : config.priceMonthly;
  const metadata: Stripe.MetadataParam = {[RC_APP_USER_ID_METADATA_KEY]: uid};

  const params: Stripe.Checkout.SessionCreateParams = {
    mode: "subscription",
    line_items: [{price, quantity: 1}],
    success_url: `${config.baseUrl}/pro/success?session_id={CHECKOUT_SESSION_ID}`,
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
  {secrets: [stripeSecret]},
  async (request) => {
    const uid = requireAuthUid(request);
    const data = asBag(request.data);
    const plan = requireString(data.plan, "plan");
    if (plan !== "monthly" && plan !== "annual") {
      throw new HttpsError(
        "invalid-argument",
        "plan doit valoir 'monthly' ou 'annual'",
      );
    }

    const config: CheckoutConfig = {
      priceMonthly: priceProMonthly.value(),
      priceAnnual: priceProAnnual.value(),
      baseUrl: webAppBaseUrl.value(),
    };
    const email =
      typeof request.auth?.token.email === "string"
        ? request.auth.token.email
        : null;

    const stripe = new Stripe(stripeSecret.value());
    const session = await stripe.checkout.sessions.create(
      buildCheckoutSessionParams({uid, plan, config, customerEmail: email}),
    );

    // L'URL hostée Stripe vers laquelle le client web redirige.
    return {url: session.url, sessionId: session.id};
  },
);
