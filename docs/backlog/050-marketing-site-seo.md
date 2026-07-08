# FEAT-050 — Site marketing statique crawlable (SEO Option B)

> **Statut** : 📋 Cadré (2026-07-08) — décision d'architecture proposée, à valider par l'utilisateur (3 décisions en fin de doc). Rien n'est implémenté.
> **Amont** : [`docs/SEO.md`](../SEO.md) (audit complet, Option A/B/C). Option A = FEAT-049, déjà appliquée (enrichit `index.html`, ne débloque que la home). Ce doc cadre **l'Option B**.
> **Fenêtre** : domaine custom acheté la semaine du **2026-07-13** → topologie à figer AVANT toute dette d'URL (rien n'est encore indexé/linké sur le domaine).

## 1. Contexte & objectif

L'UI est rendue en **CanvasKit** (peinte dans un `<canvas>`). Les crawlers extraient le texte du **DOM**, pas des pixels → aujourd'hui chaque route publique (`/`, `/faq`, `/privacy`, `/terms`, `/delete-account`) sert le **même** `index.html` quasi vide (rewrite `** → /index.html`). L'Option A (FEAT-049) a posé les métadonnées + un bloc `#seo-static` pour la home, mais **ne peut pas** produire du contenu crawlable **par page**.

**Objectif Option B** : exposer un **site marketing statique** (HTML réel, une page = un document) **séparé** de l'app Flutter, sans rien casser de l'app en production (OAuth popup web, flux natif mobile, PWA installée, scripts de boot FEAT-019, garde 3-états). Le SEO est un **chantier de croissance**, pas un bloquant de lancement : on le pose de façon **strictement additive**.

**Cible SEO** (rappel `docs/SEO.md` §5) : bailleur particulier solo (1-5 biens). Longue traîne **tool-intent** (générateur quittance, calcul régularisation, simulateur rentabilité) + **challenger BOFU** (« alternative BailFacile », « logiciel gestion locative pas cher »). Ne pas chasser les têtes verrouillées.

## 2. Décision d'architecture (recommandée)

> ✅ **Topologie confirmée le 2026-07-08 (arbitrage utilisateur)** : **sous-domaine**
> (`app.baillan.fr` + `baillan.fr`). Le sous-chemin (§3) est écarté. Domaine
> exact à confirmer à l'achat (hypothèse `baillan.fr`).

### 2.1 Topologie — SOUS-DOMAINE

| Hôte | Contenu | État |
|---|---|---|
| `baillan.fr` (apex) | **Site marketing statique** (canonique, indexé) | nouveau (2e site Hosting) |
| `www.baillan.fr` | 301 → apex | redirect |
| `app.baillan.fr` | **App Flutter** (racine du sous-domaine, `base-href` reste `/`) | app actuelle, **noindex global** |
| `easy-rent-54cd4.web.app` | app (filet de sécurité) | conservé, noindex |

**Pourquoi sous-domaine et pas sous-chemin (`baillan.fr/app`)** :

