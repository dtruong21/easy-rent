/**
 * Setup vitest global (cf. `vitest.config.ts` → `setupFiles`).
 *
 * Le code source importe `FieldValue` depuis `firebase-admin/firestore`
 * (API modulaire). Les vrais sentinels (`serverTimestamp()`, `increment()`)
 * sont opaques pour la FakeFirestore : on les remplace par ses fakes, qui
 * sont résolus au write. `Timestamp` et le reste du module restent réels.
 */
import type * as FirestoreModule from "firebase-admin/firestore";
import {vi} from "vitest";

vi.mock("firebase-admin/firestore", async (importOriginal) => {
  const actual = await importOriginal<typeof FirestoreModule>();
  const {fakeFieldValue} = await import("./fake_firestore");
  return {...actual, FieldValue: fakeFieldValue};
});
