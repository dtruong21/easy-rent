import type {CallableRequest} from "firebase-functions/v2/https";
import {beforeEach, describe, expect, it, vi} from "vitest";

import {
  dbForLandlordUid,
  dbForRequest,
  isStagingOrigin,
  STAGING_ORIGIN,
} from "../utils/db_router";

import {
  FakeFirestore,
  fakeAdminFirestoreHolder,
  fakeStagingFirestoreHolder,
} from "./helpers/fake_firestore";

// Deux bases fake, une par chemin du routeur :
// - `admin.firestore()` (chemin `(default)`/prod) est mocké ici par le fake
//   partagé `fakeAdminFirestoreHolder` ;
// - `getFirestore(STAGING_DATABASE_ID)` (chemin `staging`) est mocké
//   globalement par `helpers/setup_firestore_mock.ts` → `fakeStagingFirestoreHolder`.
// Les deux sont donc des instances distinctes et comparables par identité
// (`toBe`) : un test peut savoir laquelle le routeur a choisie.
vi.mock("firebase-admin", async () => {
  const {makeFakeAdminModule} = await import("./helpers/fake_firestore");
  return makeFakeAdminModule();
});

// `isStagingOrigin` est la décision de routage pure du chemin web : seul
// l'Origin staging exact va vers `staging`, tout le reste (prod, Origin
// absent/forgé) reste sur `(default)`.
describe("isStagingOrigin — routage par Origin", () => {
  it("Origin staging exact → staging", () => {
    expect(isStagingOrigin(STAGING_ORIGIN)).toBe(true);
    expect(isStagingOrigin("https://app.staging.baillan.com")).toBe(true);
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
    expect(isStagingOrigin("https://app.staging.baillan.com/")).toBe(false);
    expect(isStagingOrigin("http://app.staging.baillan.com")).toBe(false);
    expect(isStagingOrigin("https://app.staging.baillan.com.evil.tld")).toBe(false);
    expect(isStagingOrigin("https://www.app.staging.baillan.com")).toBe(false);
  });
});

// `dbForLandlordUid` encode la décision de sécurité critique du webhook et des
// callables mobiles : « chercher prod d'abord, puis staging ». Un inversement
// d'ordre enverrait silencieusement de vrais comptes prod vers `staging`. On
// verrouille le comportement prod-first.
describe("dbForLandlordUid — fail-safe prod-first", () => {
  let fakeDb: FakeFirestore;
  let fakeStaging: FakeFirestore;

  beforeEach(() => {
    fakeDb = new FakeFirestore();
    fakeStaging = new FakeFirestore();
    fakeAdminFirestoreHolder.db = fakeDb;
    fakeStagingFirestoreHolder.db = fakeStaging;
  });

  it("uid vide → prod (default), aucune I/O", async () => {
    expect(await dbForLandlordUid("")).toBe(fakeDb);
  });

  it("landlord présent en (default) → prod, même s'il existe aussi en staging", async () => {
    fakeDb.seed("landlords/u1", {id: "u1", subscriptionTier: "free"});
    // Même uid semé dans la base staging : la garde d'ordre. Si l'ordre était
    // inversé (staging d'abord), `dbForLandlordUid` trouverait le doc en
    // staging et renverrait `fakeStaging` — l'assertion échouerait.
    fakeStaging.seed("landlords/u1", {id: "u1", subscriptionTier: "free"});
    expect(await dbForLandlordUid("u1")).toBe(fakeDb);
  });
});

describe("dbForRequest — web par Origin, mobile par compte", () => {
  let prod: FakeFirestore;
  let staging: FakeFirestore;

  beforeEach(() => {
    prod = new FakeFirestore();
    staging = new FakeFirestore();
    fakeAdminFirestoreHolder.db = prod;
    fakeStagingFirestoreHolder.db = staging;
  });

  const req = (uid: string, origin?: string) =>
    ({
      auth: {uid},
      rawRequest: {headers: origin === undefined ? {} : {origin}},
    }) as unknown as CallableRequest;

  it("web : Origin staging → staging, même si le compte est en prod", async () => {
    prod.seed("landlords/u1", {id: "u1"});
    expect(await dbForRequest(req("u1", STAGING_ORIGIN))).toBe(staging);
  });

  it("web : Origin prod → prod", async () => {
    staging.seed("landlords/u1", {id: "u1"});
    expect(await dbForRequest(req("u1", "https://baillan.com"))).toBe(prod);
  });

  it("web : Origin inattendu → prod", async () => {
    expect(await dbForRequest(req("u1", "https://evil.example"))).toBe(prod);
  });

  it("mobile : compte en prod → prod", async () => {
    prod.seed("landlords/u1", {id: "u1"});
    staging.seed("landlords/u1", {id: "u1"});
    expect(await dbForRequest(req("u1"))).toBe(prod);
  });

  it("mobile : compte uniquement en staging → staging", async () => {
    staging.seed("landlords/u2", {id: "u2"});
    expect(await dbForRequest(req("u2"))).toBe(staging);
  });

  it("mobile : compte absent → prod (fail-safe)", async () => {
    expect(await dbForRequest(req("u3"))).toBe(prod);
  });

  it("mobile : Origin vide traité comme absent", async () => {
    staging.seed("landlords/u2", {id: "u2"});
    expect(await dbForRequest(req("u2", ""))).toBe(staging);
  });
});
