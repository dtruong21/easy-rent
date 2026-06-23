-- ============================================================================
-- FEAT-014 Phase 4 — Payment reference column (FR rental compliance)
-- ============================================================================
-- WHY : Pour le rapprochement comptable et la traçabilité, un bailleur a
-- besoin de noter le numéro de virement / chèque / référence de paiement
-- transmis par le locataire. payment_method capture déjà le moyen
-- (virement/cheque/...), `reference` capture le numéro exact.
--
-- Décisions actées (2026-06-22, validées user) :
--   - 1 seule colonne `reference` text nullable
--   - CHECK length 1..100 (si non NULL)
--   - Backward compat 100% (nullable, aucune migration data)
-- ============================================================================

BEGIN;

-- === PROD (public.payments) ===
ALTER TABLE public.payments
  ADD COLUMN reference text;

ALTER TABLE public.payments
  ADD CONSTRAINT payments_reference_check CHECK (
    reference IS NULL OR char_length(reference) BETWEEN 1 AND 100
  );

-- === DEV (dev.payments) ===
ALTER TABLE dev.payments
  ADD COLUMN reference text;

ALTER TABLE dev.payments
  ADD CONSTRAINT payments_reference_check CHECK (
    reference IS NULL OR char_length(reference) BETWEEN 1 AND 100
  );

-- Vérification défensive RLS toujours actives
SELECT dev.assert_rls_both_schemas('payments');

COMMIT;
