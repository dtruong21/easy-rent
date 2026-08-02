/**
 * Price IDs Stripe des six offres (3 paliers × 2 périodicités) — FEAT-056 §4.1.
 *
 * **Un seul registre partagé** par `createCheckoutSession` (achat initial) et
 * `manageSubscription/change_plan` (changement de palier) : deux tables de prix
 * divergentes feraient facturer un palier et en servir un autre.
 *
 * Les NOMS des paramètres viennent de la table canonique
 * (`stripePriceParam` dans `config/entitlements.json`, exposé par le miroir
 * généré), **jamais d'une concaténation** `STRIPE_PRICE_${LEVEL}_${PERIOD}` :
 * un palier ajouté au JSON sans son paramètre doit faire échouer la
 * génération, pas produire silencieusement un nom de param inexistant. Les
 * deux noms Pro existants sont ainsi conservés à l'identique → aucune
 * reconfiguration du Pro en production.
 *
 * Les price IDs ne sont **pas** des secrets (ce sont des identifiants
 * publics visibles dans l'URL de Checkout) : ils restent en `defineString`,
 * hors Secret Manager, comme avant FEAT-056.
 *
 * `default: ""` sur les six : un palier non encore configuré (Max/Ultra au
 * lancement) ne doit pas bloquer un déploiement par une invite interactive —
 * il doit échouer **à l'appel**, proprement, sur `price_not_configured`.
 */

import {defineString} from "firebase-functions/params";
import {HttpsError} from "firebase-functions/v2/https";

import {LEVELS, isPurchasable, type LevelId} from "./plan_matrix.generated";

/** Périodicité de facturation. */
export type BillingPeriod = "monthly" | "annual";

/** Les deux périodicités, pour itérer sans les recopier. */
export const BILLING_PERIODS: readonly BillingPeriod[] = ["monthly", "annual"];

/** Clé d'une offre = palier × périodicité. */
export type PriceKey = `${LevelId}_${BillingPeriod}`;

/**
 * Table des price IDs résolus. Une entrée peut être vide (`""`) : c'est le cas
 * nominal d'un palier pas encore ouvert à la vente.
 */
export type PriceTable = Readonly<Partial<Record<PriceKey, string>>>;

/** `true` si la valeur est une périodicité connue. */
export function isBillingPeriod(value: unknown): value is BillingPeriod {
  return value === "monthly" || value === "annual";
}

/** Clé d'offre — seul endroit où palier et périodicité sont concaténés. */
export function priceKey(level: LevelId, period: BillingPeriod): PriceKey {
  return `${level}_${period}`;
}

/**
 * Paramètres Firebase des six offres, déclarés au chargement du module (c'est
 * ce que la CLI inspecte au déploiement).
 */
const PRICE_PARAMS: Readonly<
  Record<PriceKey, ReturnType<typeof defineString>>
> = (() => {
  const params = {} as Record<PriceKey, ReturnType<typeof defineString>>;
  for (const level of LEVELS) {
    params[priceKey(level.id, "monthly")] = defineString(
      level.stripePriceParamMonthly,
      {default: ""},
    );
    params[priceKey(level.id, "annual")] = defineString(
      level.stripePriceParamAnnual,
      {default: ""},
    );
  }
  return params;
})();

/** Lit les six paramètres à l'exécution (jamais au chargement du module). */
export function readPriceTable(): PriceTable {
  const table: Partial<Record<PriceKey, string>> = {};
  for (const [key, param] of Object.entries(PRICE_PARAMS)) {
    table[key as PriceKey] = param.value();
  }
  return table;
}

/**
 * PURE — price ID de l'offre demandée, ou `HttpsError`.
 *
 * **Deux verrous indépendants, dans cet ordre** :
 *  1. `purchasable: false` → `level_not_purchasable`. C'est la garantie
 *     commerciale « affiché mais pas achetable » (Max et Ultra au lancement).
 *     Elle vit ICI, côté serveur, et pas seulement dans l'UI : une UI en
 *     avance de phase, un client patché ou un appel direct à la callable
 *     doivent échouer de la même façon. Ouvrir un palier = passer un booléen à
 *     `true` dans `config/entitlements.json`, sans PR de code.
 *  2. price absent/vide → `price_not_configured`. Empêche de créer une session
 *     Stripe sur un price vide si le flag a été ouvert avant que les prix
 *     soient créés côté Stripe.
 */
export function resolvePriceIdOrThrow(
  prices: PriceTable,
  level: LevelId,
  period: BillingPeriod,
): string {
  if (!isPurchasable(level)) {
    throw new HttpsError("failed-precondition", "level_not_purchasable");
  }
  const raw = prices[priceKey(level, period)];
  const priceId = typeof raw === "string" ? raw.trim() : "";
  if (priceId.length === 0) {
    throw new HttpsError("failed-precondition", "price_not_configured");
  }
  return priceId;
}

/**
 * PURE — palier auquel appartient un price ID Stripe, `null` s'il est inconnu
 * (prix legacy, promo, offre retirée de la table).
 *
 * Sert uniquement à qualifier un changement de palier (montée / descente) pour
 * le journal : `null` ne doit JAMAIS bloquer un changement, sinon un abonné sur
 * un prix historique se retrouverait coincé sur son palier.
 */
export function levelForPriceId(
  prices: PriceTable,
  priceId: string,
): LevelId | null {
  for (const level of LEVELS) {
    for (const period of BILLING_PERIODS) {
      const candidate = prices[priceKey(level.id, period)];
      if (typeof candidate === "string" &&
        candidate.length > 0 &&
        candidate === priceId) {
        return level.id;
      }
    }
  }
  return null;
}
