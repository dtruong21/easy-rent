# Features — registre

> Maintenu par `state-keeper`. **Dernière sync** : 2026-05-28

## Légende

- ✅ **done** : code mergé, testé, déployé (staging ≥ production)
- 🟢 **ready** : code mergé, en attente de deploy production
- 🚧 **wip** : en cours de développement
- 📋 **planned** : story écrite, pas commencé
- 💡 **idea** : dans le backlog mais pas spec'd

## Features implémentées

| ID | Nom | Statut | Notes |
|---|---|---|---|
| FEAT-001 | Auth propriétaire (signup, login, magic link) | ✅ done | Mergé PR#1, staging validée, tests RLS |
| (bootstrap) | Projet Flutter Web + Riverpod + go_router + Supabase init | 🟢 ready | Squelette + infra multi-env |

## Détails

### FEAT-001 : Auth propriétaire (magic link)

**Status** : ✅ DONE (mergé develop, staging déployée 2026-05-27)

**Source** : `docs/backlog/001-auth-magic-link.md`

**Code structure** :
- `lib/features/auth/domain/` : `login_form_state.dart` (freezed model)
- `lib/features/auth/data/` : `auth_repository.dart` (SupabaseAuth wrapper)
- `lib/features/auth/application/` : `auth_controller.dart`, `auth_session_provider.dart` (providers Riverpod)
- `lib/features/auth/presentation/` : `login_page.dart`, `widgets/login_form.dart`, `widgets/magic_link_sent_view.dart`

**Routes** :
- `/login` : Login form (email input, magic link send)
- Redirect logic : Auto-redirect `/login` → `/` si authentifié

**Database** :
- Table `landlords` (public + dev) : PK = `auth.users.id`, colonnes (email, created_at, updated_at, deleted_at)
- Trigger `handle_new_user()` : Auto-provisioning à chaque signup
- RLS policies : SELECT/UPDATE sur sa propre ligne uniquement

**Tests** :
- `test/unit/auth_*` : Logic tests
- `test/widget/login_form_test.dart` : Widget tests
- `test/widget/router_guard_test.dart` : Navigation guard tests
- `supabase/tests/rls_landlords.sql` : RLS cross-user validation

**Validation** : Staging déployée (Firebase Hosting + Supabase dev schema) — bout-en-bout OK (signup → magic link → session → RLS isolation)

### Bootstrap projet (non-feature)

**Status** : 🟢 ready (infrastructure en place, prêt pour FEAT-002)

**Fichiers** : `lib/main.dart`, `lib/core/`, `lib/features/`

**Routes** : `/`, `/login`, `/privacy`

**Tables Supabase** : `landlords` (FEAT-001), resto en backlog

**Widgets** : 
- `LoginPage` : magic link form (FEAT-001)
- `DashboardPage` : stub (à implémenter FEAT-002)
- `PrivacyPage` : placeholder RGPD (public route)

**État** : Infrastructure multi-env stable, CI/CD (GitHub Actions) fonctionnel, staging validée

## Backlog (prochaines features)

| ID | Nom | Priorité | Effort | Backlog |
|---|---|---|---|---|
| FEAT-002 | CRUD biens immobiliers | P0 | M | `002-data-model-rls.md` |
| FEAT-003 | CRUD locataires | P0 | M | `003-crud-properties.md` |
| FEAT-004 | CRUD baux | P0 | M | `004-crud-tenants.md` |
| FEAT-005 | Enregistrer paiement loyer | P0 | S | `005-crud-leases.md` |
| FEAT-006 | Générer quittance PDF conforme | P0 | M | (à créer) |
| FEAT-007 | Envoyer quittance par email (Edge Function + Resend) | P0 | M | (à créer) |
| FEAT-008 | Upload + stockage documents | P0 | M | (à créer) |
| FEAT-009 | Dashboard récap | P0 | S | (à créer) |
| FEAT-010 | Polish PWA (offline shell, install prompt) | P0 | S | (à créer) |

**Location** : `docs/backlog/*.md` — user stories détaillées + acceptance criteria

**Assigné** : `product-owner` et `feature-scout` agents pour triage / clarification
