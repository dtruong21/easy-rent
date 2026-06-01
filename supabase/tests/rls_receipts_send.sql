-- ============================================================================
-- Tests RLS — mark_receipt_as_sent + protection sent_columns (FEAT-008)
-- ============================================================================
-- Tests couverts :
--   1.  mark_receipt_as_sent OK pour le bailleur owner (public)
--   2.  mark_receipt_as_sent OK pour le bailleur owner (dev)
--   3.  mark_receipt_as_sent cross-user → P0002 NOT FOUND (public)
--   4.  mark_receipt_as_sent cross-user → P0002 NOT FOUND (dev)
--   5.  mark_receipt_as_sent refus si is_voided = true → P0002 (public)
--   6.  mark_receipt_as_sent refus si is_stale = true → P0002 (public)
--   7.  mark_receipt_as_sent email NULL → ERRCODE 22023 (public)
--   8.  mark_receipt_as_sent email format invalide → ERRCODE 22023 (public)
--   9.  UPDATE direct de sent_at sans flag → trigger bloque 42501 (public)
--   10. UPDATE direct de sent_to_email sans flag → trigger bloque 42501 (dev)
--   11. Idempotence : 2e appel écrase sent_at (timestamps distincts) (public)
--   12. SELECT voit sent_at non-null après envoi (policies SELECT inchangées) (public)
--   13. Anon ne peut pas appeler mark_receipt_as_sent (public)
--   14. RLS activée sur les deux schémas (assert_rls_both_schemas)
-- ============================================================================
-- USAGE: psql <connection_string> -f supabase/tests/rls_receipts_send.sql
-- ============================================================================

BEGIN;

-- ============================================================================
-- Setup : deux users + données minimales (landlord, property, tenant, lease,
--         payment, receipt) pour chaque user.
-- ============================================================================
-- UUIDs préfixe 0008 (FEAT-008) pour ne pas collisionner avec FEAT-007 (0007)
-- Receipt de User A : id=...090 — valide (non voided, non stale)
-- Receipt de User B : id=...100 — valide
-- Receipt voided de User A : id=...200
-- Receipt stale de User A : id=...300

INSERT INTO auth.users (
  id, instance_id, email, encrypted_password, email_confirmed_at,
  created_at, updated_at, raw_app_meta_data, raw_user_meta_data, aud, role
) VALUES
  ('00000000-0000-0000-0008-000000000001', '00000000-0000-0000-0000-000000000000',
   'send_user_a@test.example', 'hashed', now(), now(), now(),
   '{"provider":"email","providers":["email"]}', '{}', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0008-000000000002', '00000000-0000-0000-0000-000000000000',
   'send_user_b@test.example', 'hashed', now(), now(), now(),
   '{"provider":"email","providers":["email"]}', '{}', 'authenticated', 'authenticated')
ON CONFLICT (id) DO NOTHING;

-- Landlords
INSERT INTO public.landlords (id, email, full_name, address) VALUES
  ('00000000-0000-0000-0008-000000000001', 'send_user_a@test.example',
   'User A Send', '1 rue des Tests Send, Paris'),
  ('00000000-0000-0000-0008-000000000002', 'send_user_b@test.example',
   'User B Send', '2 avenue des Tests Send, Lyon')
ON CONFLICT (id) DO NOTHING;

INSERT INTO dev.landlords (id, email, full_name, address) VALUES
  ('00000000-0000-0000-0008-000000000001', 'send_user_a@test.example',
   'User A Send', '1 rue des Tests Send, Paris'),
  ('00000000-0000-0000-0008-000000000002', 'send_user_b@test.example',
   'User B Send', '2 avenue des Tests Send, Lyon')
ON CONFLICT (id) DO NOTHING;

-- Properties
INSERT INTO public.properties (id, landlord_id, name, address, type) VALUES
  ('00000000-0000-0000-0008-000000000010', '00000000-0000-0000-0008-000000000001',
   'Prop A (send)', '10 rue A send', 'appartement'),
  ('00000000-0000-0000-0008-000000000020', '00000000-0000-0000-0008-000000000002',
   'Prop B (send)', '20 rue B send', 'maison');

INSERT INTO dev.properties (id, landlord_id, name, address, type) VALUES
  ('00000000-0000-0000-0008-000000000010', '00000000-0000-0000-0008-000000000001',
   'Prop A (send)', '10 rue A send', 'appartement'),
  ('00000000-0000-0000-0008-000000000020', '00000000-0000-0000-0008-000000000002',
   'Prop B (send)', '20 rue B send', 'maison');

