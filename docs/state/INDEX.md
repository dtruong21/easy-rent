# Project State Index

> **Snapshot vivant du projet EasyRent.** Maintenu par l'agent `state-keeper`. Source de vérité pour les agents — à lire AVANT de grep/scanner le codebase.

## Métadonnées

- **Dernière mise à jour** : 2026-06-02T12:00:00Z
- **Commit ref** : `8f1fe54` (fix/empty-states-ux — FEAT-009 couche données SQL en cours)
- **Branche** : `feature/documents-storage`
- **Phase projet** : FEAT-001 ✅ + FEAT-002 ✅ + FEAT-003 ✅ + FEAT-004 ✅ + FEAT-005 ✅ + FEAT-006 ✅ + FEAT-007 ✅ + FEAT-008 ✅ implémentées. FEAT-009 🚧 Phase 1 (couche données SQL + Storage) appliquée. FEAT-010–012 en backlog.

## Pointeurs

| Aspect du projet | Fichier |
|---|---|
| Schéma Postgres (tables, colonnes, RLS, fonctions) | [`SCHEMA.md`](SCHEMA.md) |
| Routes Flutter et widgets principaux | [`ROUTES.md`](ROUTES.md) |
| Features implémentées et statut | [`FEATURES.md`](FEATURES.md) |
| Dépendances (pubspec, Deno imports, CLI tools, hosting CSP) | [`DEPENDENCIES.md`](DEPENDENCIES.md) |
| Edge Functions déployées et planifiées | [`FUNCTIONS.md`](FUNCTIONS.md) |
| Material 3 theme config + dark mode fixes | [`THEME.md`](THEME.md) |

## Comment l'utiliser

**Tu es un agent IA travaillant sur EasyRent ?**

1. Lis ce fichier en premier. Repère la date de mise à jour.
2. Si la date est < 7 jours → fais confiance aux fichiers d'état listés ci-dessus.
3. Si la date est ≥ 7 jours OU manquante → flag-le à l'utilisateur et propose `/refresh-state` AVANT de continuer.
4. Ne grep/scan le codebase QUE si l'état ne couvre pas ton besoin.

**Économie attendue** : un agent qui consulte `SCHEMA.md` (200 tokens) au lieu de grep toutes les migrations (5000 tokens) divise sa consommation par 25.

## Quand mettre à jour cet état

- Après chaque feature mergée → `state-keeper` met à jour automatiquement
- Avant un sprint de features → `/refresh-state` pour reset propre
- Si un agent détecte une incohérence → flag immédiat à l'utilisateur

## Stack résumé

| Couche | Tech |
|---|---|
| Frontend | Flutter Web 3.x + Dart 3.11+ |
| State | Riverpod 2.6.0 |
| Navigation | GoRouter 14.6.0 + GoRouterRefreshStream (custom) |
| Auth | Supabase Auth (magic link via PKCE) |
| Backend | Supabase (Postgres + Auth + Storage) |
| PDF | pdf + printing packages |
| Build | build_runner + freezed + json_serializable |
| Hosting | Firebase Hosting (staging ✅, prod TBD) |
| CI/CD | GitHub Actions (ci.yml + deploy.yml avec build_runner step) |

## Changements majeurs FEAT-007 (Phase 1+2+3 — WIP)

**Status** : Branche feature/quittance-pdf, commit a4386d5. Phase 1 (SQL) appliquée 2026-05-31. Phase 2 (Edge Function) + Phase 3 (UI) en cours.

1. **Migrations SQL** (Phase 1, appliquée) :
   - `20260531172904_feat007_receipts.sql` (610 lignes) : table receipts + enum document_type + RPC void_receipt + bucket receipts/
   - `20260531200000_feat007_receipts_stale_bidirectional.sql` (152 lignes) : fix is_stale bidirectionnel (soft-delete + résurrection, FEAT-007 Round 2 E5)

