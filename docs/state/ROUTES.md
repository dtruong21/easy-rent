# Routes Flutter — snapshot

> Maintenu par `state-keeper`. **Source** : `lib/core/router/app_router.dart`. **Dernière sync** : 2026-06-22 (FEAT-010 Section A — dashboard refonte, `/` route refondée)

## Routes go_router

| Path | Widget | Feature | Auth requise | Statut |
|---|---|---|---|---|
| `/` | `DashboardPage` | dashboard | ✅ oui | ✅ refondée FEAT-010 (4 KPI cards, barchart 6 mois, activité récente, onboarding, install prompt PWA) |
| `/login` | `LoginPage` | auth | ❌ non (redirect si authentifié) | ✅ implémentée (magic link PKCE) |
| `/privacy` | `PrivacyPage` | privacy | ❌ non (public) | 🟢 enrichie FEAT-010 (RGPD + mentions légales + export/effacement GDPR) |
| `/properties` | `PropertiesListPage` | properties | ✅ oui | ✅ implémentée (FEAT-003) |
| `/properties/new` | `PropertyFormPage` | properties | ✅ oui | ✅ implémentée (CREATE form) |
| `/properties/:id` | `PropertyDetailPage` | properties | ✅ oui | ✅ implémentée (READ + DELETE button) |
| `/properties/:id/edit` | `PropertyEditPage` | properties | ✅ oui | ✅ implémentée (UPDATE form) |
| `/tenants` | `TenantsListPage` | tenants | ✅ oui | ✅ implémentée (FEAT-004) |
| `/tenants/new` | `TenantFormPage` | tenants | ✅ oui | ✅ implémentée (CREATE form) |
| `/tenants/:id` | `TenantDetailPage` | tenants | ✅ oui | ✅ implémentée (READ + DELETE button + lease summary) |
| `/tenants/:id/edit` | `TenantEditPage` | tenants | ✅ oui | ✅ implémentée (UPDATE form) |
| `/leases` | `LeasesListPage` | leases | ✅ oui | ✅ implémentée (FEAT-005, filtre par statut) |
| `/leases/new` | `LeaseFormPage` | leases | ✅ oui | ✅ implémentée (CREATE form, picker propriété/locataire) |
| `/leases/:id` | `LeaseDetailPage` | leases | ✅ oui | ✅ implémentée (READ + status enum, paiements section, quittances section) |
| `/leases/:id/edit` | `LeaseEditPage` | leases | ✅ oui | ✅ implémentée (UPDATE form) |
| `/leases/:id/payments/new` | `PaymentFormPage` | payments | ✅ oui | ✅ implémentée (FEAT-006, pré-remplit depuis lease) |
| `/leases/:id/payments/:pid/edit` | `PaymentEditPage` | payments | ✅ oui | ✅ implémentée (FEAT-006, UPDATE payment) |
| `/leases/:id/receipts` | `LeaseReceiptsPage` | receipts | ✅ oui | ✅ implémentée (FEAT-007+008, liste quittances + PDF preview + void + send email) |
| `/profile` | `ProfilePage` | profile | ✅ oui | ✅ implémentée (FEAT-007, paramètres bailleur + test API) |

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

Dashboard (FEAT-010 refonde) : Affiche 4 KPI cards + barchart + activité récente + onboarding (si zéro données) + install prompt PWA au 1er login.

LeaseDetailPage (FEAT-005) : Affiche bail + bouton "Ajouter paiement" (disabled si lease fermé) et section liste paiements (FEAT-006) + section quittances (FEAT-007).

DashboardPage (FEAT-010) : Navigation principale → `/properties`, `/tenants`, `/leases` via raccourcis ou drawer (TBD).

## Routes prévues (non implémentées)

- `/documents` — Documents stockés (FEAT-009, route juste déclarée, UI non implémentée)
- `/settings` — Paramètres avancés (FEAT-011+)
- `/analytics` — Dashboard analytics avancées (FEAT-012+)

## Widgets de layout

- **AppBar** : `title: "EasyRent"` + actions (back button, menu contextuel)
- **Drawer** : Navigation principale (propriétés, locataires, baux, documents TBD, profil)
- **InstallPromptBanner** : PWA install banner (FEAT-010, visible 1 fois par semaine)

## Code generation & Build

- `flutter pub run build_runner build` génère les routeurs et modèles (freezed + json_serializable)
- **Step en CI/CD** : `deploy.yml` exécute `dart run build_runner build` avant la build Flutter
