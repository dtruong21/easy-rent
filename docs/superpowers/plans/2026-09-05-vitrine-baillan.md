# Vitrine Baillan — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Construire le site vitrine statique et crawlable de Baillan, déployé sur `staging.baillan.com`, dont les couleurs dérivent mécaniquement du thème de l'application.

**Architecture:** Les couleurs deviennent une source canonique JSON dont un générateur Dart tire deux miroirs — les constantes de l'app et les variables CSS de la vitrine. Le site est un projet Astro dans `site/`, servi par deux nouvelles cibles Firebase Hosting à côté des deux cibles existantes de l'app. Chaque page produit du HTML complet sans JavaScript, ce qui est l'inverse exact de la contrainte CanvasKit qui rend l'app inindexable.

**Tech Stack:** Astro, Dart (générateur), Firebase Hosting multi-site, GitHub Actions.

**Spec:** [`docs/superpowers/specs/2026-09-05-vitrine-baillan-migration-domaine-design.md`](../specs/2026-09-05-vitrine-baillan-migration-domaine-design.md)

## Global Constraints

- Domaine de production : `baillan.com` (deux « l »). Staging : `staging.baillan.com` pour la vitrine, `app.staging.baillan.com` pour l'app.
- Ce plan **ne fait pas la bascule de domaine**. Il s'arrête à une vitrine vérifiée sur staging. La bascule est un runbook séparé, conditionné au DNS et à la Play Console.
- Aucun déploiement Firebase sans `--only` : quatre cibles partagent le projet, un déploiement non scopé écrase les autres.
- Aucune valeur de couleur ne change. Le rendu de l'app doit rester strictement identique, verrouillé par un test.
- Tout fichier généré porte l'en-tête `// GENERATED — do not edit.` et est commité.
- Le site est en français uniquement. Astro est configuré dès maintenant avec `prefixDefaultLocale: false` pour que `/en/*` puisse s'ajouter plus tard sans déplacer les URLs françaises.
- Le légal versionné (confidentialité, CGU) reste canonique dans l'app ; la vitrine y renvoie par lien, elle ne le recopie pas.
- Commandes à lancer depuis la racine du dépôt, avec `/opt/homebrew/bin` dans le `PATH`.

## Structure des fichiers

| Fichier | Responsabilité |
|---|---|
| `config/theme_tokens.json` | Source canonique unique des 19 couleurs |
| `tool/gen_theme_tokens.dart` | Générateur : JSON → miroir Dart + miroir CSS |
| `lib/core/theme/app_palette.g.dart` | Miroir Dart généré, consommé par `AppTheme` |
| `site/src/styles/tokens.css` | Miroir CSS généré, consommé par la vitrine |
| `scripts/check-theme-tokens.sh` | Garde-fou CI : régénère et échoue si divergence |
| `site/src/layouts/BaseLayout.astro` | Chrome commun : `<head>`, nav, pied de page |
| `site/src/pages/*.astro` | Une page par fichier |
| `site/astro.config.mjs` | Configuration Astro, site canonique, i18n |

---

### Task 1 : Source canonique des couleurs et générateur

**Files:**
- Create: `config/theme_tokens.json`
- Create: `tool/gen_theme_tokens.dart`
- Create: `lib/core/theme/app_palette.g.dart` (généré)
- Create: `site/src/styles/tokens.css` (généré)
- Create: `scripts/check-theme-tokens.sh`
- Create: `test/core/theme/app_palette_test.dart`
- Modify: `lib/core/theme/app_theme.dart` (lignes 25-87, les 19 constantes)
- Modify: `.github/workflows/ci.yml` (job `analyze-test`)
- Modify: `docs/state/DESIGN_TOKENS.md` (la source de vérité change)

**Interfaces:**
- Produces: `AppPalette.<nom>` pour les 19 couleurs, `Color` non-nullable ; `AppTheme.<nom>` conserve exactement la même signature publique qu'aujourd'hui, donc **aucun site d'appel ne change**.
- Produces: variables CSS `--color-<nom-kebab>` dans `site/src/styles/tokens.css`.

> **Deux choses à savoir avant de commencer.**
>
> `test/core/theme/app_theme_design_tokens_test.dart` **existe déjà** et
> verrouille une partie des couleurs via `AppTheme.<nom>`. Ne pas le modifier
> et ne pas le remplacer : comme l'API publique `AppTheme.<nom>` est conservée,
> il doit continuer de passer tel quel. S'il casse, c'est que le déménagement a
> changé une valeur — c'est précisément le signal recherché.
>
> `app_theme.dart` déclare aussi des **alias sémantiques** (`acquitte`, `echu`,
> `consigne`, `archive`) qui pointent vers des jetons techniques. Ce ne sont pas
> des couleurs brutes : ils restent écrits à la main et ne sont **pas** générés.
> Seules les 19 constantes `Color(0x…)` deviennent canoniques.

- [ ] **Step 1 : Écrire la source canonique**

Les 19 valeurs sont celles présentes aujourd'hui dans `app_theme.dart`. Les recopier exactement — toute divergence ici change le rendu de l'app.

```json
{
  "_comment": "SOURCE CANONIQUE des couleurs Baillan. Générer les miroirs : dart run tool/gen_theme_tokens.dart",
  "colors": {
    "paper": "#F7F4ED",
    "paperDeep": "#EFE9DA",
    "cream": "#FCFAF5",
    "ink": "#1B1A17",
    "inkSurface": "#2A2823",
    "inkMuted": "#6B665D",
    "rule": "#E8E2D3",
    "olive": "#3F4A2A",
    "oliveMid": "#5E6A45",
    "oliveSoft": "#B5B89D",
    "oxblood": "#9A3B2F",
    "sealGreen": "#2E5339",
    "ochre": "#7E5612",
    "indigoInk": "#2A3656",
    "kraft": "#E4D9BD",
    "stone": "#A8A39A",
    "oliveDeep": "#34401F",
    "ruleStrong": "#C9C1AB",
    "amountNegative": "#6E3A1F"
  }
}
```

- [ ] **Step 2 : Écrire le test de non-régression, qui doit échouer**

Ce test est le verrou du plan : il prouve qu'aucune couleur n'a bougé pendant le déménagement.

