import {describe, expect, it} from "vitest";

import {STAGING_ORIGIN} from "../utils/db_router";
import {
  PROD_ORIGINS,
  resolveStripeKeyOrThrow,
  stripeEnvForOrigin,
  type StripeEnv,
} from "../utils/stripe_env";

// Issue #138 (S1) : les callables Stripe résolvaient leur clé sans regarder
// d'où venait l'appel. Un test du paywall depuis `stage.baillan.com` créait
// donc une vraie Checkout `sk_live`, encaissable. La garantie porte ici :
// `stripeEnvForOrigin` est la SEULE porte vers la clé live.
//
// ⚠️ Le fail-safe est INVERSE de celui de `db_router.isStagingOrigin` : pour
// Firestore, l'inconnu retombe sur la prod (ne jamais écrire un compte prod
// dans `dev`) ; pour Stripe, l'inconnu ne doit JAMAIS obtenir la clé live —
// « défaut = prod » signifierait ici « défaut = argent réel ».
describe("stripeEnvForOrigin — allowlist positive de la prod", () => {
  it("origines prod exactes → live", () => {
    for (const origin of PROD_ORIGINS) {
      expect(stripeEnvForOrigin(origin)).toBe<StripeEnv>("live");
    }
  });

  it("origin staging → test, jamais live", () => {
    expect(stripeEnvForOrigin("https://stage.baillan.com")).toBe<StripeEnv>(
      "test",
    );
  });

  it("origin absent / vide → unknown (jamais live)", () => {
    expect(stripeEnvForOrigin(undefined)).toBe<StripeEnv>("unknown");
    expect(stripeEnvForOrigin(null)).toBe<StripeEnv>("unknown");
    expect(stripeEnvForOrigin("")).toBe<StripeEnv>("unknown");
  });

  it("origin inconnu ou hostile → unknown (jamais live)", () => {
    expect(stripeEnvForOrigin("https://evil.tld")).toBe<StripeEnv>("unknown");
    expect(stripeEnvForOrigin("https://baillan.com.evil.tld")).toBe<StripeEnv>(
      "unknown",
    );
    expect(stripeEnvForOrigin("http://baillan.com")).toBe<StripeEnv>("unknown");
    expect(stripeEnvForOrigin("https://baillan.com/")).toBe<StripeEnv>(
      "unknown",
    );
  });

  it("localhost (émulateur) → test — c'est là que les paliers se testent", () => {
    expect(stripeEnvForOrigin("http://localhost:5000")).toBe<StripeEnv>("test");
    expect(stripeEnvForOrigin("http://127.0.0.1:5000")).toBe<StripeEnv>("test");
  });

  // L'origine résolue est réutilisée comme base des URLs de retour Stripe. Un
  // `startsWith("http://localhost:")` acceptait `http://localhost:0@evil.tld`,
  // dont l'hôte réel est `evil.tld` (la partie avant `@` est un userinfo) :
  // redirection ouverte post-paiement sous la marque.
  it("faux localhost avec userinfo → unknown, pas test", () => {
    expect(stripeEnvForOrigin("http://localhost:0@evil.tld")).toBe<StripeEnv>(
      "unknown",
    );
    expect(stripeEnvForOrigin("http://localhost:5000.evil.tld")).toBe<StripeEnv>(
      "unknown",
    );
    expect(stripeEnvForOrigin("http://localhost:5000/x")).toBe<StripeEnv>(
      "unknown",
    );
    expect(stripeEnvForOrigin("https://localhost:5000")).toBe<StripeEnv>(
      "unknown",
    );
  });

  it("app.baillan.com est pré-autorisé pour la migration de domaine", () => {
    expect(stripeEnvForOrigin("https://app.baillan.com")).toBe<StripeEnv>(
      "live",
    );
  });
});

// La garantie de #138 ne tient que si AUCUN chemin ne rend la clé live à un
// appel non-prod. On verrouille les quatre sorties possibles du résolveur.
describe("resolveStripeKeyOrThrow — seule porte vers sk_live", () => {
  const LIVE = "sk_live_xxx";
  const TEST = "sk_test_xxx";

  it("origine prod → clé live", () => {
    expect(resolveStripeKeyOrThrow("https://baillan.com", LIVE, TEST)).toBe(
      LIVE,
    );
  });

  it("origine staging → clé test, JAMAIS la live (régression #138)", () => {
    expect(
      resolveStripeKeyOrThrow("https://stage.baillan.com", LIVE, TEST),
    ).toBe(TEST);
  });

  it("origine staging sans clé test posée → refus, pas de repli sur la live", () => {
    expect(() =>
      resolveStripeKeyOrThrow("https://stage.baillan.com", LIVE, ""),
    ).toThrowError(/stripe_test_key_not_configured/);
  });

  it("origine inconnue → refus, jamais de clé rendue", () => {
    expect(() =>
      resolveStripeKeyOrThrow("https://evil.tld", LIVE, TEST),
    ).toThrowError(/origin_not_allowed/);
    expect(() => resolveStripeKeyOrThrow(undefined, LIVE, TEST)).toThrowError(
      /origin_not_allowed/,
    );
  });

  it("origine prod sans clé live posée → refus explicite", () => {
    expect(() =>
      resolveStripeKeyOrThrow("https://baillan.com", "", TEST),
    ).toThrowError(/stripe_live_key_not_configured/);
  });
});

// Les Functions se déploient à la main, `defineSecret` demandant la valeur en
// invite interactive. Coller la clé live dans le secret de test rouvrirait
// #138 en entier, sans qu'aucun test ni garde-fou ne bronche.
describe("assertion de mode — la clé doit correspondre à l'environnement", () => {
  it("clé live collée dans le secret de test → refus", () => {
    expect(() =>
      resolveStripeKeyOrThrow(
        "https://stage.baillan.com",
        "sk_live_xxx",
        "sk_live_COLLEE_PAR_ERREUR",
      ),
    ).toThrowError(/stripe_key_mode_mismatch_test/);
  });

  it("clé de test posée sur le secret live → refus", () => {
    expect(() =>
      resolveStripeKeyOrThrow(
        "https://baillan.com",
        "sk_test_COLLEE_PAR_ERREUR",
        "sk_test_xxx",
      ),
    ).toThrowError(/stripe_key_mode_mismatch_live/);
  });

  it("clés restreintes (rk_) acceptées dans les deux modes", () => {
    expect(
      resolveStripeKeyOrThrow("https://baillan.com", "rk_live_x", "rk_test_x"),
    ).toBe("rk_live_x");
    expect(
      resolveStripeKeyOrThrow(
        "https://stage.baillan.com",
        "rk_live_x",
        "rk_test_x",
      ),
    ).toBe("rk_test_x");
  });
});

// Verrou anti-dérive entre les deux routeurs d'origine : si l'hôte staging
// atterrissait un jour dans PROD_ORIGINS, la suite resterait verte sans ce test.
describe("cohérence avec db_router", () => {
  it("l'origine staging de db_router n'est jamais une origine live", () => {
    expect(stripeEnvForOrigin(STAGING_ORIGIN)).toBe<StripeEnv>("test");
    expect(PROD_ORIGINS).not.toContain(STAGING_ORIGIN);
  });
});
