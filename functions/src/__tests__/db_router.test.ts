import {describe, expect, it} from "vitest";

import {isStagingOrigin, STAGING_ORIGIN} from "../utils/db_router";

// On teste la DÉCISION de routage (pure) — pas l'instance Firestore renvoyée,
// qui exige un app Firebase initialisé. C'est `isStagingOrigin` qui porte la
// garantie de sécurité : seul le staging va vers `dev`, tout le reste (prod,
// Origin absent/forgé) reste sur `(default)`.
describe("isStagingOrigin — routage par Origin", () => {
  it("Origin staging exact → dev", () => {
    expect(isStagingOrigin(STAGING_ORIGIN)).toBe(true);
    expect(isStagingOrigin("https://stage.baillan.com")).toBe(true);
  });

  it("Origin prod → default (jamais mal-router la prod)", () => {
    expect(isStagingOrigin("https://baillan.com")).toBe(false);
  });

  it("Origin absent / vide → default (fail-safe prod)", () => {
    expect(isStagingOrigin(undefined)).toBe(false);
    expect(isStagingOrigin(null)).toBe(false);
    expect(isStagingOrigin("")).toBe(false);
  });

  it("variantes proches NON routées (trailing slash, sous-domaine, http)", () => {
    expect(isStagingOrigin("https://stage.baillan.com/")).toBe(false);
    expect(isStagingOrigin("http://stage.baillan.com")).toBe(false);
    expect(isStagingOrigin("https://stage.baillan.com.evil.tld")).toBe(false);
    expect(isStagingOrigin("https://www.stage.baillan.com")).toBe(false);
  });
});
