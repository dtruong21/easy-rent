# Schéma Postgres — snapshot

> Maintenu par `state-keeper`. **Source** : `supabase/migrations/`. **Dernière sync** : 2026-05-28

## Tables

### `landlords` (public + dev)

**Migration source** : `supabase/migrations/20260527081533_feat001_landlords_auth.sql`

| Colonne | Type | Contraintes |
|---|---|---|
| `id` | `uuid` | PRIMARY KEY, FK → `auth.users(id)` ON DELETE CASCADE |
| `email` | `text` | NOT NULL |
| `created_at` | `timestamptz` | NOT NULL DEFAULT now() |
| `updated_at` | `timestamptz` | NOT NULL DEFAULT now() (trigger `set_landlords_updated_at`) |
| `deleted_at` | `timestamptz` | NULL — soft-delete |

**Index** : `idx_public_landlords_email` sur `email` (dans les deux schémas)

**RLS** : activée dans les deux schémas

**Policies** :

| Policy | Schéma | Opération | Condition |
|---|---|---|---|
| `landlord_selects_self` | public + dev | SELECT | `id = auth.uid() AND deleted_at IS NULL` |
| `landlord_updates_self` | public + dev | UPDATE | USING: `id = auth.uid() AND deleted_at IS NULL` / WITH CHECK: `id = auth.uid()` |

**Client constraints** :
- INSERT : **interdit** (aucune policy INSERT → refusé par RLS. Trigger SECURITY DEFINER `handle_new_user` insère automatiquement)
- DELETE : **interdit** (aucune policy DELETE → soft-delete uniquement via `deleted_at`)

## Storage buckets

_(aucun bucket configuré)_

## Triggers et fonctions Postgres

### `dev.check_schema_parity()`
- **Type** : Function helper (debug)
- **Purpose** : Compare tables between `public` (PROD) et `dev` (DEV) schemas pour détecter la dérive
- **Return** : `TABLE (public_table text, dev_table text, status text)`
- **Source** : `supabase/migrations/00000000000000_init_dev_schema.sql:38-59`

### `dev.assert_rls_both_schemas(table_name text)`
- **Type** : Function helper (security check)
- **Purpose** : Assert RLS is enabled on both `public` and `dev` schemas for a given table
- **Raises** : Exception si RLS non activée
- **Source** : `supabase/migrations/00000000000000_init_dev_schema.sql:64-82`

### `public.handle_new_user()`
- **Type** : Trigger function, SECURITY DEFINER, `SET search_path = public`
- **Purpose** : Auto-provisioning — insère une ligne dans `public.landlords` ET `dev.landlords` à chaque INSERT dans `auth.users`. Idempotent (`ON CONFLICT (id) DO NOTHING`).
- **Trigger** : `on_auth_user_created` AFTER INSERT ON `auth.users` FOR EACH ROW
- **Source** : `supabase/migrations/20260527081533_feat001_landlords_auth.sql:87-118`

### `public.set_updated_at()`
- **Type** : Trigger function
- **Purpose** : Maintient `updated_at = now()` automatiquement à chaque UPDATE
- **Triggers** : `set_landlords_updated_at` BEFORE UPDATE ON `public.landlords` et `dev.landlords`
- **Source** : `supabase/migrations/20260527081533_feat001_landlords_auth.sql:124-142`

## Schémas

### `public` (PROD)
- Status : Initialized by Supabase (default)
- RLS : enabled per table
- Roles with access : `authenticated`, `anon`, `service_role`

### `dev` (DEV)
- Status : created in init migration
- RLS : enabled per table
- Roles with access : `authenticated`, `anon`, `service_role`
- Default privileges : `SELECT, INSERT, UPDATE, DELETE` on tables for `authenticated`
- Comment : "Development/staging mirror of public schema. Mapped to Git branch `develop`."

## Notes

- **Multi-environment strategy** : Same database hosts both `public` (PROD) et `dev` (DEV) schemas on Supabase free tier
- **Migration rule** : All future migrations MUST apply changes to BOTH schemas (see `docs/ENVIRONMENTS.md`)
- **FEAT-002** étendra `landlords` via `ALTER TABLE` (ajout colonnes : adresse, raison sociale, SIRET, etc.)
- **Applied to production** : Migration exécutée en réel sur le projet Supabase `tbgttutodbqffrvsvkoz` (2026-05-27 ~08:15 UTC)
