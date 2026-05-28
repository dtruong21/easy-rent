-- ============================================================================
-- FEAT-002 — Modèle de données & RLS
-- ============================================================================
-- WHY: Pose le socle Postgres des features CRUD (FEAT-003/004/005) :
--   - Extension de landlords (full_name, phone, address)
--   - Changement FK landlords → auth.users : CASCADE → NO ACTION (rétention 5 ans)
--   - Création de properties, tenants, leases avec RLS + soft-delete
--   - Trigger prevent_protected_columns_change (empêche modification de deleted_at,
--     created_at côté client)
--   - Trigger assert_lease_ownership_consistency (cohérence cross-FK sur leases)
--   - RPC SECURITY DEFINER pour soft-delete (seul point d'entrée légal pour deleted_at)
--
-- Décisions actées (source: docs/backlog/002-data-model-rls.md, 2026-05-28) :
--   - PK landlords = Option A (id = auth.users.id, 1-1). Aucune migration de données.
--   - FK landlords.id → auth.users(id) ON DELETE NO ACTION (protection rétention)
--   - Soft-delete via USING dans les policies RLS (deleted_at IS NULL)
--   - Aucune policy INSERT sur landlords côté client (trigger handle_new_user)
--   - Aucune policy DELETE sur aucune table (soft-delete uniquement)
--   - Trigger tr_01_prevent_protected avant tr_02_set_updated_at (ordre alphabétique PG)
--   - Flag de session app.allow_deleted_at_change pour autoriser les RPC soft-delete
-- ============================================================================

BEGIN;

-- ============================================================================
-- Section 0 : Fonction protect_protected_columns_change (réutilisable, 4 tables)
-- ============================================================================
-- WHY: Les policies RLS ne protègent pas les colonnes individuelles — un client
-- avec une policy INSERT ou UPDATE pourrait modifier deleted_at, created_at directement.
-- Ce trigger BEFORE INSERT OR UPDATE bloque ça. Il s'appuie sur le flag de session
-- app.allow_deleted_at_change = '1' que les RPC soft_delete_* positionnent
-- (SET LOCAL = scope transaction, pas de risque de fuite entre connexions).
-- ERRCODE 42501 = insufficient_privilege, cohérent avec une violation de policy.

CREATE OR REPLACE FUNCTION public.prevent_protected_columns_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- -----------------------------------------------------------------------
  -- Branche INSERT
  -- -----------------------------------------------------------------------
  IF TG_OP = 'INSERT' THEN
    -- deleted_at : un INSERT client ne doit jamais poser deleted_at.
    -- Un client malveillant pourrait ainsi "pré-soft-deleter" une ligne
    -- dès la création, contournant la sémantique soft-delete (qui passe
    -- exclusivement par les RPC soft_delete_*).
    -- Le flag app.allow_deleted_at_change est réservé aux RPC SECURITY DEFINER ;
    -- on l'accepte ici aussi pour cohérence (cas de tests superuser).
    IF NEW.deleted_at IS NOT NULL
       AND current_setting('app.allow_deleted_at_change', true) <> '1' THEN
      RAISE EXCEPTION 'Column deleted_at cannot be set on INSERT. Use the soft_delete_* RPC.'
        USING ERRCODE = '42501';
    END IF;

    -- created_at : si le client fournit une valeur antidatée (ex: '2020-01-01'),
    -- on la force silencieusement à now(). Choix pragmatique : lever une exception
    -- serait pénalisant pour les clients qui passent explicitement now() ou omettent
    -- la colonne. La colonne a DEFAULT now() mais un INSERT explicite peut la contourner.
    -- Forcer garantit l'intégrité temporelle sans bloquer les cas légitimes.
    NEW.created_at := now();

    -- updated_at : forcé à now() aussi à l'INSERT (cohérence avec le comportement
    -- du trigger tr_02_set_updated_at qui maintient updated_at = now() sur UPDATE).
    NEW.updated_at := now();

    RETURN NEW;
  END IF;

  -- -----------------------------------------------------------------------
  -- Branche UPDATE
  -- -----------------------------------------------------------------------

  -- deleted_at : seules les RPC soft_delete_* (SECURITY DEFINER) peuvent le modifier.
  -- Elles positionnent le flag de session 'app.allow_deleted_at_change' = '1'
  -- via SET LOCAL (scope = transaction courante uniquement).
  IF NEW.deleted_at IS DISTINCT FROM OLD.deleted_at
     AND current_setting('app.allow_deleted_at_change', true) <> '1' THEN
    RAISE EXCEPTION 'Column deleted_at cannot be modified directly. Use the soft_delete_* RPC.'
      USING ERRCODE = '42501';
  END IF;

  -- created_at est immuable sans exception.
  IF NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'Column created_at is immutable.'
      USING ERRCODE = '42501';
  END IF;

  -- updated_at : neutralise la tentative client — set_updated_at (tr_02) s'en occupe.
  NEW.updated_at := OLD.updated_at;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.prevent_protected_columns_change() IS
  'Trigger BEFORE INSERT OR UPDATE réutilisable. '
  'À l''INSERT : bloque deleted_at non-NULL (sauf flag app.allow_deleted_at_change=1), '
  'force created_at et updated_at à now() (silencieux — correction pragmatique des antidates). '
  'À l''UPDATE : bloque la modification directe de deleted_at (sauf flag) et de created_at ; '
  'neutralise updated_at (repris par set_updated_at tr_02). ERRCODE 42501. FEAT-002 F2.';

