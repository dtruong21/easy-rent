/**
 * Tokens d'auth de test pour les callables (OWASP-02).
 *
 * Les callables métier exigent un compte « de confiance » (email vérifié,
 * Google/Apple, ou anonyme confirmé) via `requireVerifiedUid`. Un token `{}`
 * représenterait donc un compte NON vérifié : les tests de comportement métier
 * utilisent [VERIFIED_TOKEN], et les cas de refus fabriquent leur propre token.
 */

/** Compte email/mot de passe dont l'email est vérifié. */
export const VERIFIED_TOKEN = {
  email_verified: true,
  firebase: {sign_in_provider: "password"},
} as never;
