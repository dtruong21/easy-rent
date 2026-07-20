# SEO — Baillan (PWA Flutter Web + Firebase Hosting)

> Synthèse de l'audit SEO (FEAT-049). Source de vérité pour l'implémentation.
> **Fait structurant** : l'UI est rendue en **CanvasKit** (peinte dans un `<canvas>`).
> Les crawlers n'indexent PAS le canvas → aujourd'hui, pour Google, chaque page
> publique ≈ une page quasi vide partageant le même titre et la même description.

**Placeholder domaine** : partout ci-dessous, remplacer `https://VOTRE-DOMAINE`
par le domaine custom une fois attribué. **Interim** possible avant le domaine
custom = `https://easy-rent-54cd4.web.app` (canal live, défaut de `Env.publicAppUrl`).
Ne JAMAIS mettre une URL de canal staging (`*--staging-*.web.app`) dans
canonical / OG / sitemap.

> **⚙️ État d'application (FEAT-049, {2026-07-08})** — Les quick-wins P0 sont
> **APPLIQUÉS** sur la branche `feature/049-seo` avec l'URL **interim
> `https://easy-rent-54cd4.web.app`** (les artefacts §4 gardent `VOTRE-DOMAINE`
> à titre de gabarit). Fichiers touchés : `web/index.html` (head enrichi + JSON-LD
> + bloc statique + `<html lang="fr">`), `web/robots.txt`, `web/robots.staging.txt`,
> `web/sitemap.xml`, `firebase.json` (headers + ignore de `robots.staging.txt`),
> `.github/workflows/deploy.yml` (étape noindex staging).
> ✅ **Domaine custom branché (2026-07-20)** : le canonique est **`baillan.com`**
> (apex ; `www.baillan.com` redirige). Substitution faite dans `web/index.html`,
> `web/robots.txt` (ligne Sitemap), chaque `<loc>` de `web/sitemap.xml`,
> `Env.publicAppUrl` et `WEB_APP_BASE_URL` (Stripe).
> ⚠️ Ne JAMAIS remplacer `easy-rent-54cd4` dans `lib/firebase_options.dart` /
> `firebase.json` : ce sont les identifiants du **projet Firebase** (projectId,
> authDomain, storageBucket), pas le domaine public. Options B/C restent à faire (P2).

---

## 1. Ce qu'un crawler voit aujourd'hui

Toutes les URLs publiques (`/`, `/faq`, `/privacy`, `/terms`, `/delete-account`,
`/simulator`) sont réécrites vers le **même** `index.html` (rewrite Firebase
`** → /index.html`). Ce document ne contient **aucun texte de contenu** :

- `<title>Baillan.</title>` (8 caractères, zéro mot-clé) — identique pour toutes les URLs.
- Une seule `<meta name="description">` de marque (« Tenir registre. En cas de doute… »),
  identique pour toutes les URLs, sans tête de requête (« gestion locative », « quittance »…).
- Un `<body>` qui ne porte que **deux `<script>` de boot** (nettoyage SW + cache-repair
  FEAT-019) — **aucun H1, aucun paragraphe, aucun lien**.
- Le vrai copy (landing, FAQ, mentions) est peint dans le `<canvas>` par CanvasKit.
  Googlebot exécute le JS mais extrait le texte du **DOM**, pas des pixels d'un canvas.
  L'arbre sémantique Flutter (`flt-semantics`) n'est construit qu'à la demande d'une
  techno d'assistance → reste **vide** pour un crawler.
- **Aucun** `robots.txt`, **aucun** `sitemap.xml`, **aucun** `canonical`, **aucune**
  balise Open Graph / Twitter, **aucun** JSON-LD, `<html>` **sans** `lang`.
- Les canaux **staging** (`develop` → `*--staging-*.web.app`) servent le **même
  artefact** que la prod, **sans noindex** → indexables s'ils fuitent.

**En une phrase** : pour Google, Baillan est aujourd'hui une seule page quasi vide,
non différenciée par route, avec zéro pilotage de crawl et un partage social vide.

---

## 2. Décision crawlabilité (le point qui débloque tout)

