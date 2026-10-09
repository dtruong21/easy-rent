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
 * `default: ""` sur les douze (six canoniques + six `…_TEST`) : un palier non
 * encore configuré (Max/Ultra au lancement) échoue **à l'appel**, proprement,
 * sur `price_not_configured`, et un `…_TEST` vide retombe sur le prix
 * canonique (cf. [selectPriceTable]).
 *
 * Ce défaut n'évite **pas** l'invite au déploiement : la CLI Firebase demande
 * tout paramètre absent de `functions/.env`, défaut ou non (prérempli en
 * interactif ; `--non-interactive` échoue sur « have no value for the
 * following environment variables »). `functions/.env` doit donc déclarer les
 * douze `STRIPE_PRICE_*` et `STRIPE_PRICE_*_TEST` ; une ligne vide
 * (`STRIPE_PRICE_PRO_MONTHLY_TEST=`) suffit pour les `…_TEST`.
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
 * Environnement Stripe d'un jeu de prix : un price ID n'existe que dans le
 * mode Stripe où il a été créé (un price test est inconnu de la clé live, et
 * inversement — cf. `stripe_env.ts`).
 */
export type PriceEnv = "live" | "test";

/**
 * Suffixe des paramètres de prix du mode TEST (reliquat de #138, suivi sur
 * #207). Le nom de base reste celui de la table canonique ; le suffixe ne
 * fabrique aucun nom à partir du palier, il qualifie un nom déjà validé.
 */
export const TEST_PRICE_PARAM_SUFFIX = "_TEST";

type ParamTable = Readonly<Record<PriceKey, ReturnType<typeof defineString>>>;

/**
 * Paramètres Firebase des six offres, déclarés au chargement du module (c'est
 * ce que la CLI inspecte au déploiement), avec [suffix] ajouté aux noms.
 */
function declarePriceParams(suffix: string): ParamTable {
  const params = {} as Record<PriceKey, ReturnType<typeof defineString>>;
  for (const level of LEVELS) {
    params[priceKey(level.id, "monthly")] = defineString(
      `${level.stripePriceParamMonthly}${suffix}`,
      {default: ""},
    );
    params[priceKey(level.id, "annual")] = defineString(
      `${level.stripePriceParamAnnual}${suffix}`,
      {default: ""},
    );
  }
  return params;
}

/** Prix du mode LIVE (prod) : noms canoniques, ex. `STRIPE_PRICE_PRO_MONTHLY`. */
const LIVE_PRICE_PARAMS = declarePriceParams("");

/** Prix du mode TEST (staging, émulateur) : ex. `STRIPE_PRICE_PRO_MONTHLY_TEST`. */
const TEST_PRICE_PARAMS = declarePriceParams(TEST_PRICE_PARAM_SUFFIX);

function readParams(params: ParamTable): PriceTable {
  const table: Partial<Record<PriceKey, string>> = {};
  for (const [key, param] of Object.entries(params)) {
    table[key as PriceKey] = param.value();
  }
  return table;
}

/**
 * PURE — table de prix d'un environnement Stripe.
 *
 * - `live` : les paramètres canoniques, seuls.
 * - `test` : les paramètres `…_TEST`, offre par offre ; une offre sans prix de
 *   test retombe sur le paramètre canonique. Ce repli est TRANSITOIRE : tant
 *   qu'aucune clé Stripe live n'existe, les paramètres canoniques portent des
 *   prix de TEST, et le staging doit continuer de fonctionner sans
 *   reconfiguration. Le jour où les paramètres canoniques reçoivent les prix
 *   LIVE, les `…_TEST` doivent recevoir les prix de test (checklist de #207) ;
 *   un oubli échoue fermé — la clé de test ne connaît pas un price live, Stripe
 *   refuse la session, aucun débit.
 */
export function selectPriceTable(
  env: PriceEnv,
  live: PriceTable,
  test: PriceTable,
): PriceTable {
  if (env === "live") return live;
  const table: Partial<Record<PriceKey, string>> = {};
  for (const level of LEVELS) {
    for (const period of BILLING_PERIODS) {
      const key = priceKey(level.id, period);
      const testPrice = test[key]?.trim() ?? "";
      table[key] = testPrice.length > 0 ? testPrice : live[key];
    }
  }
  return table;
}

/**
 * Lit la table de prix de [env] à l'exécution (jamais au chargement du
 * module) — cf. [selectPriceTable].
 */
export function readPriceTable(env: PriceEnv): PriceTable {
  return selectPriceTable(
    env,
    readParams(LIVE_PRICE_PARAMS),
    env === "test" ? readParams(TEST_PRICE_PARAMS) : {},
  );
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
 * PURE — palier ET périodicité d'un price ID Stripe, `null` s'il est inconnu
 * (prix legacy, promo, offre retirée de la table).
 *
 * Sert à qualifier un changement de palier (montée / descente) pour le journal
 * et à dire à l'UI sur quelle périodicité se trouve l'abonné : `null` ne doit
 * JAMAIS bloquer un changement, sinon un abonné sur un prix historique se
 * retrouverait coincé sur son palier.
 */
export function planForPriceId(
  prices: PriceTable,
  priceId: string,
): {level: LevelId; period: BillingPeriod} | null {
  for (const level of LEVELS) {
    for (const period of BILLING_PERIODS) {
      const candidate = prices[priceKey(level.id, period)];
      if (typeof candidate === "string" &&
        candidate.length > 0 &&
        candidate === priceId) {
        return {level: level.id, period};
      }
    }
  }
  return null;
}

/** PURE — palier d'un price ID Stripe, `null` s'il est inconnu. */
export function levelForPriceId(
  prices: PriceTable,
  priceId: string,
): LevelId | null {
  return planForPriceId(prices, priceId)?.level ?? null;
}
