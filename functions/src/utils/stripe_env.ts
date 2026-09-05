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

/**
 * Origines servant l'application de production. La clé Stripe live n'est
 * accessible QUE depuis l'une d'elles, en comparaison exacte.
 *
 * `app.baillan.com` y figure avant même la migration de domaine (sujet cadré
 * dans `docs/BACKLOG.md`, = FEAT-050e) : le sous-domaine nous appartient, rien
 * ne le sert aujourd'hui, et l'y inscrire d'avance évite l'échec silencieux le
 * jour de la bascule — un paiement prod refusé parce que l'allowlist n'a pas
 * suivi le DNS.
 */
export const PROD_ORIGINS = [
  "https://baillan.com",
  "https://www.baillan.com",
  "https://app.baillan.com",
] as const;

/** Origines servant l'app en mode test : staging déployé et émulateur local. */
const TEST_ORIGINS = ["https://stage.baillan.com"] as const;

/** Préfixes d'origine locale (émulateur) — le port varie selon la commande. */
const LOCAL_ORIGIN_PREFIXES = ["http://localhost:", "http://127.0.0.1:"] as const;

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
  if ((PROD_ORIGINS as readonly string[]).includes(origin)) return "live";
  if ((TEST_ORIGINS as readonly string[]).includes(origin)) return "test";
  if (LOCAL_ORIGIN_PREFIXES.some((p) => origin.startsWith(p))) return "test";
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
    return testKey;
  }

  if (!liveKey) {
    throw new HttpsError(
      "failed-precondition",
      "stripe_live_key_not_configured",
    );
  }
  return liveKey;
}
