/**
 * OWASP-02 — `requireVerifiedUid` : les callables métier exigent un compte
 * « de confiance » (email vérifié, Google/Apple, ou anonyme confirmé).
 */
import type {CallableRequest, HttpsError} from "firebase-functions/v2/https";
import {beforeEach, describe, expect, it, vi} from "vitest";

import {requireVerifiedUid} from "../utils/callable_helpers";

import {
  FakeAuthAdmin,
  fakeAdminFirestoreHolder,
} from "./helpers/fake_firestore";

// Cf. expenses.test.ts pour la justification du import() dynamique interne.
vi.mock("firebase-admin", async () => {
  const {makeFakeAdminModule} = await import("./helpers/fake_firestore");
  return makeFakeAdminModule();
});

const UID = "user-1";

let fakeAuth: FakeAuthAdmin;

beforeEach(() => {
  fakeAuth = new FakeAuthAdmin();
  fakeAdminFirestoreHolder.authAdmin = fakeAuth;
});

function req(token: Record<string, unknown> | null): CallableRequest {
  return {
    data: {},
    auth: token ? {uid: UID, token: token as never, rawToken: ""} : undefined,
    rawRequest: {} as never,
  } as CallableRequest;
}

async function errorOf(p: Promise<unknown>): Promise<HttpsError> {
  try {
    await p;
  } catch (e) {
    return e as HttpsError;
  }
  throw new Error("expected the call to throw");
}

describe("requireVerifiedUid — comptes non anonymes (claims du token)", () => {
  it("non authentifié → unauthenticated", async () => {
    const err = await errorOf(requireVerifiedUid(req(null)));
    expect(err.code).toBe("unauthenticated");
  });

  it("email/mot de passe vérifié → uid (aucune lecture Admin Auth)", async () => {
    const spy = vi.spyOn(fakeAuth, "getUser");
    await expect(
      requireVerifiedUid(
        req({email_verified: true, firebase: {sign_in_provider: "password"}}),
      ),
    ).resolves.toBe(UID);
    expect(spy).not.toHaveBeenCalled();
  });

  it("★ email/mot de passe NON vérifié → failed-precondition / email_not_verified", async () => {
    const err = await errorOf(
      requireVerifiedUid(
        req({email_verified: false, firebase: {sign_in_provider: "password"}}),
      ),
    );
    expect(err.code).toBe("failed-precondition");
    expect(err.message).toBe("email_not_verified");
  });

  it("claim email_verified absent (fail-closed) → email_not_verified", async () => {
    const err = await errorOf(
      requireVerifiedUid(req({firebase: {sign_in_provider: "password"}})),
    );
    expect(err.code).toBe("failed-precondition");
    expect(err.message).toBe("email_not_verified");
  });

  it("token sans claim firebase du tout (fail-closed) → email_not_verified", async () => {
    const err = await errorOf(requireVerifiedUid(req({})));
    expect(err.message).toBe("email_not_verified");
  });

  it("★ Google compte pour vérifié, même sans email_verified", async () => {
    await expect(
      requireVerifiedUid(
        req({email_verified: false, firebase: {sign_in_provider: "google.com"}}),
      ),
    ).resolves.toBe(UID);
  });

  it("★ Apple compte pour vérifié, même sans email_verified", async () => {
    await expect(
      requireVerifiedUid(req({firebase: {sign_in_provider: "apple.com"}})),
    ).resolves.toBe(UID);
  });

  it("un provider quelconque non vérifié (ex. custom) reste refusé", async () => {
    const err = await errorOf(
      requireVerifiedUid(req({firebase: {sign_in_provider: "custom"}})),
    );
    expect(err.message).toBe("email_not_verified");
  });
});

describe("requireVerifiedUid — claim « anonymous » (confirmé côté Admin SDK)", () => {
  // Le claim `sign_in_provider` reste « anonymous » sur les tokens émis AVANT
  // un linkWithCredential/Provider : il ne prouve pas que le compte est
  // toujours anonyme. Sans cette confirmation, un compte upgradé en
  // email/mot de passe (finalizeAnonymousUpgrade ne vérifie pas l'email) et
  // jamais vérifié garderait un accès complet en conservant son token.
  const anonToken = {firebase: {sign_in_provider: "anonymous"}};

  it("★ anonyme pur (aucun provider lié) → autorisé (essai sans compte)", async () => {
    await expect(requireVerifiedUid(req(anonToken))).resolves.toBe(UID);
  });

  it("★ upgradé en email/mot de passe NON vérifié, token périmé → refusé", async () => {
    fakeAuth.providerDataByUid.set(UID, [{providerId: "password"}]);
    fakeAuth.emailVerifiedByUid.set(UID, false);
    const err = await errorOf(requireVerifiedUid(req(anonToken)));
    expect(err.code).toBe("failed-precondition");
    expect(err.message).toBe("email_not_verified");
  });

  it("upgradé en email/mot de passe puis vérifié → autorisé", async () => {
    fakeAuth.providerDataByUid.set(UID, [{providerId: "password"}]);
    fakeAuth.emailVerifiedByUid.set(UID, true);
    await expect(requireVerifiedUid(req(anonToken))).resolves.toBe(UID);
  });

  it("upgradé via Google → autorisé (provider de confiance)", async () => {
    fakeAuth.providerDataByUid.set(UID, [{providerId: "google.com"}]);
    await expect(requireVerifiedUid(req(anonToken))).resolves.toBe(UID);
  });

  it("upgradé via Apple → autorisé (provider de confiance)", async () => {
    fakeAuth.providerDataByUid.set(UID, [{providerId: "apple.com"}]);
    await expect(requireVerifiedUid(req(anonToken))).resolves.toBe(UID);
  });

  it("échec de la lecture Admin Auth → fail-closed (internal)", async () => {
    fakeAuth.getUserError = {code: "auth/internal-error"};
    const err = await errorOf(requireVerifiedUid(req(anonToken)));
    expect(err.code).toBe("internal");
  });

  it("compte introuvable (supprimé) → unauthenticated", async () => {
    fakeAuth.getUserError = {code: "auth/user-not-found"};
    const err = await errorOf(requireVerifiedUid(req(anonToken)));
    expect(err.code).toBe("unauthenticated");
  });
});
