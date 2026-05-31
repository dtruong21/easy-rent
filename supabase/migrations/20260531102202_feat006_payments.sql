-- ============================================================================
-- FEAT-006 — Enregistrer un paiement de loyer
-- ============================================================================
-- WHY: Permet au bailleur de saisir les paiements mensuels d'un bail (CRUD +
-- soft-delete). Débloquera FEAT-007 (quittance PDF) qui lira directement
-- payments.rent_amount_cents / charges_amount_cents (loi 1989 art. 21).
--
-- Dépendances : FEAT-002 (schéma + pattern RLS + prevent_protected_columns_change
-- + set_updated_at), FEAT-005 (leases = entité pivot).
--
-- Décisions actées (source: docs/plans/FEAT-006-payment-record.md, 2026-05-31) :
--   - landlord_id dénormalisé pour RLS directe sans jointure (pattern leases)
--   - Pas de CHECK haut sur les montants (autorise trop-perçu — décision produit)
--   - Pas de UNIQUE sur (lease_id, period_start, period_end) : doublons autorisés
--   - Le trigger tr_00 ne vérifie PAS le statut du bail (active/terminated/archived)
--     → paiement rétroactif sur bail clôturé autorisé au niveau DB (cas légitimes :
--     régularisation, dernière mensualité après clôture). La règle "bail clôturé →
--     bouton désactivé" est purement frontend.
--   - Pas de policy DELETE : soft-delete via RPC uniquement
--   - prevent_protected_columns_change() réutilisée SANS duplication (FEAT-002)
--   - Bornes date 1900–2100 intégrées dès la création (leçon FEAT-005 hardening)
-- ============================================================================

BEGIN;

-- ============================================================================
-- Section 1 : Fonctions de cohérence cross-FK (ownership lease → payment)
-- ============================================================================
-- WHY: Garantit que le lease_id référencé existe et appartient au même landlord
-- que le paiement. Défense en profondeur indépendante de RLS (résiste à une
-- erreur de policy). Pattern identique à assert_lease_ownership_consistency().
-- SECURITY DEFINER : bypass RLS pour voir toutes les lignes de leases (y compris
-- d'autres landlords) afin de détecter les tentatives de cross-ownership.
-- SET search_path = public|dev : fixe le search_path contre tout override.

-- ---- PROD ----
CREATE OR REPLACE FUNCTION public.assert_payment_lease_ownership()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
-- SECURITY DEFINER : s'exécute avec les droits de postgres, bypasse RLS sur
-- public.leases. Intentionnel : on veut voir TOUTES les lignes pour valider la
-- cohérence cross-FK, même les leases d'autres landlords (c'est exactement ce
-- qu'on cherche à détecter pour bloquer). Sans SECURITY DEFINER, un SELECT sur
-- public.leases avec le rôle authenticated renverrait NULL pour les leases
-- non visibles par RLS — rendant le message d'erreur trompeur.
-- SET search_path = public : évite tout override malveillant du search_path.
DECLARE
  lease_landlord uuid;
BEGIN
  -- Cas 1 : lease_id inexistant
  SELECT landlord_id INTO lease_landlord
    FROM public.leases WHERE id = NEW.lease_id;

  IF lease_landlord IS NULL AND NOT EXISTS (
    SELECT 1 FROM public.leases WHERE id = NEW.lease_id
  ) THEN
    RAISE EXCEPTION 'Payment references a non-existent lease_id (%)',
      NEW.lease_id
      USING ERRCODE = '23514';
  END IF;

  -- Cas 2 : ownership mismatch — le bail appartient à un autre landlord
  IF lease_landlord IS DISTINCT FROM NEW.landlord_id THEN
    RAISE EXCEPTION 'Ownership mismatch: lease_id (%) belongs to landlord %, but payment.landlord_id is %',
      NEW.lease_id, lease_landlord, NEW.landlord_id
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.assert_payment_lease_ownership() IS
  'Trigger BEFORE INSERT OR UPDATE sur public.payments. SECURITY DEFINER + SET search_path=public. '
  'Vérifie 2 cas : lease_id inexistant, ownership mismatch (lease appartient à un landlord '
  'différent de payment.landlord_id). ERRCODE 23514 (check_violation). '
  'Ne vérifie PAS le statut du bail (paiement rétroactif sur bail clôturé autorisé — '
  'cas légitimes : régularisation, dernière mensualité après clôture). FEAT-006.';

-- ---- DEV ----
CREATE OR REPLACE FUNCTION dev.assert_payment_lease_ownership()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = dev
AS $$
-- SECURITY DEFINER + SET search_path = dev : miroir exact de public.assert_payment_lease_ownership()
-- mais opère sur le schéma dev. Lit dev.leases.
DECLARE
  lease_landlord uuid;
BEGIN
  -- Cas 1 : lease_id inexistant
  SELECT landlord_id INTO lease_landlord
    FROM dev.leases WHERE id = NEW.lease_id;

  IF lease_landlord IS NULL AND NOT EXISTS (
    SELECT 1 FROM dev.leases WHERE id = NEW.lease_id
  ) THEN
    RAISE EXCEPTION 'Payment references a non-existent lease_id (%)',
      NEW.lease_id
      USING ERRCODE = '23514';
  END IF;

  -- Cas 2 : ownership mismatch
  IF lease_landlord IS DISTINCT FROM NEW.landlord_id THEN
    RAISE EXCEPTION 'Ownership mismatch: lease_id (%) belongs to landlord %, but payment.landlord_id is %',
      NEW.lease_id, lease_landlord, NEW.landlord_id
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION dev.assert_payment_lease_ownership() IS
  'Mirror DEV de public.assert_payment_lease_ownership(). SECURITY DEFINER + SET search_path=dev. '
  'Lit dev.leases. FEAT-006.';

-- ============================================================================
-- Section 2 : Table public.payments (PROD)
-- ============================================================================
-- Paiements mensuels d'un bail. landlord_id dénormalisé pour simplifier les
-- policies RLS (landlord_id = auth.uid() sans jointure sur leases).
-- FK sur leases RESTRICT : on ne peut pas supprimer un bail qui a des paiements.
-- Montants en centimes d'euro (pas de float — évite les erreurs d'arrondi).
-- Bornes date 1900–2100 : intégrées dès la création (leçon FEAT-005 hardening).

