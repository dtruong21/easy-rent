export const meta = {
  name: 'seo-audit',
  description: 'Audit SEO complet du PWA Flutter Web (Baillan) : 5 dimensions en parallèle → synthèse stratégie + artefacts (index.html, robots, sitemap, JSON-LD)',
  whenToUse: 'Avant un lancement public, après une refonte de la landing/marketing, ou pour planifier l\'acquisition organique.',
  phases: [
    { title: 'Audit', detail: '5 agents parallèles : crawlabilité technique, meta on-page, robots/sitemap/infra, mots-clés/concurrence, contenu/perf/i18n' },
    { title: 'Synthèse', detail: 'fusionne en une stratégie priorisée + rédige docs/SEO.md + produit les artefacts exacts (head, JSON-LD, robots, sitemap)' },
  ],
}

// Contexte partagé injecté dans chaque prompt : le fait structurant du produit.
const CONTEXT = `Produit : **Baillan** (nom repo/tech : EasyRent) — PWA française de gestion locative, **Flutter Web + Firebase Hosting** (projet easy-rent-54cd4).

FAIT STRUCTURANT : Flutter Web rend en **CanvasKit** → toute l'UI (dont le copy de la landing) est peinte dans un <canvas>. **Les crawlers n'indexent pas le canvas.** Aujourd'hui, pour Google, chaque page publique ≈ page vide + une seule <meta description>.

Faits repo (à VÉRIFIER dans le code, ne pas supposer) :
- Hosting Firebase, rewrite SPA \`** → /index.html\`. Firebase sert les fichiers statiques existants AVANT le rewrite → web/robots.txt + web/sitemap.xml servis directement.
- \`main\`→prod (channel live, <projet>.web.app + domaine custom À VENIR), \`develop\`→**staging** (channel URL type easy-rent-54cd4--staging-*.web.app). Les URLs staging/preview **NE DOIVENT PAS être indexées**.
- App **bilingue FR/EN (FEAT-043)** mais locale = choix runtime, **pas dans l'URL** (pas de /fr /en). Donc hreflang par-URL ne s'applique pas tel quel — NE PAS fabriquer de hreflang bidon. Langue primaire = français.
- \`web/index.html\` contient des <script> de boot délicats (nettoyage SW + cache-repair, FEAT-019) — NE JAMAIS les retirer/réordonner.
- Build avec \`--pwa-strategy=none\` (pas de service worker). Contenu légal (loi 89-462, quittances) reste FR.
- Le copy landing/faq est désormais dans lib/l10n/app_fr.arb / app_en.arb (clés landing*, faq*, etc.).

Lis d'abord docs/state/INDEX.md + ROUTES.md avant de grep. Le domaine custom est TBD → tout ce qui est URL (canonical/OG/sitemap) doit être PARAMÉTRÉ avec un placeholder clair.`

const FINDINGS_SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: {
    dimension: { type: 'string' },
    crawlerImpact: { type: 'string', description: 'Ce qu\'un crawler voit / rate sur cette dimension aujourd\'hui' },
    findings: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false,
        properties: {
          issue: { type: 'string' },
          severity: { type: 'string', enum: ['critical', 'high', 'medium', 'low'] },
          evidence: { type: 'string', description: 'Fichier/ligne ou fait précis' },
          recommendation: { type: 'string' },
          effort: { type: 'string', enum: ['quick-win', 'medium', 'architectural'] },
        },
        required: ['issue', 'severity', 'recommendation', 'effort'],
      },
    },
    draftArtifacts: { type: 'string', description: 'Tout brouillon concret utile à la synthèse (bouts de <head>, JSON-LD, robots, sitemap, requêtes clés) — texte brut' },
    notes: { type: 'string' },
  },
  required: ['dimension', 'crawlerImpact', 'findings'],
}

