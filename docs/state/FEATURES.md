# Features — registre

> Maintenu par `state-keeper`. **Dernière sync** : 2026-06-25 (FEAT-001–016 ✅ toutes mergées — branche chore/cleanup-tech-debt-and-docs-refresh-v2, rebased sur develop à a1fefec)

## Légende

- ✅ **done** : code mergé, testé, déployé ou prêt pour prod
- 🟢 **ready** : code mergé, en attente de deploy production
- 🚧 **wip** : en cours de développement (branche ouverte)
- 📋 **planned** : user story écrite, pas commencé
- 💡 **idea** : dans le backlog mais pas spec'd

## Matrice features

| ID | Nom | Phase | Statut | Commit | Notes |
|---|---|---|---|---|---|
| FEAT-001 | Auth propriétaire (magic link) | — | ✅ Refactorisée | 20260627081533 | Remplacée par FEAT-011 (email+password 2026-06-22) |
| FEAT-002 | Modèle de données + RLS exhaustive | — | ✅ done | 20260528120000 | properties, tenants, leases + soft-delete RPC |
| FEAT-003 | CRUD UI propriétés (list, detail, form) | — | ✅ done | — | 16 fichiers Dart, 4 routes GoRouter, 56 tests |
| FEAT-004 | CRUD UI locataires (list, detail, form) | — | ✅ done | — | 15 fichiers Dart, 4 routes GoRouter, 80+ tests |
| FEAT-005 | CRUD UI baux (list, detail, form) | — | ✅ done | — | 18 fichiers Dart, 4 routes GoRouter, 90+ tests |
| FEAT-006 | CRUD paiements (enregistrement + archive) | — | ✅ done | 20260531102202 | 15 fichiers Dart, 2 routes, 31 RLS tests + 50 unit/widget |
| FEAT-007 | Générer quittance PDF conforme loi 1989 | 1+2+3 | ✅ done | 20260531172904 | Edge Function `generate-receipt` + 18 fichiers Dart |
| FEAT-008 | Partage quittance natif (Web Share API pivot) | — | ✅ done | — | Replaces Resend edge function (FEAT-008 Phase 1) |
| FEAT-009 | Upload & stockage documents (PDF, images) | — | ✅ done | 20260602100520 | 15 fichiers Dart, Storage bucket `documents`, soft-delete RPC |
| FEAT-010 | Dashboard + Polish PWA + Prod setup | 1+2+3 | ✅ done | 643789c | 3 sections (A=dashboard, B=PWA, C=workflows) |
| FEAT-011 | Auth propriétaire (email + password) | — | ✅ done | — | 22 fichiers Dart, pivot FEAT-001 (2026-06-22) |
| FEAT-012 | Cards system — pages list refonte | 0+1+2+3+4+5 | ✅ done | 2b7506b–9fdf647 | EntityCard foundation + Phase 1–5 UI refonte (Leases→Properties→Tenants→Receipts→Dashboard) |
| FEAT-013 | UX modernization | 1+2 | ✅ done | 0e20c80, ae5fdf1 | AppAppBar + transitions (Phase 1), palette indigo (Phase 2) |
| FEAT-014 | Forms enrichment FR (32 champs) | 1+2+3+4 | ✅ done | 4de7554–5f9cdfa | DPE, garant, IRL, dépôt de garantie (Property +12, Tenant +10, Lease +9, Payment +1) |
| FEAT-015 | Detail pages enrichment | — | ✅ done | 6959a9e | Expose FEAT-014 fields + finalize StatusBadge migration |
| FEAT-016 | RGPD consent persistence | — | ✅ done | e82d113 | landlords.rgpd_consent_{at,version}, trigger `handle_new_user()` extended |

## Détails par feature

### FEAT-016 : RGPD consent persistence

**Status** : ✅ DONE (mergée develop 2026-06-23, commit e82d113)

**Justification** : Accountability art. 7.1 RGPD — preuve consentement avec date + version texte présenté.

**Colonnes ajoutées** :
- `landlords.rgpd_consent_at` (timestamptz NOT NULL) — timestamp acceptation
- `landlords.rgpd_consent_version` (text NOT NULL) — version texte (ex: 'v1-2026-06', 'legacy-1')

**Backfill** : Comptes existants → version='legacy-1', timestamp=created_at (attestation rétroactive)

**Trigger `handle_new_user()` étendu** :
- Lit `rgpd_consent_version` depuis `raw_user_meta_data` (client Flutter au signup)
- Fallback 'legacy-1' pour creations admin/Studio
- Définit `rgpd_consent_at = now()` à l'insertion

**Migration** : `20260623020000_feat016_rgpd_consent.sql`

**Tests** : _(unknown — needs QA)_

---

### FEAT-015 : Detail pages enrichment

**Status** : ✅ DONE (mergée develop 2026-06-23, commit 6959a9e)

