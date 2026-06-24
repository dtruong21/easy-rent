-- ============================================================================
-- Tests smoke — handle_new_user() FEAT-016 (rgpd_consent depuis raw_user_meta_data)
-- ============================================================================
-- Objectif : vérifier que le trigger on_auth_user_created persiste bien
-- rgpd_consent_at et rgpd_consent_version dans les deux schémas.
--
-- Tests couverts :
--   1. Signup avec rgpd_consent_version fourni → landlords.rgpd_consent_version = valeur
--   2. Signup sans rgpd_consent_version (hors-app) → fallback 'legacy-1'
--   3. Signup avec rgpd_consent_version vide/espaces → fallback 'legacy-1'
--   4. Signup admin (raw_user_meta_data = NULL) → fallback 'legacy-1'
--   5. rgpd_consent_at est toujours renseigné (NOT NULL) et cohérent
-- ============================================================================
-- USAGE: psql <connection_string> -f supabase/tests/auth_rgpd_consent_smoke.sql
-- Stack locale : supabase db reset puis :
--   psql postgresql://postgres:postgres@localhost:54322/postgres \
--        -f supabase/tests/auth_rgpd_consent_smoke.sql
-- ============================================================================

BEGIN;

-- ============================================================================
-- TEST 1 : Signup avec rgpd_consent_version fourni (cas app Flutter nominal)
-- ============================================================================
DO $$
DECLARE
  v_user_id      uuid := 'f0000016-0000-0000-0000-000000000001';
  v_pub_version  text;
  v_dev_version  text;
  v_pub_at       timestamptz;
  v_dev_at       timestamptz;
BEGIN
  INSERT INTO auth.users (
    id, instance_id, email, encrypted_password, email_confirmed_at,
    created_at, updated_at, raw_app_meta_data, raw_user_meta_data, aud, role
  ) VALUES (
    v_user_id,
    '00000000-0000-0000-0000-000000000000',
    'rgpd-test1@example.com',
    'hashed_placeholder',
    now(), now(), now(),
    '{"provider":"email","providers":["email"]}',
    '{"full_name":"Alice Dupont","rgpd_consent_version":"v1-2026-06"}',
    'authenticated',
    'authenticated'
  ) ON CONFLICT (id) DO NOTHING;

  SELECT rgpd_consent_version, rgpd_consent_at
    INTO v_pub_version, v_pub_at
    FROM public.landlords WHERE id = v_user_id;

  SELECT rgpd_consent_version, rgpd_consent_at
    INTO v_dev_version, v_dev_at
    FROM dev.landlords WHERE id = v_user_id;

  IF v_pub_version IS DISTINCT FROM 'v1-2026-06' THEN
    RAISE EXCEPTION '[FAIL] TEST 1 public: rgpd_consent_version attendu "v1-2026-06", obtenu "%"', v_pub_version;
  END IF;

  IF v_dev_version IS DISTINCT FROM 'v1-2026-06' THEN
    RAISE EXCEPTION '[FAIL] TEST 1 dev: rgpd_consent_version attendu "v1-2026-06", obtenu "%"', v_dev_version;
  END IF;

  IF v_pub_at IS NULL THEN
    RAISE EXCEPTION '[FAIL] TEST 1 public: rgpd_consent_at ne doit pas être NULL';
  END IF;

  IF v_dev_at IS NULL THEN
    RAISE EXCEPTION '[FAIL] TEST 1 dev: rgpd_consent_at ne doit pas être NULL';
  END IF;

  RAISE NOTICE '[PASS] TEST 1: rgpd_consent_version="%" persisté dans les deux schémas, consent_at renseigné',
    v_pub_version;
END $$;

-- ============================================================================
-- TEST 2 : Signup sans rgpd_consent_version (raw_user_meta_data = '{}')
-- Cas : autre client, import sans metadata RGPD → fallback 'legacy-1'
-- ============================================================================
DO $$
DECLARE
  v_user_id     uuid := 'f0000016-0000-0000-0000-000000000002';
  v_pub_version text;
  v_dev_version text;
BEGIN
  INSERT INTO auth.users (
    id, instance_id, email, encrypted_password, email_confirmed_at,
    created_at, updated_at, raw_app_meta_data, raw_user_meta_data, aud, role
  ) VALUES (
    v_user_id,
    '00000000-0000-0000-0000-000000000000',
    'rgpd-test2@example.com',
    'hashed_placeholder',
    now(), now(), now(),
    '{"provider":"email","providers":["email"]}',
    '{}',   -- pas de rgpd_consent_version → fallback 'legacy-1'
    'authenticated',
    'authenticated'
  ) ON CONFLICT (id) DO NOTHING;

  SELECT rgpd_consent_version INTO v_pub_version FROM public.landlords WHERE id = v_user_id;
  SELECT rgpd_consent_version INTO v_dev_version FROM dev.landlords    WHERE id = v_user_id;

  IF v_pub_version IS DISTINCT FROM 'legacy-1' THEN
    RAISE EXCEPTION '[FAIL] TEST 2 public: fallback "legacy-1" attendu, obtenu "%"', v_pub_version;
  END IF;

  IF v_dev_version IS DISTINCT FROM 'legacy-1' THEN
    RAISE EXCEPTION '[FAIL] TEST 2 dev: fallback "legacy-1" attendu, obtenu "%"', v_dev_version;
  END IF;

  RAISE NOTICE '[PASS] TEST 2: fallback "legacy-1" appliqué quand rgpd_consent_version absent (pub="%", dev="%")',
    v_pub_version, v_dev_version;
