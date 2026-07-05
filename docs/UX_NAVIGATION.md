# Navigation & UX — Concept unifié web + mobile (FEAT-026)

> **Document de référence.** Tous les agents (flutter-dev, qa-tester, code-reviewer,
> product-owner) doivent s'y conformer pour toute évolution de la navigation.
> Statut : **concept proposé** — décisions à valider avant implémentation
> (voir §12). Auteur : software-architect, 2026-07-03.

---

## 1. Problème

Aujourd'hui (post FEAT-022 / BAILLAN-M1), **le dashboard est le hub unique** :

- toutes les sections (Biens, Locataires, Baux, Profil) se rejoignent depuis
  ses raccourcis (`ShortcutsRow`) ou ses KPI cliquables ;
- l'accès au profil et à la déconnexion passe par deux icônes de l'`AppBar`
  du dashboard exclusivement ;
- toutes les autres pages se naviguent **par empilement** avec un bouton
  retour, et quand la pile est vide, un `fallbackRoute` renvoie vers
  `/dashboard` (`AppAppBar`) ;
- **il n'existe aucune navigation persistante.**

Conséquences :

- pour passer de Biens à Locataires, on repasse **toujours** par le dashboard ;
- le positionnement du dashboard n'est pas intuitif — il joue à la fois le rôle
  de « cockpit » (KPI, activité) **et** de « menu » (raccourcis) ;
- **sur mobile (FEAT-024), ce modèle devient hostile** : des allers-retours
  permanents par un hub, sans la barre d'onglets que tout utilisateur mobile
  attend. On importerait la dette d'architecture web dans l'app native.

**Verbatim utilisateur** : « Le positionnement du dashboard n'est pas très
intuitif. Ça ramène la complexité quand on fait la version mobile après.
Travailler au-dessus afin de proposer un concept favorable qui est compatible
entre web et mobile. »

---

## 2. Concept retenu : shell adaptatif à destinations persistantes

Un **shell de navigation unique**, standard Material 3 adaptatif, partagé par le
web et le mobile :

- **`NavigationBar` en bas** quand la largeur < 600 px (idiome mobile / PWA
  étroite) ;
- **`NavigationRail` à gauche** quand la largeur ≥ 600 px (desktop / tablette /
  web large) ;
- implémenté avec **`StatefulShellRoute.indexedStack`** de GoRouter : chaque
  destination est une **branche** dont l'état (pile de navigation, scroll,
  filtres, formulaires en cours) est **préservé** quand on change d'onglet.

Le dashboard **cesse d'être le hub obligatoire**. Il devient une destination
parmi les autres : l'onglet **Accueil**. La navigation entre sections se fait
via les destinations persistantes, plus par le dashboard.

> **Principe directeur** : « Les destinations sont toujours à un tap. Le
> dashboard informe, il ne route plus. »

### Pourquoi ce modèle

- C'est le pattern Material 3 canonique (Gmail, Drive, la plupart des apps de
  gestion). Un utilisateur mobile le connaît par cœur.
- **La même structure sert le web et le mobile** : le shell réduit
  massivement le chantier FEAT-024 (plus de navigation à réinventer pour le
  tactile — voir §9).
- `indexedStack` préserve l'état : revenir sur Baux après un détour par Biens
  restitue la liste filtrée + la position de scroll, sans rechargement.

---

## 3. Destinations (décision)

**Décision : 5 destinations.** Le maximum recommandé par Material 3, justifié
ici car ce sont les 5 objets de premier niveau du domaine locatif.

| # | Destination | Route racine | Icône (proposée) | Contenu |
|---|---|---|---|---|
| 0 | **Accueil** | `/dashboard` | `home` / `home_outlined` | Dashboard actuel recentré : KPI, graphique mensuel, rendement, activité récente. Plus de raccourcis (voir §7). |
| 1 | **Biens** | `/properties` | `apartment` / `apartment_outlined` | Liste des biens + sous-pages détail/édition/création. |
| 2 | **Locataires** | `/tenants` | `people` / `people_outline` | Liste des locataires + sous-pages. |
| 3 | **Baux** | `/leases` | `description` / `description_outlined` | Liste des baux + détail (paiements, quittances en sous-pages). |
| 4 | **Profil** | `/profile` | `person` / `person_outline` | Hub de réglages (déjà mobile-first, FEAT-025b). |

