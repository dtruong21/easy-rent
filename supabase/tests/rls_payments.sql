-- ============================================================================
-- Tests RLS — table payments (FEAT-006)
-- ============================================================================
-- Tests couverts :
--   1.  User A voit ses propres paiements (public)
--   2.  User A voit ses propres paiements (dev)
--   3.  User A ne voit PAS les paiements de User B (public)
--   4.  User A ne voit PAS les paiements de User B (dev)
--   5.  User A ne peut PAS UPDATE un paiement de User B (public)
--   6.  User A ne peut PAS UPDATE un paiement de User B (dev)
--   7.  INSERT avec landlord_id = auth.uid() réussit (public)
--   8.  INSERT avec landlord_id = auth.uid() réussit (dev)
--   9.  INSERT avec landlord_id d'un autre user échoue (42501 — public)
--   10. INSERT avec landlord_id d'un autre user échoue (42501 — dev)
--   11. Trigger tr_00 : INSERT avec lease_id d'un autre user (landlord_id=self) → ERRCODE 23514 (public)
--   12. Trigger tr_00 : INSERT avec lease_id d'un autre user (landlord_id=self) → ERRCODE 23514 (dev)
--   13. Trigger tr_00 : INSERT avec lease_id inexistant → ERRCODE 23514 (public)
--   14. Trigger tr_00 : INSERT avec lease_id inexistant → ERRCODE 23514 (dev)
--   15. CHECK period_end > period_start refusé (public)
--   16. CHECK rent_amount_cents > 0 refusé (public)
--   17. CHECK charges_amount_cents >= 0 : valeur négative refusée (public)
--   18. CHECK payment_method invalide refusé (public)
--   19. CHECK notes > 500 caractères refusé (public)
--   20. CHECK date bounds period_start='1850-01-01' refusé (public)
--   21. CHECK date bounds period_start='2200-01-01' refusé (public)
--   22. Soft-delete via RPC : ligne invisible mais existante (public)
--   23. Soft-delete via RPC : ligne invisible mais existante (dev)
--   24. RPC soft_delete_payment cross-user → NOT FOUND (public)
--   25. RPC soft_delete_payment cross-user → NOT FOUND (dev)
--   26. UPDATE direct de deleted_at refusé par trigger tr_01 (42501 — public)
--   27. UPDATE direct de deleted_at refusé par trigger tr_01 (42501 — dev)
--   28. INSERT deleted_at = now() refusé par trigger tr_01 (42501 — public)
--   29. INSERT deleted_at = now() refusé par trigger tr_01 (42501 — dev)
--   30. INSERT created_at antidaté corrigé silencieusement à now() (public)
--   31. RLS activée sur les deux schémas (assert_rls_both_schemas)
-- ============================================================================
-- USAGE: psql <connection_string> -f supabase/tests/rls_payments.sql
-- ============================================================================

BEGIN;

-- ============================================================================
-- Setup : deux users + landlords + properties + tenants + leases + paiements
-- ============================================================================
-- UUIDs préfixe 0006 (FEAT-006) pour ne pas collisionner avec FEAT-003/004/005

INSERT INTO auth.users (
  id, instance_id, email, encrypted_password, email_confirmed_at,
  created_at, updated_at, raw_app_meta_data, raw_user_meta_data, aud, role
) VALUES
  ('00000000-0000-0000-0006-000000000001', '00000000-0000-0000-0000-000000000000',
   'payment_user_a@test.example', 'hashed', now(), now(), now(),
   '{"provider":"email","providers":["email"]}', '{}', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0006-000000000002', '00000000-0000-0000-0000-000000000000',
   'payment_user_b@test.example', 'hashed', now(), now(), now(),
   '{"provider":"email","providers":["email"]}', '{}', 'authenticated', 'authenticated')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.landlords (id, email) VALUES
  ('00000000-0000-0000-0006-000000000001', 'payment_user_a@test.example'),
  ('00000000-0000-0000-0006-000000000002', 'payment_user_b@test.example')
ON CONFLICT (id) DO NOTHING;

INSERT INTO dev.landlords (id, email) VALUES
  ('00000000-0000-0000-0006-000000000001', 'payment_user_a@test.example'),
  ('00000000-0000-0000-0006-000000000002', 'payment_user_b@test.example')
ON CONFLICT (id) DO NOTHING;

-- Properties : une par user
INSERT INTO public.properties (id, landlord_id, name, address, type) VALUES
  ('00000000-0000-0000-0006-000000000010', '00000000-0000-0000-0006-000000000001',
   'Prop A (payments)', '1 rue A', 'appartement'),
  ('00000000-0000-0000-0006-000000000020', '00000000-0000-0000-0006-000000000002',
   'Prop B (payments)', '2 rue B', 'maison');

