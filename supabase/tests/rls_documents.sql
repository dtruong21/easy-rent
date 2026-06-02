-- ============================================================================
-- Tests RLS — table documents (FEAT-009)
-- ============================================================================
-- Tests couverts :
--   1.  INSERT happy path (public) — User A insert document sur son propre lease
--   2.  INSERT happy path (dev) — même test sur schéma dev
--   3.  INSERT cross-lease → trigger tr_00 raise 23514 (public)
--   4.  INSERT cross-lease → trigger tr_00 raise 23514 (dev)
--   5.  SELECT own documents → rows retournés (public)
--   6.  SELECT cross-user → 0 rows (public)
--   7.  UPDATE category OK → updated_at bumpé (public)
--   8.  UPDATE filename → ERRCODE 42501 (tr_01b — public)
--   9.  UPDATE storage_path → ERRCODE 42501 (tr_01b — public)
--   10. UPDATE legal_hold → ERRCODE 42501 (tr_01b — public)
--   11. DELETE direct → 0 rows supprimées (pas de policy DELETE)
--   12. INSERT mime_type hors whitelist → ERRCODE 23514 CHECK (public)
--   13. INSERT size_bytes > 10485760 → ERRCODE 23514 CHECK (public)
--   14. INSERT category=bail_signe → trigger tr_00b force legal_hold=true (public)
--   15. INSERT category=autre + legal_hold=true → trigger tr_00b force legal_hold=false (public)
--   16. RPC soft_delete_document sans legal_hold → (storage_path, hard_deleted=true) (public)
--   17. RPC soft_delete_document avec legal_hold → (NULL, hard_deleted=false) (public)
--   18. RPC soft_delete_document cross-user → ERRCODE P0002 (public)
--   19. RPC soft_delete_document sur doc déjà supprimé → ERRCODE P0002 (public)
--   20. anon : INSERT refusé (42501)
--   21. anon : SELECT → 0 rows (aucune policy pour anon)
--   22. anon : RPC soft_delete_document → 42501
--   23. assert_rls_both_schemas('documents') passe
-- ============================================================================
-- USAGE: psql <connection_string> -f supabase/tests/rls_documents.sql
-- ============================================================================

BEGIN;

-- ============================================================================
-- Setup : deux users + landlords + properties + tenants + leases
-- ============================================================================
-- UUIDs préfixe 0009 (FEAT-009) — évite toute collision avec FEAT-006/007/008

INSERT INTO auth.users (
  id, instance_id, email, encrypted_password, email_confirmed_at,
  created_at, updated_at, raw_app_meta_data, raw_user_meta_data, aud, role
) VALUES
  ('00000000-0000-0000-0009-000000000001', '00000000-0000-0000-0000-000000000000',
   'doc_user_a@test.example', 'hashed', now(), now(), now(),
   '{"provider":"email","providers":["email"]}', '{}', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0009-000000000002', '00000000-0000-0000-0000-000000000000',
   'doc_user_b@test.example', 'hashed', now(), now(), now(),
   '{"provider":"email","providers":["email"]}', '{}', 'authenticated', 'authenticated')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.landlords (id, email) VALUES
  ('00000000-0000-0000-0009-000000000001', 'doc_user_a@test.example'),
  ('00000000-0000-0000-0009-000000000002', 'doc_user_b@test.example')
ON CONFLICT (id) DO NOTHING;

INSERT INTO dev.landlords (id, email) VALUES
  ('00000000-0000-0000-0009-000000000001', 'doc_user_a@test.example'),
  ('00000000-0000-0000-0009-000000000002', 'doc_user_b@test.example')
ON CONFLICT (id) DO NOTHING;

-- Properties
INSERT INTO public.properties (id, landlord_id, name, address, type) VALUES
  ('00000000-0000-0000-0009-000000000010', '00000000-0000-0000-0009-000000000001',
   'Prop A (docs)', '1 rue A', 'appartement'),
  ('00000000-0000-0000-0009-000000000020', '00000000-0000-0000-0009-000000000002',
   'Prop B (docs)', '2 rue B', 'maison');

