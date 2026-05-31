-- ============================================================================
-- Tests RLS — table leases (FEAT-002)
-- ============================================================================
-- Tests couverts :
--   1.  User A voit ses propres baux (public)
--   2.  User A voit ses propres baux (dev)
--   3.  User A ne voit PAS les baux de User B (public)
--   4.  User A ne voit PAS les baux de User B (dev)
--   5.  User A ne peut PAS UPDATE un bail de User B (public)
--   6.  User A ne peut PAS UPDATE un bail de User B (dev)
--   7.  INSERT avec landlord_id = auth.uid() réussit (public)
--   8.  INSERT avec landlord_id = auth.uid() réussit (dev)
--   9.  INSERT avec landlord_id d'un autre user échoue (42501 — public)
--   10. INSERT avec landlord_id d'un autre user échoue (42501 — dev)
--   11. Bail soft-deleted invisible pour son propriétaire (public)
--   12. Bail soft-deleted invisible pour son propriétaire (dev)
--   13. Trigger tr_01 : UPDATE direct de deleted_at refusé (42501 — public)
--   14. Trigger tr_01 : UPDATE direct de deleted_at refusé (42501 — dev)
--   15. RPC soft_delete_lease fonctionne — ligne invisible mais existante (public)
--   16. RPC soft_delete_lease fonctionne — ligne invisible mais existante (dev)
--   17. RPC soft_delete_lease de User A sur bail de User B → NOT FOUND (public)
--   18. RPC soft_delete_lease de User A sur bail de User B → NOT FOUND (dev)
--   19. Trigger assert_lease_ownership_consistency : property d'un user, tenant d'un autre → ERREUR (public)
--   20. Trigger assert_lease_ownership_consistency : property d'un user, tenant d'un autre → ERREUR (dev)
--   21. CHECK end_date > start_date : end_date ≤ start_date refusé (public)
--   22. CHECK rent_amount_cents > 0 : montant négatif refusé (public)
--   23. RLS activée sur les deux schémas (assert_rls_both_schemas)
-- [F2] 24. INSERT avec deleted_at = now() refusé par trigger tr_01 (SQLSTATE 42501 — public)
-- [F2] 25. INSERT avec deleted_at = now() refusé par trigger tr_01 (SQLSTATE 42501 — dev)
-- [F2] 26. INSERT avec created_at antidaté : created_at corrigé silencieusement à now() (public)
-- [F2] 27. INSERT avec created_at antidaté : created_at corrigé silencieusement à now() (dev)
-- [date-bounds] 28. INSERT start_date='1850-01-01' refusé par CHECK leases_date_range_check (23514 — public)
-- [date-bounds] 29. INSERT start_date='2200-01-01' refusé par CHECK leases_date_range_check (23514 — public)
-- [date-bounds] 30. INSERT end_date='9999-12-31' refusé par CHECK leases_date_range_check (23514 — public)
-- [date-bounds] 31. INSERT start_date='2026-01-01', end_date=NULL accepté (régression — public)
-- ============================================================================
-- USAGE: psql <connection_string> -f supabase/tests/rls_leases.sql
-- ============================================================================

BEGIN;

-- ============================================================================
-- Setup : deux users + landlords + une property et un tenant par user
-- ============================================================================

INSERT INTO auth.users (
  id, instance_id, email, encrypted_password, email_confirmed_at,
  created_at, updated_at, raw_app_meta_data, raw_user_meta_data, aud, role
) VALUES
  ('00000000-0000-0000-0003-000000000001', '00000000-0000-0000-0000-000000000000',
   'lease_user_a@test.example', 'hashed', now(), now(), now(),
   '{"provider":"email","providers":["email"]}', '{}', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0003-000000000002', '00000000-0000-0000-0000-000000000000',
   'lease_user_b@test.example', 'hashed', now(), now(), now(),
   '{"provider":"email","providers":["email"]}', '{}', 'authenticated', 'authenticated')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.landlords (id, email) VALUES
  ('00000000-0000-0000-0003-000000000001', 'lease_user_a@test.example'),
  ('00000000-0000-0000-0003-000000000002', 'lease_user_b@test.example')
ON CONFLICT (id) DO NOTHING;

INSERT INTO dev.landlords (id, email) VALUES
  ('00000000-0000-0000-0003-000000000001', 'lease_user_a@test.example'),
  ('00000000-0000-0000-0003-000000000002', 'lease_user_b@test.example')
