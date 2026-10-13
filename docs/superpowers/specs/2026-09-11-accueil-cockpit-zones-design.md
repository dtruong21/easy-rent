# Onglet Accueil — cockpit à 3 zones (restructuration)

> Spec de conception — 2026-09-11
> Statut : validée par le propriétaire (design A approuvé), prête pour le plan
> d'implémentation.

## 1. Contexte et problème

Après les remaniements successifs du dashboard (#171 panneau « À traiter / À
venir », #174 grille KPI patrimoniaux, #176 suppression du KPI renouvellements
orphelin), la structure de l'onglet **Accueil** n'est plus convaincante. Le
propriétaire a validé quatre gênes concomitantes :

1. **Ordre des blocs** — les actions à traiter (retards, quittances, baux
   finissant) sont reléguées en 4ᵉ position, sous deux blocs de métriques. Un
   cockpit de gestion devrait mener par « ce qui demande mon attention ».
2. **Redondance patrimoine** — `KpiGrid` (patrimoine) et `PortfolioYieldSection`
   (rendement) appartiennent à la même famille et se suivent, ce qui donne une
   impression de répétition.
3. **Manque de hiérarchie** — un unique en-tête « Vue d'ensemble » chapeaute
   cinq blocs hétérogènes ; la page se lit comme un empilement plat.
4. **« Docs » mal placé** — « Documents en attente » est rangé dans la grille KPI
   d'état patrimonial alors que ce n'est pas un état du patrimoine. De plus, ce
   KPI n'a **aucune destination cliquable** (pas de page documents globale ; les
   documents vivent sous `/leases/:id`).

Cause commune : **pas de zones**. Actions, états et analyse sont mélangés sous un
seul en-tête.

## 2. Objectif

Restructurer le contenu de l'Accueil (hors onboarding) en **trois zones
clairement nommées**, dans l'ordre d'un cockpit : agir d'abord, état ensuite,
analyse en dernier — **sans nouvelle requête Firestore** (recomposition de
widgets et de providers déjà montés).

## 3. État actuel (référence)

Composition du `_DataView` de `dashboard_page.dart` aujourd'hui :

1. `SectionHeader` « Vue d'ensemble »
2. `KpiGrid` — occupation · patrimoine · docs
3. `PortfolioYieldSection` — rendement brut · net · cash-flow mensuel total
4. `ActionItemsPanel` — encaissement du mois (barre) · retards · baux finissant
5. `CollapsibleCashflowSection` — graphe cash-flow historique (repliable)
6. `RecentActivitySection` — flux d'activité

Contenu réel, par famille : **actions** = encaissement + retards + baux finissant
(ActionItemsPanel) ; **état patrimonial** = occupation + patrimoine (KpiGrid) +
rendement brut/net + cash-flow total (PortfolioYield) ; **analyse** = graphe
cash-flow + activité récente. Le cash-flow apparaît **deux fois** (carte total de
PortfolioYield + graphe historique de CollapsibleCashflow).

## 4. Design cible — cockpit à 3 zones

```
DashboardHeader (Bonjour + date)                      [inchangé]
InstallPromptBanner (conditionnel, déjà en haut)      [inchangé]

ZONE 1 · « À traiter »          SectionHeader
  ActionItemsPanel
    • Encaissement du mois (barre de progression)     [inchangé]
    • Retards         → /leases?filter=late           [inchangé]
    • Baux finissant  → /leases?filter=renewable      [inchangé]
    • « N documents en attente »  — ligne passive, NOUVEAU

ZONE 2 · « Mon patrimoine »     SectionHeader
  Occupation · Patrimoine       (KpiGrid, docs retiré → 2 tuiles)
  Rendement brut · Rendement net (PortfolioYield, carte cash-flow retirée)
  note « X/total biens calculés »

ZONE 3 · « Analyse »            SectionHeader
  Graphe cash-flow (repliable)  (seule représentation cash-flow désormais)
  Activité récente

ShortcutsRow (mobile uniquement, en bas)              [inchangé]
```

## 5. Décisions (2026-09-11)

