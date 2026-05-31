# Features — registre

> Maintenu par `state-keeper`. **Dernière sync** : 2026-05-31 (FEAT-005 mergée)

## Légende

- ✅ **done** : code mergé, testé, déployé (staging ≥ production)
- 🟢 **ready** : code mergé, en attente de deploy production
- 🚧 **wip** : en cours de développement
- 📋 **planned** : story écrite, pas commencé
- 💡 **idea** : dans le backlog mais pas spec'd

## Features implémentées

| ID | Nom | Statut | Notes |
|---|---|---|---|
| FEAT-001 | Auth propriétaire (signup, login, magic link) | ✅ done | PR#1, merge 8d91219, staging validée 2026-05-27 |
| FEAT-002 | Modèle de données + RLS exhaustive (properties, tenants, leases) | ✅ done | PR#2, merge 6b28bbb, backend pur (aucun changement Flutter), 77 RLS tests |
| FEAT-003 | CRUD UI propriétés (list, detail, form) | ✅ done | PR#3, merge c1b0571, 16 fichiers Dart, 4 routes GoRouter, 56 tests |
| FEAT-004 | CRUD UI locataires (list, detail, form) | ✅ done | Commit 911ca5c, 15 fichiers Dart, 4 routes GoRouter, 80+ tests |
| FEAT-005 | CRUD UI baux (list, detail, form) + hardening | ✅ done | PR#5, merge a795686, refine 129e398, 18 fichiers Dart, 4 routes GoRouter, money parser hardening, lease date bounds |
| (bootstrap) | Projet Flutter Web + Riverpod + go_router + Supabase init | ✅ done | Squelette + infra multi-env |

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

**Validation** : Staging déployée — bout-en-bout OK (signup → magic link → session → RLS isolation)

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

**Tests RLS** : 77 tests (rls_landlords.sql, rls_properties.sql, rls_tenants.sql, rls_leases.sql)

**Code Flutter** : Aucun changement (backend pur)

**Validation** : Migration appliquée en réel sur Supabase 2026-05-28 12:00 UTC.

---

### FEAT-003 : CRUD UI propriétés (list, detail, form)

