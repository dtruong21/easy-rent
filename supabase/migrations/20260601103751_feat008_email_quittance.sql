-- ============================================================================
-- FEAT-008 — Envoyer une quittance par email (Resend)
-- Migration : ajout colonnes sent_at / sent_to_email + trigger protection
--             + RPC mark_receipt_as_sent (public + dev)
-- ============================================================================
-- WHY: Permet de tracer l'envoi email d'une quittance (audit légal) et de
-- protéger ces colonnes d'audit contre toute écriture directe côté client.
-- Seule la RPC mark_receipt_as_sent (appelée par l'Edge Function send-receipt
-- après confirmation d'envoi Resend) peut modifier ces colonnes.
--
-- Décisions actées (source: docs/plans/FEAT-008-email-quittance.md) :
--   D1=A (bloquer si tenant sans email — vérifié côté Edge Function)
--   D2=B (renvoi avec confirmation UI — idempotent côté DB, sent_at écrasé)
--   D3=B (pas de reply-to)
--   D4=B (HTML minimal)
--   D5=A (429 explicite, pas de queue)
--
-- Colonnes ajoutées :
--   - sent_at timestamptz NULL     : NULL = jamais envoyé (audit trail)
--   - sent_to_email text NULL       : email destination au moment de l'envoi
--                                    (snapshot RGPD — figé même si tenant change)
--
-- Contrainte sent_consistency : les deux colonnes sont NULL ensemble ou
-- non-NULL ensemble (cohérence d'état). CHECK dédié (pattern receipts_voiding_consistency).
--
-- Protection trigger : tr_01b_protect_sent_columns_receipts BEFORE UPDATE
-- bloque toute modification directe de sent_at / sent_to_email sauf via
-- le flag de session GUC app.allow_sent_columns_change = '1' posé par la RPC.
--
-- RPC mark_receipt_as_sent : SECURITY DEFINER, vérifie ownership + is_voided +
-- is_stale, pose le flag GUC, UPDATE, RETURN receipts. Idempotent (renvoi écrase).
--
-- Dépendances :
--   FEAT-007 (table receipts, pattern void_receipt, pattern GUC app.allow_deleted_at_change)
--   FEAT-002 (pattern RPC SECURITY DEFINER, REVOKE/GRANT)
--
-- Note dette technique (pattern GUC) :
--   Le mécanisme GUC app.allow_sent_columns_change = '1' est cohérent avec
--   l'existant (app.allow_deleted_at_change). Voir docs/SECURITY.md §Patterns sensibles.
--   Hardening P1 : remplacer par un mécanisme intransférable (pg_trigger_depth).
-- ============================================================================

BEGIN;

-- ============================================================================
-- Section 1 : Colonnes sent_at / sent_to_email sur public.receipts (PROD)
-- ============================================================================

ALTER TABLE public.receipts
  ADD COLUMN IF NOT EXISTS sent_at        timestamptz NULL,
  ADD COLUMN IF NOT EXISTS sent_to_email  text        NULL;

COMMENT ON COLUMN public.receipts.sent_at IS
  'Horodatage du dernier envoi email de cette quittance au locataire. '
  'NULL = jamais envoyé. Mis à jour par RPC mark_receipt_as_sent uniquement. '
  'Audit trail email — conformité loi 1989 art. 21 + RGPD. FEAT-008.';

COMMENT ON COLUMN public.receipts.sent_to_email IS
  'Adresse email de destination au moment de l''envoi (snapshot audit). '
  'Figée même si l''email du locataire change ultérieurement. '
  'NULL si et seulement si sent_at IS NULL (cohérence garantie par CHECK receipts_sent_consistency). '
  'Masquée côté UI (RGPD : premier char + 3 étoiles + domaine). FEAT-008.';

-- Contrainte de cohérence : sent_at et sent_to_email sont tous les deux NULL
-- ou tous les deux non-NULL. Complément : longueur email 3..255 si non-NULL.
ALTER TABLE public.receipts
  ADD CONSTRAINT receipts_sent_consistency CHECK (
    (sent_at IS NULL AND sent_to_email IS NULL)
    OR
    (sent_at IS NOT NULL AND sent_to_email IS NOT NULL
       AND char_length(sent_to_email) BETWEEN 3 AND 255)
  );

-- ============================================================================
-- Section 2 : Colonnes sent_at / sent_to_email sur dev.receipts (DEV)
-- ============================================================================

ALTER TABLE dev.receipts
  ADD COLUMN IF NOT EXISTS sent_at        timestamptz NULL,
  ADD COLUMN IF NOT EXISTS sent_to_email  text        NULL;

COMMENT ON COLUMN dev.receipts.sent_at IS
  'Mirror DEV de public.receipts.sent_at. Audit trail email. FEAT-008.';

COMMENT ON COLUMN dev.receipts.sent_to_email IS
  'Mirror DEV de public.receipts.sent_to_email. Snapshot email destination. FEAT-008.';

ALTER TABLE dev.receipts
  ADD CONSTRAINT receipts_sent_consistency CHECK (
    (sent_at IS NULL AND sent_to_email IS NULL)
    OR
    (sent_at IS NOT NULL AND sent_to_email IS NOT NULL
       AND char_length(sent_to_email) BETWEEN 3 AND 255)
  );

-- ============================================================================
-- Section 3 : Fonction trigger protect_sent_columns_receipts (PROD)
-- ============================================================================
-- WHY trigger DÉDIÉ (pas une extension de prevent_protected_columns_change) :
-- prevent_protected_columns_change est partagé par 6 tables — y ajouter
-- une logique spécifique receipts en ferait une God Function fragile.
-- Trigger dédié tr_01b (ordre alphabétique : entre tr_01 et tr_02) BEFORE UPDATE.
--
-- Mécanisme GUC (pattern identique à app.allow_deleted_at_change, FEAT-002) :
--   - set_config('app.allow_sent_columns_change', '1', true) = scope transaction locale
--   - La RPC mark_receipt_as_sent est la seule autorisée à poser ce flag
--   - Les deux arguments de set_config sont des littéraux hardcodés (règle SECURITY.md §3)
--
-- Dette hardening P1 : remplacer le pattern GUC par un mécanisme basé sur
-- pg_trigger_depth() ou un role dédié pour éviter la surface d'attaque GUC.
-- Tracké dans docs/BACKLOG.md (dette technique post-FEAT-008).

CREATE OR REPLACE FUNCTION public.protect_sent_columns_receipts()
RETURNS trigger
LANGUAGE plpgsql
AS $$
-- Trigger BEFORE UPDATE sur public.receipts.
-- Bloque toute modification directe de sent_at ou sent_to_email sauf si le
-- flag de session app.allow_sent_columns_change = '1' est posé (scope transaction).
-- Ce flag est posé exclusivement par la RPC SECURITY DEFINER mark_receipt_as_sent.
--
-- ERRCODE 42501 (insufficient_privilege) : cohérent avec prevent_protected_columns_change.
--
-- Note : ce trigger ne s'exécute QU'à l'UPDATE (BEFORE UPDATE uniquement).
-- À l'INSERT, sent_at et sent_to_email valent NULL par défaut — pas de protection
-- nécessaire (le CHECK receipts_sent_consistency bloque les valeurs incohérentes).
DECLARE
  allow_flag text := current_setting('app.allow_sent_columns_change', true);
BEGIN
  IF allow_flag IS DISTINCT FROM '1' THEN
    IF NEW.sent_at IS DISTINCT FROM OLD.sent_at THEN
      RAISE EXCEPTION 'sent_at is protected — use mark_receipt_as_sent RPC'
        USING ERRCODE = '42501';
    END IF;
    IF NEW.sent_to_email IS DISTINCT FROM OLD.sent_to_email THEN
      RAISE EXCEPTION 'sent_to_email is protected — use mark_receipt_as_sent RPC'
        USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.protect_sent_columns_receipts() IS
  'Trigger BEFORE UPDATE sur public.receipts. '
  'Bloque toute modification directe de sent_at / sent_to_email sauf si le flag '
  'de session GUC app.allow_sent_columns_change = ''1'' est posé (scope transaction). '
  'Ce flag est posé exclusivement par la RPC mark_receipt_as_sent (SECURITY DEFINER). '
  'ERRCODE 42501 (insufficient_privilege). '
  'Trigger nommé tr_01b pour s''intercaler entre tr_01 et tr_02 dans l''ordre alpha PG. '
  'Dette hardening P1 : migrer vers pg_trigger_depth() (docs/SECURITY.md). '
  'FEAT-008.';

DROP TRIGGER IF EXISTS tr_01b_protect_sent_columns_receipts ON public.receipts;
CREATE TRIGGER tr_01b_protect_sent_columns_receipts
  BEFORE UPDATE ON public.receipts
  FOR EACH ROW EXECUTE FUNCTION public.protect_sent_columns_receipts();

-- ============================================================================
-- Section 4 : Fonction trigger protect_sent_columns_receipts (DEV)
-- ============================================================================

CREATE OR REPLACE FUNCTION dev.protect_sent_columns_receipts()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  allow_flag text := current_setting('app.allow_sent_columns_change', true);
BEGIN
  IF allow_flag IS DISTINCT FROM '1' THEN
    IF NEW.sent_at IS DISTINCT FROM OLD.sent_at THEN
      RAISE EXCEPTION 'sent_at is protected — use mark_receipt_as_sent RPC'
        USING ERRCODE = '42501';
    END IF;
    IF NEW.sent_to_email IS DISTINCT FROM OLD.sent_to_email THEN
      RAISE EXCEPTION 'sent_to_email is protected — use mark_receipt_as_sent RPC'
        USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION dev.protect_sent_columns_receipts() IS
  'Mirror DEV de public.protect_sent_columns_receipts(). FEAT-008.';

DROP TRIGGER IF EXISTS tr_01b_protect_sent_columns_receipts ON dev.receipts;
CREATE TRIGGER tr_01b_protect_sent_columns_receipts
  BEFORE UPDATE ON dev.receipts
  FOR EACH ROW EXECUTE FUNCTION dev.protect_sent_columns_receipts();

-- ============================================================================
-- Section 5 : RPC mark_receipt_as_sent (PROD — public schema)
-- ============================================================================
-- WHY SECURITY DEFINER plutôt qu'UPDATE direct :
--   1. Pas de policy UPDATE sur receipts (immuabilité document) — on ne veut
--      pas ouvrir un trou par "policy UPDATE conditionnelle".
--   2. La RPC fait ownership + void + stale checks dans la même transaction (atomique).
--   3. La RPC est le seul chemin pouvant poser app.allow_sent_columns_change = '1'.
--   4. Cohérence avec void_receipt() et soft_delete_*() (pattern unique du projet).
--
-- Comportement idempotent (D2=B renvoi) : si la quittance a déjà été envoyée,
-- sent_at et sent_to_email sont ÉCRASÉS avec la nouvelle valeur. Cela permet
-- le renvoi après confirmation UI sans ambiguïté.
--
-- Checks dans l'ordre :
--   1. Validation format email (longueur + regex) → ERRCODE 22023
--   2. UPDATE avec WHERE landlord_id = auth.uid() + is_voided = false + is_stale = false
--      → NOT FOUND si cross-user / voided / stale (pas de fuite d'info)
--
-- Note : le check "voided_at IS NULL" est implicite dans is_voided = false
-- (contrainte receipts_voiding_consistency garantit la cohérence).

CREATE OR REPLACE FUNCTION public.mark_receipt_as_sent(
  p_receipt_id   uuid,
  p_sent_to_email text
)
RETURNS public.receipts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
-- RPC SECURITY DEFINER : contourne l'absence de policy UPDATE sur public.receipts.
-- Ownership check dans le WHERE (landlord_id = auth.uid()) : cross-user invisible.
-- SET search_path = public, pg_temp : évite tout override malveillant du search_path.
-- REVOKE ALL FROM PUBLIC + GRANT TO authenticated : anon ne peut jamais appeler.
DECLARE
  result public.receipts;
BEGIN
  -- Validation 1 : email non nul et longueur 3..255
  IF p_sent_to_email IS NULL OR char_length(p_sent_to_email) NOT BETWEEN 3 AND 255 THEN
    RAISE EXCEPTION 'sent_to_email must be between 3 and 255 characters'
      USING ERRCODE = '22023';  -- invalid_parameter_value
  END IF;

  -- Validation 2 : format email basique (idem regex tenants.email — FEAT-002)
  IF p_sent_to_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN
    RAISE EXCEPTION 'sent_to_email format is invalid (must match ^[^@\s]+@[^@\s]+\.[^@\s]+$)'
      USING ERRCODE = '22023';  -- invalid_parameter_value
  END IF;

  -- Poser le flag GUC pour autoriser le trigger tr_01b à laisser passer l'UPDATE.
  -- true = scope local-transaction (pas de fuite entre connexions).
  -- Les deux arguments sont des LITTÉRAUX hardcodés (règle SECURITY.md §3).
  PERFORM set_config('app.allow_sent_columns_change', '1', true);

  UPDATE public.receipts
    SET
      sent_at        = now(),
      sent_to_email  = p_sent_to_email
    WHERE id           = p_receipt_id
      AND landlord_id  = auth.uid()         -- ownership : cross-user invisible
      AND is_voided    = false              -- voided → erreur NOT FOUND (pas de fuite)
      AND is_stale     = false             -- stale → erreur NOT FOUND (pas de fuite)
  RETURNING * INTO result;

  IF NOT FOUND THEN
    -- Pas de distinction voided/stale/cross-user/inexistant — information leak évité.
    RAISE EXCEPTION 'receipt not found, voided, stale, or not owned by caller'
      USING ERRCODE = 'P0002';  -- no_data_found
  END IF;

  RETURN result;
END;
$$;

COMMENT ON FUNCTION public.mark_receipt_as_sent(uuid, text) IS
  'RPC SECURITY DEFINER : marque une quittance comme envoyée par email. '
  'Valide format email (longueur 3-255 + regex, ERRCODE 22023). '
  'Vérifie ownership (landlord_id = auth.uid()), is_voided = false, is_stale = false '
  '→ P0002 (no_data_found) si non satisfait (pas de fuite d''info). '
  'Pose SET LOCAL app.allow_sent_columns_change = ''1'' pour contourner le trigger '
  'tr_01b_protect_sent_columns_receipts. Idempotent : 2e appel écrase sent_at/sent_to_email '
  '(cas du renvoi D2=B). REVOKE ALL FROM PUBLIC → anon exclut. FEAT-008.';

REVOKE ALL ON FUNCTION public.mark_receipt_as_sent(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_receipt_as_sent(uuid, text) TO authenticated;

-- ============================================================================
-- Section 6 : RPC mark_receipt_as_sent (DEV — dev schema)
-- ============================================================================
-- Mirror exact de la version public, opère sur dev.receipts.
-- SET search_path = dev, pg_temp : isolation schema DEV.

CREATE OR REPLACE FUNCTION dev.mark_receipt_as_sent(
  p_receipt_id   uuid,
  p_sent_to_email text
)
RETURNS dev.receipts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = dev, pg_temp
AS $$
DECLARE
  result dev.receipts;
BEGIN
  IF p_sent_to_email IS NULL OR char_length(p_sent_to_email) NOT BETWEEN 3 AND 255 THEN
    RAISE EXCEPTION 'sent_to_email must be between 3 and 255 characters'
      USING ERRCODE = '22023';
  END IF;

  IF p_sent_to_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN
    RAISE EXCEPTION 'sent_to_email format is invalid (must match ^[^@\s]+@[^@\s]+\.[^@\s]+$)'
      USING ERRCODE = '22023';
  END IF;

  PERFORM set_config('app.allow_sent_columns_change', '1', true);

  UPDATE dev.receipts
    SET
      sent_at        = now(),
      sent_to_email  = p_sent_to_email
    WHERE id           = p_receipt_id
      AND landlord_id  = auth.uid()
      AND is_voided    = false
      AND is_stale     = false
  RETURNING * INTO result;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'receipt not found, voided, stale, or not owned by caller'
      USING ERRCODE = 'P0002';
  END IF;

  RETURN result;
END;
$$;

COMMENT ON FUNCTION dev.mark_receipt_as_sent(uuid, text) IS
  'Mirror DEV de public.mark_receipt_as_sent(). Opère sur dev.receipts. FEAT-008.';

REVOKE ALL ON FUNCTION dev.mark_receipt_as_sent(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION dev.mark_receipt_as_sent(uuid, text) TO authenticated;

-- ============================================================================
-- Section 7 : Vérification finale RLS sur les deux schémas
-- ============================================================================
-- RLS a été activée en FEAT-007 et n'a pas changé dans cette migration.
-- On rappelle la vérification pour idempotence (pattern toutes migrations).
SELECT dev.assert_rls_both_schemas('receipts');

COMMIT;
