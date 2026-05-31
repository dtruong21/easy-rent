# Project State Index

> **Snapshot vivant du projet EasyRent.** Maintenu par l'agent `state-keeper`. Source de vérité pour les agents — à lire AVANT de grep/scanner le codebase.

## Métadonnées

- **Dernière mise à jour** : 2026-05-31T00:00:00Z
- **Commit ref** : `2a18458` (feat(payments): CRUD paiements de loyer (FEAT-006) (#8))
- **Branche** : `develop`
- **Phase projet** : FEAT-001 ✅ + FEAT-002 ✅ + FEAT-003 ✅ + FEAT-004 ✅ + FEAT-005 ✅ + FEAT-006 ✅ implémentées. FEAT-007–010 en backlog.

## Pointeurs

| Aspect du projet | Fichier |
|---|---|
| Schéma Postgres (tables, colonnes, RLS, fonctions) | [`SCHEMA.md`](SCHEMA.md) |
| Routes Flutter et widgets principaux | [`ROUTES.md`](ROUTES.md) |
| Features implémentées et statut | [`FEATURES.md`](FEATURES.md) |
| Dépendances (pubspec, Deno imports, CLI tools) | [`DEPENDENCIES.md`](DEPENDENCIES.md) |
| Edge Functions déployées et planifiées | [`FUNCTIONS.md`](FUNCTIONS.md) |

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

## Changements majeurs FEAT-006

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

- Code matches state — aucun drift détecté post-FEAT-006
- ~4200 lignes de tests totales (31 RLS + ~50 unitaires/widget)
- RLS validée sur Postgres côté backend (FEAT-006, 31 tests)
- Flutter stable — 6 features complètes, prêt pour FEAT-007 (quittance PDF + email)
- Backlog : FEAT-007 (PDF), FEAT-008 (email), FEAT-009 (storage), FEAT-010 (dashboard + prod)