| Point | Décision |
|---|---|
| Structure | **3 zones** avec en-tête chacune, via le widget `SectionHeader` existant. L'en-tête unique « Vue d'ensemble » disparaît. |
| Ordre | Agir → État → Analyse. `ActionItemsPanel` passe **en tête**. |
| Docs | **Ligne passive** en bas de « À traiter » (« N documents en attente »), **sans tap** (aucune destination n'existe), **masquée si count == 0**. Ce n'est pas un item réellement actionnable, mais il est groupé avec les signaux à surveiller plutôt que présenté comme un état patrimonial. |
| Grille patrimoine | `KpiGrid` perd la tuile docs → **2 tuiles** (occupation, patrimoine). |
| Rendement | `PortfolioYieldSection` perd son **titre interne** (porté par l'en-tête de zone) et sa **carte cash-flow**. Conserve rendement brut + net + la note « X/total ». |
| Déduplication cash-flow | La carte « total mensuel » disparaît. L'agrégat `totalMonthlyCashflowCents` de `PortfolioYieldSummary` (et son calcul dans `computePortfolioYield`) est **retiré** s'il n'a plus aucun consommateur (vérification obligatoire — éviter un nouvel orphelin, cf. #176). Le graphe historique (`CollapsibleCashflowSection`, provider `monthlyCashflowProvider`) reste la **seule** représentation du cash-flow. |
| Activité récente | Placée **dans** la zone « Analyse », sous le graphe. Non repliable (on garde simple). |
| Données | **Zéro nouvelle requête Firestore.** Tous les providers sont déjà montés : `dashboardProvider` (docs, activité, loyers), `dashboardActionItemsProvider` (retards, baux finissant), `dashboardPortfolioKpisProvider` (occupation, patrimoine), `portfolioYieldProvider` (rendements), `monthlyCashflowProvider` (graphe). Aucun nouveau provider. |

**Écarté** : bandeau résumé condensé en chips (approche C — plus gros chantier,
repoussé) ; conserver la carte cash-flow dupliquée ; rendre l'activité récente
repliable.

## 6. Détails d'implémentation

### 6.1 `dashboard_page.dart` — `_DataView`
Remplacer la colonne plate à un en-tête par trois groupes, chacun introduit par
un `SectionHeader`, dans l'ordre Zone 1 → 2 → 3. Les espacements suivent
`AppSpacing` (même rythme `xl` entre blocs qu'aujourd'hui). L'état onboarding
(`snapshot.isOnboarding → OnboardingFirstSteps`) est **inchangé**.

### 6.2 `action_items_panel.dart`
Ajouter un paramètre `required int docsPendingCount`. En bas du panneau, après
les sections retards/baux finissant, afficher une ligne passive (sans `ListTile`
cliquable, sans `onTap`) « N documents en attente » **uniquement si
`docsPendingCount > 0`**. La ligne utilise les jetons de ton `info`/neutre
cohérents avec le reste du panneau. L'état « tout est à jour »
(`items.isEmpty`) reste régi par les seules sections late/ending ; la ligne docs
est indépendante.

### 6.3 `kpi_grid.dart`
Retirer la `KpiCard` `kpi_docs` et la logique `docsColor`/`snapshot.docs`
associée. La grille passe à **2 tuiles** ; ajuster `crossAxisCount` pour que deux
tuiles s'affichent proprement (≥ 600 px → 2 colonnes, sinon 1). `KpiGrid` n'a
alors plus besoin du `snapshot` que pour rien → si plus aucun champ de `snapshot`
n'est lu, simplifier sa signature (à confirmer à l'implémentation).

### 6.4 `portfolio_yield_section.dart`
- Retirer le `Text` de titre interne (`dashboardPortfolioYieldSectionTitle`) — la
  zone le porte.
- Retirer la `_PortfolioKpiCard` `kpi_portfolio_cashflow` et la note de
  méthodologie cash-flow (`dashboardPortfolioYieldCashflowMethodology`).
- Conserver les cartes rendement brut/net et la note « X/total »
  (`dashboardPortfolioYieldFootnote`).
- Retirer `totalMonthlyCashflowCents` de `PortfolioYieldSummary` et le calcul
  correspondant dans `computePortfolioYield` **après avoir vérifié** qu'aucun
  autre consommateur ne l'utilise (grep). Régénérer le freezed.

### 6.5 i18n (FR + EN)
- Nouvelles clés : `dashboardZoneTodoTitle` (« À traiter »), `dashboardZonePatrimonyTitle`
  (« Mon patrimoine »), `dashboardZoneAnalysisTitle` (« Analyse ») ;
  `dashboardActionDocsPending` avec placeholder `{count}` (« {count} documents en
  attente »).
- Clés potentiellement orphelines à retirer si plus utilisées :
  `dashboardOverviewSectionTitle`, `dashboardPortfolioYieldSectionTitle`,
  `dashboardPortfolioYieldCashflowLabel`, `dashboardPortfolioYieldCashflowMethodology`,
  `dashboardKpiDocsPendingLabel`, `dashboardKpiDocsPendingSubtitle` (vérifier
  chaque usage avant suppression). Le test de parité FR/EN
  (`test/l10n/arb_parity_test.dart`) exige une `@key.description` sur le gabarit
  EN pour chaque clé conservée.

## 7. Contraintes

- **Zéro nouvelle requête Firestore** ; accès Firestore jamais en direct (aucun
  nouvel accès de toute façon — pure recomposition).
- **Jetons de design uniquement** (`AppColors` via l'extension, `AppSpacing`,
  `AppRadii`) ; aucune couleur en dur.
- **i18n** FR + EN pour tout libellé visible.
- **Responsive** via les breakpoints existants (`core/ui/breakpoints.dart`,
  seuil 600) — web, mobile natif, web-mobile partagent le même code.
- Réutiliser les widgets/ providers existants ; ne pas réécrire les panneaux,
  seulement les recomposer et retirer ce qui est dédupliqué.

## 8. Vérification

- **Ordre et zones** : le widget test de `DashboardPage` vérifie la présence des
  trois en-têtes de zone et que l'en-tête « À traiter » précède « Mon
  patrimoine » qui précède « Analyse ».
- **Docs** : ligne « N documents en attente » présente quand `docs.count > 0`,
  absente quand `docs.count == 0` ; jamais cliquable. La tuile `kpi_docs`
  n'existe plus dans `KpiGrid`.
- **Patrimoine** : `KpiGrid` n'affiche plus que 2 tuiles (occupation,
  patrimoine) ; `PortfolioYieldSection` n'affiche plus la carte
  `kpi_portfolio_cashflow` ni son titre interne, mais garde brut/net + la note.
- **Dédup cash-flow** : une seule représentation cash-flow sur l'Accueil (le
  graphe) ; `totalMonthlyCashflowCents` retiré sans référence résiduelle.
- **i18n** : parité FR/EN, aucune clé orpheline laissée, `@description` sur le
  gabarit EN pour les nouvelles clés.
- `flutter analyze` clean ; suite complète verte.

## 9. Hors périmètre

- Approche « résumé condensé en chips » (C).
- Toute nouvelle page/route documents globale (docs reste sans destination).
- Rendre l'activité récente repliable ou paginée.
- Changement du calcul de rendement ou de cash-flow (seul l'affichage est
  recomposé).
- Onboarding (inchangé).
