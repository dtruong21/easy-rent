# Features — registre

> Maintenu par `state-keeper`. **Dernière sync** : 2026-05-28 (FEAT-002 mergée)

## Légende

- ✅ **done** : code mergé, testé, déployé (staging ≥ production)
- 🟢 **ready** : code mergé, en attente de deploy production
- 🚧 **wip** : en cours de développement
- 📋 **planned** : story écrite, pas commencé
- 💡 **idea** : dans le backlog mais pas spec'd

## Features implémentées

| ID | Nom | Statut | Notes |
|---|---|---|---|
| FEAT-001 | Auth propriétaire (signup, login, magic link) | ✅ done | PR#1, merge 05d59ce, staging validée 2026-05-27 |
| FEAT-002 | Modèle de données + RLS exhaustive (properties, tenants, leases) | ✅ done | PR#2, merge 9db2741, backend pur (aucun changement Flutter), 77 RLS tests |
| (bootstrap) | Projet Flutter Web + Riverpod + go_router + Supabase init | 🟢 ready | Squelette + infra multi-env |

## Détails

### FEAT-001 : Auth propriétaire (magic link)

**Status** : ✅ DONE (mergé develop 2026-05-26, staging déployée 2026-05-27)

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

---

### FEAT-002 : Modèle de données + RLS (properties, tenants, leases)

**Status** : ✅ DONE (mergé develop 2026-05-28, backend appliqué 2026-05-28 12:00 UTC)

**Source** : `docs/backlog/002-data-model-rls.md`

**Migration** : `supabase/migrations/20260528120000_feat002_data_model.sql` (757 lignes)

**Tables créées** :
- `public.properties` / `dev.properties` — Biens immobiliers (FK → landlords)
- `public.tenants` / `dev.tenants` — Locataires (FK → landlords)
- `public.leases` / `dev.leases` — Baux (FK → landlords, properties, tenants)

**Colonnes ajoutées à `landlords`** : `full_name`, `phone`, `address` (optionnels)

**Changement FK** : `landlords.id → auth.users(id)` : CASCADE → NO ACTION (rétention légale 5 ans)

**RLS** :
- 24 policies (4 tables × 2 schémas × 3 opérations SELECT/INSERT/UPDATE)
- Aucune policy DELETE (soft-delete via RPC)
- Ownership check : `landlord_id = auth.uid() AND deleted_at IS NULL`

**Soft-delete** :
- Trigger `prevent_protected_columns_change()` bloque modification de `deleted_at`, `created_at` sauf flag `app.allow_deleted_at_change = '1'`
- 4 RPC SECURITY DEFINER × 2 schémas : `soft_delete_landlord()`, `soft_delete_property()`, `soft_delete_tenant()`, `soft_delete_lease()`

**Cohérence cross-FK** :
- Trigger `assert_lease_ownership_consistency()` SECURITY DEFINER valide que property_id et tenant_id appartiennent au même landlord_id

**Triggers** :
- tr_00 : `assert_lease_ownership` (leases uniquement)
- tr_01 : `prevent_protected_columns_change_*` (4 tables)
- tr_02 : `set_updated_at_*` (4 tables)

**Tests RLS** :
- `supabase/tests/rls_landlords.sql` : Extended (soft-delete behavior)
- `supabase/tests/rls_properties.sql` : 20 tests
- `supabase/tests/rls_tenants.sql` : 20 tests
- `supabase/tests/rls_leases.sql` : 20+ tests (cross-FK validation)
- **Total** : 77 tests RLS

**Code Flutter** : Aucun changement (backend pur)

**Validation** : Migration appliquée en réel sur Supabase 2026-05-28 12:00 UTC. Staging sera mise à jour à la prochaine CI run (redeploy).

---

### Bootstrap projet (non-feature)

**Status** : 🟢 ready (infrastructure en place)

**Fichiers** : `lib/main.dart`, `lib/core/`, `lib/features/`

**Routes** : `/`, `/login`, `/privacy`

**État** : Infrastructure multi-env stable, CI/CD fonctionnel

---

## Backlog (prochaines features)

| ID | Nom | Priorité | Effort | Backlog |
|---|---|---|---|---|
| FEAT-003 | CRUD UI propriétés (list, detail, form) | P0 | M | `docs/backlog/003-crud-properties.md` |
| FEAT-004 | CRUD UI locataires | P0 | M | `docs/backlog/004-crud-tenants.md` |
| FEAT-005 | CRUD UI baux | P0 | M | `docs/backlog/005-crud-leases.md` |
| FEAT-006 | Générer quittance PDF conforme loi 1989 | P0 | M | (à créer) |
| FEAT-007 | Envoyer quittance par email (Edge Function + Resend) | P0 | M | (à créer) |
| FEAT-008 | Upload + stockage documents | P0 | M | (à créer) |
| FEAT-009 | Dashboard récap (actif, loyers, charges) | P0 | S | (à créer) |
| FEAT-010 | Polish PWA (offline shell, install prompt) | P0 | S | (à créer) |

**Location** : `docs/backlog/*.md` — user stories détaillées + acceptance criteria

**Assigné** : `product-owner` et `feature-scout` agents pour triage / clarification
