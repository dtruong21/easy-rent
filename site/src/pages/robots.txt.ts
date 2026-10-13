// site/src/pages/robots.txt.ts
//
// robots.txt dépend de l'environnement : `SITE_ENV=staging` est posé par
// l'étape "Build marketing site" de .github/workflows/deploy.yml sur
// `develop`. La cible d'hébergement `marketing-stage` sert déjà un
// `X-Robots-Tag: noindex, nofollow` sur toutes les réponses (firebase.json) ;
// ce robots.txt est une deuxième ceinture, pour qu'un explorateur ne perde
// même pas son temps à récupérer les pages avant de lire le header.
import type { APIRoute } from 'astro';

const isStaging = import.meta.env.SITE_ENV === 'staging';

export const GET: APIRoute = ({ site }) => {
  const body = isStaging
    ? 'User-agent: *\nDisallow: /\n'
    : `User-agent: *\nAllow: /\n\nSitemap: ${new URL('sitemap-index.xml', site).href}\n`;
  return new Response(body, {
    headers: { 'Content-Type': 'text/plain; charset=utf-8' },
  });
};
