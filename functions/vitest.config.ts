import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    // Ne ramasser que les sources TS : lib/ contient les copies CJS
    // compilées par tsc et ferait échouer vitest après un build.
    include: ['src/**/*.test.ts'],
    // Remplace FieldValue (firebase-admin/firestore) par le fake de la
    // FakeFirestore dans tous les tests.
    setupFiles: ['src/__tests__/helpers/setup_firestore_mock.ts'],
  },
});
