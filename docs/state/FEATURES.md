# Features — registre

> Maintenu par `state-keeper`. **Dernière sync** : 2026-05-31 (FEAT-006 mergée, commit 2a18458)

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
| FEAT-004 | CRUD UI locataires (list, detail, form) | ✅ done | PR#4, merge 911ca5c, 15 fichiers Dart, 4 routes GoRouter, 80+ tests |
| FEAT-005 | CRUD UI baux (list, detail, form) | ✅ done | PR#5, merge a795686, 18 fichiers Dart, 4 routes GoRouter, date hardening, 90+ tests |
| FEAT-006 | CRUD paiements de loyer (enregistrement + archive) | 🟢 ready | PR#8, merge 2a18458, 15 fichiers Dart, 2 routes GoRouter, 31 RLS tests + 50 unit/widget tests |
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

**Status** : ✅ DONE (mergé develop 2026-05-29, PR#4, commit 911ca5c)

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

### FEAT-005 : CRUD UI baux (list, detail, form)

**Status** : ✅ DONE (mergé develop 2026-05-29, PR#5, commit a795686)

**Source** : `docs/backlog/005-crud-leases.md`

**Migration** : `supabase/migrations/20260529120000_lease_date_bounds.sql` (date hardening, bornes 1900–2100)

**Code structure** :
- `lib/features/leases/domain/` : `lease.dart` (freezed model), `lease_status.dart` (enum: active, terminated, archived), `lease_form_state.dart`
- `lib/features/leases/data/` : `lease_repository.dart` (Supabase Postgrest wrapper, CRUD via RLS)
- `lib/features/leases/application/` : `leases_list_provider.dart`, `lease_detail_provider.dart`, `lease_form_controller.dart`
- `lib/features/leases/presentation/` : `leases_list_page.dart`, `lease_detail_page.dart`, `lease_form_page.dart`, `lease_edit_page.dart`, `widgets/`

**Routes** (4 nouvelles) :
- `/leases` : LeasesListPage
- `/leases/new` : LeaseFormPage (mode CREATE)
- `/leases/:id` : LeaseDetailPage (mode READ, prépare FEAT-006 paiements + FEAT-007 quittances)
- `/leases/:id/edit` : LeaseEditPage (mode UPDATE)

**Helpers réutilisables** :
- `lib/core/utils/lease_form_validators.dart` : Valide dates (start < end), montants, bornes 1900–2100
- `lib/core/utils/date_helpers.dart` : Helpers date Postgres ↔ Dart

**Widget spécialisé** :
- `LeaseDetailPage` : Affiche le détail du bail, boutons "Ajouter paiement" et affichage quittances (préparés pour FEAT-006/007)
- Placeholder `_PaymentsPlaceholder` : sera remplacé par `PaymentListSection` en FEAT-006

**Tests** : 90+ tests (unit + widget), incluant date boundary validation

**RLS passthrough** : Ownership délégué à Supabase RLS.

**Décisions hardening** :
- Date bounds : 1900-01-01 à 2100-12-31 (CHECK SQL + validation Dart)
- Bornes intégrées dès la création (FEAT-005 audit débloque FEAT-006)

---

### FEAT-006 : CRUD paiements de loyer

**Status** : 🟢 READY (commit 2a18458, PR#8, branche develop)

**Source** : `docs/backlog/006-payment-record.md` et `docs/plans/FEAT-006-payment-record.md`

**Migration** : `supabase/migrations/20260531102202_feat006_payments.sql` (890 lignes)

**Code structure** :
- `lib/features/payments/domain/` : `payment.dart` (freezed model + PaymentExtension), `payment_method.dart` (enum: virement, cheque, especes, prelevement, autre), `payment_form_state.dart` (sealed union)
- `lib/features/payments/data/` : `payment_repository.dart` (Supabase Postgrest wrapper, listForLease/getById/create/update/archive via RPC)
- `lib/features/payments/application/` : `lease_payments_provider.dart` (AsyncNotifierProvider.family by leaseId), `payment_detail_provider.dart` (FutureProvider.family), `payment_form_controller.dart` (StateNotifier)
- `lib/features/payments/presentation/` : `payment_form_page.dart`, `payment_edit_page.dart`, `widgets/payment_form.dart`, `widgets/payment_list_section.dart`, `widgets/payment_list_tile.dart`, `widgets/payment_amount_warning.dart`

**Routes** (2 nouvelles) :
- `/leases/:id/payments/new` : PaymentFormPage (mode CREATE, pré-remplit depuis lease)
- `/leases/:id/payments/:pid/edit` : PaymentEditPage (mode UPDATE)

**Database** :
- Table `public.payments` et `dev.payments` : 13 colonnes (id, lease_id, landlord_id, period_start, period_end, paid_at, rent_amount_cents, charges_amount_cents, payment_method, notes, created_at, updated_at, deleted_at)
- 4 index : landlord_id (RLS), lease_id (listage), period_start DESC (tri), active partial (deleted_at IS NULL)
- 3 policies RLS : SELECT/INSERT/UPDATE, pas de DELETE (soft-delete via RPC uniquement)
- Trigger tr_00 : `assert_payment_lease_ownership()` SECURITY DEFINER, cross-FK (lease_id → landlord_id)
- Trigger tr_01 / tr_02 : réutilisées (prevent_protected_columns_change, set_updated_at)
- RPC `soft_delete_payment()` SECURITY DEFINER : GRANT authenticated, REVOKE PUBLIC

**Modèle `Payment`** :
- Freezed + json_serializable
- Montants en centimes (integer), jamais double (ex: 85000 = 850,00€)
- Dates en `date` Postgres (YYYY-MM-DD) convertis via helpers JSON
- PaymentMethod enum (fromSql / sqlValue / label pour pivot SQL/Dart)
- Extension PaymentExtension : getter `totalAmountCents`

**Helpers** :
- `lib/core/utils/payment_form_validators.dart` : Valide period_start < period_end, montants > 0, méthode, notes max 500 chars
- Date conversion JSON : _dateFromJson / _dateToJson

**Widgets** :
- `PaymentForm` : Formulaire création/édition, pré-remplit depuis lease (rent_amount_cents + charges_amount_cents), warning banner si montant ≠ loyer+charges
- `PaymentListSection` : Liste paiements actifs du bail (remplace _PaymentsPlaceholder de FEAT-005), bouton "Ajouter paiement" (disabled si lease fermé)
- `PaymentListTile` : Ligne paiement avec actions (edit, archive)
- `PaymentAmountWarning` : Banner non-bloquant si montant hors normes

**Tests** :
- RLS : 31 tests dans `supabase/tests/rls_payments.sql` (SELECT/INSERT/UPDATE ownership validation)
- Unit : `payment_test.dart`, `payment_method_test.dart`, `payment_form_validators_test.dart`, `payment_repository_test.dart`
- Widget : `payment_form_test.dart`, `payment_list_section_test.dart`
- LeaseDetailPage test enrichi (PaymentListSection embedding)

**Décisions produit** (tranchées + documentées) :
1. **Paiements partiels libres** : Pas de vérification "montant ≤ loyer+charges". Warning UI seulement (non-bloquant).
2. **Doublons autorisés** : Pas de UNIQUE sur (lease_id, period_start, period_end). Cas légitimes : régularisation après audit.
3. **paid_at futur OK** : Autorisée (prélèvements programmés).
4. **Paiement sur bail fermé autorisé au DB** : Cas légitimes : régularisation, dernière mensualité après clôture. Bouton UI désactivé seulement.
5. **Soft-delete uniquement** : Pas de hard-delete. RPC `soft_delete_payment()` pour compliance RGPD.

**RLS exhaustive** :
- SELECT : `landlord_id = auth.uid() AND deleted_at IS NULL`
- INSERT : `landlord_id = auth.uid()` (trigger tr_00 valide lease_id → landlord_id)
- UPDATE : USING `landlord_id = auth.uid() AND deleted_at IS NULL` / WITH CHECK `landlord_id = auth.uid()`
- DELETE : aucune policy (soft-delete via RPC)

**Validation** : Tests RLS passent (31/31), unit/widget tests passent. Prêt pour deploy.

---

### Bootstrap projet (non-feature)

**Status** : 🟢 ready (infrastructure en place)

**Routes** : `/`, `/login`, `/privacy` + 4 × properties (FEAT-003) + 4 × tenants (FEAT-004) + 4 × leases (FEAT-005) + 2 × payments (FEAT-006)

**État** : Infrastructure multi-env stable, CI/CD fonctionnel

---

## Backlog (prochaines features)

| ID | Nom | Priorité | Effort | Backlog | Notes |
|---|---|---|---|---|---|
| FEAT-007 | Générer quittance PDF conforme loi 1989 | P0 | M | `docs/backlog/007-receipt-pdf.md` | Utilise `pdf` + `printing` packages, lira payments.rent/charges_cents |
| FEAT-008 | Envoyer quittance par email (Edge Function + Resend) | P0 | M | `docs/backlog/008-send-receipt-email.md` | Crée `supabase/functions/send-receipt` (Deno), RPC trigger |
| FEAT-009 | Upload + stockage documents | P0 | M | `docs/backlog/009-document-storage.md` | Supabase Storage (RLS files), table documents |
| FEAT-010 | Dashboard récap (actif, loyers, charges) | P0 | M | `docs/backlog/010-dashboard-analytics.md` | Agrégation SQL, charts, graphiques |
| FEAT-011 | Polish PWA (offline shell, install prompt) | P1 | S | (à créer) | Service worker, manifest, offline cache |
| FEAT-012 | Prod release (secrets, logs, monitoring) | P1 | M | (à créer) | Hosting prod, secrets, alertes |

**Location** : `docs/backlog/*.md` — user stories détaillées + acceptance criteria
