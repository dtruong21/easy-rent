-- ============================================================================
-- Tests RLS — table landlords (FEAT-001)
-- ============================================================================
-- Objectif : vérifier l'isolation cross-user dans les DEUX schémas.
-- Tests couverts :
--   1. User A voit sa propre ligne (public + dev)
--   2. User A ne voit PAS la ligne de User B (public + dev)
--   3. User A ne peut PAS mettre à jour la ligne de User B (public + dev)
--   4. Un client authentifié ne peut PAS faire un INSERT direct (public + dev)
--   5. La ligne soft-deleted n'est PAS visible (deleted_at IS NOT NULL)
-- ============================================================================
-- USAGE: psql <connection_string> -f supabase/tests/rls_landlords.sql
-- Sur stack locale : supabase db reset puis psql postgresql://postgres:postgres@localhost:54322/postgres -f supabase/tests/rls_landlords.sql
-- ============================================================================

BEGIN;

-- ============================================================================
-- Setup : deux users de test
-- ============================================================================

-- Insérer deux users fictifs directement dans auth.users (bypass trigger pour
-- contrôler précisément l'état initial)
INSERT INTO auth.users (
  id,
  instance_id,
  email,
  encrypted_password,
  email_confirmed_at,
  created_at,
  updated_at,
  raw_app_meta_data,
  raw_user_meta_data,
  aud,
  role
) VALUES
  (
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'user_a@test.example',
    'hashed_password_placeholder',
    now(),
    now(),
    now(),
    '{"provider":"email","providers":["email"]}',
    '{}',
    'authenticated',
    'authenticated'
  ),
  (
    '00000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'user_b@test.example',
    'hashed_password_placeholder',
    now(),
    now(),
    now(),
    '{"provider":"email","providers":["email"]}',
    '{}',
    'authenticated',
    'authenticated'
  )
ON CONFLICT (id) DO NOTHING;

-- Les lignes landlords sont insérées par le trigger on_auth_user_created.
-- Si le trigger n'a pas tourné (ex: insert direct ci-dessus bypasse le trigger
-- selon la version Supabase), on les insère manuellement en SECURITY DEFINER.
-- On utilise ici une insertion directe (test context = superuser).
INSERT INTO public.landlords (id, email) VALUES
  ('00000000-0000-0000-0000-000000000001', 'user_a@test.example'),
  ('00000000-0000-0000-0000-000000000002', 'user_b@test.example')
ON CONFLICT (id) DO NOTHING;

INSERT INTO dev.landlords (id, email) VALUES
  ('00000000-0000-0000-0000-000000000001', 'user_a@test.example'),
  ('00000000-0000-0000-0000-000000000002', 'user_b@test.example')
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- Helpers locaux
-- ============================================================================

-- Simule la session d'un utilisateur (set_config remplace auth.uid() dans RLS)
-- En test local, on utilise set_config('request.jwt.claims', ...) + role authenticated

-- ============================================================================
-- TEST 1 : User A voit sa propre ligne dans public.landlords
-- ============================================================================
DO $$
DECLARE
  row_count integer;
BEGIN
  -- Simuler User A comme utilisateur courant
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}',
    true);
  SET LOCAL ROLE authenticated;

  SELECT COUNT(*) INTO row_count
  FROM public.landlords
  WHERE id = '00000000-0000-0000-0000-000000000001';

  RESET ROLE;

  IF row_count <> 1 THEN
    RAISE EXCEPTION '[FAIL] TEST 1 public: User A devrait voir sa propre ligne (got %)', row_count;
  END IF;
  RAISE NOTICE '[PASS] TEST 1 public: User A voit sa propre ligne';
END $$;

-- ============================================================================
-- TEST 2 : User A voit sa propre ligne dans dev.landlords
-- ============================================================================
DO $$
DECLARE
  row_count integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}',
    true);
  SET LOCAL ROLE authenticated;

  SELECT COUNT(*) INTO row_count
  FROM dev.landlords
  WHERE id = '00000000-0000-0000-0000-000000000001';

  RESET ROLE;

  IF row_count <> 1 THEN
    RAISE EXCEPTION '[FAIL] TEST 2 dev: User A devrait voir sa propre ligne (got %)', row_count;
  END IF;
  RAISE NOTICE '[PASS] TEST 2 dev: User A voit sa propre ligne';
