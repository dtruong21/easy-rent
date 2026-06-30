-- ============================================================================
-- FEAT-018 Phase 1 — Investment scenarios table (simulateur futur)
-- ============================================================================
-- WHY : Le user veut simuler la rentabilité d'un investissement AVANT
-- d'acheter. Page /simulator avec form + résultats live + sauvegarde
-- des scenarios. Réutilise lib/core/finance/ livré par FEAT-017.
--
-- Décisions actées (workflow rentabilite-modules-design, 2026-06-29) :
--   - Table dédiée investment_scenarios (pas JSONB — sécurité + validation
--     DB native + queries fine-grained possibles)
--   - 12 champs métier (vs 17 design original — taux assurance constante,
--     vacancy/appreciation/projection_years fixés en P2)
--   - RLS strict pattern leases/payments (owner_only)
--   - Schémas dual public + dev (cohérent FEAT-002+)
--   - landlord_id DEFAULT auth.uid() (anti-bug RLS comme fix landlord-id-default)
--   - ON DELETE CASCADE depuis landlords (différent de RESTRICT métier —
--     scenarios = données d'aide à la décision, perdables avec le compte)
--   - Soft-delete via deleted_at (cohérent autres entités)
-- ============================================================================

BEGIN;

-- === PROD (public.investment_scenarios) ===
CREATE TABLE public.investment_scenarios (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  landlord_id uuid NOT NULL REFERENCES public.landlords(id) ON DELETE CASCADE DEFAULT auth.uid(),
  name text NOT NULL,
  -- Acquisition
  purchase_price_cents bigint NOT NULL,
  notary_fees_cents bigint NOT NULL DEFAULT 0,
  works_initial_cents bigint NOT NULL DEFAULT 0,
  is_new_property boolean NOT NULL DEFAULT false,
  -- Financement
  down_payment_cents bigint NOT NULL DEFAULT 0,
  loan_principal_cents bigint NOT NULL DEFAULT 0,
  loan_rate_bps int NOT NULL DEFAULT 0,
  loan_duration_months smallint NOT NULL DEFAULT 240,
  -- Revenus
  monthly_rent_hc_cents bigint NOT NULL,
  -- Charges annuelles
  property_tax_annual_cents bigint NOT NULL DEFAULT 0,
  insurance_pno_annual_cents bigint NOT NULL DEFAULT 0,
  condo_fees_non_recoverable_cents bigint NOT NULL DEFAULT 0,
  -- Métadonnées
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz
);

ALTER TABLE public.investment_scenarios
  ADD CONSTRAINT inv_scenarios_name_check CHECK (
    char_length(name) BETWEEN 1 AND 120
  ),
  ADD CONSTRAINT inv_scenarios_purchase_price_check CHECK (
    purchase_price_cents > 0 AND purchase_price_cents < 100000000000
  ),
  ADD CONSTRAINT inv_scenarios_notary_fees_check CHECK (
    notary_fees_cents >= 0 AND notary_fees_cents < 100000000000
  ),
  ADD CONSTRAINT inv_scenarios_works_initial_check CHECK (
    works_initial_cents >= 0 AND works_initial_cents < 100000000000
  ),
  ADD CONSTRAINT inv_scenarios_down_payment_check CHECK (
    down_payment_cents >= 0 AND down_payment_cents < 100000000000
  ),
  ADD CONSTRAINT inv_scenarios_loan_principal_check CHECK (
    loan_principal_cents >= 0 AND loan_principal_cents < 100000000000
  ),
  ADD CONSTRAINT inv_scenarios_loan_rate_check CHECK (
    loan_rate_bps >= 0 AND loan_rate_bps <= 3000
  ),
  ADD CONSTRAINT inv_scenarios_loan_duration_check CHECK (
    loan_duration_months >= 12 AND loan_duration_months <= 360
  ),
  ADD CONSTRAINT inv_scenarios_monthly_rent_check CHECK (
    monthly_rent_hc_cents > 0 AND monthly_rent_hc_cents < 10000000000
  ),
  ADD CONSTRAINT inv_scenarios_property_tax_check CHECK (
    property_tax_annual_cents >= 0 AND property_tax_annual_cents < 10000000000
  ),
  ADD CONSTRAINT inv_scenarios_insurance_check CHECK (
    insurance_pno_annual_cents >= 0 AND insurance_pno_annual_cents < 10000000000
  ),
  ADD CONSTRAINT inv_scenarios_condo_fees_check CHECK (
    condo_fees_non_recoverable_cents >= 0 AND condo_fees_non_recoverable_cents < 10000000000
  ),
  ADD CONSTRAINT inv_scenarios_notes_check CHECK (
    notes IS NULL OR char_length(notes) <= 2000
  );

ALTER TABLE public.investment_scenarios ENABLE ROW LEVEL SECURITY;

CREATE POLICY "inv_scenarios_select_own" ON public.investment_scenarios
  FOR SELECT
  USING (landlord_id = auth.uid() AND deleted_at IS NULL);

CREATE POLICY "inv_scenarios_insert_own" ON public.investment_scenarios
  FOR INSERT
  WITH CHECK (landlord_id = auth.uid());

CREATE POLICY "inv_scenarios_update_own" ON public.investment_scenarios
  FOR UPDATE
  USING  (landlord_id = auth.uid() AND deleted_at IS NULL)
  WITH CHECK (landlord_id = auth.uid());

CREATE INDEX idx_public_inv_scenarios_landlord_id ON public.investment_scenarios(landlord_id);

-- Trigger updated_at
CREATE TRIGGER tr_02_set_updated_at_investment_scenarios
  BEFORE UPDATE ON public.investment_scenarios
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- === DEV (dev.investment_scenarios) — mirror ===
CREATE TABLE dev.investment_scenarios (LIKE public.investment_scenarios INCLUDING ALL);

ALTER TABLE dev.investment_scenarios
  DROP CONSTRAINT IF EXISTS investment_scenarios_landlord_id_fkey,
  ADD CONSTRAINT investment_scenarios_landlord_id_fkey
    FOREIGN KEY (landlord_id) REFERENCES dev.landlords(id) ON DELETE CASCADE,
  ALTER COLUMN landlord_id SET DEFAULT auth.uid();

ALTER TABLE dev.investment_scenarios ENABLE ROW LEVEL SECURITY;

CREATE POLICY "inv_scenarios_select_own" ON dev.investment_scenarios
  FOR SELECT
  USING (landlord_id = auth.uid() AND deleted_at IS NULL);

CREATE POLICY "inv_scenarios_insert_own" ON dev.investment_scenarios
  FOR INSERT
  WITH CHECK (landlord_id = auth.uid());

CREATE POLICY "inv_scenarios_update_own" ON dev.investment_scenarios
  FOR UPDATE
  USING  (landlord_id = auth.uid() AND deleted_at IS NULL)
  WITH CHECK (landlord_id = auth.uid());

CREATE TRIGGER tr_02_set_updated_at_investment_scenarios
  BEFORE UPDATE ON dev.investment_scenarios
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

SELECT dev.assert_rls_both_schemas('investment_scenarios');

COMMIT;