INSERT INTO dev.properties (id, landlord_id, name, address, type) VALUES
  ('00000000-0000-0000-0006-000000000010', '00000000-0000-0000-0006-000000000001',
   'Prop A (payments)', '1 rue A', 'appartement'),
  ('00000000-0000-0000-0006-000000000020', '00000000-0000-0000-0006-000000000002',
   'Prop B (payments)', '2 rue B', 'maison');

-- Tenants : un par user
INSERT INTO public.tenants (id, landlord_id, first_name, last_name, email) VALUES
  ('00000000-0000-0000-0006-000000000030', '00000000-0000-0000-0006-000000000001',
   'Tenant', 'A', 'tenant_a_pay@test.example'),
  ('00000000-0000-0000-0006-000000000040', '00000000-0000-0000-0006-000000000002',
   'Tenant', 'B', 'tenant_b_pay@test.example');

INSERT INTO dev.tenants (id, landlord_id, first_name, last_name, email) VALUES
  ('00000000-0000-0000-0006-000000000030', '00000000-0000-0000-0006-000000000001',
   'Tenant', 'A', 'tenant_a_pay@test.example'),
  ('00000000-0000-0000-0006-000000000040', '00000000-0000-0000-0006-000000000002',
   'Tenant', 'B', 'tenant_b_pay@test.example');

-- Leases : un par user
INSERT INTO public.leases (
  id, landlord_id, property_id, tenant_id, rent_amount_cents, start_date
) VALUES
  ('00000000-0000-0000-0006-000000000050', '00000000-0000-0000-0006-000000000001',
   '00000000-0000-0000-0006-000000000010', '00000000-0000-0000-0006-000000000030',
   85000, '2026-01-01'),
  ('00000000-0000-0000-0006-000000000060', '00000000-0000-0000-0006-000000000002',
   '00000000-0000-0000-0006-000000000020', '00000000-0000-0000-0006-000000000040',
   120000, '2026-02-01');

INSERT INTO dev.leases (
  id, landlord_id, property_id, tenant_id, rent_amount_cents, start_date
) VALUES
  ('00000000-0000-0000-0006-000000000050', '00000000-0000-0000-0006-000000000001',
   '00000000-0000-0000-0006-000000000010', '00000000-0000-0000-0006-000000000030',
   85000, '2026-01-01'),
  ('00000000-0000-0000-0006-000000000060', '00000000-0000-0000-0006-000000000002',
   '00000000-0000-0000-0006-000000000020', '00000000-0000-0000-0006-000000000040',
   120000, '2026-02-01');

-- Paiements initiaux (insérés en superuser, sans RLS)
INSERT INTO public.payments (
  id, lease_id, landlord_id, period_start, period_end, paid_at,
  rent_amount_cents, payment_method
) VALUES
  ('00000000-0000-0000-0006-000000000070', '00000000-0000-0000-0006-000000000050',
   '00000000-0000-0000-0006-000000000001',
   '2026-01-01', '2026-01-31', '2026-01-05', 85000, 'virement'),
  ('00000000-0000-0000-0006-000000000080', '00000000-0000-0000-0006-000000000060',
   '00000000-0000-0000-0006-000000000002',
   '2026-02-01', '2026-02-28', '2026-02-05', 120000, 'prelevement');

INSERT INTO dev.payments (
  id, lease_id, landlord_id, period_start, period_end, paid_at,
  rent_amount_cents, payment_method
) VALUES
  ('00000000-0000-0000-0006-000000000070', '00000000-0000-0000-0006-000000000050',
   '00000000-0000-0000-0006-000000000001',
   '2026-01-01', '2026-01-31', '2026-01-05', 85000, 'virement'),
  ('00000000-0000-0000-0006-000000000080', '00000000-0000-0000-0006-000000000060',
   '00000000-0000-0000-0006-000000000002',
   '2026-02-01', '2026-02-28', '2026-02-05', 120000, 'prelevement');

-- ============================================================================
-- TEST 1 : User A voit ses propres paiements (public)
-- ============================================================================
DO $$
DECLARE row_count integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0006-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  SELECT COUNT(*) INTO row_count FROM public.payments
    WHERE landlord_id = '00000000-0000-0000-0006-000000000001';

  RESET ROLE;
  IF row_count <> 1 THEN
    RAISE EXCEPTION '[FAIL] TEST 1 public: User A devrait voir 1 paiement (got %)', row_count;
  END IF;
  RAISE NOTICE '[PASS] TEST 1 public: User A voit ses propres paiements';