END $$;

-- ============================================================================
-- TEST 3 : rgpd_consent_version = chaîne vide ou espaces → fallback 'legacy-1'
-- ============================================================================
DO $$
DECLARE
  v_user_id     uuid := 'f0000016-0000-0000-0000-000000000003';
  v_pub_version text;
  v_dev_version text;
BEGIN
  INSERT INTO auth.users (
    id, instance_id, email, encrypted_password, email_confirmed_at,
    created_at, updated_at, raw_app_meta_data, raw_user_meta_data, aud, role
  ) VALUES (
    v_user_id,
    '00000000-0000-0000-0000-000000000000',
    'rgpd-test3@example.com',
    'hashed_placeholder',
    now(), now(), now(),
    '{"provider":"email","providers":["email"]}',
    '{"rgpd_consent_version":"   "}',  -- espaces → TRIM + NULLIF → fallback
    'authenticated',
    'authenticated'
  ) ON CONFLICT (id) DO NOTHING;

  SELECT rgpd_consent_version INTO v_pub_version FROM public.landlords WHERE id = v_user_id;
  SELECT rgpd_consent_version INTO v_dev_version FROM dev.landlords    WHERE id = v_user_id;

  IF v_pub_version IS DISTINCT FROM 'legacy-1' THEN
    RAISE EXCEPTION '[FAIL] TEST 3 public: fallback "legacy-1" attendu, obtenu "%"', v_pub_version;
  END IF;

  IF v_dev_version IS DISTINCT FROM 'legacy-1' THEN
    RAISE EXCEPTION '[FAIL] TEST 3 dev: fallback "legacy-1" attendu, obtenu "%"', v_dev_version;
  END IF;

  RAISE NOTICE '[PASS] TEST 3: fallback "legacy-1" appliqué quand rgpd_consent_version = espaces';
END $$;

-- ============================================================================
-- TEST 4 : Création via admin (raw_user_meta_data = NULL) → fallback 'legacy-1'
-- ============================================================================
DO $$
DECLARE
  v_user_id     uuid := 'f0000016-0000-0000-0000-000000000004';
  v_pub_version text;
  v_dev_version text;
BEGIN
  INSERT INTO auth.users (
    id, instance_id, email, encrypted_password, email_confirmed_at,
    created_at, updated_at, raw_app_meta_data, raw_user_meta_data, aud, role
  ) VALUES (
    v_user_id,
    '00000000-0000-0000-0000-000000000000',
    'rgpd-test4@example.com',
    'hashed_placeholder',
    now(), now(), now(),
    '{"provider":"email","providers":["email"]}',
    NULL,   -- raw_user_meta_data NULL → opérateur ->> retourne NULL → fallback
    'authenticated',
    'authenticated'
  ) ON CONFLICT (id) DO NOTHING;

  SELECT rgpd_consent_version INTO v_pub_version FROM public.landlords WHERE id = v_user_id;
  SELECT rgpd_consent_version INTO v_dev_version FROM dev.landlords    WHERE id = v_user_id;

  IF v_pub_version IS DISTINCT FROM 'legacy-1' THEN
    RAISE EXCEPTION '[FAIL] TEST 4 public: fallback "legacy-1" attendu, obtenu "%"', v_pub_version;
  END IF;

  IF v_dev_version IS DISTINCT FROM 'legacy-1' THEN
    RAISE EXCEPTION '[FAIL] TEST 4 dev: fallback "legacy-1" attendu, obtenu "%"', v_dev_version;
  END IF;

  RAISE NOTICE '[PASS] TEST 4: fallback "legacy-1" appliqué quand raw_user_meta_data IS NULL';
END $$;

-- ============================================================================
-- TEST 5 : rgpd_consent_at est cohérent (proche de now() à ± 5 secondes)
-- ============================================================================
DO $$
DECLARE
  v_user_id uuid := 'f0000016-0000-0000-0000-000000000001'; -- TEST 1 déjà créé
  v_pub_at  timestamptz;
BEGIN
  SELECT rgpd_consent_at INTO v_pub_at FROM public.landlords WHERE id = v_user_id;

  IF v_pub_at IS NULL THEN
    RAISE EXCEPTION '[FAIL] TEST 5: rgpd_consent_at est NULL';
  END IF;

  IF abs(extract(epoch FROM (now() - v_pub_at))) > 5 THEN
    RAISE EXCEPTION '[FAIL] TEST 5: rgpd_consent_at trop éloigné de now() : %', v_pub_at;
  END IF;

  RAISE NOTICE '[PASS] TEST 5: rgpd_consent_at=% est cohérent avec now()', v_pub_at;
END $$;

-- ============================================================================
-- Teardown
-- ============================================================================
DO $$
DECLARE
  v_ids uuid[] := ARRAY[
    'f0000016-0000-0000-0000-000000000001'::uuid,
    'f0000016-0000-0000-0000-000000000002'::uuid,
    'f0000016-0000-0000-0000-000000000003'::uuid,
    'f0000016-0000-0000-0000-000000000004'::uuid
  ];
BEGIN
  DELETE FROM public.landlords WHERE id = ANY(v_ids);
  DELETE FROM dev.landlords    WHERE id = ANY(v_ids);
  DELETE FROM auth.users       WHERE id = ANY(v_ids);
  RAISE NOTICE '[INFO] Teardown : données de test FEAT-016 supprimées';
END $$;

ROLLBACK;
-- ROLLBACK annule tout. Pour un run persistant (debug), remplacer par COMMIT.
