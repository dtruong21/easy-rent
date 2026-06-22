-- ============================================================================
-- Tests smoke — handle_new_user() FEAT-011 (full_name depuis raw_user_meta_data)
-- ============================================================================
-- Objectif : vérifier que le trigger on_auth_user_created lit bien full_name
-- depuis raw_user_meta_data et applique le fallback email si absent.
--
-- Tests couverts :
--   1. Signup avec full_name fourni → landlords.full_name = valeur fournie (public + dev)
--   2. Signup sans full_name (raw_user_meta_data = '{}') → fallback = email (public + dev)
--   3. Signup avec full_name vide/espace → fallback = email (public + dev)
--   4. Signup depuis admin (raw_user_meta_data = NULL) → fallback = email (public + dev)
-- ============================================================================
-- USAGE: psql <connection_string> -f supabase/tests/auth_password_signup_smoke.sql
-- Stack locale : supabase db reset puis :
--   psql postgresql://postgres:postgres@localhost:54322/postgres \
--        -f supabase/tests/auth_password_signup_smoke.sql
-- ============================================================================

BEGIN;

-- ============================================================================
-- TEST 1 : Signup avec full_name fourni dans raw_user_meta_data
-- ============================================================================
DO $$
DECLARE
  v_user_id  uuid    := 'f0000011-0000-0000-0000-000000000001';
  v_pub_name text;
  v_dev_name text;
  v_pub_email text;
BEGIN
  INSERT INTO auth.users (
    id, instance_id, email, encrypted_password, email_confirmed_at,
    created_at, updated_at, raw_app_meta_data, raw_user_meta_data, aud, role
  ) VALUES (
    v_user_id,
    '00000000-0000-0000-0000-000000000000',
    'alice@example.com',
    'hashed_placeholder',
    now(), now(), now(),
    '{"provider":"email","providers":["email"]}',
    '{"full_name":"Alice Dupont"}',    -- full_name fourni au signup
    'authenticated',
    'authenticated'
  ) ON CONFLICT (id) DO NOTHING;

  SELECT full_name, email INTO v_pub_name, v_pub_email
    FROM public.landlords WHERE id = v_user_id;

  SELECT full_name INTO v_dev_name
    FROM dev.landlords WHERE id = v_user_id;

  IF v_pub_name IS DISTINCT FROM 'Alice Dupont' THEN
    RAISE EXCEPTION '[FAIL] TEST 1 public: full_name attendu "Alice Dupont", obtenu "%"', v_pub_name;
  END IF;

  IF v_dev_name IS DISTINCT FROM 'Alice Dupont' THEN
    RAISE EXCEPTION '[FAIL] TEST 1 dev: full_name attendu "Alice Dupont", obtenu "%"', v_dev_name;
  END IF;

  IF v_pub_email IS DISTINCT FROM 'alice@example.com' THEN
    RAISE EXCEPTION '[FAIL] TEST 1 public: email attendu "alice@example.com", obtenu "%"', v_pub_email;
  END IF;

  RAISE NOTICE '[PASS] TEST 1: full_name lu depuis raw_user_meta_data dans les deux schémas (public="%", dev="%")',
    v_pub_name, v_dev_name;
END $$;

-- ============================================================================
-- TEST 2 : Signup sans full_name (raw_user_meta_data = '{}') → fallback email
-- ============================================================================
DO $$
DECLARE
  v_user_id  uuid := 'f0000011-0000-0000-0000-000000000002';
  v_pub_name text;
  v_dev_name text;
BEGIN
  INSERT INTO auth.users (
    id, instance_id, email, encrypted_password, email_confirmed_at,
    created_at, updated_at, raw_app_meta_data, raw_user_meta_data, aud, role
  ) VALUES (
    v_user_id,
    '00000000-0000-0000-0000-000000000000',
    'bob@example.com',
    'hashed_placeholder',
    now(), now(), now(),
    '{"provider":"email","providers":["email"]}',
    '{}',    -- pas de full_name → doit fallback sur email
    'authenticated',
    'authenticated'
  ) ON CONFLICT (id) DO NOTHING;

  SELECT full_name INTO v_pub_name FROM public.landlords WHERE id = v_user_id;
  SELECT full_name INTO v_dev_name FROM dev.landlords    WHERE id = v_user_id;

  IF v_pub_name IS DISTINCT FROM 'bob@example.com' THEN
    RAISE EXCEPTION '[FAIL] TEST 2 public: fallback email attendu "bob@example.com", obtenu "%"', v_pub_name;
  END IF;

  IF v_dev_name IS DISTINCT FROM 'bob@example.com' THEN
    RAISE EXCEPTION '[FAIL] TEST 2 dev: fallback email attendu "bob@example.com", obtenu "%"', v_dev_name;
  END IF;

  RAISE NOTICE '[PASS] TEST 2: fallback email appliqué quand full_name absent (public="%", dev="%")',
    v_pub_name, v_dev_name;
END $$;

-- ============================================================================
-- TEST 3 : Signup avec full_name = chaîne vide ou espaces → fallback email
-- ============================================================================
DO $$
DECLARE
  v_user_id  uuid := 'f0000011-0000-0000-0000-000000000003';
  v_pub_name text;
  v_dev_name text;