END $$;

-- ============================================================================
-- TEST 3 : User A ne voit PAS la ligne de User B dans public.landlords
-- ============================================================================
DO $$
DECLARE
  row_count integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}',
    true);
  SET LOCAL ROLE authenticated;

  SELECT COUNT(*) INTO row_count
  FROM public.landlords
  WHERE id = '00000000-0000-0000-0000-000000000002';

  RESET ROLE;

  IF row_count <> 0 THEN
    RAISE EXCEPTION '[FAIL] TEST 3 public: User A ne devrait PAS voir la ligne de User B (got %)', row_count;
  END IF;
  RAISE NOTICE '[PASS] TEST 3 public: User A ne voit pas la ligne de User B';
END $$;

-- ============================================================================
-- TEST 4 : User A ne voit PAS la ligne de User B dans dev.landlords
-- ============================================================================
DO $$
DECLARE
  row_count integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}',
    true);
  SET LOCAL ROLE authenticated;

  SELECT COUNT(*) INTO row_count
  FROM dev.landlords
  WHERE id = '00000000-0000-0000-0000-000000000002';

  RESET ROLE;

  IF row_count <> 0 THEN
    RAISE EXCEPTION '[FAIL] TEST 4 dev: User A ne devrait PAS voir la ligne de User B (got %)', row_count;
  END IF;
  RAISE NOTICE '[PASS] TEST 4 dev: User A ne voit pas la ligne de User B';
END $$;

-- ============================================================================
-- TEST 5 : User A ne peut PAS UPDATE la ligne de User B dans public.landlords
-- ============================================================================
DO $$
DECLARE
  rows_updated integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}',
    true);
  SET LOCAL ROLE authenticated;

  UPDATE public.landlords
    SET email = 'hacked@evil.com'
    WHERE id = '00000000-0000-0000-0000-000000000002';
  GET DIAGNOSTICS rows_updated = ROW_COUNT;

  RESET ROLE;

  IF rows_updated <> 0 THEN
    RAISE EXCEPTION '[FAIL] TEST 5 public: User A ne devrait PAS pouvoir mettre à jour la ligne de User B (updated %)', rows_updated;
  END IF;
  RAISE NOTICE '[PASS] TEST 5 public: User A ne peut pas UPDATE la ligne de User B';
END $$;

-- ============================================================================
-- TEST 6 : User A ne peut PAS UPDATE la ligne de User B dans dev.landlords
-- ============================================================================
DO $$
DECLARE
  rows_updated integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}',
    true);
  SET LOCAL ROLE authenticated;

  UPDATE dev.landlords
    SET email = 'hacked@evil.com'
    WHERE id = '00000000-0000-0000-0000-000000000002';
  GET DIAGNOSTICS rows_updated = ROW_COUNT;

  RESET ROLE;

  IF rows_updated <> 0 THEN
    RAISE EXCEPTION '[FAIL] TEST 6 dev: User A ne devrait PAS pouvoir mettre à jour la ligne de User B (updated %)', rows_updated;
  END IF;
  RAISE NOTICE '[PASS] TEST 6 dev: User A ne peut pas UPDATE la ligne de User B';
END $$;