### 3.1 Baux mérite-t-il un onglet ? — OUI (décision)

**Décision : Baux reste une destination de premier niveau.**
Justification en une phrase : le bail est l'objet central du métier (il porte
loyer, paiements et quittances, c.-à-d. l'usage quotidien du bailleur) et son
volume d'accès dépasse celui de Biens/Locataires — le reléguer en sous-onglet
de Biens ou de Locataires ajouterait un tap au geste le plus fréquent.

> Alternative écartée (→ §11, option A) : accès aux baux uniquement depuis la
> fiche d'un bien ou d'un locataire.

### 3.2 Profil en onglet ou en icône d'AppBar ? — ONGLET (décision)

**Décision : Profil devient une destination persistante (onglet 4).**
Justification en une phrase : sur mobile, une icône d'AppBar en haut à droite
est un anti-pattern pour accéder aux réglages (cible tactile éloignée du pouce,
invisible quand on scrolle) alors que le `/profile` est déjà un hub mobile-first
(FEAT-025b) qui héberge thème, sécurité, support, déconnexion — il a vocation à
être une racine de branche.

Conséquence directe : **les deux `IconButton` profil + déconnexion disparaissent
de l'AppBar du dashboard.** La déconnexion vit déjà dans `/profile`
(`ProfileSessionSection`). On supprime la redondance.

> Alternative écartée (→ §11, option B) : garder Profil accessible par une icône
> d'avatar dans l'AppBar, hors shell.

### 3.3 Où vivent paiements / quittances / documents ? — SOUS-PAGES DE BAUX (inchangé)

**Décision : inchangé.** Paiements et quittances restent des **sous-pages
empilées dans la branche Baux** :

- `/leases/:id` → `/leases/:id/payments/new`, `/leases/:id/payments/:pid/edit`,
  `/leases/:id/receipts`.

Ils sont intrinsèquement liés à un bail (FK), n'ont pas de vue « globale » dans
le MVP, et n'ont donc pas à devenir des destinations. Les **documents** n'ont
pas encore de route dédiée (`SCHEMA` : `documents` TBD côté routes) ; le jour où
ils en auront une, ils s'empileront dans la branche la plus pertinente (Biens ou
Baux) — **pas de 6ᵉ onglet.**

### 3.4 Le simulateur ? — HORS SHELL (décision)

**Décision : le simulateur reste HORS du shell**, avec la landing et les écrans
d'auth.
Justification en une phrase : le simulateur est accessible aux **anonymes**
(essai 14 j) qui n'ont **pas** accès aux destinations métier (Biens/Locataires/
Baux/Accueil sont refusées par la garde ET par les rules Firestore) — l'afficher
dans une barre d'onglets exposerait des destinations mortes pour l'anonyme et
briserait le parcours d'onboarding.

Pour un **compte complet**, le simulateur reste atteignable :

- via un **point d'entrée dans l'onglet Accueil** (carte / bouton « Simuler un
  investissement » — remplace le raccourci simulateur actuel) ;
- en `push()` **par-dessus le shell** (route de premier niveau, plein écran,
  avec bouton retour) plutôt que dans une branche — ainsi l'expérience anonyme
  (plein écran, sans onglets) et l'expérience compte sont identiques.

> Alternative écartée (→ §11, option C) : simulateur comme 6ᵉ onglet ou onglet
> conditionnel selon le `SessionState`.

---

## 4. Schéma des destinations

### 4.1 Arborescence de navigation

