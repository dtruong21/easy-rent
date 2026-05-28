# Routes Flutter — snapshot

> Maintenu par `state-keeper`. **Source** : `lib/core/router/app_router.dart`. **Dernière sync** : 2026-05-28 (FEAT-003 mergée)

## Routes go_router

| Path | Widget | Feature | Auth requise | Statut |
|---|---|---|---|---|
| `/` | `DashboardPage` | dashboard | ✅ oui | 🟢 implémentée (layout stub + "Mes biens" link) |
| `/login` | `LoginPage` | auth | ❌ non (redirect si authentifié) | 🟢 implémentée (magic link PKCE) |
| `/privacy` | `PrivacyPage` | privacy | ❌ non (public) | 🚧 placeholder |
| `/properties` | `PropertiesListPage` | properties | ✅ oui | 🟢 implémentée (FEAT-003) |
| `/properties/new` | `PropertyFormPage` | properties | ✅ oui | 🟢 implémentée (CREATE form) |
| `/properties/:id` | `PropertyDetailPage` | properties | ✅ oui | 🟢 implémentée (READ + DELETE button) |
| `/properties/:id/edit` | `PropertyEditPage` | properties | ✅ oui | 🟢 implémentée (UPDATE form) |

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

Dashboard modifié (FEAT-003) : ListTile "Mes biens" navigue vers `/properties`. Drawer ou bottom nav complète à ajouter dans les prochaines features (FEAT-004+ pour tenants, baux, etc.).

## Routes prévues (non implémentées)

- `/tenants` — Liste des locataires (FEAT-004)
- `/tenants/new` — Créer locataire
- `/tenants/:id` — Fiche locataire
- `/tenants/:id/edit` — Modifier locataire
- `/leases` — Liste des baux (FEAT-005)
- `/leases/:id` — Fiche bail
- `/payments` — Suivi paiements (FEAT-008+)
- `/receipts` — Quittances émises (FEAT-006+)
- `/documents` — Documents stockés (FEAT-008+)
- `/settings` — Paramètres compte propriétaire (FEAT-009+)

## Widgets de layout

- **AppBar** : `title: "EasyRent"` (à enrichir avec menu/actions)
- **Drawer/NavBar** : À créer (prochaine étape navigation)

## Code generation & Build

- `flutter pub run build_runner build` génère les routeurs et modèles (freezed + json_serializable)
- **Step ajouté en CI/CD** : `deploy.yml` exécute `dart run build_runner build` avant la build Flutter
