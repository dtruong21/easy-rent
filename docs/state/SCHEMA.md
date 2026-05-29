# Schéma Postgres — snapshot

> Maintenu par `state-keeper`. **Source** : `supabase/migrations/`. **Dernière sync** : 2026-05-29 (FEAT-004 mergée, aucun changement SQL — frontend only)

## Tables

### `landlords` (public + dev)

**Migration source** : `20260527081533_feat001_landlords_auth.sql` (création), `20260528120000_feat002_data_model.sql` (extension)

| Colonne | Type | Contraintes |
|---|---|---|
| `id` | `uuid` | PRIMARY KEY, FK → `auth.users(id)` ON DELETE NO ACTION |
| `email` | `text` | NOT NULL |
| `full_name` | `text` | NULL — rempli dans les paramètres (FEAT-003+) |
| `phone` | `text` | NULL |
| `address` | `text` | NULL |
| `created_at` | `timestamptz` | NOT NULL DEFAULT now() |
| `updated_at` | `timestamptz` | NOT NULL DEFAULT now() (trigger `tr_02_set_updated_at_landlords`) |
| `deleted_at` | `timestamptz` | NULL — soft-delete. Modifiable uniquement via `soft_delete_landlord()` RPC |

**Index** : `idx_public_landlords_email` (public + dev)

**RLS** : activée

**Policies** (public + dev) :

| Policy | Opération | Condition |
|---|---|---|
| `landlord_selects_self` | SELECT | `id = auth.uid() AND deleted_at IS NULL` |
| `landlord_updates_self` | UPDATE | USING: `id = auth.uid() AND deleted_at IS NULL` / WITH CHECK: `id = auth.uid()` |

**Client constraints** :
- INSERT : **interdit** (aucune policy INSERT → trigger `handle_new_user()` insère auto)
- DELETE : **interdit** (soft-delete via RPC `soft_delete_landlord()`)

---

### `properties` (public + dev)

**Migration source** : `20260528120000_feat002_data_model.sql`

| Colonne | Type | Contraintes |
|---|---|---|
| `id` | `uuid` | PRIMARY KEY, DEFAULT gen_random_uuid() |
| `landlord_id` | `uuid` | FK → `landlords(id)` ON DELETE RESTRICT |
| `name` | `text` | NOT NULL, CHECK length > 0 |
| `address` | `text` | NOT NULL, CHECK length > 0 |
| `type` | `text` | NOT NULL, CHECK IN ('appartement', 'maison', 'studio', 'autre') |
| `surface_m2` | `numeric(6,2)` | NULL, CHECK > 0 (si renseigné) |
| `created_at` | `timestamptz` | NOT NULL DEFAULT now() |
| `updated_at` | `timestamptz` | NOT NULL DEFAULT now() |
| `deleted_at` | `timestamptz` | NULL — soft-delete via RPC `soft_delete_property()` |

**Index** : `idx_public_properties_landlord_id`, `idx_dev_properties_landlord_id`

**RLS** : activée

**Policies** (public + dev) :

| Policy | Opération | Condition |
|---|---|---|
| `properties_select_own` | SELECT | `landlord_id = auth.uid() AND deleted_at IS NULL` |
| `properties_insert_own` | INSERT | WITH CHECK: `landlord_id = auth.uid()` |
| `properties_update_own` | UPDATE | USING: `landlord_id = auth.uid() AND deleted_at IS NULL` / WITH CHECK: `landlord_id = auth.uid()` |

---

### `tenants` (public + dev)

**Migration source** : `20260528120000_feat002_data_model.sql`

| Colonne | Type | Contraintes |
|---|---|---|
| `id` | `uuid` | PRIMARY KEY, DEFAULT gen_random_uuid() |
| `landlord_id` | `uuid` | FK → `landlords(id)` ON DELETE RESTRICT |
| `first_name` | `text` | NOT NULL, CHECK length > 0 |
| `last_name` | `text` | NOT NULL, CHECK length > 0 |
| `email` | `text` | NOT NULL, CHECK regex `^[^@\s]+@[^@\s]+\.[^@\s]+$` |
| `phone` | `text` | NULL |
| `created_at` | `timestamptz` | NOT NULL DEFAULT now() |
| `updated_at` | `timestamptz` | NOT NULL DEFAULT now() |
| `deleted_at` | `timestamptz` | NULL — soft-delete via RPC `soft_delete_tenant()` |