```
┌─────────────────────────────────────────────────────────────────┐
│  HORS SHELL (public / auth / anonyme) — plein écran, pas d'onglets│
│                                                                   │
│   /                (Landing, carrefour onboarding)                │
│   /login  /signup  /forgot-password  /reset-password              │
│   /privacy  /terms                                                │
│   /simulator  /simulator/:id   (anonymes + comptes, plein écran)  │
└─────────────────────────────────────────────────────────────────┘
                              │
              login / compte complet (SessionState.fullyAuthenticated)
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  SHELL ADAPTATIF  (StatefulShellRoute.indexedStack)               │
│  NavigationBar (<600px) │ NavigationRail (≥600px)                 │
│                                                                   │
│  ┌───────────┬───────────┬───────────┬───────────┬────────────┐  │
│  │ Accueil   │  Biens    │ Locataires│   Baux    │   Profil   │  │
│  │ (branch0) │ (branch1) │ (branch2) │ (branch3) │ (branch4)  │  │
│  ├───────────┼───────────┼───────────┼───────────┼────────────┤  │
│  │/dashboard │/properties│ /tenants  │ /leases   │ /profile   │  │ ← racines
│  │           │  ↑push    │  ↑push    │  ↑push    │  ↑push     │  │
│  │           │/properties│/tenants/  │/leases/:id│/profile/   │  │
│  │           │  /new     │  new      │  ↑push    │  details   │  │
│  │           │/properties│/tenants/  │/leases/:id│/profile/   │  │
│  │           │  /:id     │  :id      │ /payments │  password  │  │
│  │           │  ↑push    │  ↑push    │  /new     │/profile/   │  │
│  │           │/properties│/tenants/  │/leases/:id│  support   │  │
│  │           │  /:id/edit│  :id/edit │ /receipts │            │  │
│  └───────────┴───────────┴───────────┴───────────┴────────────┘  │
│   chaque branche conserve SA pile + scroll + filtres (indexedStack)│
└─────────────────────────────────────────────────────────────────┘
```

### 4.2 Rendu adaptatif (breakpoint 600 px)

```
   < 600 px  (mobile / PWA étroite)          ≥ 600 px  (desktop / tablette)
 ┌───────────────────────────┐        ┌──────┬──────────────────────────┐
 │  AppBar (titre section)   │        │ Rail │  AppBar (titre section)   │
 ├───────────────────────────┤        │ ┌──┐ ├──────────────────────────┤
 │                           │        │ │🏠│ │                          │
 │       CONTENU             │        │ │  │ │      CONTENU             │
 │   (branche active)        │        │ │🏢│ │   (branche active)       │
 │                           │        │ │  │ │                          │
 │                           │        │ │👥│ │                          │
 │                           │        │ │  │ │                          │
 │                           │        │ │📄│ │                          │
 ├──🏠──🏢──👥──📄──👤────────┤        │ │  │ │                          │
 │  NavigationBar (bas)      │        │ │👤│ │                          │
 └───────────────────────────┘        └──┴──┴──────────────────────────┘
   SafeArea bottom (notch)              Rail dans SafeArea left
```

### 4.3 Rail repliable (implémenté 2026-07-03)

Le rail (≥600 px) est **repliable par l'utilisateur**, pas piloté par la
largeur : un bouton menu en tête (`Icons.menu` / `Icons.menu_open`) bascule
**replié** (icônes + libellés courts, `labelType.all`, étroit) ↔ **déplié**
(`extended: true`, icônes + libellés au large). État **persisté**
(`railExpandedProvider` → SharedPreferences `nav_rail_expanded`), défaut
**replié** (place maximale au contenu). Le **simulateur d'investissement** est
épinglé **en bas du rail** (action secondaire, `go('/simulator')` — hors shell) :
icône seule (replié, tooltip) ou icône + libellé (déplié). Sur mobile
(NavigationBar), le simulateur reste accessible depuis l'onglet Accueil (pas
de 6ᵉ item). Style rail + barre : thème `navigationRailTheme` /
`navigationBarTheme` à la marque (indicateur olive sourd, encre/papier).

---

## 5. Règles de navigation (contrat)

