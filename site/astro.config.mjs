import { defineConfig } from 'astro/config';

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
});