CREATE TABLE public.payments (
  id                    uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  lease_id              uuid        NOT NULL REFERENCES public.leases(id)    ON DELETE RESTRICT,
  landlord_id           uuid        NOT NULL REFERENCES public.landlords(id) ON DELETE RESTRICT,
  -- Période couverte par ce paiement
  period_start          date        NOT NULL
                                    CHECK (period_start BETWEEN '1900-01-01' AND '2100-12-31'),
  period_end            date        NOT NULL
                                    CHECK (
                                      period_end > period_start
                                      AND period_end BETWEEN '1900-01-01' AND '2100-12-31'
                                    ),
  -- Date de réception effective du paiement (autorisée dans le futur : prélèvement programmé)
  paid_at               date        NOT NULL
                                    CHECK (paid_at BETWEEN '1900-01-01' AND '2100-12-31'),
  -- Loyer hors charges en centimes. Ex: 85000 = 850,00 €
  rent_amount_cents     integer     NOT NULL CHECK (rent_amount_cents > 0),
  -- Charges en centimes. 0 si incluses ou absentes.
  charges_amount_cents  integer     NOT NULL DEFAULT 0 CHECK (charges_amount_cents >= 0),
  -- Mode de paiement : enum SQL
  payment_method        text        NOT NULL
                                    CHECK (payment_method IN (
                                      'virement', 'cheque', 'especes', 'prelevement', 'autre'
                                    )),
  -- Note libre (max 500 caractères) — peut rester NULL
  notes                 text        CHECK (notes IS NULL OR char_length(notes) <= 500),
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  -- Soft-delete : modifiable uniquement via RPC soft_delete_payment()
  deleted_at            timestamptz
);

COMMENT ON TABLE  public.payments IS
  'Paiements mensuels des baux. landlord_id dénormalisé pour simplifier RLS. '
  'Soft-delete via deleted_at (RPC uniquement). FEAT-006.';
COMMENT ON COLUMN public.payments.lease_id IS
  'Bail rattaché. FK RESTRICT : impossible de supprimer un bail avec des paiements.';
COMMENT ON COLUMN public.payments.landlord_id IS
  'Propriétaire (dénormalisé). Garanti cohérent avec lease.landlord_id par trigger tr_00.';
COMMENT ON COLUMN public.payments.period_start IS
  'Début de la période couverte. Bornes 1900-01-01..2100-12-31.';
COMMENT ON COLUMN public.payments.period_end IS
  'Fin de la période couverte. > period_start. Bornes 1900-01-01..2100-12-31.';
COMMENT ON COLUMN public.payments.paid_at IS
  'Date de réception du paiement. Autorisée dans le futur (prélèvement programmé). '
  'Bornes 1900-01-01..2100-12-31.';
COMMENT ON COLUMN public.payments.rent_amount_cents IS
  'Loyer HC en centimes d''euro. > 0. Ex: 85000 = 850,00 €. Pas de plafond haut '
  '(trop-perçu autorisé — décision produit FEAT-006).';
COMMENT ON COLUMN public.payments.charges_amount_cents IS
  'Charges en centimes d''euro. >= 0. 0 si incluses dans le loyer ou absentes.';