| Geste | API GoRouter | Effet |
|---|---|---|
| **Changer d'onglet** | `goBranch(index)` (via `StatefulNavigationShell.goBranch`) | Bascule sur la branche, **sans réinitialiser** sa pile (grâce à `indexedStack`). C'est le tap sur une destination. |
| **Naviguer vers une racine par URL/KPI** | `context.go('/leases?filter=active')` | Active la branche correspondante + remplace sa pile par la racine. Utilisé par les **KPI drill-down** et les deep links. |
| **Empiler dans l'onglet courant** | `context.push('/leases/:id')` | Pousse une sous-page **dans la branche active**. Le bouton retour dépile. Utilisé par tap sur une carte de liste, un bouton « + Nouveau », etc. |
| **Retour** | `context.pop()` / `BackButton` | Dépile **dans la branche courante**. Quand la branche est à sa racine, le bouton retour disparaît (cf. §6). |

**Règles d'or** :

1. **`goBranch` pour les onglets, `push` pour approfondir.** On ne fait jamais
   `go('/tenants')` pour changer d'onglet depuis la barre (ça reset la pile) —
   on utilise `goBranch`. `go()` reste réservé aux **deep links** et au
   **drill-down KPI** (où reset de pile est le comportement voulu).
2. **Les formulaires et détails sont des sous-pages empilées** (`push`), jamais
   des destinations. Pattern déjà appliqué au hub `/profile` (FEAT-025b) : le
   hub liste des tuiles qui `push()` vers `/profile/details`, `/profile/password`,
   `/profile/support`.
3. **Un bouton « + Nouveau » `push()` dans la branche courante** ; au succès, il
   `pop()` (ou `pop(id)` en mode picker, cf. `TenantFormPage(popOnSuccess:)`).
4. **Pas de hub obligatoire.** On ne route plus via le dashboard. Aucun code ne
   doit faire `go('/dashboard')` pour « revenir au menu ».

### 5.1 Deep links — inchangés

Les URLs restent identiques (`/properties/:id`, `/leases/:id/receipts`,
`/simulator/:id`, …). GoRouter, avec `StatefulShellRoute`, résout un deep link
vers une sous-page en **activant la bonne branche et en construisant sa pile**
jusqu'à la cible. Aucune URL n'est cassée, la PWA et le futur app-linking mobile
continuent de fonctionner à l'identique.

### 5.2 Transitions

