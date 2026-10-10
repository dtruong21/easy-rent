import { defineConfig } from 'astro/config';

import sitemap from '@astrojs/sitemap';

import { normalizeServedPath } from './src/lib/urls.ts';

export default defineConfig({
  // URL canonique de production. Elle alimente les balises canonical et le
  // sitemap ; staging sert le même HTML, volontairement en noindex.
  site: 'https://baillan.com',

  // Français à la racine, sans préfixe : /en/* pourra s'ajouter plus tard
  // sans déplacer la moindre URL française.
  i18n: {
    defaultLocale: 'fr',
    locales: ['fr'],
    routing: { prefixDefaultLocale: false },
  },

  build: { format: 'file' },
  integrations: [
    sitemap({
      // `build.format: 'file'` fait par ailleurs router les pages via des
      // chemins finissant en `.html`/`/index.html` (cf. src/lib/urls.ts) —
      // en pratique cette version de @astrojs/sitemap lit les routes
      // logiques d'Astro plutôt que les fichiers de sortie, donc les URLs
      // sont déjà propres. On applique quand même `normalizeServedPath` ici
      // pour que le sitemap partage la même règle que `getCanonicalUrl`
      // (BaseLayout) : un seul endroit fait autorité, un changement futur de
      // l'intégration ne peut pas réintroduire silencieusement du `.html`
      // dans le sitemap.
      serialize(item) {
        const url = new URL(item.url);
        url.pathname = normalizeServedPath(url.pathname);
        return { ...item, url: url.href };
      },
    }),
  ],
});
