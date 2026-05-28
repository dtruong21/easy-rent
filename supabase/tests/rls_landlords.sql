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