- **Aucune transition (pas de slide) entre onglets.** Le changement de branche
  est instantané (`indexedStack` affiche/masque, il n'anime pas). C'est le
  comportement Material attendu : les onglets sont des contextes parallèles, pas
  une hiérarchie.
- **`AppTransition.standard` (400 ms)** conservée pour les `push()` internes à
  une branche (détail, formulaire) — cohérence hiérarchique.
- **`AppTransition.fade` (300 ms)** conservée pour les routes hors shell
  (landing ↔ auth ↔ simulateur) — changement radical de contexte.
- La bascule shell ↔ hors-shell (login/logout) reste gérée par la **garde 3
  états** (redirect), pas par une transition.

---

## 6. Devenir de `fallbackRoute` et de `AppAppBar` dans le shell

Aujourd'hui, `AppAppBar` gère le retour ainsi (cf. `_resolveLeading`) :

1. `leading` explicite → override ;
2. `showBackButton == false` → pas de leading ;
3. `Navigator.canPop(context)` → `BackButton` natif ;
4. sinon `fallbackRoute` fourni → `IconButton` qui `go(fallbackRoute)` ;
5. sinon null.

**Dans le shell, cette logique se simplifie** :

- Sur une **racine de branche** (`/dashboard`, `/properties`, `/tenants`,
  `/leases`, `/profile`), la pile de la branche est vide → **pas de bouton
  retour** (l'onglet actif tient lieu de repère). Ces pages passent donc
  `showBackButton: false` (ou n'ont plus besoin de `fallbackRoute`).
- Sur une **sous-page** (`/leases/:id`, `/tenants/:id/edit`, …), il y a une pile
  → `Navigator.canPop` est `true` → **`BackButton` natif qui `pop()`** dans la
  branche. C'est déjà le cas n°3 : **le comportement est correct sans
  modification.**
- **`fallbackRoute` devient un filet de sécurité** (deep link direct sur une
  sous-page → pile mono-élément → `canPop` false → fallback vers la racine de la
  branche). On **conserve** `fallbackRoute` sur les sous-pages, pointant vers la
  racine de leur branche (`/leases`, `/tenants`, `/properties`, `/profile`) — ce
  qui est déjà le cas. **Aucun changement requis sur les sous-pages.**

**Changements concrets sur `AppAppBar`** :

- Les 4 racines de section (`PropertiesListPage`, `TenantsListPage`,
  `LeasesListPage`, `ProfilePage`) passent de `fallbackRoute: '/dashboard'` à
  `showBackButton: false` (elles ne doivent plus offrir de retour vers le
  dashboard : le dashboard n'est plus leur parent, c'est un onglet frère).
- Le dashboard (`Accueil`) : `showBackButton: false` **déjà en place** ; on lui
  **retire les deux `IconButton` profil/déconnexion** de ses `actions` (§3.2).
- `AppAppBar` **n'a pas besoin d'évoluer structurellement** : sa logique
  `canPop → BackButton, sinon fallbackRoute` reste valide dans une branche.

> Chaque branche a son propre `Navigator` (imbriqué). `Navigator.canPop` évalue
> le `Navigator` de la branche, ce qui donne exactement le comportement voulu :
> le retour dépile la branche, il ne quitte pas le shell.

---

## 7. Le dashboard devient l'onglet Accueil

- **Reste** : KPI cliquables (drill-down), graphique mensuel, rendement
  portefeuille, activité récente, onboarding « premiers pas », bannière
  d'installation PWA.
- **Change** :
  - Suppression des `IconButton` profil + déconnexion de l'`AppBar` (→ onglet
    Profil).
  - `ShortcutsRow` : **les raccourcis redondants avec les onglets dégagent**
    (Biens, Locataires, Baux sont déjà des destinations). Reste **uniquement** le
    point d'entrée **Simulateur** (hors shell — c'est le seul « ailleurs » utile
    depuis Accueil), reformulé en carte/CTA « Simuler un investissement ».
  - Titre AppBar : peut devenir « Accueil » ou rester « Baillan. » (cohérence de
    marque). **Décision proposée : « Accueil »** pour l'homogénéité des titres de
    section ; à trancher (§12).
- **KPI drill-down** : conservés. Ils `go('/leases?filter=active|renewable')` —
  ce qui **active la branche Baux + applique le filtre**. Comportement attendu :
  changer d'onglet **et** filtrer, en un tap. `go()` (et non `goBranch`) est
  correct ici car on veut positionner la branche sur une URL précise avec query.

---

## 8. Structure technique de migration (StatefulShellRoute)

### 8.1 Cible

```
GoRouter(
  initialLocation: '/',
  refreshListenable: refreshNotifier,      // INCHANGÉ (commit 07f20a3)
  redirect: (context, state) { … },        // INCHANGÉ (garde 3 états TEL QUEL)
  routes: [
    // --- Hors shell (public / auth / anonyme) ---
    GoRoute('/', LandingPage, fade),
    GoRoute('/login' … '/terms', fade),
    GoRoute('/simulator', SimulatorPage, standard),      // plein écran
    GoRoute('/simulator/:id', SimulatorPage, standard),  // plein écran

    // --- Shell adaptatif ---
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AdaptiveNavigationScaffold(shell: navigationShell), // NavBar/Rail
      branches: [
        StatefulShellBranch(routes: [ GoRoute('/dashboard', …) ]),
        StatefulShellBranch(routes: [
          GoRoute('/properties', … , routes: [
            GoRoute('new'), GoRoute(':id', routes: [ GoRoute('edit') ]),
          ]),
        ]),
        StatefulShellBranch(routes: [ /* /tenants + sous-routes */ ]),
        StatefulShellBranch(routes: [ /* /leases + payments + receipts */ ]),
        StatefulShellBranch(routes: [ /* /profile + details/password/support */ ]),
      ],
    ),
  ],
)
```

> **Note d'implémentation** : dans le shell, on privilégie des **sous-routes
> imbriquées** (`routes:` sur chaque `GoRoute`) plutôt que des chemins absolus
> frères, pour que GoRouter empile correctement dans la bonne branche. Les
> chemins relatifs (`new`, `:id`, `edit`) restent résolus en absolu à l'URL
> (`/properties/new`). C'est un point d'attention pour flutter-dev : **les URLs
> publiques ne changent pas**, seule l'arborescence de déclaration change.

### 8.2 Nouveau widget (le seul vrai code neuf)

`lib/core/ui/navigation/adaptive_navigation_scaffold.dart` — `StatelessWidget`
qui reçoit le `StatefulNavigationShell` et rend :

- `LayoutBuilder` → si `constraints.maxWidth < 600` : `Scaffold` +
  `bottomNavigationBar: NavigationBar` ; sinon : `Row(NavigationRail, contenu)`.
- `selectedIndex: shell.currentIndex`, `onDestinationSelected: (i) =>
  shell.goBranch(i, initialLocation: i == shell.currentIndex)`.
  (`initialLocation: true` sur re-tap de l'onglet actif = « pop to root » de la
  branche, comportement Material attendu.)
- 5 destinations (icône outline / filled selon sélection, label FR).
- `SafeArea` (voir §9).

> **Découpage < 200 lignes** (CONVENTIONS) : extraire la liste de destinations
> en `const _destinations` et, si besoin, un `_NavRail` / `_NavBar` privé.

### 8.3 Étapes de migration (ordre d'exécution)

1. **Créer `AdaptiveNavigationScaffold`** (widget shell, NavBar/Rail + SafeArea).
2. **Refondre `app_router.dart`** : envelopper les 5 branches dans
   `StatefulShellRoute.indexedStack` ; sortir landing/auth/simulateur du shell ;
   **conserver `redirect` et `refreshListenable` à l'identique** (garde 3 états +
   fix 07f20a3 intacts).
