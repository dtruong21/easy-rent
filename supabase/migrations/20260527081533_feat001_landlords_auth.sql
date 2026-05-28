-- ============================================================================
-- FEAT-001 — Table landlords (minimale) + trigger auto-provisioning auth.users
-- ============================================================================
-- WHY: Crée la table landlords (relation 1-1 avec auth.users) et un trigger
-- SECURITY DEFINER qui insère automatiquement la ligne landlord lors du
-- premier signup. auth.users est partagée entre les schémas dev et public
-- (free tier Supabase = un seul projet), donc le trigger insère dans les DEUX
-- schémas de façon idempotente (ON CONFLICT DO NOTHING).
--
-- Décisions actées (2026-05-27 — source: docs/backlog/001-auth-magic-link.md) :
--   - PK id = auth.users.id (relation 1-1, simplification RLS)
--   - soft-delete via deleted_at (rétention légale 5 ans)
--   - Aucune policy INSERT client : seul le trigger SECURITY DEFINER insère
--   - FEAT-002 étendra cette table via ALTER TABLE (pas de re-création)
-- ============================================================================

-- ============================================================================
-- PROD (public schema)
-- ============================================================================

CREATE TABLE public.landlords (
  -- PK = auth.users.id (relation 1-1, utilisé directement dans RLS via auth.uid())
  id          uuid        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email       text        NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  -- soft-delete : pas de suppression physique pour respecter la rétention légale
  -- (quittances : obligation de conservation 5 ans — loi 6 juillet 1989)
  deleted_at  timestamptz
);

-- Index sur email pour les lookups futurs (ex: recherche admin, déduplication)
CREATE INDEX idx_public_landlords_email ON public.landlords(email);

ALTER TABLE public.landlords ENABLE ROW LEVEL SECURITY;

-- SELECT : seulement sa propre ligne ET non supprimée logiquement
CREATE POLICY "landlord_selects_self" ON public.landlords
  FOR SELECT
  USING (id = auth.uid() AND deleted_at IS NULL);

-- UPDATE : seulement sa propre ligne (et ne peut pas se réassigner à un autre uid).
-- WITH CHECK (id = auth.uid()) empêche le changement d'id, mais toutes les autres
-- colonnes — y compris deleted_at — sont modifiables par le propriétaire.
-- Une restriction colonne-par-colonne (ex: bloquer l'écriture directe de deleted_at
-- par le client) nécessite un trigger BEFORE UPDATE comparant OLD/NEW : prévu en FEAT-002.
CREATE POLICY "landlord_updates_self" ON public.landlords
  FOR UPDATE
  USING (id = auth.uid() AND deleted_at IS NULL)
  WITH CHECK (id = auth.uid());

-- Pas de policy INSERT côté client : le trigger SECURITY DEFINER ci-dessous insère.
-- Pas de policy DELETE côté client : suppression physique interdite (soft-delete uniquement).

-- ============================================================================
-- DEV (dev schema) — miroir exact
-- ============================================================================

-- LIKE ... INCLUDING ALL copie la structure, les constraints et les index
-- MAIS ne copie PAS les FKs inter-schémas ni les policies RLS → on les recrée
CREATE TABLE dev.landlords (LIKE public.landlords INCLUDING ALL);

-- La FK vers auth.users n'est pas copiée par LIKE INCLUDING ALL (schéma auth ≠ public)
-- On la recrée explicitement
ALTER TABLE dev.landlords
  ADD CONSTRAINT dev_landlords_id_fkey
  FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE dev.landlords ENABLE ROW LEVEL SECURITY;

CREATE POLICY "landlord_selects_self" ON dev.landlords
  FOR SELECT
  USING (id = auth.uid() AND deleted_at IS NULL);

CREATE POLICY "landlord_updates_self" ON dev.landlords
  FOR UPDATE
  USING (id = auth.uid() AND deleted_at IS NULL)
  WITH CHECK (id = auth.uid());

-- ============================================================================
-- Trigger auto-provisioning : insère dans LES DEUX schémas à chaque nouveau user
-- ============================================================================
-- WHY BOTH SCHEMAS: auth.users est partagée entre dev et public. On ne sait pas
-- depuis quel environnement le signup est effectué. On insère dans les deux de
-- façon idempotente. La donnée métier (baux, quittances) sera isolée par schéma.

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
-- SECURITY DEFINER : s'exécute avec les droits du propriétaire de la fonction
-- (postgres/service_role), bypass RLS, nécessaire car l'INSERT client est bloqué.
-- SET search_path = public : sécurité contre l'injection de search_path malveillant.
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Insertion dans PROD
  INSERT INTO public.landlords (id, email)
    VALUES (NEW.id, NEW.email)
    ON CONFLICT (id) DO NOTHING;

  -- Insertion dans DEV (même auth.users, environnement inconnu au moment du signup)
  INSERT INTO dev.landlords (id, email)
    VALUES (NEW.id, NEW.email)
    ON CONFLICT (id) DO NOTHING;

  RETURN NEW;
END;
$$;

-- Trigger AFTER INSERT sur auth.users (chaque nouveau compte déclenche le provisioning)
-- CREATE OR REPLACE n'existe pas pour les triggers → DROP IF EXISTS + CREATE
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- ============================================================================
-- Trigger updated_at automatique (bonne pratique — maintenu par Postgres)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER set_landlords_updated_at
  BEFORE UPDATE ON public.landlords
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER set_landlords_updated_at
  BEFORE UPDATE ON dev.landlords
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

-- ============================================================================
-- Vérification finale : RLS activée sur les deux schémas
-- ============================================================================
SELECT dev.assert_rls_both_schemas('landlords');
