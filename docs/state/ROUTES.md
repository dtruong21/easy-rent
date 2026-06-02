# Routes Flutter — snapshot

> Maintenu par `state-keeper`. **Source** : `lib/core/router/app_router.dart`. **Dernière sync** : 2026-06-01 (FEAT-007 Phase 3 mergée — `/leases/:id/receipts` + `/profile`)

## Routes go_router

| Path | Widget | Feature | Auth requise | Statut |
|---|---|---|---|---|
| `/` | `DashboardPage` | dashboard | ✅ oui | 🟢 implémentée (layout + links "Mes biens", "Mes locataires", "Mes baux") |
| `/login` | `LoginPage` | auth | ❌ non (redirect si authentifié) | 🟢 implémentée (magic link PKCE) |
| `/privacy` | `PrivacyPage` | privacy | ❌ non (public) | 🚧 placeholder |
| `/properties` | `PropertiesListPage` | properties | ✅ oui | 🟢 implémentée (FEAT-003) |
| `/properties/new` | `PropertyFormPage` | properties | ✅ oui | 🟢 implémentée (CREATE form) |
| `/properties/:id` | `PropertyDetailPage` | properties | ✅ oui | 🟢 implémentée (READ + DELETE button) |
| `/properties/:id/edit` | `PropertyEditPage` | properties | ✅ oui | 🟢 implémentée (UPDATE form) |
| `/tenants` | `TenantsListPage` | tenants | ✅ oui | 🟢 implémentée (FEAT-004) |
| `/tenants/new` | `TenantFormPage` | tenants | ✅ oui | 🟢 implémentée (CREATE form) |
| `/tenants/:id` | `TenantDetailPage` | tenants | ✅ oui | 🟢 implémentée (READ + DELETE button + lease summary) |
| `/tenants/:id/edit` | `TenantEditPage` | tenants | ✅ oui | 🟢 implémentée (UPDATE form) |
| `/leases` | `LeasesListPage` | leases | ✅ oui | 🟢 implémentée (FEAT-005, filtre par statut) |
| `/leases/new` | `LeaseFormPage` | leases | ✅ oui | 🟢 implémentée (CREATE form, picker propriété/locataire) |
| `/leases/:id` | `LeaseDetailPage` | leases | ✅ oui | 🟢 implémentée (READ + status enum, paiements section, quittances TBD FEAT-007) |
| `/leases/:id/edit` | `LeaseEditPage` | leases | ✅ oui | 🟢 implémentée (UPDATE form) |
| `/leases/:id/payments/new` | `PaymentFormPage` | payments | ✅ oui | 🟢 implémentée (FEAT-006, pré-remplit depuis lease) |
| `/leases/:id/payments/:pid/edit` | `PaymentEditPage` | payments | ✅ oui | 🟢 implémentée (FEAT-006, UPDATE payment) |
| `/leases/:id/receipts` | `LeaseReceiptsPage` | receipts | ✅ oui | 🚧 implémentée (FEAT-007/FEAT-008, liste quittances + PDF preview + void + bouton envoi email dans ReceiptListTile) |
| `/profile` | `ProfilePage` | profile | ✅ oui | 🚧 implémentée (FEAT-007, paramètres bailleur + test API) |

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

Dashboard enrichi (FEAT-003/004/005/006) : ListTiles "Mes biens", "Mes locataires" et "Mes baux" naviguent vers `/properties`, `/tenants` et `/leases`. Drawer ou bottom nav complète à ajouter dans les prochaines features (FEAT-007+ pour quittances, etc.).

LeaseDetailPage (FEAT-005) : Affiche bail + bouton "Ajouter paiement" (disabled si lease fermé) et section liste paiements (FEAT-006).

## Routes prévues (non implémentées)

- `/documents` — Documents stockés (FEAT-009)
- `/settings` — Paramètres avancés (FEAT-010)
- `/analytics` — Dashboard analytics (FEAT-010)

## Widgets de layout

- **AppBar** : `title: "EasyRent"` (à enrichir avec menu/actions)
- **Drawer/NavBar** : À créer (prochaine étape navigation)

## Code generation & Build

- `flutter pub run build_runner build` génère les routeurs et modèles (freezed + json_serializable)
- **Step ajouté en CI/CD** : `deploy.yml` exécute `dart run build_runner build` avant la build Flutter