-- ============================================================================
-- Section 1 : ALTER landlords — extension de colonnes + changement FK
-- ============================================================================
-- Colonnes dans les deux schémas (additive — pas de migration de données)
-- full_name NULL : rempli plus tard dans les paramètres UI (FEAT-003+)

-- PROD
ALTER TABLE public.landlords
  ADD COLUMN IF NOT EXISTS full_name text,
  ADD COLUMN IF NOT EXISTS phone     text,
  ADD COLUMN IF NOT EXISTS address   text;

COMMENT ON COLUMN public.landlords.full_name IS 'Nom complet du propriétaire (facultatif à la création, complété dans les paramètres). FEAT-002.';
COMMENT ON COLUMN public.landlords.phone     IS 'Téléphone du propriétaire (facultatif). FEAT-002.';
COMMENT ON COLUMN public.landlords.address   IS 'Adresse postale du propriétaire (facultatif). FEAT-002.';

-- Changer la FK CASCADE → NO ACTION pour protéger la rétention 5 ans.
-- ON DELETE NO ACTION = la suppression de auth.users échoue si une ligne landlords existe.
-- Le flux RGPD "droit à l'effacement" passera par une Edge Function d'anonymisation (P1).
ALTER TABLE public.landlords DROP CONSTRAINT IF EXISTS landlords_id_fkey;
ALTER TABLE public.landlords
  ADD CONSTRAINT landlords_id_fkey
  FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE NO ACTION;

-- Trigger BEFORE INSERT OR UPDATE sur public.landlords (protect + updated_at) [F2: étendu à INSERT]
DROP TRIGGER IF EXISTS tr_01_prevent_protected_columns_change_landlords ON public.landlords;
CREATE TRIGGER tr_01_prevent_protected_columns_change_landlords
  BEFORE INSERT OR UPDATE ON public.landlords
  FOR EACH ROW EXECUTE FUNCTION public.prevent_protected_columns_change();

-- Le trigger tr_02 (set_updated_at) existe déjà sur public.landlords sous le nom
-- set_landlords_updated_at (FEAT-001). On le renomme pour garantir l'ordre alphabétique
-- tr_01 < tr_02. PG exécute les triggers BEFORE dans l'ordre alphabétique de leur nom.
-- Renommage via DROP + CREATE (ALTER TRIGGER RENAME requiert PG >= 15, pas disponible
-- sur toutes les versions Supabase free tier).
DROP TRIGGER IF EXISTS set_landlords_updated_at ON public.landlords;
CREATE TRIGGER tr_02_set_updated_at_landlords
  BEFORE UPDATE ON public.landlords
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- DEV
ALTER TABLE dev.landlords
  ADD COLUMN IF NOT EXISTS full_name text,
  ADD COLUMN IF NOT EXISTS phone     text,
  ADD COLUMN IF NOT EXISTS address   text;

COMMENT ON COLUMN dev.landlords.full_name IS 'Nom complet du propriétaire (facultatif à la création, complété dans les paramètres). FEAT-002.';
COMMENT ON COLUMN dev.landlords.phone     IS 'Téléphone du propriétaire (facultatif). FEAT-002.';
COMMENT ON COLUMN dev.landlords.address   IS 'Adresse postale du propriétaire (facultatif). FEAT-002.';

ALTER TABLE dev.landlords DROP CONSTRAINT IF EXISTS dev_landlords_id_fkey;
ALTER TABLE dev.landlords
  ADD CONSTRAINT dev_landlords_id_fkey
  FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE NO ACTION;

DROP TRIGGER IF EXISTS tr_01_prevent_protected_columns_change_landlords ON dev.landlords;
CREATE TRIGGER tr_01_prevent_protected_columns_change_landlords
  BEFORE INSERT OR UPDATE ON dev.landlords
  FOR EACH ROW EXECUTE FUNCTION public.prevent_protected_columns_change();

DROP TRIGGER IF EXISTS set_landlords_updated_at ON dev.landlords;
CREATE TRIGGER tr_02_set_updated_at_landlords
  BEFORE UPDATE ON dev.landlords
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ============================================================================
-- Section 2 : CREATE TABLE properties
-- ============================================================================
-- Chaque propriété appartient à un landlord (landlord_id = auth.uid() dans RLS).
-- ON DELETE RESTRICT sur landlord_id : cohérent avec la politique NO ACTION sur
-- auth.users — on ne peut pas hard-delete un landlord qui a des properties.
-- type : enum CHECK (appartement, maison, studio, autre)

