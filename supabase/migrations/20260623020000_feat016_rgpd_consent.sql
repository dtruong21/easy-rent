-- ============================================================================
-- FEAT-016 — Persistance du consentement RGPD (accountability art. 7.1)
-- ============================================================================
-- WHY: QA a détecté que la case RGPD cochée au signup n'était jamais persistée
-- en DB, violant l'accountability art. 7.1 du RGPD (le responsable de traitement
-- doit pouvoir prouver le consentement avec date et version du texte présenté).
--
-- Décisions actées (2026-06-23) :
--   - rgpd_consent_at  : timestamp du consentement (NOT NULL après backfill)
--   - rgpd_consent_version : version du texte présenté ('v1-2026-06', 'legacy-1')
--   - Backfill 'legacy-1' : les comptes existants ont coché la case RGPD depuis
--     FEAT-001 (widget existant). created_at sert de date de consentement attestée.
--   - Trigger handle_new_user() étendu pour lire rgpd_consent_version depuis
--     raw_user_meta_data, avec fallback 'legacy-1' pour les créations admin/Studio.
-- ============================================================================

BEGIN;

-- ============================================================================
-- PROD (public.landlords)
-- ============================================================================

ALTER TABLE public.landlords
  ADD COLUMN rgpd_consent_at      timestamptz,
  ADD COLUMN rgpd_consent_version text;

-- Backfill défensif : les comptes existants ont utilisé le widget RGPD présent
-- depuis FEAT-001. On atteste le consentement via created_at + version 'legacy-1'.
UPDATE public.landlords
  SET rgpd_consent_at      = COALESCE(created_at, now()),
      rgpd_consent_version = 'legacy-1'
  WHERE rgpd_consent_at IS NULL;

-- Après backfill, on passe les colonnes NOT NULL
ALTER TABLE public.landlords
  ALTER COLUMN rgpd_consent_at      SET NOT NULL,
  ALTER COLUMN rgpd_consent_version SET NOT NULL;

-- Contrainte sur la longueur de la version (évite les valeurs trop longues)
ALTER TABLE public.landlords
  ADD CONSTRAINT landlords_rgpd_consent_version_check CHECK (
    char_length(rgpd_consent_version) BETWEEN 1 AND 50
  );

-- ============================================================================
-- DEV (dev.landlords) — miroir exact
-- ============================================================================

ALTER TABLE dev.landlords
  ADD COLUMN rgpd_consent_at      timestamptz,
  ADD COLUMN rgpd_consent_version text;

UPDATE dev.landlords
  SET rgpd_consent_at      = COALESCE(created_at, now()),
      rgpd_consent_version = 'legacy-1'
  WHERE rgpd_consent_at IS NULL;

ALTER TABLE dev.landlords
  ALTER COLUMN rgpd_consent_at      SET NOT NULL,
  ALTER COLUMN rgpd_consent_version SET NOT NULL;

ALTER TABLE dev.landlords
  ADD CONSTRAINT landlords_rgpd_consent_version_check CHECK (
    char_length(rgpd_consent_version) BETWEEN 1 AND 50
  );

-- ============================================================================
-- Trigger handle_new_user() — étendu pour persister le consentement RGPD
-- ============================================================================
-- WHY REPLACE: la version FEAT-011 ne lisait que full_name depuis
-- raw_user_meta_data. On ajoute la lecture de rgpd_consent_version avec
-- fallback 'legacy-1' pour les créations hors-app (Studio, import CSV).
-- SECURITY DEFINER conservé — nécessaire pour bypass RLS sur INSERT landlords.
-- SET search_path strict conservé — sécurité anti-injection.

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_full_name    text;
  v_rgpd_version text;
BEGIN
  -- Lecture full_name depuis raw_user_meta_data (envoyé par le client Flutter).
  -- TRIM + NULLIF rejette les valeurs composées d'espaces uniquement.
  -- Fallback sur NEW.email si absent (création Studio, import CSV, etc.).
  v_full_name := NULLIF(TRIM(NEW.raw_user_meta_data->>'full_name'), '');
  IF v_full_name IS NULL THEN
    v_full_name := NEW.email;
  END IF;

  -- Lecture rgpd_consent_version depuis raw_user_meta_data.
  -- Envoyée par le client Flutter au signup (ex: 'v1-2026-06').
  -- Fallback 'legacy-1' si absente (admin Studio, import CSV, autre source non-app).
  v_rgpd_version := COALESCE(
    NULLIF(TRIM(NEW.raw_user_meta_data->>'rgpd_consent_version'), ''),
    'legacy-1'
  );

  -- Insertion dans PROD (public.landlords)
  INSERT INTO public.landlords (id, email, full_name, rgpd_consent_at, rgpd_consent_version)
    VALUES (NEW.id, NEW.email, v_full_name, now(), v_rgpd_version)
    ON CONFLICT (id) DO NOTHING;
  -- ON CONFLICT DO NOTHING : idempotence — si la ligne existe déjà (retry signup),
  -- on ne l'écrase pas (le consentement initial est préservé).

  -- Insertion dans DEV (dev.landlords)
  INSERT INTO dev.landlords (id, email, full_name, rgpd_consent_at, rgpd_consent_version)
    VALUES (NEW.id, NEW.email, v_full_name, now(), v_rgpd_version)
    ON CONFLICT (id) DO NOTHING;

  RETURN NEW;
END;
$$;

-- Le trigger on_auth_user_created reste inchangé — il pointe déjà sur cette fonction.
-- CREATE OR REPLACE FUNCTION suffit, pas besoin de DROP/CREATE TRIGGER.

-- ============================================================================
-- Vérification finale : RLS toujours activée sur les deux schémas
-- ============================================================================
SELECT dev.assert_rls_both_schemas('landlords');

COMMIT;