**Status** : ✅ DONE (mergé develop 2026-05-28, PR#3, commit c1b0571)

**Source** : `docs/backlog/003-crud-properties.md`

**Code structure** :
- `lib/features/properties/domain/` : `property.dart` (freezed model), `property_type.dart` (enum), `property_form_state.dart`
- `lib/features/properties/data/` : `property_repository.dart` (Supabase Postgrest wrapper, CRUD via RLS)
- `lib/features/properties/application/` : `properties_list_provider.dart`, `property_detail_provider.dart`, `property_form_controller.dart`
- `lib/features/properties/presentation/` : `properties_list_page.dart`, `property_detail_page.dart`, `property_form_page.dart`, `widgets/`

**Routes** (4 nouvelles) :
- `/properties` : PropertiesListPage
- `/properties/new` : PropertyFormPage (mode CREATE)
- `/properties/:id` : PropertyDetailPage (mode READ + DELETE)
- `/properties/:id/edit` : PropertyEditPage (mode UPDATE)

**Helpers réutilisables** :
- `lib/core/utils/postgrest_error_mapper.dart` : Mappe erreurs Postgrest → messages UI localisés
- `lib/core/utils/surface_validator.dart` : Valide `surface_m2 > 0`
- `lib/core/utils/property_form_validators.dart` : Valide nom, adresse, type

**Tests** : 56 tests (unit + widget + integration)

**RLS passthrough** : Ownership délégué à Supabase RLS.

---

### FEAT-004 : CRUD UI locataires (list, detail, form)

**Status** : 🟢 READY (commit 911ca5c, branche feature/crud-tenants)

**Source** : `docs/backlog/004-crud-tenants.md`

**Code structure** :
- `lib/features/tenants/domain/` : `tenant.dart` (freezed model), `tenant_form_state.dart`
- `lib/features/tenants/data/` : `tenant_repository.dart` (Supabase Postgrest wrapper, CRUD via RLS)
- `lib/features/tenants/application/` : `tenants_list_provider.dart`, `tenant_detail_provider.dart`, `tenant_form_controller.dart`
- `lib/features/tenants/presentation/` : `tenants_list_page.dart`, `tenant_detail_page.dart`, `tenant_form_page.dart`, `widgets/` (tenant_card, tenant_form, tenant_lease_summary)

**Routes** (4 nouvelles) :
- `/tenants` : TenantsListPage
- `/tenants/new` : TenantFormPage (mode CREATE)
- `/tenants/:id` : TenantDetailPage (mode READ + DELETE + lease summary)
- `/tenants/:id/edit` : TenantEditPage (mode UPDATE)

**Helpers** :
- `lib/core/utils/tenant_form_validators.dart` : Valide prénom, nom, email, téléphone
- `lib/core/widgets/archive_confirm_dialog.dart` : Widget réutilisable soft-delete (déplacé de properties → core)

**Widget spécialisé** :
- `TenantLeaseSummary` : Affiche les baux actifs du locataire (prépare FEAT-005)

**Tests** : 80+ tests (unit + widget)

**RLS passthrough** : Ownership délégué à Supabase RLS.

---

### FEAT-005 : CRUD UI baux (list, detail, form) + hardening

**Status** : ✅ DONE (commit a795686, refinement 129e398, branche fix/lease-input-hardening)

**Source** : `docs/backlog/005-crud-leases.md`

**Code structure** :
- `lib/features/leases/domain/` : `lease.dart` (freezed model), `lease_status.dart` (enum), `lease_form_state.dart`, `lease_list_item.dart`
- `lib/features/leases/data/` : `lease_repository.dart` (Supabase Postgrest wrapper, CRUD via RLS)
- `lib/features/leases/application/` : `leases_list_provider.dart`, `lease_detail_provider.dart`, `lease_form_controller.dart`
- `lib/features/leases/presentation/` : `leases_list_page.dart`, `lease_detail_page.dart`, `lease_form_page.dart`, `widgets/` (lease_card, lease_form, close_lease_dialog, active_lease_warning_dialog)

**Routes** (4 nouvelles) :
- `/leases` : LeasesListPage
- `/leases/new` : LeaseFormPage (mode CREATE)
- `/leases/:id` : LeaseDetailPage (mode READ + DELETE)
- `/leases/:id/edit` : LeaseEditPage (mode UPDATE)

**Helpers** :
- `lib/core/utils/lease_form_validators.dart` : Valide loyer, charges, dates (start < end, borne 1900-2100)

**Hardening audit (fix/lease-input-hardening)** :
- Money parser : Validation stricte montants (cents uniquement, max 999,999.99€)
- Extract constant : `_kMaxAmountCents = 99999999` (10M€ max par bail)
- DB constraint : `leases_date_range_check` ajoute borne `1900-01-01` à `2100-12-31` (migration 20260529120000)

**Modèle Lease** :
- Freezed + json_serializable avec `@JsonKey` pour snake_case
- Montants en centimes (int, pas float)
- Dates : DateTime côté Dart, `date` (YYYY-MM-DD) côté Postgres
- Status enum : active, terminated, archived

**Tests** : 1 test (lease repository) — intégration avec RLS

**RLS passthrough** : Ownership délégué à Supabase RLS + cohérence cross-FK validée par trigger `assert_lease_ownership_consistency()`.

---

### Bootstrap projet (non-feature)

**Status** : ✅ done (infrastructure en place)

**Routes** : `/`, `/login`, `/privacy` + 4 × properties (FEAT-003) + 4 × tenants (FEAT-004) + 4 × leases (FEAT-005)

**État** : Infrastructure multi-env stable, CI/CD fonctionnel, 4 features complètes

---

## Backlog (prochaines features)

| ID | Nom | Priorité | Effort | Backlog | Notes |
|---|---|---|---|---|---|
| FEAT-006 | Générer quittance PDF conforme loi 1989 | P0 | M | (à créer) | Utilise `pdf` + `printing` packages |
| FEAT-007 | Envoyer quittance par email (Edge Function + Resend) | P0 | M | (à créer) | Crée `supabase/functions/send-receipt` (Deno) |
| FEAT-008 | Upload + stockage documents | P0 | M | (à créer) | Supabase Storage (RLS files) |
| FEAT-009 | Dashboard récap (actif, loyers, charges) | P0 | S | (à créer) | Agrégation, charts |
| FEAT-010 | Polish PWA (offline shell, install prompt) | P0 | S | (à créer) | Service worker, manifest |

**Location** : `docs/backlog/*.md` — user stories détaillées + acceptance criteria