-- ---- PROD ----
CREATE TABLE public.properties (
  id          uuid           PRIMARY KEY DEFAULT gen_random_uuid(),
  landlord_id uuid           NOT NULL REFERENCES public.landlords(id) ON DELETE RESTRICT,
  name        text           NOT NULL CHECK (length(trim(name)) > 0),
  address     text           NOT NULL CHECK (length(trim(address)) > 0),
  type        text           NOT NULL CHECK (type IN ('appartement', 'maison', 'studio', 'autre')),
  surface_m2  numeric(6,2)   CHECK (surface_m2 IS NULL OR surface_m2 > 0),
  created_at  timestamptz    NOT NULL DEFAULT now(),
  updated_at  timestamptz    NOT NULL DEFAULT now(),
  deleted_at  timestamptz
);

COMMENT ON TABLE  public.properties IS 'Biens immobiliers appartenant à un propriétaire. Soft-delete via deleted_at. FEAT-002.';
COMMENT ON COLUMN public.properties.type       IS 'Enum SQL : appartement, maison, studio, autre.';
COMMENT ON COLUMN public.properties.surface_m2 IS 'Surface en m² (nullable, arrondie à 2 décimales). Positif si renseigné.';
COMMENT ON COLUMN public.properties.deleted_at IS 'Soft-delete RGPD/rétention. Protégé par trigger tr_01. Modifiable uniquement via soft_delete_property().';

ALTER TABLE public.properties ENABLE ROW LEVEL SECURITY;

CREATE POLICY "properties_select_own" ON public.properties
  FOR SELECT
  USING (landlord_id = auth.uid() AND deleted_at IS NULL);

CREATE POLICY "properties_insert_own" ON public.properties
  FOR INSERT
  WITH CHECK (landlord_id = auth.uid());

CREATE POLICY "properties_update_own" ON public.properties
  FOR UPDATE
  USING  (landlord_id = auth.uid() AND deleted_at IS NULL)
  WITH CHECK (landlord_id = auth.uid());

-- Aucune policy DELETE : suppression physique interdite côté client.

CREATE INDEX idx_public_properties_landlord_id ON public.properties(landlord_id);

DROP TRIGGER IF EXISTS tr_01_prevent_protected_columns_change_properties ON public.properties;
CREATE TRIGGER tr_01_prevent_protected_columns_change_properties
  BEFORE INSERT OR UPDATE ON public.properties
  FOR EACH ROW EXECUTE FUNCTION public.prevent_protected_columns_change();

DROP TRIGGER IF EXISTS tr_02_set_updated_at_properties ON public.properties;
CREATE TRIGGER tr_02_set_updated_at_properties
  BEFORE UPDATE ON public.properties
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---- DEV ----
CREATE TABLE dev.properties (
  id          uuid           PRIMARY KEY DEFAULT gen_random_uuid(),
  landlord_id uuid           NOT NULL REFERENCES dev.landlords(id) ON DELETE RESTRICT,
  name        text           NOT NULL CHECK (length(trim(name)) > 0),
  address     text           NOT NULL CHECK (length(trim(address)) > 0),
  type        text           NOT NULL CHECK (type IN ('appartement', 'maison', 'studio', 'autre')),
  surface_m2  numeric(6,2)   CHECK (surface_m2 IS NULL OR surface_m2 > 0),
  created_at  timestamptz    NOT NULL DEFAULT now(),
  updated_at  timestamptz    NOT NULL DEFAULT now(),
  deleted_at  timestamptz
);

COMMENT ON TABLE  dev.properties IS 'Mirror DEV de public.properties. FEAT-002.';
COMMENT ON COLUMN dev.properties.deleted_at IS 'Soft-delete RGPD/rétention. Protégé par trigger tr_01. Modifiable uniquement via dev.soft_delete_property().';

ALTER TABLE dev.properties ENABLE ROW LEVEL SECURITY;

CREATE POLICY "properties_select_own" ON dev.properties
  FOR SELECT
  USING (landlord_id = auth.uid() AND deleted_at IS NULL);

CREATE POLICY "properties_insert_own" ON dev.properties
  FOR INSERT
  WITH CHECK (landlord_id = auth.uid());

CREATE POLICY "properties_update_own" ON dev.properties
  FOR UPDATE
  USING  (landlord_id = auth.uid() AND deleted_at IS NULL)
  WITH CHECK (landlord_id = auth.uid());

CREATE INDEX idx_dev_properties_landlord_id ON dev.properties(landlord_id);

DROP TRIGGER IF EXISTS tr_01_prevent_protected_columns_change_properties ON dev.properties;
CREATE TRIGGER tr_01_prevent_protected_columns_change_properties
  BEFORE INSERT OR UPDATE ON dev.properties
  FOR EACH ROW EXECUTE FUNCTION public.prevent_protected_columns_change();

DROP TRIGGER IF EXISTS tr_02_set_updated_at_properties ON dev.properties;
CREATE TRIGGER tr_02_set_updated_at_properties
  BEFORE UPDATE ON dev.properties
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ============================================================================
-- Section 3 : CREATE TABLE tenants
-- ============================================================================
-- Les locataires sont liés à un landlord. Isolés par schéma.
-- email : regex minimaliste (garde-fou SQL ; validation forte côté Flutter).

