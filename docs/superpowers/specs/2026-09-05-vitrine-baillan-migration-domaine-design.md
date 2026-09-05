# Site vitrine baillan.com et migration de l'app vers app.baillan.com

> Spec de conception — 2026-09-05
> Statut : validée par le propriétaire, prête pour le plan d'implémentation.
> Couvre les sujets 3 et 4 de la priorisation transverse (`docs/BACKLOG.md`).

## 1. Contexte

L'application Baillan est un PWA Flutter servi aujourd'hui à la racine du
domaine de production. Elle rend son texte via CanvasKit, c'est-à-dire dans un
`<canvas>` que les moteurs de recherche n'indexent pas : le domaine racine ne
peut donc porter aucun contenu référençable tant que l'app l'occupe.

Deux chantiers en découlent et n'en forment qu'un seul : construire un site
vitrine statique et crawlable, puis déplacer l'app sur un sous-domaine pour lui
laisser la place. L'ordre est contraint — libérer la racine avant que la vitrine
soit prête créerait une fenêtre sans site indexable, et ferait payer aux
utilisateurs un changement d'origine (sessions, PWA installées) sans
contrepartie.

Le cadrage d'architecture existe déjà dans
[`docs/backlog/050-marketing-site-seo.md`](../../backlog/050-marketing-site-seo.md)
(topologie sous-domaine arbitrée le 2026-07-08, stack Astro, Firebase
multi-site). **Cette spec ne rouvre aucune de ces décisions.** Elle tranche ce
que ce document laissait ouvert et corrige ses hypothèses périmées.

### Ce que cette spec tranche par rapport à FEAT-050

| Point | FEAT-050 | Décision retenue |
|---|---|---|
| Domaine | hypothèse `baillan.fr` (38 occurrences) | `baillan.com`, confirmé par le propriétaire |
| Hôtes de staging | non couverts | miroir exact de la production |
| Page « À propos » | absente du plan v1 | ajoutée à la v1 |
| Direction visuelle | non traitée | structure produit, palette de l'app |
| Couleurs de la vitrine | non traitée | générées depuis `app_theme.dart` |

## 2. Topologie et domaines

```
PRODUCTION                            STAGING
baillan.com        vitrine Astro      staging.baillan.com      vitrine (noindex)
www.baillan.com    301 → apex
app.baillan.com    app Flutter        app.staging.baillan.com  app (noindex)
                   (noindex)
```

**L'apex est canonique** pour la vitrine, `www` redirige vers lui en 301. Ce
choix confirme FEAT-050 §2.1. Il impose des enregistrements A/AAAA sur l'apex
plutôt qu'un CNAME : c'est le coût opérationnel assumé d'une URL plus courte.

**Le staging est un miroir structurel exact de la production** : un seul mot
pour l'environnement (`staging`), et le même rapport entre vitrine et app des
deux côtés. Cela impose de déplacer l'app de staging de `stage.baillan.com` vers
`app.staging.baillan.com`, donc de changer `STAGING_ORIGIN`
(`functions/src/utils/db_router.ts`) et les domaines autorisés Firebase Auth. Ce
coût est quasi nul s'il est payé pendant la bascule de l'app, qui touche déjà
exactement ces mêmes endroits ; il serait inutilement élevé à tout autre moment.

Deux sites Firebase Hosting, cibles `marketing` et `app`. **Les déploiements
sont toujours scopés par `--only`** — sans cela, un déploiement écrase l'autre
site. Le `robots.txt` et le `sitemap.xml` réels déménagent de `web/` vers la
vitrine ; l'app sert un `Disallow: /`.

## 3. Structure du dépôt

Le site vit dans `site/`, à côté de `functions/` : mono-dépôt, une seule CI, un
seul historique. Astro produit du HTML sans JavaScript par défaut, ce qui est
exactement l'inverse de la contrainte CanvasKit.

## 4. Direction visuelle

La structure retenue est celle d'un site produit orienté conversion : hero
centré, capture du produit visible dès le premier écran, trois cartes de
bénéfices. C'est la convention que les visiteurs reconnaissent immédiatement.

La palette n'est pas choisie : elle est **celle de l'application**, reprise
telle quelle depuis `lib/core/theme/app_theme.dart`.

| Token | Valeur | Usage sur la vitrine |
|---|---|---|
| `cream` | `#FCFAF5` | fond de page |
| `paper` | `#F7F4ED` | fond du hero |
| `olive` | `#3F4A2A` | bouton principal |
| `oxblood` | `#9A3B2F` | alertes, montants négatifs |
| `kraft` | `#E4D9BD` | aplats |
| `rule` | `#E8E2D3` | filets et bordures |
| `ink` | `#1B1A17` | texte principal |
| `inkMuted` | `#6B665D` | texte secondaire |

L'objectif est la continuité : un visiteur qui clique « Ouvrir l'app » ne doit
pas avoir l'impression de changer de produit. **L'application n'est pas
retouchée** — c'est elle qui fait foi.

## 5. Générateur de tokens

C'est la seule pièce réellement nouvelle de l'architecture, et le mécanisme qui
garantit l'écosystème unique.

Un script Dart (`tool/export_theme_tokens.dart`) **importe** le thème et écrit
`site/src/styles/tokens.css`. Il importe plutôt qu'il ne parse : les valeurs
produites sont les vraies constantes compilées, jamais une copie susceptible de
dériver d'une expression régulière trop optimiste.