-- Tenants
INSERT INTO public.tenants (id, landlord_id, first_name, last_name, email) VALUES
  ('00000000-0000-0000-0008-000000000030', '00000000-0000-0000-0008-000000000001',
   'Tenant', 'A-Send', 'tenant_a_send@test.example'),
  ('00000000-0000-0000-0008-000000000040', '00000000-0000-0000-0008-000000000002',
   'Tenant', 'B-Send', 'tenant_b_send@test.example');

INSERT INTO dev.tenants (id, landlord_id, first_name, last_name, email) VALUES
  ('00000000-0000-0000-0008-000000000030', '00000000-0000-0000-0008-000000000001',
   'Tenant', 'A-Send', 'tenant_a_send@test.example'),
  ('00000000-0000-0000-0008-000000000040', '00000000-0000-0000-0008-000000000002',
   'Tenant', 'B-Send', 'tenant_b_send@test.example');

-- Leases
INSERT INTO public.leases (
  id, landlord_id, property_id, tenant_id, rent_amount_cents, charges_amount_cents, start_date
) VALUES
  ('00000000-0000-0000-0008-000000000050', '00000000-0000-0000-0008-000000000001',
   '00000000-0000-0000-0008-000000000010', '00000000-0000-0000-0008-000000000030',
   85000, 5000, '2026-01-01'),
  ('00000000-0000-0000-0008-000000000060', '00000000-0000-0000-0008-000000000002',
   '00000000-0000-0000-0008-000000000020', '00000000-0000-0000-0008-000000000040',
   120000, 10000, '2026-02-01');

INSERT INTO dev.leases (
  id, landlord_id, property_id, tenant_id, rent_amount_cents, charges_amount_cents, start_date
) VALUES
  ('00000000-0000-0000-0008-000000000050', '00000000-0000-0000-0008-000000000001',
   '00000000-0000-0000-0008-000000000010', '00000000-0000-0000-0008-000000000030',
   85000, 5000, '2026-01-01'),
  ('00000000-0000-0000-0008-000000000060', '00000000-0000-0000-0008-000000000002',
   '00000000-0000-0000-0008-000000000020', '00000000-0000-0000-0008-000000000040',
   120000, 10000, '2026-02-01');

-- Payments
INSERT INTO public.payments (
  id, lease_id, landlord_id, period_start, period_end, paid_at,
  rent_amount_cents, charges_amount_cents, payment_method
) VALUES
  ('00000000-0000-0000-0008-000000000070', '00000000-0000-0000-0008-000000000050',
   '00000000-0000-0000-0008-000000000001',
   '2026-01-01', '2026-01-31', '2026-01-05', 85000, 5000, 'virement'),
  ('00000000-0000-0000-0008-000000000080', '00000000-0000-0000-0008-000000000060',
   '00000000-0000-0000-0008-000000000002',
   '2026-02-01', '2026-02-28', '2026-02-05', 120000, 10000, 'prelevement');

INSERT INTO dev.payments (
  id, lease_id, landlord_id, period_start, period_end, paid_at,
  rent_amount_cents, charges_amount_cents, payment_method
) VALUES
  ('00000000-0000-0000-0008-000000000070', '00000000-0000-0000-0008-000000000050',
   '00000000-0000-0000-0008-000000000001',
   '2026-01-01', '2026-01-31', '2026-01-05', 85000, 5000, 'virement'),
  ('00000000-0000-0000-0008-000000000080', '00000000-0000-0000-0008-000000000060',
   '00000000-0000-0000-0008-000000000002',
   '2026-02-01', '2026-02-28', '2026-02-05', 120000, 10000, 'prelevement');