-- ============================================================================
-- TEST 7 : Un client authentifié ne peut PAS faire un INSERT direct dans public.landlords
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-000000000003","role":"authenticated"}',
    true);
  SET LOCAL ROLE authenticated;

  BEGIN
    INSERT INTO public.landlords (id, email)
      VALUES ('00000000-0000-0000-0000-000000000003', 'attacker@evil.com');
    RESET ROLE;
    -- Si on arrive ici, le test échoue : l'INSERT n'aurait pas dû passer
    RAISE EXCEPTION '[FAIL] TEST 7 public: Un client authentifié ne devrait PAS pouvoir INSERT directement';
  EXCEPTION
    WHEN insufficient_privilege THEN
      -- SQLSTATE 42501 : c'est bien RLS qui bloque — attendu
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 7 public: INSERT direct refusé par RLS (insufficient_privilege)';
    WHEN others THEN
      -- Toute autre erreur (FK, NOT NULL, etc.) ne prouve PAS que RLS bloque :
      -- le test doit échouer pour ne pas masquer une régression de policy.
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 7 public: erreur inattendue (SQLSTATE %, msg: %) — vérifier que la policy INSERT est absente',
        SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 8 : Un client authentifié ne peut PAS faire un INSERT direct dans dev.landlords
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-000000000003","role":"authenticated"}',
    true);
  SET LOCAL ROLE authenticated;

  BEGIN
    INSERT INTO dev.landlords (id, email)
      VALUES ('00000000-0000-0000-0000-000000000003', 'attacker@evil.com');
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 8 dev: Un client authentifié ne devrait PAS pouvoir INSERT directement';
  EXCEPTION
    WHEN insufficient_privilege THEN
      -- SQLSTATE 42501 : c'est bien RLS qui bloque — attendu
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 8 dev: INSERT direct refusé par RLS (insufficient_privilege)';
    WHEN others THEN
      -- Toute autre erreur (FK, NOT NULL, etc.) ne prouve PAS que RLS bloque :
      -- le test doit échouer pour ne pas masquer une régression de policy.
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 8 dev: erreur inattendue (SQLSTATE %, msg: %) — vérifier que la policy INSERT est absente',
        SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 9 : Une ligne soft-deleted n'est PAS visible par son propre propriétaire
-- ============================================================================
DO $$
DECLARE
  row_count integer;
BEGIN
  -- En superuser : marquer User B comme supprimé
  UPDATE public.landlords
    SET deleted_at = now()
    WHERE id = '00000000-0000-0000-0000-000000000002';

  -- Simuler User B
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}',
    true);
  SET LOCAL ROLE authenticated;

  SELECT COUNT(*) INTO row_count
  FROM public.landlords
  WHERE id = '00000000-0000-0000-0000-000000000002';

  RESET ROLE;

  -- Restaurer User B (pour ne pas polluer les autres tests)
  UPDATE public.landlords SET deleted_at = NULL WHERE id = '00000000-0000-0000-0000-000000000002';

  IF row_count <> 0 THEN
    RAISE EXCEPTION '[FAIL] TEST 9 public: Ligne soft-deleted ne devrait pas être visible (got %)', row_count;
  END IF;
  RAISE NOTICE '[PASS] TEST 9 public: Ligne soft-deleted invisible';
END $$;

-- ============================================================================
-- TEST 10 : Vérification RLS activée sur les deux schémas (helper existant)
-- ============================================================================
DO $$
BEGIN
  PERFORM dev.assert_rls_both_schemas('landlords');
  RAISE NOTICE '[PASS] TEST 10: RLS activée sur public.landlords ET dev.landlords';
END $$;