Le fichier généré **est commité**. La CI le régénère et échoue si le résultat
diffère du fichier versionné. Deux bénéfices : le changement de couleur est
lisible dans un diff, et il devient impossible de modifier le thème de l'app
sans que la vitrine suive ou que la CI le signale. C'est l'idiome déjà employé
dans le dépôt par `check-db-isolation.sh` et `check-stripe-isolation.sh` — une
vérité vérifiée mécaniquement plutôt que confiée à la discipline.

**Alternative écartée** : générer au moment du build Astro. Cela imposerait un
SDK Dart dans le build du site, pour aucun gain — la vérification en CI donne
déjà la garantie recherchée.

## 6. Contenu de la v1

Cinq pages, en français uniquement.

| Page | Source de la copie | Rôle |
|---|---|---|
| `/` | clés `landing*` de `lib/l10n/app_fr.arb` | produit et bénéfices, CTA vers l'app |
| `/faq` | 20 questions de `faq_page.dart` | contenu indexable, JSON-LD FAQPage |
| `/mentions-legales` | à rédiger (LCEN) | obligation légale, bloquant Play Store |
| `/supprimer-mon-compte` | informationnel | procédure, CTA vers le flux in-app |
| `/a-propos` | à rédiger | le produit, le concept, qui le développe |

### Gouvernance anti-dérive

La règle de FEAT-050 §4 est conservée : le **légal versionné** (confidentialité,
CGU, lié à `rgpdConsentVersion`) reste canonique dans l'application, qui est la
source du consentement RGPD au signup ; la vitrine y renvoie. Le **non
versionné** (FAQ, mentions LCEN) vit sur la vitrine sans risque de dérive.

**Dette assumée sur la FAQ.** Les 20 questions existent déjà dans
`faq_page.dart`. Les recopier recrée exactement le problème de dérive que le
générateur de tokens élimine sur les couleurs. Générer la FAQ depuis du Dart est
cependant nettement plus lourd que huit constantes : structure de contenu riche,
pas huit valeurs scalaires. **Décision v1 : recopie manuelle**, dette notée
explicitement, à réévaluer si la FAQ se met à bouger souvent. Ne pas laisser
cette dette implicite : elle doit figurer dans le fichier de contenu de la page.

## 7. Séquencement

L'ordre est contraint par les dépendances, pas par la préférence.

1. **Fondation** — `firebase.json` en multi-site, cibles `marketing` et `app`,
   scaffold Astro, tokens générés. Déployé sur `staging.baillan.com`.
2. **Contenu** — les cinq pages, vérifiées crawlables sur staging : contenu réel
   présent dans le DOM, JSON-LD valide.
3. **Bascule** — `app.baillan.com` branché ; **les domaines autorisés Firebase
   Auth sont mis à jour avant le routage DNS** ; `baillan.com` bascule sur la
   vitrine ; app en noindex global.
4. **Resserrage des origines** — `PROD_ORIGINS` réduit à `https://app.baillan.com`
   seul, `STAGING_ORIGIN` porté à `https://app.staging.baillan.com`.
5. **Référencement et conformité** — Search Console, sitemap soumis, URL de
   suppression de compte mise à jour dans la Play Console.

L'étape 4 découle du correctif de l'issue #138 (PR #157) : l'allowlist Stripe
autorise aujourd'hui `baillan.com` et `www.baillan.com` à obtenir la clé live,
parce que l'app y vit encore. Une fois la vitrine installée sur ces hôtes, les y
laisser permettrait au domaine marketing d'émettre de vrais paiements. Le
resserrage n'est donc pas une finition : c'est la condition de validité du
correctif après bascule.

## 8. Vérification

- **Crawlabilité** : chaque page de la v1 doit exposer son contenu dans le DOM
  servi, vérifié sans exécution de JavaScript. C'est le critère qui justifie
  tout le chantier ; il se vérifie, il ne se suppose pas.
- **Tokens** : la CI régénère `tokens.css` et échoue en cas de différence.
- **Isolation des déploiements** : vérifier qu'un déploiement `marketing` ne
  modifie pas le site `app`, et réciproquement.
- **Après bascule** : connexion Google et Apple sur `app.baillan.com`,
  installation PWA, un parcours métier complet, et un appel Stripe depuis
  l'ancien hôte qui doit désormais être refusé.

## 9. Risques

| Risque | Portée | Mitigation |
|---|---|---|
| DNS basculé avant les domaines autorisés Auth | connexion Google/Apple cassée sur le nouvel hôte | ordre imposé à l'étape 3, non négociable |
| PWA installées sur l'ancien hôte | ne suivent pas — origine différente | réinstallation ; aucun abonné réel concerné à ce jour |
| Déploiement non scopé | un site écrase l'autre | `--only` systématique, vérifié à l'étape 1 |
| URL Play Console figée dès soumission | conformité magasin | ne la changer qu'une fois, à la bascule |
| Allowlist Stripe non resserrée | le domaine marketing peut émettre de vrais paiements | étape 4, bloquante avant toute activation commerciale |
| Seconde chaîne d'outils (Astro, npm) | dette d'outillage | versions épinglées ; Node existe déjà pour `functions/` |

## 10. Hors périmètre

- L'anglais et l'i18n-SEO. Astro est configuré dès la v1 avec
  `prefixDefaultLocale: false` pour que `/en/*` puisse s'ajouter plus tard sans
  déplacer les URLs françaises, mais aucune page anglaise n'est écrite.
- Les pages-outils et le blog (v2 de FEAT-050).
- Une page tarifs. Sans structure juridique, rien n'est vendable ; publier une
  grille engagerait commercialement sans pouvoir encaisser.
- Toute modification du thème de l'application.
- L'activation commerciale des paliers payants (FEAT-057) et le correctif des
  events sandbox (issue #158), traités séparément.