```dart
// test/core/theme/app_palette_test.dart
import 'package:easyrent/core/theme/app_palette.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Valeurs relevées dans app_theme.dart AVANT la migration vers la source
  // canonique. Si l'une d'elles change, le rendu de l'app change — ce test
  // existe pour rendre ce changement impossible par accident.
  const expected = <String, int>{
    'paper': 0xFFF7F4ED,
    'paperDeep': 0xFFEFE9DA,
    'cream': 0xFFFCFAF5,
    'ink': 0xFF1B1A17,
    'inkSurface': 0xFF2A2823,
    'inkMuted': 0xFF6B665D,
    'rule': 0xFFE8E2D3,
    'olive': 0xFF3F4A2A,
    'oliveMid': 0xFF5E6A45,
    'oliveSoft': 0xFFB5B89D,
    'oxblood': 0xFF9A3B2F,
    'sealGreen': 0xFF2E5339,
    'ochre': 0xFF7E5612,
    'indigoInk': 0xFF2A3656,
    'kraft': 0xFFE4D9BD,
    'stone': 0xFFA8A39A,
    'oliveDeep': 0xFF34401F,
    'ruleStrong': 0xFFC9C1AB,
    'amountNegative': 0xFF6E3A1F,
  };

  test('les 19 couleurs générées valent exactement celles d\'avant', () {
    final actual = <String, Color>{
      'paper': AppPalette.paper,
      'paperDeep': AppPalette.paperDeep,
      'cream': AppPalette.cream,
      'ink': AppPalette.ink,
      'inkSurface': AppPalette.inkSurface,
      'inkMuted': AppPalette.inkMuted,
      'rule': AppPalette.rule,
      'olive': AppPalette.olive,
      'oliveMid': AppPalette.oliveMid,
      'oliveSoft': AppPalette.oliveSoft,
      'oxblood': AppPalette.oxblood,
      'sealGreen': AppPalette.sealGreen,
      'ochre': AppPalette.ochre,
      'indigoInk': AppPalette.indigoInk,
      'kraft': AppPalette.kraft,
      'stone': AppPalette.stone,
      'oliveDeep': AppPalette.oliveDeep,
      'ruleStrong': AppPalette.ruleStrong,
      'amountNegative': AppPalette.amountNegative,
    };

    expect(actual.length, expected.length,
        reason: 'une couleur a été ajoutée ou retirée de la palette');
    for (final entry in expected.entries) {
      expect(actual[entry.key]!.toARGB32(), entry.value,
          reason: 'la couleur ${entry.key} a changé de valeur');
    }
  });
}
```

- [ ] **Step 3 : Lancer le test pour vérifier qu'il échoue**

Run: `flutter test test/core/theme/app_palette_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:easyrent/core/theme/app_palette.g.dart'`

- [ ] **Step 4 : Écrire le générateur**

Il lit le JSON, valide, et écrit les deux miroirs. La validation compte : un JSON malformé doit arrêter la génération, pas produire un miroir tronqué.

```dart
// tool/gen_theme_tokens.dart
//
// Générateur des miroirs de la palette Baillan.
//
//   dart run tool/gen_theme_tokens.dart
//
// Lit `config/theme_tokens.json` (SOURCE CANONIQUE UNIQUE) et écrit deux
// miroirs : `lib/core/theme/app_palette.g.dart` pour l'app, et
// `site/src/styles/tokens.css` pour la vitrine. Garde-fou :
// `bash scripts/check-theme-tokens.sh`.
//
// Pourquoi générer plutôt que laisser chaque camp déclarer ses couleurs : la
// vitrine et l'app doivent être indiscernables à l'œil. Une double déclaration
// rend la divergence possible ; la génération la rend inexprimable.

import 'dart:convert';
import 'dart:io';

const _source = 'config/theme_tokens.json';
const _dartOut = 'lib/core/theme/app_palette.g.dart';
const _cssOut = 'site/src/styles/tokens.css';

/// `oliveMid` -> `olive-mid`, pour les noms de variables CSS.
String _kebab(String camel) => camel
    .replaceAllMapped(RegExp(r'[A-Z]'), (m) => '-${m[0]!.toLowerCase()}');

void main() {
  final raw = File(_source).readAsStringSync();
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final colors = (decoded['colors'] as Map<String, dynamic>).cast<String, String>();

  if (colors.isEmpty) {
    stderr.writeln('$_source ne déclare aucune couleur.');
    exit(1);
  }

  final hexRe = RegExp(r'^#[0-9A-F]{6}$');
  for (final entry in colors.entries) {
    if (!hexRe.hasMatch(entry.value)) {
      stderr.writeln(
          'Couleur invalide : ${entry.key} = "${entry.value}". '
          'Format attendu : #RRGGBB en majuscules.');
      exit(1);
    }
  }

  const header = '// GENERATED — do not edit. Source: $_source\n'
      '// Regenerate: dart run tool/gen_theme_tokens.dart\n'
      '// Guard: bash scripts/check-theme-tokens.sh\n';

  final dart = StringBuffer()
    ..writeln(header)
    ..writeln("import 'package:flutter/painting.dart';")
    ..writeln()
    ..writeln('/// Palette canonique de Baillan, partagée avec la vitrine.')
    ..writeln('abstract final class AppPalette {');
  for (final entry in colors.entries) {
    final argb = '0xFF${entry.value.substring(1)}';
    dart.writeln('  static const Color ${entry.key} = Color($argb);');
  }
  dart.writeln('}');
  File(_dartOut).writeAsStringSync(dart.toString());

  final css = StringBuffer()
    ..writeln(header.replaceAll('//', '/*').replaceAll('\n', ' */\n').trimRight())
    ..writeln(':root {');
  for (final entry in colors.entries) {
    css.writeln('  --color-${_kebab(entry.key)}: ${entry.value};');
  }
  css.writeln('}');
  Directory(File(_cssOut).parent.path).createSync(recursive: true);
  File(_cssOut).writeAsStringSync(css.toString());

  stdout.writeln('${colors.length} couleurs → $_dartOut, $_cssOut');
}
```

- [ ] **Step 5 : Générer et formater**

Run:
```bash
dart run tool/gen_theme_tokens.dart && dart format lib/core/theme/app_palette.g.dart
```
Expected: `19 couleurs → lib/core/theme/app_palette.g.dart, site/src/styles/tokens.css`

- [ ] **Step 6 : Lancer le test, qui doit maintenant passer**

Run: `flutter test test/core/theme/app_palette_test.dart`
Expected: PASS

- [ ] **Step 7 : Faire consommer le miroir par `AppTheme`**

Dans `lib/core/theme/app_theme.dart`, remplacer chacune des 19 déclarations `static const Color <nom> = Color(0x…);` par une délégation. Conserver les commentaires de documentation existants, qui expliquent l'usage de chaque teinte — ils ont de la valeur et ne sont pas générés.