END $$;

-- ============================================================================
-- TEST 2 : User A voit ses propres paiements (dev)
-- ============================================================================
DO $$
DECLARE row_count integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0006-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  SELECT COUNT(*) INTO row_count FROM dev.payments
    WHERE landlord_id = '00000000-0000-0000-0006-000000000001';

  RESET ROLE;
  IF row_count <> 1 THEN
    RAISE EXCEPTION '[FAIL] TEST 2 dev: User A devrait voir 1 paiement (got %)', row_count;
  END IF;
  RAISE NOTICE '[PASS] TEST 2 dev: User A voit ses propres paiements';
END $$;

-- ============================================================================
-- TEST 3 : User A ne voit PAS les paiements de User B (public)
-- ============================================================================
DO $$
DECLARE row_count integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0006-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  SELECT COUNT(*) INTO row_count FROM public.payments
    WHERE landlord_id = '00000000-0000-0000-0006-000000000002';

  RESET ROLE;
  IF row_count <> 0 THEN
    RAISE EXCEPTION '[FAIL] TEST 3 public: User A ne devrait pas voir les paiements de User B (got %)', row_count;
  END IF;
  RAISE NOTICE '[PASS] TEST 3 public: User A ne voit pas les paiements de User B';
END $$;

-- ============================================================================
-- TEST 4 : User A ne voit PAS les paiements de User B (dev)
-- ============================================================================
DO $$
DECLARE row_count integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0006-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  SELECT COUNT(*) INTO row_count FROM dev.payments
    WHERE landlord_id = '00000000-0000-0000-0006-000000000002';

  RESET ROLE;
  IF row_count <> 0 THEN
    RAISE EXCEPTION '[FAIL] TEST 4 dev: User A ne devrait pas voir les paiements de User B (got %)', row_count;
  END IF;
  RAISE NOTICE '[PASS] TEST 4 dev: User A ne voit pas les paiements de User B';
END $$;

-- ============================================================================
-- TEST 5 : User A ne peut PAS UPDATE un paiement de User B (public)
-- ============================================================================
DO $$
DECLARE rows_updated integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0006-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  UPDATE public.payments SET rent_amount_cents = 1
    WHERE id = '00000000-0000-0000-0006-000000000080';
  GET DIAGNOSTICS rows_updated = ROW_COUNT;

  RESET ROLE;
  IF rows_updated <> 0 THEN
    RAISE EXCEPTION '[FAIL] TEST 5 public: User A ne devrait pas UPDATE le paiement de User B (updated %)', rows_updated;
  END IF;
  RAISE NOTICE '[PASS] TEST 5 public: User A ne peut pas UPDATE le paiement de User B';
END $$;

-- ============================================================================
-- TEST 6 : User A ne peut PAS UPDATE un paiement de User B (dev)
-- ============================================================================
DO $$
DECLARE rows_updated integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0006-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  UPDATE dev.payments SET rent_amount_cents = 1
    WHERE id = '00000000-0000-0000-0006-000000000080';
  GET DIAGNOSTICS rows_updated = ROW_COUNT;

  RESET ROLE;
  IF rows_updated <> 0 THEN
    RAISE EXCEPTION '[FAIL] TEST 6 dev: User A ne devrait pas UPDATE le paiement de User B (updated %)', rows_updated;
  END IF;
  RAISE NOTICE '[PASS] TEST 6 dev: User A ne peut pas UPDATE le paiement de User B';
END $$;

