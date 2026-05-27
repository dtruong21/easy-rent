# Schéma Postgres — snapshot

> Maintenu par `state-keeper`. **Source** : `supabase/migrations/`. **Dernière sync** : 2026-05-27

## Tables

_(aucune table créée — le projet n'est pas encore initialisé au-delà de l'infrastructure multi-env)_

## Storage buckets

_(aucun bucket configuré)_

## Triggers et fonctions Postgres

### `dev.check_schema_parity()`
- **Type** : Function helper (debug)
- **Purpose** : Compare tables between `public` (PROD) and `dev` (DEV) schemas to detect drift
- **Return** : `TABLE (public_table text, dev_table text, status text)`
- **Source** : `supabase/migrations/00000000000000_init_dev_schema.sql:38-59`

### `dev.assert_rls_both_schemas(table_name text)`
- **Type** : Function helper (security check)
- **Purpose** : Assert RLS is enabled on both public and dev schemas for a given table
- **Raises** : Exception if RLS not enabled
- **Source** : `supabase/migrations/00000000000000_init_dev_schema.sql:64-82`

## Schémas

### `public` (PROD)
- Status : Initialized by Supabase (default)
- RLS : ✅ enabled by default (see Supabase auth policies)
- Roles with access : `authenticated`, `anon`, `service_role`

### `dev` (DEV)
- Status : ✅ created in init migration
- RLS : To be enabled per table
- Roles with access : `authenticated`, `anon`, `service_role`
- Default privileges : `SELECT, INSERT, UPDATE, DELETE` on tables for `authenticated`
- Comment : "Development/staging mirror of public schema. Mapped to Git branch `develop`."

## Notes

- **Multi-environment strategy** : Same database hosts both `public` (PROD) and `dev` (DEV) schemas on Supabase free tier
- **Migration rule** : All future migrations MUST apply changes to BOTH schemas (see `docs/ENVIRONMENTS.md`)
- **No tables yet** : Bootstrap focused on infra setup; feature tables will be created as features are implemented
