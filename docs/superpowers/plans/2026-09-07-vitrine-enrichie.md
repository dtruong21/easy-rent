# Vitrine enrichie — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enrichir la landing `baillan.com` (Astro statique zéro-JS) : mettre le simulateur de rentabilité en vedette avec un comparatif brut-vs-net et une capture réelle, ajouter des sections de contenu, et un bouton « Proposez une idée » vers un formulaire Tally.

**Architecture:** On enrichit `site/src/pages/index.astro` (fichier unique de la landing) en y ajoutant des `<section>` et le CSS associé, sans toucher au gabarit `BaseLayout.astro`. Une nouvelle constante centralise l'URL Tally. La capture du simulateur est un asset servi depuis `site/public/`. Aucune dépendance ni JavaScript de page ajoutés.

**Tech Stack:** Astro (statique, `build.format: 'file'`), CSS pur, tokens de couleur générés.

**Spec:** [`docs/superpowers/specs/2026-09-07-vitrine-enrichie-design.md`](../specs/2026-09-07-vitrine-enrichie-design.md)

## Global Constraints

- **Zéro JavaScript exécutable** dans les pages. Seul `<script type="application/ld+json">` est admis. Pas de directive `client:*`, pas de `<script src>`.
- **Couleurs** : uniquement les variables `--color-*` de `site/src/styles/tokens.css` (fichier généré, protégé par `scripts/check-theme-tokens.sh` — ne pas l'éditer). Jetons utiles : `--color-cream` (#FCFAF5), `--color-paper` (#F7F4ED), `--color-ink` (#1B1A17), `--color-ink-muted` (#6B665D), `--color-olive` (#3F4A2A), `--color-rule` (#E8E2D3), `--color-rule-strong` (#C9C1AB), `--color-kraft` (#E4D9BD), `--color-oxblood` (#9A3B2F), `--color-seal-green` (#2E5339, **le vert positif**), `--color-amount-negative` (#6E3A1F).
- **Liens vers l'app** : toujours via `appUrl` importé de `site/src/lib/urls.ts` (déjà env-aware). Jamais de domaine en dur.
- **Français uniquement.**
- **Style** : SaaS/direct, sans serif (pas d'éditorial serif). Le style et le CSS existants de `index.astro` sont la base.
- Commandes depuis la racine du dépôt, `export PATH=/opt/homebrew/bin:$PATH`.
- Build du site : `npm run build --prefix site` → `site/dist/`. Le build met les hex en minuscules et inline le CSS.
- Chiffres du simulateur **figés** (spec §4.1), à écrire verbatim : comparatif « **8,0 %** » (brut, les autres) vs « **+348 €/mois** » (Baillan) ; cartes de résultat : mensualité **502,12 €**, loyer net annuel **9 690 €**, cash-flow mensuel **+347,88 €**, rendement net **7,60 %**.

## Structure des fichiers

| Fichier | Responsabilité |
|---|---|
| `site/src/lib/links.ts` | Constante `ideaFormUrl` (URL Tally) — source unique |
| `site/public/screenshots/simulateur-resultats.webp` | Capture réelle du résultat simulateur (FR), servie statiquement |
| `site/src/pages/index.astro` | Landing enrichie : nouvelles sections + CSS |

---

### Task 1 : Constante d'URL du formulaire Tally

**Files:**
- Create: `site/src/lib/links.ts`

**Interfaces:**
- Produces: `export const ideaFormUrl: string` — l'URL du formulaire Tally, consommée par la section « Proposez une idée » (Task 5).

- [ ] **Step 1 : Écrire le module**

L'URL réelle sera fournie par le propriétaire (formulaire Tally à créer). En attendant, un placeholder explicite, lisible dans le code, qu'on remplacera. Ne PAS mettre `#` seul (lien mort silencieux).

```ts
// site/src/lib/links.ts
//
// Liens externes de la vitrine, centralisés pour ne pas les éparpiller.

// Formulaire Tally de collecte d'idées (canal choisi le 2026-09-07). L'URL
// réelle est à renseigner ici quand le formulaire Tally est créé. Le
// placeholder `https://tally.so/` (racine, pas un formulaire) est volontaire :
// visible, non trompeur, et rattrapé par le garde-fou de build de la Task 5.
export const ideaFormUrl = 'https://tally.so/';
```

- [ ] **Step 2 : Vérifier que le module compile**

Run: `export PATH=/opt/homebrew/bin:$PATH; cd site && npx tsc --noEmit 2>/dev/null; echo "exit=$?"`
Expected: pas d'erreur de type sur `links.ts` (exit 0, ou l'absence de `@astrojs/check` rend la commande no-op — dans ce cas le build de la Task 5 couvre la compilation).

- [ ] **Step 3 : Commit**

```bash
export PATH=/opt/homebrew/bin:$PATH
git add site/src/lib/links.ts
git commit -m "feat(site): constante d'URL du formulaire Tally (canal d'idées)"
```

---

### Task 2 : Capture réelle du simulateur (français)

**Files:**
- Create: `site/public/screenshots/simulateur-resultats.webp`

**Interfaces:**
- Produces: le fichier image `screenshots/simulateur-resultats.webp`, référencé par `<img src="/screenshots/simulateur-resultats.webp">` dans la Task 3.

> Cette tâche produit un **asset**, pas du code — pas de test unitaire, mais une vérification concrète (le fichier existe, poids raisonnable, dimensions correctes).

- [ ] **Step 1 : Ouvrir le simulateur en anonyme, en français**

Le simulateur est accessible sans compte (`/simulator` ouvert aux sessions anonymes). Dans un navigateur **réglé en français** (`Accept-Language: fr`, ou bascule de langue in-app si disponible) :
1. Ouvrir `https://app.staging.baillan.com`.
2. Cliquer « Continuer sans compte » (ou l'équivalent FR « Continuer sans compte »).
3. Arriver sur le simulateur.

- [ ] **Step 2 : Saisir le scénario figé (spec §4.1)**

| Champ | Valeur |
|---|---|
| Prix d'achat | `118000` |
| Apport | `35000` |
| Capital emprunté | `83000` (si non recalculé auto) |
| Taux nominal | `3.5` |
| Durée (mois) | `240` |
| Loyer mensuel HC | `850` |

Vérifier que la section « Résultats estimés » affiche : cash-flow **+347,88 €**, rendement brut **8,00 %**, net **7,60 %**, mensualité **502,12 €**, loyer net annuel **9 690 €**.

- [ ] **Step 3 : Capturer la section des résultats**

Capturer la carte « Résultats estimés » (les 6-8 cartes de chiffres). Cadrer serré sur les résultats — pas tout le formulaire.

**Repli (spec §4.2)** : si le français ne peut pas être forcé, OU si la capture est bloquée, produire à la place une **maquette SVG stylisée zéro-JS** reproduisant les mêmes cartes (mêmes chiffres, mêmes couleurs de marque) et la servir comme `simulateur-resultats.svg`. Adapter la Task 3 pour référencer le `.svg`. Le noter dans le rapport.

- [ ] **Step 4 : Optimiser et déposer**

Convertir en WebP, largeur ≤ 1200 px, viser < 150 Ko :

```bash
export PATH=/opt/homebrew/bin:$PATH
mkdir -p site/public/screenshots
# depuis la capture PNG source (ex. /tmp/capture.png) :
# cwebp -q 82 -resize 1200 0 /tmp/capture.png -o site/public/screenshots/simulateur-resultats.webp
ls -l site/public/screenshots/simulateur-resultats.webp
```

- [ ] **Step 5 : Vérifier l'asset**

Run:
```bash
export PATH=/opt/homebrew/bin:$PATH
file site/public/screenshots/simulateur-resultats.webp
du -k site/public/screenshots/simulateur-resultats.webp
```
Expected: un fichier image valide (WebP ou PNG/SVG de repli), poids raisonnable (< ~200 Ko).

- [ ] **Step 6 : Commit**

```bash
export PATH=/opt/homebrew/bin:$PATH
git add site/public/screenshots/
git commit -m "feat(site): capture réelle du simulateur (résultats, scénario positif)"
```

---

### Task 3 : Section simulateur (la vedette)

**Files:**
- Modify: `site/src/pages/index.astro`

**Interfaces:**
- Consumes: `appUrl` (déjà importé dans `index.astro`), l'image `screenshots/simulateur-resultats.webp` (Task 2).

- [ ] **Step 1 : Ajouter la section après le hero**

Dans `site/src/pages/index.astro`, insérer cette section **entre** la `<section class="hero">` et la `<section class="features">`. Utiliser `appUrl` pour le CTA.

```astro
  <section class="sim">
    <p class="sim-label">Le simulateur</p>
    <h2>Le vrai rendement, pas le brut flatteur</h2>
    <p class="sim-sub">
      La plupart des outils s'arrêtent au rendement brut. Baillan déduit la
      mensualité de crédit et les dépenses, et vous donne le cash-flow réel —
      mois par mois.
    </p>

    <div class="cmp">
      <div class="cmp-card">
        <p class="cmp-h">Les autres outils</p>
        <p class="cmp-big muted">8,0 %</p>
        <p class="cmp-s">rendement brut — s'arrête là</p>
      </div>
      <div class="cmp-card win">
        <p class="cmp-h">Baillan</p>
        <p class="cmp-big good">+348 €/mois</p>
        <p class="cmp-s">cash-flow réel · rendement net 7,6 % · crédit déduit</p>
      </div>
    </div>

    <figure class="sim-shot">
      <img
        src="/screenshots/simulateur-resultats.webp"
        alt="Résultats du simulateur Baillan : mensualité de crédit 502 €, loyer net annuel 9 690 €, cash-flow mensuel +347,88 €, rendement net 7,60 %."
        width="1200" height="800" loading="lazy" />
      <figcaption>Un exemple réel : 118 000 € financés, 850 € de loyer.</figcaption>
    </figure>

    <p class="sim-cta">
      <a class="btn" href={`${appUrl}/simulator`}>Essayer le simulateur</a>
    </p>
  </section>
```

- [ ] **Step 2 : Ajouter le CSS de la section**

Dans le bloc `<style>` de `index.astro`, ajouter :

```css
  .sim { padding: 3.5rem clamp(1rem,5vw,4rem); border-top: 1px solid var(--color-rule); text-align: center; }
  .sim-label { font-size: .75rem; letter-spacing: 1px; text-transform: uppercase; color: var(--color-oxblood); font-weight: 700; margin: 0 0 .5rem; }
  .sim h2 { font-size: clamp(1.5rem,3.5vw,2rem); margin: 0 auto .6rem; max-width: 20ch; }
  .sim-sub { color: var(--color-ink-muted); max-width: 48ch; margin: 0 auto 1.6rem; line-height: 1.55; }
  .cmp { display: flex; gap: .75rem; max-width: 34rem; margin: 0 auto 1.5rem; flex-wrap: wrap; }
  .cmp-card { flex: 1 1 14rem; border: 1px solid var(--color-rule); border-radius: 10px; padding: 1rem; background: var(--color-cream); text-align: left; }
  .cmp-card.win { border: 1.5px solid var(--color-olive); background: #fff; }
  .cmp-h { margin: 0 0 .4rem; font-size: .7rem; letter-spacing: .4px; text-transform: uppercase; color: var(--color-ink-muted); font-weight: 700; }
  .cmp-big { font-size: 1.6rem; font-weight: 800; margin: .2rem 0; letter-spacing: -.5px; }
  .cmp-big.muted { color: var(--color-ink-muted); }
  .cmp-big.good { color: var(--color-seal-green); }
  .cmp-s { color: var(--color-ink-muted); font-size: .8rem; margin: 0; line-height: 1.4; }
  .sim-shot { margin: 0 auto 1.5rem; max-width: 34rem; }
  .sim-shot img { width: 100%; height: auto; border: 1px solid var(--color-rule-strong); border-radius: 12px; display: block; }
  .sim-shot figcaption { font-size: .8rem; font-style: italic; color: var(--color-ink-muted); margin-top: .6rem; }
```

- [ ] **Step 3 : Construire et vérifier le contenu + zéro-JS**

Run:
```bash
export PATH=/opt/homebrew/bin:$PATH
npm run build --prefix site
grep -c 'Le vrai rendement' site/dist/index.html
grep -c '+348 €/mois' site/dist/index.html
grep -c 'seal-green' site/dist/index.html
grep -o '<script' site/dist/index.html | wc -l | tr -d ' '
```
Expected : `1` pour le titre, `1` pour « +348 €/mois », au moins `1` pour la couleur seal-green (inlinée), et `1` pour `<script` (le seul admis, le JSON-LD). Un `<script` supérieur à 1 = JavaScript de page à retirer.

- [ ] **Step 4 : Commit**

```bash
export PATH=/opt/homebrew/bin:$PATH
git add site/src/pages/index.astro
git commit -m "feat(site): section simulateur en vedette (comparatif brut-vs-net + capture)"
```

---

### Task 4 : Sections « Comment ça marche » et « Pour qui »

**Files:**
- Modify: `site/src/pages/index.astro`

**Interfaces:**
- Consumes: rien de neuf.

- [ ] **Step 1 : Ajouter les deux sections après `.features`**

Insérer **après** la `<section class="features">` (et avant le futur bloc idée) :

```astro
  <section class="steps">
    <h2>Comment ça marche</h2>
    <ol class="steps-grid">
      <li><span class="step-n">1</span><b>Ajoutez un bien</b><span>Adresse, loyer, crédit — en une minute.</span></li>
      <li><span class="step-n">2</span><b>Suivez</b><span>Loyers encaissés, retards, charges récupérables.</span></li>
      <li><span class="step-n">3</span><b>Pilotez</b><span>Quittances conformes et cash-flow réel, à jour.</span></li>
    </ol>
  </section>

  <section class="who">
    <h2>Pensé pour les bailleurs particuliers</h2>
    <p>De un à quelques biens. Pour arrêter le tableur sans passer à une usine à gaz — l'essentiel de la gestion locative, fait correctement.</p>
  </section>
```

- [ ] **Step 2 : Ajouter le CSS**

```css
  .steps { padding: 3.5rem clamp(1rem,5vw,4rem); border-top: 1px solid var(--color-rule); background: var(--color-paper); }
  .steps h2, .who h2 { text-align: center; font-size: clamp(1.4rem,3vw,1.8rem); margin: 0 0 1.6rem; }
  .steps-grid { list-style: none; padding: 0; margin: 0 auto; max-width: 52rem; display: grid; gap: 1rem; grid-template-columns: repeat(auto-fit, minmax(14rem, 1fr)); }
  .steps-grid li { display: flex; flex-direction: column; gap: .3rem; background: var(--color-cream); border: 1px solid var(--color-rule); border-radius: 10px; padding: 1.1rem; }
  .step-n { display: inline-flex; align-items: center; justify-content: center; width: 1.6rem; height: 1.6rem; border-radius: 50%; background: var(--color-olive); color: var(--color-cream); font-weight: 700; font-size: .85rem; margin-bottom: .3rem; }
  .steps-grid b { font-size: .98rem; }
  .steps-grid span:last-child { color: var(--color-ink-muted); font-size: .88rem; line-height: 1.45; }
  .who { padding: 3.5rem clamp(1rem,5vw,4rem); border-top: 1px solid var(--color-rule); text-align: center; }
  .who p { color: var(--color-ink-muted); max-width: 46ch; margin: 0 auto; line-height: 1.6; }
```

- [ ] **Step 3 : Construire et vérifier**

Run:
```bash
export PATH=/opt/homebrew/bin:$PATH
npm run build --prefix site
grep -c 'Comment ça marche' site/dist/index.html
grep -c 'bailleurs particuliers' site/dist/index.html
grep -o '<script' site/dist/index.html | wc -l | tr -d ' '
```
Expected : `1`, `1` (au moins), et `1` pour `<script`.

- [ ] **Step 4 : Commit**

```bash
export PATH=/opt/homebrew/bin:$PATH
git add site/src/pages/index.astro
git commit -m "feat(site): sections « comment ça marche » et « pour qui »"
```

---

### Task 5 : Section « Proposez une idée » (bouton Tally)

**Files:**
- Modify: `site/src/pages/index.astro`
- Create: `scripts/check-vitrine-idea-url.sh`
- Modify: `.github/workflows/deploy.yml` (job `build-and-deploy`)

**Interfaces:**
- Consumes: `ideaFormUrl` (Task 1).

- [ ] **Step 1 : Importer `ideaFormUrl` et ajouter la section**

En tête de `index.astro`, dans le frontmatter (`---`), à côté de l'import `appUrl` :

```astro
import { ideaFormUrl } from '../lib/links';
```

Puis, **avant** le pied de page (la section est la dernière du `<main>`) :

```astro
  <section class="idea">
    <h2>Baillan se construit avec vous</h2>
    <p>Une idée, un manque, une gêne ? Les retours arrivent directement chez la personne qui écrit le code.</p>
    <a class="btn" href={ideaFormUrl} target="_blank" rel="noopener">Proposer une idée →</a>
  </section>
```

- [ ] **Step 2 : Ajouter le CSS**

```css
  .idea { padding: 3.5rem clamp(1rem,5vw,4rem); border-top: 1px solid var(--color-rule); text-align: center; background: var(--color-kraft); }
  .idea h2 { font-size: clamp(1.4rem,3vw,1.8rem); margin: 0 0 .6rem; }
  .idea p { color: var(--color-ink); max-width: 44ch; margin: 0 auto 1.4rem; line-height: 1.55; }
```

- [ ] **Step 3 : Écrire le garde-fou de build**

Un lien Tally non configuré (racine `tally.so/` sans formulaire) ne doit pas partir en **production**. En staging c'est toléré (placeholder), en prod non.

```bash
#!/usr/bin/env bash
# Garde-fou — l'URL du formulaire d'idées doit être un vrai formulaire Tally
# avant un build de PRODUCTION. Le placeholder `https://tally.so/` (racine)
# est toléré en staging (SITE_ENV=staging) mais refusé en prod.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

url=$(grep -oE "ideaFormUrl = '[^']*'" site/src/lib/links.ts | sed "s/.*= '//;s/'//")

if [ "${SITE_ENV:-}" = "staging" ]; then
  echo "ℹ️  SITE_ENV=staging — placeholder Tally toléré ($url)."
  exit 0
fi

case "$url" in
  https://tally.so/|https://tally.so|"")
    echo "❌ ideaFormUrl est encore le placeholder ($url). Renseigner le vrai"
    echo "   formulaire Tally dans site/src/lib/links.ts avant un build de prod."
    exit 1 ;;
  https://tally.so/*)
    echo "✅ ideaFormUrl configuré ($url)." ; exit 0 ;;
  *)
    echo "❌ ideaFormUrl ne pointe pas vers tally.so ($url)." ; exit 1 ;;
esac
```

- [ ] **Step 4 : Vérifier le garde-fou dans les deux modes**

Run:
```bash
export PATH=/opt/homebrew/bin:$PATH
chmod +x scripts/check-vitrine-idea-url.sh
SITE_ENV=staging bash scripts/check-vitrine-idea-url.sh; echo "staging exit=$?"
bash scripts/check-vitrine-idea-url.sh; echo "prod exit=$?"
```
Expected : staging `exit=0` (toléré), prod `exit=1` (placeholder refusé). Quand le vrai formulaire sera renseigné, prod passera à `exit=0`.

- [ ] **Step 5 : Câbler le garde-fou dans le déploiement (pas la CI)**

⚠️ **Ne pas** mettre ce garde-fou dans le job `site` de `ci.yml` : ce job tourne sur chaque PR en mode prod, il **bloquerait toute PR** tant que l'URL Tally réelle n'existe pas. Le garde-fou vit dans le **déploiement**, où il distingue staging (toléré) de prod (exigé).

Dans `.github/workflows/deploy.yml`, job `build-and-deploy`, **après** l'étape « Build marketing site », ajouter — en lui passant le même `SITE_ENV` que le build (staging sur `develop`, vide sur `main`) :

```yaml
      - name: Check idea form URL (prod enforces, staging tolerates)
        env:
          SITE_ENV: ${{ needs.determine-env.outputs.app_env == 'dev' && 'staging' || '' }}
        run: bash scripts/check-vitrine-idea-url.sh
```

Effet : un déploiement `develop` → staging passe avec le placeholder ; un déploiement `main` → prod **échoue** tant que l'URL Tally réelle n'est pas renseignée (Task 1). Les PR et le job `site` de la CI ne sont pas bloqués.

- [ ] **Step 6 : Construire et vérifier la section**

Run:
```bash
export PATH=/opt/homebrew/bin:$PATH
npm run build --prefix site
grep -c 'Proposer une idée' site/dist/index.html
grep -c 'rel="noopener"' site/dist/index.html
grep -o '<script' site/dist/index.html | wc -l | tr -d ' '
```
Expected : `1`, `1` (au moins), `1` pour `<script`.

- [ ] **Step 7 : Commit**

```bash
export PATH=/opt/homebrew/bin:$PATH
git add site/src/pages/index.astro scripts/check-vitrine-idea-url.sh .github/workflows/deploy.yml
git commit -m "feat(site): section « proposez une idée » + garde-fou URL Tally en prod"
```

---

### Task 6 : Hero enrichi + finition et vérification d'ensemble

**Files:**
- Modify: `site/src/pages/index.astro`

**Interfaces:**
- Consumes: rien de neuf.

- [ ] **Step 1 : Enrichir le hero**

Dans `index.astro`, remplacer le contenu de `<section class="hero">` par une version avec pilule d'audience (garder les deux CTA existants via `appUrl`) :

```astro
  <section class="hero">
    <p class="hero-pill">Gestion locative pour bailleurs particuliers</p>
    <h1>La gestion locative,<br>enfin sans tableur</h1>
    <p class="lede">
      Quittances conformes, suivi des loyers et des charges — et un simulateur
      de rentabilité qui dit la vérité sur ce que rapporte vraiment un bien.
    </p>
    <p class="actions">
      <a class="btn" href={`${appUrl}/signup`}>Commencer gratuitement</a>
      <a class="btn-ghost" href={`${appUrl}/simulator`}>Essayer le simulateur</a>
    </p>
  </section>
```

- [ ] **Step 2 : Ajouter le CSS de la pilule (le reste du hero existe déjà)**

```css
  .hero-pill { display: inline-block; font-size: .78rem; font-weight: 700; letter-spacing: .3px; color: var(--color-olive); background: var(--color-kraft); padding: .3rem .8rem; border-radius: 999px; margin-bottom: 1rem; }
```

- [ ] **Step 3 : Vérification d'ensemble — build, zéro-JS, crawlabilité, cohérence**

Run:
```bash
export PATH=/opt/homebrew/bin:$PATH
npm run build --prefix site
echo "scripts (doit être 1) : $(grep -o '<script' site/dist/index.html | wc -l | tr -d ' ')"
echo "modules JS (doit être 0) : $(grep -c 'type=\"module\"' site/dist/index.html || true)"
echo "H1 présent : $(grep -c '<h1' site/dist/index.html)"
echo "sections (sim/steps/who/idea) :"
for s in 'Le vrai rendement' 'Comment ça marche' 'bailleurs particuliers' 'Proposer une idée'; do printf '  %-22s %s\n' "$s" "$(grep -c "$s" site/dist/index.html)"; done
echo "cohérence chiffres (chacun 1) :"
for n in '8,0 %' '+348 €/mois' '+347,88 €' '7,60 %'; do printf '  %-14s %s\n' "$n" "$(grep -c "$n" site/dist/index.html)"; done
echo "couleur en dur interdite (doit être 0) : $(grep -oiE '#[0-9a-f]{6}' site/dist/index.html | grep -viE '#fcfaf5|#f7f4ed|#1b1a17|#6b665d|#3f4a2a|#e8e2d3|#c9c1ab|#e4d9bd|#9a3b2f|#2e5339|#6e3a1f|#ffffff|#fff' | wc -l | tr -d ' ')"
```
Expected : scripts `1`, modules JS `0`, H1 `1`, chaque section `≥1`, chaque chiffre `1`, et `0` couleur hors palette (les hex listés sont les tokens + blanc, inlinés par le build — normal).

- [ ] **Step 4 : Vérification responsive (largeurs de coupe)**

Ouvrir le build dans un navigateur (ou le preview) et vérifier à ~375 px de large : le comparatif passe en une colonne, la capture reste dans le cadre (pas de débordement horizontal), les CTA s'empilent proprement. Rapporter une capture d'écran mobile + desktop.

- [ ] **Step 5 : Commit**

```bash
export PATH=/opt/homebrew/bin:$PATH
git add site/src/pages/index.astro
git commit -m "feat(site): hero enrichi (pilule d'audience) + finition landing"
```

---

## Déploiement

Le merge sur `develop` déploie automatiquement `marketing-stage` (CI, `SITE_ENV=staging`) → la vitrine enrichie est visible sur `stage.baillan.com`. Le garde-fou URL Tally tolère le placeholder en staging ; il faudra le vrai formulaire Tally avant que ça parte en prod (`main`).

## Ce que ce plan ne fait pas

- L'anglais / i18n, les pages-outils, le blog (v2 de FEAT-050).
- La création du formulaire Tally lui-même (action propriétaire) et sa conformité RGPD.
- Toute modification du gabarit `BaseLayout.astro` ou des pages FAQ / à-propos / légal.
