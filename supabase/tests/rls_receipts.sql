-- ============================================================================
-- Tests RLS — table receipts (FEAT-007)
-- ============================================================================
-- Tests couverts :
--   1.  User A voit ses propres receipts (public)
--   2.  User A voit ses propres receipts (dev)
--   3.  User A ne voit PAS les receipts de User B (public)
--   4.  User A ne voit PAS les receipts de User B (dev)
--   5.  INSERT avec landlord_id = auth.uid() réussit (public)
--   6.  INSERT avec landlord_id = auth.uid() réussit (dev)
--   7.  INSERT avec landlord_id d'un autre user échoue (42501 — public)
--   8.  INSERT avec landlord_id d'un autre user échoue (42501 — dev)
--   9.  Trigger tr_00 : lease_id d'un autre user → ERRCODE 23514 (public)
--   10. Trigger tr_00 : lease_id d'un autre user → ERRCODE 23514 (dev)
--   11. Trigger tr_00 : lease_id inexistant → ERRCODE 23514 (public)
--   12. Trigger tr_00 : lease_id inexistant → ERRCODE 23514 (dev)
--   13. CHECK total_cents = rent_cents + charges_cents refusé (public)
--   14. CHECK document_type invalide refusé (public)
--   15. CHECK array_length(payment_ids,1) >= 1 refusé (public)
--   16. CHECK period_end <= period_start refusé (public)
--   17. CHECK voiding_consistency is_voided=true sans voided_at refusé (public)
--   18. CHECK voiding_consistency is_voided=false avec voided_at refusé (public)
--   19. UPDATE direct bloqué — pas de policy UPDATE (public)
--   20. UPDATE direct bloqué — pas de policy UPDATE (dev)
--   21. DELETE direct bloqué — pas de policy DELETE (public)
--   22. DELETE direct bloqué — pas de policy DELETE (dev)
--   23. RPC void_receipt réussit pour propriétaire (public)
--   24. RPC void_receipt réussit pour propriétaire (dev)
--   25. RPC void_receipt cross-user → NOT FOUND (public)
--   26. RPC void_receipt cross-user → NOT FOUND (dev)
--   27. RPC void_receipt déjà voided → NOT FOUND (public)
--   28. RPC void_receipt motif trop court → erreur 22023 (public)
--   29. Trigger tr_03 : soft-delete payment → is_stale = true (public)
--   30. Trigger tr_03 : soft-delete payment → is_stale = true (dev)
--   31. RLS activée sur les deux schémas (assert_rls_both_schemas)
-- ============================================================================
-- USAGE: psql <connection_string> -f supabase/tests/rls_receipts.sql
-- ============================================================================

BEGIN;

-- ============================================================================
-- Setup : deux users + landlords + properties + tenants + leases + payments + receipts
-- ============================================================================
-- UUIDs préfixe 0007 (FEAT-007) pour ne pas collisionner avec FEAT-006 (0006)

INSERT INTO auth.users (
  id, instance_id, email, encrypted_password, email_confirmed_at,
  created_at, updated_at, raw_app_meta_data, raw_user_meta_data, aud, role
) VALUES
  ('00000000-0000-0000-0007-000000000001', '00000000-0000-0000-0000-000000000000',
   'receipt_user_a@test.example', 'hashed', now(), now(), now(),
   '{"provider":"email","providers":["email"]}', '{}', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0007-000000000002', '00000000-0000-0000-0000-000000000000',
   'receipt_user_b@test.example', 'hashed', now(), now(), now(),
   '{"provider":"email","providers":["email"]}', '{}', 'authenticated', 'authenticated')
ON CONFLICT (id) DO NOTHING;

-- Landlords (full_name + address requis pour génération Edge Function, pas pour RLS SQL)
INSERT INTO public.landlords (id, email, full_name, address) VALUES
  ('00000000-0000-0000-0007-000000000001', 'receipt_user_a@test.example',
   'User A Receipts', '1 rue des Tests, Paris'),
  ('00000000-0000-0000-0007-000000000002', 'receipt_user_b@test.example',
   'User B Receipts', '2 avenue des Tests, Lyon')
ON CONFLICT (id) DO NOTHING;

INSERT INTO dev.landlords (id, email, full_name, address) VALUES
  ('00000000-0000-0000-0007-000000000001', 'receipt_user_a@test.example',
   'User A Receipts', '1 rue des Tests, Paris'),
  ('00000000-0000-0000-0007-000000000002', 'receipt_user_b@test.example',
   'User B Receipts', '2 avenue des Tests, Lyon')
ON CONFLICT (id) DO NOTHING;

-- Properties : une par user
INSERT INTO public.properties (id, landlord_id, name, address, type) VALUES
  ('00000000-0000-0000-0007-000000000010', '00000000-0000-0000-0007-000000000001',
   'Prop A (receipts)', '10 rue A', 'appartement'),
  ('00000000-0000-0000-0007-000000000020', '00000000-0000-0000-0007-000000000002',
   'Prop B (receipts)', '20 rue B', 'maison');

INSERT INTO dev.properties (id, landlord_id, name, address, type) VALUES
  ('00000000-0000-0000-0007-000000000010', '00000000-0000-0000-0007-000000000001',
   'Prop A (receipts)', '10 rue A', 'appartement'),
  ('00000000-0000-0000-0007-000000000020', '00000000-0000-0000-0007-000000000002',
   'Prop B (receipts)', '20 rue B', 'maison');