Trois stratégies possibles. **Le blocage racine (contenu dans le canvas) n'est
PAS corrigeable par de la config** — il faut exposer du HTML crawlable.

| Option | Description | Coût | Ce qu'on gagne | Verdict |
|---|---|---|---|---|
| **A — Enrichir `index.html`** | `<head>` riche + bloc HTML statique dans `<body>` + robots + sitemap + noindex staging | Faible (~0,5 j) | Métadonnées + **un seul** jeu de copy (la home). Toutes les routes partagent le même `index.html` → **pas** de meta/contenu par-route | ✅ **MAINTENANT** |
| **B — Site marketing statique séparé** | Pages HTML pré-rendues à la racine (landing/FAQ/outils/guides), app Flutter sous `/app` ou sous-domaine | Moyen/élevé (base-href, liens routeur, redirect auth, domaines OAuth, `start_url` manifest, pipeline contenu) | **Seul** moyen d'avoir du contenu crawlable **par page**, de bons Core Web Vitals, et une vraie i18n-SEO (locale dans l'URL) | ⏭️ **quand le SEO devient un canal de croissance** |
| **C — Prerendering / dynamic rendering** | Snapshot du DOM rendu, ou HTML servi aux bots | — | **RIEN** : CanvasKit peint dans un canvas → le snapshot est **vide**. Le dynamic rendering = ré-author du contenu à la main = l'Option B déguisée, en plus fragile, flaggé « contournement » par Google | ❌ **à écarter** |

### Recommandation

1. **Maintenant (avant lancement) — Option A.** Injecter dans `index.html` un `<head>`
   enrichi (title/description/canonical/OG/Twitter/robots/JSON-LD), un **bloc HTML
   statique crawlable** en tête de `<body>` (H1 + copy réel + liens internes), et poser
   `web/robots.txt` + `web/sitemap.xml`. Risque nul tant qu'on **n'AJOUTE** que du markup
   dans `<head>` et en tête de `<body>` **sans toucher ni réordonner les deux scripts de
   boot FEAT-019**. Gain immédiat : partage social propre, plomberie SEO en place, un
   minimum de contenu indexable pour la home.
2. **Au lancement.** Brancher le domaine custom → remplacer tous les `https://VOTRE-DOMAINE`,
   soumettre le sitemap en Search Console, activer le noindex staging.
3. **Quand le SEO devient un canal de croissance — Option B.** C'est le SEUL levier qui
   débloque réellement le contenu crawlable **par page** (pages-outils, guides) et une
   i18n-SEO réelle. À ce moment-là seulement, les JSON-LD FAQPage / per-route deviennent
   pleinement légitimes.

> ⚠️ **Cloaking.** Le bloc statique (Option A) est une **mitigation**, pas une vraie
> solution. Le texte injecté DOIT correspondre à ce que voit l'utilisateur (c'est le cas :
> copy réel de la landing + description honnête du produit). On utilise la technique
> a11y « visually-hidden » (`clip`), **jamais** `display:none` (dévalué). Ne pas gonfler
> ce bloc avec du texte que l'UI ne montre pas.

---

## 3. Backlog priorisé

### P0 — Avant lancement (quick-wins, zéro risque archi)

| # | Action | Effort |
|---|---|---|
| 1 | `<html lang="fr">` | quick-win |
| 2 | `<title>` + `<meta description>` enrichis (mots-clés tête) | quick-win |
| 3 | `<link rel="canonical">` auto-référent | quick-win |
| 4 | Open Graph + Twitter Card (+ image 1200×630) | quick-win |
| 5 | JSON-LD Organization + SoftwareApplication + WebSite | quick-win |
| 6 | `web/robots.txt` (prod) + `web/sitemap.xml` | quick-win |
| 7 | Bloc HTML statique crawlable en tête de `<body>` | medium |
| 8 | **noindex staging** (swap `robots.staging.txt` au build, gated `APP_ENV=dev`) | medium |
| 9 | Cache-Control court sur `/robots.txt` + `/sitemap.xml` (firebase.json) | quick-win |

### P1 — Au lancement / court terme

