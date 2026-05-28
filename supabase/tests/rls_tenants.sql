-- ============================================================================
-- Tests RLS — table tenants (FEAT-002)
-- ============================================================================
-- Tests couverts :
--   1.  User A voit ses propres tenants (public)
--   2.  User A voit ses propres tenants (dev)
--   3.  User A ne voit PAS les tenants de User B (public)
--   4.  User A ne voit PAS les tenants de User B (dev)
--   5.  User A ne peut PAS UPDATE un tenant de User B (public)
--   6.  User A ne peut PAS UPDATE un tenant de User B (dev)
--   7.  INSERT avec landlord_id = auth.uid() réussit (public)
--   8.  INSERT avec landlord_id = auth.uid() réussit (dev)
--   9.  INSERT avec landlord_id d'un autre user échoue (42501 — public)
--   10. INSERT avec landlord_id d'un autre user échoue (42501 — dev)
--   11. Tenant soft-deleted invisible pour son propriétaire (public)
--   12. Tenant soft-deleted invisible pour son propriétaire (dev)
--   13. Trigger tr_01 : UPDATE direct de deleted_at refusé (42501 — public)
--   14. Trigger tr_01 : UPDATE direct de deleted_at refusé (42501 — dev)
--   15. RPC soft_delete_tenant fonctionne — ligne invisible mais existante (public)
--   16. RPC soft_delete_tenant fonctionne — ligne invisible mais existante (dev)
--   17. RPC soft_delete_tenant de User A sur tenant de User B → NOT FOUND (public)
--   18. RPC soft_delete_tenant de User A sur tenant de User B → NOT FOUND (dev)
--   19. RLS activée sur les deux schémas (assert_rls_both_schemas)
-- [F2] 20. INSERT avec deleted_at = now() refusé par trigger tr_01 (SQLSTATE 42501 — public)
-- [F2] 21. INSERT avec deleted_at = now() refusé par trigger tr_01 (SQLSTATE 42501 — dev)
-- [F2] 22. INSERT avec created_at antidaté : created_at corrigé silencieusement à now() (public)
-- [F2] 23. INSERT avec created_at antidaté : created_at corrigé silencieusement à now() (dev)
-- ============================================================================
-- USAGE: psql <connection_string> -f supabase/tests/rls_tenants.sql
-- ============================================================================

BEGIN;

-- ============================================================================
-- Setup
-- ============================================================================

INSERT INTO auth.users (
  id, instance_id, email, encrypted_password, email_confirmed_at,
  created_at, updated_at, raw_app_meta_data, raw_user_meta_data, aud, role
) VALUES
  ('00000000-0000-0000-0002-000000000001', '00000000-0000-0000-0000-000000000000',
   'ten_user_a@test.example', 'hashed', now(), now(), now(),
   '{"provider":"email","providers":["email"]}', '{}', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0002-000000000002', '00000000-0000-0000-0000-000000000000',
   'ten_user_b@test.example', 'hashed', now(), now(), now(),
   '{"provider":"email","providers":["email"]}', '{}', 'authenticated', 'authenticated')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.landlords (id, email) VALUES
  ('00000000-0000-0000-0002-000000000001', 'ten_user_a@test.example'),
  ('00000000-0000-0000-0002-000000000002', 'ten_user_b@test.example')
ON CONFLICT (id) DO NOTHING;

INSERT INTO dev.landlords (id, email) VALUES
  ('00000000-0000-0000-0002-000000000001', 'ten_user_a@test.example'),
  ('00000000-0000-0000-0002-000000000002', 'ten_user_b@test.example')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.tenants (id, landlord_id, first_name, last_name, email) VALUES
  ('00000000-0000-0000-0002-000000000010', '00000000-0000-0000-0002-000000000001',
   'Alice', 'Locataire', 'alice@locataire.example'),
  ('00000000-0000-0000-0002-000000000020', '00000000-0000-0000-0002-000000000002',
   'Bob', 'Locataire', 'bob@locataire.example');

INSERT INTO dev.tenants (id, landlord_id, first_name, last_name, email) VALUES
  ('00000000-0000-0000-0002-000000000010', '00000000-0000-0000-0002-000000000001',
   'Alice', 'Locataire', 'alice@locataire.example'),
  ('00000000-0000-0000-0002-000000000020', '00000000-0000-0000-0002-000000000002',
   'Bob', 'Locataire', 'bob@locataire.example');