const SYNTH_SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: {
    crawlerSeesToday: { type: 'string', description: 'Une phrase franche sur ce qu\'un crawler voit aujourd\'hui' },
    docPath: { type: 'string', description: 'Chemin du doc stratégie écrit (docs/SEO.md)' },
    artifacts: {
      type: 'object', additionalProperties: false,
      properties: {
        indexHtmlHead: { type: 'string', description: 'Bloc EXACT à insérer dans <head> (canonical, OG, Twitter, robots meta, title/description enrichis) + note où <html lang> doit passer' },
        jsonLd: { type: 'string', description: 'Bloc(s) <script type="application/ld+json"> (Organization, SoftwareApplication, WebSite)' },
        staticContentBlock: { type: 'string', description: 'Bloc HTML statique crawlable (headings + copy réel + liens internes) à mettre en HAUT de <body>, avant les scripts de boot' },
        robotsProd: { type: 'string' },
        robotsStaging: { type: 'string' },
        sitemap: { type: 'string' },
        firebaseHeaderSnippet: { type: 'string', description: 'Header(s) firebase.json éventuels (ex. X-Robots-Tag noindex staging, cache court robots/sitemap) + où les insérer' },
      },
      required: ['indexHtmlHead', 'jsonLd', 'staticContentBlock', 'robotsProd', 'robotsStaging', 'sitemap'],
    },
    backlog: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false,
        properties: { title: { type: 'string' }, priority: { type: 'string', enum: ['P0', 'P1', 'P2'] }, effort: { type: 'string' }, rationale: { type: 'string' } },
        required: ['title', 'priority', 'effort'],
      },
    },
    architecturalDecision: { type: 'string', description: 'La décision crawlabilité (enrichir index.html vs site statique séparé) + recommandation argumentée' },
    launchChecklist: { type: 'array', items: { type: 'string' } },
    summary: { type: 'string' },
  },
  required: ['crawlerSeesToday', 'artifacts', 'backlog', 'architecturalDecision', 'summary'],
}

const DIMENSIONS = [
  {
    key: 'technical-crawlability',
    prompt: `Dimension **crawlabilité technique**. Audite : rendu CanvasKit vs DOM, dépendance JS, rewrite SPA, canonical/redirections, indexabilité des channels staging, mobile-friendliness, et l'implication Core Web Vitals du Flutter Web (poids main.dart.js + canvaskit.wasm, LCP/FID/CLS). Lis web/index.html, firebase.json, .github/workflows/deploy.yml, docs/state/ROUTES.md. Dis PLAINEMENT ce qu'un crawler voit aujourd'hui et pourquoi. Distingue ce qui est inhérent au Flutter Web de ce qui est corrigeable.`,
  },
  {
    key: 'onpage-meta',
    prompt: `Dimension **meta on-page & données structurées**. Audite title/description/OG/Twitter/canonical/<html lang>/robots meta et l'ABSENCE de JSON-LD. Récupère le VRAI copy de marque dans lib/l10n/app_fr.arb (clés landing*, faq*) + web/manifest.json. Produis en draftArtifacts : un <head> enrichi EXACT (title + meta description riches en mots-clés FR "gestion locative", "quittance de loyer", "suivi des loyers", "régularisation des charges"), Open Graph + Twitter Card complets (URLs paramétrées, domaine TBD), et des blocs JSON-LD (Organization, SoftwareApplication avec applicationCategory/offers, WebSite). Propose aussi le bloc HTML statique crawlable (headings h1/h2 + copy réel + liens) à injecter en haut de <body>.`,
  },
  {
    key: 'infra-robots-sitemap',
    prompt: `Dimension **infra : robots.txt / sitemap.xml / headers hosting**. Il n'existe ni robots.txt ni sitemap.xml. Produis en draftArtifacts : un web/robots.txt PROD (allow + ligne Sitemap, domaine paramétré), un robots.txt STAGING (Disallow: / total), un web/sitemap.xml (URLs publiques uniquement d'après docs/state/ROUTES.md — landing, /faq, pages légales publiques ; PAS les routes derrière auth ; domaine paramétré placeholder). Vérifie dans firebase.json que les fichiers statiques passent avant le rewrite SPA, et propose les headers utiles (X-Robots-Tag noindex sur le channel staging, cache court sur robots/sitemap). Explique la bascule domaine (le seul endroit à changer quand le domaine custom arrive).`,
  },
  {
    key: 'keyword-competitive',
    prompt: `Dimension **mots-clés & concurrence** (utilise WebSearch). Cartographie le paysage de recherche FR de la gestion locative pour bailleurs particuliers : intentions ("logiciel gestion locative", "quittance de loyer gratuite/modèle", "gestion locative en ligne", "suivi des loyers", "régularisation charges locatives", "logiciel bailleur"), volume/difficulté qualitatifs, et le positionnement des concurrents (Rentila, Gererseul, Smovin, Qlower, Jelouebien, etc. — vérifie lesquels existent). Traduis en : positionnement recommandé pour Baillan (mobile-first, simple, pas cher), 5-10 mots-clés cibles priorisés, et des opportunités de contenu (pages/articles) pour ranker sur du non-marque. Mets tes trouvailles dans findings + draftArtifacts.`,
  },
  {
    key: 'content-perf-i18n',
    prompt: `Dimension **contenu crawlable, performance & i18n-SEO**. (1) Crawlabilité du contenu : compare les 3 options (enrichir index.html avec bloc statique ; site marketing statique séparé à la racine + app en /app ; prerendering) — coût/bénéfice pour une équipe solo qui lance bientôt ; recommande une séquence. (2) i18n-SEO : l'app est bilingue mais la locale est runtime (pas dans l'URL) → explique pourquoi hreflang classique ne s'applique pas, et ce qu'il faudrait (locale dans l'URL) si le ranking par langue devient un objectif ; NE fabrique PAS de hreflang bidon. (3) Perf : leviers réalistes pour un Flutter Web (preload/bootstrap, webp, subsetting polices) vs limites inhérentes. Mets le tout en findings + une reco claire en draftArtifacts.`,
  },
]