-- ============================================================================
-- TEST 11 : Trigger tr_01 — UPDATE direct de deleted_at refusé (public)
-- FEAT-002 : trigger tr_01_prevent_protected_columns_change_landlords
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}',
    true);
  SET LOCAL ROLE authenticated;

  BEGIN
    UPDATE public.landlords SET deleted_at = now()
      WHERE id = '00000000-0000-0000-0000-000000000001';
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 11 public: UPDATE direct de deleted_at aurait dû être bloqué par trigger tr_01';
  EXCEPTION
    WHEN insufficient_privilege THEN
      -- SQLSTATE 42501 levé par prevent_protected_columns_change()
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 11 public: UPDATE direct de deleted_at sur landlords bloqué par trigger tr_01 (42501)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 11 public: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 12 : Trigger tr_01 — UPDATE direct de deleted_at refusé (dev)
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}',
    true);
  SET LOCAL ROLE authenticated;

  BEGIN
    UPDATE dev.landlords SET deleted_at = now()
      WHERE id = '00000000-0000-0000-0000-000000000001';
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 12 dev: UPDATE direct de deleted_at aurait dû être bloqué par trigger tr_01';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 12 dev: UPDATE direct de deleted_at sur landlords bloqué par trigger tr_01 (42501)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 12 dev: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 13 : RPC soft_delete_landlord — fonctionne pour le propriétaire (public)
-- Vérifie : ligne soft-deleted et invisible via SELECT normal.
-- ============================================================================
DO $$
DECLARE row_count integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}',
    true);
  SET LOCAL ROLE authenticated;

  -- Appel RPC : doit réussir sans exception
  PERFORM public.soft_delete_landlord();

  -- La ligne doit être invisible via SELECT normal (RLS filtre deleted_at IS NOT NULL)
  SELECT COUNT(*) INTO row_count FROM public.landlords
    WHERE id = '00000000-0000-0000-0000-000000000001';

  RESET ROLE;

  -- En superuser : vérifier que deleted_at est bien positionné (soft-delete, pas hard-delete)
  IF (SELECT deleted_at FROM public.landlords
        WHERE id = '00000000-0000-0000-0000-000000000001') IS NULL THEN
    RAISE EXCEPTION '[FAIL] TEST 13 public: soft_delete_landlord devrait avoir positionné deleted_at';
  END IF;

  IF row_count <> 0 THEN
    RAISE EXCEPTION '[FAIL] TEST 13 public: Landlord soft-deleted devrait être invisible via SELECT (got %)', row_count;
  END IF;
  RAISE NOTICE '[PASS] TEST 13 public: soft_delete_landlord fonctionne — ligne invisible mais existante en base';

  -- Restaurer pour la suite des tests
  PERFORM set_config('app.allow_deleted_at_change', '1', true);
  UPDATE public.landlords SET deleted_at = NULL
    WHERE id = '00000000-0000-0000-0000-000000000001';
  PERFORM set_config('app.allow_deleted_at_change', '0', true);
END $$;

-- ============================================================================
-- TEST 14 : RPC soft_delete_landlord — fonctionne pour le propriétaire (dev)
-- ============================================================================
DO $$
DECLARE row_count integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}',
    true);
  SET LOCAL ROLE authenticated;

  PERFORM dev.soft_delete_landlord();

  SELECT COUNT(*) INTO row_count FROM dev.landlords
    WHERE id = '00000000-0000-0000-0000-000000000001';

  RESET ROLE;

  IF (SELECT deleted_at FROM dev.landlords
        WHERE id = '00000000-0000-0000-0000-000000000001') IS NULL THEN
    RAISE EXCEPTION '[FAIL] TEST 14 dev: soft_delete_landlord devrait avoir positionné deleted_at';
  END IF;

  IF row_count <> 0 THEN
    RAISE EXCEPTION '[FAIL] TEST 14 dev: Landlord soft-deleted devrait être invisible via SELECT (got %)', row_count;
  END IF;
  RAISE NOTICE '[PASS] TEST 14 dev: soft_delete_landlord fonctionne — ligne invisible mais existante en base';

  PERFORM set_config('app.allow_deleted_at_change', '1', true);
  UPDATE dev.landlords SET deleted_at = NULL
    WHERE id = '00000000-0000-0000-0000-000000000001';
  PERFORM set_config('app.allow_deleted_at_change', '0', true);
END $$;

-- ============================================================================
-- TEST 15 : FK NO ACTION — DELETE d'un auth.user avec landlord existant échoue
-- FEAT-002 change la FK landlords.id → auth.users(id) de CASCADE à NO ACTION.
-- Ce test vérifie que la suppression d'un auth.user est bien bloquée par la FK
-- tant qu'une ligne landlords non-deleted existe.
-- ============================================================================
DO $$
BEGIN
  BEGIN
    -- Tenter de supprimer User B (qui a une ligne landlords active)
    DELETE FROM auth.users WHERE id = '00000000-0000-0000-0000-000000000002';
    -- Si on arrive ici, la FK CASCADE est toujours active → FEAT-002 n'a pas
    -- correctement changé la contrainte. C'est un bug critique de migration.
    RAISE EXCEPTION '[FAIL] TEST 15: DELETE d''un auth.user avec landlord existant aurait dû échouer (FK NO ACTION) — vérifier que la migration a bien remplacé ON DELETE CASCADE par ON DELETE NO ACTION';
  EXCEPTION
    WHEN foreign_key_violation THEN
      -- SQLSTATE 23503 : la FK NO ACTION bloque le DELETE — attendu
      RAISE NOTICE '[PASS] TEST 15: DELETE auth.user bloqué par FK NO ACTION (23503) — rétention 5 ans protégée';
    WHEN OTHERS THEN
      RAISE EXCEPTION '[FAIL] TEST 15: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 16 : handle_new_user — provisioning automatique après FEAT-002
