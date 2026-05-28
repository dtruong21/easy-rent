# Routes Flutter — snapshot

> Maintenu par `state-keeper`. **Source** : `lib/core/router/app_router.dart`. **Dernière sync** : 2026-05-28

## Routes go_router

| Path | Widget | Feature | Auth requise | Statut |
|---|---|---|---|---|
| `/` | `DashboardPage` | dashboard | ✅ oui | 🚧 stub |
| `/login` | `LoginPage` | auth | ❌ non (redirect si authentifié) | 🟢 implémentée (magic link PKCE) |
| `/privacy` | `PrivacyPage` | privacy | ❌ non (public) | 🚧 placeholder |

## Logique de redirect

Dans [`lib/core/router/app_router.dart`](../../lib/core/router/app_router.dart) :
- Non-authentifié + route ≠ `/login` → redirect `/login` (sauf `/privacy` qui est public)
- Authentifié + route `/login` → redirect `/`
- Route `/privacy` : toujours accessible

**Implémentation** : Custom `GoRouterRefreshStream` classe dans `lib/core/router/go_router_refresh_stream.dart` écoute `authRepository.authStateChanges` et déclenche re-évaluation des redirects à chaque changement de session.

## Authentification

- **Type** : Magic link via email (PKCE implicit flow)
- **Fournisseur** : Supabase Auth native
- **Provider** : `authRepositoryProvider` (Riverpod, voir `lib/features/auth/data/auth_repository.dart`)
- **État de session** : `isAuthenticatedProvider` (getter simplifié du state d'auth)

## Navigation principale

À implémenter dans FEAT-002 (CRUD biens) : drawer ou bottom nav avec les sections principales (Dashboard, Biens, Locataires, Baux, Documents).

## Routes prévues (non implémentées)

- `/properties` — Liste des biens immobiliers
- `/properties/:id` — Fiche bien
- `/tenants` — Liste des locataires
- `/tenants/:id` — Fiche locataire
- `/leases` — Liste des baux
- `/leases/:id` — Fiche bail
- `/payments` — Suivi paiements
- `/receipts` — Quittances émises
- `/documents` — Documents stockés
- `/settings` — Paramètres compte propriétaire

## Widgets de layout

- **AppBar** : `title: "EasyRent"` (à enrichir avec menu/actions)
- **Drawer/NavBar** : À créer (prochaine étape navigation)

## Code generation & Build

- `flutter pub run build_runner build` génère les routeurs et modèles (freezed + json_serializable)
- **Step ajouté en CI/CD** : `deploy.yml` exécute `dart run build_runner build` avant la build Flutter