COMMENT ON COLUMN public.payments.payment_method IS
  'Enum SQL : virement, cheque, especes, prelevement, autre.';
COMMENT ON COLUMN public.payments.notes IS
  'Note libre. Nullable. Max 500 caractères (CHECK SQL).';
COMMENT ON COLUMN public.payments.deleted_at IS
  'Soft-delete RGPD/rétention. Protégé par trigger tr_01. '
  'Modifiable uniquement via soft_delete_payment(). FEAT-006.';

-- ---- RLS ----
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;

-- SELECT : uniquement les paiements actifs (non supprimés) du landlord courant
CREATE POLICY "payments_select_own" ON public.payments
  FOR SELECT
  USING (landlord_id = auth.uid() AND deleted_at IS NULL);

-- INSERT : le client ne peut insérer que ses propres paiements
-- (le trigger tr_00 valide ensuite la cohérence lease_id → landlord_id)
CREATE POLICY "payments_insert_own" ON public.payments
  FOR INSERT
  WITH CHECK (landlord_id = auth.uid());

-- UPDATE : uniquement les paiements actifs du landlord courant
CREATE POLICY "payments_update_own" ON public.payments
  FOR UPDATE
  USING  (landlord_id = auth.uid() AND deleted_at IS NULL)
  WITH CHECK (landlord_id = auth.uid());

-- Aucune policy DELETE : suppression physique interdite côté client.

-- ---- Index ----
-- FK landlord_id : filtrage RLS (auth.uid())
CREATE INDEX idx_public_payments_landlord_id ON public.payments(landlord_id);
-- FK lease_id : listage paiements d'un bail
CREATE INDEX idx_public_payments_lease_id    ON public.payments(lease_id);
-- Tri liste paiements par période décroissante (dashboard bail)
CREATE INDEX idx_public_payments_period_start_desc
  ON public.payments(lease_id, period_start DESC);
-- Vue active : paiements non supprimés d'un bail (requête la plus fréquente)
CREATE INDEX idx_public_payments_active_partial
  ON public.payments(lease_id)
  WHERE deleted_at IS NULL;

-- ---- Triggers ----
-- tr_00 : validation ownership lease → payment (SECURITY DEFINER, voir Section 1)
DROP TRIGGER IF EXISTS tr_00_assert_payment_lease_ownership ON public.payments;
CREATE TRIGGER tr_00_assert_payment_lease_ownership
  BEFORE INSERT OR UPDATE ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.assert_payment_lease_ownership();

-- tr_01 : protection deleted_at / created_at (réutilise FEAT-002, PAS de duplication)
DROP TRIGGER IF EXISTS tr_01_prevent_protected_columns_change_payments ON public.payments;
CREATE TRIGGER tr_01_prevent_protected_columns_change_payments
  BEFORE INSERT OR UPDATE ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.prevent_protected_columns_change();

-- tr_02 : mise à jour auto de updated_at (réutilise FEAT-002)
DROP TRIGGER IF EXISTS tr_02_set_updated_at_payments ON public.payments;
CREATE TRIGGER tr_02_set_updated_at_payments
  BEFORE UPDATE ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ============================================================================
-- Section 3 : Table dev.payments (DEV) — miroir exact
-- ============================================================================

CREATE TABLE dev.payments (
  id                    uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  lease_id              uuid        NOT NULL REFERENCES dev.leases(id)    ON DELETE RESTRICT,
  landlord_id           uuid        NOT NULL REFERENCES dev.landlords(id) ON DELETE RESTRICT,
  period_start          date        NOT NULL
                                    CHECK (period_start BETWEEN '1900-01-01' AND '2100-12-31'),
  period_end            date        NOT NULL
                                    CHECK (
                                      period_end > period_start
                                      AND period_end BETWEEN '1900-01-01' AND '2100-12-31'
                                    ),
  paid_at               date        NOT NULL
                                    CHECK (paid_at BETWEEN '1900-01-01' AND '2100-12-31'),
  rent_amount_cents     integer     NOT NULL CHECK (rent_amount_cents > 0),
  charges_amount_cents  integer     NOT NULL DEFAULT 0 CHECK (charges_amount_cents >= 0),
  payment_method        text        NOT NULL
                                    CHECK (payment_method IN (
                                      'virement', 'cheque', 'especes', 'prelevement', 'autre'
                                    )),
  notes                 text        CHECK (notes IS NULL OR char_length(notes) <= 500),
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  deleted_at            timestamptz
);

COMMENT ON TABLE  dev.payments IS 'Mirror DEV de public.payments. FEAT-006.';
COMMENT ON COLUMN dev.payments.deleted_at IS
  'Soft-delete. Protégé par trigger tr_01. Modifiable uniquement via dev.soft_delete_payment().';

