# Site vitrine Baillan (`site/`)

Site statique Astro, crawlable, destiné à `baillan.com` (FEAT-050). Construit
et déployé séparément de l'app Flutter (`web/`), sur les cibles Firebase
Hosting `marketing` (prod) et `marketing-stage` (staging).

## Invariants durs — à ne jamais casser

1. **Zéro JavaScript exécutable.** Aucune île (`client:*`), aucun `<script>`
   ajouté à la main, sauf JSON-LD (`type="application/ld+json"`), qui n'exécute
   rien. C'est la raison d'être du site : il doit rester intégralement
   crawlable et léger sans dépendre d'un moteur JS côté client.
2. **`src/styles/tokens.css` est un fichier généré — ne jamais l'éditer à la
   main.** Source canonique : `config/theme_tokens.json`, à la racine du
   dépôt. Pour changer une couleur : éditer le JSON puis régénérer avec
   `dart run tool/gen_theme_tokens.dart` (régénère aussi le miroir Dart de
   l'app, `lib/core/theme/app_palette.g.dart`). Garde-fou CI :
   `scripts/check-theme-tokens.sh` — échoue si ce fichier diverge de ce que
   produit le générateur.
3. **Version d'Astro épinglée exacte** (`"astro": "7.3.1"` dans
   `package.json`, sans `^`) — volontaire, pas un oubli. Ne pas la remettre en
   range sans une raison explicite.
4. **URL canonique** : toujours via `getCanonicalUrl` /
   `normalizeServedPath` de `src/lib/urls.ts`, jamais recalculée depuis
   `Astro.url` directement. `build.format: 'file'` (astro.config.mjs) fait
   que `Astro.url.pathname` reflète le nom de fichier de sortie
   (`/index.html`, `/faq.html`), pas l'URL réellement servie une fois
   `cleanUrls: true` appliqué par Firebase Hosting — `urls.ts` est le seul
   endroit qui connaît cette règle.

## Commandes

| Commande | Action |
| :--- | :--- |
| `npm ci --prefix site` | Installe les dépendances (utilisé en CI) |
| `npm run dev --prefix site` | Serveur de dev local (`localhost:4321`) |
| `npm run build --prefix site` | Build de production dans `site/dist/` |
| `npm run preview --prefix site` | Prévisualise le build localement |

Node **>= 22.12.0** requis (`engines.node` dans `package.json`) — Astro 7 ne
démarre pas sur Node 20.