phase('Audit')
const results = (await parallel(DIMENSIONS.map((d) => () =>
  agent(`${CONTEXT}\n\n---\n\n${d.prompt}`, {
    label: `audit:${d.key}`,
    phase: 'Audit',
    agentType: d.key === 'keyword-competitive' ? 'general-purpose' : 'seo-specialist',
    schema: FINDINGS_SCHEMA,
  })
))).filter(Boolean)

const totalFindings = results.reduce((s, r) => s + (r.findings ? r.findings.length : 0), 0)
log(`Audit : ${results.length}/${DIMENSIONS.length} dimensions, ${totalFindings} findings`)

phase('Synthèse')
const synthPrompt = `${CONTEXT}\n\n---\n\nTu es l'agent de SYNTHÈSE SEO. Voici les résultats des 5 dimensions d'audit :\n\n${JSON.stringify(results, null, 2)}\n\nÀ faire :\n1. **Écris docs/SEO.md** : état actuel, ce qu'un crawler voit aujourd'hui, backlog priorisé (quick wins → architectural), la décision crawlabilité (enrichir index.html vs site statique séparé) AVEC recommandation, notes mots-clés/positionnement, et une checklist de lancement (Search Console, vérif domaine, ping sitemap, staging noindex). Doc en français, concis, actionnable.\n2. **Produis les artefacts EXACTS prêts à appliquer** (l'orchestrateur les posera lui-même dans les fichiers délicats) : bloc <head> enrichi, JSON-LD, bloc HTML statique crawlable pour <body>, web/robots.txt (prod ET staging), web/sitemap.xml, et le snippet de header firebase.json éventuel. Dédoublonne et réconcilie les brouillons des 5 dimensions. Utilise le VRAI copy de marque (lis app_fr.arb si besoin). URLs paramétrées (domaine TBD — placeholder clair type https://VOTRE-DOMAINE).\n\nNE touche PAS web/index.html ni firebase.json (l'orchestrateur applique). Tu PEUX écrire docs/SEO.md. Retourne le tout selon le schéma.`

const synth = await agent(synthPrompt, { label: 'synth:seo', phase: 'Synthèse', agentType: 'seo-specialist', schema: SYNTH_SCHEMA })

return { dimensions: results.map((r) => ({ dimension: r.dimension, crawlerImpact: r.crawlerImpact, findings: (r.findings || []).length })), synthesis: synth }
