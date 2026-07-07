import {defineConfig} from "vitest/config";

// Config dédiée aux tests de Firestore Security Rules — exécutés contre
// l'émulateur via `npm run test:rules` (firebase emulators:exec). Séparée
// du run vitest par défaut (`npm test`), qui ne requiert AUCUN émulateur.
export default defineConfig({
  test: {
    include: ["rules-tests/**/*.test.ts"],
    // L'émulateur démarre en quelques secondes ; les assertions réseau
    // locales restent rapides mais on laisse de la marge en CI.
    testTimeout: 15000,
    hookTimeout: 30000,
  },
});