3. **Dashboard** : retirer les `IconButton` profil/déconnexion ; réduire
   `ShortcutsRow` au seul simulateur (ou le déplacer en carte CTA).
4. **Racines de section** : `PropertiesListPage`, `TenantsListPage`,
   `LeasesListPage`, `ProfilePage` → `showBackButton: false` (retirer
   `fallbackRoute: '/dashboard'`).
5. **Sous-pages** : **aucun changement** (leur `fallbackRoute` relatif + le
   `BackButton` natif restent corrects).
6. **Simulateur** : rendre le point d'entrée compte depuis Accueil (CTA) ;
   vérifier que le retour depuis `/simulator` (compte) revient au shell.
7. **Tests** : adapter/étendre (voir §10).

> **La garde 3 états n'est pas touchée.** Elle continue de rediriger
> `unauthenticated → /login`, `anonymous → /simulator`,
> `fullyAuthenticated → /dashboard`. Le shell vit **sous** la garde : un
> utilisateur non pleinement authentifié n'atteint jamais une branche du shell
> (le redirect le sort avant).

---

## 9. Compatibilité mobile (FEAT-024)

**La structure est identique sur web et mobile — c'est tout l'intérêt.** Points
d'attention natifs :

- **`SafeArea`** : la `NavigationBar` doit respecter le safe-area **bottom**
  (home indicator iOS, gesture bar Android) ; le `NavigationRail` respecte le
  safe-area **left** (notch en paysage). Material gère `SafeArea` en partie, mais
  le scaffold shell doit l'expliciter pour le contenu.
- **`resizeToAvoidBottomInset`** : sur les sous-pages avec formulaire (branches),
  le clavier ne doit pas masquer les champs — comportement natif à vérifier (déjà
  noté dans MOBILE §7).
- **Tailles cibles tactiles** : destinations `NavigationBar` ≥ 48×48 dp (défaut
  Material OK) ; vérifier les `IconButton` d'AppBar restants (édition, etc.).
