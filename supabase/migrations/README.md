# Supabase migrations — convention

## Règle d'or : toutes les migrations touchent les deux schémas

`EasyRent` utilise deux schémas Postgres pour séparer DEV et PROD au sein du même projet Supabase free tier :
- `public` → PROD
- `dev` → DEV / staging

→ **Chaque migration doit créer/modifier les tables dans les DEUX schémas.**

## Template de migration

```sql
-- Migration: <date>_<description>.sql

-- ============ PROD (public schema) ============
CREATE TABLE public.<nom> (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  landlord_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  -- ... autres colonnes ...
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.<nom> ENABLE ROW LEVEL SECURITY;

CREATE POLICY "landlord_owns_<nom>" ON public.<nom>
  FOR ALL
  USING (landlord_id = auth.uid())
  WITH CHECK (landlord_id = auth.uid());

CREATE INDEX idx_public_<nom>_landlord ON public.<nom>(landlord_id);

-- ============ DEV (dev schema) — mirror exact ============
CREATE TABLE dev.<nom> (LIKE public.<nom> INCLUDING ALL);

ALTER TABLE dev.<nom> ENABLE ROW LEVEL SECURITY;

CREATE POLICY "landlord_owns_<nom>" ON dev.<nom>
  FOR ALL
  USING (landlord_id = auth.uid())
  WITH CHECK (landlord_id = auth.uid());

-- INCLUDING ALL copie les indexes — pas besoin de les recréer

-- ============ Vérification ============
SELECT dev.assert_rls_both_schemas('<nom>');
```

## Foreign keys cross-schema

Une FK doit pointer vers une table du **même schéma** :
- `public.leases.property_id` → `public.properties.id`
- `dev.leases.property_id` → `dev.properties.id`

**Sauf** pour `auth.users` qui est commun aux deux :
- `public.landlords.id` → `auth.users.id` ✅
- `dev.landlords.id` → `auth.users.id` ✅

## Modifications de structure

Pour ajouter une colonne :
```sql
ALTER TABLE public.<nom> ADD COLUMN ...;
ALTER TABLE dev.<nom> ADD COLUMN ...;
```

Pour ajouter une policy :
```sql
CREATE POLICY ... ON public.<nom> ...;
CREATE POLICY ... ON dev.<nom> ...;
```

## Vérifier la parité après migration

```sql
SELECT * FROM dev.check_schema_parity();
-- Doit retourner aucune ligne (= parité parfaite)
```

## Test RLS obligatoire

Avant de merger une migration, écrire un test dans `supabase/tests/rls_<nom>.sql` :
- Crée 2 users de test
- Insère des données pour user A dans **les deux schémas**
- Vérifie que user B ne voit rien dans **les deux schémas**