ON CONFLICT (id) DO NOTHING;

-- Properties : une par user
INSERT INTO public.properties (id, landlord_id, name, address, type) VALUES
  ('00000000-0000-0000-0003-000000000010', '00000000-0000-0000-0003-000000000001',
   'Prop User A', '1 rue A', 'appartement'),
  ('00000000-0000-0000-0003-000000000020', '00000000-0000-0000-0003-000000000002',
   'Prop User B', '2 rue B', 'maison');

INSERT INTO dev.properties (id, landlord_id, name, address, type) VALUES
  ('00000000-0000-0000-0003-000000000010', '00000000-0000-0000-0003-000000000001',
   'Prop User A', '1 rue A', 'appartement'),
  ('00000000-0000-0000-0003-000000000020', '00000000-0000-0000-0003-000000000002',
   'Prop User B', '2 rue B', 'maison');

-- Tenants : un par user
INSERT INTO public.tenants (id, landlord_id, first_name, last_name, email) VALUES
  ('00000000-0000-0000-0003-000000000030', '00000000-0000-0000-0003-000000000001',
   'Tenant', 'A', 'tenant_a@test.example'),
  ('00000000-0000-0000-0003-000000000040', '00000000-0000-0000-0003-000000000002',
   'Tenant', 'B', 'tenant_b@test.example');

INSERT INTO dev.tenants (id, landlord_id, first_name, last_name, email) VALUES
  ('00000000-0000-0000-0003-000000000030', '00000000-0000-0000-0003-000000000001',
   'Tenant', 'A', 'tenant_a@test.example'),
  ('00000000-0000-0000-0003-000000000040', '00000000-0000-0000-0003-000000000002',
   'Tenant', 'B', 'tenant_b@test.example');

-- Baux : un par user
INSERT INTO public.leases (
  id, landlord_id, property_id, tenant_id, rent_amount_cents, start_date
) VALUES
  ('00000000-0000-0000-0003-000000000050', '00000000-0000-0000-0003-000000000001',
   '00000000-0000-0000-0003-000000000010', '00000000-0000-0000-0003-000000000030',
   85000, '2026-01-01'),
  ('00000000-0000-0000-0003-000000000060', '00000000-0000-0000-0003-000000000002',
   '00000000-0000-0000-0003-000000000020', '00000000-0000-0000-0003-000000000040',
   120000, '2026-02-01');

INSERT INTO dev.leases (
  id, landlord_id, property_id, tenant_id, rent_amount_cents, start_date
) VALUES
  ('00000000-0000-0000-0003-000000000050', '00000000-0000-0000-0003-000000000001',
   '00000000-0000-0000-0003-000000000010', '00000000-0000-0000-0003-000000000030',
   85000, '2026-01-01'),
  ('00000000-0000-0000-0003-000000000060', '00000000-0000-0000-0003-000000000002',
   '00000000-0000-0000-0003-000000000020', '00000000-0000-0000-0003-000000000040',
   120000, '2026-02-01');

-- ============================================================================
-- TEST 1 : User A voit ses propres baux (public)
-- ============================================================================
DO $$
DECLARE row_count integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0003-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  SELECT COUNT(*) INTO row_count FROM public.leases
    WHERE landlord_id = '00000000-0000-0000-0003-000000000001';

  RESET ROLE;
  IF row_count <> 1 THEN
    RAISE EXCEPTION '[FAIL] TEST 1 public: User A devrait voir 1 bail (got %)', row_count;
  END IF;
  RAISE NOTICE '[PASS] TEST 1 public: User A voit ses propres baux';
END $$;

-- ============================================================================
-- TEST 2 : User A voit ses propres baux (dev)
-- ============================================================================
DO $$
DECLARE row_count integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0003-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  SELECT COUNT(*) INTO row_count FROM dev.leases
    WHERE landlord_id = '00000000-0000-0000-0003-000000000001';

  RESET ROLE;
  IF row_count <> 1 THEN
    RAISE EXCEPTION '[FAIL] TEST 2 dev: User A devrait voir 1 bail (got %)', row_count;
  END IF;
  RAISE NOTICE '[PASS] TEST 2 dev: User A voit ses propres baux';
END $$;

