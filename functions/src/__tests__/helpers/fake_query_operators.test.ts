import {beforeEach, describe, expect, it} from "vitest";

import {FakeFirestore} from "./fake_firestore";

describe("FakeQuery — opérateurs de comparaison", () => {
  let db: FakeFirestore;

  beforeEach(() => {
    db = new FakeFirestore();
    db.seed("receipts/r-past", {id: "r-past", retentionUntil: new Date(1_000)});
    db.seed("receipts/r-future", {
      id: "r-future",
      retentionUntil: new Date(9_999_999_999_999),
    });
    db.seed("receipts/r-none", {id: "r-none"}); // pas de retentionUntil
  });

  it("<= retourne les docs dont le champ est <= la valeur (champ absent exclu)", async () => {
    const now = new Date(5_000);
    const snap = await db
      .collection("receipts")
      .where("retentionUntil", "<=", now)
      .get();
    const ids = snap.docs.map((d) => d.id).sort();
    expect(ids).toEqual(["r-past"]);
  });

  it("== reste une égalité stricte inchangée", async () => {
    const snap = await db
      .collection("receipts")
      .where("id", "==", "r-future")
      .get();
    expect(snap.docs.map((d) => d.id)).toEqual(["r-future"]);
  });

  it("lève sur un opérateur non supporté", async () => {
    expect(() =>
      db.collection("receipts").where("id", "array-contains", "x"),
    ).toThrow();
  });
});
