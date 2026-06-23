-- ============================================================================
-- FEAT-014 Phase 3 — Lease enrichment pour conformité location FR
-- ============================================================================
-- WHY : Le formulaire bail actuel ne capture que property_id/tenant_id/dates/
-- rent/charges. Pour matcher la location FR (MVP utilisable), on ajoute :
--   - lease_type (vide/meublé/mobilité/étudiant — impacte durée légale)
--   - deposit_amount_cents (dépôt de garantie)
--   - payment_day (jour échéance mensuelle 1..28)
--   - payment_method (mode paiement attendu — réutilise enum payments)
--   - irl_index_value + irl_quarter_ref (révision annuelle)
--   - agency_fees_cents (honoraires)
--   - solidarity_clause (colocataires solidaires)
--   - entry_inventory_done (état des lieux fait)
--
-- Décisions actées (2026-06-22, validées user) :
--   - lease_type DEFAULT 'unfurnished' (90% des cas) — backward compat
--   - payment_day DEFAULT 1 (le 1er du mois, standard)
--   - payment_method DEFAULT 'virement' (standard FR)
--   - agency_fees_cents DEFAULT 0 (bailleurs particuliers majoritaires)
--   - bool flags DEFAULT false
--   - Reuse enum payments.payment_method (virement/cheque/especes/prelevement/autre)
--   - solidarity_clause sur lease, pas lease_tenants (MVP 1-tenant/lease)
--   - irl_quarter_ref text libre format "T1-2026" (regex strict)
--   - Schémas dual public + dev (mirror obligatoire)
-- ============================================================================

BEGIN;

-- === PROD (public.leases) ===
ALTER TABLE public.leases
  ADD COLUMN lease_type text NOT NULL DEFAULT 'unfurnished',
  ADD COLUMN deposit_amount_cents bigint,
  ADD COLUMN payment_day smallint NOT NULL DEFAULT 1,
  ADD COLUMN payment_method text NOT NULL DEFAULT 'virement',
  ADD COLUMN irl_index_value numeric(8,2),
  ADD COLUMN irl_quarter_ref text,
  ADD COLUMN agency_fees_cents bigint NOT NULL DEFAULT 0,
  ADD COLUMN solidarity_clause boolean NOT NULL DEFAULT false,
  ADD COLUMN entry_inventory_done boolean NOT NULL DEFAULT false;

ALTER TABLE public.leases
  ADD CONSTRAINT leases_lease_type_check CHECK (
    lease_type IN ('unfurnished', 'furnished', 'mobility', 'student')
  ),
  ADD CONSTRAINT leases_deposit_check CHECK (
    deposit_amount_cents IS NULL OR (
      deposit_amount_cents >= 0 AND deposit_amount_cents <= 10000000000
    )
  ),
  ADD CONSTRAINT leases_payment_day_check CHECK (
    payment_day BETWEEN 1 AND 28
  ),
  ADD CONSTRAINT leases_payment_method_check CHECK (
    payment_method IN ('virement', 'cheque', 'especes', 'prelevement', 'autre')
  ),
  ADD CONSTRAINT leases_irl_index_check CHECK (
    irl_index_value IS NULL OR (irl_index_value > 0 AND irl_index_value < 10000)
  ),
  ADD CONSTRAINT leases_irl_quarter_check CHECK (
    irl_quarter_ref IS NULL OR irl_quarter_ref ~ '^T[1-4]-\d{4}$'
  ),
  ADD CONSTRAINT leases_agency_fees_check CHECK (
    agency_fees_cents >= 0 AND agency_fees_cents <= 10000000000
  );

-- === DEV (dev.leases) ===
ALTER TABLE dev.leases
  ADD COLUMN lease_type text NOT NULL DEFAULT 'unfurnished',
  ADD COLUMN deposit_amount_cents bigint,
  ADD COLUMN payment_day smallint NOT NULL DEFAULT 1,
  ADD COLUMN payment_method text NOT NULL DEFAULT 'virement',
  ADD COLUMN irl_index_value numeric(8,2),
  ADD COLUMN irl_quarter_ref text,
  ADD COLUMN agency_fees_cents bigint NOT NULL DEFAULT 0,
  ADD COLUMN solidarity_clause boolean NOT NULL DEFAULT false,
  ADD COLUMN entry_inventory_done boolean NOT NULL DEFAULT false;

ALTER TABLE dev.leases
  ADD CONSTRAINT leases_lease_type_check CHECK (
    lease_type IN ('unfurnished', 'furnished', 'mobility', 'student')
  ),
  ADD CONSTRAINT leases_deposit_check CHECK (
    deposit_amount_cents IS NULL OR (
      deposit_amount_cents >= 0 AND deposit_amount_cents <= 10000000000
    )
  ),
  ADD CONSTRAINT leases_payment_day_check CHECK (
    payment_day BETWEEN 1 AND 28
  ),
  ADD CONSTRAINT leases_payment_method_check CHECK (
    payment_method IN ('virement', 'cheque', 'especes', 'prelevement', 'autre')
  ),
  ADD CONSTRAINT leases_irl_index_check CHECK (
    irl_index_value IS NULL OR (irl_index_value > 0 AND irl_index_value < 10000)
  ),
  ADD CONSTRAINT leases_irl_quarter_check CHECK (
    irl_quarter_ref IS NULL OR irl_quarter_ref ~ '^T[1-4]-\d{4}$'
  ),
  ADD CONSTRAINT leases_agency_fees_check CHECK (
    agency_fees_cents >= 0 AND agency_fees_cents <= 10000000000
  );

-- Vérification défensive RLS toujours actives
SELECT dev.assert_rls_both_schemas('leases');

COMMIT;