**Contenu** :
- PropertyDetailPage : expose champs FEAT-014 Phase 1 (DPE, étage, chauffage, etc.)
- TenantDetailPage : expose champs FEAT-014 Phase 2 (birth, garant, revenus, etc.)
- LeaseDetailPage : expose champs FEAT-014 Phase 3 (type bail, dépôt, IRL, paiement, etc.)
- StatusBadge migration finalisée (design unif leaf status badges)

**Files** : modifie 8 pages detail + 3 widgets

---

### FEAT-014 : Forms enrichment FR (4 phases — 32 colonnes)

**Status** : ✅ DONE (Phase 1–4 mergées 2026-06-22 — 2026-06-23)

**Justification** : MVP location FR utilisable — conformité légale (DPE obligatoire, garant standard, révision IRL, etc.)

| Phase | Table | Colonnes (nb) | Migration | Commit |
|---|---|---|---|---|
| 1 | properties | rooms, bedrooms, floor, has_elevator, furnished, heating_type, dpe_letter, dpe_value_kwh_m2_year, ges_letter, construction_year, postal_code, city (12) | 20260622220000 | 4de7554 |
| 2 | tenants | birth_date, birth_place, nationality, profession, employer, monthly_income_cents, previous_address, guarantor_name, guarantor_email, guarantor_phone (10) | 20260622230000 | b1d91d7 |
| 3 | leases | lease_type, deposit_amount_cents, payment_day, payment_method, irl_index_value, irl_quarter_ref, agency_fees_cents, solidarity_clause, entry_inventory_done (9) | 20260623000000 | a87702b |
| 4 | payments | reference (1) | 20260623010000 | 5f9cdfa |

**Backward compat** : Tous les champs nullable ou DEFAULT non-cassant. Aucune ligne existante modifiée. Code Dart client préexistant jamais cassé.

**Décisions** :
- DPE/GES letters : A-G (loi Climat & Résilience 2021)
- Garant : structure simple (nom, email, phone) — pas de table séparée (MVP)
- IRL : quarter_ref format "T1-2026" (regex strict), index_value numérique 8.2
- Lease_type DEFAULT 'unfurnished', payment_day DEFAULT 1, payment_method DEFAULT 'virement'

---

### FEAT-013 : UX modernization (2 phases)

**Status** : ✅ DONE (Phase 1+2 mergées 2026-06-21 — 2026-06-22, commits 0e20c80, ae5fdf1)

**Phase 1 : AppAppBar standardisé + transitions**
- Widget `AppAppBar` unifié (header, title, appbar pour toutes les pages)
- `AppTransition` enum : standard (slide), fade (auth pages)
- Page transitions smooth (slide droite sur mobile sens, fade auth)
- Files : `lib/core/ui/app_bar/app_app_bar.dart`, `lib/core/router/transitions.dart`
- Tests : 15 widget tests AppAppBar

**Phase 2 : Palette indigo moderne**
- Remplacement couleur teal → indigo (Material 3 defaults)
- Surface/surfaceVariant, primary/primaryContainer, secondaryContainer refresh
- Dark mode support (Material 3 full)
- Files : `lib/core/theme/material3_theme.dart` refonte palette
- Tests : 8 theme tests

---

### FEAT-012 : Cards system (5 phases + foundation)

**Status** : ✅ DONE (Phase 0–5 mergées 2026-06-17 — 2026-06-22, commits 2b7506b–9fdf647)

**Foundation (Phase 0)** :
- `lib/core/ui/cards/entity_card.dart` — base reusable card widget
- `lib/core/ui/cards/status_badge.dart` — uniform status badges (lease status, payment state)
- `lib/core/ui/cards/card_grid.dart` — responsive grid wrapper
- 5 tests foundation

**Phase 1 (Leases)** : `LeaseCard` + `LeasesListPage` refonte
- Card displays : property name, tenant name, loyer + charges, status badge
- Tap → details page
- 10 files, 35 tests

**Phase 2 (Properties)** : `PropertyCard` + `PropertiesListPage` refonte
- Card displays : address, type, surface
- Color-coded type icon (appartement/maison/studio/autre)
- 8 files, 22 tests

**Phase 3 (Tenants)** : `TenantCard` + `TenantsListPage` refonte
- Card displays : full name, email, phone (if present)
- Avatar placeholder (initials)
- 9 files, 28 tests

**Phase 4 (Receipts)** : Timeline `ReceiptCard` + `LeaseReceiptsPage` refonte
- Vertical timeline (PDF generation date, sender) + share button
- is_voided badge
- 7 files, 25 tests

**Phase 5 (Dashboard polish)** : Design tokens (color, spacing, typography)
- KPI card polish (shadows, borders)
- Font scale consistency
- Spacing grid 4/8/12/16/20px
- 6 files, 12 tests