INSERT INTO dev.properties (id, landlord_id, name, address, type) VALUES
  ('00000000-0000-0000-0009-000000000010', '00000000-0000-0000-0009-000000000001',
   'Prop A (docs)', '1 rue A', 'appartement'),
  ('00000000-0000-0000-0009-000000000020', '00000000-0000-0000-0009-000000000002',
   'Prop B (docs)', '2 rue B', 'maison');

-- Tenants
INSERT INTO public.tenants (id, landlord_id, first_name, last_name, email) VALUES
  ('00000000-0000-0000-0009-000000000011', '00000000-0000-0000-0009-000000000001',
   'Alice', 'Dupont', 'alice@test.example'),
  ('00000000-0000-0000-0009-000000000021', '00000000-0000-0000-0009-000000000002',
   'Bob', 'Martin', 'bob@test.example');

INSERT INTO dev.tenants (id, landlord_id, first_name, last_name, email) VALUES
  ('00000000-0000-0000-0009-000000000011', '00000000-0000-0000-0009-000000000001',
   'Alice', 'Dupont', 'alice@test.example'),
  ('00000000-0000-0000-0009-000000000021', '00000000-0000-0000-0009-000000000002',
   'Bob', 'Martin', 'bob@test.example');

-- Leases : une par user
INSERT INTO public.leases (
  id, landlord_id, property_id, tenant_id,
  rent_amount_cents, charges_amount_cents, start_date, status
) VALUES
  ('00000000-0000-0000-0009-000000000012', '00000000-0000-0000-0009-000000000001',
   '00000000-0000-0000-0009-000000000010', '00000000-0000-0000-0009-000000000011',
   80000, 5000, '2025-01-01', 'active'),
  ('00000000-0000-0000-0009-000000000022', '00000000-0000-0000-0009-000000000002',
   '00000000-0000-0000-0009-000000000020', '00000000-0000-0000-0009-000000000021',
   90000, 0, '2025-01-01', 'active');

INSERT INTO dev.leases (
  id, landlord_id, property_id, tenant_id,
  rent_amount_cents, charges_amount_cents, start_date, status
) VALUES
  ('00000000-0000-0000-0009-000000000012', '00000000-0000-0000-0009-000000000001',
   '00000000-0000-0000-0009-000000000010', '00000000-0000-0000-0009-000000000011',
   80000, 5000, '2025-01-01', 'active'),
  ('00000000-0000-0000-0009-000000000022', '00000000-0000-0000-0009-000000000002',
   '00000000-0000-0000-0009-000000000020', '00000000-0000-0000-0009-000000000021',
   90000, 0, '2025-01-01', 'active');

-- ============================================================================
-- TEST 1 : INSERT happy path (public) — User A insert sur son propre lease
-- ============================================================================

DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0009-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    INSERT INTO public.documents (
      id, landlord_id, lease_id, category,
      filename, storage_path, mime_type, size_bytes
    ) VALUES (
      '00000000-0000-0000-0009-000000000101',
      '00000000-0000-0000-0009-000000000001',
      '00000000-0000-0000-0009-000000000012',
      'attestation_assurance',
      'assurance_2025.pdf',
      'prod/00000000-0000-0000-0009-000000000001/00000000-0000-0000-0009-000000000101.pdf',
      'application/pdf',
      524288
    );
    RESET ROLE;
    RAISE NOTICE '[PASS] TEST 1 (public): INSERT happy path — User A insert document sur son lease';
  EXCEPTION
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 1 (public): INSERT devrait réussir (SQLSTATE %, msg: %)',
        SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 2 : INSERT happy path (dev)
-- ============================================================================

DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0009-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    INSERT INTO dev.documents (
      id, landlord_id, lease_id, category,
      filename, storage_path, mime_type, size_bytes
    ) VALUES (
      '00000000-0000-0000-0009-000000000201',
      '00000000-0000-0000-0009-000000000001',
      '00000000-0000-0000-0009-000000000012',
      'attestation_assurance',
      'assurance_2025_dev.pdf',
      'dev/00000000-0000-0000-0009-000000000001/00000000-0000-0000-0009-000000000201.pdf',
      'application/pdf',
      524288
    );
    RESET ROLE;
    RAISE NOTICE '[PASS] TEST 2 (dev): INSERT happy path — User A insert document sur son lease';
  EXCEPTION
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 2 (dev): INSERT devrait réussir (SQLSTATE %, msg: %)',
        SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 3 : INSERT avec lease_id cross-user → trigger tr_00 raise 23514 (public)
