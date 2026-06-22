-- ============================================================================
-- FEAT-014 Phase 1 — Property enrichment pour conformité location FR
-- ============================================================================
-- WHY : Les formulaires de création/édition de bien locatif manquaient de
-- champs attendus par tout bailleur français : DPE/GES (obligatoires légalement
-- depuis la loi Climat & Résilience 2021), étage, meublé, mode de chauffage,
-- code postal séparé, etc. Ces colonnes sont TOUTES nullable ou ont un DEFAULT
-- non-cassant pour garantir une backward compatibility 100% : aucune ligne
-- existante n'est modifiée, aucun code Dart existant ne casse.
--
-- REF : docs/plans/FEAT-014-forms-enrichment.md — section Phase 1 (Property)
-- Branche : feature/feat-014-phase1-property
-- Date : 2026-06-22
-- ============================================================================

BEGIN;

-- ============================================================================
-- PROD (public.properties) — ajout des 12 colonnes
-- ============================================================================

ALTER TABLE public.properties
  ADD COLUMN rooms                  smallint,
  ADD COLUMN bedrooms               smallint,
  ADD COLUMN floor                  smallint,
  ADD COLUMN has_elevator           boolean NOT NULL DEFAULT false,
  ADD COLUMN furnished              boolean NOT NULL DEFAULT false,
  ADD COLUMN heating_type           text,
  ADD COLUMN dpe_letter             text,
  ADD COLUMN dpe_value_kwh_m2_year  integer,
  ADD COLUMN ges_letter             text,
  ADD COLUMN construction_year      smallint,
  ADD COLUMN postal_code            text,
  ADD COLUMN city                   text;

-- CHECK constraints PROD
-- Toutes les colonnes nullable : le pattern IS NULL OR (...) garantit que
-- NULL est toujours accepté (sentinel "non communiqué").
ALTER TABLE public.properties
  ADD CONSTRAINT properties_rooms_check
    CHECK (rooms IS NULL OR (rooms > 0 AND rooms <= 50)),
  ADD CONSTRAINT properties_bedrooms_check
    CHECK (bedrooms IS NULL OR (bedrooms >= 0 AND bedrooms <= 50)),
  ADD CONSTRAINT properties_floor_check
    CHECK (floor IS NULL OR (floor BETWEEN -5 AND 200)),
  ADD CONSTRAINT properties_heating_type_check
    CHECK (heating_type IS NULL OR heating_type IN (
      'electric','gas','collective','fuel','wood','heat_pump','other'
    )),
  ADD CONSTRAINT properties_dpe_letter_check
    CHECK (dpe_letter IS NULL OR dpe_letter ~ '^[A-G]$'),
  ADD CONSTRAINT properties_dpe_value_kwh_m2_year_check
    CHECK (dpe_value_kwh_m2_year IS NULL OR (dpe_value_kwh_m2_year > 0 AND dpe_value_kwh_m2_year < 2000)),
  ADD CONSTRAINT properties_ges_letter_check
    CHECK (ges_letter IS NULL OR ges_letter ~ '^[A-G]$'),
  ADD CONSTRAINT properties_construction_year_check
    CHECK (construction_year IS NULL OR (construction_year >= 1700 AND construction_year <= extract(year from now())::int + 1)),
  ADD CONSTRAINT properties_postal_code_check
    CHECK (postal_code IS NULL OR postal_code ~ '^\d{5}$'),
  ADD CONSTRAINT properties_city_check
    CHECK (city IS NULL OR (char_length(city) BETWEEN 1 AND 100));

-- ============================================================================
-- DEV (dev.properties) — mirror exact
-- ============================================================================

ALTER TABLE dev.properties
  ADD COLUMN rooms                  smallint,
  ADD COLUMN bedrooms               smallint,
  ADD COLUMN floor                  smallint,
  ADD COLUMN has_elevator           boolean NOT NULL DEFAULT false,
  ADD COLUMN furnished              boolean NOT NULL DEFAULT false,
  ADD COLUMN heating_type           text,
  ADD COLUMN dpe_letter             text,
  ADD COLUMN dpe_value_kwh_m2_year  integer,
  ADD COLUMN ges_letter             text,
  ADD COLUMN construction_year      smallint,
  ADD COLUMN postal_code            text,
  ADD COLUMN city                   text;

-- CHECK constraints DEV (identiques PROD)
ALTER TABLE dev.properties
  ADD CONSTRAINT properties_rooms_check
    CHECK (rooms IS NULL OR (rooms > 0 AND rooms <= 50)),
  ADD CONSTRAINT properties_bedrooms_check
    CHECK (bedrooms IS NULL OR (bedrooms >= 0 AND bedrooms <= 50)),
  ADD CONSTRAINT properties_floor_check
    CHECK (floor IS NULL OR (floor BETWEEN -5 AND 200)),
  ADD CONSTRAINT properties_heating_type_check
    CHECK (heating_type IS NULL OR heating_type IN (
      'electric','gas','collective','fuel','wood','heat_pump','other'
    )),
  ADD CONSTRAINT properties_dpe_letter_check
    CHECK (dpe_letter IS NULL OR dpe_letter ~ '^[A-G]$'),
  ADD CONSTRAINT properties_dpe_value_kwh_m2_year_check
    CHECK (dpe_value_kwh_m2_year IS NULL OR (dpe_value_kwh_m2_year > 0 AND dpe_value_kwh_m2_year < 2000)),
  ADD CONSTRAINT properties_ges_letter_check
    CHECK (ges_letter IS NULL OR ges_letter ~ '^[A-G]$'),
  ADD CONSTRAINT properties_construction_year_check
    CHECK (construction_year IS NULL OR (construction_year >= 1700 AND construction_year <= extract(year from now())::int + 1)),
  ADD CONSTRAINT properties_postal_code_check
    CHECK (postal_code IS NULL OR postal_code ~ '^\d{5}$'),
  ADD CONSTRAINT properties_city_check
    CHECK (city IS NULL OR (char_length(city) BETWEEN 1 AND 100));

-- ============================================================================
-- Vérification défensive : RLS toujours active sur les deux schémas
-- ============================================================================
SELECT dev.assert_rls_both_schemas('properties');

COMMIT;