-- ---- RLS DEV ----
ALTER TABLE dev.payments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "payments_select_own" ON dev.payments
  FOR SELECT
  USING (landlord_id = auth.uid() AND deleted_at IS NULL);

CREATE POLICY "payments_insert_own" ON dev.payments
  FOR INSERT
  WITH CHECK (landlord_id = auth.uid());

CREATE POLICY "payments_update_own" ON dev.payments
  FOR UPDATE
  USING  (landlord_id = auth.uid() AND deleted_at IS NULL)
  WITH CHECK (landlord_id = auth.uid());

-- ---- Index DEV ----
CREATE INDEX idx_dev_payments_landlord_id ON dev.payments(landlord_id);
CREATE INDEX idx_dev_payments_lease_id    ON dev.payments(lease_id);
CREATE INDEX idx_dev_payments_period_start_desc
  ON dev.payments(lease_id, period_start DESC);
CREATE INDEX idx_dev_payments_active_partial
  ON dev.payments(lease_id)
  WHERE deleted_at IS NULL;

-- ---- Triggers DEV ----
DROP TRIGGER IF EXISTS tr_00_assert_payment_lease_ownership ON dev.payments;
CREATE TRIGGER tr_00_assert_payment_lease_ownership
  BEFORE INSERT OR UPDATE ON dev.payments
  FOR EACH ROW EXECUTE FUNCTION dev.assert_payment_lease_ownership();

DROP TRIGGER IF EXISTS tr_01_prevent_protected_columns_change_payments ON dev.payments;
CREATE TRIGGER tr_01_prevent_protected_columns_change_payments
  BEFORE INSERT OR UPDATE ON dev.payments
  FOR EACH ROW EXECUTE FUNCTION public.prevent_protected_columns_change();

DROP TRIGGER IF EXISTS tr_02_set_updated_at_payments ON dev.payments;
CREATE TRIGGER tr_02_set_updated_at_payments
  BEFORE UPDATE ON dev.payments
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ============================================================================
-- Section 4 : RPC SECURITY DEFINER — soft_delete_payment
-- ============================================================================
-- WHY SECURITY DEFINER: Le trigger tr_01 bloque toute modification de deleted_at
-- via UPDATE direct. La RPC pose app.allow_deleted_at_change = '1' (SET LOCAL =
-- scope transaction) avant l'UPDATE, déverrouillant le trigger pour cette seule
-- transaction. Ownership check (landlord_id = auth.uid() AND deleted_at IS NULL)
-- dans le WHERE : un User A ne peut pas soft-delete les paiements de User B —
-- le NOT FOUND est retourné (pas de fuite d'information sur l'existence de la ligne).
-- REVOKE ALL + GRANT authenticated : principle of least privilege.

-- ---- PROD ----
CREATE OR REPLACE FUNCTION public.soft_delete_payment(p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM set_config('app.allow_deleted_at_change', '1', true);
  UPDATE public.payments
    SET deleted_at = now()
    WHERE id = p_id
      AND landlord_id = auth.uid()
      AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Payment not found or already deleted'
      USING ERRCODE = 'P0002';
  END IF;
END;
$$;

COMMENT ON FUNCTION public.soft_delete_payment(uuid) IS
  'RPC SECURITY DEFINER : soft-delete d''un paiement (vérifie ownership landlord_id = auth.uid()). '
  'Pose SET LOCAL app.allow_deleted_at_change=1 pour contourner trigger tr_01. '
  'NOT FOUND si paiement inexistant, appartenant à un autre user, ou déjà supprimé '
  '(pas de fuite d''information). Pas de hard-delete. FEAT-006.';

REVOKE ALL ON FUNCTION public.soft_delete_payment(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.soft_delete_payment(uuid) TO authenticated;

-- ---- DEV ----
CREATE OR REPLACE FUNCTION dev.soft_delete_payment(p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = dev
AS $$
BEGIN
  PERFORM set_config('app.allow_deleted_at_change', '1', true);
  UPDATE dev.payments
    SET deleted_at = now()
    WHERE id = p_id
      AND landlord_id = auth.uid()
      AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Payment not found or already deleted'
      USING ERRCODE = 'P0002';
  END IF;
END;
$$;

COMMENT ON FUNCTION dev.soft_delete_payment(uuid) IS
  'Mirror DEV de public.soft_delete_payment(). Opère sur dev.payments. FEAT-006.';

REVOKE ALL ON FUNCTION dev.soft_delete_payment(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION dev.soft_delete_payment(uuid) TO authenticated;

-- ============================================================================
-- Section 5 : Vérification finale RLS sur les deux schémas
-- ============================================================================
SELECT dev.assert_rls_both_schemas('payments');

COMMIT;