-- ============================================================================
-- TEST 1 : User A voit ses propres tenants (public)
-- ============================================================================
DO $$
DECLARE row_count integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0002-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  SELECT COUNT(*) INTO row_count FROM public.tenants
    WHERE landlord_id = '00000000-0000-0000-0002-000000000001';

  RESET ROLE;
  IF row_count <> 1 THEN
    RAISE EXCEPTION '[FAIL] TEST 1 public: User A devrait voir 1 tenant (got %)', row_count;
  END IF;
  RAISE NOTICE '[PASS] TEST 1 public: User A voit ses propres tenants';
END $$;

-- ============================================================================
-- TEST 2 : User A voit ses propres tenants (dev)
-- ============================================================================
DO $$
DECLARE row_count integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0002-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  SELECT COUNT(*) INTO row_count FROM dev.tenants
    WHERE landlord_id = '00000000-0000-0000-0002-000000000001';

  RESET ROLE;
  IF row_count <> 1 THEN
    RAISE EXCEPTION '[FAIL] TEST 2 dev: User A devrait voir 1 tenant (got %)', row_count;
  END IF;
  RAISE NOTICE '[PASS] TEST 2 dev: User A voit ses propres tenants';
END $$;

-- ============================================================================
-- TEST 3 : User A ne voit PAS les tenants de User B (public)
-- ============================================================================
DO $$
DECLARE row_count integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0002-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  SELECT COUNT(*) INTO row_count FROM public.tenants
    WHERE landlord_id = '00000000-0000-0000-0002-000000000002';

  RESET ROLE;
  IF row_count <> 0 THEN
    RAISE EXCEPTION '[FAIL] TEST 3 public: User A ne devrait pas voir les tenants de User B (got %)', row_count;
  END IF;
  RAISE NOTICE '[PASS] TEST 3 public: User A ne voit pas les tenants de User B';
END $$;

-- ============================================================================
-- TEST 4 : User A ne voit PAS les tenants de User B (dev)
-- ============================================================================
DO $$
DECLARE row_count integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0002-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  SELECT COUNT(*) INTO row_count FROM dev.tenants
    WHERE landlord_id = '00000000-0000-0000-0002-000000000002';

  RESET ROLE;
  IF row_count <> 0 THEN
    RAISE EXCEPTION '[FAIL] TEST 4 dev: User A ne devrait pas voir les tenants de User B (got %)', row_count;
  END IF;
  RAISE NOTICE '[PASS] TEST 4 dev: User A ne voit pas les tenants de User B';
END $$;

-- ============================================================================
-- TEST 5 : User A ne peut PAS UPDATE un tenant de User B (public)
-- ============================================================================
DO $$
DECLARE rows_updated integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0002-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  UPDATE public.tenants SET first_name = 'Hacked'
    WHERE id = '00000000-0000-0000-0002-000000000020';
  GET DIAGNOSTICS rows_updated = ROW_COUNT;

  RESET ROLE;
  IF rows_updated <> 0 THEN
    RAISE EXCEPTION '[FAIL] TEST 5 public: User A ne devrait pas UPDATE le tenant de User B (updated %)', rows_updated;
  END IF;
  RAISE NOTICE '[PASS] TEST 5 public: User A ne peut pas UPDATE le tenant de User B';
END $$;

-- ============================================================================
-- TEST 6 : User A ne peut PAS UPDATE un tenant de User B (dev)
-- ============================================================================
DO $$
DECLARE rows_updated integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0002-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  UPDATE dev.tenants SET first_name = 'Hacked'
    WHERE id = '00000000-0000-0000-0002-000000000020';
  GET DIAGNOSTICS rows_updated = ROW_COUNT;

  RESET ROLE;
  IF rows_updated <> 0 THEN
    RAISE EXCEPTION '[FAIL] TEST 6 dev: User A ne devrait pas UPDATE le tenant de User B (updated %)', rows_updated;
  END IF;
  RAISE NOTICE '[PASS] TEST 6 dev: User A ne peut pas UPDATE le tenant de User B';
END $$;