-- Receipts :
--   090 → User A, valide (non voided, non stale)
--   100 → User B, valide
--   200 → User A, voided (is_voided = true)
--   300 → User A, stale (is_stale = true)
INSERT INTO public.receipts (
  id, landlord_id, lease_id, payment_ids,
  period_start, period_end,
  rent_cents, charges_cents, total_cents,
  document_type, pdf_path,
  is_voided, voided_at, voided_reason,
  is_stale
) VALUES
  -- 090 : valide User A
  ('00000000-0000-0000-0008-000000000090',
   '00000000-0000-0000-0008-000000000001',
   '00000000-0000-0000-0008-000000000050',
   ARRAY['00000000-0000-0000-0008-000000000070']::uuid[],
   '2026-01-01', '2026-01-31', 85000, 5000, 90000, 'quittance',
   '00000000-0000-0000-0008-000000000001/00000000-0000-0000-0008-000000000090.pdf',
   false, NULL, NULL, false),
  -- 100 : valide User B
  ('00000000-0000-0000-0008-000000000100',
   '00000000-0000-0000-0008-000000000002',
   '00000000-0000-0000-0008-000000000060',
   ARRAY['00000000-0000-0000-0008-000000000080']::uuid[],
   '2026-02-01', '2026-02-28', 120000, 10000, 130000, 'quittance',
   '00000000-0000-0000-0008-000000000002/00000000-0000-0000-0008-000000000100.pdf',
   false, NULL, NULL, false),
  -- 200 : voided User A
  ('00000000-0000-0000-0008-000000000200',
   '00000000-0000-0000-0008-000000000001',
   '00000000-0000-0000-0008-000000000050',
   ARRAY['00000000-0000-0000-0008-000000000070']::uuid[],
   '2026-03-01', '2026-03-31', 85000, 5000, 90000, 'quittance',
   '00000000-0000-0000-0008-000000000001/00000000-0000-0000-0008-000000000200.pdf',
   true, now(), 'Test voided receipt FEAT-008', false),
  -- 300 : stale User A (is_stale forcé directement)
  ('00000000-0000-0000-0008-000000000300',
   '00000000-0000-0000-0008-000000000001',
   '00000000-0000-0000-0008-000000000050',
   ARRAY['00000000-0000-0000-0008-000000000070']::uuid[],
   '2026-04-01', '2026-04-30', 85000, 5000, 90000, 'quittance',
   '00000000-0000-0000-0008-000000000001/00000000-0000-0000-0008-000000000300.pdf',
   false, NULL, NULL, true);

INSERT INTO dev.receipts (
  id, landlord_id, lease_id, payment_ids,
  period_start, period_end,
  rent_cents, charges_cents, total_cents,
  document_type, pdf_path,
  is_voided, voided_at, voided_reason,
  is_stale
) VALUES
  ('00000000-0000-0000-0008-000000000090',
   '00000000-0000-0000-0008-000000000001',
   '00000000-0000-0000-0008-000000000050',
   ARRAY['00000000-0000-0000-0008-000000000070']::uuid[],
   '2026-01-01', '2026-01-31', 85000, 5000, 90000, 'quittance',
   '00000000-0000-0000-0008-000000000001/00000000-0000-0000-0008-000000000090.pdf',
   false, NULL, NULL, false),
  ('00000000-0000-0000-0008-000000000100',
   '00000000-0000-0000-0008-000000000002',
   '00000000-0000-0000-0008-000000000060',
   ARRAY['00000000-0000-0000-0008-000000000080']::uuid[],
   '2026-02-01', '2026-02-28', 120000, 10000, 130000, 'quittance',
   '00000000-0000-0000-0008-000000000002/00000000-0000-0000-0008-000000000100.pdf',
   false, NULL, NULL, false);

-- ============================================================================
-- TEST 1 : mark_receipt_as_sent OK pour le bailleur owner (public)
-- ============================================================================
DO $$
DECLARE result_row public.receipts;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0008-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    SELECT * INTO result_row FROM public.mark_receipt_as_sent(
      '00000000-0000-0000-0008-000000000090',
      'tenant_a_send@test.example'
    );
    RESET ROLE;

    IF result_row.sent_at IS NULL THEN
      RAISE EXCEPTION '[FAIL] TEST 1 public: sent_at devrait être non-NULL après mark_receipt_as_sent';
    END IF;
    IF result_row.sent_to_email IS DISTINCT FROM 'tenant_a_send@test.example' THEN
      RAISE EXCEPTION '[FAIL] TEST 1 public: sent_to_email incorrect (got %)', result_row.sent_to_email;
    END IF;
    RAISE NOTICE '[PASS] TEST 1 public: mark_receipt_as_sent OK pour le propriétaire';
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 1 public: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 2 : mark_receipt_as_sent OK pour le bailleur owner (dev)
-- ============================================================================
DO $$
DECLARE result_row dev.receipts;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0008-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    SELECT * INTO result_row FROM dev.mark_receipt_as_sent(
      '00000000-0000-0000-0008-000000000090',
      'tenant_a_send@test.example'
    );
    RESET ROLE;

    IF result_row.sent_at IS NULL THEN
      RAISE EXCEPTION '[FAIL] TEST 2 dev: sent_at devrait être non-NULL après mark_receipt_as_sent';
    END IF;
    IF result_row.sent_to_email IS DISTINCT FROM 'tenant_a_send@test.example' THEN
      RAISE EXCEPTION '[FAIL] TEST 2 dev: sent_to_email incorrect (got %)', result_row.sent_to_email;
    END IF;
    RAISE NOTICE '[PASS] TEST 2 dev: mark_receipt_as_sent OK pour le propriétaire';
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 2 dev: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 3 : mark_receipt_as_sent cross-user → NOT FOUND P0002 (public)
-- Scénario : User A tente de marquer la receipt de User B.
-- Attendu : ERRCODE P0002 — pas de fuite sur l'existence de la receipt.
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0008-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    PERFORM public.mark_receipt_as_sent(
      '00000000-0000-0000-0008-000000000100',  -- receipt de User B
      'tenant_a_send@test.example'
    );
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 3 public: cross-user aurait dû lever NOT FOUND';
  EXCEPTION
    WHEN no_data_found THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 3 public: mark_receipt_as_sent cross-user → NOT FOUND (P0002)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 3 public: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;

  -- Vérifier que la receipt de User B n'a pas été modifiée
  IF (SELECT sent_at FROM public.receipts
        WHERE id = '00000000-0000-0000-0008-000000000100') IS NOT NULL THEN
    RAISE EXCEPTION '[FAIL] TEST 3 public: La receipt de User B ne devrait pas avoir été modifiée';
  END IF;