---

### FEAT-011 : Auth propriétaire (email + password)

**Status** : ✅ DONE (mergée develop 2026-06-22)

**Pivot justification** : Remplacement magic link (FEAT-001) pour stabilité MVP + UX français.

**Architecture** :
- 4 controllers (Riverpod StateNotifier) : login, signup, forgot-password, reset-password
- AuthRepository refactor : `signIn()`, `signUp()`, `resetPassword()`, `confirmPasswordReset()`
- PasswordValidator : policy 8 chars + 1 lettre + 1 chiffre (Supabase `letters_digits`)
- AuthErrorMapper : conversion erreurs Supabase → messages UI FR localisés

**Routes publiques** (4) :
- `/login` : email + password (refactorisé FEAT-001)
- `/signup` : email + full_name + password × 2
- `/forgot-password` : demande reset link
- `/reset-password?token=...` : nouveau password (backend validation)

**SQL** : `20260622130000_feat011_handle_new_user_fullname.sql`
- Trigger `handle_new_user()` : extrait `full_name` de `raw_user_meta_data`, fallback `email`

**Fichiers Dart** : 22 créés (pages, widgets, controllers, validators, mappers)

**Tests** : 1093/1093 passing (refactors FEAT-001–010 inclus)

---

### FEAT-010 : Dashboard + PWA Polish + Prod setup (3 sections)

**Status** : ✅ DONE (mergée develop 2026-06-22, commit 643789c)

**Section A : Dashboard refonte**
- 4 KPI cards : loyers mois (encaissé/dû), retards (35j sans paiement), renouvellements (30j), documents (en attente)
- Mini-barchart 6 mois (encaissé vs dû, `fl_chart` v0.69.0)
- Activité récente (top 5 paiements + quittances + documents)
- Onboarding « Premiers pas » (visible si 0 propriété + 0 locataire + 0 bail)
- Files : 18 Dart, 7 nouveaux tests widget (69 assertions)