BEGIN
  INSERT INTO auth.users (
    id, instance_id, email, encrypted_password, email_confirmed_at,
    created_at, updated_at, raw_app_meta_data, raw_user_meta_data, aud, role
  ) VALUES (
    v_user_id,
    '00000000-0000-0000-0000-000000000000',
    'charlie@example.com',
    'hashed_placeholder',
    now(), now(), now(),
    '{"provider":"email","providers":["email"]}',
    '{"full_name":"   "}',    -- espaces uniquement → TRIM + NULLIF → fallback email
    'authenticated',
    'authenticated'
  ) ON CONFLICT (id) DO NOTHING;

  SELECT full_name INTO v_pub_name FROM public.landlords WHERE id = v_user_id;
  SELECT full_name INTO v_dev_name FROM dev.landlords    WHERE id = v_user_id;

  IF v_pub_name IS DISTINCT FROM 'charlie@example.com' THEN
    RAISE EXCEPTION '[FAIL] TEST 3 public: fallback email attendu "charlie@example.com", obtenu "%"', v_pub_name;
  END IF;

  IF v_dev_name IS DISTINCT FROM 'charlie@example.com' THEN
    RAISE EXCEPTION '[FAIL] TEST 3 dev: fallback email attendu "charlie@example.com", obtenu "%"', v_dev_name;
  END IF;

  RAISE NOTICE '[PASS] TEST 3: fallback email appliqué quand full_name = espaces (public="%", dev="%")',
    v_pub_name, v_dev_name;
END $$;

-- ============================================================================
-- TEST 4 : Création via admin (raw_user_meta_data = NULL) → fallback email
-- Cas réel : Supabase Studio crée des users sans raw_user_meta_data
-- ============================================================================
DO $$
DECLARE
  v_user_id  uuid := 'f0000011-0000-0000-0000-000000000004';
  v_pub_name text;
  v_dev_name text;
BEGIN
  INSERT INTO auth.users (
    id, instance_id, email, encrypted_password, email_confirmed_at,
    created_at, updated_at, raw_app_meta_data, raw_user_meta_data, aud, role
  ) VALUES (
    v_user_id,
    '00000000-0000-0000-0000-000000000000',
    'diana@example.com',
    'hashed_placeholder',
    now(), now(), now(),
    '{"provider":"email","providers":["email"]}',
    NULL,    -- raw_user_meta_data NULL → l'opérateur ->> retourne NULL → fallback email
    'authenticated',
    'authenticated'
  ) ON CONFLICT (id) DO NOTHING;

  SELECT full_name INTO v_pub_name FROM public.landlords WHERE id = v_user_id;
  SELECT full_name INTO v_dev_name FROM dev.landlords    WHERE id = v_user_id;

  IF v_pub_name IS DISTINCT FROM 'diana@example.com' THEN
    RAISE EXCEPTION '[FAIL] TEST 4 public: fallback email attendu "diana@example.com", obtenu "%"', v_pub_name;
  END IF;

  IF v_dev_name IS DISTINCT FROM 'diana@example.com' THEN
    RAISE EXCEPTION '[FAIL] TEST 4 dev: fallback email attendu "diana@example.com", obtenu "%"', v_dev_name;
  END IF;

  RAISE NOTICE '[PASS] TEST 4: fallback email appliqué quand raw_user_meta_data IS NULL (public="%", dev="%")',
    v_pub_name, v_dev_name;
END $$;

-- ============================================================================
-- TEST 5 : Idempotence — un deuxième INSERT sur le même id est ignoré (ON CONFLICT DO NOTHING)
-- Simule un retry de signup ou un double-trigger.
-- ============================================================================
DO $$
DECLARE
  v_user_id   uuid    := 'f0000011-0000-0000-0000-000000000001'; -- même que TEST 1
  v_pub_count integer;
  v_pub_name  text;
BEGIN
  -- Tenter de ré-insérer le même user (doit être ignoré silencieusement)
  INSERT INTO auth.users (
    id, instance_id, email, encrypted_password, email_confirmed_at,
    created_at, updated_at, raw_app_meta_data, raw_user_meta_data, aud, role
  ) VALUES (
    v_user_id,
    '00000000-0000-0000-0000-000000000000',
    'alice@example.com',
    'hashed_placeholder',
    now(), now(), now(),
    '{"provider":"email","providers":["email"]}',
    '{"full_name":"Alice Modifiee"}',  -- tentative de remplacement
    'authenticated',
    'authenticated'
  ) ON CONFLICT (id) DO NOTHING;

  SELECT COUNT(*), MAX(full_name)
    INTO v_pub_count, v_pub_name
    FROM public.landlords WHERE id = v_user_id;

  IF v_pub_count <> 1 THEN
    RAISE EXCEPTION '[FAIL] TEST 5: attendu 1 ligne, obtenu % (idempotence brisée)', v_pub_count;
  END IF;

  IF v_pub_name IS DISTINCT FROM 'Alice Dupont' THEN
    RAISE EXCEPTION '[FAIL] TEST 5: full_name ne doit pas être écrasé par un re-trigger (obtenu "%")', v_pub_name;
  END IF;

  RAISE NOTICE '[PASS] TEST 5: idempotence confirmée — ON CONFLICT DO NOTHING préserve la valeur initiale';
END $$;

-- ============================================================================
-- Teardown
-- ============================================================================
DO $$
DECLARE
  v_ids uuid[] := ARRAY[
    'f0000011-0000-0000-0000-000000000001'::uuid,
    'f0000011-0000-0000-0000-000000000002'::uuid,
    'f0000011-0000-0000-0000-000000000003'::uuid,
    'f0000011-0000-0000-0000-000000000004'::uuid
  ];
BEGIN
  DELETE FROM public.landlords WHERE id = ANY(v_ids);
  DELETE FROM dev.landlords    WHERE id = ANY(v_ids);
  DELETE FROM auth.users       WHERE id = ANY(v_ids);
  RAISE NOTICE '[INFO] Teardown : données de test supprimées';
END $$;

ROLLBACK;
-- ROLLBACK annule tout. Pour un run persistant (debug), remplacer par COMMIT.
