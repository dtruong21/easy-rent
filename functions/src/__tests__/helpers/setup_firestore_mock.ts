/**
 * Setup vitest global (cf. `vitest.config.ts` → `setupFiles`).
 *
 * Le code source importe `FieldValue` depuis `firebase-admin/firestore`
 * (API modulaire). Les vrais sentinels (`serverTimestamp()`, `increment()`)
 * sont opaques pour la FakeFirestore : on les remplace par ses fakes, qui
 * sont résolus au write. `Timestamp` et le reste du module restent réels.
 *
 * `getFirestore` est aussi mocké : la base nommée (`staging`) renvoie la
 * FakeFirestore dédiée `fakeStagingFirestoreHolder.db` — c'est le chemin
 * qu'emprunte `dbForRequest` pour un appel mobile dont le compte vit en
 * staging. La base `(default)` passe, elle, par `admin.firestore()`.
 */
import type * as FirestoreModule from "firebase-admin/firestore";
import {vi} from "vitest";

vi.mock("firebase-admin/firestore", async (importOriginal) => {
  const actual = await importOriginal<typeof FirestoreModule>();
  const {fakeFieldValue, fakeStagingFirestoreHolder} = await import(
    "./fake_firestore"
  );
  return {
    ...actual,
    FieldValue: fakeFieldValue,
    // Base nommée (staging) → FakeFirestore dédiée ; la prod passe par
    // `admin.firestore()`, mockée ailleurs.
    getFirestore: () => fakeStagingFirestoreHolder.db,
  };
});