```dart
import 'package:easyrent/core/theme/app_palette.g.dart';

// … dans class AppTheme :
  static const Color paper = AppPalette.paper;
  static const Color paperDeep = AppPalette.paperDeep;
  static const Color cream = AppPalette.cream;
  static const Color ink = AppPalette.ink;
  static const Color inkSurface = AppPalette.inkSurface;
  static const Color inkMuted = AppPalette.inkMuted;
  static const Color rule = AppPalette.rule;
  static const Color olive = AppPalette.olive;
  static const Color oliveMid = AppPalette.oliveMid;
  static const Color oliveSoft = AppPalette.oliveSoft;
  static const Color oxblood = AppPalette.oxblood;
  static const Color sealGreen = AppPalette.sealGreen;
  static const Color ochre = AppPalette.ochre;
  static const Color indigoInk = AppPalette.indigoInk;
  static const Color kraft = AppPalette.kraft;
  static const Color stone = AppPalette.stone;
  static const Color oliveDeep = AppPalette.oliveDeep;
  static const Color ruleStrong = AppPalette.ruleStrong;
  static const Color amountNegative = AppPalette.amountNegative;
```

L'API publique ne bouge pas : `AppTheme.olive` reste `AppTheme.olive`, donc aucun site d'appel n'est touché.

- [ ] **Step 8 : Vérifier que l'app compile et que rien n'a bougé**

Run:
```bash
flutter analyze && flutter test
```
Expected: analyze sans erreur, toute la suite au vert — **y compris**
`test/core/theme/app_theme_design_tokens_test.dart`, qui vérifiait déjà les
hex via `AppTheme.<nom>` avant ce plan. Un échec ici signale une couleur mal
recopiée à l'étape 1.

- [ ] **Step 9 : Écrire le garde-fou**

```bash
#!/usr/bin/env bash
# Garde-fou — miroirs de la palette à jour.
#
# Échoue si `app_palette.g.dart` ou `tokens.css` diffèrent de ce que produit
# le générateur. Deux causes possibles : un miroir édité à la main, ou la
# source canonique modifiée sans régénérer. Dans les deux cas, la vitrine et
# l'app risquent d'afficher des couleurs différentes.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

dart_out="lib/core/theme/app_palette.g.dart"
css_out="site/src/styles/tokens.css"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Sauvegarder l'état commité pour le comparer au résultat régénéré. On compare
# aux fichiers de l'ARBRE DE TRAVAIL, pas à `git diff` : un miroir encore non
# suivi par git échapperait sinon à la vérification.
for f in "$dart_out" "$css_out"; do
  if [ ! -f "$f" ]; then
    echo "❌ Miroir manquant : $f — lancer : dart run tool/gen_theme_tokens.dart"
    exit 1
  fi
  cp "$f" "$tmp/$(basename "$f").before"
done

dart run tool/gen_theme_tokens.dart >/dev/null
dart format "$dart_out" >/dev/null

fail=0
for f in "$dart_out" "$css_out"; do
  if ! diff -q "$tmp/$(basename "$f").before" "$f" >/dev/null; then
    echo "❌ $f est périmé :"
    diff -u "$tmp/$(basename "$f").before" "$f" | head -30 || true
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo ""
  echo "   Régénérer puis committer : dart run tool/gen_theme_tokens.dart"
  exit 1
fi

echo "✅ Miroirs de la palette à jour."
```

- [ ] **Step 10 : Vérifier que le garde-fou attrape une vraie divergence**

Un garde-fou qui ne dit jamais non ne vaut rien. Le prouver :

```bash
chmod +x scripts/check-theme-tokens.sh
bash scripts/check-theme-tokens.sh                      # attendu : ✅
printf '\n/* sabotage */\n' >> site/src/styles/tokens.css
bash scripts/check-theme-tokens.sh; echo "exit=$?"      # attendu : ❌ et exit=1
git checkout -- site/src/styles/tokens.css
bash scripts/check-theme-tokens.sh                      # attendu : ✅
```
Expected: le deuxième appel échoue avec `exit=1`, les deux autres passent.

- [ ] **Step 11 : Câbler en CI**

Dans `.github/workflows/ci.yml`, job `analyze-test`, ajouter l'étape à la suite des garde-fous existants :

```yaml
      - name: Check theme token mirrors
        run: bash scripts/check-theme-tokens.sh
```

- [ ] **Step 12 : Mettre à jour la documentation des jetons**

`docs/state/DESIGN_TOKENS.md` annonce en tête que la source de vérité est
`lib/core/theme/app_theme.dart`. Ce n'est plus vrai. Remplacer l'en-tête par :

```markdown
> **Source de vérité** : [`config/theme_tokens.json`](../../config/theme_tokens.json).
> Les constantes de [`app_theme.dart`](../../lib/core/theme/app_theme.dart) et les
> variables CSS de la vitrine en sont deux miroirs générés
> (`dart run tool/gen_theme_tokens.dart`, garde-fou `scripts/check-theme-tokens.sh`).
> Les **alias sémantiques** (`acquitte`, `echu`, `consigne`, `archive`) restent
> écrits à la main dans `app_theme.dart` : ce sont des indirections métier, pas
> des couleurs.
> **Dernière mise à jour** : 2026-09-05 (source canonique partagée avec la vitrine).
```

La règle d'or du document — utiliser l'alias sémantique plutôt que le jeton
technique, et jamais une couleur en dur — reste valable telle quelle.

- [ ] **Step 13 : Commit**

```bash
git add config/theme_tokens.json tool/gen_theme_tokens.dart \
        lib/core/theme/app_palette.g.dart lib/core/theme/app_theme.dart \
        site/src/styles/tokens.css scripts/check-theme-tokens.sh \
        test/core/theme/app_palette_test.dart .github/workflows/ci.yml \
        docs/state/DESIGN_TOKENS.md
git commit -m "feat(theme): source canonique unique pour les 19 couleurs

La vitrine et l'app doivent être indiscernables à l'œil. Les couleurs
deviennent donc une source canonique JSON dont un générateur tire deux
miroirs : les constantes Dart de l'app et les variables CSS du site. Même
patron que config/entitlements.json — la divergence devient inexprimable
plutôt que simplement détectable.

Aucune valeur ne change : un test compare les 19 couleurs à leur valeur
d'avant migration, et l'API publique AppTheme.<nom> est conservée, donc
aucun site d'appel n'est touché."
```

---

### Task 2 : Scaffold Astro