-- ============================================================================
-- TEST 3 : User A ne voit PAS les baux de User B (public)
-- ============================================================================
DO $$
DECLARE row_count integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0003-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  SELECT COUNT(*) INTO row_count FROM public.leases
    WHERE landlord_id = '00000000-0000-0000-0003-000000000002';

  RESET ROLE;
  IF row_count <> 0 THEN
    RAISE EXCEPTION '[FAIL] TEST 3 public: User A ne devrait pas voir les baux de User B (got %)', row_count;
  END IF;
  RAISE NOTICE '[PASS] TEST 3 public: User A ne voit pas les baux de User B';
END $$;

-- ============================================================================
-- TEST 4 : User A ne voit PAS les baux de User B (dev)
-- ============================================================================
DO $$
DECLARE row_count integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0003-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  SELECT COUNT(*) INTO row_count FROM dev.leases
    WHERE landlord_id = '00000000-0000-0000-0003-000000000002';

  RESET ROLE;
  IF row_count <> 0 THEN
    RAISE EXCEPTION '[FAIL] TEST 4 dev: User A ne devrait pas voir les baux de User B (got %)', row_count;
  END IF;
  RAISE NOTICE '[PASS] TEST 4 dev: User A ne voit pas les baux de User B';
END $$;

-- ============================================================================
-- TEST 5 : User A ne peut PAS UPDATE un bail de User B (public)
-- ============================================================================
DO $$
DECLARE rows_updated integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0003-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  UPDATE public.leases SET rent_amount_cents = 1
    WHERE id = '00000000-0000-0000-0003-000000000060';
  GET DIAGNOSTICS rows_updated = ROW_COUNT;

  RESET ROLE;
  IF rows_updated <> 0 THEN
    RAISE EXCEPTION '[FAIL] TEST 5 public: User A ne devrait pas UPDATE le bail de User B (updated %)', rows_updated;
  END IF;
  RAISE NOTICE '[PASS] TEST 5 public: User A ne peut pas UPDATE le bail de User B';
END $$;

-- ============================================================================
-- TEST 6 : User A ne peut PAS UPDATE un bail de User B (dev)
-- ============================================================================
DO $$
DECLARE rows_updated integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0003-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  UPDATE dev.leases SET rent_amount_cents = 1
    WHERE id = '00000000-0000-0000-0003-000000000060';
  GET DIAGNOSTICS rows_updated = ROW_COUNT;

  RESET ROLE;
  IF rows_updated <> 0 THEN
    RAISE EXCEPTION '[FAIL] TEST 6 dev: User A ne devrait pas UPDATE le bail de User B (updated %)', rows_updated;
  END IF;
  RAISE NOTICE '[PASS] TEST 6 dev: User A ne peut pas UPDATE le bail de User B';
END $$;

