import {describe, expect, it} from "vitest";

import {isAnonymousUser} from "../auth/handle_new_user";

describe("isAnonymousUser", () => {
  it("détecte un compte anonyme (pas d'email, pas de provider)", () => {
    expect(isAnonymousUser({email: null, providerData: []})).toBe(true);
  });

  it("détecte un compte anonyme quand providerData est undefined", () => {
    expect(isAnonymousUser({email: undefined, providerData: undefined})).toBe(
      true,
    );
  });

  it("ne détecte PAS anonyme un compte email/password", () => {
    expect(
      isAnonymousUser({
        email: "jean@exemple.fr",
        providerData: [{providerId: "password"}],
      }),
    ).toBe(false);
  });

  it("ne détecte PAS anonyme un compte Google (providerData non vide)", () => {
    expect(
      isAnonymousUser({
        email: "jean@gmail.com",
        providerData: [{providerId: "google.com"}],
      }),
    ).toBe(false);
  });

  it("ne détecte PAS anonyme si email présent même sans providerData (edge case défensif)", () => {
    expect(
      isAnonymousUser({email: "jean@exemple.fr", providerData: []}),
    ).toBe(false);
  });

  it("ne détecte PAS anonyme si providerData non-vide même sans email (edge case défensif)", () => {
    // Ce cas ne devrait jamais se produire en pratique (un provider externe
    // fournit toujours un email), mais on documente le comportement exact :
    // la présence d'un provider externe suffit à écarter l'hypothèse
    // anonyme, peu importe l'email.
    expect(
      isAnonymousUser({
        email: null,
        providerData: [{providerId: "google.com"}],
      }),
    ).toBe(false);
  });
});