-- ---- PROD ----
CREATE TABLE public.tenants (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  landlord_id uuid        NOT NULL REFERENCES public.landlords(id) ON DELETE RESTRICT,
  first_name  text        NOT NULL CHECK (length(trim(first_name)) > 0),
  last_name   text        NOT NULL CHECK (length(trim(last_name)) > 0),
  email       text        NOT NULL CHECK (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  phone       text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  deleted_at  timestamptz
);

COMMENT ON TABLE  public.tenants IS 'Locataires appartenant à un propriétaire. Soft-delete via deleted_at. FEAT-002.';
COMMENT ON COLUMN public.tenants.email      IS 'Email du locataire. Regex CHECK minimaliste SQL — validation forte côté Flutter.';
COMMENT ON COLUMN public.tenants.deleted_at IS 'Soft-delete RGPD/rétention. Protégé par trigger tr_01. Modifiable uniquement via soft_delete_tenant().';

ALTER TABLE public.tenants ENABLE ROW LEVEL SECURITY;

CREATE POLICY "tenants_select_own" ON public.tenants
  FOR SELECT
  USING (landlord_id = auth.uid() AND deleted_at IS NULL);

CREATE POLICY "tenants_insert_own" ON public.tenants
  FOR INSERT
  WITH CHECK (landlord_id = auth.uid());

CREATE POLICY "tenants_update_own" ON public.tenants
  FOR UPDATE
  USING  (landlord_id = auth.uid() AND deleted_at IS NULL)
  WITH CHECK (landlord_id = auth.uid());

CREATE INDEX idx_public_tenants_landlord_id ON public.tenants(landlord_id);

DROP TRIGGER IF EXISTS tr_01_prevent_protected_columns_change_tenants ON public.tenants;
CREATE TRIGGER tr_01_prevent_protected_columns_change_tenants
  BEFORE INSERT OR UPDATE ON public.tenants
  FOR EACH ROW EXECUTE FUNCTION public.prevent_protected_columns_change();

DROP TRIGGER IF EXISTS tr_02_set_updated_at_tenants ON public.tenants;
CREATE TRIGGER tr_02_set_updated_at_tenants
  BEFORE UPDATE ON public.tenants
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---- DEV ----
CREATE TABLE dev.tenants (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  landlord_id uuid        NOT NULL REFERENCES dev.landlords(id) ON DELETE RESTRICT,
  first_name  text        NOT NULL CHECK (length(trim(first_name)) > 0),
  last_name   text        NOT NULL CHECK (length(trim(last_name)) > 0),
  email       text        NOT NULL CHECK (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  phone       text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  deleted_at  timestamptz
);

COMMENT ON TABLE  dev.tenants IS 'Mirror DEV de public.tenants. FEAT-002.';
COMMENT ON COLUMN dev.tenants.deleted_at IS 'Soft-delete RGPD/rétention. Protégé par trigger tr_01. Modifiable uniquement via dev.soft_delete_tenant().';

ALTER TABLE dev.tenants ENABLE ROW LEVEL SECURITY;

CREATE POLICY "tenants_select_own" ON dev.tenants
  FOR SELECT
  USING (landlord_id = auth.uid() AND deleted_at IS NULL);

CREATE POLICY "tenants_insert_own" ON dev.tenants
  FOR INSERT
  WITH CHECK (landlord_id = auth.uid());

CREATE POLICY "tenants_update_own" ON dev.tenants
  FOR UPDATE
  USING  (landlord_id = auth.uid() AND deleted_at IS NULL)
  WITH CHECK (landlord_id = auth.uid());

CREATE INDEX idx_dev_tenants_landlord_id ON dev.tenants(landlord_id);

DROP TRIGGER IF EXISTS tr_01_prevent_protected_columns_change_tenants ON dev.tenants;
CREATE TRIGGER tr_01_prevent_protected_columns_change_tenants
  BEFORE INSERT OR UPDATE ON dev.tenants
  FOR EACH ROW EXECUTE FUNCTION public.prevent_protected_columns_change();

DROP TRIGGER IF EXISTS tr_02_set_updated_at_tenants ON dev.tenants;
CREATE TRIGGER tr_02_set_updated_at_tenants
  BEFORE UPDATE ON dev.tenants
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ============================================================================
-- Section 4 : CREATE TABLE leases
-- ============================================================================
-- Bail entre un propriétaire, un bien, et un locataire.
-- Trois FK RESTRICT pour protéger la rétention légale.
-- landlord_id redondant (dénormalisation volontaire pour simplifier RLS).
-- rent_amount_cents et charges_amount_cents en centimes (pas de float).
-- Trigger assert_lease_ownership_consistency sur INSERT OR UPDATE.

-- ---- Fonction de cohérence cross-FK — PROD ----
-- WHY: Garantit que property_id et tenant_id appartiennent au même landlord_id
-- que la lease. Garde-fou indépendant de RLS (résiste à une erreur de policy).
-- La version dev lit dev.properties et dev.tenants (fonctions séparées —
-- pas de SQL dynamique pour garder un plan d'exécution stable et auditable).

CREATE OR REPLACE FUNCTION public.assert_lease_ownership_consistency()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
-- SECURITY DEFINER : la fonction s'exécute avec les droits du propriétaire (postgres),
-- bypasse donc RLS sur properties/tenants. C'est intentionnel : on veut voir TOUTES
-- les lignes pour valider la cohérence cross-FK, y compris celles soft-deleted ou
-- appartenant à d'autres landlords (c'est précisément ce qu'on cherche à détecter).
-- Sans SECURITY DEFINER, le SELECT passerait par RLS avec le rôle de l'appelant
-- (authenticated), ce qui peut renvoyer NULL pour des lignes existantes mais non
-- visibles — rendant le message d'erreur trompeur ("NULL IS DISTINCT FROM").
-- SET search_path = public : fixe le search_path pour éviter tout override malveillant.
DECLARE
  prop_landlord uuid;
  tnt_landlord  uuid;
BEGIN
  -- Cas 1 : property inexistante (prop_landlord reste NULL si aucune ligne trouvée)
  SELECT landlord_id INTO prop_landlord
    FROM public.properties WHERE id = NEW.property_id;

  IF prop_landlord IS NULL AND NOT EXISTS (
    SELECT 1 FROM public.properties WHERE id = NEW.property_id
  ) THEN
    RAISE EXCEPTION 'Lease references a non-existent property_id (%)',
      NEW.property_id
      USING ERRCODE = '23514';
  END IF;

  -- Cas 2 : tenant inexistant
  SELECT landlord_id INTO tnt_landlord
    FROM public.tenants WHERE id = NEW.tenant_id;

  IF tnt_landlord IS NULL AND NOT EXISTS (
    SELECT 1 FROM public.tenants WHERE id = NEW.tenant_id
  ) THEN
    RAISE EXCEPTION 'Lease references a non-existent tenant_id (%)',
      NEW.tenant_id
      USING ERRCODE = '23514';
  END IF;

  -- Cas 3 : ownership mismatch — property ou tenant appartient à un autre landlord
  IF prop_landlord IS DISTINCT FROM NEW.landlord_id THEN
    RAISE EXCEPTION 'Ownership mismatch: property_id (%) belongs to landlord %, but lease.landlord_id is %',
      NEW.property_id, prop_landlord, NEW.landlord_id
      USING ERRCODE = '23514';
  END IF;

  IF tnt_landlord IS DISTINCT FROM NEW.landlord_id THEN
    RAISE EXCEPTION 'Ownership mismatch: tenant_id (%) belongs to landlord %, but lease.landlord_id is %',
      NEW.tenant_id, tnt_landlord, NEW.landlord_id
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.assert_lease_ownership_consistency() IS
  'Trigger BEFORE INSERT OR UPDATE sur public.leases. SECURITY DEFINER + SET search_path=public. '
  'Vérifie 3 cas : property inexistante, tenant inexistant, ownership mismatch (property ou tenant '
  'appartient à un landlord différent de lease.landlord_id). ERRCODE 23514 (check_violation). '
  'Garde-fou indépendant des policies RLS. FEAT-002 F3.';

-- ---- Fonction de cohérence cross-FK — DEV ----
CREATE OR REPLACE FUNCTION dev.assert_lease_ownership_consistency()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = dev
AS $$
-- SECURITY DEFINER + SET search_path = dev : miroir exact de public.assert_lease_ownership_consistency()
-- mais opère sur le schéma dev. Même justification : bypass RLS nécessaire pour voir toutes
-- les lignes de dev.properties / dev.tenants indépendamment du rôle appelant.
DECLARE
  prop_landlord uuid;
  tnt_landlord  uuid;
BEGIN
  -- Cas 1 : property inexistante
  SELECT landlord_id INTO prop_landlord
    FROM dev.properties WHERE id = NEW.property_id;

  IF prop_landlord IS NULL AND NOT EXISTS (
    SELECT 1 FROM dev.properties WHERE id = NEW.property_id
  ) THEN
    RAISE EXCEPTION 'Lease references a non-existent property_id (%)',
      NEW.property_id
      USING ERRCODE = '23514';
  END IF;

  -- Cas 2 : tenant inexistant
  SELECT landlord_id INTO tnt_landlord
    FROM dev.tenants WHERE id = NEW.tenant_id;

  IF tnt_landlord IS NULL AND NOT EXISTS (
    SELECT 1 FROM dev.tenants WHERE id = NEW.tenant_id
  ) THEN
    RAISE EXCEPTION 'Lease references a non-existent tenant_id (%)',
      NEW.tenant_id
      USING ERRCODE = '23514';
  END IF;

  -- Cas 3 : ownership mismatch
  IF prop_landlord IS DISTINCT FROM NEW.landlord_id THEN
    RAISE EXCEPTION 'Ownership mismatch: property_id (%) belongs to landlord %, but lease.landlord_id is %',
      NEW.property_id, prop_landlord, NEW.landlord_id
      USING ERRCODE = '23514';
  END IF;

  IF tnt_landlord IS DISTINCT FROM NEW.landlord_id THEN
    RAISE EXCEPTION 'Ownership mismatch: tenant_id (%) belongs to landlord %, but lease.landlord_id is %',
      NEW.tenant_id, tnt_landlord, NEW.landlord_id
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION dev.assert_lease_ownership_consistency() IS
  'Mirror DEV de public.assert_lease_ownership_consistency(). SECURITY DEFINER + SET search_path=dev. '
  'Lit dev.properties et dev.tenants. FEAT-002 F3.';

-- ---- PROD ----
CREATE TABLE public.leases (
  id                    uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  landlord_id           uuid        NOT NULL REFERENCES public.landlords(id)   ON DELETE RESTRICT,
  property_id           uuid        NOT NULL REFERENCES public.properties(id)  ON DELETE RESTRICT,
  tenant_id             uuid        NOT NULL REFERENCES public.tenants(id)      ON DELETE RESTRICT,
  -- Montants en centimes d'euro (évite les erreurs d'arrondi float). Ex: 85000 = 850,00 €
  rent_amount_cents     integer     NOT NULL CHECK (rent_amount_cents > 0),
  charges_amount_cents  integer     NOT NULL DEFAULT 0 CHECK (charges_amount_cents >= 0),
  start_date            date        NOT NULL,
  -- end_date NULL = bail reconductible (CDI locatif). Quand renseigné, doit être > start_date.
  end_date              date        CHECK (end_date IS NULL OR end_date > start_date),
  -- status : active (en cours), terminated (résilié), archived (archivé)
  status                text        NOT NULL DEFAULT 'active'
                                    CHECK (status IN ('active', 'terminated', 'archived')),
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  deleted_at            timestamptz
);

COMMENT ON TABLE  public.leases IS 'Baux locatifs. landlord_id dénormalisé pour simplifier les policies RLS (landlord_id = auth.uid()). Soft-delete via deleted_at. FEAT-002.';
COMMENT ON COLUMN public.leases.rent_amount_cents    IS 'Loyer en centimes d''euro (entier). Ex: 85000 = 850,00 €. Pas de float pour éviter les erreurs d''arrondi.';
COMMENT ON COLUMN public.leases.charges_amount_cents IS 'Charges en centimes d''euro. 0 si incluses dans le loyer ou absentes.';
COMMENT ON COLUMN public.leases.end_date             IS 'NULL = bail reconductible. Si renseigné : end_date > start_date (CHECK SQL).';
COMMENT ON COLUMN public.leases.status               IS 'Enum : active, terminated, archived.';
COMMENT ON COLUMN public.leases.deleted_at           IS 'Soft-delete. Protégé par trigger tr_01. Modifiable uniquement via soft_delete_lease().';

ALTER TABLE public.leases ENABLE ROW LEVEL SECURITY;

CREATE POLICY "leases_select_own" ON public.leases
  FOR SELECT
  USING (landlord_id = auth.uid() AND deleted_at IS NULL);

CREATE POLICY "leases_insert_own" ON public.leases
  FOR INSERT
  WITH CHECK (landlord_id = auth.uid());

CREATE POLICY "leases_update_own" ON public.leases
  FOR UPDATE
  USING  (landlord_id = auth.uid() AND deleted_at IS NULL)
  WITH CHECK (landlord_id = auth.uid());

-- Index FK + filtrage RLS
CREATE INDEX idx_public_leases_landlord_id ON public.leases(landlord_id);
CREATE INDEX idx_public_leases_property_id ON public.leases(property_id);
CREATE INDEX idx_public_leases_tenant_id   ON public.leases(tenant_id);
-- Index partiel pour le dashboard (FEAT-010) : baux actifs non supprimés
CREATE INDEX idx_public_leases_status_active_partial
  ON public.leases(landlord_id)
  WHERE status = 'active' AND deleted_at IS NULL;

DROP TRIGGER IF EXISTS tr_00_assert_lease_ownership ON public.leases;
CREATE TRIGGER tr_00_assert_lease_ownership
  BEFORE INSERT OR UPDATE ON public.leases
  FOR EACH ROW EXECUTE FUNCTION public.assert_lease_ownership_consistency();

DROP TRIGGER IF EXISTS tr_01_prevent_protected_columns_change_leases ON public.leases;
CREATE TRIGGER tr_01_prevent_protected_columns_change_leases
  BEFORE INSERT OR UPDATE ON public.leases
  FOR EACH ROW EXECUTE FUNCTION public.prevent_protected_columns_change();

DROP TRIGGER IF EXISTS tr_02_set_updated_at_leases ON public.leases;
CREATE TRIGGER tr_02_set_updated_at_leases
  BEFORE UPDATE ON public.leases
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---- DEV ----
CREATE TABLE dev.leases (
  id                    uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  landlord_id           uuid        NOT NULL REFERENCES dev.landlords(id)   ON DELETE RESTRICT,
  property_id           uuid        NOT NULL REFERENCES dev.properties(id)  ON DELETE RESTRICT,
  tenant_id             uuid        NOT NULL REFERENCES dev.tenants(id)      ON DELETE RESTRICT,
  rent_amount_cents     integer     NOT NULL CHECK (rent_amount_cents > 0),
  charges_amount_cents  integer     NOT NULL DEFAULT 0 CHECK (charges_amount_cents >= 0),
  start_date            date        NOT NULL,
  end_date              date        CHECK (end_date IS NULL OR end_date > start_date),
  status                text        NOT NULL DEFAULT 'active'
                                    CHECK (status IN ('active', 'terminated', 'archived')),
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  deleted_at            timestamptz
);

COMMENT ON TABLE  dev.leases IS 'Mirror DEV de public.leases. FEAT-002.';
COMMENT ON COLUMN dev.leases.deleted_at IS 'Soft-delete. Protégé par trigger tr_01. Modifiable uniquement via dev.soft_delete_lease().';

ALTER TABLE dev.leases ENABLE ROW LEVEL SECURITY;

CREATE POLICY "leases_select_own" ON dev.leases
  FOR SELECT
  USING (landlord_id = auth.uid() AND deleted_at IS NULL);

CREATE POLICY "leases_insert_own" ON dev.leases
  FOR INSERT
  WITH CHECK (landlord_id = auth.uid());

CREATE POLICY "leases_update_own" ON dev.leases
  FOR UPDATE
  USING  (landlord_id = auth.uid() AND deleted_at IS NULL)
  WITH CHECK (landlord_id = auth.uid());

CREATE INDEX idx_dev_leases_landlord_id ON dev.leases(landlord_id);
CREATE INDEX idx_dev_leases_property_id ON dev.leases(property_id);
CREATE INDEX idx_dev_leases_tenant_id   ON dev.leases(tenant_id);
CREATE INDEX idx_dev_leases_status_active_partial
  ON dev.leases(landlord_id)
  WHERE status = 'active' AND deleted_at IS NULL;

DROP TRIGGER IF EXISTS tr_00_assert_lease_ownership ON dev.leases;
CREATE TRIGGER tr_00_assert_lease_ownership
  BEFORE INSERT OR UPDATE ON dev.leases
  FOR EACH ROW EXECUTE FUNCTION dev.assert_lease_ownership_consistency();

DROP TRIGGER IF EXISTS tr_01_prevent_protected_columns_change_leases ON dev.leases;
CREATE TRIGGER tr_01_prevent_protected_columns_change_leases
  BEFORE INSERT OR UPDATE ON dev.leases
  FOR EACH ROW EXECUTE FUNCTION public.prevent_protected_columns_change();

DROP TRIGGER IF EXISTS tr_02_set_updated_at_leases ON dev.leases;
CREATE TRIGGER tr_02_set_updated_at_leases
  BEFORE UPDATE ON dev.leases
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ============================================================================
-- Section 5 : RPC SECURITY DEFINER — soft-delete
-- ============================================================================
-- WHY SECURITY DEFINER: Le trigger tr_01 bloque toute modification de deleted_at
-- via UPDATE direct. Les RPC positionnent app.allow_deleted_at_change = '1'
-- (SET LOCAL = scope transaction) avant l'UPDATE, ce qui déverrouille le trigger
-- pour cette seule transaction.
-- Ownership check (landlord_id = auth.uid()) dans le WHERE : un User A ne peut
-- pas soft-delete les données de User B — le NOT FOUND est retourné silencieusement
-- (pas de fuite d'information sur l'existence de la ligne).
-- REVOKE ALL FROM PUBLIC + GRANT TO authenticated : principle of least privilege.

-- ---- soft_delete_landlord ---- (PROD)
CREATE OR REPLACE FUNCTION public.soft_delete_landlord()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM set_config('app.allow_deleted_at_change', '1', true);
  UPDATE public.landlords
    SET deleted_at = now()
    WHERE id = auth.uid()
      AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Landlord not found or already deleted'
      USING ERRCODE = 'P0002';
  END IF;
END;
$$;

COMMENT ON FUNCTION public.soft_delete_landlord() IS
  'RPC SECURITY DEFINER : soft-delete du landlord courant (auth.uid()). '
  'Pose SET LOCAL app.allow_deleted_at_change=1 pour contourner le trigger tr_01. FEAT-002.';

REVOKE ALL ON FUNCTION public.soft_delete_landlord() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.soft_delete_landlord() TO authenticated;

-- ---- soft_delete_property ---- (PROD)
CREATE OR REPLACE FUNCTION public.soft_delete_property(p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM set_config('app.allow_deleted_at_change', '1', true);
  UPDATE public.properties
    SET deleted_at = now()
    WHERE id = p_id
      AND landlord_id = auth.uid()
      AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Property not found or already deleted'
      USING ERRCODE = 'P0002';
  END IF;
END;
$$;

COMMENT ON FUNCTION public.soft_delete_property(uuid) IS
  'RPC SECURITY DEFINER : soft-delete d''une property (vérifie ownership landlord_id = auth.uid()). '
  'NOT FOUND si propriété inexistante ou appartenant à un autre user (pas de fuite). FEAT-002.';

REVOKE ALL ON FUNCTION public.soft_delete_property(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.soft_delete_property(uuid) TO authenticated;

-- ---- soft_delete_tenant ---- (PROD)
CREATE OR REPLACE FUNCTION public.soft_delete_tenant(p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM set_config('app.allow_deleted_at_change', '1', true);
  UPDATE public.tenants
    SET deleted_at = now()
    WHERE id = p_id
      AND landlord_id = auth.uid()
      AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tenant not found or already deleted'
      USING ERRCODE = 'P0002';
  END IF;
END;
$$;

COMMENT ON FUNCTION public.soft_delete_tenant(uuid) IS
  'RPC SECURITY DEFINER : soft-delete d''un tenant (vérifie ownership landlord_id = auth.uid()). FEAT-002.';

REVOKE ALL ON FUNCTION public.soft_delete_tenant(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.soft_delete_tenant(uuid) TO authenticated;

-- ---- soft_delete_lease ---- (PROD)
CREATE OR REPLACE FUNCTION public.soft_delete_lease(p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM set_config('app.allow_deleted_at_change', '1', true);
  UPDATE public.leases
    SET deleted_at = now()
    WHERE id = p_id
      AND landlord_id = auth.uid()
      AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Lease not found or already deleted'
      USING ERRCODE = 'P0002';
  END IF;
END;
$$;

COMMENT ON FUNCTION public.soft_delete_lease(uuid) IS
  'RPC SECURITY DEFINER : soft-delete d''un bail (vérifie ownership landlord_id = auth.uid()). FEAT-002.';

REVOKE ALL ON FUNCTION public.soft_delete_lease(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.soft_delete_lease(uuid) TO authenticated;

-- ---- Versions DEV des 4 RPC ----
-- Les fonctions DEV opèrent sur le schéma dev et sont exposées au rôle authenticated.

CREATE OR REPLACE FUNCTION dev.soft_delete_landlord()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = dev
AS $$
BEGIN
  PERFORM set_config('app.allow_deleted_at_change', '1', true);
  UPDATE dev.landlords
    SET deleted_at = now()
    WHERE id = auth.uid()
      AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Landlord not found or already deleted'
      USING ERRCODE = 'P0002';
  END IF;
END;
$$;

COMMENT ON FUNCTION dev.soft_delete_landlord() IS 'Mirror DEV de public.soft_delete_landlord(). FEAT-002.';
REVOKE ALL ON FUNCTION dev.soft_delete_landlord() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION dev.soft_delete_landlord() TO authenticated;

CREATE OR REPLACE FUNCTION dev.soft_delete_property(p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = dev
AS $$
BEGIN
  PERFORM set_config('app.allow_deleted_at_change', '1', true);
  UPDATE dev.properties
    SET deleted_at = now()
    WHERE id = p_id
      AND landlord_id = auth.uid()
      AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Property not found or already deleted'
      USING ERRCODE = 'P0002';
  END IF;
END;
$$;

COMMENT ON FUNCTION dev.soft_delete_property(uuid) IS 'Mirror DEV de public.soft_delete_property(). FEAT-002.';
REVOKE ALL ON FUNCTION dev.soft_delete_property(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION dev.soft_delete_property(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION dev.soft_delete_tenant(p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = dev
AS $$
BEGIN
  PERFORM set_config('app.allow_deleted_at_change', '1', true);
  UPDATE dev.tenants
    SET deleted_at = now()
    WHERE id = p_id
      AND landlord_id = auth.uid()
      AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tenant not found or already deleted'
      USING ERRCODE = 'P0002';
  END IF;
END;
$$;

COMMENT ON FUNCTION dev.soft_delete_tenant(uuid) IS 'Mirror DEV de public.soft_delete_tenant(). FEAT-002.';
REVOKE ALL ON FUNCTION dev.soft_delete_tenant(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION dev.soft_delete_tenant(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION dev.soft_delete_lease(p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = dev
AS $$
BEGIN
  PERFORM set_config('app.allow_deleted_at_change', '1', true);
  UPDATE dev.leases
    SET deleted_at = now()
    WHERE id = p_id
      AND landlord_id = auth.uid()
      AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Lease not found or already deleted'
      USING ERRCODE = 'P0002';
  END IF;
END;
$$;

COMMENT ON FUNCTION dev.soft_delete_lease(uuid) IS 'Mirror DEV de public.soft_delete_lease(). FEAT-002.';
REVOKE ALL ON FUNCTION dev.soft_delete_lease(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION dev.soft_delete_lease(uuid) TO authenticated;

-- ============================================================================
-- Section 6 : Vérification finale RLS sur les 4 tables × 2 schémas
-- ============================================================================
SELECT dev.assert_rls_both_schemas('landlords');
SELECT dev.assert_rls_both_schemas('properties');
SELECT dev.assert_rls_both_schemas('tenants');
SELECT dev.assert_rls_both_schemas('leases');

COMMIT;
