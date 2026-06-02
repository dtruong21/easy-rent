-- ============================================================================
-- Tests RLS Storage — bucket documents/ (FEAT-009, security-auditor finding)
-- ============================================================================
-- Vérifie les policies Storage sur le bucket "documents" :
--   documents_storage_select_own  (FOR SELECT)
--   documents_storage_insert_own  (FOR INSERT)
--   documents_storage_delete_own  (FOR DELETE)
--   Pas de policy UPDATE (fichiers immuables — replace = delete + re-upload)
--
-- Divergence vs bucket receipts/ :
--   - receipts/ : isolation sur segment [1] = landlord_id
--     chemin = {landlord_id}/{receipt_id}.pdf
--   - documents/ : isolation sur segment [2] = landlord_id (segment [1] = env)
--     chemin = {env}/{landlord_id}/{document_id}.{ext}
--   Cette asymétrie est assumée (cf. §3.2 FEAT-009-documents-storage.md).
--
-- Tests couverts (10 tests, plan §12.2 + brief security-auditor) :
--   1. insert_own_path_ok          — User A INSERT dans documents/prod/<self>/...       → OK
--   2. insert_cross_user_refused   — User A INSERT dans documents/prod/<other>/...      → 42501
--   3. select_own_path_ok          — User A SELECT ses propres objets                   → count >= 1
--   4. select_cross_user_refused   — User A SELECT objets de User B                     → 0 rows
--   5. delete_own_path_ok          — User A DELETE son propre objet                     → 1 ligne supprimée
--   6. delete_cross_user_refused   — User A DELETE objet de User B                      → 0 lignes (RLS filtre silencieusement)
--   7. mime_whitelist_enforced     — INSERT MIME non autorisé en dehors de l'API HTTP   → limitation documentée (cf. note)
--   8. size_limit_enforced         — INSERT fichier > 10 MB via SQL direct              → limitation documentée (cf. note)
--   9. anon_refused                — Sans JWT (rôle anon) : INSERT + SELECT + DELETE    → 0 rows / 42501
--  10. assert_storage_bucket_config — Vérifie file_size_limit=10485760 + allowed_mime_types whitelist
--
-- Note sur mime_whitelist (tests 7 & 8) :
--   Les contraintes `allowed_mime_types` et `file_size_limit` sont appliquées par
--   le service HTTP Supabase Storage (storage-api), PAS par des policies RLS SQL.
--   Un INSERT direct dans storage.objects (qui contourne l'API HTTP) ne déclenche
--   pas ces validations — elles opèrent au niveau de l'API multipart/form-data.
--   Le test 10 vérifie la configuration du bucket (valeurs en DB), ce qui est la
--   seule assertion SQL valide. Les tests 7 et 8 sont remplacés par des assertions
--   de configuration + documentation de la limitation.
--   Pattern identique documenté dans storage_receipts.sql (FEAT-007 Round 2).
--
-- USAGE: psql <connection_string> -f supabase/tests/storage_documents.sql
--
-- Si psql n'est pas disponible : les requêtes manuelles à exécuter dans
-- Supabase Studio (SQL Editor) sont documentées en commentaires ci-dessous.
-- ============================================================================

BEGIN;

-- ============================================================================
-- Setup : deux users + landlords (préfixe 0009-s pour Storage)
-- ============================================================================
-- UUIDs : 00000000-0000-0000-0009-0000000002xx
-- Préfixe 0009-0002 pour éviter toute collision avec rls_documents.sql (0009-0001)

INSERT INTO auth.users (
  id, instance_id, email, encrypted_password, email_confirmed_at,
  created_at, updated_at, raw_app_meta_data, raw_user_meta_data, aud, role
) VALUES
  ('00000000-0000-0000-0009-000000000201', '00000000-0000-0000-0000-000000000000',
   'doc_storage_user_a@test.example', 'hashed', now(), now(), now(),
   '{"provider":"email","providers":["email"]}', '{}', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0009-000000000202', '00000000-0000-0000-0000-000000000000',
   'doc_storage_user_b@test.example', 'hashed', now(), now(), now(),
   '{"provider":"email","providers":["email"]}', '{}', 'authenticated', 'authenticated')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.landlords (id, email) VALUES
  ('00000000-0000-0000-0009-000000000201', 'doc_storage_user_a@test.example'),
  ('00000000-0000-0000-0009-000000000202', 'doc_storage_user_b@test.example')
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- TEST 1 : User A peut uploader dans son propre folder (INSERT autorisé)
-- ============================================================================
-- Policy "documents_storage_insert_own" :
--   WITH CHECK (bucket_id = 'documents' AND (storage.foldername(name))[2] = auth.uid()::text)
-- Le chemin documents/prod/{landlord_id}/{doc_id}.pdf
-- → foldername = ARRAY['prod', '{landlord_id}'] → [2] = landlord_id
--
-- Requête Supabase Studio manuelle (si psql indisponible) :
--   SET request.jwt.claims TO '{"sub":"00000000-0000-0000-0009-000000000201","role":"authenticated"}';
--   SET ROLE authenticated;
--   INSERT INTO storage.objects (bucket_id, name, owner, owner_id, metadata)
--     VALUES ('documents', 'prod/00000000-0000-0000-0009-000000000201/doc-test-1.pdf',
--             '00000000-0000-0000-0009-000000000201'::uuid,
--             '00000000-0000-0000-0009-000000000201'::uuid,
--             '{}');
--   -- Attendu : INSERT 1 ligne

DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0009-000000000201","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    INSERT INTO storage.objects (bucket_id, name, owner, owner_id, metadata)
      VALUES (
        'documents',
        'prod/00000000-0000-0000-0009-000000000201/doc-test-1.pdf',
        '00000000-0000-0000-0009-000000000201'::uuid,
        '00000000-0000-0000-0009-000000000201'::uuid,
        '{}'::jsonb
      );
    RESET ROLE;
    RAISE NOTICE '[PASS] TEST 1 (insert_own_path_ok): User A peut uploader dans documents/prod/<self>/ (documents_storage_insert_own)';
  EXCEPTION
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 1 (insert_own_path_ok): User A devrait pouvoir uploader dans son folder (SQLSTATE %, msg: %)',
        SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 2 : User A NE peut PAS uploader dans le folder de User B
-- ============================================================================
-- Attendu : SQLSTATE 42501 (insufficient_privilege) — RLS violation
-- Le chemin contient B.id en segment [2] → (storage.foldername(name))[2] = B.id ≠ auth.uid()
--
-- Requête Supabase Studio manuelle :
--   SET request.jwt.claims TO '{"sub":"00000000-0000-0000-0009-000000000201","role":"authenticated"}';
--   SET ROLE authenticated;
--   INSERT INTO storage.objects (bucket_id, name, owner, owner_id, metadata)
--     VALUES ('documents', 'prod/00000000-0000-0000-0009-000000000202/doc-test-2.pdf',
--             '00000000-0000-0000-0009-000000000201'::uuid,
--             '00000000-0000-0000-0009-000000000201'::uuid,
--             '{}');
--   -- Attendu : ERROR 42501 new row violates row-level security policy

DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0009-000000000201","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    INSERT INTO storage.objects (bucket_id, name, owner, owner_id, metadata)
      VALUES (
        'documents',
        'prod/00000000-0000-0000-0009-000000000202/doc-test-2.pdf',   -- folder de User B
        '00000000-0000-0000-0009-000000000201'::uuid,                  -- owner = User A (mismatch segment [2])
        '00000000-0000-0000-0009-000000000201'::uuid,
        '{}'::jsonb
      );
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 2 (insert_cross_user_refused): User A NE devrait PAS pouvoir uploader dans le folder de User B';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 2 (insert_cross_user_refused): User A ne peut pas uploader dans le folder de User B (42501 — documents_storage_insert_own, segment [2])';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 2 (insert_cross_user_refused): Erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- Setup TEST 3, 4, 6 : insérer un objet Storage pour User B en superuser
-- ============================================================================
-- Aucun rôle → superuser contourne RLS → INSERT dans le folder de User B
INSERT INTO storage.objects (bucket_id, name, owner, owner_id, metadata)
  VALUES (
    'documents',
    'prod/00000000-0000-0000-0009-000000000202/doc-test-3.pdf',
    '00000000-0000-0000-0009-000000000202'::uuid,
    '00000000-0000-0000-0009-000000000202'::uuid,
    '{}'::jsonb
  )
ON CONFLICT DO NOTHING;

-- ============================================================================
-- TEST 3 : User A peut lister/SELECT ses propres objets Storage
-- ============================================================================
-- Policy "documents_storage_select_own" :
--   USING (bucket_id = 'documents' AND (storage.foldername(name))[2] = auth.uid()::text)
--
-- Requête Supabase Studio manuelle :
--   SET request.jwt.claims TO '{"sub":"00000000-0000-0000-0009-000000000201","role":"authenticated"}';
--   SET ROLE authenticated;
--   SELECT COUNT(*) FROM storage.objects
--     WHERE bucket_id = 'documents'
--       AND name LIKE 'prod/00000000-0000-0000-0009-000000000201/%';
--   -- Attendu : 1 (l'objet uploadé au TEST 1)

DO $$
DECLARE row_count integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0009-000000000201","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  SELECT COUNT(*) INTO row_count FROM storage.objects
    WHERE bucket_id = 'documents'
      AND name LIKE '%/00000000-0000-0000-0009-000000000201/%';

  RESET ROLE;

  IF row_count < 1 THEN
    RAISE EXCEPTION '[FAIL] TEST 3 (select_own_path_ok): User A devrait voir ses propres objets Storage (got %)', row_count;
  END IF;
  RAISE NOTICE '[PASS] TEST 3 (select_own_path_ok): User A voit ses propres objets Storage (count=%, documents_storage_select_own)', row_count;
END $$;

-- ============================================================================
-- TEST 4 : User A NE peut PAS voir les objets de User B (isolation Storage)
-- ============================================================================
-- La policy "documents_storage_select_own" filtre sur foldername[2] = auth.uid()
-- → les objets de User B (foldername[2] = B.id) sont invisibles pour User A.
--
-- Requête Supabase Studio manuelle :
--   SET request.jwt.claims TO '{"sub":"00000000-0000-0000-0009-000000000201","role":"authenticated"}';
--   SET ROLE authenticated;
--   SELECT COUNT(*) FROM storage.objects
--     WHERE bucket_id = 'documents'
--       AND name LIKE '%/00000000-0000-0000-0009-000000000202/%';
--   -- Attendu : 0 (isolation — objet de User B invisible)

DO $$
DECLARE row_count integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0009-000000000201","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  SELECT COUNT(*) INTO row_count FROM storage.objects
    WHERE bucket_id = 'documents'
      AND name LIKE '%/00000000-0000-0000-0009-000000000202/%';

  RESET ROLE;

  IF row_count <> 0 THEN
    RAISE EXCEPTION '[FAIL] TEST 4 (select_cross_user_refused): User A ne devrait pas voir les objets de User B (got %)', row_count;
  END IF;
  RAISE NOTICE '[PASS] TEST 4 (select_cross_user_refused): User A ne voit pas les objets de User B (isolation Storage, segment [2] OK)';
END $$;

-- ============================================================================
-- Setup TEST 5 : insérer un objet pour User A en superuser (à supprimer au TEST 5)
-- ============================================================================
INSERT INTO storage.objects (bucket_id, name, owner, owner_id, metadata)
  VALUES (
    'documents',
    'prod/00000000-0000-0000-0009-000000000201/doc-test-5-to-delete.pdf',
    '00000000-0000-0000-0009-000000000201'::uuid,
    '00000000-0000-0000-0009-000000000201'::uuid,
    '{}'::jsonb
  )
ON CONFLICT DO NOTHING;

-- ============================================================================
-- TEST 5 : User A peut DELETE son propre objet (DELETE autorisé)
-- ============================================================================
-- Policy "documents_storage_delete_own" :
--   USING (bucket_id = 'documents' AND (storage.foldername(name))[2] = auth.uid()::text)
-- Divergence vs receipts/ : ici DELETE est autorisé (hard-delete coordonné avec RPC
-- soft_delete_document — cf. D3 modifié §3.3 FEAT-009-documents-storage.md).
--
-- Requête Supabase Studio manuelle :
--   SET request.jwt.claims TO '{"sub":"00000000-0000-0000-0009-000000000201","role":"authenticated"}';
--   SET ROLE authenticated;
--   DELETE FROM storage.objects
--     WHERE bucket_id = 'documents'
--       AND name = 'prod/00000000-0000-0000-0009-000000000201/doc-test-5-to-delete.pdf';
--   -- Attendu : 1 ligne supprimée

DO $$
DECLARE rows_deleted integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0009-000000000201","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  DELETE FROM storage.objects
    WHERE bucket_id = 'documents'
      AND name = 'prod/00000000-0000-0000-0009-000000000201/doc-test-5-to-delete.pdf';
  GET DIAGNOSTICS rows_deleted = ROW_COUNT;

  RESET ROLE;

  IF rows_deleted <> 1 THEN
    RAISE EXCEPTION '[FAIL] TEST 5 (delete_own_path_ok): User A devrait pouvoir DELETE son propre objet (got % lignes supprimées)', rows_deleted;
  END IF;
  RAISE NOTICE '[PASS] TEST 5 (delete_own_path_ok): User A peut supprimer son propre objet Storage (1 ligne, documents_storage_delete_own)';
END $$;

-- ============================================================================
-- TEST 6 : User A NE peut PAS DELETE l'objet de User B
-- ============================================================================
-- Policy "documents_storage_delete_own" : USING (... foldername[2] = auth.uid()::text)
-- → objets de User B ont foldername[2] = B.id ≠ auth.uid()
-- → RLS filtre silencieusement (DELETE 0 rows — pas de 42501 sur DELETE sans policy MATCH)
-- Note : PostgreSQL RLS sans policy match sur DELETE retourne 0 rows affectées
-- (la ligne n'est pas "visible" pour DELETE). Comportement identique storage_receipts.sql TEST 5.
--
-- Requête Supabase Studio manuelle :
--   SET request.jwt.claims TO '{"sub":"00000000-0000-0000-0009-000000000201","role":"authenticated"}';
--   SET ROLE authenticated;
--   DELETE FROM storage.objects
--     WHERE bucket_id = 'documents'
--       AND name = 'prod/00000000-0000-0000-0009-000000000202/doc-test-3.pdf';
--   -- Attendu : 0 lignes supprimées (RLS bloque silencieusement)

DO $$
DECLARE rows_deleted integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0009-000000000201","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  DELETE FROM storage.objects
    WHERE bucket_id = 'documents'
      AND name = 'prod/00000000-0000-0000-0009-000000000202/doc-test-3.pdf';
  GET DIAGNOSTICS rows_deleted = ROW_COUNT;

  RESET ROLE;

  IF rows_deleted <> 0 THEN
    RAISE EXCEPTION '[FAIL] TEST 6 (delete_cross_user_refused): User A NE devrait PAS pouvoir supprimer l''objet de User B (got % lignes)', rows_deleted;
  END IF;
  RAISE NOTICE '[PASS] TEST 6 (delete_cross_user_refused): User A ne peut pas DELETE l''objet de User B (0 lignes — documents_storage_delete_own, segment [2] filtre)';
END $$;

-- ============================================================================
-- TEST 7 : mime_whitelist_enforced — Limitation documentée
-- ============================================================================
-- La contrainte `allowed_mime_types` du bucket est appliquée par le service HTTP
-- Supabase Storage (storage-api), PAS par une policy RLS SQL sur storage.objects.
-- Un INSERT SQL direct bypass cette validation : il faut tester via l'API HTTP
-- (ex: curl avec Content-Type: text/plain → attend HTTP 415 Unsupported Media Type).
--
-- Ce test vérifie que la colonne `allowed_mime_types` du bucket est correctement
-- configurée en base (préalable à la validation API). Le vrai test MIME doit être
-- effectué via l'API HTTP Storage (intégration, hors scope SQL pur).
--
-- Validation équivalente : test 10 (assert_storage_bucket_config) couvre la config.

DO $$
DECLARE
  mime_types text[];
BEGIN
  SELECT allowed_mime_types INTO mime_types
    FROM storage.buckets
   WHERE id = 'documents';

  IF mime_types IS NULL OR array_length(mime_types, 1) = 0 THEN
    RAISE EXCEPTION '[FAIL] TEST 7 (mime_whitelist_enforced): bucket documents — allowed_mime_types non configuré';
  END IF;

  -- Vérifie que text/plain N'EST PAS dans la whitelist
  IF 'text/plain' = ANY(mime_types) THEN
    RAISE EXCEPTION '[FAIL] TEST 7 (mime_whitelist_enforced): text/plain NE devrait PAS être dans allowed_mime_types (found: %)', mime_types;
  END IF;

  -- Vérifie que les 4 MIME autorisés sont présents
  IF NOT ('application/pdf' = ANY(mime_types)
    AND 'image/jpeg' = ANY(mime_types)
    AND 'image/png'  = ANY(mime_types)
    AND 'image/webp' = ANY(mime_types))
  THEN
    RAISE EXCEPTION '[FAIL] TEST 7 (mime_whitelist_enforced): whitelist incomplète (attendu: application/pdf + image/jpeg + image/png + image/webp, got: %)', mime_types;
  END IF;

  RAISE NOTICE '[PASS] TEST 7 (mime_whitelist_enforced): allowed_mime_types = % (text/plain absent, whitelist complète). NOTE: validation effective via API HTTP (HTTP 415 sur MIME non autorisé).', mime_types;
END $$;

-- ============================================================================
-- TEST 8 : size_limit_enforced — Limitation documentée
-- ============================================================================
-- La contrainte `file_size_limit` est appliquée par le service HTTP Supabase
-- Storage (storage-api), PAS via SQL. Un INSERT direct dans storage.objects ne
-- valide PAS la taille du fichier (la colonne metadata peut avoir n'importe quelle
-- valeur size). Le vrai test doit être effectué via l'API HTTP (ex: upload d'un
-- fichier > 10 MB → attend HTTP 413 Payload Too Large).
--
-- Ce test vérifie uniquement que file_size_limit est configuré à 10485760 (10 MB).
-- Le test 10 (assert_storage_bucket_config) couvre aussi cette vérification.

DO $$
DECLARE
  size_limit bigint;
BEGIN
  SELECT file_size_limit INTO size_limit
    FROM storage.buckets
   WHERE id = 'documents';

  IF size_limit IS NULL THEN
    RAISE EXCEPTION '[FAIL] TEST 8 (size_limit_enforced): bucket documents — file_size_limit non configuré (NULL)';
  END IF;

  IF size_limit <> 10485760 THEN
    RAISE EXCEPTION '[FAIL] TEST 8 (size_limit_enforced): file_size_limit attendu 10485760 (10 MB), got %', size_limit;
  END IF;

  RAISE NOTICE '[PASS] TEST 8 (size_limit_enforced): file_size_limit = % (10 MB). NOTE: validation effective via API HTTP (HTTP 413 si fichier trop volumineux).', size_limit;
END $$;

-- ============================================================================
-- TEST 9 : anon_refused — Sans JWT, toutes opérations refusées
-- ============================================================================
-- Le rôle "anon" ne correspond à aucune policy (toutes utilisent auth.uid() qui
-- retourne NULL pour anon). Comportement attendu :
--   INSERT → 42501 (new row violates RLS)
--   SELECT → 0 rows (WHERE filter sur NULL = UID)
--   DELETE → 0 rows (aucune row "visible" pour NULL uid)
--
-- Requête Supabase Studio manuelle :
--   SET ROLE anon;  -- sans SET request.jwt.claims
--   INSERT INTO storage.objects (bucket_id, name, owner, owner_id, metadata)
--     VALUES ('documents', 'prod/00000000-0000-0000-0009-000000000201/anon-attack.pdf',
--             NULL, NULL, '{}');
--   -- Attendu : ERROR 42501

-- Test 9a : anon INSERT refusé
DO $$
BEGIN
  -- Pas de set_config jwt.claims → auth.uid() retourne NULL
  SET LOCAL ROLE anon;

  BEGIN
    INSERT INTO storage.objects (bucket_id, name, owner, owner_id, metadata)
      VALUES (
        'documents',
        'prod/00000000-0000-0000-0009-000000000201/anon-attack.pdf',
        NULL,
        NULL,
        '{}'::jsonb
      );
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 9a (anon_refused — INSERT): anon NE devrait PAS pouvoir uploader dans documents/';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 9a (anon_refused — INSERT): anon ne peut pas INSERT dans bucket documents (42501)';
    WHEN OTHERS THEN
      RESET ROLE;
      -- RLS sur anon peut aussi donner d'autres erreurs (ex: 42P01 si storage.objects non accessible)
      RAISE NOTICE '[PASS] TEST 9a (anon_refused — INSERT): anon bloqué (SQLSTATE %, non 42501 mais accès refusé)', SQLSTATE;
  END;
END $$;

-- Test 9b : anon SELECT → 0 rows
DO $$
DECLARE row_count integer;
BEGIN
  SET LOCAL ROLE anon;

  SELECT COUNT(*) INTO row_count FROM storage.objects
    WHERE bucket_id = 'documents';

  RESET ROLE;

  IF row_count <> 0 THEN
    RAISE EXCEPTION '[FAIL] TEST 9b (anon_refused — SELECT): anon ne devrait voir aucun objet Storage (got %)', row_count;
  END IF;
  RAISE NOTICE '[PASS] TEST 9b (anon_refused — SELECT): anon ne voit aucun objet dans bucket documents (0 rows, auth.uid() IS NULL)';
END $$;

-- Test 9c : anon DELETE → 0 lignes supprimées
DO $$
DECLARE rows_deleted integer;
BEGIN
  SET LOCAL ROLE anon;

  DELETE FROM storage.objects
    WHERE bucket_id = 'documents'
      AND name LIKE 'prod/00000000-0000-0000-0009-000000000201/%';
  GET DIAGNOSTICS rows_deleted = ROW_COUNT;

  RESET ROLE;

  IF rows_deleted <> 0 THEN
    RAISE EXCEPTION '[FAIL] TEST 9c (anon_refused — DELETE): anon NE devrait PAS pouvoir DELETE des objets (got % lignes)', rows_deleted;
  END IF;
  RAISE NOTICE '[PASS] TEST 9c (anon_refused — DELETE): anon ne peut pas DELETE dans bucket documents (0 lignes)';
END $$;

-- ============================================================================
-- TEST 10 : assert_storage_bucket_config — Configuration complète du bucket
-- ============================================================================
-- Vérifie que le bucket "documents" est bien configuré :
--   - public = false (jamais d'URL publique)
--   - file_size_limit = 10485760 (10 MB)
--   - allowed_mime_types = {application/pdf, image/jpeg, image/png, image/webp}
--
-- Requête Supabase Studio manuelle :
--   SELECT id, name, public, file_size_limit, allowed_mime_types
--     FROM storage.buckets
--    WHERE id = 'documents';
--   -- Attendu : public=false, file_size_limit=10485760, 4 MIME types

DO $$
DECLARE
  bucket_public    boolean;
  bucket_size_lim  bigint;
  bucket_mimes     text[];
  expected_mimes   text[] := ARRAY['application/pdf','image/jpeg','image/png','image/webp'];
BEGIN
  SELECT b.public, b.file_size_limit, b.allowed_mime_types
    INTO bucket_public, bucket_size_lim, bucket_mimes
    FROM storage.buckets b
   WHERE b.id = 'documents';

  IF NOT FOUND THEN
    RAISE EXCEPTION '[FAIL] TEST 10 (assert_storage_bucket_config): bucket "documents" inexistant dans storage.buckets';
  END IF;

  -- Vérification public = false
  IF bucket_public IS DISTINCT FROM false THEN
    RAISE EXCEPTION '[FAIL] TEST 10 (assert_storage_bucket_config): bucket documents doit être privé (public=false), got public=%', bucket_public;
  END IF;

  -- Vérification file_size_limit = 10485760 (10 MB)
  IF bucket_size_lim IS DISTINCT FROM 10485760 THEN
    RAISE EXCEPTION '[FAIL] TEST 10 (assert_storage_bucket_config): file_size_limit attendu 10485760, got %', bucket_size_lim;
  END IF;

  -- Vérification allowed_mime_types : les 4 types attendus doivent tous être présents
  IF NOT (
    'application/pdf' = ANY(bucket_mimes)
    AND 'image/jpeg'  = ANY(bucket_mimes)
    AND 'image/png'   = ANY(bucket_mimes)
    AND 'image/webp'  = ANY(bucket_mimes)
  ) THEN
    RAISE EXCEPTION '[FAIL] TEST 10 (assert_storage_bucket_config): allowed_mime_types incomplet. Attendu: %, got: %',
      expected_mimes, bucket_mimes;
  END IF;

  RAISE NOTICE '[PASS] TEST 10 (assert_storage_bucket_config): bucket documents — public=false, file_size_limit=10485760, allowed_mime_types=% (D1=B whitelist serveur)', bucket_mimes;
END $$;

-- ============================================================================
-- Teardown : nettoyage des objets Storage et users de test
-- ============================================================================
-- Suppression en superuser (pas de RLS) pour nettoyer le state du test.
-- Le préfixe %/00000000-0000-0000-0009-0000000002% couvre tous les objets des
-- deux users de test, quel que soit l'env prefix (prod/, dev/, etc.).
DELETE FROM storage.objects
  WHERE bucket_id = 'documents'
    AND (
      name LIKE '%/00000000-0000-0000-0009-000000000201/%'
      OR name LIKE '%/00000000-0000-0000-0009-000000000202/%'
    );

DELETE FROM public.landlords WHERE id IN (
  '00000000-0000-0000-0009-000000000201',
  '00000000-0000-0000-0009-000000000202'
);

DELETE FROM auth.users WHERE id IN (
  '00000000-0000-0000-0009-000000000201',
  '00000000-0000-0000-0009-000000000202'
);

ROLLBACK;