-- ============================================================================
-- TEST 7 : INSERT avec landlord_id = auth.uid() réussit (public)
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0002-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    INSERT INTO public.tenants (landlord_id, first_name, last_name, email)
      VALUES ('00000000-0000-0000-0002-000000000001', 'Charlie', 'Test', 'charlie@test.example');
    RESET ROLE;
    RAISE NOTICE '[PASS] TEST 7 public: INSERT avec son propre landlord_id réussit';
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
    '{"sub":"00000000-0000-0000-0002-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    INSERT INTO dev.tenants (landlord_id, first_name, last_name, email)
      VALUES ('00000000-0000-0000-0002-000000000001', 'Charlie DEV', 'Test', 'charlie.dev@test.example');
    RESET ROLE;
    RAISE NOTICE '[PASS] TEST 8 dev: INSERT avec son propre landlord_id réussit';
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
    '{"sub":"00000000-0000-0000-0002-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    INSERT INTO public.tenants (landlord_id, first_name, last_name, email)
      VALUES ('00000000-0000-0000-0002-000000000002', 'Evil', 'Inject', 'evil@inject.example');
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
    '{"sub":"00000000-0000-0000-0002-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    INSERT INTO dev.tenants (landlord_id, first_name, last_name, email)
      VALUES ('00000000-0000-0000-0002-000000000002', 'Evil DEV', 'Inject', 'evil.dev@inject.example');
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
-- TEST 11 : Tenant soft-deleted invisible pour son propriétaire (public)
-- ============================================================================
DO $$
DECLARE row_count integer;
BEGIN
  PERFORM set_config('app.allow_deleted_at_change', '1', true);
  UPDATE public.tenants SET deleted_at = now()
    WHERE id = '00000000-0000-0000-0002-000000000010';
  PERFORM set_config('app.allow_deleted_at_change', '0', true);

  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0002-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  SELECT COUNT(*) INTO row_count FROM public.tenants
    WHERE id = '00000000-0000-0000-0002-000000000010';

  RESET ROLE;

  PERFORM set_config('app.allow_deleted_at_change', '1', true);
  UPDATE public.tenants SET deleted_at = NULL
    WHERE id = '00000000-0000-0000-0002-000000000010';
  PERFORM set_config('app.allow_deleted_at_change', '0', true);

  IF row_count <> 0 THEN
    RAISE EXCEPTION '[FAIL] TEST 11 public: Tenant soft-deleted devrait être invisible (got %)', row_count;
  END IF;
  RAISE NOTICE '[PASS] TEST 11 public: Tenant soft-deleted invisible pour son propriétaire';
END $$;

-- ============================================================================
-- TEST 12 : Tenant soft-deleted invisible pour son propriétaire (dev)
-- ============================================================================
DO $$
DECLARE row_count integer;
BEGIN
  PERFORM set_config('app.allow_deleted_at_change', '1', true);
  UPDATE dev.tenants SET deleted_at = now()
    WHERE id = '00000000-0000-0000-0002-000000000010';
  PERFORM set_config('app.allow_deleted_at_change', '0', true);

  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0002-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  SELECT COUNT(*) INTO row_count FROM dev.tenants
    WHERE id = '00000000-0000-0000-0002-000000000010';

  RESET ROLE;

  PERFORM set_config('app.allow_deleted_at_change', '1', true);
  UPDATE dev.tenants SET deleted_at = NULL
    WHERE id = '00000000-0000-0000-0002-000000000010';
  PERFORM set_config('app.allow_deleted_at_change', '0', true);

  IF row_count <> 0 THEN
    RAISE EXCEPTION '[FAIL] TEST 12 dev: Tenant soft-deleted devrait être invisible (got %)', row_count;
  END IF;
  RAISE NOTICE '[PASS] TEST 12 dev: Tenant soft-deleted invisible pour son propriétaire';
END $$;

-- ============================================================================
-- TEST 13 : Trigger tr_01 — UPDATE direct de deleted_at refusé (public)
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0002-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    UPDATE public.tenants SET deleted_at = now()
      WHERE id = '00000000-0000-0000-0002-000000000010';
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
    '{"sub":"00000000-0000-0000-0002-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    UPDATE dev.tenants SET deleted_at = now()
      WHERE id = '00000000-0000-0000-0002-000000000010';
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
-- TEST 15 : RPC soft_delete_tenant fonctionne (public)
-- ============================================================================
DO $$
DECLARE row_count integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0002-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  PERFORM public.soft_delete_tenant('00000000-0000-0000-0002-000000000010');

  SELECT COUNT(*) INTO row_count FROM public.tenants
    WHERE id = '00000000-0000-0000-0002-000000000010';

  RESET ROLE;

  IF (SELECT deleted_at FROM public.tenants
        WHERE id = '00000000-0000-0000-0002-000000000010') IS NULL THEN
    RAISE EXCEPTION '[FAIL] TEST 15 public: La ligne devrait avoir deleted_at positionné';
  END IF;

  IF row_count <> 0 THEN
    RAISE EXCEPTION '[FAIL] TEST 15 public: Le tenant soft-deleted devrait être invisible via SELECT (got %)', row_count;
  END IF;
  RAISE NOTICE '[PASS] TEST 15 public: soft_delete_tenant fonctionne — ligne invisible mais existante';

  PERFORM set_config('app.allow_deleted_at_change', '1', true);
  UPDATE public.tenants SET deleted_at = NULL
    WHERE id = '00000000-0000-0000-0002-000000000010';
  PERFORM set_config('app.allow_deleted_at_change', '0', true);