-- ============================================================================
-- User A essaie d'insérer un document en référençant le bail de User B.
-- Le trigger assert_document_lease_ownership() doit bloquer avec ERRCODE 23514.

DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0009-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    INSERT INTO public.documents (
      id, landlord_id, lease_id, category,
      filename, storage_path, mime_type, size_bytes
    ) VALUES (
      '00000000-0000-0000-0009-000000000103',
      '00000000-0000-0000-0009-000000000001',
      '00000000-0000-0000-0009-000000000022', -- lease de User B !
      'autre',
      'cross_lease.pdf',
      'prod/00000000-0000-0000-0009-000000000001/00000000-0000-0000-0009-000000000103.pdf',
      'application/pdf',
      1024
    );
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 3 (public): INSERT cross-lease devrait être bloqué par tr_00';
  EXCEPTION
    WHEN check_violation THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 3 (public): INSERT cross-lease bloqué par tr_00 (23514 check_violation)';
    WHEN insufficient_privilege THEN
      -- RLS bloque avant même le trigger si landlord_id mismatch
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 3 (public): INSERT cross-lease bloqué (42501 — RLS avant trigger)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 3 (public): Erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 4 : INSERT avec lease_id cross-user → trigger tr_00 raise 23514 (dev)
-- ============================================================================

DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0009-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    INSERT INTO dev.documents (
      id, landlord_id, lease_id, category,
      filename, storage_path, mime_type, size_bytes
    ) VALUES (
      '00000000-0000-0000-0009-000000000204',
      '00000000-0000-0000-0009-000000000001',
      '00000000-0000-0000-0009-000000000022', -- lease de User B !
      'autre',
      'cross_lease_dev.pdf',
      'dev/00000000-0000-0000-0009-000000000001/00000000-0000-0000-0009-000000000204.pdf',
      'application/pdf',
      1024
    );
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 4 (dev): INSERT cross-lease devrait être bloqué par tr_00';
  EXCEPTION
    WHEN check_violation THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 4 (dev): INSERT cross-lease bloqué par tr_00 (23514 check_violation)';
    WHEN insufficient_privilege THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 4 (dev): INSERT cross-lease bloqué (42501 — RLS avant trigger)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 4 (dev): Erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 5 : SELECT — User A voit ses propres documents (public)
-- ============================================================================

DO $$
DECLARE row_count integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0009-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  SELECT COUNT(*) INTO row_count
    FROM public.documents
    WHERE lease_id = '00000000-0000-0000-0009-000000000012';

  RESET ROLE;

  IF row_count < 1 THEN
    RAISE EXCEPTION '[FAIL] TEST 5 (public): User A devrait voir ses documents (got %)', row_count;
  END IF;
  RAISE NOTICE '[PASS] TEST 5 (public): User A voit ses documents (count=%)', row_count;
END $$;

-- ============================================================================
-- TEST 6 : SELECT cross-user → 0 rows (public)
-- ============================================================================

DO $$
DECLARE row_count integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0009-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  -- Insérer un doc de User B en superuser pour avoir quelque chose à tester
  RESET ROLE;
  INSERT INTO public.documents (
    id, landlord_id, lease_id, category,
    filename, storage_path, mime_type, size_bytes
  ) VALUES (
    '00000000-0000-0000-0009-000000000102',
    '00000000-0000-0000-0009-000000000002',
    '00000000-0000-0000-0009-000000000022',
    'autre',
    'doc_user_b.pdf',
    'prod/00000000-0000-0000-0009-000000000002/00000000-0000-0000-0009-000000000102.pdf',
    'application/pdf',
    2048
  ) ON CONFLICT (id) DO NOTHING;

  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0009-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  SELECT COUNT(*) INTO row_count
    FROM public.documents
    WHERE landlord_id = '00000000-0000-0000-0009-000000000002';

  RESET ROLE;

  IF row_count <> 0 THEN
    RAISE EXCEPTION '[FAIL] TEST 6 (public): User A ne devrait pas voir les docs de User B (got %)', row_count;
  END IF;
  RAISE NOTICE '[PASS] TEST 6 (public): SELECT cross-user → 0 rows (isolation RLS OK)';
END $$;