-- ============================================================================
-- TEST 7 : INSERT valide avec landlord_id = auth.uid() réussit (public)
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0003-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    INSERT INTO public.leases (
      landlord_id, property_id, tenant_id, rent_amount_cents, start_date
    ) VALUES (
      '00000000-0000-0000-0003-000000000001',
      '00000000-0000-0000-0003-000000000010',
      '00000000-0000-0000-0003-000000000030',
      75000, '2026-06-01'
    );
    RESET ROLE;
    RAISE NOTICE '[PASS] TEST 7 public: INSERT valide avec son propre landlord_id réussit';
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 7 public: INSERT devrait réussir (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 8 : INSERT valide avec landlord_id = auth.uid() réussit (dev)
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0003-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    INSERT INTO dev.leases (
      landlord_id, property_id, tenant_id, rent_amount_cents, start_date
    ) VALUES (
      '00000000-0000-0000-0003-000000000001',
      '00000000-0000-0000-0003-000000000010',
      '00000000-0000-0000-0003-000000000030',
      75000, '2026-06-01'
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
    '{"sub":"00000000-0000-0000-0003-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    INSERT INTO public.leases (
      landlord_id, property_id, tenant_id, rent_amount_cents, start_date
    ) VALUES (
      '00000000-0000-0000-0003-000000000002',  -- landlord_id de User B
      '00000000-0000-0000-0003-000000000020',
      '00000000-0000-0000-0003-000000000040',
      50000, '2026-06-01'
    );
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 9 public: INSERT avec landlord_id étranger aurait dû être bloqué';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 9 public: INSERT avec landlord_id étranger refusé par RLS (42501)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 9 public: erreur inattendue (SQLSTATE %, msg: %) — vérifier policy INSERT',
        SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 10 : INSERT avec landlord_id d'un autre user échoue (42501 — dev)
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0003-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    INSERT INTO dev.leases (
      landlord_id, property_id, tenant_id, rent_amount_cents, start_date
    ) VALUES (
      '00000000-0000-0000-0003-000000000002',
      '00000000-0000-0000-0003-000000000020',
      '00000000-0000-0000-0003-000000000040',
      50000, '2026-06-01'
    );
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 10 dev: INSERT avec landlord_id étranger aurait dû être bloqué';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 10 dev: INSERT avec landlord_id étranger refusé par RLS (42501)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 10 dev: erreur inattendue (SQLSTATE %, msg: %) — vérifier policy INSERT',
        SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 11 : Bail soft-deleted invisible pour son propriétaire (public)
-- ============================================================================
DO $$
DECLARE row_count integer;
BEGIN
  PERFORM set_config('app.allow_deleted_at_change', '1', true);
  UPDATE public.leases SET deleted_at = now()
    WHERE id = '00000000-0000-0000-0003-000000000050';
  PERFORM set_config('app.allow_deleted_at_change', '0', true);

  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0003-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  SELECT COUNT(*) INTO row_count FROM public.leases
    WHERE id = '00000000-0000-0000-0003-000000000050';

  RESET ROLE;

  PERFORM set_config('app.allow_deleted_at_change', '1', true);
  UPDATE public.leases SET deleted_at = NULL
    WHERE id = '00000000-0000-0000-0003-000000000050';
  PERFORM set_config('app.allow_deleted_at_change', '0', true);

  IF row_count <> 0 THEN
    RAISE EXCEPTION '[FAIL] TEST 11 public: Bail soft-deleted devrait être invisible (got %)', row_count;
  END IF;
  RAISE NOTICE '[PASS] TEST 11 public: Bail soft-deleted invisible pour son propriétaire';
END $$;

-- ============================================================================
-- TEST 12 : Bail soft-deleted invisible pour son propriétaire (dev)
-- ============================================================================
DO $$
DECLARE row_count integer;
BEGIN
  PERFORM set_config('app.allow_deleted_at_change', '1', true);
  UPDATE dev.leases SET deleted_at = now()
    WHERE id = '00000000-0000-0000-0003-000000000050';
  PERFORM set_config('app.allow_deleted_at_change', '0', true);

  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0003-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  SELECT COUNT(*) INTO row_count FROM dev.leases
    WHERE id = '00000000-0000-0000-0003-000000000050';

  RESET ROLE;

  PERFORM set_config('app.allow_deleted_at_change', '1', true);
  UPDATE dev.leases SET deleted_at = NULL
    WHERE id = '00000000-0000-0000-0003-000000000050';
  PERFORM set_config('app.allow_deleted_at_change', '0', true);

  IF row_count <> 0 THEN
    RAISE EXCEPTION '[FAIL] TEST 12 dev: Bail soft-deleted devrait être invisible (got %)', row_count;
  END IF;
  RAISE NOTICE '[PASS] TEST 12 dev: Bail soft-deleted invisible pour son propriétaire';
END $$;

-- ============================================================================
-- TEST 13 : Trigger tr_01 — UPDATE direct de deleted_at refusé (public)
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0003-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    UPDATE public.leases SET deleted_at = now()
      WHERE id = '00000000-0000-0000-0003-000000000050';
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 13 public: UPDATE direct de deleted_at aurait dû être bloqué par trigger tr_01';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 13 public: UPDATE direct de deleted_at bloqué par trigger tr_01 (42501)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 13 public: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 14 : Trigger tr_01 — UPDATE direct de deleted_at refusé (dev)
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0003-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    UPDATE dev.leases SET deleted_at = now()
      WHERE id = '00000000-0000-0000-0003-000000000050';
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 14 dev: UPDATE direct de deleted_at aurait dû être bloqué par trigger tr_01';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 14 dev: UPDATE direct de deleted_at bloqué par trigger tr_01 (42501)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 14 dev: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 15 : RPC soft_delete_lease fonctionne (public)
-- ============================================================================
DO $$
DECLARE row_count integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0003-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  PERFORM public.soft_delete_lease('00000000-0000-0000-0003-000000000050');

  SELECT COUNT(*) INTO row_count FROM public.leases
    WHERE id = '00000000-0000-0000-0003-000000000050';

  RESET ROLE;

  IF (SELECT deleted_at FROM public.leases
        WHERE id = '00000000-0000-0000-0003-000000000050') IS NULL THEN
    RAISE EXCEPTION '[FAIL] TEST 15 public: La ligne devrait avoir deleted_at positionné';
  END IF;

  IF row_count <> 0 THEN
    RAISE EXCEPTION '[FAIL] TEST 15 public: Le bail soft-deleted devrait être invisible (got %)', row_count;
  END IF;
  RAISE NOTICE '[PASS] TEST 15 public: soft_delete_lease fonctionne — ligne invisible mais existante';

  PERFORM set_config('app.allow_deleted_at_change', '1', true);
  UPDATE public.leases SET deleted_at = NULL
    WHERE id = '00000000-0000-0000-0003-000000000050';
  PERFORM set_config('app.allow_deleted_at_change', '0', true);
END $$;

-- ============================================================================
-- TEST 16 : RPC soft_delete_lease fonctionne (dev)
-- ============================================================================
DO $$
DECLARE row_count integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0003-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  PERFORM dev.soft_delete_lease('00000000-0000-0000-0003-000000000050');

  SELECT COUNT(*) INTO row_count FROM dev.leases
    WHERE id = '00000000-0000-0000-0003-000000000050';

  RESET ROLE;

  IF (SELECT deleted_at FROM dev.leases
        WHERE id = '00000000-0000-0000-0003-000000000050') IS NULL THEN
    RAISE EXCEPTION '[FAIL] TEST 16 dev: La ligne devrait avoir deleted_at positionné';
  END IF;

  IF row_count <> 0 THEN
    RAISE EXCEPTION '[FAIL] TEST 16 dev: Le bail soft-deleted devrait être invisible (got %)', row_count;
  END IF;
  RAISE NOTICE '[PASS] TEST 16 dev: soft_delete_lease fonctionne — ligne invisible mais existante';

  PERFORM set_config('app.allow_deleted_at_change', '1', true);
  UPDATE dev.leases SET deleted_at = NULL
    WHERE id = '00000000-0000-0000-0003-000000000050';
  PERFORM set_config('app.allow_deleted_at_change', '0', true);
END $$;

-- ============================================================================
-- TEST 17 : RPC soft_delete_lease de User A sur bail de User B → NOT FOUND (public)
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0003-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    PERFORM public.soft_delete_lease('00000000-0000-0000-0003-000000000060');
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 17 public: La RPC aurait dû lever NOT FOUND pour un bail étranger';
  EXCEPTION
    WHEN no_data_found THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 17 public: soft_delete_lease sur bail étranger → NOT FOUND (P0002)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 17 public: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;

  IF (SELECT deleted_at FROM public.leases
        WHERE id = '00000000-0000-0000-0003-000000000060') IS NOT NULL THEN
    RAISE EXCEPTION '[FAIL] TEST 17 public: Le bail de User B ne devrait pas avoir été soft-deleted';
  END IF;
END $$;

-- ============================================================================
-- TEST 18 : RPC soft_delete_lease de User A sur bail de User B → NOT FOUND (dev)
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0003-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    PERFORM dev.soft_delete_lease('00000000-0000-0000-0003-000000000060');
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 18 dev: La RPC aurait dû lever NOT FOUND pour un bail étranger';
  EXCEPTION
    WHEN no_data_found THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 18 dev: soft_delete_lease sur bail étranger → NOT FOUND (P0002)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 18 dev: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;

  IF (SELECT deleted_at FROM dev.leases
        WHERE id = '00000000-0000-0000-0003-000000000060') IS NOT NULL THEN
    RAISE EXCEPTION '[FAIL] TEST 18 dev: Le bail de User B ne devrait pas avoir été soft-deleted';
  END IF;
END $$;

-- ============================================================================
-- TEST 19 : Trigger assert_lease_ownership_consistency — cross-ownership (public)
-- Scénario : on essaie en superuser d'insérer un bail dont property_id appartient
-- à User A mais tenant_id appartient à User B → le trigger doit rejeter (ERRCODE 23514).
-- ============================================================================
DO $$
BEGIN
  BEGIN
    INSERT INTO public.leases (
      landlord_id, property_id, tenant_id, rent_amount_cents, start_date
    ) VALUES (
      '00000000-0000-0000-0003-000000000001',  -- landlord = User A
      '00000000-0000-0000-0003-000000000010',  -- property de User A (OK)
      '00000000-0000-0000-0003-000000000040',  -- tenant de User B (INCOHÉRENT)
      65000, '2026-07-01'
    );
    RAISE EXCEPTION '[FAIL] TEST 19 public: Le trigger aurait dû rejeter le bail cross-ownership';
  EXCEPTION
    WHEN check_violation THEN
      -- SQLSTATE 23514 : levé par assert_lease_ownership_consistency()
      RAISE NOTICE '[PASS] TEST 19 public: Bail cross-ownership rejeté par trigger assert_lease_ownership_consistency (23514)';
    WHEN OTHERS THEN
      RAISE EXCEPTION '[FAIL] TEST 19 public: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 20 : Trigger assert_lease_ownership_consistency — cross-ownership (dev)
-- ============================================================================
DO $$
BEGIN
  BEGIN
    INSERT INTO dev.leases (
      landlord_id, property_id, tenant_id, rent_amount_cents, start_date
    ) VALUES (
      '00000000-0000-0000-0003-000000000001',
      '00000000-0000-0000-0003-000000000010',
      '00000000-0000-0000-0003-000000000040',  -- tenant de User B
      65000, '2026-07-01'
    );
    RAISE EXCEPTION '[FAIL] TEST 20 dev: Le trigger aurait dû rejeter le bail cross-ownership';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE '[PASS] TEST 20 dev: Bail cross-ownership rejeté par trigger assert_lease_ownership_consistency (23514)';
    WHEN OTHERS THEN
      RAISE EXCEPTION '[FAIL] TEST 20 dev: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 21 : CHECK end_date > start_date — end_date ≤ start_date refusé (public)
-- ============================================================================
DO $$
BEGIN
  BEGIN
    INSERT INTO public.leases (
      landlord_id, property_id, tenant_id, rent_amount_cents, start_date, end_date
    ) VALUES (
      '00000000-0000-0000-0003-000000000001',
      '00000000-0000-0000-0003-000000000010',
      '00000000-0000-0000-0003-000000000030',
      70000, '2026-06-01', '2026-06-01'  -- end_date = start_date : invalide
    );
    RAISE EXCEPTION '[FAIL] TEST 21 public: Le CHECK aurait dû rejeter end_date = start_date';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE '[PASS] TEST 21 public: end_date = start_date refusé par CHECK (23514)';
    WHEN OTHERS THEN
      RAISE EXCEPTION '[FAIL] TEST 21 public: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 22 : CHECK rent_amount_cents > 0 — montant négatif refusé (public)
-- ============================================================================
DO $$
BEGIN
  BEGIN
    INSERT INTO public.leases (
      landlord_id, property_id, tenant_id, rent_amount_cents, start_date
    ) VALUES (
      '00000000-0000-0000-0003-000000000001',
      '00000000-0000-0000-0003-000000000010',
      '00000000-0000-0000-0003-000000000030',
      -1, '2026-06-01'  -- montant négatif : invalide
    );
    RAISE EXCEPTION '[FAIL] TEST 22 public: Le CHECK aurait dû rejeter rent_amount_cents = -1';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE '[PASS] TEST 22 public: rent_amount_cents négatif refusé par CHECK (23514)';
    WHEN OTHERS THEN
      RAISE EXCEPTION '[FAIL] TEST 22 public: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 23 : RLS activée sur les deux schémas
-- ============================================================================
DO $$
BEGIN
  PERFORM dev.assert_rls_both_schemas('leases');
  RAISE NOTICE '[PASS] TEST 23: RLS activée sur public.leases ET dev.leases';
END $$;

-- ============================================================================
-- TEST 24 [F2] : INSERT avec deleted_at = now() refusé par trigger tr_01 (public)
-- Scénario : un client tente de créer un bail avec deleted_at positionné dès l'INSERT.
-- Note : le trigger tr_00_assert_lease_ownership s'exécute avant tr_01 (ordre alpha).
-- tr_00 valide la cohérence cross-FK, puis tr_01 bloque deleted_at = now().
-- Attendu : SQLSTATE 42501 (insufficient_privilege).
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0003-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    INSERT INTO public.leases (
      landlord_id, property_id, tenant_id, rent_amount_cents, start_date, deleted_at
    ) VALUES (
      '00000000-0000-0000-0003-000000000001',
      '00000000-0000-0000-0003-000000000010',
      '00000000-0000-0000-0003-000000000030',
      55000, '2026-08-01',
      now()  -- tentative de pré-soft-delete
    );
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 24 public: INSERT avec deleted_at aurait dû être bloqué par trigger tr_01 (F2)';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 24 public: INSERT avec deleted_at=now() refusé par trigger tr_01 (42501)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 24 public: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 25 [F2] : INSERT avec deleted_at = now() refusé par trigger tr_01 (dev)
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0003-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    INSERT INTO dev.leases (
      landlord_id, property_id, tenant_id, rent_amount_cents, start_date, deleted_at
    ) VALUES (
      '00000000-0000-0000-0003-000000000001',
      '00000000-0000-0000-0003-000000000010',
      '00000000-0000-0000-0003-000000000030',
      55000, '2026-08-01',
      now()
    );
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 25 dev: INSERT avec deleted_at aurait dû être bloqué par trigger tr_01 (F2)';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 25 dev: INSERT avec deleted_at=now() refusé par trigger tr_01 (42501)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 25 dev: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 26 [F2] : INSERT avec created_at antidaté → created_at forcé à now() (public)
-- Scénario : le client fournit '2020-01-01'::timestamptz comme created_at.
-- Attendu : la ligne est créée, created_at ≥ now() - interval '10 seconds'.
-- ============================================================================
DO $$
DECLARE
  inserted_created_at timestamptz;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0003-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    INSERT INTO public.leases (
      landlord_id, property_id, tenant_id, rent_amount_cents, start_date, created_at
    ) VALUES (
      '00000000-0000-0000-0003-000000000001',
      '00000000-0000-0000-0003-000000000010',
      '00000000-0000-0000-0003-000000000030',
      60000, '2026-09-01',
      '2020-01-01 00:00:00+00'::timestamptz  -- antidaté intentionnel
    )
    RETURNING created_at INTO inserted_created_at;

    RESET ROLE;

    IF inserted_created_at < (now() - interval '10 seconds') THEN
      RAISE EXCEPTION '[FAIL] TEST 26 public: created_at antidaté non corrigé (got %)', inserted_created_at;
    END IF;
    RAISE NOTICE '[PASS] TEST 26 public: created_at antidaté corrigé silencieusement à now() par trigger tr_01 (got %)', inserted_created_at;

  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 26 public: INSERT devrait réussir avec created_at corrigé (SQLSTATE %, msg: %)',
      SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 27 [F2] : INSERT avec created_at antidaté → created_at forcé à now() (dev)
-- ============================================================================
DO $$
DECLARE
  inserted_created_at timestamptz;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0003-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    INSERT INTO dev.leases (
      landlord_id, property_id, tenant_id, rent_amount_cents, start_date, created_at
    ) VALUES (
      '00000000-0000-0000-0003-000000000001',
      '00000000-0000-0000-0003-000000000010',
      '00000000-0000-0000-0003-000000000030',
      60000, '2026-09-01',
      '2020-01-01 00:00:00+00'::timestamptz
    )
    RETURNING created_at INTO inserted_created_at;

    RESET ROLE;

    IF inserted_created_at < (now() - interval '10 seconds') THEN
      RAISE EXCEPTION '[FAIL] TEST 27 dev: created_at antidaté non corrigé (got %)', inserted_created_at;
    END IF;
    RAISE NOTICE '[PASS] TEST 27 dev: created_at antidaté corrigé silencieusement à now() par trigger tr_01 (got %)', inserted_created_at;

  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 27 dev: INSERT devrait réussir avec created_at corrigé (SQLSTATE %, msg: %)',
      SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 28 [date-bounds] : start_date hors borne inférieure refusé (public)
-- Scénario : start_date='1850-01-01' est avant 1900-01-01 → CHECK leases_date_range_check
-- Attendu : SQLSTATE 23514 (check_violation).
-- ============================================================================
DO $$
BEGIN
  BEGIN
    INSERT INTO public.leases (
      landlord_id, property_id, tenant_id, rent_amount_cents, start_date
    ) VALUES (
      '00000000-0000-0000-0003-000000000001',
      '00000000-0000-0000-0003-000000000010',
      '00000000-0000-0000-0003-000000000030',
      70000, '1850-01-01'
    );
    RAISE EXCEPTION '[FAIL] TEST 28 public: start_date=''1850-01-01'' aurait dû être refusé par leases_date_range_check';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE '[PASS] TEST 28 public: start_date=''1850-01-01'' refusé par CHECK leases_date_range_check (23514)';
    WHEN OTHERS THEN
      RAISE EXCEPTION '[FAIL] TEST 28 public: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 29 [date-bounds] : start_date hors borne supérieure refusé (public)
-- Scénario : start_date='2200-01-01' est après 2100-12-31 → CHECK leases_date_range_check
-- Attendu : SQLSTATE 23514 (check_violation).
-- ============================================================================
DO $$
BEGIN
  BEGIN
    INSERT INTO public.leases (
      landlord_id, property_id, tenant_id, rent_amount_cents, start_date
    ) VALUES (
      '00000000-0000-0000-0003-000000000001',
      '00000000-0000-0000-0003-000000000010',
      '00000000-0000-0000-0003-000000000030',
      70000, '2200-01-01'
    );
    RAISE EXCEPTION '[FAIL] TEST 29 public: start_date=''2200-01-01'' aurait dû être refusé par leases_date_range_check';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE '[PASS] TEST 29 public: start_date=''2200-01-01'' refusé par CHECK leases_date_range_check (23514)';
    WHEN OTHERS THEN
      RAISE EXCEPTION '[FAIL] TEST 29 public: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 30 [date-bounds] : end_date='9999-12-31' refusé (public)
-- Scénario : end_date dépasse 2100-12-31 → CHECK leases_date_range_check
-- Note : end_date > start_date (CHECK FEAT-002) est satisfait ; seul le range check doit lever.
-- Attendu : SQLSTATE 23514 (check_violation).
-- ============================================================================
DO $$
BEGIN
  BEGIN
    INSERT INTO public.leases (
      landlord_id, property_id, tenant_id, rent_amount_cents, start_date, end_date
    ) VALUES (
      '00000000-0000-0000-0003-000000000001',
      '00000000-0000-0000-0003-000000000010',
      '00000000-0000-0000-0003-000000000030',
      70000, '2026-01-01', '9999-12-31'
    );
    RAISE EXCEPTION '[FAIL] TEST 30 public: end_date=''9999-12-31'' aurait dû être refusé par leases_date_range_check';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE '[PASS] TEST 30 public: end_date=''9999-12-31'' refusé par CHECK leases_date_range_check (23514)';
    WHEN OTHERS THEN
      RAISE EXCEPTION '[FAIL] TEST 30 public: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 31 [date-bounds] : bail valide start_date='2026-01-01', end_date=NULL accepté (régression — public)
-- Scénario : dates dans les bornes, end_date NULL (CDI locatif) — doit réussir.
-- Attendu : INSERT réussit (pas d'exception).
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0003-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    INSERT INTO public.leases (
      landlord_id, property_id, tenant_id, rent_amount_cents, start_date
    ) VALUES (
      '00000000-0000-0000-0003-000000000001',
      '00000000-0000-0000-0003-000000000010',
      '00000000-0000-0000-0003-000000000030',
      80000, '2026-01-01'
      -- end_date intentionnellement omis (NULL = CDI)
    );
    RESET ROLE;
    RAISE NOTICE '[PASS] TEST 31 public: bail valide (start_date=''2026-01-01'', end_date=NULL) accepté — régression OK';
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 31 public: bail valide refusé à tort (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- Teardown
-- ============================================================================
DELETE FROM public.leases WHERE landlord_id IN (
  '00000000-0000-0000-0003-000000000001',
  '00000000-0000-0000-0003-000000000002'
);
DELETE FROM dev.leases WHERE landlord_id IN (
  '00000000-0000-0000-0003-000000000001',
  '00000000-0000-0000-0003-000000000002'
);
DELETE FROM public.tenants WHERE landlord_id IN (
  '00000000-0000-0000-0003-000000000001',
  '00000000-0000-0000-0003-000000000002'
);
DELETE FROM dev.tenants WHERE landlord_id IN (
  '00000000-0000-0000-0003-000000000001',
  '00000000-0000-0000-0003-000000000002'
);
DELETE FROM public.properties WHERE landlord_id IN (
  '00000000-0000-0000-0003-000000000001',
  '00000000-0000-0000-0003-000000000002'
);
DELETE FROM dev.properties WHERE landlord_id IN (
  '00000000-0000-0000-0003-000000000001',
  '00000000-0000-0000-0003-000000000002'
);
DELETE FROM public.landlords WHERE id IN (
  '00000000-0000-0000-0003-000000000001',
  '00000000-0000-0000-0003-000000000002'
);
DELETE FROM dev.landlords WHERE id IN (
  '00000000-0000-0000-0003-000000000001',
  '00000000-0000-0000-0003-000000000002'
);
DELETE FROM auth.users WHERE id IN (
  '00000000-0000-0000-0003-000000000001',
  '00000000-0000-0000-0003-000000000002'
);

ROLLBACK;
