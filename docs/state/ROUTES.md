# Routes Flutter — snapshot

> Maintenu par `state-keeper`. **Source** : `lib/core/router/app_router.dart`. **Dernière sync** : 2026-06-25 (FEAT-013 Phase 1+2 transitions + AppAppBar)

## Routes go_router (18 total)

| Path | Widget | Feature | Auth | Transition | Statut |
|---|---|---|---|---|---|
| `/` | `DashboardPage` | dashboard | ✅ | standard | ✅ FEAT-010 refonde (4 KPI, barchart 6m, activité, onboarding, PWA) |
| `/login` | `LoginPage` | auth | ❌ | fade | ✅ FEAT-011 (email + password) |
| `/signup` | `SignupPage` | auth | ❌ | fade | ✅ FEAT-011 (email + full_name + password × 2) |
| `/forgot-password` | `ForgotPasswordPage` | auth | ❌ | fade | ✅ FEAT-011 (reset link request) |
| `/reset-password` | `ResetPasswordPage` | auth | ❌ | fade | ✅ FEAT-011 (token validation + change password) |
| `/privacy` | `PrivacyPage` | privacy | ❌ | fade | ✅ FEAT-010 (RGPD + legal mentions + GDPR export/delete) |
| `/properties` | `PropertiesListPage` | properties | ✅ | standard | ✅ FEAT-003, FEAT-012 Phase 2 cards refonte |
| `/properties/new` | `PropertyFormPage` | properties | ✅ | standard | ✅ FEAT-003 (CREATE form) |
| `/properties/:id` | `PropertyDetailPage` | properties | ✅ | standard | ✅ FEAT-003, FEAT-015 expose FEAT-014 Phase 1 fields |
| `/properties/:id/edit` | `PropertyEditPage` | properties | ✅ | standard | ✅ FEAT-003 (UPDATE form, FEAT-014 Phase 1) |
| `/tenants` | `TenantsListPage` | tenants | ✅ | standard | ✅ FEAT-004, FEAT-012 Phase 3 cards refonte |
| `/tenants/new` | `TenantFormPage` | tenants | ✅ | standard | ✅ FEAT-004 (CREATE form) |
| `/tenants/:id` | `TenantDetailPage` | tenants | ✅ | standard | ✅ FEAT-004, FEAT-015 expose FEAT-014 Phase 2 fields |
| `/tenants/:id/edit` | `TenantEditPage` | tenants | ✅ | standard | ✅ FEAT-004 (UPDATE form, FEAT-014 Phase 2) |
| `/leases` | `LeasesListPage` | leases | ✅ | standard | ✅ FEAT-005, FEAT-012 Phase 1 cards refonte, status badges |
| `/leases/new` | `LeaseFormPage` | leases | ✅ | standard | ✅ FEAT-005 (CREATE form, property/tenant pickers, typed params) |
| `/leases/:id` | `LeaseDetailPage` | leases | ✅ | standard | ✅ FEAT-005, FEAT-015 expose FEAT-014 Phase 3 fields, payments section, receipts timeline |
| `/leases/:id/edit` | `LeaseEditPage` | leases | ✅ | standard | ✅ FEAT-005 (UPDATE form, FEAT-014 Phase 3) |
| `/leases/:id/payments/new` | `PaymentFormPage` | payments | ✅ | standard | ✅ FEAT-006 (CREATE, pre-fills from lease) |
| `/leases/:id/payments/:pid/edit` | `PaymentEditPage` | payments | ✅ | standard | ✅ FEAT-006 (UPDATE, FEAT-014 Phase 4 reference field) |
| `/leases/:id/receipts` | `LeaseReceiptsPage` | receipts | ✅ | standard | ✅ FEAT-007/008, FEAT-012 Phase 4 timeline refonte, void + share buttons |
| `/profile` | `ProfilePage` | profile | ✅ | standard | ✅ FEAT-007 (landlord settings, API test) |

