import type {Firestore} from "firebase-admin/firestore";
import {describe, expect, it} from "vitest";

import {
  SANDBOX_ALLOWLIST_DOC,
  parseSandboxAllowlist,
  readSandboxAllowlist,
  readSandboxAllowlistOrEmpty,
} from "../utils/sandbox_allowlist";

import {FakeFirestore} from "./helpers/fake_firestore";

const asDb = (db: unknown) => db as Firestore;

/** Base dont toute lecture échoue (réseau, permissions…). */
const failingDb = asDb({
  doc: () => ({get: () => Promise.reject(new Error("unavailable"))}),
});

describe("parseSandboxAllowlist", () => {
  it("doc absent ou vide → aucun uid", () => {
    expect([...parseSandboxAllowlist(undefined)]).toEqual([]);
    expect([...parseSandboxAllowlist({})]).toEqual([]);
  });

  it("uids pas un tableau → aucun uid", () => {
    expect([...parseSandboxAllowlist({uids: "u1"})]).toEqual([]);
  });

  it("ne garde que des chaînes non vides, sans espaces autour", () => {
    const set = parseSandboxAllowlist({uids: ["u1", " u2 ", "", 42, null]});
    expect([...set].sort()).toEqual(["u1", "u2"]);
  });
});

describe("readSandboxAllowlist", () => {
  it("lit les uids du document prod", async () => {
    const db = new FakeFirestore();
    db.seed(SANDBOX_ALLOWLIST_DOC, {uids: ["review-demo"]});
    const set = await readSandboxAllowlist(asDb(db));
    expect(set.has("review-demo")).toBe(true);
  });

  it("document absent → ensemble vide", async () => {
    const set = await readSandboxAllowlist(asDb(new FakeFirestore()));
    expect(set.size).toBe(0);
  });

  it("lecture en échec → lève (l'appelant décide)", async () => {
    await expect(readSandboxAllowlist(failingDb)).rejects.toThrow("unavailable");
  });
});

describe("readSandboxAllowlistOrEmpty", () => {
  it("lecture en échec → ensemble vide, sans lever (fail-closed)", async () => {
    const set = await readSandboxAllowlistOrEmpty(failingDb, "test");
    expect(set.size).toBe(0);
  });
});
