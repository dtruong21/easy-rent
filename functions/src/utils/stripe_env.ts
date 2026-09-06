/**
 * Résolution de l'environnement Stripe par l'Origin de l'appel (issue #138).
 *
 * Avant ce module, `createCheckoutSession` et `manageSubscription` lisaient un
 * secret `STRIPE_SECRET_KEY` unique, sans regarder d'où venait l'appel. Comme
 * les Cloud Functions sont callables depuis les deux hosts et partagent le même
 * projet, un test du paywall depuis `stage.baillan.com` créait une vraie
 * Checkout `sk_live` : transaction réelle, puis webhook qui passait le compte
 * en `paid` dans la base de prod.
 *
 * ⚠️ Le fail-safe ici est **l'inverse** de celui de [db_router.isStagingOrigin].
 * Pour Firestore, une origine inconnue retombe sur `(default)` — on ne veut
 * jamais écrire un vrai compte prod dans `staging`. Pour Stripe, « défaut =
 * prod » voudrait dire « défaut = argent réel » : c'est précisément le défaut
 * que décrit #138. D'où une **allowlist positive** : la clé live n'est servie
 * que sur une origine prod reconnue au caractère près ; tout le reste est
 * `test` (staging, émulateur) ou `unknown` (refus par l'appelant).
 *
 * Un client non-navigateur peut forger l'Origin. L'impact reste borné : forger
 * une origine staging ne donne qu'un tunnel Stripe en mode test (argent fictif,
 * aucun entitlement prod accordé — le déverrouillage passe par le webhook
 * RevenueCat). Forger une origine prod depuis ailleurs ne permet que de payer
 * réellement, avec sa propre carte, pour son propre compte.
 */

import {HttpsError} from "firebase-functions/v2/https";

import {STAGING_ORIGIN} from "./db_router";

/**
 * Origines servant l'application de production. La clé Stripe live n'est
 * accessible QUE depuis l'une d'elles, en comparaison exacte.
 *
 * Depuis la bascule de domaine (FEAT-050e), l'app vit sur `app.baillan.com`
 * SEUL. `baillan.com` et `www.baillan.com` servent désormais la vitrine
 * statique : ils ne doivent JAMAIS obtenir la clé live — un `createCheckoutSession`
 * appelé depuis la vitrine est refusé (`origin_not_allowed`). Les y laisser
 * rouvrirait la faille de #138 sous une autre forme (le domaine marketing
 * pourrait encaisser).
 */
export const PROD_ORIGINS: readonly string[] = ["https://app.baillan.com"];

/**
 * Origines servant l'app en mode test. Le littéral staging vient de
 * [db_router] plutôt que d'être retapé : si l'hôte de staging déménage et
 * qu'une seule des deux listes suit, le checkout staging casse — ou pire,
 * l'ancien hôte se retrouve hors des deux listes et bascule en `unknown`.
 */
export const TEST_ORIGINS: readonly string[] = [STAGING_ORIGIN];

/**
 * Origine locale (émulateur), en correspondance STRICTE. Un simple
 * `startsWith("http://localhost:")` acceptait `http://localhost:0@evil.tld`,
 * dont l'hôte réel est `evil.tld` : la partie avant `@` est un userinfo, pas
 * un hôte. Comme l'origine est ensuite réutilisée pour les URLs de retour
 * Stripe, ça donnait une redirection ouverte sous la marque.
 */
const LOCAL_ORIGIN_RE = /^http:\/\/(localhost|127\.0\.0\.1):\d{1,5}$/;

/**
 * Environnement Stripe d'un appel.
 * - `live` : origine de production reconnue → clé `sk_live` autorisée.
 * - `test` : staging ou émulateur → clé `sk_test` obligatoire.
 * - `unknown` : Origin absent, forgé ou inattendu → l'appelant DOIT refuser.
 *   On ne retombe pas silencieusement sur `test` pour ne pas transformer un
 *   vrai achat prod (dont l'en-tête aurait été perdu par un proxy) en session
 *   de test que l'utilisateur croirait valide.
 */
export type StripeEnv = "live" | "test" | "unknown";

/**
 * Environnement Stripe pour une origine. Comparaison EXACTE sur les origines
 * connues : `https://baillan.com/` (slash final), `http://baillan.com` (schéma
 * clair) et `https://baillan.com.evil.tld` (suffixe) sont tous `unknown`.
 */
export function stripeEnvForOrigin(origin: unknown): StripeEnv {
  if (typeof origin !== "string" || origin === "") return "unknown";
  if (PROD_ORIGINS.includes(origin)) return "live";
  if (TEST_ORIGINS.includes(origin)) return "test";
  if (LOCAL_ORIGIN_RE.test(origin)) return "test";
  return "unknown";
}

/**
 * Clé Stripe à utiliser pour un appel callable, ou refus.
 *
 * Seule porte vers `sk_live` du code serveur : les callables ne doivent JAMAIS
 * lire `stripeSecret.value()` directement, sinon la garantie de #138 fuit par
 * l'appel oublié.
 *
 * @param origin  En-tête `Origin` de la requête (`request.rawRequest.headers`).
 * @param liveKey Valeur du secret `STRIPE_SECRET_KEY` (mode live en prod).
 * @param testKey Valeur du secret `STRIPE_SECRET_KEY_TEST`, vide si non posé.
 */
export function resolveStripeKeyOrThrow(
  origin: unknown,
  liveKey: string,
  testKey: string,
): string {
  const env = stripeEnvForOrigin(origin);

  if (env === "unknown") {
    // Ni prod ni test reconnu : on refuse plutôt que de deviner. Deviner
    // « live » rejouerait #138 ; deviner « test » donnerait à un vrai client
    // prod une session de paiement fictive qu'il croirait valide.
    throw new HttpsError(
      "failed-precondition",
      "origin_not_allowed",
    );
  }

  if (env === "test") {
    if (!testKey) {
      // Fail-secure : sans clé de test configurée, on refuse. Le repli sur la
      // clé live est exactement le bug que cette fonction existe pour rendre
      // impossible.
      throw new HttpsError(
        "failed-precondition",
        "stripe_test_key_not_configured",
      );
    }
    assertKeyMode(testKey, "test");
    return testKey;
  }

  if (!liveKey) {
    throw new HttpsError(
      "failed-precondition",
      "stripe_live_key_not_configured",
    );
  }
  assertKeyMode(liveKey, "live");
  return liveKey;
}

/**
 * Refuse une clé dont le mode ne correspond pas à l'environnement résolu.
 *
 * Les Functions se déploient à la main et `defineSecret` demande la valeur en
 * invite interactive : coller la clé live dans `STRIPE_SECRET_KEY_TEST`
 * rouvrirait #138 en entier, avec CI verte, tests verts et garde-fou vert.
 * C'est la seule défense contre cette faute de frappe. Stripe préfixe ses
 * clés secrètes `sk_` et ses clés restreintes `rk_`.
 */
function assertKeyMode(key: string, mode: "live" | "test"): void {
  if (key.startsWith(`sk_${mode}_`) || key.startsWith(`rk_${mode}_`)) return;
  throw new HttpsError(
    "failed-precondition",
    `stripe_key_mode_mismatch_${mode}`,
  );
}