END $$;

-- ============================================================================
-- TEST 16 : RPC soft_delete_tenant fonctionne (dev)
-- ============================================================================
DO $$
DECLARE row_count integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0002-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  PERFORM dev.soft_delete_tenant('00000000-0000-0000-0002-000000000010');

  SELECT COUNT(*) INTO row_count FROM dev.tenants
    WHERE id = '00000000-0000-0000-0002-000000000010';

  RESET ROLE;

  IF (SELECT deleted_at FROM dev.tenants
        WHERE id = '00000000-0000-0000-0002-000000000010') IS NULL THEN
    RAISE EXCEPTION '[FAIL] TEST 16 dev: La ligne devrait avoir deleted_at positionné';
  END IF;

  IF row_count <> 0 THEN
    RAISE EXCEPTION '[FAIL] TEST 16 dev: Le tenant soft-deleted devrait être invisible via SELECT (got %)', row_count;
  END IF;
  RAISE NOTICE '[PASS] TEST 16 dev: soft_delete_tenant fonctionne — ligne invisible mais existante';

  PERFORM set_config('app.allow_deleted_at_change', '1', true);
  UPDATE dev.tenants SET deleted_at = NULL
    WHERE id = '00000000-0000-0000-0002-000000000010';
  PERFORM set_config('app.allow_deleted_at_change', '0', true);
END $$;

-- ============================================================================
-- TEST 17 : RPC soft_delete_tenant de User A sur tenant de User B → NOT FOUND (public)
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0002-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    PERFORM public.soft_delete_tenant('00000000-0000-0000-0002-000000000020');
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 17 public: La RPC aurait dû lever NOT FOUND pour un tenant étranger';
  EXCEPTION
    WHEN no_data_found THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 17 public: soft_delete_tenant sur tenant étranger → NOT FOUND (P0002)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 17 public: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;

  IF (SELECT deleted_at FROM public.tenants
        WHERE id = '00000000-0000-0000-0002-000000000020') IS NOT NULL THEN
    RAISE EXCEPTION '[FAIL] TEST 17 public: Le tenant de User B ne devrait pas avoir été soft-deleted';
  END IF;
END $$;

-- ============================================================================
-- TEST 18 : RPC soft_delete_tenant de User A sur tenant de User B → NOT FOUND (dev)
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0002-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    PERFORM dev.soft_delete_tenant('00000000-0000-0000-0002-000000000020');
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 18 dev: La RPC aurait dû lever NOT FOUND pour un tenant étranger';
  EXCEPTION
    WHEN no_data_found THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 18 dev: soft_delete_tenant sur tenant étranger → NOT FOUND (P0002)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 18 dev: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;

  IF (SELECT deleted_at FROM dev.tenants
        WHERE id = '00000000-0000-0000-0002-000000000020') IS NOT NULL THEN
    RAISE EXCEPTION '[FAIL] TEST 18 dev: Le tenant de User B ne devrait pas avoir été soft-deleted';
  END IF;
END $$;

-- ============================================================================
-- TEST 19 : RLS activée sur les deux schémas
-- ============================================================================
DO $$
BEGIN
  PERFORM dev.assert_rls_both_schemas('tenants');
  RAISE NOTICE '[PASS] TEST 19: RLS activée sur public.tenants ET dev.tenants';
END $$;

