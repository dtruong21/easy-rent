-- ============================================================================
-- FEAT-009 — Upload & stockage de documents
-- ============================================================================
-- WHY: Table documents pour stocker les métadonnées des documents uploadés par
-- le bailleur (bail signé, état des lieux, attestation assurance, quittances
-- scannées, autres). Bucket Storage privé `documents` avec MIME whitelist
-- serveur (D1=B). Fichiers à valeur juridique protégés par legal_hold
-- (bail_signe, etat_des_lieux) — calculé automatiquement par trigger.
--
-- Dépendances :
--   FEAT-001 (auth), FEAT-002 (pattern RLS, prevent_protected_columns_change,
--   RPC SECURITY DEFINER, set_updated_at), FEAT-005 (leases pivot),
--   FEAT-007 (pattern bucket Storage privé + policy storage.foldername),
--   FEAT-008 (pattern trigger tr_01b protect immutable columns via GUC-free).
--
-- Décisions actées (source: docs/plans/FEAT-009-documents-storage.md, 2026-06-02) :
--   - D1=B : validation MIME via Storage policy `allowed_mime_types` (pas d'Edge Function)
--   - D2=B : quota warning 100MB client-side (rien à coder DB)
--   - D3 modifié : legal_hold calculé par trigger BEFORE INSERT
--     (true ssi category IN ('bail_signe', 'etat_des_lieux'))
--   - D4=B : seule `category` est UPDATE-able ; autres colonnes protégées par tr_01b
--   - Soft-delete via RPC soft_delete_document(p_id uuid) — retourne
--     (storage_path, hard_deleted) pour coordonner la suppression Storage côté frontend
--   - landlord_id dénormalisé pour RLS directe sans jointure (pattern payments/receipts)
--   - Bucket privé (public=false), chemin {env}/{landlord_id}/{document_id}.{ext}
--   - Path isolation sur segment [2] (env=segment[1], landlord_id=segment[2])
--   - ON DELETE RESTRICT sur FK (leases + landlords) : rétention légale
--   - Pas de policy DELETE sur table DB : tout passe par RPC SECURITY DEFINER
-- ============================================================================

BEGIN;

-- ============================================================================
-- Section 1 : Type enum document_category (public + dev)
-- ============================================================================
-- WHY enum natif PG vs text CHECK : validation implicite, erreur claire côté
-- client, cohérence évolutive (ALTER TYPE ADD VALUE), pattern aligné
-- public.document_type (FEAT-007).
-- DO $$ EXCEPTION : PG n'a pas CREATE TYPE IF NOT EXISTS.

DO $$ BEGIN
  CREATE TYPE public.document_category AS ENUM (
    'bail_signe',
    'etat_des_lieux',
    'attestation_assurance',
    'quittance_scannee',
    'autre'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE dev.document_category AS ENUM (
    'bail_signe',
    'etat_des_lieux',
    'attestation_assurance',
    'quittance_scannee',
    'autre'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TYPE public.document_category IS
  'Catégorie de document locatif. bail_signe et etat_des_lieux déclenchent legal_hold=true '
  '(rétention légale, suppression physique bloquée). FEAT-009.';

COMMENT ON TYPE dev.document_category IS 'Mirror DEV de public.document_category. FEAT-009.';

-- ============================================================================
-- Section 2 : Fonction trigger — assert_document_lease_ownership (public + dev)
-- ============================================================================
-- WHY: Garantit que lease_id référencé appartient au même landlord que le document.
-- Défense en profondeur indépendante de RLS.
-- SECURITY DEFINER + SET search_path : bypass RLS pour voir toutes les leases
-- et valider la cohérence cross-FK, même les baux soft-deleted (un bailleur peut
-- uploader un document de référence sur un bail archivé).
-- Pattern strictement aligné assert_receipt_lease_ownership() (FEAT-007) et
-- assert_payment_lease_ownership() (FEAT-006).

-- ---- PROD ----
CREATE OR REPLACE FUNCTION public.assert_document_lease_ownership()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
-- SECURITY DEFINER : bypass RLS sur public.leases. Intentionnel — on veut voir
-- TOUTES les leases (même soft-deleted) pour valider la cohérence cross-FK.
-- SET search_path = public : évite tout override malveillant du search_path.
DECLARE
  lease_landlord uuid;
BEGIN
  -- Cas 1 : lease_id inexistant (bail soft-deleted toléré → SELECT sans filtre deleted_at)
  SELECT landlord_id INTO lease_landlord
    FROM public.leases WHERE id = NEW.lease_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Document lease ownership mismatch: lease_id (%) does not exist',
      NEW.lease_id
      USING ERRCODE = '23514';
  END IF;

  -- Cas 2 : ownership mismatch
  IF lease_landlord IS DISTINCT FROM NEW.landlord_id THEN
    RAISE EXCEPTION 'Document lease ownership mismatch: lease_id (%) belongs to landlord %, but document.landlord_id is %',
      NEW.lease_id, lease_landlord, NEW.landlord_id
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.assert_document_lease_ownership() IS
  'Trigger BEFORE INSERT sur public.documents. SECURITY DEFINER + SET search_path=public. '
  'Vérifie : (a) lease_id existe dans public.leases (bail soft-deleted toléré), '
  '(b) lease.landlord_id = document.landlord_id. ERRCODE 23514 (check_violation). '
  'Pattern aligné assert_receipt_lease_ownership() FEAT-007. FEAT-009.';

-- ---- DEV ----
CREATE OR REPLACE FUNCTION dev.assert_document_lease_ownership()
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
    RAISE EXCEPTION 'Document lease ownership mismatch: lease_id (%) does not exist',
      NEW.lease_id
      USING ERRCODE = '23514';
  END IF;

  IF lease_landlord IS DISTINCT FROM NEW.landlord_id THEN
    RAISE EXCEPTION 'Document lease ownership mismatch: lease_id (%) belongs to landlord %, but document.landlord_id is %',
      NEW.lease_id, lease_landlord, NEW.landlord_id
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION dev.assert_document_lease_ownership() IS
  'Mirror DEV de public.assert_document_lease_ownership(). Opère sur dev.leases. FEAT-009.';

-- ============================================================================
-- Section 3 : Fonction trigger — compute_document_legal_hold (public + dev)
-- ============================================================================
-- WHY: La catégorie est la source de vérité du legal_hold. Un client qui envoie
-- legal_hold=false pour category=bail_signe verra son champ écrasé à true.
-- Inversement, legal_hold=true pour category=autre → écrasé à false.
-- Ce calcul est toujours appliqué à l'INSERT (D3 modifié).
-- Pas SECURITY DEFINER : logique pure sur NEW, pas d'accès aux autres tables.

-- ---- PROD ----
CREATE OR REPLACE FUNCTION public.compute_document_legal_hold()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- La catégorie est source de vérité : bail_signe et etat_des_lieux
  -- impliquent toujours legal_hold=true, indépendamment de ce que le
  -- client envoie. Protection contre la désactivation frauduleuse du hold.
  NEW.legal_hold := (NEW.category IN ('bail_signe', 'etat_des_lieux'));
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.compute_document_legal_hold() IS
  'Trigger BEFORE INSERT sur public.documents. '
  'Calcule legal_hold = (category IN (bail_signe, etat_des_lieux)). '
  'La catégorie est source de vérité — toujours écrasé même si le client envoie une valeur. '
  'Pas SECURITY DEFINER : logique pure sur NEW. FEAT-009.';

-- ---- DEV ----
CREATE OR REPLACE FUNCTION dev.compute_document_legal_hold()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.legal_hold := (NEW.category IN ('bail_signe', 'etat_des_lieux'));
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION dev.compute_document_legal_hold() IS
  'Mirror DEV de public.compute_document_legal_hold(). FEAT-009.';

-- ============================================================================
-- Section 4 : Fonction trigger — protect_immutable_documents (public + dev)
-- ============================================================================
-- WHY: Protège 5 colonnes immuables après INSERT : filename, storage_path,
-- mime_type, size_bytes, legal_hold. Aucun GUC bypass — ces colonnes ne
-- doivent JAMAIS être réécrites, même par RPC.
-- Pattern strict de protect_sent_columns_receipts() (FEAT-008), sans GUC :
-- ici l'immuabilité est totale (pas de mise à jour autorisée via RPC).
-- Note legal_hold : tr_00b calcule legal_hold à l'INSERT depuis category.
-- tr_01b bloque ensuite tout changement → un UPDATE category ne change PAS
-- legal_hold (voulu : dégrade le hold serait une faille légale).

-- ---- PROD ----
CREATE OR REPLACE FUNCTION public.protect_immutable_documents()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.filename       IS DISTINCT FROM OLD.filename
     OR NEW.storage_path IS DISTINCT FROM OLD.storage_path
     OR NEW.mime_type    IS DISTINCT FROM OLD.mime_type
     OR NEW.size_bytes   IS DISTINCT FROM OLD.size_bytes
     OR NEW.legal_hold   IS DISTINCT FROM OLD.legal_hold
  THEN
    RAISE EXCEPTION 'columns filename/storage_path/mime_type/size_bytes/legal_hold are immutable on documents'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.protect_immutable_documents() IS
  'Trigger BEFORE UPDATE sur public.documents. '
  'Bloque toute modification de : filename, storage_path, mime_type, size_bytes, legal_hold. '
  'Aucun GUC bypass — immuabilité totale (même pas via RPC). '
  'Pattern aligné protect_sent_columns_receipts() FEAT-008. FEAT-009.';

-- ---- DEV ----
CREATE OR REPLACE FUNCTION dev.protect_immutable_documents()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.filename       IS DISTINCT FROM OLD.filename
     OR NEW.storage_path IS DISTINCT FROM OLD.storage_path
     OR NEW.mime_type    IS DISTINCT FROM OLD.mime_type
     OR NEW.size_bytes   IS DISTINCT FROM OLD.size_bytes
     OR NEW.legal_hold   IS DISTINCT FROM OLD.legal_hold
  THEN
    RAISE EXCEPTION 'columns filename/storage_path/mime_type/size_bytes/legal_hold are immutable on documents'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION dev.protect_immutable_documents() IS
  'Mirror DEV de public.protect_immutable_documents(). FEAT-009.';

-- ============================================================================
-- Section 5 : Table public.documents (PROD)
-- ============================================================================
-- landlord_id dénormalisé pour simplifier les policies RLS (pattern payments/receipts).
-- FK RESTRICT sur leases + landlords : on ne peut pas supprimer une entité
-- avec des documents liés (rétention légale).
-- Pas de hard-delete côté DB : tout soft-delete via RPC soft_delete_document().
-- La protection de category comme seul champ mutable est assurée par tr_01b
-- (tr_01b protège les 5 colonnes immuables) + la policy UPDATE autorise
-- techniquement UPDATE * mais le trigger bloque tout hors category/updated_at.

CREATE TABLE public.documents (
  id             uuid                      PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Ownership (dénormalisé pour RLS directe)
  landlord_id    uuid                      NOT NULL
                                           REFERENCES public.landlords(id) ON DELETE RESTRICT,
  lease_id       uuid                      NOT NULL
                                           REFERENCES public.leases(id)    ON DELETE RESTRICT,

  -- Catégorie (seul champ mutable après INSERT)
  category       public.document_category  NOT NULL,

  -- Métadonnées fichier (immuables après INSERT — protégées par tr_01b)
  filename       text                      NOT NULL
                                           CHECK (char_length(filename) BETWEEN 1 AND 255),
  storage_path   text                      NOT NULL UNIQUE
                                           CHECK (char_length(storage_path) BETWEEN 1 AND 500),
  mime_type      text                      NOT NULL
                                           CHECK (mime_type IN (
                                             'application/pdf',
                                             'image/jpeg',
                                             'image/png',
                                             'image/webp'
                                           )),
  size_bytes     integer                   NOT NULL
                                           CHECK (size_bytes BETWEEN 1 AND 10485760),

  -- Rétention légale (calculé par trigger tr_00b à l'INSERT)
  legal_hold     boolean                   NOT NULL DEFAULT false,

  -- Timestamps
  uploaded_at    timestamptz               NOT NULL DEFAULT now(),
  created_at     timestamptz               NOT NULL DEFAULT now(),
  updated_at     timestamptz               NOT NULL DEFAULT now(),
  deleted_at     timestamptz               NULL  -- soft-delete via RPC soft_delete_document()
);

COMMENT ON TABLE  public.documents IS
  'Documents locatifs uploadés par le bailleur (PDF, images). '
  'Seule la catégorie est mutable après INSERT. '
  'legal_hold=true (bail_signe, etat_des_lieux) bloque le hard-delete Storage. '
  'Soft-delete via RPC soft_delete_document() uniquement (pas de DELETE policy). '
  'FEAT-009.';
COMMENT ON COLUMN public.documents.landlord_id IS
  'Bailleur propriétaire (dénormalisé). Garanti cohérent avec lease.landlord_id par trigger tr_00. '
  'FK RESTRICT : impossible de supprimer un landlord avec des documents liés.';
COMMENT ON COLUMN public.documents.lease_id IS
  'Bail rattaché. FK RESTRICT : impossible de supprimer un bail avec des documents liés.';
COMMENT ON COLUMN public.documents.category IS
  'Seul champ mutable après INSERT. Détermine legal_hold via trigger tr_00b.';
COMMENT ON COLUMN public.documents.filename IS
  'Nom original du fichier tel que sélectionné par le bailleur. CHECK 1..255 chars.';
COMMENT ON COLUMN public.documents.storage_path IS
  'Chemin complet dans le bucket documents/. '
  'Format : {env}/{landlord_id}/{document_id}.{ext} '
  'Exemple : prod/8e6c.../3a91....pdf. UNIQUE + CHECK 1..500 chars.';
COMMENT ON COLUMN public.documents.mime_type IS
  'MIME type validé. CHECK IN (application/pdf, image/jpeg, image/png, image/webp). '
  'Immuable après INSERT (protégé par tr_01b_protect_immutable_documents).';
COMMENT ON COLUMN public.documents.size_bytes IS
  'Taille du fichier en octets. CHECK BETWEEN 1 AND 10485760 (10 MB max). '
  'Immuable après INSERT. Utilisé pour calcul quota client-side (D2=B, 100 MB soft limit).';
COMMENT ON COLUMN public.documents.legal_hold IS
  'Calculé par trigger tr_00b : true ssi category IN (bail_signe, etat_des_lieux). '
  'Immuable après INSERT (protégé par tr_01b). '
  'Si true au soft-delete → hard-delete Storage bloqué (RPC retourne hard_deleted=false). '
  'D3 modifié — FEAT-009.';
COMMENT ON COLUMN public.documents.uploaded_at IS
  'Moment où le fichier a été reçu (distinct de created_at). '
  'Sémantique : "fichier reçu" vs "row créée". Mêmes valeurs en pratique.';
COMMENT ON COLUMN public.documents.deleted_at IS
  'Soft-delete via RPC soft_delete_document() uniquement. '
  'Modifiable uniquement via RPC (GUC app.allow_deleted_at_change = 1).';

-- ---- RLS PROD ----
ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;

-- SELECT : le bailleur voit ses propres documents non supprimés
CREATE POLICY "documents_select_own" ON public.documents
  FOR SELECT
  USING (landlord_id = auth.uid() AND deleted_at IS NULL);

-- INSERT : uniquement sous son propre landlord_id
-- Le trigger tr_00 valide ensuite lease_id → landlord_id
-- Le trigger tr_00b calcule legal_hold depuis category
CREATE POLICY "documents_insert_own" ON public.documents
  FOR INSERT
  WITH CHECK (landlord_id = auth.uid());

-- UPDATE : autorisé sur ses propres documents non supprimés
-- Le trigger tr_01b_protect_immutable_documents bloque tout hors category (et updated_at via tr_02)
-- D4=B : seule category est effectivement mutable
CREATE POLICY "documents_update_category_only" ON public.documents
  FOR UPDATE
  USING (landlord_id = auth.uid() AND deleted_at IS NULL)
  WITH CHECK (landlord_id = auth.uid());

-- Pas de policy DELETE : soft-delete uniquement via RPC soft_delete_document()

-- ---- Index PROD ----
-- Composite (landlord_id, lease_id, deleted_at) : listing par bail (requête principale)
CREATE INDEX idx_public_documents_lease
  ON public.documents(landlord_id, lease_id, deleted_at);

-- Composite (landlord_id, deleted_at) : quota global landlord (SUM size_bytes)
CREATE INDEX idx_public_documents_landlord
  ON public.documents(landlord_id, deleted_at);

-- Partial unique sur storage_path (docs actifs seulement — soft-delete aware)
CREATE UNIQUE INDEX idx_public_documents_storage_path
  ON public.documents(storage_path)
  WHERE deleted_at IS NULL;

-- ---- Triggers PROD ----
-- tr_00 : validation ownership lease → document (SECURITY DEFINER)
-- BEFORE INSERT uniquement (landlord_id + lease_id immuables)
DROP TRIGGER IF EXISTS tr_00_assert_documents_lease_ownership ON public.documents;
CREATE TRIGGER tr_00_assert_documents_lease_ownership
  BEFORE INSERT ON public.documents
  FOR EACH ROW EXECUTE FUNCTION public.assert_document_lease_ownership();

-- tr_00b : calcul legal_hold depuis category (BEFORE INSERT)
-- Ordre alpha : tr_00b > tr_00 → s'exécute après la validation ownership
-- (mais avant tr_01 qui bloque deleted_at). L'ordre est garanti par le nom.
DROP TRIGGER IF EXISTS tr_00b_compute_legal_hold ON public.documents;
CREATE TRIGGER tr_00b_compute_legal_hold
  BEFORE INSERT ON public.documents
  FOR EACH ROW EXECUTE FUNCTION public.compute_document_legal_hold();

-- tr_01 : protection created_at + deleted_at (réutilise prevent_protected_columns_change — FEAT-002)
DROP TRIGGER IF EXISTS tr_01_prevent_protected_columns_change_documents ON public.documents;
CREATE TRIGGER tr_01_prevent_protected_columns_change_documents
  BEFORE INSERT OR UPDATE ON public.documents
  FOR EACH ROW EXECUTE FUNCTION public.prevent_protected_columns_change();

-- tr_01b : protection colonnes immuables (filename, storage_path, mime_type, size_bytes, legal_hold)
-- Ordre alpha : tr_01b après tr_01 (stable), avant tr_02.
-- Pas de GUC bypass — immuabilité totale.
DROP TRIGGER IF EXISTS tr_01b_protect_immutable_documents ON public.documents;
CREATE TRIGGER tr_01b_protect_immutable_documents
  BEFORE UPDATE ON public.documents
  FOR EACH ROW EXECUTE FUNCTION public.protect_immutable_documents();

-- tr_02 : updated_at = now() (réutilise set_updated_at — FEAT-001)
DROP TRIGGER IF EXISTS tr_02_set_updated_at_documents ON public.documents;
CREATE TRIGGER tr_02_set_updated_at_documents
  BEFORE UPDATE ON public.documents
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ============================================================================
-- Section 6 : Table dev.documents (DEV) — miroir exact
-- ============================================================================

CREATE TABLE dev.documents (
  id             uuid                    PRIMARY KEY DEFAULT gen_random_uuid(),
  landlord_id    uuid                    NOT NULL
                                         REFERENCES dev.landlords(id) ON DELETE RESTRICT,
  lease_id       uuid                    NOT NULL
                                         REFERENCES dev.leases(id)    ON DELETE RESTRICT,
  category       dev.document_category   NOT NULL,
  filename       text                    NOT NULL
                                         CHECK (char_length(filename) BETWEEN 1 AND 255),
  storage_path   text                    NOT NULL UNIQUE
                                         CHECK (char_length(storage_path) BETWEEN 1 AND 500),
  mime_type      text                    NOT NULL
                                         CHECK (mime_type IN (
                                           'application/pdf',
                                           'image/jpeg',
                                           'image/png',
                                           'image/webp'
                                         )),
  size_bytes     integer                 NOT NULL
                                         CHECK (size_bytes BETWEEN 1 AND 10485760),
  legal_hold     boolean                 NOT NULL DEFAULT false,
  uploaded_at    timestamptz             NOT NULL DEFAULT now(),
  created_at     timestamptz             NOT NULL DEFAULT now(),
  updated_at     timestamptz             NOT NULL DEFAULT now(),
  deleted_at     timestamptz             NULL
);

COMMENT ON TABLE  dev.documents IS 'Mirror DEV de public.documents. FEAT-009.';
COMMENT ON COLUMN dev.documents.legal_hold IS
  'Calculé par trigger tr_00b via dev.compute_document_legal_hold(). '
  'true ssi category IN (bail_signe, etat_des_lieux). FEAT-009.';

-- ---- RLS DEV ----
ALTER TABLE dev.documents ENABLE ROW LEVEL SECURITY;

CREATE POLICY "documents_select_own" ON dev.documents
  FOR SELECT
  USING (landlord_id = auth.uid() AND deleted_at IS NULL);

CREATE POLICY "documents_insert_own" ON dev.documents
  FOR INSERT
  WITH CHECK (landlord_id = auth.uid());

CREATE POLICY "documents_update_category_only" ON dev.documents
  FOR UPDATE
  USING (landlord_id = auth.uid() AND deleted_at IS NULL)
  WITH CHECK (landlord_id = auth.uid());

-- Pas de policy DELETE (même règle que PROD).

-- ---- Index DEV ----
CREATE INDEX idx_dev_documents_lease
  ON dev.documents(landlord_id, lease_id, deleted_at);

CREATE INDEX idx_dev_documents_landlord
  ON dev.documents(landlord_id, deleted_at);

CREATE UNIQUE INDEX idx_dev_documents_storage_path
  ON dev.documents(storage_path)
  WHERE deleted_at IS NULL;

-- ---- Triggers DEV ----
DROP TRIGGER IF EXISTS tr_00_assert_documents_lease_ownership ON dev.documents;
CREATE TRIGGER tr_00_assert_documents_lease_ownership
  BEFORE INSERT ON dev.documents
  FOR EACH ROW EXECUTE FUNCTION dev.assert_document_lease_ownership();

DROP TRIGGER IF EXISTS tr_00b_compute_legal_hold ON dev.documents;
CREATE TRIGGER tr_00b_compute_legal_hold
  BEFORE INSERT ON dev.documents
  FOR EACH ROW EXECUTE FUNCTION dev.compute_document_legal_hold();

DROP TRIGGER IF EXISTS tr_01_prevent_protected_columns_change_documents ON dev.documents;
CREATE TRIGGER tr_01_prevent_protected_columns_change_documents
  BEFORE INSERT OR UPDATE ON dev.documents
  FOR EACH ROW EXECUTE FUNCTION public.prevent_protected_columns_change();

DROP TRIGGER IF EXISTS tr_01b_protect_immutable_documents ON dev.documents;
CREATE TRIGGER tr_01b_protect_immutable_documents
  BEFORE UPDATE ON dev.documents
  FOR EACH ROW EXECUTE FUNCTION dev.protect_immutable_documents();

DROP TRIGGER IF EXISTS tr_02_set_updated_at_documents ON dev.documents;
CREATE TRIGGER tr_02_set_updated_at_documents
  BEFORE UPDATE ON dev.documents
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ============================================================================
-- Section 7 : RPC soft_delete_document (public + dev)
-- ============================================================================
-- WHY SECURITY DEFINER: RLS n'autorise pas DELETE ni UPDATE deleted_at directement.
-- La RPC contourne intentionnellement pour le seul cas autorisé (soft-delete).
-- Retourne (storage_path, hard_deleted) pour orchestrer le hard-delete Storage
-- côté frontend (D3 modifié) :
--   hard_deleted=true  → frontend appelle storage.from('documents').remove([storage_path])
--   hard_deleted=false → legal_hold ON, fichier conservé en Storage, frontend ne fait rien
-- Ownership check + deleted_at IS NULL dans le SELECT FOR UPDATE (atomique).
-- ERRCODE P0002 si non trouvé / cross-user / déjà supprimé (pas de fuite d'info).

-- ---- PROD ----
CREATE OR REPLACE FUNCTION public.soft_delete_document(p_id uuid)
RETURNS TABLE (storage_path text, hard_deleted boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_legal_hold   boolean;
  v_storage_path text;
BEGIN
  -- Lock + ownership + récupération atomique (évite race condition)
  SELECT d.legal_hold, d.storage_path
    INTO v_legal_hold, v_storage_path
    FROM public.documents d
    WHERE d.id          = p_id
      AND d.landlord_id = auth.uid()
      AND d.deleted_at  IS NULL
    FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'document not found, not owned, or already deleted'
      USING ERRCODE = 'P0002';
  END IF;

  -- Pose le GUC pour autoriser la modification de deleted_at via tr_01
  PERFORM set_config('app.allow_deleted_at_change', '1', true);

  UPDATE public.documents
     SET deleted_at = now()
   WHERE id = p_id;

  -- Retour au frontend :
  -- legal_hold=true  → fichier conservé en Storage (obligation légale)
  -- legal_hold=false → frontend doit appeler storage.remove([storage_path])
  hard_deleted := NOT v_legal_hold;
  storage_path := CASE WHEN v_legal_hold THEN NULL ELSE v_storage_path END;
  RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION public.soft_delete_document(uuid) IS
  'RPC SECURITY DEFINER : soft-delete un document (deleted_at = now()). '
  'Retourne (storage_path, hard_deleted) pour orchestrer le hard-delete Storage côté frontend. '
  'hard_deleted=true si legal_hold=false (frontend doit appeler storage.remove). '
  'hard_deleted=false si legal_hold=true (fichier conservé pour obligation légale). '
  'ERRCODE P0002 si non trouvé / cross-user / déjà supprimé. '
  'REVOKE ALL FROM PUBLIC → seul authenticated peut appeler. FEAT-009.';

REVOKE ALL ON FUNCTION public.soft_delete_document(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.soft_delete_document(uuid) TO authenticated;

-- ---- DEV ----
CREATE OR REPLACE FUNCTION dev.soft_delete_document(p_id uuid)
RETURNS TABLE (storage_path text, hard_deleted boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = dev, pg_temp
AS $$
DECLARE
  v_legal_hold   boolean;
  v_storage_path text;
BEGIN
  SELECT d.legal_hold, d.storage_path
    INTO v_legal_hold, v_storage_path
    FROM dev.documents d
    WHERE d.id          = p_id
      AND d.landlord_id = auth.uid()
      AND d.deleted_at  IS NULL
    FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'document not found, not owned, or already deleted'
      USING ERRCODE = 'P0002';
  END IF;

  PERFORM set_config('app.allow_deleted_at_change', '1', true);

  UPDATE dev.documents
     SET deleted_at = now()
   WHERE id = p_id;

  hard_deleted := NOT v_legal_hold;
  storage_path := CASE WHEN v_legal_hold THEN NULL ELSE v_storage_path END;
  RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION dev.soft_delete_document(uuid) IS
  'Mirror DEV de public.soft_delete_document(). Opère sur dev.documents. FEAT-009.';

REVOKE ALL ON FUNCTION dev.soft_delete_document(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION dev.soft_delete_document(uuid) TO authenticated;

-- ============================================================================
-- Section 8 : Bucket Storage documents/ (idempotent)
-- ============================================================================
-- WHY: Bucket privé (public=false) — jamais d'URL publique.
-- URLs signées générées à la demande (5 min) via storage.createSignedUrl.
-- allowed_mime_types : D1=B — whitelist MIME serveur au moment de l'upload.
-- file_size_limit : 10 MB max par fichier.
-- ON CONFLICT DO UPDATE : met à jour la whitelist MIME si le bucket existe.
-- Chemin : documents/{env}/{landlord_id}/{document_id}.{ext}
-- Isolation buckets : shared PROD/DEV dans le même bucket,
-- isolation via auth.uid() (segment [2] dans le chemin).

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  VALUES (
    'documents',
    'documents',
    false,                           -- privé : jamais d'URL publique
    10485760,                        -- 10 MB max par fichier
    ARRAY[
      'application/pdf',
      'image/jpeg',
      'image/png',
      'image/webp'
    ]                                -- D1=B : MIME whitelist serveur
  )
  ON CONFLICT (id) DO UPDATE
    SET allowed_mime_types = EXCLUDED.allowed_mime_types,
        file_size_limit    = EXCLUDED.file_size_limit;

-- ---- Policies Storage ----
-- Isolation sur segment [2] (env=segment[1], landlord_id=segment[2]).
-- Divergence assumée vs receipts (receipts utilise segment[1] = landlord_id sans env).
-- Pour documents : chemin = {env}/{landlord_id}/... → foldername[1]=env, foldername[2]=landlord_id.
-- Conséquence : policy sur [2] (et non [1] comme receipts).

-- SELECT : un user ne voit que ses propres documents (peu importe l'env)
DROP POLICY IF EXISTS "documents_storage_select_own" ON storage.objects;
CREATE POLICY "documents_storage_select_own" ON storage.objects
  FOR SELECT
  USING (
    bucket_id = 'documents'
    AND (storage.foldername(name))[2] = auth.uid()::text
  );

-- INSERT : upload uniquement sous {env}/{auth.uid()}/...
DROP POLICY IF EXISTS "documents_storage_insert_own" ON storage.objects;
CREATE POLICY "documents_storage_insert_own" ON storage.objects
  FOR INSERT
  WITH CHECK (
    bucket_id = 'documents'
    AND (storage.foldername(name))[2] = auth.uid()::text
  );

-- DELETE : hard-delete autorisé sous {env}/{auth.uid()}/...
-- Orchestré par frontend après RPC soft_delete_document (D3 modifié).
-- Pas d'UPDATE Storage : fichiers immuables (replace = delete + new upload).
DROP POLICY IF EXISTS "documents_storage_delete_own" ON storage.objects;
CREATE POLICY "documents_storage_delete_own" ON storage.objects
  FOR DELETE
  USING (
    bucket_id = 'documents'
    AND (storage.foldername(name))[2] = auth.uid()::text
  );

-- ============================================================================
-- Section 9 : Vérification finale RLS sur les deux schémas
-- ============================================================================
SELECT dev.assert_rls_both_schemas('documents');

COMMIT;
