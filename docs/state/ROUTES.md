# Routes Flutter — snapshot

> Maintenu par `state-keeper`. **Source** : `lib/core/router/app_router.dart`. **Dernière sync** : 2026-05-27

## Routes go_router

| Path | Widget | Feature | Auth requise | Statut |
|---|---|---|---|---|
| `/` | `DashboardPage` | dashboard | ✅ oui | 🚧 stub |
| `/login` | `LoginPage` | auth | ❌ non (redirect si déjà loggué) | 🚧 stub |

## Logique de redirect

Dans [`lib/core/router/app_router.dart`](../../lib/core/router/app_router.dart) :
- Non-authentifié + route ≠ `/login` → redirect `/login`
- Authentifié + route `/login` → redirect `/`

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

## Code generation

- `flutter pub run build_runner build` génère les routeurs et modèles (freezed + json_serializable)
