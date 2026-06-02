-- ============================================================================
-- Tests RLS Storage — bucket receipts/ (FEAT-007 Round 2, issue M6)
-- ============================================================================
-- Vérifie les policies Storage sur le bucket "receipts" :
--   receipts_storage_select_own  (FOR SELECT)
--   receipts_storage_insert_own  (FOR INSERT)
--   Pas de policy UPDATE ni DELETE (immuabilité légale)
--
-- Tests couverts :
--   1. User A peut uploader dans son propre folder (INSERT autorisé)
--   2. User A NE peut PAS uploader dans le folder de User B (42501)
--   3. User A peut lister/SELECT ses propres objets Storage
--   4. User A NE peut PAS voir les objets de User B (isolation Storage)
--   5. DELETE bloqué : aucune policy DELETE → 42501 pour tout le monde
--
-- Note sur l'architecture des tests Storage :
--   storage.objects est une table gérée par l'extension Supabase Storage.
--   Sous Supabase (PostgREST + storage-api), les uploads passent par l'API
--   HTTP Storage, pas par des INSERT SQL directs. En test SQL pur (psql), on
--   insère directement dans storage.objects pour simuler le comportement RLS.
--   La colonne "owner" est le user_id (uuid), et le chemin "name" détermine
--   le folder via storage.foldername(name)[1].
--   Les policies Storage évaluent auth.uid() exactement comme les tables RLS.
--
-- USAGE: psql <connection_string> -f supabase/tests/storage_receipts.sql
--
-- Si psql n'est pas disponible : les requêtes manuelles à exécuter dans
-- Supabase Studio (SQL Editor) sont documentées en commentaires ci-dessous.
-- ============================================================================

BEGIN;

-- ============================================================================
-- Setup : deux users + landlords (préfixe 0007-s pour Storage)
-- ============================================================================
-- UUIDs : 00000000-0000-0000-0007-0000000002xx
-- Préfixe 0007-0002 pour éviter toute collision avec rls_receipts.sql (0007-0001)

INSERT INTO auth.users (
  id, instance_id, email, encrypted_password, email_confirmed_at,
  created_at, updated_at, raw_app_meta_data, raw_user_meta_data, aud, role
) VALUES
  ('00000000-0000-0000-0007-000000000201', '00000000-0000-0000-0000-000000000000',
   'storage_user_a@test.example', 'hashed', now(), now(), now(),
   '{"provider":"email","providers":["email"]}', '{}', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0007-000000000202', '00000000-0000-0000-0000-000000000000',
   'storage_user_b@test.example', 'hashed', now(), now(), now(),
   '{"provider":"email","providers":["email"]}', '{}', 'authenticated', 'authenticated')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.landlords (id, email) VALUES
  ('00000000-0000-0000-0007-000000000201', 'storage_user_a@test.example'),
  ('00000000-0000-0000-0007-000000000202', 'storage_user_b@test.example')
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- TEST 1 : User A peut uploader dans son propre folder
-- ============================================================================
-- Policy "receipts_storage_insert_own" :
--   WITH CHECK (bucket_id = 'receipts' AND (storage.foldername(name))[1] = auth.uid()::text)
-- Le chemin receipts/<landlord_id>/<receipt_id>.pdf → foldername[1] = landlord_id
--
-- Requête Supabase Studio manuelle (si psql indisponible) :
--   SET request.jwt.claims TO '{"sub":"00000000-0000-0000-0007-000000000201","role":"authenticated"}';
--   SET ROLE authenticated;
--   INSERT INTO storage.objects (bucket_id, name, owner, owner_id, metadata)
--     VALUES ('receipts', '00000000-0000-0000-0007-000000000201/receipt-test-1.pdf',
--             '00000000-0000-0000-0007-000000000201'::uuid,
--             '00000000-0000-0000-0007-000000000201'::uuid,
--             '{}');
--   -- Attendu : INSERT 1 ligne

DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0007-000000000201","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    INSERT INTO storage.objects (bucket_id, name, owner, owner_id, metadata)
      VALUES (
        'receipts',
        '00000000-0000-0000-0007-000000000201/receipt-test-1.pdf',
        '00000000-0000-0000-0007-000000000201'::uuid,
        '00000000-0000-0000-0007-000000000201'::uuid,
        '{}'::jsonb
      );
    RESET ROLE;
    RAISE NOTICE '[PASS] TEST 1: User A peut uploader dans son propre folder (receipts_storage_insert_own)';
  EXCEPTION
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 1: User A devrait pouvoir uploader dans son folder (SQLSTATE %, msg: %)',
        SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 2 : User A NE peut PAS uploader dans le folder de User B
-- ============================================================================
-- Attendu : SQLSTATE 42501 (insufficient_privilege) — RLS violation
-- Le chemin commence par B.id → (storage.foldername(name))[1] = B.id ≠ auth.uid()
--
-- Requête Supabase Studio manuelle :
--   SET request.jwt.claims TO '{"sub":"00000000-0000-0000-0007-000000000201","role":"authenticated"}';
--   SET ROLE authenticated;
--   INSERT INTO storage.objects (bucket_id, name, owner, owner_id, metadata)
--     VALUES ('receipts', '00000000-0000-0000-0007-000000000202/receipt-test-2.pdf',
--             '00000000-0000-0000-0007-000000000201'::uuid,
--             '00000000-0000-0000-0007-000000000201'::uuid,
--             '{}');
--   -- Attendu : ERROR 42501 new row violates row-level security policy

DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0007-000000000201","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    INSERT INTO storage.objects (bucket_id, name, owner, owner_id, metadata)
      VALUES (
        'receipts',
        '00000000-0000-0000-0007-000000000202/receipt-test-2.pdf',  -- folder de User B
        '00000000-0000-0000-0007-000000000201'::uuid,               -- owner = User A (mismatch chemin)
        '00000000-0000-0000-0007-000000000201'::uuid,
        '{}'::jsonb
      );
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 2: User A NE devrait PAS pouvoir uploader dans le folder de User B';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 2: User A ne peut pas uploader dans le folder de User B (42501 — receipts_storage_insert_own)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 2: Erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- Setup TEST 3 et 4 : insérer un objet Storage pour User B en superuser
-- ============================================================================
-- Aucun rôle → superuser contourne RLS → INSERT dans le folder de User B
INSERT INTO storage.objects (bucket_id, name, owner, owner_id, metadata)
  VALUES (
    'receipts',
    '00000000-0000-0000-0007-000000000202/receipt-test-3.pdf',
    '00000000-0000-0000-0007-000000000202'::uuid,
    '00000000-0000-0000-0007-000000000202'::uuid,
    '{}'::jsonb
  )
ON CONFLICT DO NOTHING;