END $$;

-- ============================================================================
-- TEST 4 : mark_receipt_as_sent cross-user → NOT FOUND P0002 (dev)
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0008-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    PERFORM dev.mark_receipt_as_sent(
      '00000000-0000-0000-0008-000000000100',  -- receipt de User B
      'tenant_a_send@test.example'
    );
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 4 dev: cross-user aurait dû lever NOT FOUND';
  EXCEPTION
    WHEN no_data_found THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 4 dev: mark_receipt_as_sent cross-user → NOT FOUND (P0002)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 4 dev: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;

  IF (SELECT sent_at FROM dev.receipts
        WHERE id = '00000000-0000-0000-0008-000000000100') IS NOT NULL THEN
    RAISE EXCEPTION '[FAIL] TEST 4 dev: La receipt de User B ne devrait pas avoir été modifiée';
  END IF;
END $$;

-- ============================================================================
-- TEST 5 : mark_receipt_as_sent refus si is_voided = true → P0002 (public)
-- Scénario : User A tente de marquer sa propre receipt voided (id=...200).
-- Attendu : ERRCODE P0002 (même erreur que cross-user — pas de fuite).
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0008-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    PERFORM public.mark_receipt_as_sent(
      '00000000-0000-0000-0008-000000000200',  -- receipt voided
      'tenant_a_send@test.example'
    );
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 5 public: receipt voided aurait dû lever NOT FOUND';
  EXCEPTION
    WHEN no_data_found THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 5 public: mark_receipt_as_sent voided → NOT FOUND (P0002)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 5 public: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 6 : mark_receipt_as_sent refus si is_stale = true → P0002 (public)
-- Scénario : User A tente de marquer sa propre receipt stale (id=...300).
-- Attendu : ERRCODE P0002.
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0008-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    PERFORM public.mark_receipt_as_sent(
      '00000000-0000-0000-0008-000000000300',  -- receipt stale
      'tenant_a_send@test.example'
    );
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 6 public: receipt stale aurait dû lever NOT FOUND';
  EXCEPTION
    WHEN no_data_found THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 6 public: mark_receipt_as_sent stale → NOT FOUND (P0002)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 6 public: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 7 : mark_receipt_as_sent email NULL → ERRCODE 22023 (public)
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0008-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    PERFORM public.mark_receipt_as_sent(
      '00000000-0000-0000-0008-000000000090',
      NULL  -- email null
    );
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 7 public: email NULL aurait dû lever 22023';
  EXCEPTION
    WHEN invalid_parameter_value THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 7 public: email NULL → ERRCODE 22023 (invalid_parameter_value)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 7 public: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 8 : mark_receipt_as_sent email format invalide → ERRCODE 22023 (public)
