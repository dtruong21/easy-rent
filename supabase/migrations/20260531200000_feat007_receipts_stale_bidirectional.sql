-- ============================================================================
-- FEAT-007 Round 2 — Correction sécurité E5 : trigger is_stale bidirectionnel
-- ============================================================================
-- WHY: La version initiale (20260531172904_feat007_receipts.sql) de la fonction
-- recompute_receipt_stale_on_payment_archive() ne traitait que le cas de
-- soft-delete (NULL → NOT NULL). Si un payment est "ressuscité" (deleted_at
-- NOT NULL → NULL), les receipts liées restaient is_stale = true à jamais.
--
-- Correction : ajout du Cas 2 (résurrection d'un payment) :
--   - Pour chaque receipt incluant le payment ressuscité, recomputer is_stale
--     en regardant si au moins un autre payment_id du receipt est encore
--     soft-deleted (deleted_at IS NOT NULL). Si oui → is_stale reste true.
--     Si tous les payment_ids sont actifs → is_stale = false.
--   - Le payment en cours de résurrection est exclu de la sous-requête car
--     son NEW.deleted_at vient de passer à NULL mais la valeur lue dans la
--     table payments lors du trigger AFTER UPDATE correspond déjà à NEW
--     (le UPDATE est déjà appliqué). On inclut donc le payment directement
--     sans exclusion nécessaire — mais par clarté, la sous-requête exclut
--     explicitement NEW.id avec AND p.id != NEW.id pour éviter la fausse
--     détection d'un deleted_at résiduel sur la ligne en cours.
--
-- Source de l'issue : security-auditor, FEAT-007 Round 2, issue E5 (ÉLEVÉ).
-- Aucune modification de table ni de trigger attaché — uniquement CREATE OR
-- REPLACE FUNCTION (idempotent).
-- ============================================================================

BEGIN;

-- ============================================================================
-- PROD : public.recompute_receipt_stale_on_payment_archive()
-- ============================================================================
-- Remplace la version précédente (Cas 1 uniquement) par la version
-- bidirectionnelle (Cas 1 : soft-delete, Cas 2 : résurrection).
-- SECURITY DEFINER + SET search_path = public : protection contre l'injection
-- de search_path. Bypass RLS intentionnel pour modifier receipts
-- transversalement (tous les bailleurs confondus).

CREATE OR REPLACE FUNCTION public.recompute_receipt_stale_on_payment_archive()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
-- Déclenché AFTER UPDATE OF deleted_at sur public.payments.
-- Deux cas traités :
--
--   Cas 1 : payment soft-deleted (OLD.deleted_at IS NULL → NEW.deleted_at IS NOT NULL)
--     → Marque is_stale = true sur les receipts incluant ce payment.
--     Optimisation : ne touche que les receipts qui n'étaient pas encore stales.
--
--   Cas 2 : payment ressuscité (OLD.deleted_at IS NOT NULL → NEW.deleted_at IS NULL)
--     → Pour chaque receipt incluant ce payment, recompute is_stale :
--       si tous les autres payment_ids du receipt sont actifs (deleted_at IS NULL)
--       alors is_stale passe à false ; sinon is_stale reste true (au moins un
--       autre payment associé est encore soft-deleted).
--     Note : au moment où ce trigger AFTER s'exécute, la ligne payments a déjà
--     été mise à jour — NEW.deleted_at = NULL est effectif dans la table.
--     La sous-requête NOT EXISTS exclut NEW.id pour éviter une auto-détection
--     fantôme si l'état intermédiaire était visible.
BEGIN
  -- Cas 1 : payment vient d'être soft-deleted
  IF OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
    UPDATE public.receipts
      SET is_stale = TRUE
      WHERE payment_ids @> ARRAY[NEW.id]::uuid[]
        AND is_stale = FALSE;
    -- Optimisation : filtre AND is_stale = FALSE pour éviter les UPDATE nuls.
  END IF;

  -- Cas 2 : payment vient d'être ressuscité (résurrection)
  IF OLD.deleted_at IS NOT NULL AND NEW.deleted_at IS NULL THEN
    -- Recompute is_stale pour chaque receipt liée à ce payment.
    -- Une receipt redevient non-stale seulement si TOUS ses payment_ids
    -- sont désormais actifs (aucun autre deleted_at IS NOT NULL).
    UPDATE public.receipts r
      SET is_stale = FALSE
      WHERE r.payment_ids @> ARRAY[NEW.id]::uuid[]
        AND r.is_stale = TRUE
        AND NOT EXISTS (
          SELECT 1 FROM public.payments p
          WHERE p.id = ANY(r.payment_ids)
            AND p.deleted_at IS NOT NULL
            AND p.id != NEW.id   -- exclure le payment en cours de résurrection
                                 -- (son deleted_at est déjà NULL dans la table,
                                 --  exclusion défensive pour la lisibilité)
        );
  END IF;

  RETURN NULL; -- AFTER trigger → valeur de retour ignorée par PostgreSQL
END;
$$;

COMMENT ON FUNCTION public.recompute_receipt_stale_on_payment_archive() IS
  'Trigger AFTER UPDATE OF deleted_at sur public.payments. SECURITY DEFINER + SET search_path=public. '
  'Cas 1 (soft-delete NULL→NOT NULL) : marque is_stale=true sur les receipts dont payment_ids @> ARRAY[NEW.id]. '
  'Cas 2 (résurrection NOT NULL→NULL) : recompute is_stale=false pour les receipts où tous les payment_ids '
  'sont actifs (aucun deleted_at IS NOT NULL parmi les autres payment_ids). '
  'Index GIN idx_public_receipts_payment_ids_gin rend l''opérateur @> performant. '
  'Correction issue E5 security-auditor (FEAT-007 Round 2).';

-- ============================================================================
-- DEV : dev.recompute_receipt_stale_on_payment_archive() — miroir exact
-- ============================================================================

CREATE OR REPLACE FUNCTION dev.recompute_receipt_stale_on_payment_archive()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = dev
AS $$
BEGIN
  -- Cas 1 : payment soft-deleted (NULL → NOT NULL)
  IF OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
    UPDATE dev.receipts
      SET is_stale = TRUE
      WHERE payment_ids @> ARRAY[NEW.id]::uuid[]
        AND is_stale = FALSE;
  END IF;

  -- Cas 2 : payment ressuscité (NOT NULL → NULL)
  IF OLD.deleted_at IS NOT NULL AND NEW.deleted_at IS NULL THEN
    UPDATE dev.receipts r
      SET is_stale = FALSE
      WHERE r.payment_ids @> ARRAY[NEW.id]::uuid[]
        AND r.is_stale = TRUE
        AND NOT EXISTS (
          SELECT 1 FROM dev.payments p
          WHERE p.id = ANY(r.payment_ids)
            AND p.deleted_at IS NOT NULL
            AND p.id != NEW.id
        );
  END IF;

  RETURN NULL;
END;
$$;

COMMENT ON FUNCTION dev.recompute_receipt_stale_on_payment_archive() IS
  'Mirror DEV de public.recompute_receipt_stale_on_payment_archive(). '
  'Bidirectionnel : soft-delete (Cas 1) et résurrection (Cas 2). '
  'Correction issue E5 security-auditor (FEAT-007 Round 2).';

-- ============================================================================
-- Vérification : les triggers attachés sont déjà corrects et n'ont pas besoin
-- d'être recréés. Le trigger AFTER UPDATE OF deleted_at couvre les deux
-- directions (NULL→NOT NULL et NOT NULL→NULL) sans modification.
-- tr_03_set_receipt_stale_on_payment_archive sur public.payments : INCHANGÉ
-- tr_03_set_receipt_stale_on_payment_archive sur dev.payments    : INCHANGÉ
-- ============================================================================

COMMIT;