## Logique de redirect

Dans [`lib/core/router/app_router.dart`](../../lib/core/router/app_router.dart) :

- Non-authentifié + route protégée → redirect `/login`
- Authentifié + route auth (`/login`, `/signup`) → redirect `/`
- Route `/privacy` : toujours publique accessible
- **Password recovery guard** : `isInPasswordRecoveryProvider` (session temporaire de reset)
  - Si password recovery actif + location ≠ `/reset-password` → redirect `/reset-password`
  - Empêche navigation avant réinitialisation

**Implémentation** : `GoRouterRefreshStream` (custom, `lib/core/router/go_router_refresh_stream.dart`) écoute `authRepository.authStateChanges` et déclenche re-évaluation des redirects.

## Authentification

- **Type** : Email + Password (Supabase Auth native)
- **Politique** : 8 chars min + 1 lettre + 1 chiffre (Supabase `letters_digits`)
- **Confirmation** : Obligatoire (SMTP FR template)
- **Fournisseur** : Supabase Auth native
- **Provider** : `authRepositoryProvider` (Riverpod, `lib/features/auth/data/auth_repository.dart`)
- **Pivot FEAT-011 (2026-06-22)** : Remplace magic link (FEAT-001) par password classique

## Transitions UI (FEAT-013 Phase 1)

**AppTransition enum** (`lib/core/router/transitions.dart`) :
- `standard` : SlideTransition (slide droite, fade entrée) — pages métier
- `fade` : FadeTransition — auth pages (login/signup/forgot/reset)

Touts les routes utilisent `appPage()` builder avec `AppAppBar` standardisé + AppTransition spécifié.

## AppAppBar (FEAT-013 Phase 1)

Widget `AppAppBar` (`lib/core/ui/app_bar/app_app_bar.dart`) unifié :
- Header : logo "EasyRent" + user menu
- Title : titre page dynamic
- Back button : auto-géré (visible si GoRouter history > 1)
- Actions : contextual (menus, settings, etc.)

Appliqué à toutes les 22 routes (pageBuilder + appPage).

## Navigation principale

**DashboardPage** (FEAT-010 refonde) :
- 4 KPI cards (loyers encaissé/dû, retards, renouvellements, documents)
- Mini-barchart 6 mois (fl_chart v0.69.0)
- Activité récente (top 5 paiements + quittances + documents)
- Onboarding « Premiers pas » (si 0 propriété + 0 locataire + 0 bail)
- Install prompt PWA (visible 1× par semaine)

**LeaseDetailPage** (FEAT-005 + FEAT-006 + FEAT-007 integration) :
- Affiche bail complet (FEAT-014 Phase 3 fields)
- Section paiements (liste + bouton "Ajouter" disabled si fermé)
- Section quittances (timeline FEAT-012 Phase 4, void + share buttons)

**Raccourcis dashboard** : Links vers `/properties`, `/tenants`, `/leases` (shortcut row, TBD drawer)

## Routes non implémentées

- `/documents` — Documents (FEAT-009 route déclarée, UI TBD)
- `/settings` — Settings avancés (post-MVP)
- `/analytics` — Dashboard analytics (post-MVP)

## Widgets de layout

- **AppBar** : `AppAppBar` standardisé (FEAT-013 Phase 1)
- **Drawer** : Navigation principale (TBD)
- **InstallPromptBanner** : PWA install (FEAT-010, visible 1×/semaine)
- **Cards** : EntityCard foundation + Phase-specific (LeaseCard, PropertyCard, TenantCard, ReceiptCard) — FEAT-012 Phases 1–4

## Guards et logique d'accès

- **RLS au niveau DB** : Chaque query respecte `landlord_id = auth.uid()`
- **Client-side** : Aucun check client (RLS est source of truth)
- **Password recovery** : Session temporaire de reset → `isInPasswordRecoveryProvider` guard
