/**
 * manageSubscription — résilie, réactive ou CHANGE DE PALIER l'abonnement
 * Baillan sur le WEB (FEAT-044f, conformité art. L215-1-1 C. conso.
 * « résiliation en 3 clics » ; changement de palier ajouté par FEAT-056 §4.4).
 *
 * Architecture « RevenueCat = plan de gestion » : cette fonction ne touche que
 * l'abonnement **Stripe** (`cancel_at_period_end`, ou l'item de facturation
 * pour un changement de palier). Elle N'ÉCRIT PAS Firestore — le tier, le
 * `planLevel` et les champs `pro*` restent mis à jour par le SEUL écrivain
 * autoritaire, le webhook RevenueCat (`revenuecat_webhook.ts`), et le downgrade
 * vers freemium suit automatiquement (`reconcile_entitlements.ts`). Ne pas
 * « aider l'UI à réagir plus vite » en écrivant ici : ce serait un second
 * écrivain du droit, donc une source de désaccord avec la facturation.
 *
 * Frontière de sécurité : le client ne fournit JAMAIS d'identifiant Stripe. La
 * fonction dérive l'UID via `requireAuthUid` puis résout l'abonnement par la
 * metadata `rc_app_user_id` posée au checkout à la valeur de CE propriétaire
 * (`create_checkout_session.ts`, [RC_APP_USER_ID_METADATA_KEY]). Aucun paramètre
 * client ne peut donc viser l'abonnement d'autrui — l'IDOR est structurellement
 * impossible. `change_plan` ne fait PAS exception : il n'accepte qu'un palier
 * et une périodicité, jamais un subscription id, un item id ni un price id.
 */

import {defineSecret} from "firebase-functions/params";
import {logger} from "firebase-functions/v2";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import Stripe from "stripe";

import {rankOf, type LevelId} from "../entitlements/plan_matrix.generated";
import {
  levelForPriceId,
  readPriceTable,
  resolvePriceIdOrThrow,
  type BillingPeriod,
  type PriceTable,
} from "../entitlements/stripe_prices";
import {asBag, requireAuthUid, requireString} from "../utils/callable_helpers";
import {resolveStripeKeyOrThrow} from "../utils/stripe_env";

import {
  parsePlanSelection,
  RC_APP_USER_ID_METADATA_KEY,
} from "./create_checkout_session";

/** Clé secrète Stripe (serveur uniquement) — réutilise le secret existant. */
const stripeSecret = defineSecret("STRIPE_SECRET_KEY");

/**
 * Clé secrète Stripe TEST — servie au staging et à l'émulateur (issue #138).
 * Même garantie que sur `createCheckoutSession` : gérer un abonnement depuis
 * staging ne doit jamais toucher les abonnements réels du compte Stripe live.
 */
const stripeTestSecret = defineSecret("STRIPE_SECRET_KEY_TEST");

/**
 * Statuts Stripe d'un abonnement encore « gérable » (la période court, donc on
 * peut (dé)programmer sa résiliation ou changer son palier). Un
 * `canceled`/`incomplete_expired` n'a plus rien à gérer.
 */
export const CANCELABLE_STATUSES: ReadonlySet<string> = new Set<string>([
  "active",
  "trialing",
  "past_due",
  "unpaid",
]);

export type SubscriptionAction = "cancel" | "reactivate" | "change_plan";

export interface ManageSubscriptionResult {
  status: "updated" | "noop";
  cancelAtPeriodEnd: boolean;
}

export interface ChangePlanResult {
  status: "updated" | "noop";
  level: LevelId;
  period: BillingPeriod;
  /**
   * Instant d'effet (epoch ms). Toujours « maintenant » : la politique retenue
   * est un changement **immédiat et proratisé dans les deux sens**.
   */
  effectiveAt: number;
}

/** Une ligne de facturation d'un abonnement (forme minimale, testable). */
export interface SubscriptionItemLike {
  id: string;
  price: {id: string};
}