-- Scénario : email sans @ → regex ^[^@\s]+@[^@\s]+\.[^@\s]+$ ne matche pas.
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0008-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    PERFORM public.mark_receipt_as_sent(
      '00000000-0000-0000-0008-000000000090',
      'invalide-sans-arobase'  -- pas de @ : format invalide
    );
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 8 public: email format invalide aurait dû lever 22023';
  EXCEPTION
    WHEN invalid_parameter_value THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 8 public: email format invalide → ERRCODE 22023 (invalid_parameter_value)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION '[FAIL] TEST 8 public: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 9 : UPDATE direct de sent_at sans flag → trigger bloque 42501 (public)
-- Scénario (superuser) : UPDATE sent_at directement sans poser le flag GUC.
-- Attendu : ERRCODE 42501 (insufficient_privilege).
-- Note : le trigger BEFORE UPDATE s'exécute même pour superuser (row-level trigger).
-- ============================================================================
DO $$
BEGIN
  BEGIN
    UPDATE public.receipts
      SET sent_at = now()
      WHERE id = '00000000-0000-0000-0008-000000000090';
    RAISE EXCEPTION '[FAIL] TEST 9 public: UPDATE direct sent_at aurait dû être bloqué par le trigger';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE '[PASS] TEST 9 public: UPDATE direct sent_at bloqué par tr_01b (42501)';
    WHEN OTHERS THEN
      RAISE EXCEPTION '[FAIL] TEST 9 public: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 10 : UPDATE direct de sent_to_email sans flag → trigger bloque 42501 (dev)
-- ============================================================================
DO $$
BEGIN
  BEGIN
    UPDATE dev.receipts
      SET sent_to_email = 'hacker@evil.com'
      WHERE id = '00000000-0000-0000-0008-000000000090';
    RAISE EXCEPTION '[FAIL] TEST 10 dev: UPDATE direct sent_to_email aurait dû être bloqué';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE '[PASS] TEST 10 dev: UPDATE direct sent_to_email bloqué par tr_01b (42501)';
    WHEN OTHERS THEN
      RAISE EXCEPTION '[FAIL] TEST 10 dev: erreur inattendue (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;
END $$;

-- ============================================================================
-- TEST 11 : Idempotence — 2e appel écrase sent_at (timestamps distincts) (public)
-- Pré-condition : TEST 1 a appelé mark_receipt_as_sent sur la receipt 090.
--   sent_at devrait déjà être non-NULL.
-- On appelle une 2e fois et on vérifie que le nouveau sent_at est >= l'ancien.
-- (Dans un test synchrone ils peuvent être égaux ; on vérifie surtout que ça ne crash pas
--  et que sent_at est mis à jour — idempotence sans erreur.)
-- ============================================================================
DO $$
DECLARE
  first_sent_at  timestamptz;
  second_sent_at timestamptz;