-- ============================================================================
-- TEST 3 : User A peut lister/SELECT ses propres objets Storage
-- ============================================================================
-- Policy "receipts_storage_select_own" :
--   USING (bucket_id = 'receipts' AND (storage.foldername(name))[1] = auth.uid()::text)
--
-- Requête Supabase Studio manuelle :
--   SET request.jwt.claims TO '{"sub":"00000000-0000-0000-0007-000000000201","role":"authenticated"}';
--   SET ROLE authenticated;
--   SELECT COUNT(*) FROM storage.objects
--     WHERE bucket_id = 'receipts'
--       AND name LIKE '00000000-0000-0000-0007-000000000201/%';
--   -- Attendu : 1 (l'objet uploadé au TEST 1)

DO $$
DECLARE row_count integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0007-000000000201","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  SELECT COUNT(*) INTO row_count FROM storage.objects
    WHERE bucket_id = 'receipts'
      AND name LIKE '00000000-0000-0000-0007-000000000201/%';

  RESET ROLE;

  IF row_count < 1 THEN
    RAISE EXCEPTION '[FAIL] TEST 3: User A devrait voir ses propres objets Storage (got %)', row_count;
  END IF;
  RAISE NOTICE '[PASS] TEST 3: User A voit ses propres objets Storage (count=%, receipts_storage_select_own)', row_count;
END $$;

-- ============================================================================
-- TEST 4 : User A NE peut PAS voir les objets de User B
-- ============================================================================
-- La policy "receipts_storage_select_own" filtre sur foldername[1] = auth.uid()
-- → les objets de User B (foldername[1] = B.id) sont invisibles pour User A.
--
-- Requête Supabase Studio manuelle :
--   SET request.jwt.claims TO '{"sub":"00000000-0000-0000-0007-000000000201","role":"authenticated"}';
--   SET ROLE authenticated;
--   SELECT COUNT(*) FROM storage.objects
--     WHERE bucket_id = 'receipts'
--       AND name LIKE '00000000-0000-0000-0007-000000000202/%';
--   -- Attendu : 0 (isolation — objet de User B invisible)

DO $$
DECLARE row_count integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0007-000000000201","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  SELECT COUNT(*) INTO row_count FROM storage.objects
    WHERE bucket_id = 'receipts'
      AND name LIKE '00000000-0000-0000-0007-000000000202/%';

  RESET ROLE;

  IF row_count <> 0 THEN
    RAISE EXCEPTION '[FAIL] TEST 4: User A ne devrait pas voir les objets de User B (got %)', row_count;
  END IF;
  RAISE NOTICE '[PASS] TEST 4: User A ne voit pas les objets de User B (isolation Storage OK)';
END $$;

-- ============================================================================
-- TEST 5 : DELETE bloqué — aucune policy DELETE sur storage.objects (bucket receipts)
-- ============================================================================
-- Pas de policy DELETE définie pour le bucket "receipts" → RLS bloque DELETE
-- pour le rôle authenticated (immuabilité légale — rétention 5 ans).
--
-- Requête Supabase Studio manuelle :
--   SET request.jwt.claims TO '{"sub":"00000000-0000-0000-0007-000000000201","role":"authenticated"}';
--   SET ROLE authenticated;
--   DELETE FROM storage.objects
--     WHERE bucket_id = 'receipts'
--       AND name = '00000000-0000-0000-0007-000000000201/receipt-test-1.pdf';
--   -- Attendu : 0 lignes supprimées (RLS bloque silencieusement DELETE sans policy)
--   -- Note : PostgreSQL RLS sans policy DELETE retourne 0 rows affectées, pas 42501.

DO $$
DECLARE rows_deleted integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0007-000000000201","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  DELETE FROM storage.objects
    WHERE bucket_id = 'receipts'
      AND name = '00000000-0000-0000-0007-000000000201/receipt-test-1.pdf';
  GET DIAGNOSTICS rows_deleted = ROW_COUNT;

  RESET ROLE;

  -- Avec RLS sans policy DELETE, PostgreSQL ne lève pas d'exception — il retourne
  -- simplement 0 lignes affectées (la ligne n'est pas "visible" pour DELETE).
  IF rows_deleted <> 0 THEN
    RAISE EXCEPTION '[FAIL] TEST 5: DELETE devrait être bloqué par RLS (absence de policy DELETE), mais % lignes supprimées', rows_deleted;
  END IF;
  RAISE NOTICE '[PASS] TEST 5: DELETE bloqué — aucune policy DELETE sur bucket receipts (0 lignes supprimées, immuabilité légale confirmée)';
END $$;

-- ============================================================================
-- Teardown : nettoyage des objets Storage et users de test
-- ============================================================================
-- Suppression en superuser (pas de RLS) pour nettoyer le state du test
DELETE FROM storage.objects
  WHERE bucket_id = 'receipts'
    AND name LIKE '00000000-0000-0000-0007-0000000002%';

DELETE FROM public.landlords WHERE id IN (
  '00000000-0000-0000-0007-000000000201',
  '00000000-0000-0000-0007-000000000202'
);

DELETE FROM auth.users WHERE id IN (
  '00000000-0000-0000-0007-000000000201',
  '00000000-0000-0000-0007-000000000202'
);

ROLLBACK;