- **`NavigationBar` iOS vs `BottomNavigationBar` Cupertino** : on **reste sur
  `NavigationBar` Material** (le reste de l'app est Material 3) — cohérence
  cross-platform assumée, pas de bascule Cupertino.
- **Le shell réduit le chantier mobile** : plus besoin d'inventer une navigation
  tactile spécifique en J3. La « passe UI mobile » (MOBILE §7) se limite à
  SafeArea + clavier + touch targets sur une structure déjà bonne.

**Conséquence pour le plan de semaine mobile** : le shell adaptatif devient un
**prérequis J1** (voir `docs/MOBILE.md`). Idéalement, FEAT-026 est livré **sur le
web avant** le démarrage mobile, pour que la semaine mobile parte d'une base déjà
navigable au tactile.

---

## 10. Impact sur les tests & stratégie de test

### 10.1 Tests existants — impact

| Test | Impact | Action |
|---|---|---|
| `router_three_state_guard_test.dart` | **Faible.** Il pilote le router (`router.go(location)`) et lit `currentConfiguration.uri`. La garde est inchangée, les paths sont inchangés. | **Re-run.** Attendu vert sans modif. Vérifier que `pumpAndSettle` résout bien les branches (ajout éventuel d'un `pump` si l'`indexedStack` diffère le 1er build). |
| `router_auth_refresh_test.dart` | **Faible/Moyen.** Teste le refresh à chaud (login → redirect). La cible `/dashboard` est désormais une racine de branche → le shell est monté. Le test pompe déjà un dashboard mocké. | **Re-run + vérifier** que le dashboard s'affiche dans le shell (l'`AdaptiveNavigationScaffold` wrappe le body). Adapter les `find` si un finder visait l'`AppBar` du dashboard. |
| `router_guard_test.dart` (binaire historique) | Faible. | Re-run. |
| `dashboard_page_test.dart` | **Moyen.** Il vérifie probablement les `IconButton` profil/déconnexion (qu'on supprime) et `ShortcutsRow` (qu'on réduit). | **À mettre à jour** : retirer les assertions sur les icônes AppBar supprimées et sur les raccourcis Biens/Locataires/Baux ; garder l'assertion simulateur. |
| `app_app_bar_test.dart` | Faible. `AppAppBar` inchangé structurellement. | Re-run. Éventuel test additionnel : `showBackButton: false` sur racine de branche. |
| `tenant_lease_summary_nav_test.dart` | Faible. Teste `push` vers un bail. | Re-run. |

### 10.2 Tests à écrire (nouveaux)

- **`adaptive_navigation_scaffold_test.dart`** (widget) :
  - < 600 px → `NavigationBar` présente, `NavigationRail` absente ;
  - ≥ 600 px → `NavigationRail` présente, `NavigationBar` absente ;
  - tap sur une destination → `goBranch` appelé avec le bon index ;
  - `selectedIndex` reflète la branche active.