/** Forme minimale d'un abonnement dont la logique pure a besoin (testable sans Stripe). */
export interface ManageableSubscriptionLike {
  id: string;
  status: string;
  cancel_at_period_end: boolean;
  created: number;
  items?: SubscriptionItemLike[];
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
): {
  id: string;
  cancel_at_period_end: boolean;
  items: SubscriptionItemLike[];
} | null {
  const manageable = subs
    .filter((s) => CANCELABLE_STATUSES.has(s.status))
    .sort((a, b) => b.created - a.created);
  const chosen = manageable[0];
  if (!chosen) return null;
  return {
    id: chosen.id,
    cancel_at_period_end: chosen.cancel_at_period_end,
    items: chosen.items ?? [],
  };
}

/**
 * PURE — la ligne de facturation à repricer lors d'un changement de palier.
 *
 * Un abonnement Baillan a exactement UNE ligne. Face à zéro ou plusieurs, on
 * refuse au lieu de deviner : repricer la mauvaise ligne d'un abonnement
 * composite modifierait une facturation qu'on ne comprend pas.
 */
export function pickSubscriptionItem(
  items: SubscriptionItemLike[],
): SubscriptionItemLike {
  const only = items.length === 1 ? items[0] : undefined;
  if (only === undefined) {
    throw new HttpsError(
      "failed-precondition",
      "unsupported_subscription_shape",
    );
  }
  return only;
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

/**
 * PURE — qualifie un changement de palier.
 *
 * - `noop` : le price visé est déjà celui facturé. On n'appelle alors PAS
 *   Stripe — même politique d'idempotence que cancel/reactivate, et zéro event
 *   RevenueCat parasite (donc zéro risque de proration à 0 € qui polluerait la
 *   facture).
 * - `direction` : purement informatif (journal + support). La proration Stripe
 *   est **symétrique** — `create_prorations` dans les deux sens —, donc aucune
 *   décision de facturation ne dépend de ce champ. `same` couvre le changement
 *   de périodicité à palier constant (mensuel ↔ annuel) et le cas d'un price
 *   courant inconnu de la table (offre legacy) : on ne bloque jamais un abonné
 *   sur un prix historique.
 */
export function planLevelChange(args: {
  currentPriceId: string | null;
  targetPriceId: string;
  currentRank: number;
  targetRank: number;
}): {noop: boolean; direction: "upgrade" | "downgrade" | "same"} {
  const noop = args.currentPriceId === args.targetPriceId;
  let direction: "upgrade" | "downgrade" | "same" = "same";
  if (args.targetRank > args.currentRank) direction = "upgrade";
  else if (args.targetRank < args.currentRank) direction = "downgrade";
  return {noop, direction};
}

/** Valide l'action reçue du client. */
export function parseAction(value: unknown): SubscriptionAction {
  const raw = requireString(value, "action");
  if (raw !== "cancel" && raw !== "reactivate" && raw !== "change_plan") {
    throw new HttpsError(
      "invalid-argument",
      "action must be 'cancel', 'reactivate' or 'change_plan'",
    );
  }
  return raw;
}

/**
 * Défense en profondeur avant interpolation de l'UID dans la requête Stripe
 * Search : un UID Firebase est alphanumérique URL-safe, donc ne contient jamais
 * l'apostrophe qui casserait le littéral `'...'` de la query (seul métacaractère
 * dangereux). Tout UID hors de cette forme est rejeté — l'interpolation §handler
 * n'est donc jamais injectable. Fonction pure exportée pour être testée : c'est
 * la garantie « injection impossible » qui repose dessus.
 */
export function assertSafeUid(uid: string): void {
  if (!/^[A-Za-z0-9_-]+$/.test(uid)) {
    throw new HttpsError("invalid-argument", "malformed uid");
  }
}

/**
 * Offre visée par un `change_plan`, résolue en un bloc : palier, périodicité et
 * price ID cible.
 *
 * Le client ne fournit QUE `{level, period}` — jamais un price ID, jamais un
 * identifiant Stripe. Le price est dérivé côté serveur de la même table que le
 * checkout, donc soumis aux deux mêmes verrous : un palier non vendable
 * (`level_not_purchasable`) ou sans prix configuré (`price_not_configured`)
 * échoue AVANT le moindre appel Stripe.
 */
function resolveChange(data: Record<string, unknown>): {
  prices: PriceTable;
  level: LevelId;
  period: BillingPeriod;
  targetPriceId: string;
} {
  const prices = readPriceTable();
  const {level, period} = parsePlanSelection(data);
  return {
    prices,
    level,
    period,
    targetPriceId: resolvePriceIdOrThrow(prices, level, period),
  };
}

export const manageSubscription = onCall(
  {secrets: [stripeSecret, stripeTestSecret]},
  async (request): Promise<ManageSubscriptionResult | ChangePlanResult> => {
    const uid = requireAuthUid(request);
    const data = asBag(request.data);
    const action = parseAction(data.action);
    assertSafeUid(uid);

    // Résolution de l'offre visée AVANT tout appel Stripe : un palier non
    // vendable (`level_not_purchasable`) ou sans price configuré
    // (`price_not_configured`) doit échouer sans toucher à l'abonnement.
    // `null` pour cancel/reactivate — c'est ce champ, et non `action`, qui
    // sélectionne la branche plus bas, pour qu'aucune combinaison partielle
    // (palier résolu sans action, ou l'inverse) ne soit représentable.
    const change = action === "change_plan" ? resolveChange(data) : null;

    // Issue #138 : clé résolue par l'Origin de l'appel. Sans ce garde-fou,
    // un `cancel`/`change_plan` lancé depuis staging opérait sur les vrais
    // abonnements du compte Stripe de production.
    const stripe = new Stripe(
      resolveStripeKeyOrThrow(
        request.rawRequest?.headers?.origin,
        stripeSecret.value(),
        stripeTestSecret.value(),
      ),
    );

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
        items: s.items.data.map((i) => ({id: i.id, price: {id: i.price.id}})),
      })),
    );
    if (target === null) {
      // Abonné via un store mobile (IAP) ou sans abonnement web : l'UI renvoie
      // vers le store, le changement de palier y est obligatoire.
      throw new HttpsError("failed-precondition", "no_active_web_subscription");
    }

    if (change !== null) {
      const item = pickSubscriptionItem(target.items);
      const currentLevel = levelForPriceId(change.prices, item.price.id);
      const {noop, direction} = planLevelChange({
        currentPriceId: item.price.id,
        targetPriceId: change.targetPriceId,
        currentRank: currentLevel === null ? 0 : rankOf(currentLevel),
        targetRank: rankOf(change.level),
      });

      if (noop) {
        return {
          status: "noop",
          level: change.level,
          period: change.period,
          effectiveAt: Date.now(),
        };
      }

      // Politique validée par le propriétaire : effet IMMÉDIAT et proratisé
      // dans les deux sens. Une montée est facturée au prorata des jours
      // restants ; une descente génère un AVOIR reporté sur les factures
      // suivantes — jamais un remboursement. C'est le comportement natif de
      // Stripe (`create_prorations`), sans machine à états maison ni
      // Subscription Schedule.
      await stripe.subscriptions.update(target.id, {
        items: [{id: item.id, price: change.targetPriceId}],
        proration_behavior: "create_prorations",
        // Une montée de palier peut exiger une authentification 3DS : on ne
        // laisse pas l'échec de paiement annuler l'abonnement en cours.
        payment_behavior: "pending_if_incomplete",
      });
      logger.info("change_plan applied", {
        uid,
        direction,
        from: currentLevel,
        to: change.level,
        period: change.period,
      });

      // Aucune écriture Firestore : le palier reste accordé par le seul
      // webhook RevenueCat (PRODUCT_CHANGE).
      return {
        status: "updated",
        level: change.level,
        period: change.period,
        effectiveAt: Date.now(),
      };
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
