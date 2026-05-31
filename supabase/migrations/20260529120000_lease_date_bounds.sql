-- ============================================================================
-- fix/lease-input-hardening — Contrainte de borne de dates sur leases
-- ============================================================================
-- WHY: La table leases (FEAT-002) n'avait aucune contrainte de borne sur
-- start_date et end_date. Le widget Flutter DatePicker enforçait 2000..2100
-- côté client uniquement. Une requête forgée pouvait donc POST des dates
-- absurdes (ex: '0001-01-01', '9999-12-31') qui polluent les rapports et
-- les futurs PDF quittances (FEAT-007).
--
-- Décision (FEAT-005 audit) :
--   - Borne MIN : 1900-01-01 (couvre tous les baux historiques plausibles)
--   - Borne MAX : 2100-12-31 (loi 1989 : pas de bail > 99 ans en pratique)
--   - end_date reste nullable (NULL = bail reconductible / CDI locatif)
--   - La contrainte end_date > start_date existante (FEAT-002) est conservée
--
-- Idempotence : DROP CONSTRAINT IF EXISTS avant ADD CONSTRAINT —
-- même idiome que le changement de FK landlords_id_fkey en FEAT-002.
-- ============================================================================

BEGIN;

-- ============================================================================
-- PROD (public)
-- ============================================================================

ALTER TABLE public.leases
  DROP CONSTRAINT IF EXISTS leases_date_range_check;

ALTER TABLE public.leases
  ADD CONSTRAINT leases_date_range_check
  CHECK (
    start_date BETWEEN '1900-01-01' AND '2100-12-31'
    AND (end_date IS NULL OR end_date BETWEEN '1900-01-01' AND '2100-12-31')
  );

COMMENT ON CONSTRAINT leases_date_range_check ON public.leases IS
  'Borne de dates : start_date et end_date doivent être entre 1900-01-01 et 2100-12-31. '
  'Garde-fou DB contre les dates absurdes échappant au DatePicker Flutter. '
  'fix/lease-input-hardening (FEAT-005 audit).';

-- ============================================================================
-- DEV (dev) — miroir exact
-- ============================================================================

ALTER TABLE dev.leases
  DROP CONSTRAINT IF EXISTS leases_date_range_check;

ALTER TABLE dev.leases
  ADD CONSTRAINT leases_date_range_check
  CHECK (
    start_date BETWEEN '1900-01-01' AND '2100-12-31'
    AND (end_date IS NULL OR end_date BETWEEN '1900-01-01' AND '2100-12-31')
  );

COMMENT ON CONSTRAINT leases_date_range_check ON dev.leases IS
  'Mirror DEV — même contrainte que public.leases. fix/lease-input-hardening.';

-- ============================================================================
-- Vérification finale (RLS inchangée, on confirme juste qu'elle est toujours là)
-- ============================================================================
SELECT dev.assert_rls_both_schemas('leases');

COMMIT;
