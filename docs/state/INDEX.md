# Project State Index

> **Snapshot vivant du projet EasyRent.** Maintenu par l'agent `state-keeper`. Source de vérité pour les agents — à lire AVANT de grep/scanner le codebase.

## Métadonnées

- **Dernière mise à jour** : 2026-06-22T12:00:00Z
- **Commit ref** : `643789c` (Merge pull request #23 from dtruong21/feature/dashboard-pwa-prod-setup)
- **Branche** : `develop` (FEAT-008 pivot en branche `feature/feat-008-web-share-pivot`)
- **Phase projet** : FEAT-001–010 implémentées. FEAT-001–009 ✅ mergés. FEAT-010 ✅ mergée 2026-06-22. **FEAT-008 refactorisée 2026-06-22 (pivot Web Share API)**. FEAT-011–012 en backlog.

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
| Hosting | Firebase Hosting (staging ✅, prod ready) |
| CI/CD | GitHub Actions (ci.yml + deploy.yml + migrate-prod.yml) |

## Changements majeurs FEAT-010 (Complétée 2026-06-22)

**Status** : ✅ DONE (mergée develop commit 643789c)

1. **Dashboard refonte** (Section A) :
   - 4 KPI cards : loyers mois encaissé/dû, retards (locataires 35j sans paiement), renouvellements 30j, documents en attente
   - Mini-barchart 6 mois (encaissé vs dû, `fl_chart` v0.69.0)
   - Activité récente (top 5 paiements/quittances/documents par date DESC)
   - Onboarding « Premiers pas » (affiché si 0 bien + 0 locataire + 0 bail)
   - 18 fichiers Dart, 7 nouveaux tests widget (69 assertions)

2. **PWA Polish** (Section B) :
   - `manifest.json` complètement rempli (name, description, background_color #0F766E, icons 192+512 + maskable)
   - Icônes placeholder « ER » générées via script ImageMagick (192/512 px)
   - Install prompt JS interop via `web` package (beforeinstallprompt + matchMedia)
   - Dismiss persisté via `shared_preferences` (1 semaine avant ré-affichage)
   - `web/index.html` : manifest ref + background color cohérente
   - 7 fichiers Dart (pwa feature), 2 nouvelles dépendances (shared_preferences 2.3.5, web 1.1.0)

3. **Prod setup** (Section C) :
   - `.github/workflows/migrate-prod.yml` (nouvelle) : workflow_dispatch + input confirm=yes/no → `supabase db push`
   - `.github/workflows/deploy.yml` (modifié) : +31 lignes, build staging + prod branche, firebase deploy avec `--only hosting:staging` vs `--only hosting:prod`
   - `docs/PROD_DEPLOY_CHECKLIST.md` (nouvelle) : 117 lignes, 22 étapes, déploiement + rollback
   - `docs/RUNBOOK_PROD_DEPLOY.md` (nouvelle) : 183 lignes, procédure step-by-step avec commands exactes
   - `dart-defines.prod.example.json` (nouvelle) : template variables Firebase projet prod
   - `/privacy` page enrichie avec RGPD + export/effacement GDPR (190+ lignes)
   - `firebase.json` (modifié) : CSP étendue (fonts.gstatic.com) + cache strategy SW

4. **Tests ajoutés** :
   - 69 nouveaux tests (dashboard: 27 unit + 42 widget)
   - Integration test router_guard (4 assertions, pas de changement)

3. **Suppression Edge Function** : `supabase/functions/send-receipt/` (Resend) a été supprimée
   - Plus de dépendance backend email, plus de secret API key
   - RPC `mark_receipt_as_sent` inchangée — appelée côté client APRÈS partage réussi

4. **Décisions FEAT-010** :
   - KPI "Documents en attente" = count(category='autre' AND deleted_at IS NULL) — proxy MVP
   - "Retards" = locataires sans paiement depuis 35j (simplification MVP)
   - Activité récente = UNION payments + receipts + documents (5 items top)
   - Onboarding = affiché seulement si count(properties) + count(tenants) + count(leases) = 0

5. **Décisions FEAT-008 pivot** :
   - Partage natif Web Share API = intention utilisateur (pas preuve serveur d'envoi)
   - RPC `mark_receipt_as_sent` appelée asynchrone APRÈS succès du picker
   - Idempotence : 2e partage écrase `sent_at` (marque le dernier partage)
   - Zéro secret backend = go-live sans attente domaine Resend

6. **Incohérences détectées** :
   - Aucune — state entièrement cohérent avec code (643789c)

## Changements majeurs FEAT-009 (Complétée)

**Status** : ✅ DONE (mergée develop 2026-06-17, commit 57c8164)

1. **Migration SQL** : `supabase/migrations/20260602100520_feat009_documents.sql` (588 lignes)
   - Table `public.documents` / `dev.documents` (12 colonnes + 4 index + 2 policies RLS)
   - Enum `document_category` (bail_signe, etat_des_lieux, attestation_assurance, quittance_scannee, autre)
   - Bucket Storage privé `documents/` (chemins `{schema}/{landlord_id}/{document_id}.{ext}`)
   - RPC `soft_delete_document()` SECURITY DEFINER (retourne storage_path + hard_deleted)
   - Triggers : ownership check, protect immutable columns, legal_hold auto-calc

2. **15 fichiers Dart** : `lib/features/documents/`
   - Domain : `document.dart` (freezed), `document_category.dart`, `document_upload_state.dart`
   - Data : `document_repository.dart` (CRUD, Storage)
   - Application : providers (list, form controllers)
   - Presentation : upload form, list, preview, delete dialog

3. **Nouvelles routes GoRouter** :
   - `/documents` (non implémentée — route juste déclarée)

4. **RLS exhaustive** : 2 policies sur documents + 1 bucket Storage policy

## Changements majeurs FEAT-008 (Refactorisée — Pivot 2026-06-22)

**Status** : ✅ REFACTORED (pivot Web Share API native, branche `feature/feat-008-web-share-pivot`)

**Pivot justification** : Élimination dépendance Resend → zéro secret backend, pas de domaine DNS, meilleure UX native

1. **Web Share Service** (Flutter + Dart, native système)
   - JS interop `navigator.share()` + fallback `mailto://`
   - Récupère PDF depuis Storage, partage natif (Mail/Gmail/WhatsApp/etc.)
   - Zéro secret backend requis, zéro serveur email

2. **5 fichiers Dart** : `lib/features/receipts/` (Web Share natif)
   - Service : `web_share_service.dart` (JS interop)
   - Controller : `share_receipt_controller.dart` (StateNotifier)
   - State : `share_receipt_state.dart` (sealed freezed)
   - Widgets : `share_receipt_button.dart`, `confirm_resend_dialog.dart`
   - Tests : 3 fichiers (~25 tests)

## État de la base de code

- Code matches state — 100% synchronisé (643789c)
- 177 fichiers Dart, ~7000+ lignes de code métier
- 1074 tests (69 nouveaux FEAT-010), tous passing
- RLS validée : payments (31 tests), receipts (en cours), documents (en cours)
- 3 Edge Functions : generate-receipt ✅, send-receipt 🚧 (secrets attente), _shared (utils)
- Dashboard : refonte complète, 4 KPI + mini-chart + activité
- PWA : manifest complet, icônes, install prompt, offline-first
- Prod : migrate-prod workflow + checklist + runbook prêts
- Backlog : FEAT-011 (email récurrents), FEAT-012 (analytics avancées), P1 features (charges récupérables, crédits, etc.)

## Audit incohérences

À la date 2026-06-22 (après merge FEAT-010) :

- **✅ Aucune migration sans code correspondant** : toutes les 9 migrations ont des composants Dart ou RPC
- **✅ Aucune route sans feature** : 26 routes, 11 features implémentées
- **✅ Aucune table sans RLS** : landlords, properties, tenants, leases, payments, receipts, documents — 100% RLS
- **✅ Aucun dépendance non déclarée** : pubspec.yaml à jour (ajoute web, shared_preferences, fl_chart pour FEAT-010)
- **✅ Firestore CSP fixed** : fonts.gstatic.com dans firebase.json

## Prochaines étapes

- **Prod go-live** : ✅ FEAT-008 pivot = zéro blocker backend email. Déploiement web immédiat possible.
- **FEAT-011 (P1)** : Email récurrents / rappels paiements (cron Edge Function)
- **FEAT-012 (P1)** : Analytics avancées, export comptable
- **Dashboard vision** : Charts Stripe/Brex post-MVP (amorce architecturale en KpiCard.child)
- **Documentation post-pivot** : Voir `docs/plans/FEAT-008-email-quittance.md` pour détails complets pivot Web Share API