-- ============================================================================
-- TEST 7 : INSERT avec landlord_id = auth.uid() réussit (public)
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0006-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    INSERT INTO public.payments (
      lease_id, landlord_id, period_start, period_end, paid_at,
      rent_amount_cents, payment_method
    ) VALUES (
      '00000000-0000-0000-0006-000000000050',
      '00000000-0000-0000-0006-000000000001',
      '2026-03-01', '2026-03-31', '2026-03-05',
      85000, 'virement'
    );
    RESET ROLE;
    RAISE NOTICE '[PASS] TEST 7 public: INSERT valide avec son propre landlord_id réussit';
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 7 public: INSERT devrait réussir (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 8 : INSERT avec landlord_id = auth.uid() réussit (dev)
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0006-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    INSERT INTO dev.payments (
      lease_id, landlord_id, period_start, period_end, paid_at,
      rent_amount_cents, payment_method
    ) VALUES (
      '00000000-0000-0000-0006-000000000050',
      '00000000-0000-0000-0006-000000000001',
      '2026-03-01', '2026-03-31', '2026-03-05',
      85000, 'virement'
    );
    RESET ROLE;
    RAISE NOTICE '[PASS] TEST 8 dev: INSERT valide avec son propre landlord_id réussit';
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 8 dev: INSERT devrait réussir (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 9 : INSERT avec landlord_id d'un autre user échoue (42501 — public)
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0006-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    INSERT INTO public.payments (
      lease_id, landlord_id, period_start, period_end, paid_at,
      rent_amount_cents, payment_method
    ) VALUES (
      '00000000-0000-0000-0006-000000000060',   -- lease de User B
      '00000000-0000-0000-0006-000000000002',   -- landlord_id de User B
      '2026-03-01', '2026-03-31', '2026-03-05',
      50000, 'cheque'
    );
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 9 public: INSERT avec landlord_id étranger aurait dû être bloqué';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 9 public: INSERT avec landlord_id étranger refusé par RLS (42501)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 9 public: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 10 : INSERT avec landlord_id d'un autre user échoue (42501 — dev)
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0006-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    INSERT INTO dev.payments (
      lease_id, landlord_id, period_start, period_end, paid_at,
      rent_amount_cents, payment_method
    ) VALUES (
      '00000000-0000-0000-0006-000000000060',
      '00000000-0000-0000-0006-000000000002',
      '2026-03-01', '2026-03-31', '2026-03-05',
      50000, 'cheque'
    );
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 10 dev: INSERT avec landlord_id étranger aurait dû être bloqué';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 10 dev: INSERT avec landlord_id étranger refusé par RLS (42501)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 10 dev: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 11 : Trigger tr_00 — lease_id d'un autre user, landlord_id=self → ERRCODE 23514 (public)
-- Scénario (superuser) : on insère un paiement avec landlord_id=User A mais
-- lease_id appartenant à User B → le trigger doit rejeter (ownership mismatch).
-- ============================================================================
DO $$
BEGIN
  BEGIN
    INSERT INTO public.payments (
      lease_id, landlord_id, period_start, period_end, paid_at,
      rent_amount_cents, payment_method
    ) VALUES (
      '00000000-0000-0000-0006-000000000060',   -- lease de User B
      '00000000-0000-0000-0006-000000000001',   -- landlord_id de User A (mismatch)
      '2026-04-01', '2026-04-30', '2026-04-05',
      85000, 'virement'
    );
    RAISE EXCEPTION '[FAIL] TEST 11 public: Le trigger tr_00 aurait dû rejeter le cross-ownership lease';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE '[PASS] TEST 11 public: lease_id d''un autre user refusé par trigger tr_00 (23514)';
    WHEN OTHERS THEN
      RAISE EXCEPTION '[FAIL] TEST 11 public: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 12 : Trigger tr_00 — lease_id d'un autre user, landlord_id=self → ERRCODE 23514 (dev)
-- ============================================================================
DO $$
BEGIN
  BEGIN
    INSERT INTO dev.payments (
      lease_id, landlord_id, period_start, period_end, paid_at,
      rent_amount_cents, payment_method
    ) VALUES (
      '00000000-0000-0000-0006-000000000060',
      '00000000-0000-0000-0006-000000000001',
      '2026-04-01', '2026-04-30', '2026-04-05',
      85000, 'virement'
    );
    RAISE EXCEPTION '[FAIL] TEST 12 dev: Le trigger tr_00 aurait dû rejeter le cross-ownership lease';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE '[PASS] TEST 12 dev: lease_id d''un autre user refusé par trigger tr_00 (23514)';
    WHEN OTHERS THEN
      RAISE EXCEPTION '[FAIL] TEST 12 dev: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 13 : Trigger tr_00 — lease_id inexistant → ERRCODE 23514 (public)
-- ============================================================================
DO $$
BEGIN
  BEGIN
    INSERT INTO public.payments (
      lease_id, landlord_id, period_start, period_end, paid_at,
      rent_amount_cents, payment_method
    ) VALUES (
      'ffffffff-ffff-ffff-ffff-ffffffffffff',   -- lease_id inexistant
      '00000000-0000-0000-0006-000000000001',
      '2026-04-01', '2026-04-30', '2026-04-05',
      85000, 'virement'
    );
    RAISE EXCEPTION '[FAIL] TEST 13 public: Le trigger tr_00 aurait dû rejeter le lease_id inexistant';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE '[PASS] TEST 13 public: lease_id inexistant refusé par trigger tr_00 (23514)';
    WHEN OTHERS THEN
      RAISE EXCEPTION '[FAIL] TEST 13 public: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 14 : Trigger tr_00 — lease_id inexistant → ERRCODE 23514 (dev)
-- ============================================================================
DO $$
BEGIN
  BEGIN
    INSERT INTO dev.payments (
      lease_id, landlord_id, period_start, period_end, paid_at,
      rent_amount_cents, payment_method
    ) VALUES (
      'ffffffff-ffff-ffff-ffff-ffffffffffff',
      '00000000-0000-0000-0006-000000000001',
      '2026-04-01', '2026-04-30', '2026-04-05',
      85000, 'virement'
    );
    RAISE EXCEPTION '[FAIL] TEST 14 dev: Le trigger tr_00 aurait dû rejeter le lease_id inexistant';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE '[PASS] TEST 14 dev: lease_id inexistant refusé par trigger tr_00 (23514)';
    WHEN OTHERS THEN
      RAISE EXCEPTION '[FAIL] TEST 14 dev: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 15 : CHECK period_end > period_start — refusé (public)
-- ============================================================================
DO $$
BEGIN
  BEGIN
    INSERT INTO public.payments (
      lease_id, landlord_id, period_start, period_end, paid_at,
      rent_amount_cents, payment_method
    ) VALUES (
      '00000000-0000-0000-0006-000000000050',
      '00000000-0000-0000-0006-000000000001',
      '2026-05-31', '2026-05-01',  -- period_end < period_start : invalide
      '2026-05-05',
      85000, 'virement'
    );
    RAISE EXCEPTION '[FAIL] TEST 15 public: Le CHECK aurait dû rejeter period_end < period_start';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE '[PASS] TEST 15 public: period_end < period_start refusé par CHECK (23514)';
    WHEN OTHERS THEN
      RAISE EXCEPTION '[FAIL] TEST 15 public: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 16 : CHECK rent_amount_cents > 0 — valeur nulle ou négative refusée (public)
-- ============================================================================
DO $$
BEGIN
  BEGIN
    INSERT INTO public.payments (
      lease_id, landlord_id, period_start, period_end, paid_at,
      rent_amount_cents, payment_method
    ) VALUES (
      '00000000-0000-0000-0006-000000000050',
      '00000000-0000-0000-0006-000000000001',
      '2026-05-01', '2026-05-31', '2026-05-05',
      0, 'virement'  -- 0 : invalide (doit être > 0)
    );
    RAISE EXCEPTION '[FAIL] TEST 16 public: Le CHECK aurait dû rejeter rent_amount_cents = 0';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE '[PASS] TEST 16 public: rent_amount_cents = 0 refusé par CHECK (23514)';
    WHEN OTHERS THEN
      RAISE EXCEPTION '[FAIL] TEST 16 public: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 17 : CHECK charges_amount_cents >= 0 — valeur négative refusée (public)
-- ============================================================================
DO $$
BEGIN
  BEGIN
    INSERT INTO public.payments (
      lease_id, landlord_id, period_start, period_end, paid_at,
      rent_amount_cents, charges_amount_cents, payment_method
    ) VALUES (
      '00000000-0000-0000-0006-000000000050',
      '00000000-0000-0000-0006-000000000001',
      '2026-05-01', '2026-05-31', '2026-05-05',
      85000, -1, 'virement'  -- charges négatives : invalide
    );
    RAISE EXCEPTION '[FAIL] TEST 17 public: Le CHECK aurait dû rejeter charges_amount_cents = -1';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE '[PASS] TEST 17 public: charges_amount_cents = -1 refusé par CHECK (23514)';
    WHEN OTHERS THEN
      RAISE EXCEPTION '[FAIL] TEST 17 public: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 18 : CHECK payment_method invalide — refusé (public)
-- ============================================================================
DO $$
BEGIN
  BEGIN
    INSERT INTO public.payments (
      lease_id, landlord_id, period_start, period_end, paid_at,
      rent_amount_cents, payment_method
    ) VALUES (
      '00000000-0000-0000-0006-000000000050',
      '00000000-0000-0000-0006-000000000001',
      '2026-05-01', '2026-05-31', '2026-05-05',
      85000, 'carte_bleue'  -- valeur hors enum : invalide
    );
    RAISE EXCEPTION '[FAIL] TEST 18 public: Le CHECK aurait dû rejeter payment_method=''carte_bleue''';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE '[PASS] TEST 18 public: payment_method=''carte_bleue'' refusé par CHECK (23514)';
    WHEN OTHERS THEN
      RAISE EXCEPTION '[FAIL] TEST 18 public: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 19 : CHECK notes > 500 caractères — refusé (public)
-- ============================================================================
DO $$
BEGIN
  BEGIN
    INSERT INTO public.payments (
      lease_id, landlord_id, period_start, period_end, paid_at,
      rent_amount_cents, payment_method, notes
    ) VALUES (
      '00000000-0000-0000-0006-000000000050',
      '00000000-0000-0000-0006-000000000001',
      '2026-05-01', '2026-05-31', '2026-05-05',
      85000, 'virement',
      repeat('x', 501)  -- 501 caractères : au-delà de la limite
    );
    RAISE EXCEPTION '[FAIL] TEST 19 public: Le CHECK aurait dû rejeter notes > 500 chars';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE '[PASS] TEST 19 public: notes > 500 chars refusé par CHECK (23514)';
    WHEN OTHERS THEN
      RAISE EXCEPTION '[FAIL] TEST 19 public: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 20 : CHECK date bounds — period_start='1850-01-01' refusé (public)
-- ============================================================================
DO $$
BEGIN
  BEGIN
    INSERT INTO public.payments (
      lease_id, landlord_id, period_start, period_end, paid_at,
      rent_amount_cents, payment_method
    ) VALUES (
      '00000000-0000-0000-0006-000000000050',
      '00000000-0000-0000-0006-000000000001',
      '1850-01-01', '1850-01-31', '1850-01-05',  -- hors borne inférieure 1900
      85000, 'virement'
    );
    RAISE EXCEPTION '[FAIL] TEST 20 public: period_start=''1850-01-01'' aurait dû être refusé';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE '[PASS] TEST 20 public: period_start=''1850-01-01'' refusé par CHECK date bounds (23514)';
    WHEN OTHERS THEN
      RAISE EXCEPTION '[FAIL] TEST 20 public: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 21 : CHECK date bounds — period_start='2200-01-01' refusé (public)
-- ============================================================================
DO $$
BEGIN
  BEGIN
    INSERT INTO public.payments (
      lease_id, landlord_id, period_start, period_end, paid_at,
      rent_amount_cents, payment_method
    ) VALUES (
      '00000000-0000-0000-0006-000000000050',
      '00000000-0000-0000-0006-000000000001',
      '2200-01-01', '2200-01-31', '2200-01-05',  -- hors borne supérieure 2100
      85000, 'virement'
    );
    RAISE EXCEPTION '[FAIL] TEST 21 public: period_start=''2200-01-01'' aurait dû être refusé';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE '[PASS] TEST 21 public: period_start=''2200-01-01'' refusé par CHECK date bounds (23514)';
    WHEN OTHERS THEN
      RAISE EXCEPTION '[FAIL] TEST 21 public: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 22 : Soft-delete via RPC — ligne invisible mais existante (public)
-- ============================================================================
DO $$
DECLARE row_count integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0006-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  PERFORM public.soft_delete_payment('00000000-0000-0000-0006-000000000070');

  SELECT COUNT(*) INTO row_count FROM public.payments
    WHERE id = '00000000-0000-0000-0006-000000000070';

  RESET ROLE;

  IF (SELECT deleted_at FROM public.payments
        WHERE id = '00000000-0000-0000-0006-000000000070') IS NULL THEN
    RAISE EXCEPTION '[FAIL] TEST 22 public: La ligne devrait avoir deleted_at positionné';
  END IF;

  IF row_count <> 0 THEN
    RAISE EXCEPTION '[FAIL] TEST 22 public: Le paiement soft-deleted devrait être invisible (got %)', row_count;
  END IF;
  RAISE NOTICE '[PASS] TEST 22 public: soft_delete_payment fonctionne — ligne invisible mais existante';

  -- Réinitialiser pour les tests suivants
  PERFORM set_config('app.allow_deleted_at_change', '1', true);
  UPDATE public.payments SET deleted_at = NULL
    WHERE id = '00000000-0000-0000-0006-000000000070';
  PERFORM set_config('app.allow_deleted_at_change', '0', true);
END $$;

-- ============================================================================
-- TEST 23 : Soft-delete via RPC — ligne invisible mais existante (dev)
-- ============================================================================
DO $$
DECLARE row_count integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0006-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  PERFORM dev.soft_delete_payment('00000000-0000-0000-0006-000000000070');

  SELECT COUNT(*) INTO row_count FROM dev.payments
    WHERE id = '00000000-0000-0000-0006-000000000070';

  RESET ROLE;

  IF (SELECT deleted_at FROM dev.payments
        WHERE id = '00000000-0000-0000-0006-000000000070') IS NULL THEN
    RAISE EXCEPTION '[FAIL] TEST 23 dev: La ligne devrait avoir deleted_at positionné';
  END IF;

  IF row_count <> 0 THEN
    RAISE EXCEPTION '[FAIL] TEST 23 dev: Le paiement soft-deleted devrait être invisible (got %)', row_count;
  END IF;
  RAISE NOTICE '[PASS] TEST 23 dev: soft_delete_payment fonctionne — ligne invisible mais existante';

  PERFORM set_config('app.allow_deleted_at_change', '1', true);
  UPDATE dev.payments SET deleted_at = NULL
    WHERE id = '00000000-0000-0000-0006-000000000070';
  PERFORM set_config('app.allow_deleted_at_change', '0', true);
END $$;

-- ============================================================================
-- TEST 24 : RPC soft_delete_payment cross-user → NOT FOUND (public)
-- Scénario : User A tente de soft-delete un paiement de User B.
-- Attendu : ERRCODE P0002 (no_data_found) — pas de fuite sur l'existence.
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0006-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    PERFORM public.soft_delete_payment('00000000-0000-0000-0006-000000000080');
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 24 public: La RPC aurait dû lever NOT FOUND pour un paiement étranger';
  EXCEPTION
    WHEN no_data_found THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 24 public: soft_delete_payment sur paiement étranger → NOT FOUND (P0002)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 24 public: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;

  -- Vérifier que le paiement de User B n'a pas été modifié
  IF (SELECT deleted_at FROM public.payments
        WHERE id = '00000000-0000-0000-0006-000000000080') IS NOT NULL THEN
    RAISE EXCEPTION '[FAIL] TEST 24 public: Le paiement de User B ne devrait pas avoir été soft-deleted';
  END IF;
END $$;

-- ============================================================================
-- TEST 25 : RPC soft_delete_payment cross-user → NOT FOUND (dev)
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0006-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    PERFORM dev.soft_delete_payment('00000000-0000-0000-0006-000000000080');
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 25 dev: La RPC aurait dû lever NOT FOUND pour un paiement étranger';
  EXCEPTION
    WHEN no_data_found THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 25 dev: soft_delete_payment sur paiement étranger → NOT FOUND (P0002)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 25 dev: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;

  IF (SELECT deleted_at FROM dev.payments
        WHERE id = '00000000-0000-0000-0006-000000000080') IS NOT NULL THEN
    RAISE EXCEPTION '[FAIL] TEST 25 dev: Le paiement de User B ne devrait pas avoir été soft-deleted';
  END IF;
END $$;

-- ============================================================================
-- TEST 26 : Trigger tr_01 — UPDATE direct de deleted_at refusé (42501 — public)
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0006-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    UPDATE public.payments SET deleted_at = now()
      WHERE id = '00000000-0000-0000-0006-000000000070';
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 26 public: UPDATE direct de deleted_at aurait dû être bloqué par trigger tr_01';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 26 public: UPDATE direct de deleted_at bloqué par trigger tr_01 (42501)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 26 public: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 27 : Trigger tr_01 — UPDATE direct de deleted_at refusé (42501 — dev)
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0006-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    UPDATE dev.payments SET deleted_at = now()
      WHERE id = '00000000-0000-0000-0006-000000000070';
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 27 dev: UPDATE direct de deleted_at aurait dû être bloqué par trigger tr_01';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 27 dev: UPDATE direct de deleted_at bloqué par trigger tr_01 (42501)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 27 dev: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 28 : INSERT avec deleted_at = now() refusé par trigger tr_01 (42501 — public)
-- Scénario : un client tente de créer un paiement avec deleted_at positionné dès
-- l'INSERT (pré-soft-delete malveillant).
-- Note : tr_00_assert_payment_lease_ownership s'exécute avant tr_01 (ordre alpha).
-- tr_00 valide le lease_id, puis tr_01 bloque deleted_at = now().
-- Attendu : SQLSTATE 42501 (insufficient_privilege).
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0006-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    INSERT INTO public.payments (
      lease_id, landlord_id, period_start, period_end, paid_at,
      rent_amount_cents, payment_method, deleted_at
    ) VALUES (
      '00000000-0000-0000-0006-000000000050',
      '00000000-0000-0000-0006-000000000001',
      '2026-06-01', '2026-06-30', '2026-06-05',
      85000, 'virement',
      now()  -- tentative de pré-soft-delete
    );
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 28 public: INSERT avec deleted_at aurait dû être bloqué par trigger tr_01';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 28 public: INSERT avec deleted_at=now() refusé par trigger tr_01 (42501)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 28 public: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 29 : INSERT avec deleted_at = now() refusé par trigger tr_01 (42501 — dev)
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0006-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    INSERT INTO dev.payments (
      lease_id, landlord_id, period_start, period_end, paid_at,
      rent_amount_cents, payment_method, deleted_at
    ) VALUES (
      '00000000-0000-0000-0006-000000000050',
      '00000000-0000-0000-0006-000000000001',
      '2026-06-01', '2026-06-30', '2026-06-05',
      85000, 'virement',
      now()
    );
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 29 dev: INSERT avec deleted_at aurait dû être bloqué par trigger tr_01';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 29 dev: INSERT avec deleted_at=now() refusé par trigger tr_01 (42501)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 29 dev: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 30 : INSERT avec created_at antidaté → created_at forcé à now() (public)
-- Scénario : le client fournit '2020-01-01' comme created_at.
-- Attendu : la ligne est créée, created_at ≥ now() - interval '10 seconds'.
-- ============================================================================
DO $$
DECLARE inserted_created_at timestamptz;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0006-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    INSERT INTO public.payments (
      lease_id, landlord_id, period_start, period_end, paid_at,
      rent_amount_cents, payment_method, created_at
    ) VALUES (
      '00000000-0000-0000-0006-000000000050',
      '00000000-0000-0000-0006-000000000001',
      '2026-07-01', '2026-07-31', '2026-07-05',
      85000, 'especes',
      '2020-01-01 00:00:00+00'::timestamptz  -- antidaté intentionnel
    )
    RETURNING created_at INTO inserted_created_at;

    RESET ROLE;

    IF inserted_created_at < (now() - interval '10 seconds') THEN
      RAISE EXCEPTION '[FAIL] TEST 30 public: created_at antidaté non corrigé (got %)', inserted_created_at;
    END IF;
    RAISE NOTICE '[PASS] TEST 30 public: created_at antidaté corrigé silencieusement à now() par trigger tr_01 (got %)', inserted_created_at;

  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 30 public: INSERT devrait réussir avec created_at corrigé (SQLSTATE %, msg: %)',
      SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 31 : RLS activée sur les deux schémas
-- ============================================================================
DO $$
BEGIN
  PERFORM dev.assert_rls_both_schemas('payments');
  RAISE NOTICE '[PASS] TEST 31: RLS activée sur public.payments ET dev.payments';
END $$;

-- ============================================================================
-- Teardown
-- ============================================================================
DELETE FROM public.payments WHERE landlord_id IN (
  '00000000-0000-0000-0006-000000000001',
  '00000000-0000-0000-0006-000000000002'
);
DELETE FROM dev.payments WHERE landlord_id IN (
  '00000000-0000-0000-0006-000000000001',
  '00000000-0000-0000-0006-000000000002'
);
DELETE FROM public.leases WHERE landlord_id IN (
  '00000000-0000-0000-0006-000000000001',
  '00000000-0000-0000-0006-000000000002'
);
DELETE FROM dev.leases WHERE landlord_id IN (
  '00000000-0000-0000-0006-000000000001',
  '00000000-0000-0000-0006-000000000002'
);
DELETE FROM public.tenants WHERE landlord_id IN (
  '00000000-0000-0000-0006-000000000001',
  '00000000-0000-0000-0006-000000000002'
);
DELETE FROM dev.tenants WHERE landlord_id IN (
  '00000000-0000-0000-0006-000000000001',
  '00000000-0000-0000-0006-000000000002'
);
DELETE FROM public.properties WHERE landlord_id IN (
  '00000000-0000-0000-0006-000000000001',
  '00000000-0000-0000-0006-000000000002'
);
DELETE FROM dev.properties WHERE landlord_id IN (
  '00000000-0000-0000-0006-000000000001',
  '00000000-0000-0000-0006-000000000002'
);
DELETE FROM public.landlords WHERE id IN (
  '00000000-0000-0000-0006-000000000001',
  '00000000-0000-0000-0006-000000000002'
);
DELETE FROM dev.landlords WHERE id IN (
  '00000000-0000-0000-0006-000000000001',
  '00000000-0000-0000-0006-000000000002'
);
DELETE FROM auth.users WHERE id IN (
  '00000000-0000-0000-0006-000000000001',
  '00000000-0000-0000-0006-000000000002'
);

ROLLBACK;
