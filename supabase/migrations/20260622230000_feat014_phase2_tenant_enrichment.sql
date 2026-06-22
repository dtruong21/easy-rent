-- ============================================================================
-- FEAT-014 Phase 2 — Tenant enrichment pour conformité location FR
-- ============================================================================
-- WHY : Le formulaire tenant actuel ne capture que first_name/last_name/email/
-- phone. Pour matcher les attentes d'un bailleur français en MVP utilisable,
-- on ajoute identité civile (date+lieu naissance, nationalité), situation
-- socio-pro (profession, employeur, revenus mensuels), adresse précédente,
-- et garant (caution physique).
--
-- Décisions actées (2026-06-22, validées user) :
--   - Tous nouveaux champs nullable (backward compat 100%)
--   - CHECK constraint stricts côté DB (birth_date >= 1900 AND <= now-18ans,
--     guarantor_email regex, monthly_income borné)
--   - Schémas dual public + dev (mirror obligatoire)
--   - Pas de migration data, pas de RLS nouvelle (héritent)
-- ============================================================================

BEGIN;

-- === PROD (public.tenants) ===
ALTER TABLE public.tenants
  ADD COLUMN birth_date date,
  ADD COLUMN birth_place text,
  ADD COLUMN nationality text,
  ADD COLUMN profession text,
  ADD COLUMN employer text,
  ADD COLUMN monthly_income_cents bigint,
  ADD COLUMN previous_address text,
  ADD COLUMN guarantor_name text,
  ADD COLUMN guarantor_email text,
  ADD COLUMN guarantor_phone text;

ALTER TABLE public.tenants
  ADD CONSTRAINT tenants_birth_date_check CHECK (
    birth_date IS NULL OR (
      birth_date >= '1900-01-01'::date
      AND birth_date <= (CURRENT_DATE - INTERVAL '18 years')::date
    )
  ),
  ADD CONSTRAINT tenants_birth_place_check CHECK (
    birth_place IS NULL OR char_length(birth_place) BETWEEN 1 AND 100
  ),
  ADD CONSTRAINT tenants_nationality_check CHECK (
    nationality IS NULL OR char_length(nationality) BETWEEN 1 AND 60
  ),
  ADD CONSTRAINT tenants_profession_check CHECK (
    profession IS NULL OR char_length(profession) BETWEEN 1 AND 100
  ),
  ADD CONSTRAINT tenants_employer_check CHECK (
    employer IS NULL OR char_length(employer) BETWEEN 1 AND 100
  ),
  ADD CONSTRAINT tenants_monthly_income_check CHECK (
    monthly_income_cents IS NULL OR (
      monthly_income_cents >= 0 AND monthly_income_cents <= 10000000000
    )
  ),
  ADD CONSTRAINT tenants_previous_address_check CHECK (
    previous_address IS NULL OR char_length(previous_address) BETWEEN 1 AND 300
  ),
  ADD CONSTRAINT tenants_guarantor_name_check CHECK (
    guarantor_name IS NULL OR char_length(guarantor_name) BETWEEN 1 AND 200
  ),
  ADD CONSTRAINT tenants_guarantor_email_check CHECK (
    guarantor_email IS NULL OR guarantor_email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'
  ),
  ADD CONSTRAINT tenants_guarantor_phone_check CHECK (
    guarantor_phone IS NULL OR char_length(guarantor_phone) BETWEEN 1 AND 30
  );

-- === DEV (dev.tenants) ===
ALTER TABLE dev.tenants
  ADD COLUMN birth_date date,
  ADD COLUMN birth_place text,
  ADD COLUMN nationality text,
  ADD COLUMN profession text,
  ADD COLUMN employer text,
  ADD COLUMN monthly_income_cents bigint,
  ADD COLUMN previous_address text,
  ADD COLUMN guarantor_name text,
  ADD COLUMN guarantor_email text,
  ADD COLUMN guarantor_phone text;

ALTER TABLE dev.tenants
  ADD CONSTRAINT tenants_birth_date_check CHECK (
    birth_date IS NULL OR (
      birth_date >= '1900-01-01'::date
      AND birth_date <= (CURRENT_DATE - INTERVAL '18 years')::date
    )
  ),
  ADD CONSTRAINT tenants_birth_place_check CHECK (
    birth_place IS NULL OR char_length(birth_place) BETWEEN 1 AND 100
  ),
  ADD CONSTRAINT tenants_nationality_check CHECK (
    nationality IS NULL OR char_length(nationality) BETWEEN 1 AND 60
  ),
  ADD CONSTRAINT tenants_profession_check CHECK (
    profession IS NULL OR char_length(profession) BETWEEN 1 AND 100
  ),
  ADD CONSTRAINT tenants_employer_check CHECK (
    employer IS NULL OR char_length(employer) BETWEEN 1 AND 100
  ),
  ADD CONSTRAINT tenants_monthly_income_check CHECK (
    monthly_income_cents IS NULL OR (
      monthly_income_cents >= 0 AND monthly_income_cents <= 10000000000
    )
  ),
  ADD CONSTRAINT tenants_previous_address_check CHECK (
    previous_address IS NULL OR char_length(previous_address) BETWEEN 1 AND 300
  ),
  ADD CONSTRAINT tenants_guarantor_name_check CHECK (
    guarantor_name IS NULL OR char_length(guarantor_name) BETWEEN 1 AND 200
  ),
  ADD CONSTRAINT tenants_guarantor_email_check CHECK (
    guarantor_email IS NULL OR guarantor_email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'
  ),
  ADD CONSTRAINT tenants_guarantor_phone_check CHECK (
    guarantor_phone IS NULL OR char_length(guarantor_phone) BETWEEN 1 AND 30
  );

-- Vérification défensive RLS toujours actives
SELECT dev.assert_rls_both_schemas('tenants');

COMMIT;