2. **Table `receipts`** (public + dev) :
   - 16 colonnes (id, landlord_id, lease_id, payment_ids[], period_start/end, rent_cents, charges_cents, total_cents, document_type, pdf_path, generated_at, created_at, is_voided, voided_at, voided_reason, is_stale)
   - Enum `document_type` (quittance | recu)
   - 4 index stratégiques (landlord_id, lease_id, period_start_desc, payment_ids GIN)
   - 2 policies RLS (SELECT all, INSERT own landlord) — pas d'UPDATE ni DELETE (immuable)
   - Triggers : tr_00 (ownership), tr_01 (protect columns), tr_03 AFTER (is_stale recompute bidirectionnel)
   - RPC `void_receipt()` SECURITY DEFINER (annulation via RLS bypass)
   - Bucket Storage receipts/ (privé, PDF-only, 10MB, 2 policies)

3. **Edge Function generate-receipt** (Phase 2) :
   - `supabase/functions/generate-receipt/` (Deno TS)
   - Orchestration : fetch payments → build PDF (pdf-lib + loi 1989 AR 21) → upload Storage → INSERT receipts
   - Dépendances : pdf-lib@1.17.1, @supabase/supabase-js@2.45.0
   - Invocation : POST `/functions/v1/generate-receipt` avec JWT + `{lease_id, schema}`
   - Blockers fixes (Round 2) : CORS allowlist, timeout, privacy

4. **UI + Void Flow** (Phase 3) :
   - 18 fichiers Dart : `lib/features/receipts/` (domain, data, application, presentation)
   - Modèles : `receipt.dart` (freezed), `document_type.dart`, `receipt_generation_state.dart` (sealed union)
   - Providers : `lease_receipts_provider.dart` (AsyncNotifierProvider.family), `generate_receipt_controller.dart`, `void_receipt_controller.dart`
   - Routes : `/leases/:id/receipts` (LeaseReceiptsPage), `/profile` (ProfilePage paramètres bailleur)
   - Widgets : receipt_list_tile, receipt_preview_dialog, void_receipt_dialog, generate_receipt_button, profile_incomplete_dialog
   - Business logic : génération via Edge Function, voiding via RPC, is_stale tracking automatique

5. **Décisions tranchées** :
   - is_stale bidirectionnel : soft-delete → stale, résurrection → recompute (E5 FEAT-007 Round 2)
   - Immuabilité document : pas de DELETE (rétention légale 5 ans)
   - Bucket privé : URLs signées 5 min uniquement
   - document_type : enum SQL natif (validation + cohérence)
   - Profile validation : full_name obligatoire avant génération (loi 1989)

6. **Tests** :
   - RLS tests : rls_receipts.sql (en cours)
   - Unit tests : receipt.dart, receipt_generation, receipt_repository
   - Widget tests : lease_receipts_page, dialogs, generation flow
   - E2E : full cycle (create payments → generate → preview → void)

### Bugfixes post-FEAT-007 Phase 3 (commits dd1673e–e322c87)

1. **Theme bugfixes** (commits dd1673e, 870c335, b71cdfb) :
   - Problème : M3 textTheme opacity trop faible → texte invisible en dark mode (notamment RichText/TextSpan)
   - **Fix appliqué** : `app_theme.dart` rewritten pour forcer `textTheme.apply(bodyColor, displayColor)` + sous-thèmes explicites (AppBar, Card, ListTile, Dialog…)
   - Status : Workaround `ThemeMode.light` appliqué puis reverté (e322c87)

