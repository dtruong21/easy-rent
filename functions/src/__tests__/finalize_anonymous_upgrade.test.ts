import {describe, expect, it} from "vitest";

import {
  CURRENT_RGPD_VERSION,
  resolveRgpdConsentVersion,
  resolveUpgradeIdentity,
} from "../callable/finalize_anonymous_upgrade";

describe("resolveUpgradeIdentity", () => {
  /** Doc anonyme tel que provisionné par le client : ni email ni nom. */
  const anonDoc = {email: null, fullName: ""};

  it("cas réel Google : displayName absent au niveau supérieur, présent sur le provider", () => {
    // Reproduit exactement le compte observé en recette (uid 7gj7hJ1…) :
    // `authUser.displayName` undefined, mais providerData porte le vrai nom.
    // C'est CE cas qui produisait `fullName: ''` sur un compte complet.
    expect(
      resolveUpgradeIdentity(
        {
          email: undefined,
          displayName: undefined,
          providerData: [
            {email: "daki@example.com", displayName: "Thi Kim Chi Le"},
          ],
        },
        anonDoc,
      ),
    ).toEqual({email: "daki@example.com", fullName: "Thi Kim Chi Le"});
  });

  it("préfère le niveau supérieur quand il est renseigné", () => {
    expect(
      resolveUpgradeIdentity(
        {
          email: "top@example.com",
          displayName: "Nom Top",
          providerData: [{email: "prov@example.com", displayName: "Nom Prov"}],
        },
        anonDoc,
      ),
    ).toEqual({email: "top@example.com", fullName: "Nom Top"});
  });

  it("n'écrase JAMAIS une valeur déjà renseignée sur le doc", () => {
    // Un upgrade rejoué ne doit pas écraser un nom corrigé par l'utilisateur.
    expect(
      resolveUpgradeIdentity(
        {
          email: "auth@example.com",
          displayName: "Nom Auth",
          providerData: [],
        },
        {email: "deja@example.com", fullName: "Nom Déjà Corrigé"},
      ),
    ).toEqual({});
  });

  it("complète uniquement le champ manquant", () => {
    expect(
      resolveUpgradeIdentity(
        {email: "a@example.com", displayName: "Nom A", providerData: []},
        {email: "deja@example.com", fullName: ""},
      ),
    ).toEqual({fullName: "Nom A"});
  });

  it("retombe sur l'email comme nom quand aucun displayName n'existe nulle part", () => {
    // Laid, mais respecte l'invariant « un compte complet a un nom non vide »
    // qu'impose la rule CREATE — et ça reste modifiable dans l'app.
    expect(
      resolveUpgradeIdentity(
        {email: null, displayName: null, providerData: [{email: "x@y.z"}]},
        anonDoc,
      ),
    ).toEqual({email: "x@y.z", fullName: "x@y.z"});
  });

  it("ignore les chaînes vides ou blanches, au niveau supérieur comme provider", () => {
    expect(
      resolveUpgradeIdentity(
        {
          email: "   ",
          displayName: "",
          providerData: [{email: "", displayName: "   "}],
        },
        anonDoc,
      ),
    ).toEqual({});
  });

  it("trim les valeurs retenues", () => {
    expect(
      resolveUpgradeIdentity(
        {email: "  a@b.c  ", displayName: "  Nom  ", providerData: []},
        anonDoc,
      ),
    ).toEqual({email: "a@b.c", fullName: "Nom"});
  });

  it("prend le premier provider portant la valeur, pas forcément le premier tout court", () => {
    expect(
      resolveUpgradeIdentity(
        {
          email: null,
          displayName: null,
          providerData: [
            {email: null, displayName: null},
            {email: "second@example.com", displayName: "Second"},
          ],
        },
        anonDoc,
      ),
    ).toEqual({email: "second@example.com", fullName: "Second"});
  });

  it("ne renvoie rien si Auth n'a aucune identité exploitable", () => {
    expect(
      resolveUpgradeIdentity(
        {email: null, displayName: null, providerData: []},
        anonDoc,
      ),
    ).toEqual({});
  });
});

describe("resolveRgpdConsentVersion", () => {
  it("retourne la version courante si le client envoie exactement la même", () => {
    expect(resolveRgpdConsentVersion(CURRENT_RGPD_VERSION)).toBe(
      CURRENT_RGPD_VERSION,
    );
  });

  it("retombe sur la version serveur si le client envoie une version obsolète", () => {
    expect(resolveRgpdConsentVersion("v0-2025-01")).toBe(CURRENT_RGPD_VERSION);
  });

  it("retombe sur la version serveur si le client n'envoie rien (undefined)", () => {
    expect(resolveRgpdConsentVersion(undefined)).toBe(CURRENT_RGPD_VERSION);
  });

  it("retombe sur la version serveur si le client envoie null", () => {
    expect(resolveRgpdConsentVersion(null)).toBe(CURRENT_RGPD_VERSION);
  });

  it("retombe sur la version serveur si le client envoie un type invalide", () => {
    expect(resolveRgpdConsentVersion(42)).toBe(CURRENT_RGPD_VERSION);
  });
});
