# Routes — index & modèle de navigation

> Source d'état — routes (index). Maintenu par state-keeper.

**Source** : `lib/core/router/app_router.dart`. Sync 2026-07-21. GoRouter 14.6.0, `StatefulShellRoute.indexedStack`. **36 `GoRoute` déclarées** (nested), **0 route nommée** — la navigation se fait par chemin (`context.go/push('/...')`), il n'y a **aucun `name:`** dans le router (l'état annonçait « ~50 routes nommées », ce qui envoyait chercher des `goNamed` inexistants). Redirect `redirect(context, state)` lit `state.matchedLocation`.

## Modèle 3-états (sessionStateProvider, Riverpod StreamProvider)

| État | Accès | Redirect défaut |
|---|---|---|
| unauthenticated | landing `/` + publicRoutes | `/login` (RED-001) |
| anonymous (essai 14j BAILLAN-M1) | `/simulator[/:id]` + publicRoutes ; `/`→`/simulator` | `/` (RED-002, route métier→landing) |
| fullyAuthenticated (email/pwd/Google/Apple) | shell + toutes routes ; `/`→`/dashboard` ; `/login`\|`/signup`→`/dashboard` | — (RED-003) |

- `publicRoutes` (valeur exacte du code) = {`/login`, `/signup`, `/forgot-password`, `/reset-password`, `/privacy`, `/terms`, `/legal`, `/delete-account`, `/faq`} — **9 entrées**.
- ⚠️ Corrigé 2026-07-21 : `/legal` manquait de la liste, et `/delete-account`/`/faq` étaient décrits comme « hors set publicRoutes » alors qu'ils **sont dans le set** (donc accessibles à tous les états, anonyme inclus).
- `isAnonAccessible` = `location == '/simulator'` OU `location.startsWith('/simulator/')`.
- Refresh : `ref.listen(sessionStateProvider)` → `_RouterRefreshNotifier.refresh()` re-évalue redirect immédiatement post-auth (fix race commit 07f20a3, FEAT-030).

## Erreurs d'accès (guard)

| Condition | Redirect | Code |
|---|---|---|
| unauthenticated + non-public | `/login` | RED-001 |
| anonymous + non-accessible | `/` | RED-002 |
| fullyAuthenticated + `/login` | `/dashboard` | RED-003 |

## Shell nav (FEAT-026 — StatefulShellRoute.indexedStack, 5 branches, fullyAuthenticated only ; anonyme redirigé)

| Branche | Racine | Domaine shard |
|---|---|---|
| 0 Accueil | `/dashboard` | dashboard |
| 1 Biens | `/properties` | properties (+ `/expenses…` → expenses-documents) |
| 2 Locataires | `/tenants` | properties |
| 3 Baux | `/leases` | leases (+ payments/receipts → payments-receipts) |
| 4 Profil | `/profile` | account |

- Responsive : `<600px` NavigationBar bottom (5 dest, labels+icônes) ; `≥600px` NavigationRail left (compact ou libellés+icônes).
- `railExpandedProvider` (FEAT-026) : StateProvider<bool>, SharedPreferences, défaut `true` (expanded).
- **Réinitialisation au changement d'onglet** (commit 49d6069, 2026-08-11, renversement de décision produit) : `goBranch(index, initialLocation: true)` systématique ramène chaque branche à sa racine. ⚠️ L'implémentation reste `indexedStack` (chaque branche garde son Navigator), donc le `State` d'une racine **jamais quittée en profondeur** (aucune sous-page poussée) survit, ainsi que sa position de scroll et ses filtres (`StateProvider` Riverpod non-autoDispose). Détail & historique des arbitrages → `docs/UX_NAVIGATION.md` encart en tête (§5.1). Branding logo Baillan (réplié icône / déplié wordmark).

## Transitions (`lib/core/router/transitions.dart`)

| Transition | Animation | Usage |
|---|---|---|
| `AppTransition.standard` | slide bottom→top, 200ms | nested routes (shell + métier) |
| `AppTransition.fade` | fade opacity 0→1, 150ms | auth forms (landing, login, signup) |

## Deep linking & navigation externe

- Web URLs = chemins directs `https://baillan.com/<path>` (landing, /login, /dashboard, /properties/:id, /leases/:id?action=regularize, /simulator…). **Domaine canonique depuis PR #121** (`Env.publicAppUrl`, `web/index.html`, sitemap, robots) — l'ancienne mention `easyrent.app` était fausse. Staging = `stage.baillan.com` (site Hosting distinct, cible `stage`, PR #124).
- ⚠️ Les identifiants du **projet** Firebase (`projectId`/`authDomain`/`storageBucket` = `easy-rent-54cd4*`) ne sont PAS le domaine public et ne doivent pas être renommés.
- Email : `/reset-password?token=…` (extraction via `state.uri.queryParameters`).
- Firebase Dynamic Links : à implémenter (passthrough → URLs standard).
- Deep-links spécifiques par domaine : voir shard concerné.

## Checklist nav (QA FEAT-030)

- Formulaires (`new`/`edit`) → `pop()` au succès (retour fiche, pas liste).
- Tuiles Accueil → `push()` (stack conservée).
- Bouton Profil retiré de fiche bail (contradictoire avec stack).
- Simulateur → `push()` par-dessus shell (plein écran, pas remplacement).
- Drill-down KPI dashboard → `/leases?filter=late` (présélection).
- `/leases/:id?action=regularize` → auto-ouvre dialog (pas de subroute).

## Index routes → shard

| Route(s) | Shard |
|---|---|
| `/` | account |
| `/login`, `/signup`, `/forgot-password`, `/reset-password` | account |
| `/privacy`, `/terms` | account |
| `/delete-account`, `/faq` | account |
| `/profile`, `/profile/details`, `/profile/password`, `/profile/support`, `/profile/delete-account` | account |
| `/dashboard` | dashboard |
| `/properties`, `/properties/new`, `/properties/:id`, `/properties/:id/edit` | properties |
| `/tenants`, `/tenants/new`, `/tenants/:id`, `/tenants/:id/edit` | properties |
| `/properties/:id/expenses`, `…/new`, `…/:eid/edit` | expenses-documents |
| `/leases`, `/leases/new`, `/leases/:id`, `/leases/:id/edit` | leases |
| `/leases/:id/payments/new`, `…/:pid/edit`, `/leases/:id/receipts` | payments-receipts |
| `/simulator`, `/simulator/:id` | simulator |

**FEATs cross-cutting (ici)** : FEAT-026 (shell nav wrapper), FEAT-030 (navigation fix : redirect tuning + transitions).