**Index** : `idx_public_tenants_landlord_id`, `idx_dev_tenants_landlord_id`

**RLS** : activée

**Policies** (public + dev) :

| Policy | Opération | Condition |
|---|---|---|
| `tenants_select_own` | SELECT | `landlord_id = auth.uid() AND deleted_at IS NULL` |
| `tenants_insert_own` | INSERT | WITH CHECK: `landlord_id = auth.uid()` |
| `tenants_update_own` | UPDATE | USING: `landlord_id = auth.uid() AND deleted_at IS NULL` / WITH CHECK: `landlord_id = auth.uid()` |

---

### `leases` (public + dev)

**Migration source** : `20260528120000_feat002_data_model.sql`

| Colonne | Type | Contraintes |
|---|---|---|
| `id` | `uuid` | PRIMARY KEY, DEFAULT gen_random_uuid() |
| `landlord_id` | `uuid` | FK → `landlords(id)` ON DELETE RESTRICT (dénormalisé pour RLS) |
| `property_id` | `uuid` | FK → `properties(id)` ON DELETE RESTRICT |
| `tenant_id` | `uuid` | FK → `tenants(id)` ON DELETE RESTRICT |
| `rent_amount_cents` | `integer` | NOT NULL, CHECK > 0 (en centimes, ex: 85000 = 850,00€) |
| `charges_amount_cents` | `integer` | NOT NULL DEFAULT 0, CHECK >= 0 |
| `start_date` | `date` | NOT NULL |
| `end_date` | `date` | NULL (= CDI), CHECK end_date > start_date (si renseigné) |
| `status` | `text` | NOT NULL DEFAULT 'active', CHECK IN ('active', 'terminated', 'archived') |
| `created_at` | `timestamptz` | NOT NULL DEFAULT now() |
| `updated_at` | `timestamptz` | NOT NULL DEFAULT now() |
| `deleted_at` | `timestamptz` | NULL — soft-delete via RPC `soft_delete_lease()` |

**Index** : `idx_public_leases_landlord_id`, `idx_public_leases_property_id`, `idx_public_leases_tenant_id`, `idx_public_leases_status_active_partial` (WHERE status='active' AND deleted_at IS NULL) + équivalents dev

**RLS** : activée

**Policies** (public + dev) :

| Policy | Opération | Condition |
|---|---|---|
| `leases_select_own` | SELECT | `landlord_id = auth.uid() AND deleted_at IS NULL` |
| `leases_insert_own` | INSERT | WITH CHECK: `landlord_id = auth.uid()` |
| `leases_update_own` | UPDATE | USING: `landlord_id = auth.uid() AND deleted_at IS NULL` / WITH CHECK: `landlord_id = auth.uid()` |

---

## Triggers et fonctions Postgres

### Fonctions helper (debug, init)

**`dev.check_schema_parity()`** — Compares tables between `public` et `dev` schémas. FEAT-001.

**`dev.assert_rls_both_schemas(table_name text)`** — Assert RLS activée sur table dans les deux schémas. FEAT-002.

---

### Fonctions de sécurité

**`public.prevent_protected_columns_change()`** — Trigger BEFORE INSERT OR UPDATE (réutilisable, 4 tables × 2 schémas)

- **À l'INSERT** :
  - Bloque `deleted_at` ≠ NULL sauf flag `app.allow_deleted_at_change = '1'` (réservé aux RPC)
  - Force `created_at := now()` et `updated_at := now()` (pragmatique — corrige les antidates silencieusement)
- **À l'UPDATE** :
  - Bloque modification de `deleted_at` sauf flag (ERRCODE 42501)
  - Bloque modification de `created_at` (immuable, ERRCODE 42501)
  - Force `updated_at := OLD.updated_at` (repris par tr_02)

**`public.assert_lease_ownership_consistency()`** — Trigger BEFORE INSERT OR UPDATE sur `public.leases`, SECURITY DEFINER, SET search_path = public

- Valide que `property_id` existe
- Valide que `tenant_id` existe
- Valide que `property_id.landlord_id` = `NEW.landlord_id`
- Valide que `tenant_id.landlord_id` = `NEW.landlord_id`
- ERRCODE 23514 (check_violation)
- Bypass RLS intentionnellement pour voir toutes les lignes (cohérence cross-FK)

**`dev.assert_lease_ownership_consistency()`** — Mirror DEV (SET search_path = dev, lit dev.properties et dev.tenants)

---

### Fonctions d'auto-provisioning et maintenance