-- Tenants : un par user
INSERT INTO public.tenants (id, landlord_id, first_name, last_name, email) VALUES
  ('00000000-0000-0000-0007-000000000030', '00000000-0000-0000-0007-000000000001',
   'Tenant', 'A-Receipt', 'tenant_a_rec@test.example'),
  ('00000000-0000-0000-0007-000000000040', '00000000-0000-0000-0007-000000000002',
   'Tenant', 'B-Receipt', 'tenant_b_rec@test.example');

INSERT INTO dev.tenants (id, landlord_id, first_name, last_name, email) VALUES
  ('00000000-0000-0000-0007-000000000030', '00000000-0000-0000-0007-000000000001',
   'Tenant', 'A-Receipt', 'tenant_a_rec@test.example'),
  ('00000000-0000-0000-0007-000000000040', '00000000-0000-0000-0007-000000000002',
   'Tenant', 'B-Receipt', 'tenant_b_rec@test.example');

-- Leases : un par user (rent=85000, charges=5000 → total_dû=90000)
INSERT INTO public.leases (
  id, landlord_id, property_id, tenant_id, rent_amount_cents, charges_amount_cents, start_date
) VALUES
  ('00000000-0000-0000-0007-000000000050', '00000000-0000-0000-0007-000000000001',
   '00000000-0000-0000-0007-000000000010', '00000000-0000-0000-0007-000000000030',
   85000, 5000, '2026-01-01'),
  ('00000000-0000-0000-0007-000000000060', '00000000-0000-0000-0007-000000000002',
   '00000000-0000-0000-0007-000000000020', '00000000-0000-0000-0007-000000000040',
   120000, 10000, '2026-02-01');

INSERT INTO dev.leases (
  id, landlord_id, property_id, tenant_id, rent_amount_cents, charges_amount_cents, start_date
) VALUES
  ('00000000-0000-0000-0007-000000000050', '00000000-0000-0000-0007-000000000001',
   '00000000-0000-0000-0007-000000000010', '00000000-0000-0000-0007-000000000030',
   85000, 5000, '2026-01-01'),
  ('00000000-0000-0000-0007-000000000060', '00000000-0000-0000-0007-000000000002',
   '00000000-0000-0000-0007-000000000020', '00000000-0000-0000-0007-000000000040',
   120000, 10000, '2026-02-01');

-- Payments : un par user (insérés en superuser, sans RLS)
INSERT INTO public.payments (
  id, lease_id, landlord_id, period_start, period_end, paid_at,
  rent_amount_cents, charges_amount_cents, payment_method
) VALUES
  ('00000000-0000-0000-0007-000000000070', '00000000-0000-0000-0007-000000000050',
   '00000000-0000-0000-0007-000000000001',
   '2026-01-01', '2026-01-31', '2026-01-05', 85000, 5000, 'virement'),
  ('00000000-0000-0000-0007-000000000080', '00000000-0000-0000-0007-000000000060',
   '00000000-0000-0000-0007-000000000002',
   '2026-02-01', '2026-02-28', '2026-02-05', 120000, 10000, 'prelevement');

INSERT INTO dev.payments (
  id, lease_id, landlord_id, period_start, period_end, paid_at,
  rent_amount_cents, charges_amount_cents, payment_method
) VALUES
  ('00000000-0000-0000-0007-000000000070', '00000000-0000-0000-0007-000000000050',
   '00000000-0000-0000-0007-000000000001',
   '2026-01-01', '2026-01-31', '2026-01-05', 85000, 5000, 'virement'),
  ('00000000-0000-0000-0007-000000000080', '00000000-0000-0000-0007-000000000060',
   '00000000-0000-0000-0007-000000000002',
   '2026-02-01', '2026-02-28', '2026-02-05', 120000, 10000, 'prelevement');

-- Receipts initiaux (insérés en superuser, sans RLS)
-- User A : quittance janvier 2026 (total=90000 = rent 85000 + charges 5000)
INSERT INTO public.receipts (
  id, landlord_id, lease_id, payment_ids,
  period_start, period_end,
  rent_cents, charges_cents, total_cents,
  document_type, pdf_path
) VALUES
  ('00000000-0000-0000-0007-000000000090',
   '00000000-0000-0000-0007-000000000001',
   '00000000-0000-0000-0007-000000000050',
   ARRAY['00000000-0000-0000-0007-000000000070']::uuid[],
   '2026-01-01', '2026-01-31',
   85000, 5000, 90000,
   'quittance',
   '00000000-0000-0000-0007-000000000001/00000000-0000-0000-0007-000000000090.pdf'),
  -- User B : quittance février 2026
  ('00000000-0000-0000-0007-000000000100',
   '00000000-0000-0000-0007-000000000002',
   '00000000-0000-0000-0007-000000000060',
   ARRAY['00000000-0000-0000-0007-000000000080']::uuid[],
   '2026-02-01', '2026-02-28',
   120000, 10000, 130000,
   'quittance',
   '00000000-0000-0000-0007-000000000002/00000000-0000-0000-0007-000000000100.pdf');