-- ============================================================================
-- TEST 7 : UPDATE category OK → updated_at bumpé (public)
-- ============================================================================

DO $$
DECLARE
  old_updated_at timestamptz;
  new_updated_at timestamptz;
  new_category   text;
BEGIN
  -- Récupère l'updated_at courant en superuser
  SELECT updated_at INTO old_updated_at
    FROM public.documents
    WHERE id = '00000000-0000-0000-0009-000000000101';

  -- Attendre un tick (timestamptz est précis à la microseconde)
  PERFORM pg_sleep(0.01);

  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0009-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    UPDATE public.documents
       SET category = 'quittance_scannee'
     WHERE id = '00000000-0000-0000-0009-000000000101';
    RESET ROLE;
  EXCEPTION
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 7 (public): UPDATE category devrait réussir (SQLSTATE %, msg: %)',
        SQLSTATE, SQLERRM;
  END;

  -- Vérification en superuser
  SELECT updated_at, category::text INTO new_updated_at, new_category
    FROM public.documents
    WHERE id = '00000000-0000-0000-0009-000000000101';

  IF new_category <> 'quittance_scannee' THEN
    RAISE EXCEPTION '[FAIL] TEST 7 (public): category devrait être quittance_scannee, got %', new_category;
  END IF;

  RAISE NOTICE '[PASS] TEST 7 (public): UPDATE category OK (category=%, updated_at bumpé=%)',
    new_category, new_updated_at > old_updated_at;
END $$;

-- ============================================================================
-- TEST 8 : UPDATE filename → ERRCODE 42501 (tr_01b — public)
-- ============================================================================

DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0009-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    UPDATE public.documents
       SET filename = 'hacked_filename.pdf'
     WHERE id = '00000000-0000-0000-0009-000000000101';
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 8 (public): UPDATE filename devrait être bloqué par tr_01b';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 8 (public): UPDATE filename bloqué par tr_01b (42501 insufficient_privilege)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 8 (public): Erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 9 : UPDATE storage_path → ERRCODE 42501 (tr_01b — public)
-- ============================================================================

DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0009-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    UPDATE public.documents
       SET storage_path = 'prod/evil/path.pdf'
     WHERE id = '00000000-0000-0000-0009-000000000101';
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 9 (public): UPDATE storage_path devrait être bloqué par tr_01b';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 9 (public): UPDATE storage_path bloqué par tr_01b (42501)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 9 (public): Erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 10 : UPDATE legal_hold → ERRCODE 42501 (tr_01b — public)
-- ============================================================================

DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0009-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    UPDATE public.documents
       SET legal_hold = true
     WHERE id = '00000000-0000-0000-0009-000000000101';
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 10 (public): UPDATE legal_hold devrait être bloqué par tr_01b';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 10 (public): UPDATE legal_hold bloqué par tr_01b (42501)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 10 (public): Erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 11 : DELETE direct → 0 rows supprimées (pas de policy DELETE)
-- ============================================================================
-- PostgreSQL sans policy DELETE retourne 0 rows affectées silencieusement
-- (la ligne n'est pas "visible" pour DELETE — comportement cohérent avec
-- les tests rls_payments.sql test #28).

DO $$
DECLARE rows_deleted integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0009-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  DELETE FROM public.documents
    WHERE id = '00000000-0000-0000-0009-000000000101';
  GET DIAGNOSTICS rows_deleted = ROW_COUNT;

  RESET ROLE;

  IF rows_deleted <> 0 THEN
    RAISE EXCEPTION '[FAIL] TEST 11 (public): DELETE direct devrait retourner 0 rows, got %', rows_deleted;
  END IF;
  RAISE NOTICE '[PASS] TEST 11 (public): DELETE direct → 0 rows (pas de policy DELETE — soft-delete via RPC uniquement)';
END $$;

-- ============================================================================
-- TEST 12 : INSERT mime_type hors whitelist → ERRCODE 23514 CHECK (public)
-- ============================================================================

DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0009-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    INSERT INTO public.documents (
      id, landlord_id, lease_id, category,
      filename, storage_path, mime_type, size_bytes
    ) VALUES (
      '00000000-0000-0000-0009-000000000112',
      '00000000-0000-0000-0009-000000000001',
      '00000000-0000-0000-0009-000000000012',
      'autre',
      'document.docx',
      'prod/00000000-0000-0000-0009-000000000001/00000000-0000-0000-0009-000000000112.docx',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document', -- hors whitelist
      1024
    );
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 12 (public): INSERT mime_type hors whitelist devrait être refusé';
  EXCEPTION
    WHEN check_violation THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 12 (public): mime_type hors whitelist refusé (23514 check_violation)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 12 (public): Erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 13 : INSERT size_bytes > 10485760 → ERRCODE 23514 CHECK (public)
-- ============================================================================

DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0009-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    INSERT INTO public.documents (
      id, landlord_id, lease_id, category,
      filename, storage_path, mime_type, size_bytes
    ) VALUES (
      '00000000-0000-0000-0009-000000000113',
      '00000000-0000-0000-0009-000000000001',
      '00000000-0000-0000-0009-000000000012',
      'autre',
      'huge_file.pdf',
      'prod/00000000-0000-0000-0009-000000000001/00000000-0000-0000-0009-000000000113.pdf',
      'application/pdf',
      10485761 -- 1 octet de trop
    );
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 13 (public): INSERT size_bytes > 10MB devrait être refusé';
  EXCEPTION
    WHEN check_violation THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 13 (public): size_bytes > 10MB refusé (23514 check_violation)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 13 (public): Erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 14 : INSERT category=bail_signe → trigger tr_00b force legal_hold=true (public)
-- ============================================================================

DO $$
DECLARE actual_legal_hold boolean;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0009-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  INSERT INTO public.documents (
    id, landlord_id, lease_id, category,
    filename, storage_path, mime_type, size_bytes,
    legal_hold  -- client envoie false, trigger doit écraser à true
  ) VALUES (
    '00000000-0000-0000-0009-000000000114',
    '00000000-0000-0000-0009-000000000001',
    '00000000-0000-0000-0009-000000000012',
    'bail_signe',
    'bail_2025.pdf',
    'prod/00000000-0000-0000-0009-000000000001/00000000-0000-0000-0009-000000000114.pdf',
    'application/pdf',
    204800,
    false  -- volontairement false — le trigger doit l'écraser à true
  );

  RESET ROLE;

  -- Vérification en superuser
  SELECT legal_hold INTO actual_legal_hold
    FROM public.documents
    WHERE id = '00000000-0000-0000-0009-000000000114';

  IF actual_legal_hold IS NOT TRUE THEN
    RAISE EXCEPTION '[FAIL] TEST 14 (public): legal_hold devrait être true pour bail_signe, got %', actual_legal_hold;
  END IF;
  RAISE NOTICE '[PASS] TEST 14 (public): trigger tr_00b force legal_hold=true pour category=bail_signe';
END $$;

-- ============================================================================
-- TEST 15 : INSERT category=autre + legal_hold=true → trigger tr_00b force legal_hold=false (public)
-- ============================================================================

DO $$
DECLARE actual_legal_hold boolean;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0009-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  INSERT INTO public.documents (
    id, landlord_id, lease_id, category,
    filename, storage_path, mime_type, size_bytes,
    legal_hold  -- client envoie true, trigger doit écraser à false
  ) VALUES (
    '00000000-0000-0000-0009-000000000115',
    '00000000-0000-0000-0009-000000000001',
    '00000000-0000-0000-0009-000000000012',
    'autre',
    'facture_2025.pdf',
    'prod/00000000-0000-0000-0009-000000000001/00000000-0000-0000-0009-000000000115.pdf',
    'application/pdf',
    102400,
    true  -- volontairement true — le trigger doit l'écraser à false
  );

  RESET ROLE;

  SELECT legal_hold INTO actual_legal_hold
    FROM public.documents
    WHERE id = '00000000-0000-0000-0009-000000000115';

  IF actual_legal_hold IS NOT FALSE THEN
    RAISE EXCEPTION '[FAIL] TEST 15 (public): legal_hold devrait être false pour category=autre, got %', actual_legal_hold;
  END IF;
  RAISE NOTICE '[PASS] TEST 15 (public): trigger tr_00b force legal_hold=false pour category=autre (même si client envoie true)';
END $$;

-- ============================================================================
-- TEST 16 : RPC soft_delete_document sans legal_hold → (storage_path, hard_deleted=true) (public)
-- ============================================================================

DO $$
DECLARE
  v_storage_path text;
  v_hard_deleted boolean;
  v_deleted_at   timestamptz;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0009-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  -- doc 115 = category=autre → legal_hold=false → hard_deleted=true attendu
  SELECT storage_path, hard_deleted
    INTO v_storage_path, v_hard_deleted
    FROM public.soft_delete_document('00000000-0000-0000-0009-000000000115');

  RESET ROLE;

  IF v_hard_deleted IS NOT TRUE THEN
    RAISE EXCEPTION '[FAIL] TEST 16 (public): hard_deleted devrait être true (legal_hold=false), got %', v_hard_deleted;
  END IF;
  IF v_storage_path IS NULL THEN
    RAISE EXCEPTION '[FAIL] TEST 16 (public): storage_path ne devrait pas être NULL si hard_deleted=true';
  END IF;

  -- Vérifier deleted_at posé en superuser
  SELECT deleted_at INTO v_deleted_at
    FROM public.documents WHERE id = '00000000-0000-0000-0009-000000000115';

  IF v_deleted_at IS NULL THEN
    RAISE EXCEPTION '[FAIL] TEST 16 (public): deleted_at devrait être posé après soft_delete_document';
  END IF;

  RAISE NOTICE '[PASS] TEST 16 (public): soft_delete_document sans legal_hold → (storage_path=%, hard_deleted=true, deleted_at posé)', v_storage_path;
END $$;

-- ============================================================================
-- TEST 17 : RPC soft_delete_document avec legal_hold → (NULL, hard_deleted=false) (public)
-- ============================================================================

DO $$
DECLARE
  v_storage_path text;
  v_hard_deleted boolean;
  v_deleted_at   timestamptz;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0009-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  -- doc 114 = category=bail_signe → legal_hold=true → hard_deleted=false attendu
  SELECT storage_path, hard_deleted
    INTO v_storage_path, v_hard_deleted
    FROM public.soft_delete_document('00000000-0000-0000-0009-000000000114');

  RESET ROLE;

  IF v_hard_deleted IS NOT FALSE THEN
    RAISE EXCEPTION '[FAIL] TEST 17 (public): hard_deleted devrait être false (legal_hold=true), got %', v_hard_deleted;
  END IF;
  IF v_storage_path IS NOT NULL THEN
    RAISE EXCEPTION '[FAIL] TEST 17 (public): storage_path devrait être NULL si hard_deleted=false, got %', v_storage_path;
  END IF;

  -- Vérifier deleted_at posé
  SELECT deleted_at INTO v_deleted_at
    FROM public.documents WHERE id = '00000000-0000-0000-0009-000000000114';

  IF v_deleted_at IS NULL THEN
    RAISE EXCEPTION '[FAIL] TEST 17 (public): deleted_at devrait être posé même avec legal_hold=true';
  END IF;

  RAISE NOTICE '[PASS] TEST 17 (public): soft_delete_document avec legal_hold → (NULL, hard_deleted=false, deleted_at posé)';
END $$;

-- ============================================================================
-- TEST 18 : RPC soft_delete_document cross-user → ERRCODE P0002 (public)
-- ============================================================================
-- User A essaie de soft-delete un document appartenant à User B.

DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0009-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    PERFORM public.soft_delete_document('00000000-0000-0000-0009-000000000102');
    -- doc 102 appartient à User B
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 18 (public): soft_delete_document cross-user devrait lever P0002';
  EXCEPTION
    WHEN no_data_found THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 18 (public): soft_delete_document cross-user → P0002 (no_data_found)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 18 (public): Erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 19 : RPC soft_delete_document sur doc déjà supprimé → ERRCODE P0002 (public)
-- ============================================================================
-- doc 115 a été soft-deleted au TEST 16 → 2e appel doit retourner P0002

DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0009-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    PERFORM public.soft_delete_document('00000000-0000-0000-0009-000000000115');
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 19 (public): soft_delete sur doc déjà supprimé devrait lever P0002';
  EXCEPTION
    WHEN no_data_found THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 19 (public): soft_delete doc déjà supprimé → P0002 (idempotent protégé)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 19 (public): Erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 20 : anon — INSERT refusé (42501)
-- ============================================================================

DO $$
BEGIN
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
  SET LOCAL ROLE anon;

  BEGIN
    INSERT INTO public.documents (
      id, landlord_id, lease_id, category,
      filename, storage_path, mime_type, size_bytes
    ) VALUES (
      '00000000-0000-0000-0009-000000000120',
      '00000000-0000-0000-0009-000000000001',
      '00000000-0000-0000-0009-000000000012',
      'autre',
      'anon_test.pdf',
      'prod/00000000-0000-0000-0009-000000000001/00000000-0000-0000-0009-000000000120.pdf',
      'application/pdf',
      1024
    );
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 20: anon ne devrait pas pouvoir INSERT dans documents';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 20: anon INSERT → 42501 insufficient_privilege';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 20: Erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 21 : anon — SELECT → 0 rows (aucune policy pour anon)
-- ============================================================================

DO $$
DECLARE row_count integer;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
  SET LOCAL ROLE anon;

  SELECT COUNT(*) INTO row_count FROM public.documents;

  RESET ROLE;

  IF row_count <> 0 THEN
    RAISE EXCEPTION '[FAIL] TEST 21: anon ne devrait pas voir de documents (got %)', row_count;
  END IF;
  RAISE NOTICE '[PASS] TEST 21: anon SELECT → 0 rows (aucune policy anon sur documents)';
END $$;

-- ============================================================================
-- TEST 22 : anon — RPC soft_delete_document → 42501
-- ============================================================================

DO $$
BEGIN
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
  SET LOCAL ROLE anon;

  BEGIN
    PERFORM public.soft_delete_document('00000000-0000-0000-0009-000000000101');
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 22: anon ne devrait pas pouvoir appeler soft_delete_document';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 22: anon soft_delete_document → 42501 (REVOKE anon + PUBLIC confirmé)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 22: Erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 23 : assert_rls_both_schemas('documents') passe
-- ============================================================================

DO $$
BEGIN
  PERFORM dev.assert_rls_both_schemas('documents');
  RAISE NOTICE '[PASS] TEST 23: RLS activée sur public.documents ET dev.documents (assert_rls_both_schemas)';
EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION '[FAIL] TEST 23: assert_rls_both_schemas échoue (SQLSTATE %, msg: %)',
      SQLSTATE, SQLERRM;
END $$;

-- ============================================================================
-- Teardown : nettoyage des données de test
-- ============================================================================

-- Suppression en superuser (bypass RLS)
DELETE FROM public.documents WHERE id IN (
  '00000000-0000-0000-0009-000000000101',
  '00000000-0000-0000-0009-000000000102',
  '00000000-0000-0000-0009-000000000114',
  '00000000-0000-0000-0009-000000000115'
);

DELETE FROM dev.documents WHERE id IN (
  '00000000-0000-0000-0009-000000000201'
);

-- Suppression des leases, tenants, properties, landlords (ordre FK)
DELETE FROM public.leases WHERE id IN (
  '00000000-0000-0000-0009-000000000012',
  '00000000-0000-0000-0009-000000000022'
);
DELETE FROM dev.leases WHERE id IN (
  '00000000-0000-0000-0009-000000000012',
  '00000000-0000-0000-0009-000000000022'
);

DELETE FROM public.tenants WHERE id IN (
  '00000000-0000-0000-0009-000000000011',
  '00000000-0000-0000-0009-000000000021'
);
DELETE FROM dev.tenants WHERE id IN (
  '00000000-0000-0000-0009-000000000011',
  '00000000-0000-0000-0009-000000000021'
);

DELETE FROM public.properties WHERE id IN (
  '00000000-0000-0000-0009-000000000010',
  '00000000-0000-0000-0009-000000000020'
);
DELETE FROM dev.properties WHERE id IN (
  '00000000-0000-0000-0009-000000000010',
  '00000000-0000-0000-0009-000000000020'
);

DELETE FROM public.landlords WHERE id IN (
  '00000000-0000-0000-0009-000000000001',
  '00000000-0000-0000-0009-000000000002'
);
DELETE FROM dev.landlords WHERE id IN (
  '00000000-0000-0000-0009-000000000001',
  '00000000-0000-0000-0009-000000000002'
);

DELETE FROM auth.users WHERE id IN (
  '00000000-0000-0000-0009-000000000001',
  '00000000-0000-0000-0009-000000000002'
);

ROLLBACK;