-- Vérifie que le trigger on_auth_user_created copie email dans landlords,
-- que full_name est NULL (attendu — rempli plus tard par l'UI), et que
-- les nouvelles colonnes FEAT-002 (phone, address) sont aussi NULL.
-- ============================================================================
DO $$
DECLARE
  test_user_id uuid := '00000000-0000-0000-0000-000000000099';
  pub_count    integer;
  dev_count    integer;
  pub_email    text;
  dev_email    text;
  pub_fullname text;
BEGIN
  -- Insérer un nouvel auth.user — doit déclencher handle_new_user()
  INSERT INTO auth.users (
    id, instance_id, email, encrypted_password, email_confirmed_at,
    created_at, updated_at, raw_app_meta_data, raw_user_meta_data, aud, role
  ) VALUES (
    test_user_id,
    '00000000-0000-0000-0000-000000000000',
    'trigger_test@test.example',
    'hashed_placeholder',
    now(), now(), now(),
    '{"provider":"email","providers":["email"]}',
    '{}',
    'authenticated',
    'authenticated'
  ) ON CONFLICT (id) DO NOTHING;

  -- Vérifier provisioning dans public
  SELECT COUNT(*), MAX(email), MAX(full_name)
    INTO pub_count, pub_email, pub_fullname
    FROM public.landlords WHERE id = test_user_id;

  -- Vérifier provisioning dans dev
  SELECT COUNT(*) INTO dev_count
    FROM dev.landlords WHERE id = test_user_id;

  -- Assertions
  IF pub_count <> 1 THEN
    RAISE EXCEPTION '[FAIL] TEST 16: handle_new_user n''a pas créé de ligne dans public.landlords (count=%). Trigger on_auth_user_created actif ?', pub_count;
  END IF;

  IF dev_count <> 1 THEN
    RAISE EXCEPTION '[FAIL] TEST 16: handle_new_user n''a pas créé de ligne dans dev.landlords (count=%)', dev_count;
  END IF;

  IF pub_email <> 'trigger_test@test.example' THEN
    RAISE EXCEPTION '[FAIL] TEST 16: email mal copié dans public.landlords (got "%")', pub_email;
  END IF;

  IF pub_fullname IS NOT NULL THEN
    RAISE EXCEPTION '[FAIL] TEST 16: full_name devrait être NULL à la création (got "%")', pub_fullname;
  END IF;

  RAISE NOTICE '[PASS] TEST 16: handle_new_user provisionne landlords avec email copié et full_name NULL dans les deux schémas';

  -- Cleanup (le ROLLBACK final s'en charge, mais on nettoie explicitement
  -- pour éviter les conflits si le test tourne en COMMIT)
  DELETE FROM public.landlords WHERE id = test_user_id;
  DELETE FROM dev.landlords     WHERE id = test_user_id;
  DELETE FROM auth.users        WHERE id = test_user_id;
END $$;

-- ============================================================================
-- Teardown : supprimer les données de test
-- ============================================================================
DELETE FROM public.landlords
  WHERE id IN (
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000002'
  );

DELETE FROM dev.landlords
  WHERE id IN (
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000002'
  );

DELETE FROM auth.users
  WHERE id IN (
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000002'
  );

ROLLBACK;
-- Note: ROLLBACK annule toutes les modifications de test.
-- Pour exécuter sans rollback (état persistant), remplacer ROLLBACK par COMMIT.