- **`shell_branch_state_test.dart`** (widget) : naviguer Baux → pousser un
  détail → basculer Biens → revenir Baux → **le détail est toujours empilé**
  (preuve de préservation d'état `indexedStack`).
- **Étendre `router_three_state_guard_test.dart`** : deep link direct sur une
  sous-page (`/leases/:id`) en `fullyAuthenticated` → branche Baux active + pile
  construite ; en `anonymous` → redirect `/simulator` (garde intacte).

### 10.3 QA manuelle (parcours à valider)

1. Login → Accueil ; taper chaque onglet → la bonne section s'affiche.
2. Baux → ouvrir un bail → onglet Biens → revenir Baux : **le bail est encore
   ouvert** (état préservé).
3. KPI « baux actifs » sur Accueil → bascule sur Baux **filtré** actif.
4. Deep link `app.com/leases/<id>` (nouvel onglet navigateur) → Baux ouvert sur
   le détail, retour ramène à la liste Baux.
5. Anonyme : jamais d'onglets, simulateur plein écran, pas d'accès métier.
6. Redimensionnement fenêtre autour de 600 px → bascule NavigationBar ↔
   NavigationRail sans perte d'état.
7. Déconnexion depuis Profil → retour landing/login (garde).
8. (Mobile, FEAT-024) SafeArea : NavigationBar au-dessus du home indicator.

---

## 11. Options écartées

**Option A — Baux en sous-onglet de Biens/Locataires (pas de destination
propre).** Écartée : le bail est l'objet d'usage quotidien (paiements,
quittances) ; l'enterrer d'un niveau pénalise le geste le plus fréquent. 5
onglets restent dans la limite Material 3.

**Option B — Profil en icône d'avatar dans l'AppBar (hors shell).** Écartée :
anti-pattern tactile (cible haute, éloignée du pouce), et le `/profile` est déjà
un hub mobile-first destiné à être une racine. Une icône d'AppBar dupliquerait un
accès déjà porté par un onglet.

**Option C — Simulateur comme onglet (fixe ou conditionnel au SessionState).**
Écartée : un onglet conditionnel qui apparaît/disparaît selon anonyme/compte est
déroutant et complexifie le shell ; et un onglet fixe exposerait aux anonymes 4
destinations mortes. Le simulateur est un « outil » ponctuel, pas une section →
point d'entrée depuis Accueil + `push` plein écran.

**Option D — `ShellRoute` simple (sans état par branche).** Écartée : ne
préserve pas les piles/scroll/filtres par onglet — on perdrait l'état de Baux en
passant par Biens. `StatefulShellRoute.indexedStack` est explicitement conçu pour
ce besoin.

**Option E — `NavigationDrawer` (menu hamburger) au lieu de Bar/Rail.** Écartée :
le drawer cache la navigation derrière un tap supplémentaire et est moins bon sur
mobile que la `NavigationBar`. Le rail (≥600) offre la même densité sans masquer.
(Un drawer pourra compléter le rail plus tard si le nombre de destinations
secondaires explose — hors scope.)

**Option F — Migrer d'abord sur mobile, garder le web en hub.** Écartée :
maintiendrait deux modèles de navigation divergents ; l'objectif explicite est
**un seul concept web+mobile**.

---

## 12. Critères d'acceptation

- [ ] Shell `StatefulShellRoute.indexedStack` à 5 branches (Accueil, Biens,
      Locataires, Baux, Profil).
- [ ] `NavigationBar` (<600 px) / `NavigationRail` (≥600 px), bascule au
      breakpoint 600 px.
- [ ] État de chaque branche préservé au changement d'onglet (pile + scroll +
      filtres).
- [ ] Changement d'onglet via `goBranch` ; sous-navigation via `push` ; deep
      links inchangés et fonctionnels.
- [ ] Garde 3 états **inchangée** (fix 07f20a3 intact) ; anonyme sans onglets ;
      simulateur hors shell.
- [ ] Dashboard = onglet Accueil, sans icônes profil/déconnexion, sans raccourcis
      redondants (simulateur conservé en CTA).
- [ ] Racines de branche sans bouton retour ; sous-pages avec retour natif.
- [ ] `SafeArea` respectée (prépare FEAT-024).
- [ ] Tests de garde verts ; nouveaux tests shell (adaptatif + préservation
      d'état) verts ; `flutter analyze` clean.
- [ ] `dart format .` OK ; `code-reviewer` ✅ ; `security-auditor` ✅ (surface
      inchangée : mêmes routes, même garde, mêmes rules).

---

## 13. Décisions nécessitant validation utilisateur

Voir la synthèse en fin de rapport de l'architecte. En résumé :

1. **5 onglets, Baux inclus** (vs 4 sans Baux).
2. **Profil en onglet** (vs icône d'avatar dans l'AppBar).
3. **Simulateur hors shell** (vs onglet).
4. **Suppression des raccourcis redondants** du dashboard (Biens/Locataires/Baux).
5. **Titre de l'onglet 0** : « Accueil » (vs garder « Baillan. »).
6. **FEAT-026 livré sur web avant le démarrage mobile** (prérequis J1 vs chantier
   pendant la semaine).