INSERT INTO dev.receipts (
  id, landlord_id, lease_id, payment_ids,
  period_start, period_end,
  rent_cents, charges_cents, total_cents,
  document_type, pdf_path
) VALUES
  ('00000000-0000-0000-0007-000000000090',
   '00000000-0000-0000-0007-000000000001',
   '00000000-0000-0000-0007-000000000050',
   ARRAY['00000000-0000-0000-0007-000000000070']::uuid[],
   '2026-01-01', '2026-01-31',
   85000, 5000, 90000,
   'quittance',
   '00000000-0000-0000-0007-000000000001/00000000-0000-0000-0007-000000000090.pdf'),
  ('00000000-0000-0000-0007-000000000100',
   '00000000-0000-0000-0007-000000000002',
   '00000000-0000-0000-0007-000000000060',
   ARRAY['00000000-0000-0000-0007-000000000080']::uuid[],
   '2026-02-01', '2026-02-28',
   120000, 10000, 130000,
   'quittance',
   '00000000-0000-0000-0007-000000000002/00000000-0000-0000-0007-000000000100.pdf');

-- ============================================================================
-- TEST 1 : User A voit ses propres receipts (public)
-- ============================================================================
DO $$
DECLARE row_count integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0007-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  SELECT COUNT(*) INTO row_count FROM public.receipts
    WHERE landlord_id = '00000000-0000-0000-0007-000000000001';

  RESET ROLE;
  IF row_count <> 1 THEN
    RAISE EXCEPTION '[FAIL] TEST 1 public: User A devrait voir 1 receipt (got %)', row_count;
  END IF;
  RAISE NOTICE '[PASS] TEST 1 public: User A voit ses propres receipts';
END $$;

-- ============================================================================
-- TEST 2 : User A voit ses propres receipts (dev)
-- ============================================================================
DO $$
DECLARE row_count integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0007-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  SELECT COUNT(*) INTO row_count FROM dev.receipts
    WHERE landlord_id = '00000000-0000-0000-0007-000000000001';

  RESET ROLE;
  IF row_count <> 1 THEN
    RAISE EXCEPTION '[FAIL] TEST 2 dev: User A devrait voir 1 receipt (got %)', row_count;
  END IF;
  RAISE NOTICE '[PASS] TEST 2 dev: User A voit ses propres receipts';
END $$;

-- ============================================================================
-- TEST 3 : User A ne voit PAS les receipts de User B (public)
-- ============================================================================
DO $$
DECLARE row_count integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0007-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  SELECT COUNT(*) INTO row_count FROM public.receipts
    WHERE landlord_id = '00000000-0000-0000-0007-000000000002';

  RESET ROLE;
  IF row_count <> 0 THEN
    RAISE EXCEPTION '[FAIL] TEST 3 public: User A ne devrait pas voir les receipts de User B (got %)', row_count;
  END IF;
  RAISE NOTICE '[PASS] TEST 3 public: User A ne voit pas les receipts de User B';
END $$;

-- ============================================================================
-- TEST 4 : User A ne voit PAS les receipts de User B (dev)
-- ============================================================================
DO $$
DECLARE row_count integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0007-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  SELECT COUNT(*) INTO row_count FROM dev.receipts
    WHERE landlord_id = '00000000-0000-0000-0007-000000000002';

  RESET ROLE;
  IF row_count <> 0 THEN
    RAISE EXCEPTION '[FAIL] TEST 4 dev: User A ne devrait pas voir les receipts de User B (got %)', row_count;
  END IF;
  RAISE NOTICE '[PASS] TEST 4 dev: User A ne voit pas les receipts de User B';
END $$;

