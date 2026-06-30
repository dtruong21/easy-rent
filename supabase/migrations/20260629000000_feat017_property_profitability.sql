-- ============================================================================
-- FEAT-017 Phase 1 — Property profitability data (rental investment ROI)
-- ============================================================================
-- WHY : Pour calculer la rentabilité d'un investissement locatif (rendement
-- brut/net, cash flow mensuel), on a besoin du prix d'achat + frais notaire +
-- conditions du prêt + taxe foncière + assurance PNO + charges copro non
-- récupérables. Toutes ces données manquent au modèle Property actuel.
--
-- Décisions actées (workflow rentabilite-modules-design, 2026-06-29) :
--   - Prêt INLINE sur properties (pas de table loan_scenarios v1)
--   - Charges copro = NON RÉCUPÉRABLES UNIQUEMENT (label UI explicite)
--   - Frais notaire avec toggle is_new_property (2.5% neuf vs 7.5% ancien)
--   - Tous les champs NULLABLE → backward compat 100% biens existants
--   - Cents partout (bigint) cohérence avec rent_amount_cents existant
--   - Taux en basis points (int) — 0..3000 bps = 0..30%
--   - Durées en months (smallint) — 12..360 mois = 1..30 ans
--   - Schémas dual public + dev
-- ============================================================================

BEGIN;

-- === PROD (public.properties) ===
ALTER TABLE public.properties
  -- Acquisition
  ADD COLUMN purchase_price_cents bigint,
  ADD COLUMN purchase_date date,
  ADD COLUMN notary_fees_cents bigint,
  ADD COLUMN is_new_property boolean NOT NULL DEFAULT false,
  -- Charges récurrentes annuelles
  ADD COLUMN property_tax_annual_cents bigint,
  ADD COLUMN insurance_pno_annual_cents bigint,
  ADD COLUMN condo_fees_non_recoverable_cents bigint,
  -- Prêt immobilier (inline v1, pas de table loan_scenarios séparée)
  ADD COLUMN loan_principal_cents bigint,
  ADD COLUMN loan_rate_bps int,
  ADD COLUMN loan_insurance_bps int,
  ADD COLUMN loan_duration_months smallint,
  ADD COLUMN loan_start_date date,
  ADD COLUMN loan_monthly_payment_override_cents bigint;
  -- override permet de saisir la mensualité réelle si différente du calcul
  -- (ex: prêt à taux modulables, paliers, ou prêt déjà existant avec params perdus)

ALTER TABLE public.properties
  ADD CONSTRAINT properties_purchase_price_check CHECK (
    purchase_price_cents IS NULL OR (purchase_price_cents > 0 AND purchase_price_cents < 100000000000)
  ),
  ADD CONSTRAINT properties_notary_fees_check CHECK (
    notary_fees_cents IS NULL OR (notary_fees_cents >= 0 AND notary_fees_cents < 100000000000)
  ),
  ADD CONSTRAINT properties_property_tax_check CHECK (
    property_tax_annual_cents IS NULL OR (property_tax_annual_cents >= 0 AND property_tax_annual_cents < 10000000000)
  ),
  ADD CONSTRAINT properties_insurance_pno_check CHECK (
    insurance_pno_annual_cents IS NULL OR (insurance_pno_annual_cents >= 0 AND insurance_pno_annual_cents < 10000000000)
  ),
  ADD CONSTRAINT properties_condo_fees_check CHECK (
    condo_fees_non_recoverable_cents IS NULL OR (condo_fees_non_recoverable_cents >= 0 AND condo_fees_non_recoverable_cents < 10000000000)
  ),
  ADD CONSTRAINT properties_loan_principal_check CHECK (
    loan_principal_cents IS NULL OR (loan_principal_cents >= 0 AND loan_principal_cents < 100000000000)
  ),
  ADD CONSTRAINT properties_loan_rate_check CHECK (
    loan_rate_bps IS NULL OR (loan_rate_bps >= 0 AND loan_rate_bps <= 3000)
  ),
  ADD CONSTRAINT properties_loan_insurance_check CHECK (
    loan_insurance_bps IS NULL OR (loan_insurance_bps >= 0 AND loan_insurance_bps <= 200)
  ),
  ADD CONSTRAINT properties_loan_duration_check CHECK (
    loan_duration_months IS NULL OR (loan_duration_months >= 12 AND loan_duration_months <= 360)
  ),
  ADD CONSTRAINT properties_loan_override_check CHECK (
    loan_monthly_payment_override_cents IS NULL OR (loan_monthly_payment_override_cents > 0 AND loan_monthly_payment_override_cents < 10000000000)
  );

-- === DEV (dev.properties) — mirror identique ===
ALTER TABLE dev.properties
  ADD COLUMN purchase_price_cents bigint,
  ADD COLUMN purchase_date date,
  ADD COLUMN notary_fees_cents bigint,
  ADD COLUMN is_new_property boolean NOT NULL DEFAULT false,
  ADD COLUMN property_tax_annual_cents bigint,
  ADD COLUMN insurance_pno_annual_cents bigint,
  ADD COLUMN condo_fees_non_recoverable_cents bigint,
  ADD COLUMN loan_principal_cents bigint,
  ADD COLUMN loan_rate_bps int,
  ADD COLUMN loan_insurance_bps int,
  ADD COLUMN loan_duration_months smallint,
  ADD COLUMN loan_start_date date,
  ADD COLUMN loan_monthly_payment_override_cents bigint;

ALTER TABLE dev.properties
  ADD CONSTRAINT properties_purchase_price_check CHECK (
    purchase_price_cents IS NULL OR (purchase_price_cents > 0 AND purchase_price_cents < 100000000000)
  ),
  ADD CONSTRAINT properties_notary_fees_check CHECK (
    notary_fees_cents IS NULL OR (notary_fees_cents >= 0 AND notary_fees_cents < 100000000000)
  ),
  ADD CONSTRAINT properties_property_tax_check CHECK (
    property_tax_annual_cents IS NULL OR (property_tax_annual_cents >= 0 AND property_tax_annual_cents < 10000000000)
  ),
  ADD CONSTRAINT properties_insurance_pno_check CHECK (
    insurance_pno_annual_cents IS NULL OR (insurance_pno_annual_cents >= 0 AND insurance_pno_annual_cents < 10000000000)
  ),
  ADD CONSTRAINT properties_condo_fees_check CHECK (
    condo_fees_non_recoverable_cents IS NULL OR (condo_fees_non_recoverable_cents >= 0 AND condo_fees_non_recoverable_cents < 10000000000)
  ),
  ADD CONSTRAINT properties_loan_principal_check CHECK (
    loan_principal_cents IS NULL OR (loan_principal_cents >= 0 AND loan_principal_cents < 100000000000)
  ),
  ADD CONSTRAINT properties_loan_rate_check CHECK (
    loan_rate_bps IS NULL OR (loan_rate_bps >= 0 AND loan_rate_bps <= 3000)
  ),
  ADD CONSTRAINT properties_loan_insurance_check CHECK (
    loan_insurance_bps IS NULL OR (loan_insurance_bps >= 0 AND loan_insurance_bps <= 200)
  ),
  ADD CONSTRAINT properties_loan_duration_check CHECK (
    loan_duration_months IS NULL OR (loan_duration_months >= 12 AND loan_duration_months <= 360)
  ),
  ADD CONSTRAINT properties_loan_override_check CHECK (
    loan_monthly_payment_override_cents IS NULL OR (loan_monthly_payment_override_cents > 0 AND loan_monthly_payment_override_cents < 10000000000)
  );

SELECT dev.assert_rls_both_schemas('properties');

COMMIT;