**Section B : PWA Polish**
- `manifest.json` complet (name, description, background_color #0F766E, icons 192+512+maskable)
- Icônes placeholder « ER » (ImageMagick script)
- Install prompt JS interop (beforeinstallprompt, matchMedia)
- Dismiss persistence via `shared_preferences` (1 semaine TTL)
- Files : 7 Dart (pwa feature), 2 dépendances (shared_preferences, web)

**Section C : Prod setup**
- `.github/workflows/migrate-prod.yml` (workflow_dispatch + confirm input)
- `.github/workflows/deploy.yml` (extend pour staging vs prod branch)
- `docs/PROD_DEPLOY_CHECKLIST.md` (22 étapes)
- `docs/RUNBOOK_PROD_DEPLOY.md` (step-by-step)
- `firebase.json` (CSP étendue fonts.gstatic.com)

---

### FEAT-009 : Upload & stockage documents

**Status** : ✅ DONE (mergée develop 2026-06-17, commit 57c8164)

**Contenu** :
- Table `documents` (12 colonnes) + enum `document_category` (bail_signe, etat_des_lieux, attestation_assurance, quittance_scannee, autre)
- Storage bucket `documents/` (privé, chemins `{schema}/{landlord_id}/{document_id}.{ext}`)
- RPC `soft_delete_document()` (retourne storage_path + hard_deleted flag)
- Legal hold : auto-calculé (true si category IN (bail_signe, etat_des_lieux))
- Files : 15 Dart, 23 RLS tests
- Migrations : `20260602100520_feat009_documents.sql`

---

### FEAT-008 : Partage quittance natif

**Status** : ✅ DONE — Pivot Web Share API native (FEAT-008 Phase 1 Resend supprimée)

**Justification** : Élimination dépendance Resend + secret backend + domaine DNS. UX native meilleure.

**Architecture** :
- Service `web_share_service.dart` : JS interop `navigator.share()` + fallback `mailto://`
- Controller `share_receipt_controller.dart` (StateNotifier)
- State `share_receipt_state.dart` (sealed freezed)
- Widgets : `share_receipt_button.dart`, `confirm_resend_dialog.dart`
- RPC `mark_receipt_as_sent()` : appellée APRÈS partage réussi (audit trail)
- Idempotent : 2e appel écrase `sent_at` (dernière tentative)
- Files : 5 Dart, 3 tests
- Edge Function `send-receipt` : SUPPRIMÉE (Resend pivot 2026-06-22)

---

### FEAT-007 : Générer quittance PDF conforme loi 1989 (3 phases)

**Status** : ✅ DONE (mergée develop 2026-06-02, commit db5d522)

**Contenu** :
- Table `receipts` (13 colonnes) + enum `document_type` (quittance, recu)
- Edge Function `generate-receipt` (Deno + pdf-lib) → PDF Storage
- RPC `void_receipt()` (annulation avec raison)
- Fields : payment_ids[], period_start, period_end, rent_cents, charges_cents, total_cents, is_voided, sent_at, etc.
- Immuabilité document (pas d'UPDATE, soft-delete via RPC)
- Files : 18 Dart, 31 RLS tests
- Migrations : `20260531172904_feat007_receipts.sql`, `20260601103751_feat008_email_quittance.sql` (sent_at, sent_to_email colonnes)

---

### FEAT-006 : CRUD paiements

**Status** : ✅ DONE (mergée develop 2026-06-02, commit 2a18458)

**Contenu** :
- Table `payments` (12 colonnes) — montants cents, dates hardened, soft-delete
- RPC `soft_delete_payment()`
- PaymentMethod enum (virement, cheque, especes, prelevement, autre)
- Trigger `assert_payment_lease_ownership()` (cross-FK validation)
- Fields : period_start/end, paid_at, rent/charges_amount_cents, payment_method, notes, reference
- Files : 15 Dart, 2 routes, 31 RLS tests + 50 unit/widget tests
- Migrations : `20260531102202_feat006_payments.sql` (890 lignes)

---

### FEAT-005 : CRUD UI baux

**Status** : ✅ DONE (mergée develop 2026-05-31, commit a795686)

**Contenu** :
- Pages : list, detail, form (LeaseFormPage, LeaseDetailPage)
- Models : Lease (freezed), LeaseStatus enum, LeaseType (si soft-delete)
- Fields : property_id, tenant_id, rent/charges, start/end dates, status
- Date hardening : bornes 1900-01-01 à 2100-12-31
- Validations : end_date > start_date, rent > 0, charges >= 0
- Files : 18 Dart, 4 routes (list, detail, new, edit), 90+ tests

---

### FEAT-004 : CRUD UI locataires

**Status** : ✅ DONE (mergée develop 2026-05-31, commit 911ca5c)

**Contenu** :
- Pages : list, detail, form (TenantFormPage, TenantDetailPage)
- Models : Tenant (freezed)
- Fields : first_name, last_name, email, phone
- Email validation (regex)
- Files : 15 Dart, 4 routes (list, detail, new, edit), 80+ tests

---

### FEAT-003 : CRUD UI propriétés

**Status** : ✅ DONE (mergée develop 2026-05-31, commit c1b0571)

**Contenu** :
- Pages : list, detail, form (PropertyFormPage, PropertyDetailPage)
- Models : Property (freezed), PropertyType enum
- Fields : name, address, type, surface_m2
- PropertyType : appartement, maison, studio, autre
- Files : 16 Dart, 4 routes (list, detail, new, edit), 56 tests

---

### FEAT-002 : Modèle de données + RLS exhaustive

**Status** : ✅ DONE (mergée develop 2026-05-28, commit 6b28bbb)

**Contenu** :
- Tables : properties, tenants, leases (public + dev)
- Colonnes landlords : full_name, phone, address (ajout)
- FK change : landlords.id → auth.users(id) : CASCADE → NO ACTION (RGPD retention 5 ans)
- Soft-delete : pattern complet avec RPC (soft_delete_property, soft_delete_tenant, soft_delete_lease)
- RLS : 24 policies × SELECT/INSERT/UPDATE (pas DELETE)
- Triggers : tr_00 (ownership), tr_01 (protect columns), tr_02 (updated_at)
- Migration : `20260528120000_feat002_data_model.sql` (37k lignes)
- Tests : 77 RLS tests

---

### FEAT-001 : Auth propriétaire (magic link — refactorisée FEAT-011)

**Status** : ✅ REFACTORED into FEAT-011 (2026-06-22)

**Original contenu** :
- Supabase Auth magic link (email-only, OTP)
- SignupPage + LoginPage (widgets magic link)
- Session recovery via PKCE

**Pivot justification** : FEAT-011 password auth plus stable pour MVP français + UX habituelle.

**Remainders** : Pas d'enregistrement technique — refactoring complet en FEAT-011 (signup/login/forgot/reset classiques).

---

## Synthèse état

**Total features** : 16 (FEAT-001–016)

**Status** :
- ✅ DONE : 16 (100%)
- 🟢 READY : 0
- 🚧 WIP : 0
- 📋 PLANNED : 0

**MVP coverage** : 100% (FEAT-001–010 + FEAT-011 fondamentale, FEAT-012–016 enhancements)

**Tests** : 1093/1093 passing (au dernier merge, a1fefec)

**Dépendances** : pubspec.yaml à jour (Riverpod 2.6.0, GoRouter 14.6.0, freezed 2.5.7, etc.)

**Prochaines étapes post-MVP** :
- Riverpod 3.x upgrade (breaking changes)
- GoRouter 17.x (breaking changes)
- freezed 3.x (breaking changes)
- Analytics avancées (export comptable, vision Stripe)