| # | Action | Effort |
|---|---|---|
| 10 | Brancher domaine custom → substituer `VOTRE-DOMAINE` partout (head + robots + sitemap) | medium |
| 11 | Search Console : vérif domaine, soumettre sitemap, Inspection d'URL | quick-win |
| 12 | ✅ Image OG dédiée `og-image-1200x630.png` (« B » paraphe + wordmark + « Tenir registre. » sur fond #1B1A17). Générée par `scripts/generate-og-image.sh` (source `scripts/og-image.svg`, rendu rsvg-convert). | quick-win |
| 13 | Auto-héberger la police serif en woff2 sous-ensemblé (retire la dépendance fonts.gstatic.com, gagne du LCP) | medium |
| 14 | `<link rel="preload">` boot (flutter_bootstrap.js, main.dart.js, canvaskit.wasm) | medium |

### P2 — Quand le SEO devient un canal (architectural)

| # | Action | Effort |
|---|---|---|
| 15 | **Option B** : socle de pages HTML statiques/pré-rendues (landing + FAQ + pages-outils + guides) servi avant le rewrite SPA | architectural |
| 16 | JSON-LD FAQPage sur une `/faq` pré-rendue (Q/R AUSSI visibles dans le DOM) | medium |
| 17 | Pages-outils lead-gen : /outils/quittance-de-loyer, /outils/simulateur-rentabilite, /outils/regularisation-charges | architectural |
| 18 | i18n-SEO réelle (locale dans l'URL /fr /en + hreflang réciproque) — **uniquement** sur la couche statique | architectural |

---

## 4. Artefacts prêts à appliquer

> ⚠️ Ne JAMAIS retirer/réordonner les deux `<script>` de boot FEAT-019
> (`web/index.html` lignes 46-85 et 96-153). Tous les ajouts vont dans `<head>`
> (avant le 1er script) ou en **tout début** de `<body>` (avant le script de cache-repair).

### 4.1 `<head>` enrichi

- Ligne 2 : `<html>` → `<html lang="fr">`
- Remplacer la `<meta name="description">` existante (ligne 21) et le `<title>` (ligne 37).
- Ajouter le reste juste après le `<title>` / `<link rel="manifest">`, **avant** le
  `<script>` de nettoyage SW (ligne 46).

```html
<title>Baillan — Gestion locative &amp; quittances de loyer pour bailleurs</title>
<meta name="description" content="Baillan : la gestion locative simple pour bailleurs particuliers. Quittances de loyer conformes (loi 1989), suivi des loyers, charges et régularisation, simulateur d'investissement. Gratuit, données en Europe.">

<!-- Robots : index,follow en PROD. En STAGING, l'étape CI (APP_ENV=dev) remplace
     "index, follow" par "noindex, nofollow" (cf. §4.6) — ne jamais laisser noindex en prod. -->
<meta name="robots" content="index, follow">
<link rel="canonical" href="https://VOTRE-DOMAINE/">

<!-- Open Graph -->
<meta property="og:type" content="website">
<meta property="og:site_name" content="Baillan">
<meta property="og:title" content="Baillan — Gestion locative & quittances de loyer pour bailleurs">
<meta property="og:description" content="Quittances conformes (loi du 6 juillet 1989), suivi des loyers et des retards, régularisation des charges et simulateur d'investissement locatif. Simple, gratuit, données en Europe.">
<meta property="og:url" content="https://VOTRE-DOMAINE/">
<meta property="og:locale" content="fr_FR">
<meta property="og:locale:alternate" content="en_US">
<!-- Image OG en PNG 1200x630 (PAS webp — plusieurs scrapers sociaux ne le lisent pas).
     Asset dédié : régénérable via scripts/generate-og-image.sh (source scripts/og-image.svg). -->
<meta property="og:image" content="https://VOTRE-DOMAINE/icons/og-image-1200x630.png">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="Baillan — Tenir registre.">

<!-- Twitter Card -->
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="Baillan — Gestion locative & quittances de loyer">
<meta name="twitter:description" content="Quittances conformes, suivi des loyers, régularisation des charges et simulateur d'investissement. Simple, gratuit, données en Europe.">
<meta name="twitter:image" content="https://VOTRE-DOMAINE/icons/og-image-1200x630.png">
```

### 4.2 JSON-LD (dans `<head>`)

```html
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "Organization",
  "name": "Baillan",
  "url": "https://VOTRE-DOMAINE/",
  "logo": "https://VOTRE-DOMAINE/icons/Icon-512.png",
  "slogan": "Tenir registre.",
  "description": "Outil de gestion locative pour bailleurs particuliers : quittances de loyer, suivi des loyers, régularisation des charges et simulateur d'investissement.",
  "areaServed": "FR",
  "email": "daki.tle.26@gmail.com"
}
</script>
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  "name": "Baillan",
  "url": "https://VOTRE-DOMAINE/",
  "applicationCategory": "BusinessApplication",
  "applicationSubCategory": "Property Management",
  "operatingSystem": "Web, iOS, Android",
  "inLanguage": ["fr", "en"],
  "description": "Gestion locative pour bailleurs particuliers : biens, locataires et baux, suivi des loyers et des retards, quittances de loyer conformes à la loi du 6 juillet 1989, registre des dépenses, régularisation annuelle des charges et simulateur d'investissement locatif.",
  "offers": {
    "@type": "Offer",
    "price": "0",
    "priceCurrency": "EUR",
    "availability": "https://schema.org/InStock"
  },
  "featureList": [
    "Quittances de loyer conformes (loi n° 89-462)",
    "Suivi des loyers et détection des retards",
    "Régularisation annuelle des charges",
    "Registre des dépenses (décret 87-713)",
    "Simulateur d'investissement locatif (rendement, cash-flow, coût du crédit)"
  ],
  "publisher": { "@type": "Organization", "name": "Baillan" }
}
</script>
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "WebSite",
  "name": "Baillan",
  "url": "https://VOTRE-DOMAINE/",
  "inLanguage": "fr-FR",
  "publisher": { "@type": "Organization", "name": "Baillan" }
}
</script>
```

> **FAQPage** : à réserver à une `/faq` **pré-rendue** (Option B), où les 20 Q/R sont
> AUSSI visibles dans le DOM — sinon Google rejette le balisage comme non visible.
> Source du contenu : `lib/features/support/presentation/faq_page.dart`. Bloc modèle en
> annexe (§7).

### 4.3 Bloc HTML statique crawlable (tout début de `<body>`, AVANT le script cache-repair)

Copy sourcée de `lib/l10n/app_fr.arb` (clés `landing*`) + description honnête des piliers
produit. Flutter monte par-dessus au boot ; le crawler l'a déjà lu.

```html
<div id="seo-static" style="position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0);white-space:nowrap;">
  <h1>Baillan — Tenir registre. La gestion locative simple pour les bailleurs.</h1>
  <p>Simulez votre prochain investissement locatif, ou gérez le registre de vos biens : baux, quittances, échéances. En cas de doute, sortez le registre.</p>
  <h2>Quittances de loyer conformes</h2>
  <p>Générez des quittances de loyer numérotées et conformes à l'article 21 de la loi n° 89-462 du 6 juillet 1989, prêtes à partager en PDF.</p>
  <h2>Suivi des loyers et des retards</h2>
  <p>Enregistrez les paiements, suivez les échéances de chaque bail et repérez les loyers en retard d'un coup d'œil.</p>
  <h2>Régularisation des charges et registre des dépenses</h2>
  <p>Tenez le registre des dépenses par bien (copropriété, taxe foncière, assurance PNO, travaux) et régularisez annuellement les charges récupérables.</p>
  <h2>Simulateur d'investissement locatif</h2>
  <p>Estimez rendement, cash-flow et coût du crédit avant d'acheter.</p>
  <nav>
    <a href="/simulator">Simulateur d'investissement</a>
    <a href="/faq">Questions fréquentes</a>
    <a href="/privacy">Politique de confidentialité</a>
    <a href="/terms">Conditions générales</a>
    <a href="/delete-account">Supprimer mon compte</a>
  </nav>
</div>
<noscript>
  <h1>Baillan — Gestion locative pour bailleurs</h1>
  <p>Quittances conformes, suivi des loyers et charges, simulateur d'investissement. Activez JavaScript pour utiliser l'application.</p>
</noscript>
```

### 4.4 `web/robots.txt` — PRODUCTION

```
# robots.txt — Baillan (PRODUCTION)
# Domaine : remplacer VOTRE-DOMAINE par le domaine custom (unique occurrence : ligne Sitemap).
# App SPA Flutter (rewrite ** -> /index.html) : toute URL renvoie 200 + le shell index.html,
# donc on interdit explicitement les sections privées pour éviter des doublons de la landing.

User-agent: *
Allow: /

# Namespace réservé Firebase (helpers auth/hosting — jamais utile aux crawlers)
Disallow: /__/

# Sections applicatives derrière auth (rendu canvas, sans valeur SEO)
Disallow: /dashboard
Disallow: /properties
Disallow: /tenants
Disallow: /leases
Disallow: /profile

# Pages utilitaires auth avec jetons (sans valeur SEO)
Disallow: /reset-password

Sitemap: https://VOTRE-DOMAINE/sitemap.xml
```

### 4.5 `web/robots.staging.txt` — STAGING (à committer, NE PAS laisser devenir le robots.txt prod)

```
# robots.txt — Baillan (STAGING / preview channels)
# Bloque tout crawl des URLs de preview (easy-rent-54cd4--staging-*.web.app).
# Remplace build/web/robots.txt UNIQUEMENT sur les builds APP_ENV=dev (cf. §4.6).

User-agent: *
Disallow: /
```

### 4.6 `web/sitemap.xml`

Routes **publiques** uniquement (cf. `docs/state/routes/README.md`). Pas de hreflang (locale
FR/EN = choix runtime, pas dans l'URL — FEAT-043). `/simulator` **exclu** : en
unauthenticated il redirige vers `/login` (pas de contenu autonome indexable
aujourd'hui). `/login`, `/signup`, `/forgot-password`, `/reset-password` exclus
(pages minces). Tout le shell est derrière auth → jamais dans le sitemap.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!-- sitemap.xml — Baillan. URLs publiques uniquement. Remplacer VOTRE-DOMAINE. -->
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>https://VOTRE-DOMAINE/</loc><changefreq>weekly</changefreq><priority>1.0</priority></url>
  <url><loc>https://VOTRE-DOMAINE/faq</loc><changefreq>monthly</changefreq><priority>0.8</priority></url>
  <url><loc>https://VOTRE-DOMAINE/privacy</loc><changefreq>yearly</changefreq><priority>0.3</priority></url>
  <url><loc>https://VOTRE-DOMAINE/terms</loc><changefreq>yearly</changefreq><priority>0.3</priority></url>
  <url><loc>https://VOTRE-DOMAINE/delete-account</loc><changefreq>yearly</changefreq><priority>0.3</priority></url>
</urlset>
```

> Nuance : sans Option B, ces URLs servent toutes le même `index.html`. Le sitemap
> n'ajoute de la valeur **par-route** qu'une fois qu'il y a du contenu par-route. On le
> pose quand même (plomberie standard, routes légitimes) — le caveat est assumé.

### 4.7 `firebase.json` — headers Cache-Control (robots/sitemap)

À AJOUTER dans `hosting.headers`, parmi les règles à source exacte (aucun glob existant
ne matche `.txt`/`.xml`, donc aucun conflit de clé) :

```json
{
  "source": "/robots.txt",
  "headers": [
    { "key": "Cache-Control", "value": "public, max-age=3600" }
  ]
},
{
  "source": "/sitemap.xml",
  "headers": [
    { "key": "Cache-Control", "value": "public, max-age=3600" }
  ]
}
```

### 4.8 `.github/workflows/deploy.yml` — noindex staging (mécanisme PRIMAIRE)

`firebase.json` est **partagé** entre live et channels → la seule différenciation fiable
par canal est un **swap de fichier au build**. Ajouter cette étape **après** « Build web
(release) » et **avant** « Deploy to Firebase Hosting » :

```yaml
- name: Staging — noindex (swap robots.txt + drop sitemap + meta noindex)
  if: needs.determine-env.outputs.app_env == 'dev'
  run: |
    cp web/robots.staging.txt build/web/robots.txt
    rm -f build/web/sitemap.xml
    # Durcissement : bascule aussi la meta robots de l'index.html buildé.
    sed -i 's/content="index, follow"/content="noindex, nofollow"/' build/web/index.html
```

> **Asymétrie de risque assumée** : le `robots.txt` staging (`Disallow: /`) est le
> garde-fou robuste. La `<meta robots>` prod est `index, follow` **par défaut** (sûr
> même si l'étape CI est oubliée) ; l'étape ci-dessus la flippe en `noindex` uniquement
> sur les builds dev. `Disallow: /` bloque le crawl mais pas l'indexation d'une URL
> connue par ailleurs ; pour du staging jamais lié (hash aléatoire, `--expires 7d`),
> c'est pragmatiquement suffisant.

---

## 5. Mots-clés & positionnement (résumé)

> La stratégie mots-clés est **inerte** tant que le contenu reste dans le canvas
> (Option A ne débloque que la home ; le vrai ROI vient de l'Option B). À décorréler
> du SPA Flutter : socle de pages HTML statiques servi avant le rewrite.

**Cible** : bailleur particulier solo (1 à 5 biens), qui trouve Rentila/GérerSeul trop
denses, BailFacile trop cher au bien, et qui gère (mal) sous Excel.

**3 piliers différenciants (tous réels, à capitaliser)** :
- **Mobile-first** : vraies apps natives iOS/Android (FEAT-024) vs concurrents web-first.
- **Simple & pas cher** : métaphore « registre » + (à venir) freemium forfait **plat**
  multi-biens (FEAT-044) vs tarif/bien de BailFacile.
- **Friction zéro + conforme** : essai anonyme 14 j sans compte ; quittances loi 1989 +
  charges décret 87-713 intégrées. Le simulateur (FEAT-018) fait le pont
  « je réfléchis à investir » → « je gère mon bien ».

**Ne PAS chasser les têtes** (« logiciel gestion locative » : verrouillé par
BailFacile, GérerSeul, iGestionlocative, ImmobilierLoyer + mur de sites d'avis). Attaquer :
- Longue traîne **tool-intent** : générateur quittance sans inscription, calcul
  régularisation charges, simulateur rentabilité.
- **Challenger BOFU** : « logiciel gestion locative pas cher », « alternative BailFacile »,
  « alternative Rentila ».
- Angle **mobile** : « application gestion locative » / « suivi des loyers » (moins saturé
  que « logiciel »).

**Périmètre** : concurrents directs = Rentila, GérerSeul, BailFacile, iGestionlocative,
ImmobilierLoyer, Smovin. **Adjacents à ne PAS combattre frontalement** : Qlower (compta
LMNP), Jelouebien (courtier assurance).

**Quick-win indépendant de l'Option B** : la réécriture title + description (§4.1) porte
déjà les mots-clés tête sur la home.

---

## 6. Checklist de lancement

- [x] Domaine custom attribué (**`baillan.com`**, 2026-07-20) → substitution faite
      (head `index.html`, `robots.txt`, `sitemap.xml`) + `Env.publicAppUrl` /
      `APP_PUBLIC_URL` + `WEB_APP_BASE_URL` alignés.
- [ ] **Côté consoles (hors dépôt)** : domaine ajouté dans Firebase Hosting (apex +
      `www` en redirection), DNS (TXT de vérification puis A), SSL provisionné, et
      **`baillan.com` ajouté aux domaines autorisés de Firebase Auth** (sinon liens
      email + Google/Apple cassés).
- [ ] Mettre à jour l'URL `/delete-account` déclarée sur la fiche Google Play (FEAT-045).
- [ ] `<head>` enrichi appliqué (title, description, canonical, OG, Twitter, JSON-LD),
      `<html lang="fr">`, sans toucher aux scripts de boot FEAT-019.
- [ ] Bloc statique `#seo-static` + `<noscript>` en tête de `<body>`.
- [ ] `web/robots.txt`, `web/robots.staging.txt`, `web/sitemap.xml` committés.
- [ ] Étape deploy.yml « noindex staging » en place + testée sur un build dev.
- [ ] Headers Cache-Control robots/sitemap dans `firebase.json`.
- [x] Image OG `og-image-1200x630.png` créée (générée par `scripts/generate-og-image.sh`).
- [ ] **Vérif DOM servi** : `curl -s https://VOTRE-DOMAINE/ | grep -iE "og:|canonical|<h1|ld\+json"` → doit renvoyer le head + le bloc `#seo-static`.
- [ ] **Vérif fichiers statiques** (servis avant le rewrite) :
      `curl -s https://VOTRE-DOMAINE/robots.txt` et `.../sitemap.xml` → renvoient le fichier, pas `index.html`.
- [ ] **Vérif staging noindexé** : `curl -s https://easy-rent-54cd4--staging-XXXX.web.app/robots.txt` → `Disallow: /` ; `.../index.html | grep noindex`.
- [ ] **Search Console** : vérifier la propriété (domaine), soumettre `sitemap.xml`,
      « Inspection d'URL » → « Tester l'URL en direct » sur `/` (le HTML rendu doit montrer
      le head + `#seo-static`).
- [ ] Surveiller les fuites : `site:easy-rent-54cd4.web.app` et `site:VOTRE-DOMAINE`.
- [ ] Partage social : passer `/` dans les validateurs OG (LinkedIn Post Inspector,
      debugger Facebook) → carte avec titre + description + image.

---

## 7. Annexe — FAQPage JSON-LD (réservé à une `/faq` pré-rendue)

À n'utiliser QUE si les Q/R sont AUSSI dans le DOM crawlable de `/faq` (Option B).
Source : `lib/features/support/presentation/faq_page.dart` (20 Q/R). Extrait des 4 plus
stratégiques — compléter avec les 20 lors du pré-rendu :

```html
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "FAQPage",
  "mainEntity": [
    {"@type":"Question","name":"Qu'est-ce que Baillan ?","acceptedAnswer":{"@type":"Answer","text":"Baillan est le registre locatif des bailleurs particuliers : vos biens, locataires et baux au même endroit, le suivi des paiements et des retards, des quittances de loyer conformes, le registre de vos dépenses, la régularisation annuelle des charges et un simulateur d'investissement."}},
    {"@type":"Question","name":"Les quittances sont-elles conformes à la loi ?","acceptedAnswer":{"@type":"Answer","text":"Oui. Chaque quittance porte les mentions requises par l'article 21 de la loi n° 89-462 du 6 juillet 1989 : identité et adresse du bailleur, nom du locataire, adresse du logement, période concernée, détail loyer et charges, montant total et date d'émission. Les quittances sont numérotées et archivées."}},
    {"@type":"Question","name":"Comment fonctionne la régularisation annuelle des charges ?","acceptedAnswer":{"@type":"Answer","text":"Pour un bail en provisions, Baillan rapproche les provisions encaissées des dépenses récupérables enregistrées, calcule le solde (trop-perçu ou complément) et génère un avis de régularisation en PDF à transmettre au locataire."}},
    {"@type":"Question","name":"Baillan est-il gratuit ?","acceptedAnswer":{"@type":"Answer","text":"Oui, l'application est gratuite à ce jour. Si une offre payante voit le jour, elle sera annoncée dans l'application — vous ne serez jamais facturé sans action explicite de votre part."}}
  ]
}
</script>
```

---

## 8. Garde-fous respectés

- Scripts de boot FEAT-019 (nettoyage SW + cache-repair) **intouchés**.
- Pas de hreflang par-URL fabriqué (locale runtime FEAT-043, pas de `/fr` `/en`) ;
  bilinguisme exprimé via `og:locale:alternate` uniquement. Langue primaire = français.
- Toutes les URLs paramétrées via `https://VOTRE-DOMAINE` (domaine custom TBD).
- Contenu légal (loi 89-462, quittances) reste FR.
- Aucune URL de canal staging dans canonical / OG / sitemap.
</content>
</invoke>
