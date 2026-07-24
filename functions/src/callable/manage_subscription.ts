/**
 * manageSubscription — résilie ou réactive l'abonnement Baillan Pro sur le WEB
 * (FEAT-044f, conformité art. L215-1-1 C. conso. « résiliation en 3 clics »).
 *
 * Architecture « RevenueCat = plan de gestion » : cette fonction bascule
 * seulement `cancel_at_period_end` sur l'abonnement Stripe. Elle N'ÉCRIT PAS
 * Firestore — le tier et les champs `pro*` restent mis à jour par le SEUL
 * écrivain autoritaire, le webhook RevenueCat (`revenuecat_webhook.ts`), et le
 * downgrade vers freemium suit automatiquement (`reconcile_entitlements.ts`).
 *
 * Frontière de sécurité : le client ne fournit JAMAIS d'identifiant Stripe. La
 * fonction dérive l'UID via `requireAuthUid` puis résout l'abonnement par la
 * metadata `rc_app_user_id` posée au checkout à la valeur de CE propriétaire
 * (`create_checkout_session.ts`, [RC_APP_USER_ID_METADATA_KEY]). Aucun paramètre
 * client ne peut donc viser l'abonnement d'autrui — l'IDOR est structurellement
 * impossible.
 */

import {defineSecret} from "firebase-functions/params";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import Stripe from "stripe";

import {asBag, requireAuthUid, requireString} from "../utils/callable_helpers";

import {RC_APP_USER_ID_METADATA_KEY} from "./create_checkout_session";

/** Clé secrète Stripe (serveur uniquement) — réutilise le secret existant. */
const stripeSecret = defineSecret("STRIPE_SECRET_KEY");

/**
 * Statuts Stripe d'un abonnement encore « gérable » (la période court, donc on
 * peut (dé)programmer sa résiliation). Un `canceled`/`incomplete_expired` n'a
 * plus rien à gérer.
 */
const CANCELABLE_STATUSES = new Set<string>([
  "active",
  "trialing",
  "past_due",
  "unpaid",
]);

export type SubscriptionAction = "cancel" | "reactivate";

export interface ManageSubscriptionResult {
  status: "updated" | "noop";
  cancelAtPeriodEnd: boolean;
}

/** Forme minimale d'un abonnement dont la logique pure a besoin (testable sans Stripe). */
export interface ManageableSubscriptionLike {
  id: string;
  status: string;
  cancel_at_period_end: boolean;
  created: number;
}

/**
 * PURE — sélectionne l'unique abonnement à gérer parmi les résultats de la
 * Search API. Ignore les statuts non gérables (canceled, incomplete_expired…),
 * et si plusieurs subsistent, prend le plus récemment créé (déterministe).
 * Retourne `null` si aucun abonnement gérable (abonné mobile IAP, abonnement
 * déjà terminé, jamais passé par Stripe).
 */
export function pickManageableSubscription(
  subs: ManageableSubscriptionLike[],
): {id: string; cancel_at_period_end: boolean} | null {
  const manageable = subs
    .filter((s) => CANCELABLE_STATUSES.has(s.status))
    .sort((a, b) => b.created - a.created);
  const chosen = manageable[0];
  if (!chosen) return null;
  return {id: chosen.id, cancel_at_period_end: chosen.cancel_at_period_end};
}

/**
 * PURE — décide l'état cible de `cancel_at_period_end` pour l'action demandée,
 * et signale `noop` si l'abonnement est déjà dans cet état (idempotence : on
 * n'appelle alors PAS Stripe, évitant tout event RevenueCat parasite).
 */
export function planSubscriptionUpdate(args: {
  action: SubscriptionAction;
  currentCancelAtPeriodEnd: boolean;
}): {targetCancelAtPeriodEnd: boolean; noop: boolean} {
  const target = args.action === "cancel";
  return {
    targetCancelAtPeriodEnd: target,
    noop: args.currentCancelAtPeriodEnd === target,
  };
}

/** Valide l'action reçue du client. */
function parseAction(value: unknown): SubscriptionAction {
  const raw = requireString(value, "action");
  if (raw !== "cancel" && raw !== "reactivate") {
    throw new HttpsError(
      "invalid-argument",
      "action must be 'cancel' or 'reactivate'",
    );
  }
  return raw;
}

export const manageSubscription = onCall(
  {secrets: [stripeSecret]},
  async (request): Promise<ManageSubscriptionResult> => {
    const uid = requireAuthUid(request);
    const action = parseAction(asBag(request.data).action);

    // Défense en profondeur : un UID Firebase est alphanumérique URL-safe, donc
    // ne contient pas d'apostrophe. On rejette tout UID hors de cette forme
    // avant de l'interpoler dans la requête Search (aucune injection possible).
    if (!/^[A-Za-z0-9_-]+$/.test(uid)) {
      throw new HttpsError("invalid-argument", "malformed uid");
    }

    const stripe = new Stripe(stripeSecret.value());

    const search = await stripe.subscriptions.search({
      query: `metadata['${RC_APP_USER_ID_METADATA_KEY}']:'${uid}'`,
      limit: 20,
    });

    const target = pickManageableSubscription(
      search.data.map((s) => ({
        id: s.id,
        status: s.status,
        cancel_at_period_end: s.cancel_at_period_end,
        created: s.created,
      })),
    );
    if (target === null) {
      throw new HttpsError("failed-precondition", "no_active_web_subscription");
    }

    const {targetCancelAtPeriodEnd, noop} = planSubscriptionUpdate({
      action,
      currentCancelAtPeriodEnd: target.cancel_at_period_end,
    });

    if (noop) {
      return {status: "noop", cancelAtPeriodEnd: target.cancel_at_period_end};
    }

    const updated = await stripe.subscriptions.update(target.id, {
      cancel_at_period_end: targetCancelAtPeriodEnd,
    });
    return {status: "updated", cancelAtPeriodEnd: updated.cancel_at_period_end};
  },
);
