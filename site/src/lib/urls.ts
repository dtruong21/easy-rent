// site/src/lib/urls.ts
//
// astro.config.mjs fixe `build.format: 'file'` pour coller au `cleanUrls: true`
// de firebase.json (build : fichiers .html plats ; diffusion : extension
// retirée par Firebase Hosting). Astro construit donc `Astro.url.pathname`
// à partir du nom de fichier de sortie : `/index.html` pour la racine,
// `/faq.html` pour toute autre route — jamais le chemin réellement servi.
//
// `normalizeServedPath` annule cet effet pour retrouver l'URL telle que les
// visiteurs et les moteurs la voient. Utilisé par BaseLayout (canonical,
// og:url) et, plus tard, par le générateur de sitemap.xml — un seul endroit
// pour cette règle évite qu'ils divergent.
export function normalizeServedPath(pathname: string): string {
  if (pathname.endsWith('/index.html')) {
    return pathname.slice(0, -'index.html'.length);
  }
  if (pathname.endsWith('.html')) {
    return pathname.slice(0, -'.html'.length);
  }
  return pathname;
}

export function getCanonicalUrl(pathname: string, site: URL | undefined): string {
  return new URL(normalizeServedPath(pathname), site).href;
}

// URL de l'app web (PWA Flutter), distincte du site vitrine construit ici.
//
// Dépend de l'environnement, même mécanisme que `robots.txt.ts` : la vitrine est
// un build statique servi sur DEUX hôtes (prod `baillan.com`, staging
// `stage.baillan.com`). `SITE_ENV=staging` est posé par l'étape « Build marketing
// site » de `.github/workflows/deploy.yml` sur `develop` ; sans lui (build prod),
// on retombe sur l'app de prod. Sans ce discriminant, la vitrine de staging
// enverrait ses visiteurs vers l'app de PROD (« Ouvrir l'app », /signup, footer…).
export const isStaging = import.meta.env.SITE_ENV === 'staging';

export const appUrl = isStaging
  ? 'https://app.staging.baillan.com'
  : 'https://app.baillan.com';
