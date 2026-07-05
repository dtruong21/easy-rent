import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    // Ne ramasser que les sources TS : lib/ contient les copies CJS
    // compilées par tsc et ferait échouer vitest après un build.
    include: ['src/**/*.test.ts'],
  },
});