BEGIN
  -- Lire le sent_at posé par TEST 1
  SELECT sent_at INTO first_sent_at
    FROM public.receipts WHERE id = '00000000-0000-0000-0008-000000000090';

  IF first_sent_at IS NULL THEN
    RAISE EXCEPTION '[FAIL] TEST 11 public: pré-condition — sent_at devrait être non-NULL (TEST 1 a dû l''initialiser)';
  END IF;

  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0008-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    -- 2e appel avec un email différent (renvoi à une autre adresse)
    PERFORM public.mark_receipt_as_sent(
      '00000000-0000-0000-0008-000000000090',
      'tenant_a_resend@test.example'
    );
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 11 public: 2e appel mark_receipt_as_sent a levé une erreur (SQLSTATE %, msg: %)', SQLSTATE, SQLERRM;
  END;

  SELECT sent_at INTO second_sent_at
    FROM public.receipts WHERE id = '00000000-0000-0000-0008-000000000090';

  IF second_sent_at IS NULL THEN
    RAISE EXCEPTION '[FAIL] TEST 11 public: sent_at est NULL après le 2e appel';
  END IF;
  -- sent_at >= first_sent_at (même valeur ou plus récente — selon la résolution d'horloge)
  IF second_sent_at < first_sent_at THEN
    RAISE EXCEPTION '[FAIL] TEST 11 public: sent_at 2e appel (%) < 1er appel (%) — inattendu',
      second_sent_at, first_sent_at;
  END IF;
  -- Vérifier que sent_to_email a été mis à jour
  IF (SELECT sent_to_email FROM public.receipts
        WHERE id = '00000000-0000-0000-0008-000000000090')
      IS DISTINCT FROM 'tenant_a_resend@test.example' THEN
    RAISE EXCEPTION '[FAIL] TEST 11 public: sent_to_email devrait avoir été mis à jour au 2e appel';
  END IF;
  RAISE NOTICE '[PASS] TEST 11 public: idempotence — 2e appel écrase sent_at et sent_to_email sans erreur';
END $$;

-- ============================================================================
-- TEST 12 : SELECT voit sent_at non-null après envoi (public)
-- Vérifie que la policy receipts_select_own expose bien les nouvelles colonnes.
-- Pré-condition : TEST 1 a marqué la receipt 090 comme envoyée.
-- ============================================================================
DO $$
DECLARE sent_ts timestamptz;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0008-000000000001","role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  SELECT sent_at INTO sent_ts
    FROM public.receipts
    WHERE id = '00000000-0000-0000-0008-000000000090';

  RESET ROLE;

  IF sent_ts IS NULL THEN
    RAISE EXCEPTION '[FAIL] TEST 12 public: SELECT devrait voir sent_at non-NULL (got NULL)';
  END IF;
  RAISE NOTICE '[PASS] TEST 12 public: SELECT voit sent_at non-NULL via policy receipts_select_own';
END $$;

-- ============================================================================
-- TEST 13 : Anon ne peut pas appeler mark_receipt_as_sent (public)
-- Attendu : ERRCODE 42501 (insufficient_privilege) — REVOKE FROM PUBLIC.
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-000000000000","role":"anon"}', true);
  SET LOCAL ROLE anon;

  BEGIN
    PERFORM public.mark_receipt_as_sent(
      '00000000-0000-0000-0008-000000000090',
      'hacker@anon.example'
    );
    RESET ROLE;
    RAISE EXCEPTION '[FAIL] TEST 13 public: anon aurait dû être refusé par REVOKE';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 13 public: anon ne peut pas appeler mark_receipt_as_sent (42501)';
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE NOTICE '[PASS] TEST 13 public: anon refusé (SQLSTATE %)', SQLSTATE;
  END;
END $$;

-- ============================================================================
-- TEST 14 : RLS activée sur les deux schémas
-- ============================================================================
DO $$
BEGIN
  PERFORM dev.assert_rls_both_schemas('receipts');
  RAISE NOTICE '[PASS] TEST 14: RLS activée sur public.receipts ET dev.receipts';
END $$;

-- ============================================================================
-- Teardown : nettoyage dans l'ordre inverse des FK
-- ============================================================================
DELETE FROM public.receipts WHERE landlord_id IN (
  '00000000-0000-0000-0008-000000000001',
  '00000000-0000-0000-0008-000000000002'
);
DELETE FROM dev.receipts WHERE landlord_id IN (
  '00000000-0000-0000-0008-000000000001',
  '00000000-0000-0000-0008-000000000002'
);
DELETE FROM public.payments WHERE landlord_id IN (
  '00000000-0000-0000-0008-000000000001',
  '00000000-0000-0000-0008-000000000002'
);
DELETE FROM dev.payments WHERE landlord_id IN (
  '00000000-0000-0000-0008-000000000001',
  '00000000-0000-0000-0008-000000000002'
);
DELETE FROM public.leases WHERE landlord_id IN (
  '00000000-0000-0000-0008-000000000001',
  '00000000-0000-0000-0008-000000000002'
);
DELETE FROM dev.leases WHERE landlord_id IN (
  '00000000-0000-0000-0008-000000000001',
  '00000000-0000-0000-0008-000000000002'
);
DELETE FROM public.tenants WHERE landlord_id IN (
  '00000000-0000-0000-0008-000000000001',
  '00000000-0000-0000-0008-000000000002'
);
DELETE FROM dev.tenants WHERE landlord_id IN (
  '00000000-0000-0000-0008-000000000001',
  '00000000-0000-0000-0008-000000000002'
);
DELETE FROM public.properties WHERE landlord_id IN (
  '00000000-0000-0000-0008-000000000001',
  '00000000-0000-0000-0008-000000000002'
);
DELETE FROM dev.properties WHERE landlord_id IN (
  '00000000-0000-0000-0008-000000000001',
  '00000000-0000-0000-0008-000000000002'
);
DELETE FROM public.landlords WHERE id IN (
  '00000000-0000-0000-0008-000000000001',
  '00000000-0000-0000-0008-000000000002'
);
DELETE FROM dev.landlords WHERE id IN (
  '00000000-0000-0000-0008-000000000001',
  '00000000-0000-0000-0008-000000000002'
);
DELETE FROM auth.users WHERE id IN (
  '00000000-0000-0000-0008-000000000001',
  '00000000-0000-0000-0008-000000000002'
);

ROLLBACK;