**`public.handle_new_user()`** — Trigger AFTER INSERT ON `auth.users`, SECURITY DEFINER, SET search_path = public

- Insère une ligne dans `public.landlords` ET `dev.landlords` à chaque signup
- Idempotent (ON CONFLICT DO NOTHING)
- FEAT-001

**`public.set_updated_at()`** — Trigger BEFORE UPDATE, maintient `updated_at = now()`

- Attaché à `public.landlords` (tr_02), `public.properties` (tr_02), `public.tenants` (tr_02), `public.leases` (tr_02) + équivalents dev
- FEAT-001 (créée FEAT-002 a renommé le trigger sur landlords pour respect de l'ordre alphabétique tr_01 < tr_02)

---

### RPC SECURITY DEFINER — soft-delete

Chacune pose `SET LOCAL app.allow_deleted_at_change = '1'` (scope transaction) pour contourner le trigger `tr_01`. Ownership check (`landlord_id = auth.uid()`) dans le WHERE. Aucune policy DELETE sur aucune table.

**`public.soft_delete_landlord()`** — Soft-delete du landlord courant (auth.uid()). FEAT-002.

**`public.soft_delete_property(p_id uuid)`** — Soft-delete property (vérifie ownership). FEAT-002.

**`public.soft_delete_tenant(p_id uuid)`** — Soft-delete tenant (vérifie ownership). FEAT-002.

**`public.soft_delete_lease(p_id uuid)`** — Soft-delete lease (vérifie ownership). FEAT-002.

**Versions dev** : `dev.soft_delete_landlord()`, `dev.soft_delete_property()`, `dev.soft_delete_tenant()`, `dev.soft_delete_lease()` — mêmes signatures, opèrent sur schéma `dev`.

---

## Triggers ordre d'exécution

PG exécute BEFORE INSERT OR UPDATE dans l'ordre alphabétique du nom. Ordre garanti :

1. **`tr_00_assert_lease_ownership`** (leases uniquement) — Validation cross-FK
2. **`tr_01_prevent_protected_columns_change_*`** (toutes les 4 tables) — Bloque deleted_at, created_at ; force updated_at
3. **`tr_02_set_updated_at_*`** (toutes les 4 tables sauf si DELETE) — Remet à jour updated_at

---

## Schémas

### `public` (PROD)

- Status : Initialized by Supabase (default)
- RLS : enabled per table
- Roles : `authenticated`, `anon`, `service_role`

### `dev` (DEV)

- Status : créé via migration init
- RLS : enabled per table
- Roles : `authenticated`, `anon`, `service_role`
- Default privileges : `SELECT, INSERT, UPDATE, DELETE` sur tables pour `authenticated`
- Comment : "Development/staging mirror of public schema. Mapped to Git branch `develop`."

---

## Résumé des changements FEAT-002

**Nouvelles tables** : `properties`, `tenants`, `leases` (public + dev)

**Colonnes ajoutées à `landlords`** : `full_name`, `phone`, `address`

**FK change** : `landlords.id → auth.users(id)` : CASCADE → NO ACTION (rétention 5 ans RGPD)

**Soft-delete** : Implémentation exhaustive (24 policies RLS pour les 4 tables × 2 schémas × SELECT/INSERT/UPDATE, aucune DELETE)

**Trigger framework** : Pattern tr_00/tr_01/tr_02 pour ordre d'exécution alphabétique stable

**RPC framework** : 4 RPC × 2 schémas pour soft-delete (+ versions dev)

**Protection colonne** : Trigger `prevent_protected_columns_change()` bloque modification de `deleted_at`, `created_at` sauf flag de session `app.allow_deleted_at_change = '1'`

**Cohérence cross-FK** : Trigger `assert_lease_ownership_consistency()` SECURITY DEFINER valide la triade (property, tenant, lease) appartient au même landlord

---

## Notes

- **Multi-env strategy** : Same database hosts `public` (PROD) et `dev` (DEV) sur Supabase free tier
- **Migration rule** : Toutes les migrations futures DOIVENT appliquer les changements aux DEUX schémas (docs/ENVIRONMENTS.md)
- **Applied to production** : Migration exécutée en réel sur Supabase `tbgttutodbqffrvsvkoz` (2026-05-28 ~12:00 UTC)
- **77 RLS tests** : `supabase/tests/rls_landlords.sql`, `rls_properties.sql`, `rls_tenants.sql`, `rls_leases.sql`