2. **Hosting CSP bugfix** (commit e322c87, issue #16) :
   - Problème : Google Fonts invisible car `fonts.gstatic.com` bloqué par CSP strict
   - **Fix appliqué** : `firebase.json` CSP étendue :
     - `font-src` : ajout `https://fonts.gstatic.com`
     - `connect-src` : ajout `https://fonts.gstatic.com`
   - Status : Déployé staging, issue #16 closed

### Incohérences détectées (FEAT-007 + bugfixes)

Aucune — state entièrement synchronisé avec code feature/quittance-pdf (commit e322c87).

## Changements majeurs FEAT-006 (Complétée)

1. **Migration SQL** : `supabase/migrations/20260531102202_feat006_payments.sql` (890 lignes)
   - Table `public.payments` et `dev.payments` (13 colonnes + 4 index + 3 policies RLS)
   - Trigger `tr_00_assert_payment_lease_ownership()` (SECURITY DEFINER, cross-FK validation)
   - Trigger `tr_01_prevent_protected_columns_change()` et `tr_02_set_updated_at()` réutilisées
   - RPC `soft_delete_payment()` SECURITY DEFINER (GRANT authenticated, REVOKE PUBLIC)
   - 31 tests RLS dans `supabase/tests/rls_payments.sql`

2. **15 nouveaux fichiers Dart** : `lib/features/payments/`
   - Domain : `payment.dart` (freezed model + extensions), `payment_method.dart` (enum SQL), `payment_form_state.dart` (sealed union)
   - Data : `payment_repository.dart` (listForLease/getById/create/update/archive)
   - Application : `lease_payments_provider.dart` (AsyncNotifierProvider.family), `payment_detail_provider.dart`, `payment_form_controller.dart` (StateNotifier)
   - Presentation : `payment_form_page.dart`, `payment_edit_page.dart`, `payment_form.dart`, `payment_list_section.dart`, `payment_list_tile.dart`, `payment_amount_warning.dart`

3. **2 nouvelles routes GoRouter** :
   - `/leases/:id/payments/new` → `PaymentFormPage`
   - `/leases/:id/payments/:pid/edit` → `PaymentEditPage`

4. **Modèle `Payment`** : freezed + json_serializable, snake_case via `@JsonKey`
   - Montants en centimes d'euro (integer, jamais double)
   - Dates période en `date` Postgres (YYYY-MM-DD)
   - PaymentMethod enum (virement, cheque, especes, prelevement, autre)
   - Helpers pour conversion date ↔ JSON

5. **Décisions produit tranchées** :
   - Paiements partiels libres (pas de vérification "montant ≤ loyer+charges")
   - Doublons période autorisés (pas de UNIQUE sur (lease_id, period_start, period_end))
   - paid_at autorisée dans le futur (prélèvements programmés)
   - Paiement sur bail clôturé autorisé au niveau DB (régularisation), bouton UI désactivé
   - Soft-delete via RPC uniquement, pas de hard-delete

6. **RLS exhaustive** : 3 policies sur payments (SELECT/INSERT/UPDATE, pas de DELETE)
   - SELECT : `landlord_id = auth.uid() AND deleted_at IS NULL`
   - INSERT : `landlord_id = auth.uid()`
   - UPDATE : USING `landlord_id = auth.uid() AND deleted_at IS NULL` / WITH CHECK `landlord_id = auth.uid()`

7. **Index stratégiques** :
   - `idx_*_payments_landlord_id` (filtrage RLS)
   - `idx_*_payments_lease_id` (listage paiements d'un bail)
   - `idx_*_payments_period_start_desc` (tri par période décroissante)
   - `idx_*_payments_active_partial` (paiements non supprimés — requête fréquente)

8. **Tests** :
   - 31 RLS tests dans `supabase/tests/rls_payments.sql` (SELECT/INSERT/UPDATE ownership)
   - Unit tests : `payment_test.dart`, `payment_method_test.dart`, `payment_form_validators_test.dart`, `payment_repository_test.dart`
   - Widget tests : `payment_form_test.dart`, `payment_list_section_test.dart`
   - LeaseDetailPage enrichie avec `PaymentListSection` (button disabled si lease fermé)

### Incohérences détectées

Aucune incohérence — état entièrement cohérent avec code post-FEAT-006.

Blockers pré-release B1 du code-reviewer résolus :
1. ✅ INDEX.md : commit bumped vers 2a18458, phase updated (FEAT-006 ✅)
2. ✅ FEATURES.md : FEAT-006 corrigée "CRUD paiements de loyer" (pas "Quittance PDF"), quittance PDF = FEAT-007 backlog
3. ✅ SCHEMA.md : table `payments` (public + dev) complètement indexée
4. ✅ ROUTES.md : 2 routes paiements ajoutées

## État de la base de code

- Code matches state — synchronisé avec feature/quittance-pdf (commit a4386d5)
- ~6000+ lignes de tests totales (31 RLS payments + ~31 RLS receipts en cours + unit/widget)
- RLS validée sur Postgres côté backend (payments: 31 tests, receipts: en cours)
- Edge Function implémentée : generate-receipt (Phase 2, Deno TS)
- Flutter Phase 3 : UI + void flow implémentée (18 fichiers Dart)
- is_stale bidirectionnel fixé (FEAT-007 Round 2 E5)
- Backlog : FEAT-008 (email send-receipt), FEAT-009 (storage), FEAT-010 (dashboard), FEAT-011 (PWA polish), FEAT-012 (prod release)