- Le sous-domaine laisse l'app Flutter **strictement inchangée** : `base-href` reste `/`, routeur/garde 3-états inchangés, rewrite `** → /index.html` inchangé, `manifest.start_url` `/` inchangé, scope PWA inchangé, scripts de boot FEAT-019 intouchés. **Zéro ligne de Dart** (hormis un dart-define de build). C'est le levier n°1 de « zéro régression ».
- Le sous-chemin imposerait `--base-href=/app/` : migration du build, rewrite SPA à scoper (`/app/**`) cohabitant avec des fichiers statiques (ordonnancement fragile), `manifest.start_url` + scope à migrer (ré-install PWA forcée), 301 de **toutes** les anciennes URLs racine, re-scoping de **tous** les headers de cache FEAT-019, et re-vérification de l'interaction `base-href` ↔ boot scripts ↔ scope SW. Pour un dev solo profil mobile, à la veille du lancement, c'est le chemin à plus haut risque sur du code déjà livré (web **et** mobile).
- **L'argument « subfolder > subdomain »** (consolidation d'autorité) est **quasi inapplicable ici** : l'app n'a **aucun contenu à ranker** (canvas + derrière auth) et sera **noindex**. Tout le contenu indexable vit sur `baillan.fr`, propriété unique → il n'y a rien à consolider côté app. Le gain résiduel du sous-chemin (backlinks pointant vers l'outil) est mineur, adressable par maillage interne, et **réversible** plus tard. Le domaine étant neuf, aucune dette de redirection n'est créée.
- **Bonus mobile** : les deep links vérifiés (roadmap MOBILE.md, non câblés aujourd'hui) iront proprement sur `app.baillan.fr/.well-known/`, sans ambiguïté de chemin avec le marketing.

### 2.2 Stack statique — ASTRO

Site dans un dossier `site/` du repo (mono-repo, versionnement unique, sibling de `functions/`). Build `astro build` → `site/dist/`.

**Pourquoi Astro** :
- Sortie **zéro-JS par défaut** → HTML/CSS pur livré = crawlabilité parfaite + excellents Core Web Vitals (l'inverse du canvas).
- **Layouts/composants** → header/footer/`<head>`/JSON-LD factorisés (le point de douleur n°1 du HTML à la main dès 5+ pages : une modif de nav = N fichiers + drift silencieux).
- **Content Collections** (Markdown/MDX typé) → blog/guides et pages-outils v2 sans re-plateformer.
- **i18n routing natif** + `@astrojs/sitemap` (sitemap + hreflang auto) → i18n-SEO réelle quand l'EN arrivera.
- **Pas d'écosystème étranger** : le repo maintient déjà Node 20 (`functions/`, lint, vitest) et la CI lance déjà `npm`/`npx`. Docs massives + « LLM-legible » → un dev mobile assisté avance vite.

**Rejetés** : HTML à la main (ne passe pas l'échelle blog/i18n, duplication du chrome) ; Hugo (templating Go hostile à un profil mobile, moins d'effet de levier LLM) ; Eleventy (Node aussi mais i18n/sitemap/images en assemblage manuel).

**Mitigations dette** : pin des versions dans `package.json`, mises à jour trimestrielles volontaires (pas de bot auto agressif).

### 2.3 Hosting — Firebase multi-site

Passer `firebase.json` `hosting` en **tableau** de 2 blocs + cibles nommées dans `.firebaserc`.

- **Bloc `app`** = config **actuelle strictement inchangée** (`public: build/web`, rewrite `** → /index.html`, **tous** les headers no-cache/immutable FEAT-019/FEAT-049) + `"target": "app"`. Seul ajout : bascule `web/robots.txt` en `Disallow: /` et retrait de `web/sitemap.xml` de l'app (déménagent sur le marketing) → app en **noindex global**.
- **Bloc `marketing`** = `{ "target": "marketing", "public": "site/dist", "cleanUrls": true, headers (HTML no-cache court + `/_astro/**` immutable 1 an car Astro **fingerprinte** ses assets — pas le piège Flutter — + robots/sitemap max-age 3600), redirects www→apex, PAS de rewrite SPA (404.html propre) }`.
- **`.firebaserc`** : `targets.easy-rent-54cd4.hosting = { "app": ["easy-rent-54cd4"], "marketing": ["baillan-marketing"] }`. Créer le site : `firebase hosting:sites:create baillan-marketing`.
- **⚠️ Déploiements SCOPÉS obligatoires** : sans `--only`, un deploy croiserait/écraserait l'autre site.
  - App : `deploy.yml` passe de `deploy --only hosting` → `--only hosting:app` (live) et `hosting:channel:deploy staging --only app`.
  - Marketing : job/étape séparée `--only hosting:marketing` (live) / `hosting:channel:deploy <ch> --only marketing`.
  - Garde-fou « pas de prod sans confirmation » conservé ; préférer les commandes `firebase` explicites (bug deployer connu, cf. MEMORY).

### 2.4 Précédence Firebase Hosting (à connaître)

`/__/` réservé > `redirects` > **fichier statique exact** > `rewrites`. Sur le marketing, **pas** de rewrite catch-all → une URL inconnue tombe sur `404.html` (pas sur la landing). Les fichiers `robots.txt`/`sitemap.xml`/`.well-known/*` sont servis avant tout rewrite.

## 3. Alternatives considérées (et pourquoi écartées)

| Approche | Verdict |
|---|---|
| **Sous-chemin `baillan.fr/app`** (SEO maximal) | Écarté au lancement : meilleur SEO en théorie mais migration `base-href=/app/` = plus haut risque sur l'app prod (mobile + web), 301 massifs, PWA ré-install, headers/boot à re-vérifier. Gain SEO mineur (app noindex → rien à consolider) et **réversible**. Rouvrable si le SEO devient stratégique et qu'on accepte un cutover encadré. |
| **Prerendering / dynamic rendering** (Option C) | Écarté : CanvasKit peint dans un canvas → le snapshot DOM est **vide**. Ré-authoring manuel = Option B déguisée, plus fragile, flaggé « contournement » par Google. |
| **HTML statique à la main** | Écarté : ne tient pas au-delà de ~5 pages (blog + pages-outils prévus), duplication du chrome, pas de sitemap/hreflang auto. |
| **Sous-domaine par langue** (`en.baillan.fr`) | Écarté : fragmente l'autorité, plus lourd à opérer pour un solo. EN ira en sous-répertoire `/en`. |

## 4. Plan de contenu (anti-drift = clé pour un solo)

**Principe de gouvernance** : séparer le **contenu SEO** (statique, source = marketing) du **contenu légal versionné** (source canonique = **in-app**, lié à `rgpdConsentVersion`).

- **Légal versionné** (`privacy` v1.2, `terms`/CGU v2-2026-07) → **reste canonique in-app** (`app.baillan.fr/privacy`, `/terms`). C'est la source du consentement RGPD au signup. Le footer marketing y renvoie. SEO quasi nul (priority 0.3) → perte négligeable, **drift évité**. L'app étant noindex, aucun duplicate content.
- **Non versionné** (FAQ, mentions LCEN) → vit sur le statique sans risque de drift.

### v1 (au lancement, FR uniquement, crawlable sur `baillan.fr`)

| Page | Source de copy | Notes |
|---|---|---|
| `/` (landing) | clés `landing*` de `lib/l10n/app_fr.arb` + bloc `#seo-static` FEAT-049 | H1/H2 + sections piliers (quittances loi 1989, suivi loyers/retards, régularisation charges décret 87-713, simulateur) + CTA → `app.baillan.fr/simulator` et `/signup` |
| `/faq` | `lib/features/support/presentation/faq_page.dart` (**20 Q/R** — vérifié ; l'INDEX qui dit « 11 » est erroné) | Q/R visibles dans le DOM → **JSON-LD FAQPage désormais légitime** |
| `/mentions-legales` | à rédiger (LCEN) | coche aussi un bloquant STORE_COMPLIANCE.md |
| `/supprimer-mon-compte` | informationnel | décrit la procédure + **CTA → `app.baillan.fr/delete-account`** (le flux interactif reste in-app ; les anonymes y suppriment leur essai) |

> `robots.txt` + `sitemap.xml` « réels » **déménagent** de `web/` vers le marketing. L'app sert un `robots.txt` `Disallow: /`.

### v2 (croissance SEO, post-lancement)

- **Pages-outils lead-gen** (page statique qui RANK → CTA vers l'outil Flutter qui CONVERTIT) :
  - `/outils/quittance-de-loyer` (mentions loi 89-462 + CTA générer dans l'app)
  - `/outils/simulateur-rentabilite` (méthode rendement/cash-flow + CTA → `/simulator`)
  - `/outils/regularisation-charges` (méthode décret 87-713 + CTA)
- **Blog/guides** (`/guides/*`, `/blog/*`) via Content Collections MDX : longue traîne BOFU (« alternative BailFacile », « suivi des loyers », « logiciel gestion locative pas cher »).
- JSON-LD par type (Article, HowTo, `SoftwareApplication` réutilisé) + fil d'Ariane + maillage interne fort `baillan.fr` ↔ `app.baillan.fr`.

> Anti-cloaking (SEO.md §2) : ne PAS gonfler avec du texte que l'app ne montre pas. Le copy marketing peut diverger/enrichir légitimement (ce n'est plus le bloc `#seo-static` visually-hidden, c'est du vrai contenu de page).

## 5. Stratégie i18n-SEO

- L'app garde sa **locale runtime** (FEAT-043, hors URL) — **intouchée**. L'i18n-SEO ne vit **que** sur la couche statique (l'app est noindex).
- **v1 = FR uniquement**, FR à la racine (`baillan.fr/faq`). Astro configuré avec `defaultLocale: 'fr'` **sans préfixe** (`prefixDefaultLocale: false`) → l'EN pourra s'ajouter en `/en/*` **sans déplacer** les URLs FR.
- **EN différé (v2+)** : ajouter `/en/*` page par page **uniquement quand la traduction existe** (pas de page EN vide → thin content nuit au SEO). hreflang réciproques (`fr` / `en` / `x-default=fr`) + sitemap par-locale générés par `@astrojs/sitemap`.
- Le légal reste FR (loi 89-462, décret 87-713).

## 6. Découpage en tickets

### v1 — Fondation & lancement

**FEAT-050a — Firebase multi-site + déploiements scopés**
- Créer le site `baillan-marketing` ; `.firebaserc` cibles `app`/`marketing`.
- `firebase.json` `hosting` → tableau 2 blocs (app inchangé + `target: app` ; marketing).
- `deploy.yml` : app en `--only hosting:app` (live) / `--only app` (channel).
- **CA** : `firebase deploy --only hosting:app` ne touche pas le marketing et vice-versa (testé sur channel preview) ; app prod inchangée (OAuth + PWA + parcours métier OK) ; headers/boot FEAT-019 intouchés.

**FEAT-050b — Scaffold Astro + layout + SEO plumbing**
- `site/` : Astro, layout (header/footer/tokens de marque), composant `<Seo>` (title/description/canonical/OG/Twitter/JSON-LD par page), `@astrojs/sitemap`, i18n `defaultLocale=fr` sans préfixe.
- `robots.txt` (marketing, `Allow: /` + `Disallow: /__/` + `Sitemap:`) + `sitemap.xml` auto.
- Job CI `build-marketing` : `npm --prefix site ci && npm --prefix site run build` → deploy scopé (path filter `site/**` + déclenchable indépendamment) ; **noindex sur channels preview** (cp robots noindex + drop sitemap sur `site/dist`, réplique de l'astuce app).
- **CA** : `curl` d'une page rendue montre `<head>` + `<h1>` + JSON-LD dans le DOM ; channel preview `Disallow: /`.

**FEAT-050c — Contenu FR v1 (4 pages)**
- `/` (landing), `/faq` (+ JSON-LD FAQPage, 20 Q/R), `/mentions-legales` (LCEN), `/supprimer-mon-compte` (info → CTA app). Footer → liens légaux **in-app** (`app.baillan.fr/privacy`, `/terms`).
- **CA** : les 4 pages crawlables (contenu dans le DOM), maillage interne + CTA vers l'app, FAQPage validé (Rich Results Test).

**FEAT-050d — App en noindex + nettoyage Option A**
- `web/robots.txt` → `Disallow: /` ; retirer `web/sitemap.xml` de l'app ; `<meta robots>` app → `noindex`.
- **Déplacer** (pas supprimer en urgence) le `<head>` enrichi + JSON-LD + bloc `#seo-static` de `web/index.html` vers l'Astro (source de vérité SEO). Suppression du bloc dans l'index Flutter **optionnelle** (ne pas toucher aux boot scripts FEAT-019).
- **CA** : `curl app.baillan.fr/robots.txt` = `Disallow: /` ; `site:app.baillan.fr` ne remonte plus ; `baillan.fr` porte tout le SEO ; app fonctionnelle.

**FEAT-050e — Câblage domaine + Search Console** (dépend de l'achat 07-13)
- Custom domains : `baillan.fr` + `www.baillan.fr` → marketing (www→apex 301) ; `app.baillan.fr` → app.
- **OAuth** : ajouter `app.baillan.fr` (+ `baillan.fr` par sûreté) aux **Authorized domains** Firebase Auth **AVANT** de router le DNS.
- Build prod app : `--dart-define=APP_PUBLIC_URL=https://app.baillan.fr` (staging garde `.web.app`).
- **Play Console** : URL « Account deletion » = `https://app.baillan.fr/delete-account` (figée dès soumission).
- Search Console : vérifier `baillan.fr`, soumettre `sitemap.xml`, inspecter `/` + `/faq`.
- **CA** : sign-in Google/Apple OK sur `app.baillan.fr` ; liens email verify/reset atterrissent sur le bon hôte ; DNS/SSL propagés avant la comm de lancement.

### v2 — Croissance (débit choisi)

**FEAT-050f** — 3 pages-outils lead-gen (quittance / simulateur / régularisation) + JSON-LD HowTo + maillage.
**FEAT-050g** — Blog/guides (Content Collections MDX) + cadence éditoriale BOFU.
**FEAT-050h** — i18n EN : activer `/en`, hreflang réciproques, traduire v1 page par page (jamais de page EN vide au sitemap).
**FEAT-050i** (indépendant, roadmap mobile) — Deep links vérifiés : `.well-known/assetlinks.json` + `apple-app-site-association` sur `app.baillan.fr`, `associatedDomains: app.baillan.fr` (iOS) + intent-filter autoVerify (Android). Bundle réel = **`com.daki.baillan`**.

## 7. Checklist de migration

- [ ] `firebase hosting:sites:create baillan-marketing` + `.firebaserc` cibles `app`/`marketing`.
- [ ] `firebase.json` `hosting` → tableau ; bloc `app` = config actuelle + `target: app` (rewrite/headers/boot **intouchés**).
- [ ] `deploy.yml` app → `--only hosting:app` (live) / `--only app` (channel) ; job marketing `--only hosting:marketing`.
- [ ] `base-href` app = **`/`** (inchangé) ; `manifest.start_url` = **`/`** (inchangé) ; scope PWA inchangé.
- [ ] **OAuth** : `app.baillan.fr` (+ `baillan.fr`) ajoutés aux Authorized domains Firebase Auth **avant** DNS ; `authDomain` reste `easy-rent-54cd4.firebaseapp.com` (handler `/__/auth/handler` inchangé → popup/redirect intacts, pas de reconfig Google/Apple).
- [ ] `APP_PUBLIC_URL=https://app.baillan.fr` au build **prod** (staging garde `.web.app`).
- [ ] `web/robots.txt` app → `Disallow: /` ; `web/sitemap.xml` retiré de l'app ; `<meta robots>` app → `noindex`.
- [ ] `robots.txt` + `sitemap.xml` « réels » sur le **marketing** ; noindex répliqué sur les channels preview marketing.
- [ ] Redirections : `www.baillan.fr` → apex (301). Domaine neuf → **pas** de 301 legacy massifs. `easy-rent-54cd4.web.app` conservé (filet, noindex).
- [ ] **Play Console** : URL « Account deletion » = `https://app.baillan.fr/delete-account` (figée dès soumission).
- [ ] hreflang/sitemap : FR seul en v1 ; EN ajouté page par page en v2 (jamais de page vide).
- [ ] **assetlinks/AASA** : non applicables en v1 (deep links non câblés, `web/.well-known` absent — vérifié) ; à héberger sur `app.baillan.fr/.well-known/` quand la roadmap mobile les priorise. Bundle = `com.daki.baillan`.
- [ ] Search Console : vérifier `baillan.fr`, soumettre sitemap, inspecter `/` + `/faq` ; surveiller `site:baillan.fr` et `site:app.baillan.fr` (fuites).
- [ ] QA : `curl` marketing (head + H1 + JSON-LD dans le DOM), `curl` app robots (`Disallow: /`), OAuth Google/Apple sur `app.baillan.fr`, install PWA, parcours métier, staging toujours noindex.

## 8. Risques & mitigations

| # | Risque | Mitigation |
|---|---|---|
| 1 | Deploy multi-site non scopé écrase l'autre site | `--only hosting:app` / `:marketing` **partout** (CI + manuel) ; tester sur channel preview ; ne pas toucher rewrite/headers/boot FEAT-019 pendant le refactor |
| 2 | OAuth cassé si `app.baillan.fr` oublié dans Authorized domains (échec silencieux Google/Apple) | Ajouter le domaine **avant** de router le DNS ; tester sign-in dès propagation |
| 3 | Latence DNS/SSL du custom domain Firebase (parfois plusieurs heures) | Séquencer **avant** la comm de lancement |
| 4 | Drift du contenu légal (in-app vs statique) | Légal versionné **single-source in-app** ; seul le non-versionné (FAQ, mentions LCEN) sur le statique |
| 5 | Doublon d'indexation `app.baillan.fr` (landing Flutter #seo-static) vs `baillan.fr` | **noindex global** sur `app.baillan.fr` (robots `Disallow: /` + meta) |
| 6 | Dilution SEO sous-domaine vs sous-chemin | Assumée (app noindex → rien à consolider) ; maillage interne fort + contenu tool-intent auto-portant ; **réversible** |
| 7 | 2e toolchain (Astro/npm) | Node déjà présent (`functions/`) ; pin versions + updates trimestrielles |
| 8 | URL Play « Account deletion » cassée si non figée | Figer `app.baillan.fr/delete-account` dès la soumission store |
| 9 | PWA : aucun impact attendu (app à sa racine) | Nouvelles installs depuis `app.baillan.fr` ; installs `.web.app` survivent (origine distincte, pas de migration — pré-lancement, impact ~nul) |

## 9. Estimation d'effort (dev solo assisté)

| Phase | Contenu | Effort |
|---|---|---|
| **v1 — Phase 0** (câblage domaine, largement nécessaire pour l'achat) | DNS + custom domains + Authorized domains + `APP_PUBLIC_URL` + URL Play | ~0,5-1 j |
| **v1 — Phase 1** (cœur Option B) | multi-site + `.firebaserc` + deploy scopé (~0,5 j) ; scaffold Astro + layout + `<Seo>` + CI (~1 j) ; 4 pages FR (~2 j) ; flip app noindex + QA (~0,5 j) | ~4 j |
| **v2 — croissance** | 3 pages-outils + blog + JSON-LD/maillage | ~3-5 j (dominé par le contenu) |
| **v2 — i18n EN** | routing `/en` + hreflang (~0,5 j) + traduction = contenu | hors chiffrage archi |

**Mise en ligne Option B (v1)** : ~**4-5 j-dev**, l'essentiel = scaffold Astro + câblage multi-site. v2 = travail de contenu à débit choisi.

## 10. Phasage

1. **Phase 0 — Lancement protégé (semaine 07-13)** : livrer sur Option A (déjà faite) + custom domains. **Aucune** migration de topologie risquée le jour du go-live. `app.baillan.fr` + Option A fournit déjà une home crawlable en attendant le marketing.
2. **Phase 1 — Marketing v1** : multi-site scopé, scaffold Astro + CI, 4 pages FR, brancher `baillan.fr`/`www`→marketing, **puis** flip `app.baillan.fr` en noindex une fois le marketing live. Search Console.
3. **Phase 2 — Croissance FR** : pages-outils + blog + JSON-LD FAQPage/HowTo + maillage.
4. **Phase 3 — i18n EN** : `/en` page par page + hreflang, quand le contenu EN existe.
5. **Transverse** : chaque phase passe `code-reviewer` + `security-auditor` ; pas de deploy prod sans confirmation utilisateur (CLAUDE.md).

## 11. Corrections apportées aux hypothèses du cadrage

- **Bundle mobile** : le brief cite `app.baillan.mobile` — le repo et les stores utilisent **`com.daki.baillan`** (vérifié : `firebase.json`, MOBILE.md). Les futurs assetlinks/AASA doivent utiliser `com.daki.baillan`.
- **Nombre de Q/R FAQ** : **20** (vérifié dans `faq_page.dart`), pas 11 (INDEX erroné) ni 25.
- **Deep links** : `web/.well-known` **absent** aujourd'hui (vérifié) → hors scope v1, simple note d'archi.
- **`base-href` actuel** : le build web n'a **aucun** `--base-href` (défaut `/`) → le sous-domaine ne change rien.

## 12. Dépendances

Achat domaine custom (semaine 07-13) · FEAT-049 (Option A, socle SEO) · FEAT-043 (i18n runtime, non impactée) · MOBILE.md / STORE_COMPLIANCE.md (mentions LCEN, deep links).
