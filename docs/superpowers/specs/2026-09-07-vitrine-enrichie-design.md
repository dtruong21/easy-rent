# Vitrine baillan.com enrichie — canal d'idées + simulateur en vedette

> Spec de conception — 2026-09-07
> Statut : validée par le propriétaire, prête pour le plan d'implémentation.
> Suite de FEAT-050 (vitrine v1). Enrichit la vitrine existante ; ne la refond pas.

## 1. Contexte et objectif

La vitrine v1 (FEAT-050, en ligne sur `stage.baillan.com`, à venir sur
`baillan.com`) est fonctionnelle mais minimale : hero + 4 cartes + FAQ + à
propos + légal. Le propriétaire la juge « trop plate ». Deux objectifs :

1. **Enrichir** la page — plus de contenu qui convainc **et** plus de vie
   visuelle — sans changer de stack ni casser les acquis (zéro-JS, SEO,
   palette de l'app).
2. **Mettre le simulateur de rentabilité en vedette** comme différenciateur
   n°1 : là où la plupart des outils s'arrêtent au rendement brut, Baillan
   déduit la mensualité de crédit et les dépenses et donne le **cash-flow
   réel**. C'est un avantage produit vérifié dans le code (dashboard/simulateur
   calculent le cash-flow net, crédit déduit).
3. **Ajouter un canal de collecte d'idées** des utilisateurs.

## 2. Direction retenue (décisions du 2026-09-07)

| Point | Décision |
|---|---|
| Style visuel | **SaaS/direct** (sans serif, produit en avant), palette de l'app — PAS l'éditorial « magazine » (écarté par le propriétaire) |
| Canal d'idées | **Bouton vers un formulaire Tally** (choisi le 2026-09-07), pas de backend |
| Captures | **Vraies captures du simulateur**, prises sur l'app, avec exemple **cash-flow positif** |
| Contrainte | Reste **zéro-JS exécutable** (seul le JSON-LD est admis), statique Astro |

**Écarté** : direction éditoriale serif ; boîte à idées avec backend (POST →
Cloud Function) ; board public votable. Chacun documenté comme alternative
au §8.

## 3. Structure de la page (ordre des sections)

1. **Hero** (retravaillé) — pilule d'audience, titre « La gestion locative,
   enfin sans tableur », sous-titre, deux CTA (Commencer / Essayer le
   simulateur). Fond dégradé `paper → cream`.
2. **★ Simulateur** (nouveau, la vedette) — voir §4. Comparatif brut-vs-net +
   capture réelle du résultat.
3. **Comment ça marche** (nouveau) — 3 étapes : ajouter un bien → suivre →
   piloter.
4. **Piliers / fonctionnalités** (gardé) — les 4 cartes actuelles (quittances,
   loyers, charges, rentabilité), rythmées (fond alterné, éventuelles icônes).
5. **Pour qui** (nouveau) — positionnement : bailleurs particuliers, 1 à
   quelques biens.
6. **Proposez une idée** (nouveau) — voir §5. Bloc court + bouton vers le
   formulaire externe.
7. **Pied de page** (gardé) — À propos, FAQ, Légal, Ouvrir l'app.

La FAQ, l'à-propos, les mentions légales et la suppression de compte restent
des **pages** distinctes (inchangées) ; cette spec ne touche que la landing
`/` et lui ajoute ces sections.

## 4. Section simulateur (la vedette)

**Message** : « Le vrai rendement, pas le brut flatteur. » Les autres outils
s'arrêtent au rendement brut ; Baillan déduit la mensualité de crédit et les
dépenses et donne le cash-flow réel.

