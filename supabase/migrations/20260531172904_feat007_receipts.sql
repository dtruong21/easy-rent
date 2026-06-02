-- ============================================================================
-- FEAT-007 — Générer une quittance PDF de loyer
-- ============================================================================
-- WHY: Table receipts pour persister les quittances et reçus PDF générés par
-- l'Edge Function generate-receipt. Document légalement conforme (loi 1989
-- art. 21). Immuable hors flags is_voided / is_stale (preuve légale).
--
-- Dépendances :
--   FEAT-001 (auth), FEAT-002 (pattern RLS, prevent_protected_columns_change,
--   RPC SECURITY DEFINER), FEAT-005 (leases pivot), FEAT-006 (payments source).
--
-- Décisions actées (source: docs/plans/FEAT-007-quittance-pdf.md, 2026-05-31) :
--   - landlord_id dénormalisé pour RLS directe sans jointure (pattern payments)
--   - Pas de updated_at ni deleted_at : document immuable hors is_voided/is_stale
--   - Soft-delete = is_voided (rétention légale 5 ans, jamais de DELETE)
--   - voided_reason obligatoire 3-500 chars si is_voided = true (audit légal)
--   - is_stale recomputed par trigger sur soft-delete d'un payment lié (pas
--     computed-on-read : évite OR EXISTS coûteux à chaque SELECT)
--   - Bucket receipts privé (jamais public : true)
--   - document_type : enum PostgreSQL natif (quittance | recu)
--   - Pas de policy DELETE côté RLS (immuabilité)
--   - Pas de policy UPDATE directe : seule la RPC void_receipt peut modifier
--     is_voided/voided_at/voided_reason (pas de trigger protect — l'absence de
--     policy UPDATE couvre l'immuabilité des colonnes métier)
--   - CHECK total_cents = rent_cents + charges_cents (cohérence arithmétique)
--   - GIN index sur payment_ids pour le trigger is_stale
--   - Bornes date 1900–2100 (pattern FEAT-005/006)
-- ============================================================================

BEGIN;

-- ============================================================================
-- Section 1 : Type enum document_type (public + dev)
-- ============================================================================
-- WHY enum natif PG vs text CHECK : plus compact, validation implicite,
-- erreur claire côté client, cohérence évolutive (ALTER TYPE ADD VALUE).
-- ON CONFLICT via DO $$ EXCEPTION : PG n'a pas CREATE TYPE IF NOT EXISTS.

DO $$ BEGIN
  CREATE TYPE public.document_type AS ENUM ('quittance', 'recu');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE dev.document_type AS ENUM ('quittance', 'recu');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TYPE public.document_type IS
  'Type de document locatif. quittance = libératoire (total >= loyer+charges contractuels). '
  'recu = non libératoire (total < loyer+charges). Déterminé par Edge Function generate-receipt. '
  'Loi 1989 art. 21. FEAT-007.';

COMMENT ON TYPE dev.document_type IS 'Mirror DEV de public.document_type. FEAT-007.';

-- ============================================================================
-- Section 2 : Fonctions de cohérence cross-FK (ownership lease → receipt)
-- ============================================================================
-- WHY: Garantit que le lease_id référencé existe et appartient au même landlord
-- que la quittance. Défense en profondeur indépendante de RLS.
-- Pattern strictement aligné assert_payment_lease_ownership() (FEAT-006).
-- SECURITY DEFINER : bypass RLS pour voir toutes les lignes de leases.
-- Note : bail soft-deleted toléré (régularisation post-clôture — décision §8).

-- ---- PROD ----
CREATE OR REPLACE FUNCTION public.assert_receipt_lease_ownership()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
-- SECURITY DEFINER : s'exécute avec les droits de postgres, bypasse RLS sur
-- public.leases. Intentionnel : on veut voir TOUTES les lignes pour valider
-- la cohérence cross-FK, même les leases soft-deleted (régularisation autorisée).
-- SET search_path = public : évite tout override malveillant du search_path.
DECLARE
  lease_landlord uuid;
BEGIN
  -- Cas 1 : lease_id inexistant (même soft-deleted toléré → SELECT sans filtre deleted_at)
  SELECT landlord_id INTO lease_landlord
    FROM public.leases WHERE id = NEW.lease_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Receipt references a non-existent lease_id (%)',
      NEW.lease_id
      USING ERRCODE = '23514';
  END IF;

  -- Cas 2 : ownership mismatch — le bail appartient à un autre landlord
  IF lease_landlord IS DISTINCT FROM NEW.landlord_id THEN
    RAISE EXCEPTION 'Ownership mismatch: lease_id (%) belongs to landlord %, but receipt.landlord_id is %',
      NEW.lease_id, lease_landlord, NEW.landlord_id
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.assert_receipt_lease_ownership() IS
  'Trigger BEFORE INSERT sur public.receipts. SECURITY DEFINER + SET search_path=public. '
  'Vérifie 2 cas : lease_id inexistant, ownership mismatch (lease appartient à un landlord '
  'différent de receipt.landlord_id). ERRCODE 23514 (check_violation). '
  'Bail soft-deleted toléré (régularisation rétroactive autorisée — décision FEAT-007 §8). '
  'FEAT-007.';

-- ---- DEV ----
CREATE OR REPLACE FUNCTION dev.assert_receipt_lease_ownership()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = dev
AS $$
DECLARE
  lease_landlord uuid;
BEGIN
  SELECT landlord_id INTO lease_landlord
    FROM dev.leases WHERE id = NEW.lease_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Receipt references a non-existent lease_id (%)',
      NEW.lease_id
      USING ERRCODE = '23514';
  END IF;

  IF lease_landlord IS DISTINCT FROM NEW.landlord_id THEN
    RAISE EXCEPTION 'Ownership mismatch: lease_id (%) belongs to landlord %, but receipt.landlord_id is %',
      NEW.lease_id, lease_landlord, NEW.landlord_id
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION dev.assert_receipt_lease_ownership() IS
  'Mirror DEV de public.assert_receipt_lease_ownership(). Opère sur dev.leases. FEAT-007.';

-- ============================================================================
-- Section 3 : Fonction trigger recompute is_stale (sur payments)
-- ============================================================================
-- WHY: Quand un payment est soft-deleted, toutes les receipts qui l'incluent
-- (via payment_ids @> ARRAY[id]) doivent passer is_stale = true.
-- Trigger AFTER UPDATE sur payments, pas sur receipts (on ne modifie pas
-- la receipt directement, on la "marque" depuis l'event payment).
-- SECURITY DEFINER : bypass RLS pour voir + modifier receipts transversalement.
-- Index GIN sur payment_ids rend l'opérateur @> performant (cf. Section 4).

-- ---- PROD ----
CREATE OR REPLACE FUNCTION public.recompute_receipt_stale_on_payment_archive()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
-- Déclenché AFTER UPDATE sur public.payments.
-- Condition d'activation : payment vient d'être soft-deleted
-- (OLD.deleted_at IS NULL → NEW.deleted_at IS NOT NULL).
-- Marque is_stale = true sur les receipts incluant ce payment.
-- Pas de flag app.allow_deleted_at_change requis : on n'altère pas deleted_at.
BEGIN
  IF OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
    UPDATE public.receipts
      SET is_stale = true
      WHERE payment_ids @> ARRAY[NEW.id]::uuid[]
        AND is_stale = false;
    -- Note : si is_stale est déjà true, pas d'UPDATE (optimisation).
  END IF;
  RETURN NULL; -- AFTER trigger → valeur ignorée
END;
$$;

COMMENT ON FUNCTION public.recompute_receipt_stale_on_payment_archive() IS
  'Trigger AFTER UPDATE sur public.payments. SECURITY DEFINER + SET search_path=public. '
  'Si OLD.deleted_at IS NULL et NEW.deleted_at IS NOT NULL (soft-delete effectué) → '
  'marque is_stale = true sur toutes les public.receipts dont payment_ids @> ARRAY[NEW.id]. '
  'Index GIN idx_public_receipts_payment_ids_gin rend l''opérateur @> performant. '
  'Pas besoin de flag allow_deleted_at_change (on n''altère pas deleted_at). FEAT-007.';

-- ---- DEV ----
CREATE OR REPLACE FUNCTION dev.recompute_receipt_stale_on_payment_archive()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = dev
AS $$
BEGIN
  IF OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
    UPDATE dev.receipts
      SET is_stale = true
      WHERE payment_ids @> ARRAY[NEW.id]::uuid[]
        AND is_stale = false;
  END IF;
  RETURN NULL;
END;
$$;

COMMENT ON FUNCTION dev.recompute_receipt_stale_on_payment_archive() IS
  'Mirror DEV de public.recompute_receipt_stale_on_payment_archive(). Opère sur dev.payments/dev.receipts. FEAT-007.';

-- ============================================================================
-- Section 4 : Table public.receipts (PROD)
-- ============================================================================
-- Quittances et reçus PDF générés par l'Edge Function generate-receipt.
-- landlord_id dénormalisé pour simplifier les policies RLS.
-- FK RESTRICT sur leases + landlords : on ne peut pas supprimer une entité
-- avec des documents légaux liés.
-- Document immuable hors is_voided / voided_at / voided_reason / is_stale.
-- Pas de updated_at (immuabilité), pas de deleted_at (is_voided remplace).
-- CHECK total_cents = rent_cents + charges_cents : cohérence arithmétique.
-- CHECK voiding consistency : (not voided → tout NULL) OR (voided → tout non-NULL + raison).

CREATE TABLE public.receipts (
  id              uuid                    PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Ownership (dénormalisé pour RLS directe)
  landlord_id     uuid                    NOT NULL
                                          REFERENCES public.landlords(id) ON DELETE RESTRICT,
  lease_id        uuid                    NOT NULL
                                          REFERENCES public.leases(id)    ON DELETE RESTRICT,

  -- Paiements inclus dans ce document (>= 1 obligatoire)
  payment_ids     uuid[]                  NOT NULL
                                          CHECK (array_length(payment_ids, 1) >= 1),

  -- Période couverte (bornes 1900–2100, pattern FEAT-005/006)
  period_start    date                    NOT NULL
                                          CHECK (period_start BETWEEN '1900-01-01' AND '2100-12-31'),
  period_end      date                    NOT NULL
                                          CHECK (
                                            period_end > period_start
                                            AND period_end BETWEEN '1900-01-01' AND '2100-12-31'
                                          ),

  -- Montants en centimes d'euro (pas de float — erreurs d'arrondi)
  rent_cents      integer                 NOT NULL CHECK (rent_cents > 0),
  charges_cents   integer                 NOT NULL DEFAULT 0 CHECK (charges_cents >= 0),
  total_cents     integer                 NOT NULL CHECK (total_cents > 0),

  -- Type de document (enum natif)
  document_type   public.document_type    NOT NULL,

  -- Chemin Storage (pas l'URL — URL signée générée à la demande)
  -- Format : receipts/<landlord_id>/<receipt_id>.pdf
  pdf_path        text                    NOT NULL,

  -- Timestamps de génération
  generated_at    timestamptz             NOT NULL DEFAULT now(),
  created_at      timestamptz             NOT NULL DEFAULT now(),

  -- Annulation (is_voided remplace deleted_at pour rétention légale)
  is_voided       boolean                 NOT NULL DEFAULT false,
  voided_at       timestamptz,
  voided_reason   text
                                          CHECK (
                                            voided_reason IS NULL
                                            OR char_length(voided_reason) BETWEEN 3 AND 500
                                          ),

  -- Staleness (recomputed par trigger quand un payment lié est soft-deleted)
  is_stale        boolean                 NOT NULL DEFAULT false,

  -- Cohérence arithmétique
  CONSTRAINT receipts_total_check
    CHECK (total_cents = rent_cents + charges_cents),

  -- Cohérence voiding : soit tout NULL (non voided), soit tout non-NULL avec raison
  CONSTRAINT receipts_voiding_consistency
    CHECK (
      (is_voided = false AND voided_at IS NULL     AND voided_reason IS NULL)
      OR
      (is_voided = true  AND voided_at IS NOT NULL AND voided_reason IS NOT NULL)
    )
);

COMMENT ON TABLE  public.receipts IS
  'Quittances et reçus PDF (loi 1989 art. 21). Document immuable hors is_voided/is_stale. '
  'Pas de deleted_at (rétention légale 5 ans via is_voided). '
  'Généré exclusivement par l''Edge Function generate-receipt. FEAT-007.';
COMMENT ON COLUMN public.receipts.landlord_id IS
  'Bailleur propriétaire (dénormalisé). Garanti cohérent avec lease.landlord_id par trigger tr_00. '
  'FK RESTRICT : impossible de supprimer un landlord avec des documents légaux.';
COMMENT ON COLUMN public.receipts.lease_id IS
  'Bail rattaché. FK RESTRICT : impossible de supprimer un bail avec des quittances.';
COMMENT ON COLUMN public.receipts.payment_ids IS
  'UUIDs des paiements inclus dans ce document. CHECK array_length >= 1. '
  'Index GIN pour trigger recompute_is_stale.';
COMMENT ON COLUMN public.receipts.rent_cents IS
  'Somme des rent_amount_cents des paiements inclus. > 0. En centimes d''euro.';
COMMENT ON COLUMN public.receipts.charges_cents IS
  'Somme des charges_amount_cents des paiements inclus. >= 0. En centimes d''euro.';
COMMENT ON COLUMN public.receipts.total_cents IS
  'rent_cents + charges_cents. CHECK total_cents = rent_cents + charges_cents.';
COMMENT ON COLUMN public.receipts.document_type IS
  'quittance si total >= loyer+charges contractuels ; recu sinon. Déterminé par Edge Function.';
COMMENT ON COLUMN public.receipts.pdf_path IS
  'Chemin Storage : receipts/<landlord_id>/<receipt_id>.pdf. '
  'Pas une URL (URL signée générée à la demande par storage.createSignedUrl).';
COMMENT ON COLUMN public.receipts.is_voided IS
  'Document annulé par le bailleur via RPC void_receipt. Jamais effacé (rétention 5 ans). '
  'Reste visible en lecture avec badge "Annulée".';
COMMENT ON COLUMN public.receipts.voided_reason IS
  'Motif d''annulation. Obligatoire si is_voided = true (audit légal). '
  'CHECK char_length BETWEEN 3 AND 500. NULL si non annulé.';
COMMENT ON COLUMN public.receipts.is_stale IS
  'Recomputed par trigger tr_03 si un payment_id lié est soft-deleted. '
  'Signale au bailleur que le document ne reflète plus l''état actuel des paiements.';

-- ---- RLS PROD ----
ALTER TABLE public.receipts ENABLE ROW LEVEL SECURITY;

-- SELECT : le bailleur voit TOUTES ses receipts (y compris voided — traçabilité)
-- Pas de filtre is_voided : le badge "Annulée" est côté Flutter
CREATE POLICY "receipts_select_own" ON public.receipts
  FOR SELECT
  USING (landlord_id = auth.uid());

-- INSERT : uniquement via l'Edge Function avec le JWT du user
-- Le trigger tr_00 valide ensuite la cohérence lease_id → landlord_id
CREATE POLICY "receipts_insert_own" ON public.receipts
  FOR INSERT
  WITH CHECK (landlord_id = auth.uid());

-- UPDATE : intentionnellement ABSENT — immuabilité des champs métier.
-- La seule mutation autorisée (voiding) passe par RPC void_receipt (SECURITY DEFINER).
-- is_stale est modifié exclusivement par trigger recompute_receipt_stale_on_payment_archive (SECURITY DEFINER).

-- Pas de policy DELETE : rétention légale 5 ans, aucun chemin de suppression.

-- ---- Index PROD ----
-- FK landlord_id : filtrage RLS (auth.uid())
CREATE INDEX idx_public_receipts_landlord_id
  ON public.receipts(landlord_id);

-- FK lease_id : listing des quittances d'un bail
CREATE INDEX idx_public_receipts_lease_id
  ON public.receipts(lease_id);

-- Tri liste quittances par période décroissante (dashboard bail)
CREATE INDEX idx_public_receipts_period_start_desc
  ON public.receipts(lease_id, period_start DESC);

-- GIN sur payment_ids : opérateur @> pour trigger recompute is_stale
CREATE INDEX idx_public_receipts_payment_ids_gin
  ON public.receipts USING GIN (payment_ids);

-- ---- Triggers PROD ----
-- tr_00 : validation ownership lease → receipt (SECURITY DEFINER, voir Section 2)
-- BEFORE INSERT uniquement (document immuable — pas d'UPDATE sur ces colonnes)
DROP TRIGGER IF EXISTS tr_00_assert_receipt_lease_ownership ON public.receipts;
CREATE TRIGGER tr_00_assert_receipt_lease_ownership
  BEFORE INSERT ON public.receipts
  FOR EACH ROW EXECUTE FUNCTION public.assert_receipt_lease_ownership();

-- tr_01 : protection created_at (réutilise prevent_protected_columns_change — FEAT-002)
-- Note : deleted_at absent sur receipts → le check deleted_at de la fonction est
-- sans objet mais tolérant (NEW.deleted_at retourne NULL → aucun effet).
-- L'immuabilité des colonnes métier est garantie par l'absence de policy UPDATE.
DROP TRIGGER IF EXISTS tr_01_prevent_protected_columns_change_receipts ON public.receipts;
CREATE TRIGGER tr_01_prevent_protected_columns_change_receipts
  BEFORE INSERT OR UPDATE ON public.receipts
  FOR EACH ROW EXECUTE FUNCTION public.prevent_protected_columns_change();

-- Pas de tr_02_set_updated_at : pas de colonne updated_at (document immuable).

-- ============================================================================
-- Section 5 : Table dev.receipts (DEV) — miroir exact
-- ============================================================================

CREATE TABLE dev.receipts (
  id              uuid                  PRIMARY KEY DEFAULT gen_random_uuid(),
  landlord_id     uuid                  NOT NULL
                                        REFERENCES dev.landlords(id) ON DELETE RESTRICT,
  lease_id        uuid                  NOT NULL
                                        REFERENCES dev.leases(id)    ON DELETE RESTRICT,
  payment_ids     uuid[]                NOT NULL
                                        CHECK (array_length(payment_ids, 1) >= 1),
  period_start    date                  NOT NULL
                                        CHECK (period_start BETWEEN '1900-01-01' AND '2100-12-31'),
  period_end      date                  NOT NULL
                                        CHECK (
                                          period_end > period_start
                                          AND period_end BETWEEN '1900-01-01' AND '2100-12-31'
                                        ),
  rent_cents      integer               NOT NULL CHECK (rent_cents > 0),
  charges_cents   integer               NOT NULL DEFAULT 0 CHECK (charges_cents >= 0),
  total_cents     integer               NOT NULL CHECK (total_cents > 0),
  document_type   dev.document_type     NOT NULL,
  pdf_path        text                  NOT NULL,
  generated_at    timestamptz           NOT NULL DEFAULT now(),
  created_at      timestamptz           NOT NULL DEFAULT now(),
  is_voided       boolean               NOT NULL DEFAULT false,
  voided_at       timestamptz,
  voided_reason   text
                                        CHECK (
                                          voided_reason IS NULL
                                          OR char_length(voided_reason) BETWEEN 3 AND 500
                                        ),
  is_stale        boolean               NOT NULL DEFAULT false,

  CONSTRAINT receipts_total_check
    CHECK (total_cents = rent_cents + charges_cents),
  CONSTRAINT receipts_voiding_consistency
    CHECK (
      (is_voided = false AND voided_at IS NULL     AND voided_reason IS NULL)
      OR
      (is_voided = true  AND voided_at IS NOT NULL AND voided_reason IS NOT NULL)
    )
);

COMMENT ON TABLE  dev.receipts IS 'Mirror DEV de public.receipts. FEAT-007.';
COMMENT ON COLUMN dev.receipts.is_voided IS
  'Annulation via dev.void_receipt(). Rétention 5 ans.';

-- ---- RLS DEV ----
ALTER TABLE dev.receipts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "receipts_select_own" ON dev.receipts
  FOR SELECT
  USING (landlord_id = auth.uid());

CREATE POLICY "receipts_insert_own" ON dev.receipts
  FOR INSERT
  WITH CHECK (landlord_id = auth.uid());

-- Pas de policy UPDATE ni DELETE (même immuabilité que PROD).

-- ---- Index DEV ----
CREATE INDEX idx_dev_receipts_landlord_id
  ON dev.receipts(landlord_id);

CREATE INDEX idx_dev_receipts_lease_id
  ON dev.receipts(lease_id);

CREATE INDEX idx_dev_receipts_period_start_desc
  ON dev.receipts(lease_id, period_start DESC);

CREATE INDEX idx_dev_receipts_payment_ids_gin
  ON dev.receipts USING GIN (payment_ids);

-- ---- Triggers DEV ----
DROP TRIGGER IF EXISTS tr_00_assert_receipt_lease_ownership ON dev.receipts;
CREATE TRIGGER tr_00_assert_receipt_lease_ownership
  BEFORE INSERT ON dev.receipts
  FOR EACH ROW EXECUTE FUNCTION dev.assert_receipt_lease_ownership();

DROP TRIGGER IF EXISTS tr_01_prevent_protected_columns_change_receipts ON dev.receipts;
CREATE TRIGGER tr_01_prevent_protected_columns_change_receipts
  BEFORE INSERT OR UPDATE ON dev.receipts
  FOR EACH ROW EXECUTE FUNCTION public.prevent_protected_columns_change();

-- ============================================================================
-- Section 6 : Trigger tr_03_set_receipt_stale_on_payment_archive
--             attaché à public.payments ET dev.payments
-- ============================================================================
-- WHY trigger AFTER UPDATE sur payments (pas sur receipts) : le soft-delete
-- d'un payment génère un UPDATE sur payments.deleted_at, qui déclenche ici
-- un UPDATE transverse sur receipts. Séparation de responsabilité propre.
-- Trigger nommé tr_03 pour rester après tr_00/tr_01/tr_02 dans l'ordre alpha
-- (PG execute AFTER triggers dans l'ordre alphabétique du nom).

-- ---- Sur public.payments ----
DROP TRIGGER IF EXISTS tr_03_set_receipt_stale_on_payment_archive ON public.payments;
CREATE TRIGGER tr_03_set_receipt_stale_on_payment_archive
  AFTER UPDATE OF deleted_at ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.recompute_receipt_stale_on_payment_archive();

-- ---- Sur dev.payments ----
DROP TRIGGER IF EXISTS tr_03_set_receipt_stale_on_payment_archive ON dev.payments;
CREATE TRIGGER tr_03_set_receipt_stale_on_payment_archive
  AFTER UPDATE OF deleted_at ON dev.payments
  FOR EACH ROW EXECUTE FUNCTION dev.recompute_receipt_stale_on_payment_archive();

-- ============================================================================
-- Section 7 : RPC void_receipt (public + dev)
-- ============================================================================
-- WHY SECURITY DEFINER: RLS n'autorise pas UPDATE sur receipts (pas de policy).
-- La RPC contourne intentionnellement pour le seul cas autorisé (voiding).
-- Ownership check (landlord_id = auth.uid() AND is_voided = false) dans WHERE :
-- cross-user et déjà-voided retournent NOT FOUND (pas de fuite d'information).
-- REVOKE ALL + GRANT authenticated : anon ne peut jamais appeler void_receipt.

-- ---- PROD ----
CREATE OR REPLACE FUNCTION public.void_receipt(p_id uuid, p_reason text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Validation longueur raison (défense en profondeur — aussi CHECK en DB)
  IF p_reason IS NULL OR char_length(p_reason) < 3 OR char_length(p_reason) > 500 THEN
    RAISE EXCEPTION 'voided_reason must be between 3 and 500 characters'
      USING ERRCODE = '22023';  -- invalid_parameter_value
  END IF;

  UPDATE public.receipts
    SET
      is_voided     = true,
      voided_at     = now(),
      voided_reason = p_reason
    WHERE id            = p_id
      AND landlord_id   = auth.uid()
      AND is_voided     = false;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Receipt not found, already voided, or not owned by caller'
      USING ERRCODE = 'P0002';  -- no_data_found
  END IF;
END;
$$;

COMMENT ON FUNCTION public.void_receipt(uuid, text) IS
  'RPC SECURITY DEFINER : annule une quittance (is_voided = true, voided_at = now(), voided_reason). '
  'Vérifie ownership (landlord_id = auth.uid()) et NOT FOUND si déjà annulée ou cross-user '
  '(pas de fuite d''information). Validation longueur raison 3-500 chars (ERRCODE 22023). '
  'REVOKE ALL FROM PUBLIC → seul le rôle authenticated peut appeler. '
  'Pas de REVOKE/GRANT nécessaire pour service_role (superuser). FEAT-007.';

REVOKE ALL ON FUNCTION public.void_receipt(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.void_receipt(uuid, text) TO authenticated;

-- ---- DEV ----
CREATE OR REPLACE FUNCTION dev.void_receipt(p_id uuid, p_reason text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = dev
AS $$
BEGIN
  IF p_reason IS NULL OR char_length(p_reason) < 3 OR char_length(p_reason) > 500 THEN
    RAISE EXCEPTION 'voided_reason must be between 3 and 500 characters'
      USING ERRCODE = '22023';
  END IF;

  UPDATE dev.receipts
    SET
      is_voided     = true,
      voided_at     = now(),
      voided_reason = p_reason
    WHERE id            = p_id
      AND landlord_id   = auth.uid()
      AND is_voided     = false;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Receipt not found, already voided, or not owned by caller'
      USING ERRCODE = 'P0002';
  END IF;
END;
$$;

COMMENT ON FUNCTION dev.void_receipt(uuid, text) IS
  'Mirror DEV de public.void_receipt(). Opère sur dev.receipts. FEAT-007.';

REVOKE ALL ON FUNCTION dev.void_receipt(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION dev.void_receipt(uuid, text) TO authenticated;

-- ============================================================================
-- Section 8 : Bucket Storage receipts/ (idempotent)
-- ============================================================================
-- WHY: Bucket privé (public = false) — jamais d'URL publique.
-- URLs signées générées à la demande (5 min) via storage.createSignedUrl.
-- ON CONFLICT DO NOTHING : idempotent si le bucket existe déjà.
-- Chemin : receipts/<landlord_id>/<receipt_id>.pdf
-- Un seul bucket partagé PROD/DEV : isolation via landlord_id (auth.uid()).

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  VALUES (
    'receipts',
    'receipts',
    false,                        -- privé : jamais d'URL publique
    10485760,                     -- 10 MB max par fichier (PDF raisonnable)
    ARRAY['application/pdf']      -- uniquement des PDF
  )
  ON CONFLICT (id) DO NOTHING;

-- ---- Policies Storage ----
-- Isolation : (storage.foldername(name))[1] = le premier segment du chemin
-- = landlord_id pour le format receipts/<landlord_id>/<receipt_id>.pdf
-- storage.foldername retourne text[] ; [1] = premier segment.

-- SELECT : un user ne voit que ses propres PDF
DROP POLICY IF EXISTS "receipts_storage_select_own" ON storage.objects;
CREATE POLICY "receipts_storage_select_own" ON storage.objects
  FOR SELECT
  USING (
    bucket_id = 'receipts'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- INSERT : l'Edge Function (JWT du user) ne peut uploader que sous son propre landlord_id
DROP POLICY IF EXISTS "receipts_storage_insert_own" ON storage.objects;
CREATE POLICY "receipts_storage_insert_own" ON storage.objects
  FOR INSERT
  WITH CHECK (
    bucket_id = 'receipts'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Pas de policy UPDATE / DELETE : immuabilité des PDF (rétention légale 5 ans).
-- Un orphan PDF (upload OK, INSERT DB échoué) est toléré au MVP (nettoyage P2).

-- ============================================================================
-- Section 9 : Vérification finale RLS sur les deux schémas
-- ============================================================================
SELECT dev.assert_rls_both_schemas('receipts');

COMMIT;
