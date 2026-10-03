/**
 * cleanupExpiredAnon — purge des comptes anonymes expirés (BAILLAN-M1) et,
 * depuis OWASP-04, de leurs objets Storage `documents/{uid}/`.
 *
 * Avant ce correctif le cron supprimait Auth + Firestore mais PAS les fichiers :
 * un compte anonyme (création gratuite et illimitée) qui avait déposé des
 * objets de 50 Mio les laissait dans le bucket indéfiniment.
 */

import {Timestamp} from "firebase-admin/firestore";
import {beforeEach, describe, expect, it, vi} from "vitest";

import {cleanupExpiredAnonImpl} from "../scheduled/cleanup_expired_anon";

import {
  FakeAuthAdmin,
  FakeFirestore,
  FakeStorage,
  fakeAdminFirestoreHolder,
} from "./helpers/fake_firestore";

// Cf. purge_expired_receipts.test.ts pour le import() dynamique interne
// (le factory `vi.mock` est hoisted au-dessus des imports du fichier).
vi.mock("firebase-admin", async () => {
  const {makeFakeAdminModule} = await import("./helpers/fake_firestore");
  return makeFakeAdminModule();
});

let fakeDb: FakeFirestore;
let fakeStorage: FakeStorage;
let fakeAuth: FakeAuthAdmin;

const PAST = Timestamp.fromMillis(Date.now() - 24 * 60 * 60 * 1000);
const FUTURE = Timestamp.fromMillis(Date.now() + 24 * 60 * 60 * 1000);

function seedAnon(uid: string, anonExpiresAt: Timestamp) {
  fakeDb.seed(`landlords/${uid}`, {id: uid, isAnonymous: true, anonExpiresAt});
}

function run() {
  return cleanupExpiredAnonImpl(fakeDb as never, Timestamp.now());
}

beforeEach(() => {
  fakeDb = new FakeFirestore();
  fakeStorage = new FakeStorage();
  fakeAuth = new FakeAuthAdmin();
  fakeAdminFirestoreHolder.db = fakeDb;
  fakeAdminFirestoreHolder.storage = fakeStorage;
  fakeAdminFirestoreHolder.authAdmin = fakeAuth;
});

describe("cleanupExpiredAnon", () => {
  it("purge Auth, Firestore ET le dossier Storage d'un anonyme expiré", async () => {
    seedAnon("anon-expired", PAST);
    fakeDb.seed("investment_scenarios/s1", {landlordId: "anon-expired"});

    const res = await run();

    expect(res).toEqual({purged: 1, failed: 0});
    expect(fakeAuth.deletedUids).toEqual(["anon-expired"]);
    expect(fakeDb.peek("landlords/anon-expired")).toBeUndefined();
    expect(fakeDb.peek("investment_scenarios/s1")).toBeUndefined();
    expect(fakeStorage.deletedPrefixes).toEqual(["documents/anon-expired/"]);
  });

  it("le préfixe se termine par « / » (anon-1 ne purge pas anon-10)", async () => {
    seedAnon("anon-1", PAST);

    await run();

    const [prefix] = fakeStorage.deletedPrefixes;
    expect(prefix).toBe("documents/anon-1/");
    expect("documents/anon-10/x.pdf".startsWith(prefix)).toBe(false);
  });

  it("purge un dossier par compte expiré, et AUCUN autre", async () => {
    seedAnon("anon-a", PAST);
    seedAnon("anon-b", PAST);
    seedAnon("anon-still-valid", FUTURE);
    // Compte non anonyme expiré en apparence : ne doit jamais être touché.
    fakeDb.seed("landlords/real-user", {
      id: "real-user",
      isAnonymous: false,
      anonExpiresAt: PAST,
    });

    const res = await run();

    expect(res).toEqual({purged: 2, failed: 0});
    expect([...fakeStorage.deletedPrefixes].sort()).toEqual([
      "documents/anon-a/",
      "documents/anon-b/",
    ]);
    expect(fakeDb.peek("landlords/anon-still-valid")).toBeDefined();
    expect(fakeDb.peek("landlords/real-user")).toBeDefined();
    expect(fakeAuth.deletedUids).not.toContain("real-user");
    expect(fakeAuth.deletedUids).not.toContain("anon-still-valid");
  });

  it("échec de la purge Storage : le landlord reste pour le run suivant", async () => {
    seedAnon("anon-x", PAST);
    fakeStorage.deleteFilesError = new Error("gcs unavailable");

    const res = await run();

    expect(res).toEqual({purged: 0, failed: 1});
    // Le doc landlord est la clé de découverte du cron : le garder permet de
    // retenter (deleteUser renverra alors « user-not-found », toléré).
    expect(fakeDb.peek("landlords/anon-x")).toBeDefined();

    // Run suivant, Storage rétabli : Auth déjà supprimé, le reste est purgé.
    fakeStorage.deleteFilesError = null;
    fakeAuth.deleteUserError = {code: "auth/user-not-found"};

    const retry = await run();

    expect(retry).toEqual({purged: 1, failed: 0});
    expect(fakeStorage.deletedPrefixes).toEqual(["documents/anon-x/"]);
    expect(fakeDb.peek("landlords/anon-x")).toBeUndefined();
  });

  it("un compte en échec n'empêche pas la purge des suivants", async () => {
    seedAnon("anon-fail", PAST);
    seedAnon("anon-ok", PAST);
    const original = fakeStorage.bucket.bind(fakeStorage);
    vi.spyOn(fakeStorage, "bucket").mockImplementation(() => {
      const bucket = original();
      return {
        ...bucket,
        deleteFiles: (opts: {prefix: string}) =>
          opts.prefix === "documents/anon-fail/" ?
            Promise.reject(new Error("gcs unavailable")) :
            bucket.deleteFiles(opts),
      };
    });

    const res = await run();

    expect(res).toEqual({purged: 1, failed: 1});
    expect(fakeStorage.deletedPrefixes).toEqual(["documents/anon-ok/"]);
    expect(fakeDb.peek("landlords/anon-fail")).toBeDefined();
    expect(fakeDb.peek("landlords/anon-ok")).toBeUndefined();
  });

  it("échec réel de deleteUser : ni Storage ni Firestore touchés", async () => {
    seedAnon("anon-y", PAST);
    fakeAuth.deleteUserError = {code: "auth/internal-error"};

    const res = await run();

    expect(res).toEqual({purged: 0, failed: 1});
    expect(fakeStorage.deletedPrefixes).toEqual([]);
    expect(fakeDb.peek("landlords/anon-y")).toBeDefined();
  });

  it("aucun anonyme expiré : ne touche ni Storage ni Auth", async () => {
    seedAnon("anon-fresh", FUTURE);

    const res = await run();

    expect(res).toEqual({purged: 0, failed: 0});
    expect(fakeStorage.deletedPrefixes).toEqual([]);
    expect(fakeAuth.deletedUids).toEqual([]);
  });
});