**Files:**
- Create: `site/package.json`, `site/astro.config.mjs`, `site/tsconfig.json`
- Create: `site/src/layouts/BaseLayout.astro`
- Create: `site/src/pages/index.astro` (page d'attente, remplacée en Task 4)
- Modify: `.gitignore`

**Interfaces:**
- Consumes: `site/src/styles/tokens.css` (Task 1).
- Produces: `BaseLayout.astro`, qui accepte les props `title` (string), `description` (string) et `noindex` (boolean, défaut `false`). Toutes les pages des Tasks 4 à 6 l'utilisent.

- [ ] **Step 1 : Créer le projet**

```bash
npm create astro@latest site -- --template minimal --install --no-git --typescript strict
```

- [ ] **Step 2 : Épingler la version**

Astro doit être épinglé exactement — une montée de version silencieuse sur un site marketing est une régression invisible jusqu'à ce qu'un lecteur la voie.

```bash
cd site && npm pkg get dependencies.astro   # relever la version installée
npm install --save-exact astro@<version relevée>
```

- [ ] **Step 3 : Ignorer les artefacts de build**

Ajouter à `.gitignore` :

```
# Site vitrine (Astro)
site/node_modules/
site/dist/
site/.astro/
```

- [ ] **Step 4 : Configurer Astro**

```js
// site/astro.config.mjs
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
```

- [ ] **Step 5 : Écrire le gabarit commun**

```astro
---
// site/src/layouts/BaseLayout.astro
import '../styles/tokens.css';

interface Props {
  title: string;
  description: string;
  noindex?: boolean;
}
const { title, description, noindex = false } = Astro.props;
const canonical = new URL(Astro.url.pathname, Astro.site).href;
const appUrl = 'https://app.baillan.com';
---
<!doctype html>
<html lang="fr">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>{title}</title>
    <meta name="description" content={description} />
    <link rel="canonical" href={canonical} />
    {noindex && <meta name="robots" content="noindex, nofollow" />}
    <meta property="og:title" content={title} />
    <meta property="og:description" content={description} />
    <meta property="og:type" content="website" />
    <meta property="og:url" content={canonical} />
    <slot name="head" />
  </head>
  <body>
    <header class="site-nav">
      <a class="brand" href="/">Baillan</a>
      <nav>
        <a href="/faq">FAQ</a>
        <a href="/a-propos">À propos</a>
        <a class="cta" href={appUrl}>Ouvrir l'app</a>
      </nav>
    </header>
    <main><slot /></main>
    <footer class="site-footer">
      <a href="/mentions-legales">Mentions légales</a>
      <a href={`${appUrl}/privacy`}>Confidentialité</a>
      <a href={`${appUrl}/terms`}>CGU</a>
      <a href="/supprimer-mon-compte">Supprimer mon compte</a>
    </footer>
  </body>
</html>

<style>
  :root { color-scheme: light; }
  body {
    margin: 0;
    background: var(--color-cream);
    color: var(--color-ink);
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    line-height: 1.6;
  }
  .site-nav, .site-footer {
    display: flex; align-items: center; gap: 1.5rem;
    padding: 1rem clamp(1rem, 5vw, 4rem);
  }
  .site-nav { border-bottom: 1px solid var(--color-rule); }
  .site-nav nav { margin-left: auto; display: flex; gap: 1.5rem; align-items: center; }
  .brand { font-weight: 800; font-size: 1.15rem; text-decoration: none; color: var(--color-ink); }
  .site-nav a, .site-footer a { color: var(--color-ink-muted); text-decoration: none; }
  .site-nav a:hover, .site-footer a:hover { color: var(--color-ink); text-decoration: underline; }
  .site-nav .cta {
    background: var(--color-olive); color: var(--color-cream);
    padding: .55rem 1rem; border-radius: 7px; font-weight: 650;
  }
  .site-footer {
    border-top: 1px solid var(--color-rule);
    margin-top: 4rem; font-size: .9rem; flex-wrap: wrap;
  }
  main { max-width: 68rem; margin: 0 auto; padding: 0 clamp(1rem, 5vw, 4rem); }
</style>
```

- [ ] **Step 6 : Page d'attente, remplacée en Task 4**

```astro
---
// site/src/pages/index.astro
import BaseLayout from '../layouts/BaseLayout.astro';
---
<BaseLayout title="Baillan — gestion locative" description="La gestion locative sans tableur.">
  <h1>Baillan</h1>
</BaseLayout>
```

- [ ] **Step 7 : Vérifier que le site se construit et que les tokens arrivent bien**

```bash
cd site && npm run build
grep -q '#3F4A2A' dist/index.html dist/_astro/*.css && echo "olive présent" || echo "TOKENS ABSENTS"
```
Expected: le build réussit et affiche `olive présent` — la chaîne source canonique → CSS → page est prouvée de bout en bout.

- [ ] **Step 8 : Commit**

```bash
git add site/ .gitignore
git commit -m "feat(site): scaffold Astro de la vitrine

Sortie sans JavaScript par défaut, donc parfaitement crawlable — l'inverse
exact de la contrainte CanvasKit qui rend l'app inindexable. Le gabarit
commun consomme les variables CSS générées depuis la palette de l'app.

Version d'Astro épinglée exactement : sur un site marketing, une montée de
version silencieuse est une régression que personne ne voit avant un lecteur."
```

---

### Task 3 : Deux cibles Firebase Hosting et déploiement staging

**Files:**
- Modify: `firebase.json` (tableau `hosting`, aujourd'hui 2 blocs)
- Modify: `.firebaserc` (bloc `targets`)
- Modify: `.github/workflows/deploy.yml`

**Interfaces:**
- Consumes: `site/dist/` produit par Task 2.
- Produces: cibles `marketing` et `marketing-stage` déployables par `--only hosting:<cible>`.

- [ ] **Step 1 : Créer les deux sites Firebase**

```bash
npx -y firebase-tools@latest hosting:sites:create baillan-marketing
npx -y firebase-tools@latest hosting:sites:create baillan-marketing-stage
```

- [ ] **Step 2 : Déclarer les cibles**

Ajouter dans `.firebaserc`, sous `targets.easy-rent-54cd4.hosting`, à côté de `prod` et `stage` :

```json
        "marketing": [
          "baillan-marketing"
        ],
        "marketing-stage": [
          "baillan-marketing-stage"
        ]
```

- [ ] **Step 3 : Ajouter les deux blocs de hosting**

Dans `firebase.json`, ajouter au tableau `hosting`, sans toucher aux blocs `prod` et `stage` existants. Noter l'absence de réécriture attrape-tout : une URL inconnue doit tomber sur une vraie 404, pas sur la page d'accueil.

```json
    {
      "target": "marketing",
      "public": "site/dist",
      "cleanUrls": true,
      "ignore": ["firebase.json", "**/.*", "**/node_modules/**"],
      "headers": [
        {
          "source": "**/*.html",
          "headers": [{ "key": "Cache-Control", "value": "public, max-age=0, must-revalidate" }]
        },
        {
          "source": "/_astro/**",
          "headers": [{ "key": "Cache-Control", "value": "public, max-age=31536000, immutable" }]
        },
        {
          "source": "/{robots.txt,sitemap.xml}",
          "headers": [{ "key": "Cache-Control", "value": "public, max-age=3600" }]
        }
      ]
    },
    {
      "target": "marketing-stage",
      "public": "site/dist",
      "cleanUrls": true,
      "ignore": ["firebase.json", "**/.*", "**/node_modules/**"],
      "headers": [
        {
          "source": "**",
          "headers": [{ "key": "X-Robots-Tag", "value": "noindex, nofollow" }]
        },
        {
          "source": "**/*.html",
          "headers": [{ "key": "Cache-Control", "value": "public, max-age=0, must-revalidate" }]
        }
      ]
    }
```

Le `X-Robots-Tag` sur la cible de staging est la protection qui compte : `staging.baillan.com` sera un domaine réellement joignable, et un site de préproduction indexé fait du contenu dupliqué contre soi-même.

`/_astro/**` est mis en cache un an sans risque : Astro empreinte ses noms de fichiers, contrairement au piège connu côté Flutter.

- [ ] **Step 4 : Construire le site dans la CI de déploiement**

Dans `.github/workflows/deploy.yml`, job `build-and-deploy`, avant l'étape de déploiement :

```yaml
      - name: Build marketing site
        run: npm ci --prefix site && npm run build --prefix site
```

- [ ] **Step 5 : Ajouter la cible aux déploiements**

Dans le job `determine-env` de `deploy.yml`, ajouter la cible marketing à chaque branche. Pour `main` :

```bash
            echo 'deploy_targets=hosting:prod,hosting:marketing,firestore:(default),storage' >> $GITHUB_OUTPUT
```

Pour `develop` :

```bash
            echo "deploy_targets=hosting:stage,hosting:marketing-stage,firestore:staging" >> $GITHUB_OUTPUT
```

Le garde-fou existant qui refuse une liste de cibles vide reste en place et continue de protéger contre un déploiement non filtré.

- [ ] **Step 6 : Vérifier l'isolation des cibles avant de déployer pour de vrai**

Un déploiement croisé écraserait l'app par le site marketing. Le prouver à blanc :

```bash
cd site && npm run build && cd ..
npx -y firebase-tools@latest deploy --only hosting:marketing-stage --dry-run
```
Expected: la sortie ne mentionne que `baillan-marketing-stage`. Si `easy-rent-54cd4` ou `baillan-stage` apparaissent, **arrêter** — le ciblage est faux.

- [ ] **Step 7 : Déployer sur staging et vérifier**

```bash
npx -y firebase-tools@latest deploy --only hosting:marketing-stage
curl -sI https://baillan-marketing-stage.web.app | grep -i x-robots-tag
```
Expected: le déploiement réussit et l'en-tête `x-robots-tag: noindex, nofollow` est présent.

- [ ] **Step 8 : Commit**

```bash
git add firebase.json .firebaserc .github/workflows/deploy.yml
git commit -m "feat(hosting): deux cibles pour la vitrine, prod et staging

firebase.json portait déjà deux cibles servant l'app ; on passe à quatre.
Chaque déploiement reste scopé par --only, sans quoi une cible écrase les
autres — quatre sites partagent le même projet.

La cible de staging sert un X-Robots-Tag noindex : staging.baillan.com sera
un domaine réellement joignable, et un site de préproduction indexé se fait
du contenu dupliqué à lui-même."
```

---

### Task 4 : Page d'accueil

**Files:**
- Modify: `site/src/pages/index.astro`
- Test: vérification manuelle du HTML produit (commandes fournies)

**Interfaces:**
- Consumes: `BaseLayout.astro` (Task 2), variables `--color-*` (Task 1).

- [ ] **Step 1 : Écrire la page**

La copie s'appuie sur les clés `landing*` de `lib/l10n/app_fr.arb` — les lire d'abord pour ne pas réinventer un discours produit qui contredirait l'app.

```astro
---
// site/src/pages/index.astro
import BaseLayout from '../layouts/BaseLayout.astro';

const appUrl = 'https://app.baillan.com';
const jsonLd = {
  '@context': 'https://schema.org',
  '@type': 'SoftwareApplication',
  name: 'Baillan',
  applicationCategory: 'BusinessApplication',
  operatingSystem: 'Web, iOS, Android',
  inLanguage: 'fr',
  description:
    'Gestion locative pour bailleurs particuliers : quittances conformes, suivi des loyers, charges et rentabilité.',
};
---
<BaseLayout
  title="Baillan — la gestion locative sans tableur"
  description="Quittances conformes à la loi de 1989, suivi des loyers et des retards, régularisation des charges et rentabilité réelle. Pour les bailleurs particuliers."
>
  <script type="application/ld+json" slot="head" set:html={JSON.stringify(jsonLd)} />

  <section class="hero">
    <h1>La gestion locative enfin sans tableur</h1>
    <p class="lede">
      Quittances, loyers, charges et rentabilité dans un seul outil, conçu pour
      les bailleurs particuliers.
    </p>
    <p class="actions">
      <a class="btn" href={`${appUrl}/signup`}>Commencer gratuitement</a>
      <a class="btn-ghost" href={`${appUrl}/simulator`}>Essayer le simulateur</a>
    </p>
  </section>

  <section class="features">
    <article>
      <h2>Quittances conformes</h2>
      <p>
        Les mentions imposées par la loi du 6 juillet 1989 sont générées avec le
        document. Vous obtenez un PDF prêt à envoyer, pas un modèle à compléter.
      </p>
    </article>
    <article>
      <h2>Loyers et retards</h2>
      <p>
        Chaque encaissement met à jour le bail. Vous savez qui a payé, qui doit
        encore, et depuis combien de temps.
      </p>
    </article>
    <article>
      <h2>Charges récupérables</h2>
      <p>
        La régularisation suit le décret 87-713 : seules les charges réellement
        récupérables sont imputées au locataire.
      </p>
    </article>
    <article>
      <h2>Rentabilité réelle</h2>
      <p>
        Le cash-flow déduit les dépenses et la mensualité de crédit. Vous voyez
        ce que le bien rapporte, pas ce qu'il encaisse.
      </p>
    </article>
  </section>
</BaseLayout>

<style>
  .hero { padding: 4.5rem 0 3rem; text-align: center; }
  h1 {
    font-size: clamp(2rem, 5vw, 3rem); line-height: 1.1;
    letter-spacing: -.02em; margin: 0 0 1rem;
  }
  .lede {
    font-size: 1.15rem; color: var(--color-ink-muted);
    max-width: 46ch; margin: 0 auto 2rem;
  }
  .actions { display: flex; gap: .75rem; justify-content: center; flex-wrap: wrap; }
  .btn {
    background: var(--color-olive); color: var(--color-cream);
    padding: .8rem 1.4rem; border-radius: 7px;
    font-weight: 650; text-decoration: none;
  }
  .btn-ghost {
    color: var(--color-olive); border: 1px solid var(--color-rule-strong);
    padding: .8rem 1.4rem; border-radius: 7px; text-decoration: none;
  }
  .features {
    display: grid; gap: 1rem; padding-bottom: 2rem;
    grid-template-columns: repeat(auto-fit, minmax(15rem, 1fr));
  }
  .features article {
    background: var(--color-paper); border: 1px solid var(--color-rule);
    border-radius: 9px; padding: 1.25rem;
  }
  .features h2 { font-size: 1.05rem; margin: 0 0 .5rem; }
  .features p { margin: 0; color: var(--color-ink-muted); font-size: .95rem; }
</style>
```

- [ ] **Step 2 : Vérifier que le contenu est bien dans le HTML servi**

C'est le critère qui justifie tout le chantier. Le vérifier, ne pas le supposer :

```bash
cd site && npm run build
grep -c 'loi du 6 juillet 1989' dist/index.html
grep -c 'application/ld+json' dist/index.html
grep -c '<script' dist/index.html
```
Expected: `1` pour la mention légale, `1` pour le JSON-LD, et `1` pour `<script` — le seul script de la page est le JSON-LD, qui n'est pas du JavaScript exécutable. Un chiffre supérieur signale du JavaScript embarqué à retirer.

- [ ] **Step 3 : Commit**

```bash
git add site/src/pages/index.astro
git commit -m "feat(site): page d'accueil

Contenu réel dans le DOM servi, sans JavaScript exécutable : c'est
exactement ce que l'app ne peut pas offrir, CanvasKit peignant son texte
dans un canvas que les moteurs n'indexent pas.

JSON-LD SoftwareApplication pour la description du produit."
```

---

### Task 5 : Page FAQ

**Files:**
- Create: `site/src/data/faq.ts`
- Create: `site/src/pages/faq.astro`

**Interfaces:**
- Produces: `faq.ts` exporte `faqItems: { question: string; answer: string }[]`.

- [ ] **Step 1 : Recopier les 20 questions**

Source : `lib/features/support/presentation/faq_page.dart`, qui contient exactement 20 entrées `question:`. Les recopier dans `site/src/data/faq.ts`, avec cet en-tête, qui doit rester dans le fichier :

```ts
// Copie manuelle des 20 questions de
// lib/features/support/presentation/faq_page.dart.
//
// DETTE ASSUMÉE (spec du 2026-09-05, §6) : contrairement aux couleurs, cette
// copie peut dériver de l'app sans que rien ne le signale. Générer la FAQ
// depuis le Dart a été écarté pour la v1 — la structure est trop riche pour
// justifier un générateur d'emblée. À réévaluer si la FAQ se met à bouger
// souvent. En attendant : toute modification dans faq_page.dart doit être
// reportée ici À LA MAIN.
export const faqItems: { question: string; answer: string }[] = [
  { question: '…', answer: '…' },
];
```

Extraire les questions du fichier Dart pour ne pas les retaper de mémoire :

```bash
grep -nE "^\s*question:" lib/features/support/presentation/faq_page.dart
```

Reprendre ensuite chaque réponse associée dans le même fichier. Les 20 paires
doivent apparaître dans l'ordre du fichier Dart : c'est cet ordre que l'étape 3
vérifie, et c'est celui que verra un utilisateur qui compare les deux surfaces.

- [ ] **Step 2 : Écrire la page avec son JSON-LD**

Le balisage `FAQPage` n'est légitime que parce que les questions sont visibles dans la page. C'est précisément ce que l'app ne pouvait pas offrir.

```astro
---
// site/src/pages/faq.astro
import BaseLayout from '../layouts/BaseLayout.astro';
import { faqItems } from '../data/faq';

const jsonLd = {
  '@context': 'https://schema.org',
  '@type': 'FAQPage',
  mainEntity: faqItems.map((item) => ({
    '@type': 'Question',
    name: item.question,
    acceptedAnswer: { '@type': 'Answer', text: item.answer },
  })),
};
---
<BaseLayout
  title="Questions fréquentes — Baillan"
  description="Les réponses aux questions les plus courantes sur Baillan : quittances, loyers, charges, données et compte."
>
  <script type="application/ld+json" slot="head" set:html={JSON.stringify(jsonLd)} />

  <h1>Questions fréquentes</h1>
  <dl class="faq">
    {faqItems.map((item) => (
      <>
        <dt>{item.question}</dt>
        <dd>{item.answer}</dd>
      </>
    ))}
  </dl>
</BaseLayout>

<style>
  h1 { margin: 3rem 0 2rem; font-size: clamp(1.8rem, 4vw, 2.4rem); }
  .faq { max-width: 44rem; }
  .faq dt { font-weight: 650; margin-top: 1.75rem; }
  .faq dd {
    margin: .5rem 0 0; padding-bottom: 1.25rem;
    color: var(--color-ink-muted); border-bottom: 1px solid var(--color-rule);
  }
</style>
```

- [ ] **Step 3 : Vérifier le nombre de questions rendues**

```bash
cd site && npm run build
grep -c '<dt>' dist/faq.html
```
Expected: `20`. Un autre chiffre signale une recopie incomplète.

- [ ] **Step 4 : Commit**

```bash
git add site/src/data/faq.ts site/src/pages/faq.astro
git commit -m "feat(site): page FAQ et balisage FAQPage

Les 20 questions sont visibles dans le DOM, ce qui rend le balisage
schema.org FAQPage légitime — l'app ne pouvait pas l'offrir, son texte étant
peint dans un canvas.

La recopie depuis faq_page.dart est une dette assumée et documentée dans le
fichier de données : contrairement aux couleurs, rien ne signale sa dérive."
```

---

### Task 6 : À propos, mentions légales, suppression de compte

**Files:**
- Create: `site/src/pages/a-propos.astro`
- Create: `site/src/pages/mentions-legales.astro`
- Create: `site/src/pages/supprimer-mon-compte.astro`

**Interfaces:**
- Consumes: `BaseLayout.astro` (Task 2).

- [ ] **Step 1 : Écrire la page À propos**

C'est la page que le propriétaire a explicitement demandée : le produit, le concept, et qui le développe.

```astro
---
// site/src/pages/a-propos.astro
import BaseLayout from '../layouts/BaseLayout.astro';
---
<BaseLayout
  title="À propos — Baillan"
  description="Pourquoi Baillan existe, ce que l'outil fait, et qui le développe."
>
  <article class="prose">
    <h1>À propos</h1>

    <h2>Le problème</h2>
    <p>
      La plupart des bailleurs particuliers gèrent leurs locations dans un
      tableur, et le reste dans leur tête. Ça marche jusqu'au jour où il faut
      retrouver une quittance, justifier une régularisation de charges, ou
      simplement savoir si un bien rapporte vraiment.
    </p>

    <h2>Le parti pris</h2>
    <p>
      Baillan ne cherche pas à remplacer un gestionnaire de patrimoine. L'outil
      fait quelques choses et les fait correctement : des quittances qui portent
      les mentions imposées par la loi du 6 juillet 1989, un suivi des loyers qui
      dit qui doit quoi, une régularisation des charges qui suit le décret
      87-713, et un calcul de rentabilité qui déduit le crédit au lieu de
      l'ignorer.
    </p>

    <h2>Qui développe</h2>
    <p>
      Baillan est développé par Daki Studio. Le produit est conçu et écrit par
      une seule personne, ce qui explique le rythme et le périmètre : peu de
      fonctionnalités, mais chacune terminée. Les retours arrivent directement
      chez la personne qui écrit le code.
    </p>

    <h2>Vos données</h2>
    <p>
      Vos données de gestion vous appartiennent. Vous pouvez les exporter et
      supprimer votre compte à tout moment, depuis l'application. La
      <a href="https://app.baillan.com/privacy">politique de confidentialité</a>
      détaille ce qui est collecté et pourquoi.
    </p>
  </article>
</BaseLayout>

<style>
  .prose { max-width: 42rem; padding: 3rem 0; }
  .prose h1 { font-size: clamp(1.8rem, 4vw, 2.4rem); margin: 0 0 2rem; }
  .prose h2 { font-size: 1.15rem; margin: 2.25rem 0 .5rem; }
  .prose p { color: var(--color-ink-muted); }
  .prose a { color: var(--color-olive); }
</style>
```

- [ ] **Step 2 : Écrire la page de suppression de compte**

Cette page est un bloquant de conformité magasin : sa présence et son URL sont exigées par la Play Console. Elle décrit la procédure, le flux interactif restant dans l'app.

```astro
---
// site/src/pages/supprimer-mon-compte.astro
import BaseLayout from '../layouts/BaseLayout.astro';
const appUrl = 'https://app.baillan.com';
---
<BaseLayout
  title="Supprimer mon compte — Baillan"
  description="Comment supprimer définitivement votre compte Baillan et les données associées."
>
  <article class="prose">
    <h1>Supprimer mon compte</h1>
    <p>
      La suppression est définitive : le compte, les biens, les baux, les
      quittances et les documents associés sont effacés. Cette action ne peut
      pas être annulée.
    </p>
    <h2>Comment faire</h2>
    <ol>
      <li>Ouvrez l'application et connectez-vous.</li>
      <li>Allez dans Profil, puis « Supprimer mon compte ».</li>
      <li>Confirmez. La suppression est immédiate.</li>
    </ol>
    <p>
      <a class="btn" href={`${appUrl}/delete-account`}>Aller à la suppression</a>
    </p>
    <h2>Si vous avez essayé sans créer de compte</h2>
    <p>
      Un essai sans inscription crée un compte anonyme. Il se supprime par le
      même écran, depuis l'appareil utilisé pour l'essai.
    </p>
  </article>
</BaseLayout>

<style>
  .prose { max-width: 42rem; padding: 3rem 0; }
  .prose h1 { font-size: clamp(1.8rem, 4vw, 2.4rem); margin: 0 0 1.5rem; }
  .prose h2 { font-size: 1.15rem; margin: 2.25rem 0 .5rem; }
  .prose p, .prose li { color: var(--color-ink-muted); }
  .btn {
    display: inline-block; background: var(--color-olive); color: var(--color-cream);
    padding: .8rem 1.4rem; border-radius: 7px; font-weight: 650; text-decoration: none;
  }
</style>
```

- [ ] **Step 3 : Écrire les mentions légales**

Obligation LCEN. Les valeurs propres à l'éditeur — raison sociale, forme juridique, SIREN, adresse, directeur de publication — **ne sont pas connues à ce jour** : la structure juridique n'existe pas encore. Écrire la page avec les rubriques exigées et un encadré visible signalant ce qui reste à renseigner, plutôt qu'un texte faussement complet.

```astro
---
// site/src/pages/mentions-legales.astro
import BaseLayout from '../layouts/BaseLayout.astro';
---
<BaseLayout
  title="Mentions légales — Baillan"
  description="Éditeur, hébergeur et informations légales du site baillan.com."
>
  <article class="prose">
    <h1>Mentions légales</h1>

    <p class="todo">
      <strong>À compléter avant la mise en ligne en production.</strong>
      Les informations d'éditeur dépendent de la structure juridique, qui n'est
      pas encore créée. Cette page ne doit pas être déployée sur
      <code>baillan.com</code> en l'état.
    </p>

    <h2>Éditeur du site</h2>
    <p>
      Baillan, édité par Daki Studio.<br />
      Forme juridique, numéro SIREN, adresse du siège et directeur de la
      publication : à renseigner à la création de la structure.<br />
      Contact : à renseigner.
    </p>

    <h2>Hébergement</h2>
    <p>
      Site et application hébergés par Google Ireland Limited, Gordon House,
      Barrow Street, Dublin 4, Irlande, via Firebase Hosting.
    </p>

    <h2>Propriété intellectuelle</h2>
    <p>
      Les contenus de ce site sont protégés par le droit d'auteur. Toute
      reproduction sans autorisation est interdite.
    </p>

    <h2>Données personnelles</h2>
    <p>
      Le traitement des données est décrit dans la
      <a href="https://app.baillan.com/privacy">politique de confidentialité</a>,
      qui fait foi. Vous disposez d'un droit d'accès, de rectification,
      d'effacement et de portabilité, exerçables depuis l'application.
    </p>
  </article>
</BaseLayout>

<style>
  .prose { max-width: 42rem; padding: 3rem 0; }
  .prose h1 { font-size: clamp(1.8rem, 4vw, 2.4rem); margin: 0 0 1.5rem; }
  .prose h2 { font-size: 1.15rem; margin: 2.25rem 0 .5rem; }
  .prose p { color: var(--color-ink-muted); }
  .prose a { color: var(--color-olive); }
  .todo {
    background: var(--color-paper); border-left: 3px solid var(--color-oxblood);
    padding: 1rem; color: var(--color-ink);
  }
</style>
```

- [ ] **Step 4 : Vérifier que les trois pages se construisent**

```bash
cd site && npm run build
ls dist/a-propos.html dist/mentions-legales.html dist/supprimer-mon-compte.html
grep -c 'À compléter avant la mise en ligne' dist/mentions-legales.html
```
Expected: les trois fichiers existent, et l'avertissement des mentions légales est présent — il doit rester visible tant que la structure juridique n'existe pas.

- [ ] **Step 5 : Commit**

```bash
git add site/src/pages/a-propos.astro site/src/pages/mentions-legales.astro \
        site/src/pages/supprimer-mon-compte.astro
git commit -m "feat(site): pages À propos, mentions légales et suppression de compte

La page de suppression de compte lève un bloquant de conformité Play Store ;
le flux interactif reste dans l'app, la page décrit la procédure.

Les mentions légales portent un avertissement visible : les informations
d'éditeur dépendent d'une structure juridique qui n'existe pas encore. Mieux
vaut une page manifestement incomplète qu'un texte faussement complet."
```

---

### Task 7 : Indexation — robots, sitemap, et mise en noindex de l'app

**Files:**
- Create: `site/src/pages/robots.txt.ts`
- Modify: `site/package.json`, `site/astro.config.mjs` (intégration sitemap)
- Modify: `web/robots.txt`
- Delete: `web/sitemap.xml`

**Interfaces:**
- Consumes: toutes les pages des Tasks 4 à 6.

- [ ] **Step 1 : Installer l'intégration sitemap**

```bash
cd site && npx astro add sitemap --yes
```

- [ ] **Step 2 : Servir un robots.txt qui dépend de l'environnement**

Staging ne doit pas être exploré. L'en-tête `X-Robots-Tag` de la Task 3 le couvre déjà, mais un `robots.txt` cohérent évite qu'un explorateur perde son temps.

```ts
// site/src/pages/robots.txt.ts
import type { APIRoute } from 'astro';

// `SITE_ENV=staging` est posé par le workflow de déploiement sur develop.
const isStaging = import.meta.env.SITE_ENV === 'staging';

export const GET: APIRoute = ({ site }) => {
  const body = isStaging
    ? 'User-agent: *\nDisallow: /\n'
    : `User-agent: *\nAllow: /\n\nSitemap: ${new URL('sitemap-index.xml', site).href}\n`;
  return new Response(body, {
    headers: { 'Content-Type': 'text/plain; charset=utf-8' },
  });
};
```

Dans `.github/workflows/deploy.yml`, l'étape de build du site sur `develop` doit exporter `SITE_ENV=staging`.

- [ ] **Step 3 : Mettre l'app en noindex**

Le `robots.txt` réel déménage sur la vitrine ; l'app doit désormais refuser l'exploration. Remplacer tout le contenu de `web/robots.txt` par :

```
# L'app Flutter n'a rien d'indexable : CanvasKit peint son texte dans un
# canvas, invisible aux moteurs. Le contenu référençable vit sur la vitrine.
User-agent: *
Disallow: /
```

Puis supprimer le sitemap de l'app, qui n'a plus d'objet :

```bash
git rm web/sitemap.xml
```

- [ ] **Step 4 : Vérifier le sitemap et l'absence de JavaScript**

```bash
cd site && npm run build
ls dist/sitemap-index.xml
grep -o '<loc>[^<]*</loc>' dist/sitemap-0.xml
grep -rl 'type="module"' dist/*.html || echo "aucun JavaScript de page"
```
Expected: le sitemap liste les cinq URLs (`/`, `/faq`, `/a-propos`, `/mentions-legales`, `/supprimer-mon-compte`), et aucune page ne charge de module JavaScript.

- [ ] **Step 5 : Vérifier la crawlabilité sur le site déployé**

C'est la vérification finale du plan, et la seule qui prouve l'objectif. Elle se fait sur le site réellement servi, pas sur le build local.

```bash
npx -y firebase-tools@latest deploy --only hosting:marketing-stage
BASE=https://baillan-marketing-stage.web.app
for p in "" faq a-propos mentions-legales supprimer-mon-compte; do
  printf '%-24s %s\n' "/$p" "$(curl -s "$BASE/$p" | grep -c '<h1')"
done
curl -s "$BASE/faq" | grep -c '<dt>'
```
Expected: chaque page renvoie `1` (un `<h1>` présent dans le HTML servi, sans exécution de JavaScript), et la FAQ renvoie `20`.

- [ ] **Step 6 : Commit**

```bash
git add site/ web/robots.txt .github/workflows/deploy.yml
git rm --cached web/sitemap.xml 2>/dev/null || true
git commit -m "feat(site): sitemap, robots, et mise en noindex de l'app

Le robots.txt et le sitemap réels déménagent de l'app vers la vitrine :
c'est elle qui porte désormais le contenu indexable. L'app passe en
Disallow global — son texte est peint dans un canvas, elle n'a rien à
offrir aux moteurs et ferait du contenu dupliqué.

Le robots.txt de staging interdit toute exploration, en plus du
X-Robots-Tag servi par la cible d'hébergement."
```

---

## Ce que ce plan ne fait pas

La **bascule de domaine** — étapes 3 à 5 de la spec — est délibérément exclue. Elle dépend d'actions manuelles hors du dépôt : achat et vérification du domaine, enregistrements DNS, domaines autorisés Firebase Auth, mise à jour de l'URL de suppression de compte dans la Play Console. Elle fera un runbook séparé, à exécuter dans un ordre strict dont le point non négociable est : **les domaines autorisés Auth avant le routage DNS**, faute de quoi les connexions Google et Apple cassent sur le nouvel hôte.

Le resserrage de `PROD_ORIGINS` vers `https://app.baillan.com` seul, et de `STAGING_ORIGIN` vers `https://app.staging.baillan.com`, appartient à ce runbook. Tant qu'il n'est pas fait, l'allowlist Stripe autorise les hôtes de la vitrine à obtenir la clé live.

Sont également hors périmètre : l'anglais, les pages-outils et le blog (v2 de FEAT-050), et toute page tarifs.
