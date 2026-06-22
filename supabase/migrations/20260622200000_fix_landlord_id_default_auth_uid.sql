-- ============================================================================
-- FIX — DEFAULT auth.uid() sur landlord_id de toutes les tables owner-scoped
-- ============================================================================
-- WHY: Le code client (PropertyRepository, TenantRepository, etc.) n'envoie
-- PAS landlord_id dans les payloads d'INSERT. Le commentaire "RLS WITH CHECK le
-- fixe à auth.uid()" est FAUX — WITH CHECK valide mais ne SET pas. Sans DEFAULT,
-- landlord_id reste NULL, et la WITH CHECK (landlord_id = auth.uid()) évalue
-- NULL = uuid → NULL → traité comme FALSE → RLS denial 42501 "permission denied".
--
-- BUG découvert via QA staging FEAT-012 le 2026-06-22 : nouvel utilisateur ne
-- peut créer aucune entité ("Vous n'avez pas les droits pour effectuer cette
-- action"). Bug latent depuis FEAT-002 — n'a jamais été détecté car les
-- utilisateurs précédents ont été créés via Supabase Studio (service_role
-- bypass RLS) ou avec un code client qui passait landlord_id.
--
-- FIX : ajouter DEFAULT auth.uid() sur les colonnes landlord_id des 6 tables
-- owner-scoped (properties, tenants, leases, payments, receipts, documents),
-- dans les 2 schémas (public + dev). Quand le client INSERT sans landlord_id,
-- Postgres pose auth.uid() automatiquement, et WITH CHECK passe.
--
-- BACKFILL : insérer la ligne landlords manquante pour tout utilisateur déjà
-- créé via auth.users mais sans ligne landlords (cas typique : signup
-- FEAT-011 avant que le trigger handle_new_user() v2 ne soit appliqué côté
-- remote — la migration 20260622130000 était locale seulement jusqu'ici).
-- ============================================================================

-- ============================================================================
-- 1. DEFAULT auth.uid() sur les 6 tables × 2 schémas
-- ============================================================================

-- PROD (public)
ALTER TABLE public.properties ALTER COLUMN landlord_id SET DEFAULT auth.uid();
ALTER TABLE public.tenants    ALTER COLUMN landlord_id SET DEFAULT auth.uid();
ALTER TABLE public.leases     ALTER COLUMN landlord_id SET DEFAULT auth.uid();
ALTER TABLE public.payments   ALTER COLUMN landlord_id SET DEFAULT auth.uid();
ALTER TABLE public.receipts   ALTER COLUMN landlord_id SET DEFAULT auth.uid();
ALTER TABLE public.documents  ALTER COLUMN landlord_id SET DEFAULT auth.uid();

-- DEV (dev)
ALTER TABLE dev.properties ALTER COLUMN landlord_id SET DEFAULT auth.uid();
ALTER TABLE dev.tenants    ALTER COLUMN landlord_id SET DEFAULT auth.uid();
ALTER TABLE dev.leases     ALTER COLUMN landlord_id SET DEFAULT auth.uid();
ALTER TABLE dev.payments   ALTER COLUMN landlord_id SET DEFAULT auth.uid();
ALTER TABLE dev.receipts   ALTER COLUMN landlord_id SET DEFAULT auth.uid();
ALTER TABLE dev.documents  ALTER COLUMN landlord_id SET DEFAULT auth.uid();

-- ============================================================================
-- 2. Backfill landlords pour les utilisateurs orphelins
-- ============================================================================

INSERT INTO public.landlords (id, email, full_name)
SELECT u.id, u.email, COALESCE(NULLIF(TRIM(u.raw_user_meta_data->>'full_name'), ''), u.email)
FROM auth.users u
WHERE u.id NOT IN (SELECT id FROM public.landlords)
ON CONFLICT (id) DO NOTHING;

INSERT INTO dev.landlords (id, email, full_name)
SELECT u.id, u.email, COALESCE(NULLIF(TRIM(u.raw_user_meta_data->>'full_name'), ''), u.email)
FROM auth.users u
WHERE u.id NOT IN (SELECT id FROM dev.landlords)
ON CONFLICT (id) DO NOTHING;