-- ============================================================================
-- TEST 20 [F2] : INSERT avec deleted_at = now() refusé par trigger tr_01 (public)
-- Scénario : un client tente de créer un tenant avec deleted_at positionné dès l'INSERT.
-- Attendu : SQLSTATE 42501 levé par prevent_protected_columns_change (branche INSERT).
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0002-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    INSERT INTO public.tenants (landlord_id, first_name, last_name, email, deleted_at)
      VALUES (
        '00000000-0000-0000-0002-000000000001',
        'Ghost', 'Tenant', 'ghost@tenant.example',
        now()  -- tentative de pré-soft-delete dès l'INSERT
      );
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 20 public: INSERT avec deleted_at aurait dû être bloqué par trigger tr_01 (F2)';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 20 public: INSERT avec deleted_at=now() refusé par trigger tr_01 (42501)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 20 public: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 21 [F2] : INSERT avec deleted_at = now() refusé par trigger tr_01 (dev)
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0002-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    INSERT INTO dev.tenants (landlord_id, first_name, last_name, email, deleted_at)
      VALUES (
        '00000000-0000-0000-0002-000000000001',
        'Ghost DEV', 'Tenant', 'ghost.dev@tenant.example',
        now()
      );
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 21 dev: INSERT avec deleted_at aurait dû être bloqué par trigger tr_01 (F2)';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 21 dev: INSERT avec deleted_at=now() refusé par trigger tr_01 (42501)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 21 dev: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 22 [F2] : INSERT avec created_at antidaté → created_at forcé à now() (public)
-- Scénario : le client fournit '2020-01-01'::timestamptz comme created_at.
-- Attendu : la ligne est créée, created_at ≥ now() - interval '10 seconds'.
-- ============================================================================
DO $$
DECLARE
  inserted_created_at timestamptz;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0002-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    INSERT INTO public.tenants (landlord_id, first_name, last_name, email, created_at)
      VALUES (
        '00000000-0000-0000-0002-000000000001',
        'Backdated', 'Tenant', 'backdated@tenant.example',
        '2020-01-01 00:00:00+00'::timestamptz
      )
      RETURNING created_at INTO inserted_created_at;

    RESET ROLE;

    IF inserted_created_at < (now() - interval '10 seconds') THEN
      RAISE EXCEPTION '[FAIL] TEST 22 public: created_at antidaté non corrigé (got %)', inserted_created_at;
    END IF;
    RAISE NOTICE '[PASS] TEST 22 public: created_at antidaté corrigé silencieusement à now() par trigger tr_01 (got %)', inserted_created_at;

  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 22 public: INSERT devrait réussir avec created_at corrigé (SQLSTATE %, msg: %)',
      SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 23 [F2] : INSERT avec created_at antidaté → created_at forcé à now() (dev)
-- ============================================================================
DO $$
DECLARE
  inserted_created_at timestamptz;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0002-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    INSERT INTO dev.tenants (landlord_id, first_name, last_name, email, created_at)
      VALUES (
        '00000000-0000-0000-0002-000000000001',
        'Backdated DEV', 'Tenant', 'backdated.dev@tenant.example',
        '2020-01-01 00:00:00+00'::timestamptz
      )
      RETURNING created_at INTO inserted_created_at;

    RESET ROLE;

    IF inserted_created_at < (now() - interval '10 seconds') THEN
      RAISE EXCEPTION '[FAIL] TEST 23 dev: created_at antidaté non corrigé (got %)', inserted_created_at;
    END IF;
    RAISE NOTICE '[PASS] TEST 23 dev: created_at antidaté corrigé silencieusement à now() par trigger tr_01 (got %)', inserted_created_at;

  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 23 dev: INSERT devrait réussir avec created_at corrigé (SQLSTATE %, msg: %)',
      SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- Teardown
-- ============================================================================
DELETE FROM public.tenants WHERE landlord_id IN (
  '00000000-0000-0000-0002-000000000001',
  '00000000-0000-0000-0002-000000000002'
);
DELETE FROM dev.tenants WHERE landlord_id IN (
  '00000000-0000-0000-0002-000000000001',
  '00000000-0000-0000-0002-000000000002'
);
DELETE FROM public.landlords WHERE id IN (
  '00000000-0000-0000-0002-000000000001',
  '00000000-0000-0000-0002-000000000002'
);
DELETE FROM dev.landlords WHERE id IN (
  '00000000-0000-0000-0002-000000000001',
  '00000000-0000-0000-0002-000000000002'
);
DELETE FROM auth.users WHERE id IN (
  '00000000-0000-0000-0002-000000000001',
  '00000000-0000-0000-0002-000000000002'
);

ROLLBACK;
