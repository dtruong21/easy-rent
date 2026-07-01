import {describe, expect, it} from "vitest";

import {
  CURRENT_RGPD_VERSION,
  resolveRgpdConsentVersion,
} from "../callable/finalize_anonymous_upgrade";

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