-- ============================================================================
-- TEST 5 : INSERT avec landlord_id = auth.uid() réussit (public)
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0007-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    INSERT INTO public.receipts (
      id, landlord_id, lease_id, payment_ids,
      period_start, period_end,
      rent_cents, charges_cents, total_cents,
      document_type, pdf_path
    ) VALUES (
      '00000000-0000-0000-0007-000000000901',
      '00000000-0000-0000-0007-000000000001',
      '00000000-0000-0000-0007-000000000050',
      ARRAY['00000000-0000-0000-0007-000000000070']::uuid[],
      '2026-03-01', '2026-03-31',
      85000, 5000, 90000,
      'quittance',
      '00000000-0000-0000-0007-000000000001/00000000-0000-0000-0007-000000000901.pdf'
    );
    RESET ROLE;
    RAISE NOTICE '[PASS] TEST 5 public: INSERT valide avec son propre landlord_id réussit';
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 5 public: INSERT devrait réussir (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 6 : INSERT avec landlord_id = auth.uid() réussit (dev)
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0007-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    INSERT INTO dev.receipts (
      id, landlord_id, lease_id, payment_ids,
      period_start, period_end,
      rent_cents, charges_cents, total_cents,
      document_type, pdf_path
    ) VALUES (
      '00000000-0000-0000-0007-000000000902',
      '00000000-0000-0000-0007-000000000001',
      '00000000-0000-0000-0007-000000000050',
      ARRAY['00000000-0000-0000-0007-000000000070']::uuid[],
      '2026-03-01', '2026-03-31',
      85000, 5000, 90000,
      'quittance',
      '00000000-0000-0000-0007-000000000001/00000000-0000-0000-0007-000000000902.pdf'
    );
    RESET ROLE;
    RAISE NOTICE '[PASS] TEST 6 dev: INSERT valide avec son propre landlord_id réussit';
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 6 dev: INSERT devrait réussir (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 7 : INSERT avec landlord_id d'un autre user échoue (42501 — public)
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0007-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    INSERT INTO public.receipts (
      id, landlord_id, lease_id, payment_ids,
      period_start, period_end,
      rent_cents, charges_cents, total_cents,
      document_type, pdf_path
    ) VALUES (
      '00000000-0000-0000-0007-000000000903',
      '00000000-0000-0000-0007-000000000002',   -- landlord_id de User B
      '00000000-0000-0000-0007-000000000060',   -- lease de User B
      ARRAY['00000000-0000-0000-0007-000000000080']::uuid[],
      '2026-02-01', '2026-02-28',
      120000, 10000, 130000,
      'quittance',
      '00000000-0000-0000-0007-000000000002/00000000-0000-0000-0007-000000000903.pdf'
    );
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 7 public: INSERT avec landlord_id étranger aurait dû être bloqué';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 7 public: INSERT avec landlord_id étranger refusé par RLS (42501)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 7 public: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 8 : INSERT avec landlord_id d'un autre user échoue (42501 — dev)
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0007-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    INSERT INTO dev.receipts (
      id, landlord_id, lease_id, payment_ids,
      period_start, period_end,
      rent_cents, charges_cents, total_cents,
      document_type, pdf_path
    ) VALUES (
      '00000000-0000-0000-0007-000000000904',
      '00000000-0000-0000-0007-000000000002',
      '00000000-0000-0000-0007-000000000060',
      ARRAY['00000000-0000-0000-0007-000000000080']::uuid[],
      '2026-02-01', '2026-02-28',
      120000, 10000, 130000,
      'quittance',
      '00000000-0000-0000-0007-000000000002/00000000-0000-0000-0007-000000000904.pdf'
    );
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 8 dev: INSERT avec landlord_id étranger aurait dû être bloqué';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 8 dev: INSERT avec landlord_id étranger refusé par RLS (42501)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 8 dev: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 9 : Trigger tr_00 — lease_id d'un autre user, landlord_id=self → 23514 (public)
-- Scénario (superuser) : landlord_id=User A mais lease_id appartenant à User B.
-- ============================================================================
DO $$
BEGIN
  BEGIN
    INSERT INTO public.receipts (
      landlord_id, lease_id, payment_ids,
      period_start, period_end,
      rent_cents, charges_cents, total_cents,
      document_type, pdf_path
    ) VALUES (
      '00000000-0000-0000-0007-000000000001',   -- landlord_id User A
      '00000000-0000-0000-0007-000000000060',   -- lease de User B (mismatch)
      ARRAY['00000000-0000-0000-0007-000000000070']::uuid[],
      '2026-04-01', '2026-04-30',
      85000, 5000, 90000,
      'quittance',
      '00000000-0000-0000-0007-000000000001/test-tr00.pdf'
    );
    RAISE EXCEPTION '[FAIL] TEST 9 public: Le trigger tr_00 aurait dû rejeter le cross-ownership lease';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE '[PASS] TEST 9 public: lease_id d''un autre user refusé par trigger tr_00 (23514)';
    WHEN OTHERS THEN
      RAISE EXCEPTION '[FAIL] TEST 9 public: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 10 : Trigger tr_00 — lease_id d'un autre user → 23514 (dev)
-- ============================================================================
DO $$
BEGIN
  BEGIN
    INSERT INTO dev.receipts (
      landlord_id, lease_id, payment_ids,
      period_start, period_end,
      rent_cents, charges_cents, total_cents,
      document_type, pdf_path
    ) VALUES (
      '00000000-0000-0000-0007-000000000001',
      '00000000-0000-0000-0007-000000000060',
      ARRAY['00000000-0000-0000-0007-000000000070']::uuid[],
      '2026-04-01', '2026-04-30',
      85000, 5000, 90000,
      'quittance',
      '00000000-0000-0000-0007-000000000001/test-tr00-dev.pdf'
    );
    RAISE EXCEPTION '[FAIL] TEST 10 dev: Le trigger tr_00 aurait dû rejeter le cross-ownership lease';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE '[PASS] TEST 10 dev: lease_id d''un autre user refusé par trigger tr_00 (23514)';
    WHEN OTHERS THEN
      RAISE EXCEPTION '[FAIL] TEST 10 dev: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 11 : Trigger tr_00 — lease_id inexistant → 23514 (public)
-- ============================================================================
DO $$
BEGIN
  BEGIN
    INSERT INTO public.receipts (
      landlord_id, lease_id, payment_ids,
      period_start, period_end,
      rent_cents, charges_cents, total_cents,
      document_type, pdf_path
    ) VALUES (
      '00000000-0000-0000-0007-000000000001',
      'ffffffff-ffff-ffff-ffff-ffffffffffff',   -- lease_id inexistant
      ARRAY['00000000-0000-0000-0007-000000000070']::uuid[],
      '2026-05-01', '2026-05-31',
      85000, 5000, 90000,
      'quittance',
      '00000000-0000-0000-0007-000000000001/test-notfound.pdf'
    );
    RAISE EXCEPTION '[FAIL] TEST 11 public: Le trigger tr_00 aurait dû rejeter le lease_id inexistant';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE '[PASS] TEST 11 public: lease_id inexistant refusé par trigger tr_00 (23514)';
    WHEN OTHERS THEN
      RAISE EXCEPTION '[FAIL] TEST 11 public: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 12 : Trigger tr_00 — lease_id inexistant → 23514 (dev)
-- ============================================================================
DO $$
BEGIN
  BEGIN
    INSERT INTO dev.receipts (
      landlord_id, lease_id, payment_ids,
      period_start, period_end,
      rent_cents, charges_cents, total_cents,
      document_type, pdf_path
    ) VALUES (
      '00000000-0000-0000-0007-000000000001',
      'ffffffff-ffff-ffff-ffff-ffffffffffff',
      ARRAY['00000000-0000-0000-0007-000000000070']::uuid[],
      '2026-05-01', '2026-05-31',
      85000, 5000, 90000,
      'quittance',
      '00000000-0000-0000-0007-000000000001/test-notfound-dev.pdf'
    );
    RAISE EXCEPTION '[FAIL] TEST 12 dev: Le trigger tr_00 aurait dû rejeter le lease_id inexistant';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE '[PASS] TEST 12 dev: lease_id inexistant refusé par trigger tr_00 (23514)';
    WHEN OTHERS THEN
      RAISE EXCEPTION '[FAIL] TEST 12 dev: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 13 : CHECK total_cents = rent_cents + charges_cents refusé (public)
-- Scénario : total_cents ≠ rent_cents + charges_cents → constraint violation.
-- ============================================================================
DO $$
BEGIN
  BEGIN
    INSERT INTO public.receipts (
      landlord_id, lease_id, payment_ids,
      period_start, period_end,
      rent_cents, charges_cents, total_cents,
      document_type, pdf_path
    ) VALUES (
      '00000000-0000-0000-0007-000000000001',
      '00000000-0000-0000-0007-000000000050',
      ARRAY['00000000-0000-0000-0007-000000000070']::uuid[],
      '2026-06-01', '2026-06-30',
      85000, 5000,
      99999,  -- incohérent : 85000+5000=90000, pas 99999
      'quittance',
      '00000000-0000-0000-0007-000000000001/test-total.pdf'
    );
    RAISE EXCEPTION '[FAIL] TEST 13 public: Le CHECK total_cents aurait dû rejeter la valeur incohérente';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE '[PASS] TEST 13 public: total_cents incohérent refusé par CHECK (23514)';
    WHEN OTHERS THEN
      RAISE EXCEPTION '[FAIL] TEST 13 public: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 14 : CHECK document_type invalide refusé (public)
-- Scénario : valeur hors enum → invalid_text_representation ou check_violation.
-- ============================================================================
DO $$
BEGIN
  BEGIN
    INSERT INTO public.receipts (
      landlord_id, lease_id, payment_ids,
      period_start, period_end,
      rent_cents, charges_cents, total_cents,
      document_type, pdf_path
    ) VALUES (
      '00000000-0000-0000-0007-000000000001',
      '00000000-0000-0000-0007-000000000050',
      ARRAY['00000000-0000-0000-0007-000000000070']::uuid[],
      '2026-07-01', '2026-07-31',
      85000, 5000, 90000,
      'facture'::public.document_type,   -- valeur hors enum
      '00000000-0000-0000-0007-000000000001/test-dtype.pdf'
    );
    RAISE EXCEPTION '[FAIL] TEST 14 public: document_type invalide aurait dû être refusé';
  EXCEPTION
    WHEN invalid_text_representation THEN
      RAISE NOTICE '[PASS] TEST 14 public: document_type invalide refusé (invalid_text_representation)';
    WHEN check_violation THEN
      RAISE NOTICE '[PASS] TEST 14 public: document_type invalide refusé (check_violation)';
    WHEN OTHERS THEN
      -- Les versions de PG peuvent varier sur l'erreur exacte pour un cast d'enum invalide
      IF SQLSTATE IN ('22P02', '23514') THEN
        RAISE NOTICE '[PASS] TEST 14 public: document_type invalide refusé (SQLSTATE %)', SQLSTATE;
      ELSE
        RAISE EXCEPTION '[FAIL] TEST 14 public: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
      END IF;
  END;
END $$;

-- ============================================================================
-- TEST 15 : CHECK array_length(payment_ids,1) >= 1 refusé (public)
-- Scénario : tableau vide → check_violation.
-- ============================================================================
DO $$
BEGIN
  BEGIN
    INSERT INTO public.receipts (
      landlord_id, lease_id, payment_ids,
      period_start, period_end,
      rent_cents, charges_cents, total_cents,
      document_type, pdf_path
    ) VALUES (
      '00000000-0000-0000-0007-000000000001',
      '00000000-0000-0000-0007-000000000050',
      ARRAY[]::uuid[],   -- tableau vide : invalide
      '2026-08-01', '2026-08-31',
      85000, 5000, 90000,
      'quittance',
      '00000000-0000-0000-0007-000000000001/test-empty-arr.pdf'
    );
    RAISE EXCEPTION '[FAIL] TEST 15 public: payment_ids vide aurait dû être refusé';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE '[PASS] TEST 15 public: payment_ids vide refusé par CHECK (23514)';
    WHEN OTHERS THEN
      RAISE EXCEPTION '[FAIL] TEST 15 public: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 16 : CHECK period_end <= period_start refusé (public)
-- ============================================================================
DO $$
BEGIN
  BEGIN
    INSERT INTO public.receipts (
      landlord_id, lease_id, payment_ids,
      period_start, period_end,
      rent_cents, charges_cents, total_cents,
      document_type, pdf_path
    ) VALUES (
      '00000000-0000-0000-0007-000000000001',
      '00000000-0000-0000-0007-000000000050',
      ARRAY['00000000-0000-0000-0007-000000000070']::uuid[],
      '2026-09-30', '2026-09-01',   -- period_end < period_start : invalide
      85000, 5000, 90000,
      'quittance',
      '00000000-0000-0000-0007-000000000001/test-period.pdf'
    );
    RAISE EXCEPTION '[FAIL] TEST 16 public: period_end < period_start aurait dû être refusé';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE '[PASS] TEST 16 public: period_end < period_start refusé par CHECK (23514)';
    WHEN OTHERS THEN
      RAISE EXCEPTION '[FAIL] TEST 16 public: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 17 : CHECK voiding_consistency — is_voided=true sans voided_at refusé (public)
-- ============================================================================
DO $$
BEGIN
  BEGIN
    INSERT INTO public.receipts (
      landlord_id, lease_id, payment_ids,
      period_start, period_end,
      rent_cents, charges_cents, total_cents,
      document_type, pdf_path,
      is_voided, voided_at, voided_reason
    ) VALUES (
      '00000000-0000-0000-0007-000000000001',
      '00000000-0000-0000-0007-000000000050',
      ARRAY['00000000-0000-0000-0007-000000000070']::uuid[],
      '2026-10-01', '2026-10-31',
      85000, 5000, 90000,
      'quittance',
      '00000000-0000-0000-0007-000000000001/test-void1.pdf',
      true,      -- is_voided=true
      NULL,      -- voided_at NULL : incohérent
      NULL       -- voided_reason NULL : incohérent
    );
    RAISE EXCEPTION '[FAIL] TEST 17 public: is_voided=true sans voided_at aurait dû être refusé';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE '[PASS] TEST 17 public: voiding_consistency refusé (is_voided=true sans voided_at)';
    WHEN OTHERS THEN
      RAISE EXCEPTION '[FAIL] TEST 17 public: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 18 : CHECK voiding_consistency — is_voided=false avec voided_at refusé (public)
-- ============================================================================
DO $$
BEGIN
  BEGIN
    INSERT INTO public.receipts (
      landlord_id, lease_id, payment_ids,
      period_start, period_end,
      rent_cents, charges_cents, total_cents,
      document_type, pdf_path,
      is_voided, voided_at, voided_reason
    ) VALUES (
      '00000000-0000-0000-0007-000000000001',
      '00000000-0000-0000-0007-000000000050',
      ARRAY['00000000-0000-0000-0007-000000000070']::uuid[],
      '2026-11-01', '2026-11-30',
      85000, 5000, 90000,
      'quittance',
      '00000000-0000-0000-0007-000000000001/test-void2.pdf',
      false,     -- is_voided=false
      now(),     -- voided_at non-NULL : incohérent
      'raison'   -- voided_reason non-NULL : incohérent
    );
    RAISE EXCEPTION '[FAIL] TEST 18 public: is_voided=false avec voided_at aurait dû être refusé';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE '[PASS] TEST 18 public: voiding_consistency refusé (is_voided=false avec voided_at)';
    WHEN OTHERS THEN
      RAISE EXCEPTION '[FAIL] TEST 18 public: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 19 : UPDATE direct bloqué — pas de policy UPDATE (public)
-- Scénario : User A tente de modifier un champ d'une de ses receipts.
-- Attendu : 0 lignes mises à jour (pas de policy → UPDATE silencieusement rejeté).
-- ============================================================================
DO $$
DECLARE rows_updated integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0007-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  UPDATE public.receipts
    SET pdf_path = 'malicious/path.pdf'
    WHERE id = '00000000-0000-0000-0007-000000000090';
  GET DIAGNOSTICS rows_updated = ROW_COUNT;

  RESET ROLE;
  IF rows_updated <> 0 THEN
    RAISE EXCEPTION '[FAIL] TEST 19 public: UPDATE direct aurait dû être bloqué (updated %)', rows_updated;
  END IF;
  RAISE NOTICE '[PASS] TEST 19 public: UPDATE direct bloqué (pas de policy UPDATE — 0 lignes)';
END $$;

-- ============================================================================
-- TEST 20 : UPDATE direct bloqué — pas de policy UPDATE (dev)
-- ============================================================================
DO $$
DECLARE rows_updated integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0007-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  UPDATE dev.receipts
    SET pdf_path = 'malicious/path.pdf'
    WHERE id = '00000000-0000-0000-0007-000000000090';
  GET DIAGNOSTICS rows_updated = ROW_COUNT;

  RESET ROLE;
  IF rows_updated <> 0 THEN
    RAISE EXCEPTION '[FAIL] TEST 20 dev: UPDATE direct aurait dû être bloqué (updated %)', rows_updated;
  END IF;
  RAISE NOTICE '[PASS] TEST 20 dev: UPDATE direct bloqué (pas de policy UPDATE — 0 lignes)';
END $$;

-- ============================================================================
-- TEST 21 : DELETE direct bloqué — pas de policy DELETE (public)
-- Scénario : User A tente de supprimer sa propre receipt.
-- Attendu : 0 lignes supprimées (RLS bloque sans policy DELETE).
-- ============================================================================
DO $$
DECLARE rows_deleted integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0007-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  DELETE FROM public.receipts
    WHERE id = '00000000-0000-0000-0007-000000000090';
  GET DIAGNOSTICS rows_deleted = ROW_COUNT;

  RESET ROLE;
  IF rows_deleted <> 0 THEN
    RAISE EXCEPTION '[FAIL] TEST 21 public: DELETE devrait être bloqué par absence de policy (deleted %)', rows_deleted;
  END IF;
  RAISE NOTICE '[PASS] TEST 21 public: DELETE bloqué (pas de policy DELETE — 0 lignes)';
END $$;

-- ============================================================================
-- TEST 22 : DELETE direct bloqué — pas de policy DELETE (dev)
-- ============================================================================
DO $$
DECLARE rows_deleted integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0007-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  DELETE FROM dev.receipts
    WHERE id = '00000000-0000-0000-0007-000000000090';
  GET DIAGNOSTICS rows_deleted = ROW_COUNT;

  RESET ROLE;
  IF rows_deleted <> 0 THEN
    RAISE EXCEPTION '[FAIL] TEST 22 dev: DELETE devrait être bloqué par absence de policy (deleted %)', rows_deleted;
  END IF;
  RAISE NOTICE '[PASS] TEST 22 dev: DELETE bloqué (pas de policy DELETE — 0 lignes)';
END $$;

-- ============================================================================
-- TEST 23 : RPC void_receipt réussit pour propriétaire (public)
-- ============================================================================
DO $$
DECLARE voided_flag boolean;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0007-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    PERFORM public.void_receipt(
      '00000000-0000-0000-0007-000000000090',
      'Erreur de saisie — paiement annulé et recréé'
    );
    RESET ROLE;

    SELECT is_voided INTO voided_flag
      FROM public.receipts WHERE id = '00000000-0000-0000-0007-000000000090';

    IF voided_flag IS NOT TRUE THEN
      RAISE EXCEPTION '[FAIL] TEST 23 public: is_voided devrait être true après void_receipt';
    END IF;
    RAISE NOTICE '[PASS] TEST 23 public: void_receipt réussit pour propriétaire';
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 23 public: void_receipt devrait réussir (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 24 : RPC void_receipt réussit pour propriétaire (dev)
-- ============================================================================
DO $$
DECLARE voided_flag boolean;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0007-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    PERFORM dev.void_receipt(
      '00000000-0000-0000-0007-000000000090',
      'Erreur de saisie — paiement annulé et recréé'
    );
    RESET ROLE;

    SELECT is_voided INTO voided_flag
      FROM dev.receipts WHERE id = '00000000-0000-0000-0007-000000000090';

    IF voided_flag IS NOT TRUE THEN
      RAISE EXCEPTION '[FAIL] TEST 24 dev: is_voided devrait être true après void_receipt';
    END IF;
    RAISE NOTICE '[PASS] TEST 24 dev: void_receipt réussit pour propriétaire';
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 24 dev: void_receipt devrait réussir (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 25 : RPC void_receipt cross-user → NOT FOUND (public)
-- Scénario : User A tente d'annuler la receipt de User B.
-- Attendu : ERRCODE P0002 — pas de fuite sur l'existence.
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0007-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    PERFORM public.void_receipt(
      '00000000-0000-0000-0007-000000000100',  -- receipt de User B
      'tentative cross-user'
    );
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 25 public: void_receipt cross-user aurait dû lever NOT FOUND';
  EXCEPTION
    WHEN no_data_found THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 25 public: void_receipt cross-user → NOT FOUND (P0002)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 25 public: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;

  -- Vérifier que la receipt de User B n'a pas été modifiée
  IF (SELECT is_voided FROM public.receipts
        WHERE id = '00000000-0000-0000-0007-000000000100') IS TRUE THEN
    RAISE EXCEPTION '[FAIL] TEST 25 public: La receipt de User B ne devrait pas avoir été voided';
  END IF;
END $$;

-- ============================================================================
-- TEST 26 : RPC void_receipt cross-user → NOT FOUND (dev)
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0007-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    PERFORM dev.void_receipt(
      '00000000-0000-0000-0007-000000000100',
      'tentative cross-user dev'
    );
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 26 dev: void_receipt cross-user aurait dû lever NOT FOUND';
  EXCEPTION
    WHEN no_data_found THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 26 dev: void_receipt cross-user → NOT FOUND (P0002)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 26 dev: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;

  IF (SELECT is_voided FROM dev.receipts
        WHERE id = '00000000-0000-0000-0007-000000000100') IS TRUE THEN
    RAISE EXCEPTION '[FAIL] TEST 26 dev: La receipt de User B ne devrait pas avoir été voided';
  END IF;
END $$;

-- ============================================================================
-- TEST 27 : RPC void_receipt déjà voided → NOT FOUND (public)
-- Pré-condition : TEST 23 a voided la receipt 090.
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0007-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    PERFORM public.void_receipt(
      '00000000-0000-0000-0007-000000000090',  -- déjà voided par TEST 23
      'deuxième tentative de void'
    );
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 27 public: void_receipt sur receipt déjà voided aurait dû lever NOT FOUND';
  EXCEPTION
    WHEN no_data_found THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 27 public: void_receipt déjà voided → NOT FOUND (P0002)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 27 public: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 28 : RPC void_receipt motif trop court (< 3 chars) → erreur 22023 (public)
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0007-000000000002","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    PERFORM public.void_receipt(
      '00000000-0000-0000-0007-000000000100',  -- receipt de User B (appelant = User B)
      'ab'  -- 2 chars : trop court (minimum 3)
    );
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 28 public: motif trop court aurait dû être refusé';
  EXCEPTION
    WHEN invalid_parameter_value THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 28 public: motif < 3 chars refusé (22023 invalid_parameter_value)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 28 public: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 29 : Trigger tr_03 — soft-delete payment → is_stale = true (public)
-- Scénario : soft-delete du payment_id inclu dans la receipt 901 (TEST 5).
-- Note : receipt 090 est voided (TEST 23) mais is_stale est aussi updatable.
--        On utilise la receipt 901 créée en TEST 5 qui est encore active.
-- ============================================================================
DO $$
DECLARE stale_flag boolean;
BEGIN
  -- Soft-delete du payment lié à la receipt 901 (payment 070)
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0007-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  PERFORM public.soft_delete_payment('00000000-0000-0000-0007-000000000070');

  RESET ROLE;

  -- Vérifier que is_stale = true sur les receipts incluant ce payment_id
  SELECT is_stale INTO stale_flag
    FROM public.receipts
    WHERE payment_ids @> ARRAY['00000000-0000-0000-0007-000000000070']::uuid[]
      AND id = '00000000-0000-0000-0007-000000000901';

  IF stale_flag IS NOT TRUE THEN
    RAISE EXCEPTION '[FAIL] TEST 29 public: is_stale devrait être true après soft-delete du payment lié (got %)', stale_flag;
  END IF;
  RAISE NOTICE '[PASS] TEST 29 public: trigger tr_03 → is_stale = true après soft-delete payment';

  -- Restaurer le payment pour les tests suivants
  PERFORM set_config('app.allow_deleted_at_change', '1', true);
  UPDATE public.payments SET deleted_at = NULL
    WHERE id = '00000000-0000-0000-0007-000000000070';
  PERFORM set_config('app.allow_deleted_at_change', '0', true);
END $$;

-- ============================================================================
-- TEST 30 : Trigger tr_03 — soft-delete payment → is_stale = true (dev)
-- ============================================================================
DO $$
DECLARE stale_flag boolean;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0007-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  PERFORM dev.soft_delete_payment('00000000-0000-0000-0007-000000000070');

  RESET ROLE;

  SELECT is_stale INTO stale_flag
    FROM dev.receipts
    WHERE payment_ids @> ARRAY['00000000-0000-0000-0007-000000000070']::uuid[]
      AND id = '00000000-0000-0000-0007-000000000902';

  IF stale_flag IS NOT TRUE THEN
    RAISE EXCEPTION '[FAIL] TEST 30 dev: is_stale devrait être true après soft-delete du payment lié (got %)', stale_flag;
  END IF;
  RAISE NOTICE '[PASS] TEST 30 dev: trigger tr_03 → is_stale = true après soft-delete payment';

  PERFORM set_config('app.allow_deleted_at_change', '1', true);
  UPDATE dev.payments SET deleted_at = NULL
    WHERE id = '00000000-0000-0000-0007-000000000070';
  PERFORM set_config('app.allow_deleted_at_change', '0', true);
END $$;

-- ============================================================================
-- TEST 31 : RLS activée sur les deux schémas
-- ============================================================================
DO $$
BEGIN
  PERFORM dev.assert_rls_both_schemas('receipts');
  RAISE NOTICE '[PASS] TEST 31: RLS activée sur public.receipts ET dev.receipts';
END $$;

-- ============================================================================
-- Teardown
-- ============================================================================
DELETE FROM public.receipts WHERE landlord_id IN (
  '00000000-0000-0000-0007-000000000001',
  '00000000-0000-0000-0007-000000000002'
);
DELETE FROM dev.receipts WHERE landlord_id IN (
  '00000000-0000-0000-0007-000000000001',
  '00000000-0000-0000-0007-000000000002'
);
DELETE FROM public.payments WHERE landlord_id IN (
  '00000000-0000-0000-0007-000000000001',
  '00000000-0000-0000-0007-000000000002'
);
DELETE FROM dev.payments WHERE landlord_id IN (
  '00000000-0000-0000-0007-000000000001',
  '00000000-0000-0000-0007-000000000002'
);
DELETE FROM public.leases WHERE landlord_id IN (
  '00000000-0000-0000-0007-000000000001',
  '00000000-0000-0000-0007-000000000002'
);
DELETE FROM dev.leases WHERE landlord_id IN (
  '00000000-0000-0000-0007-000000000001',
  '00000000-0000-0000-0007-000000000002'
);
DELETE FROM public.tenants WHERE landlord_id IN (
  '00000000-0000-0000-0007-000000000001',
  '00000000-0000-0000-0007-000000000002'
);
DELETE FROM dev.tenants WHERE landlord_id IN (
  '00000000-0000-0000-0007-000000000001',
  '00000000-0000-0000-0007-000000000002'
);
DELETE FROM public.properties WHERE landlord_id IN (
  '00000000-0000-0000-0007-000000000001',
  '00000000-0000-0000-0007-000000000002'
);
DELETE FROM dev.properties WHERE landlord_id IN (
  '00000000-0000-0000-0007-000000000001',
  '00000000-0000-0000-0007-000000000002'
);
DELETE FROM public.landlords WHERE id IN (
  '00000000-0000-0000-0007-000000000001',
  '00000000-0000-0000-0007-000000000002'
);
DELETE FROM dev.landlords WHERE id IN (
  '00000000-0000-0000-0007-000000000001',
  '00000000-0000-0000-0007-000000000002'
);
DELETE FROM auth.users WHERE id IN (
  '00000000-0000-0000-0007-000000000001',
  '00000000-0000-0000-0007-000000000002'
);

ROLLBACK;