**Comparatif** deux colonnes :
- *Les autres outils* — « 8,0 % » (rendement brut, s'arrête là), en ton neutre.
- *Baillan* (mis en avant, bordure olive) — « +348 €/mois » (cash-flow réel ·
  rendement net 7,6 % · crédit déduit), en olive.

**Capture produit** dans un cadre sombre fidèle à l'app, montrant les cartes de
résultat réelles : mensualité de crédit 502 €, loyer net annuel 9 690 €,
cash-flow mensuel **+347,88 €**, rendement net **7,60 %**.

### 4.1 Le scénario de démonstration (exemple positif, figé)

Les captures sont prises avec ce scénario (cash-flow positif, rendement
attractif) — à reproduire exactement pour que chiffres du comparatif et de la
capture concordent :

| Entrée | Valeur |
|---|---|
| Prix d'achat | 118 000 € |
| Frais de notaire | 9 440 € (8 %, auto) |
| Apport | 35 000 € |
| Capital emprunté | 83 000 € |
| Taux nominal | 3,5 % |
| Durée | 240 mois |
| Loyer mensuel HC | 850 € |

Résultats produits (vérifiés en direct sur l'app le 2026-09-07) : mensualité
502,12 € · loyer net annuel 9 690 € · **cash-flow +347,88 €/mois** · rendement
brut **8,00 %** · net **7,60 %** · coût total du crédit 120 508,80 € · valeur
estimée à 20 ans 158 928,89 €.

### 4.2 Comment les captures sont produites

Vérifié faisable le 2026-09-07 : le simulateur est **accessible en anonyme**
(`app_router.dart` : `/simulator` ouvert aux sessions anonymes, carrefour
d'onboarding). On le capture donc **sans identifiants** :

1. Ouvrir `app.staging.baillan.com` dans un navigateur → « Continuer sans
   compte » → `/simulator`.
2. Saisir le scénario du §4.1.
3. Capturer la section « Résultats estimés ».

**En français** : l'app suit la locale du navigateur ; les captures finales
doivent être prises avec un navigateur/appareil en **français** (les captures
d'exploration étaient en anglais). Réglage `Accept-Language: fr` ou bascule de
locale in-app avant capture.

**Repli** : si une capture s'avère bloquée, une maquette SVG/HTML stylisée
(zéro-JS) reproduit les mêmes cartes de résultat aux couleurs de la marque,
remplaçable plus tard.

**Traitement** : captures optimisées (largeur raisonnable, format compressé),
présentées dans un cadre. Elles comptent dans le budget 16 Mo — pas de PNG
lourds non compressés.

## 5. Canal d'idées (formulaire externe)

Section « Proposez une idée » : un bloc court (« Baillan se construit avec
vous — les retours arrivent directement chez la personne qui écrit le code »)
et un **bouton vers un formulaire Tally** (outil choisi le 2026-09-07).

- **Pas de backend, pas de collecte côté vitrine** — cohérent avec le zéro-JS.
- L'URL du formulaire est une **constante de configuration** dans le site
  (`site/src/lib/links.ts` ou équivalent), fournie par le propriétaire. Tant
  qu'elle est absente, un placeholder explicite (`#` + note) évite de livrer un
  lien mort en production — le build échoue ou avertit si l'URL n'est pas
  renseignée pour la prod.
- Le bouton ouvre le formulaire dans un **nouvel onglet** (`target="_blank"
  rel="noopener"`).

Aucune donnée personnelle ne transite par la vitrine ; le formulaire externe
(Tally) porte sa propre politique de confidentialité (conformité RGPD à
vérifier au moment de créer le formulaire — hors périmètre de cette spec).

## 6. Contraintes visuelles et techniques

- **Zéro-JS exécutable.** Animations éventuelles en **CSS pur** (apparition au
  scroll via `animation-timeline: view()` ou équivalent, transitions au survol)
  — jamais de JavaScript de page. Seul `<script type="application/ld+json">`
  est admis.
- **Palette** : uniquement les variables `--color-*` générées
  (`site/src/styles/tokens.css`), jamais de couleur en dur. Le vert positif du
  cash-flow réutilise le jeton de succès de l'app.
- **`appUrl` env-aware** : déjà en place (`site/src/lib/urls.ts` suit
  `SITE_ENV`) — les nouveaux liens app passent par `appUrl`, pas de domaine en
  dur.
- **Français uniquement** ; l'anglais reste différé (Astro déjà en
  `prefixDefaultLocale: false`).
- **Responsive** : le comparatif et les cartes passent en une colonne sur
  mobile ; la capture reste lisible (largeur `max-width: 100%`).
- **Réutilise** `BaseLayout.astro` et le style existant ; enrichit la landing
  `index.astro`, sans réécrire le gabarit.

## 7. Vérification

- **Crawlabilité** : tout le texte des nouvelles sections est dans le DOM
  servi, sans exécution de JavaScript (le critère de FEAT-050 tient).
- **Zéro-JS** : aucune balise `<script src>` ni directive `client:*` dans les
  pages construites.
- **Cohérence des chiffres** : les valeurs du comparatif (8 % brut, +348 €,
  7,6 % net) correspondent exactement à la capture affichée.
- **Liens** : le bouton « Ouvrir l'app » et les CTA suivent `appUrl` (staging
  vs prod) ; le bouton « Proposer une idée » pointe vers l'URL de formulaire
  configurée et s'ouvre en nouvel onglet.
- **Poids** : la page reste raisonnable ; captures compressées.

## 8. Hors périmètre / alternatives écartées

- **Direction éditoriale serif** — maquettée, écartée par le propriétaire
  (trop « magazine »).
- **Boîte à idées avec backend** (formulaire POST natif → Cloud Function →
  Firestore) — écartée au profit du formulaire externe (zéro infra pour un dev
  solo). Réouvrable si le formulaire externe montre ses limites.
- **Board public votable** (type Canny) — écarté : modération, spam, backend
  lecture+écriture, trop lourd.
- **Anglais / i18n-SEO**, pages-outils, blog — restent la v2 de FEAT-050.
- **Conformité RGPD du formulaire Tally** — à vérifier à la création du
  formulaire ; la spec ne fait que réserver l'emplacement et la constante d'URL.
