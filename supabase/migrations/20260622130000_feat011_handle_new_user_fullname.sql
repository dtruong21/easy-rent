-- ============================================================================
-- FEAT-011 — Adapter handle_new_user() pour lire full_name depuis les métadonnées
-- ============================================================================
-- WHY: Le pivot magic link → email/password (FEAT-011) introduit un formulaire
-- de signup qui envoie full_name dans options.data (raw_user_meta_data). La
-- fonction handle_new_user() originale (FEAT-001) n'utilisait que NEW.email.
-- On REPLACE la fonction pour lire raw_user_meta_data->>'full_name' avec un
-- fallback sur NEW.email si la métadonnée est absente ou vide (ex: user créé
-- depuis Supabase Studio sans full_name).
--
-- Décisions actées (2026-06-22) :
--   - full_name NULL/vide → fallback = NEW.email (provisionnel, éditable ensuite)
--   - Le trigger on_auth_user_created reste inchangé (pointe toujours sur cette fn)
--   - SECURITY DEFINER + SET search_path strict conservés (anti-injection)
--   - ON CONFLICT DO NOTHING conservé (idempotence)
--   - NE PAS modifier la migration FEAT-001 historique
-- ============================================================================

-- ============================================================================
-- PROD (public schema) — REPLACE la fonction existante FEAT-001
-- ============================================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
-- SECURITY DEFINER : s'exécute avec les droits du propriétaire (postgres/service_role).
-- Nécessaire car INSERT public.landlords n'a aucune policy client (seul ce trigger insère).
-- SET search_path : sécurité anti-injection search_path (OWASP recommandation PostgreSQL).
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_full_name text;
BEGIN
  -- Lire full_name depuis raw_user_meta_data (envoyé par le client via options.data).
  -- Trim pour rejeter les valeurs composées uniquement d'espaces.
  -- Fallback sur NEW.email si NULL ou chaîne vide — provisionnel, user peut éditer ensuite.
  v_full_name := NULLIF(TRIM(NEW.raw_user_meta_data->>'full_name'), '');
  IF v_full_name IS NULL THEN
    -- Cas : création depuis Supabase Studio, import CSV, ou signup sans full_name fourni.
    v_full_name := NEW.email;
  END IF;

  -- Insertion dans PROD (public.landlords)
  INSERT INTO public.landlords (id, email, full_name)
    VALUES (NEW.id, NEW.email, v_full_name)
    ON CONFLICT (id) DO NOTHING;
  -- ON CONFLICT DO NOTHING : idempotence — si la ligne existe déjà (ex: retry signup),
  -- on ne l'écrase pas (l'user a peut-être déjà renseigné ses données).

  -- Insertion dans DEV (dev.landlords)
  -- auth.users est partagée entre les deux schémas (free tier Supabase = 1 projet).
  -- On ne sait pas depuis quel env le signup est effectué → on insère dans les deux.
  INSERT INTO dev.landlords (id, email, full_name)
    VALUES (NEW.id, NEW.email, v_full_name)
    ON CONFLICT (id) DO NOTHING;

  RETURN NEW;
END;
$$;

-- Le trigger on_auth_user_created reste inchangé — il pointe déjà sur cette fonction.
-- CREATE OR REPLACE FUNCTION suffit, pas besoin de DROP/CREATE TRIGGER.

-- ============================================================================
-- Vérification : RLS toujours activée sur les deux schémas
-- ============================================================================
-- Cette migration ne modifie pas les tables (pas de ALTER TABLE, pas de CREATE TABLE).
-- On vérifie quand même que RLS est active (protection contre régression accidentelle).
SELECT dev.assert_rls_both_schemas('landlords');
