# Features — registre

> Maintenu par `state-keeper`. **Dernière sync** : 2026-07-05 (FEAT-023...FEAT-030 ✅ mergées, post-MVP M1 feature-complete staging).

## Légende

- ✅ **done** : code mergé, Cloud Functions déployées, Firestore rules testées
- 🟢 **ready** : code prêt prod, en attente déploiement
- 🚧 **wip** : développement en cours
- 📋 **planned** : spec'd, backlog ordonné
- 💡 **idea** : conceptuel

## Matrice features (MVP + Post-MVP en cours)

| ID | Nom | Phase | Status | Commit | Notes |
|---|---|---|---|---|---|
| FEAT-001 | Auth propriétaire (magic link) | — | ✅ Refactorisée | 20260527081533 | Remplacée FEAT-011 (email+password 2026-06-22) |
| FEAT-002 | Modèle de données Postgres + RLS | — | ✅ done | 20260528120000 | _(Supabase) Archivé — migré Firestore FEAT-019_ |
| FEAT-003 | CRUD UI propriétés | — | ✅ done | — | PropertiesListPage, PropertyDetailPage, PropertyFormPage, PropertyEditPage |
| FEAT-004 | CRUD UI locataires | — | ✅ done | — | TenantsListPage, TenantDetailPage, TenantFormPage, TenantEditPage |
| FEAT-005 | CRUD UI baux | — | ✅ done | — | LeasesListPage, LeaseDetailPage, LeaseFormPage, LeaseEditPage + status pills |
| FEAT-006 | CRUD paiements | — | ✅ done | 20260531102202 | PaymentFormPage, PaymentEditPage (nested /leases/:id/payments*) |
| FEAT-007 | Quittance PDF + Web Share | 1+2+3 | ✅ done | 20260531172904 | CF `generateReceipt` + `markReceiptAsSent` (Web Share API native) |
| FEAT-008 | Partage quittance natif | — | ✅ done | — | Web Share API (pivot FEAT-007 Phase 1 Resend) |
| FEAT-009 | Upload documents (PDF, images) | — | ✅ done | 20260602100520 | CF `createDocument`, Storage rules, legalHold logic |
| FEAT-010 | Dashboard + PWA + Prod setup | 1+2+3 | ✅ done | 643789c | 4 KPI + 6m chart + activité + onboarding + install prompt |
| FEAT-011 | Auth email + password | — | ✅ done | — | Pivot FEAT-001 (2026-06-22) — Firebase Auth native |
| FEAT-012 | Cards system | 0–5 | ✅ done | 2b7506b–9fdf647 | EntityCard foundation + phases: Leases, Properties, Tenants, Receipts, Dashboard |
| FEAT-013 | UX modernization | 1+2 | ✅ done | 0e20c80, ae5fdf1 | AppAppBar + transitions + indigo palette |
| FEAT-014 | Forms enrichment FR | 1–4 | ✅ done | 4de7554–5f9cdfa | 32 champs (DPE, garant, IRL, dépôt) — Postgres schema (archivé) |
| FEAT-015 | Detail pages enrichment | — | ✅ done | 6959a9e | PropertyDetailPage, TenantDetailPage, LeaseDetailPage expose FEAT-014 |
| FEAT-016 | RGPD consent persistence | — | ✅ done | e82d113 | Postgres rgpd_consent_{at,version} (archivé) |
| FEAT-017 | _(Reserve)_ | — | 💡 idea | — | — |
| FEAT-018 | Simulateur investissement | — | ✅ done | — | SimulatorPage CRUD investment_scenarios Firestore |
| FEAT-019 | Migration Supabase → Firebase | Phase 1–3 | ✅ done | 61a5956–85f1be2 | Firestore collections + rules + 28 indexes + Cloud Functions (callable + triggers + scheduled) |
| FEAT-020 | Rebrand EasyRent → Baillan | — | ✅ done | — | Logo, palette, asset fonts (EB Garamond) |
| FEAT-021 | Vérification email post-signup | — | ✅ done | — | Firebase Auth verification link |
| FEAT-022 | Redesign login "La Page du Registre" | — | ✅ done | — | Landing publique, simulator carrefour, quit demo dialog |
| FEAT-023 | Réglages app (thème + légal) | — | ✅ done | — | ProfilePage tuniles, themeModeProvider persisté, /terms page, package_info_plus version |
| FEAT-024 | _(Reserve)_ | — | 💡 idea | — | — |
| FEAT-025 | Sécurité + support in-app | — | ✅ done | 0cd54de, f5734b4 | Changement mot de passe + formulaire support → support_requests, rgpdConsentVersion v2-2026-07 |
| FEAT-025b | /profile HUB de réglages | — | ✅ done | 16ebc77 | Sous-pages /profile/details, /profile/password, /profile/support, mobile-first tuiles |
| FEAT-026 | Navigation shell adaptative | — | ✅ done | ca2d10a | StatefulShellRoute.indexedStack 5 branches, NavigationBar <600px / NavigationRail ≥600px, railExpandedProvider persisté |
| FEAT-027 | Dashboard — période graphique | — | ✅ done | ba7c12d | chartPeriodProvider (6/12/24m) persisté, monthlyAmountsProvider découplé |
| FEAT-028 | Détection retards de paiement | — | ✅ done | 7ac1d03 | lease_lateness.dart règle métier, LeaseFilter.late, KPI drill-down, pastille « En retard » |
| FEAT-029 | Charges — motif + régularisation | — | ✅ done | 871ebff | payment.notes motif libre sur PDF, régularisation annuelle (bail nu), Web Share, PAS archivage V1 |
| FEAT-029b | Découvrabilité régularisation | — | ✅ done | 514666f | Menu « Régulariser » sur carte/ligne bail nu, ?action=regularize query param |
| FEAT-030 | Navigation retour corrigée | — | ✅ done | 7db144d | Formulaires pop(), tuiles push(), simulateur push() par-dessus shell |

---

## Détails par feature (Post-MVP M1, session 2026-07-03–07-05)

### FEAT-030 : Navigation retour corrigée

**Status** : ✅ DONE (commit 7db144d)

**Contenu** :
- Formulaires d'édition (PropertyEditPage, TenantEditPage, LeaseEditPage, PaymentEditPage) → `pop()` retour fiche
- Tuiles Accueil drill-down → `push()` (empilage, retour à Accueil)
- Simulateur (comptes) → `push()` par-dessus shell (non-destructif)
- Bouton Profil retiré de la fiche bail (FEAT-030 découverte : via shell, pas fiche)

**Impact** : QA F-1 through F-4 audit (2026-07-04), correctifs UX

---

### FEAT-029b : Découvrabilité régularisation charges

**Status** : ✅ DONE (commit 514666f)

**Contenu** :
- Menu contextuel « Régulariser les charges » sur card/ligne bail nu
- Paramètre query `/leases/:id?action=regularize` → dialog ouvre automatiquement sur chargement fiche
- Accessible via FEAT-029 UI (charge_regularization_form)

---

### FEAT-029 V1 : Charges — motif + régularisation annuelle

**Status** : ✅ DONE (commit 871ebff)

**Contenu** :
- **Motif paiement libre** : nouveau champ `payment.notes` (string, optional)
  - Affiché sur reçu (quittance PDF)
  - Rendu au signature (Web Share API)
  
- **Régularisation annuelle** (bail nu uniquement) :
  - Route : `/leases/:id?action=regularize` (query param)
  - Feature : `lib/features/charge_regularization/**`
  - Workflow :
    1. Calcul provisions au prorata (client-side, testable)
    2. Solde annuel (provisions vs charges réelles)
    3. Avis récapitulatif PDF (lib/features/charge_regularization/domain/charge_regularization_pdf_renderer.dart)
    4. Web Share API (fallback mailto://)
  - PAS d'archivage (V2, dépend Cloud Functions async processing)

**Schema** : `lease.chargeRegularizationHistory` (map, optional) stocke l'historique

**Tests** : charge_regularization_balance_test.dart (calculs)

---

### FEAT-028 : Détection retards de paiement corrigée

**Status** : ✅ DONE (commit 7ac1d03)

**Contenu** :
- Fonction pure `isLeaseLate()` (lib/features/leases/domain/lease_lateness.dart)
  - Règle métier : délai grâce 5j après échéance, pas proratisation 1ᵉʳ mois, couverture période, troncature locale anti-fuseau
  - Testable sans Firestore
  
- **LeaseFilter** enum nouvelle valeur : `late` (« En retard ») — priority > renewable > active
  
- **KPI Dashboard** : retards détectés (rouge, drill-down → /leases?filter=late)
  
- **Pastille UI** : « En retard » sur LeaseCard, LeaseListItem, LeaseDetailPage

- **Provider** : `leaseLatenessProvider` (FutureProvider, dépend payments stream)

**Tests** : lease_lateness_test.dart (couverture périodes, bornes grâce, mois courts)

---

### FEAT-027 : Dashboard — période graphique sélectionnable

**Status** : ✅ DONE (commit ba7c12d)

**Contenu** :
- **Sélecteur période** : 6 / 12 / 24 mois (toggle buttons)
- **Persistence** : `chartPeriodProvider` (StateNotifierProvider) + ChartPeriodStorage (SharedPreferences)
- **Découplage** : `monthlyAmountsProvider` (FutureProvider) dépend `chartPeriodProvider` (watch)
- **UI Polish** : section « Vue d'ensemble » Accueil, loyers graphique défilable, couleurs par état

**Domain** : lib/features/dashboard/domain/chart_period.dart (enum 6m/12m/24m, fromName)

**Provider** : chartPeriodProvider (non-autoDispose, persisté session)

---

### FEAT-026 : Navigation shell adaptative web+mobile

**Status** : ✅ DONE (commit ca2d10a, ADR navigation-26)

**Contenu** :
- **Shell 5 branches** : Accueil, Biens, Locataires, Baux, Profil
  - `StatefulShellRoute.indexedStack` (état préservé par branche)
  - Racines sans bouton retour (destinées shell)
  
- **Responsive** :
  - <600px (mobile) : NavigationBar bottom (5 destinations)
  - ≥600px (desktop/tablet) : NavigationRail left (5 destinations, repliable)
  
- **Rail repliable** : `railExpandedProvider` (StateNotifierProvider, SharedPreferences)
  - Compact (false) : icônes seules + libellés courts (icône 24px)
  - Étendu (true) : icônes + full libellés (sidebar Gmail-like)
  - Bouton menu (HamburgerButton) en entête rail
  
- **Marque Baillan** : entête rail/navbar (logo Baillan)
  - Rail replié : icône 32px
  - Rail étendu : wordmark (Baillan logo + texte)
  
- **Hors-shell** : Landing / Auth / Légal (/terms, /privacy) / Simulateur (toutes tailles)
  - Garde 3-états inchangée (unauthenticated → landing | anonymous → simulator | fullyAuthenticated → shell)
  - Transition fade (auth) vs standard (métier)

**Widgets** : AdaptiveNavigationScaffold, BrandMark, RailExpandedStorage

**Tests** : app navigation integration tests (routes, focus)

---

### FEAT-025b : /profile HUB de réglages (mobile-first)

**Status** : ✅ DONE (commit 16ebc77)

**Contenu** :
- ProfilePage refondu : tuiles (cards) au lieu de liste classique
  - Chaque tuile = une section (Identité, Sécurité, Support, Légal, À propos)
  - Clic tuile → navigation sous-page (imbriquée, gardée shell)
  
- Nouvelles sous-pages empilées :
  - `/profile/details` → ProfileDetailsPage (identité complète)
  - `/profile/password` → ChangePasswordPage (comptes email only)
  - `/profile/support` → SupportPage (formulaire contact)
  
- Mobile-first : tuiles full-width, stack vertical

**Impact** : sections Sécurité + Support + Légal découvrables

---

### FEAT-025 : Sécurité + support in-app

**Status** : ✅ DONE (commits 0cd54de, f5734b4)

**Contenu** :
- **Changement de mot de passe** (comptes email only) :
  - Route : `/profile/password` (ChangePasswordPage)
  - Workflow : reauthenticateWithPassword() + updatePassword() (Firebase Auth native API)
  - Gate : `hasPasswordProvider` (FutureProvider, dépend auth.currentUser?.providerData)
  - UI : tuile Sécurité ProfilePage (visible si email+password)
  
- **Support formulaire** (« Nous contacter ») :
  - Route : `/profile/support` (SupportPage)
  - Destination : **nouvelle collection Firestore `support_requests`** (create-only)
  - Schéma : landlordId, email, subject (≤120 chars), message (≤2000 chars), appVersion, appEnv, status='new', createdAt=request.time
  - Firestore rules : isFullyAuthed() + landlordId==uid (isOwner implicit)
  - No get/list/update/delete (V1)
  - Traitement : Admin console + Cloud Function async (notification email Trigger Email extension, V2)
  
- **RGPD consent** : version bumpée `v1-2026-06` → `v2-2026-07` (CGU v1.0 + politique confidentalité v1.0)
  - Sync : auth_repository.dart (`rgpdConsentVersion` constant)
  - Sync : functions/finalize_anonymous_upgrade.ts (custom claims check)
  
- **Politique de confidentialité** : v1.1 (collecte support documentée)

**Widgets** : ChangePasswordForm, SupportForm (validation, error handling)

**Tests** : support_form_test.dart, change_password_test.dart

---

### FEAT-023 : Réglages app (thème + légal + version)

**Status** : ✅ DONE

**Contenu** :
- **Thème** (ProfilePage tuile « Apparence ») :
  - Sélecteur ThemeMode : Système / Clair / Sombre
  - Provider : `themeModeProvider` (StateNotifierProvider<ThemeModeNotifier, ThemeMode>)
  - Storage : `ThemeModeStorage` (SharedPreferences key='theme_mode')
  - Défaut : ThemeMode.system (subit système jusqu'à changement manuel)
  - Persistance : session entière + future sessions
  
- **Liens légaux** :
  - Tuile « Légal » ProfilePage
  - Liens : `/terms` (Conditions générales) + `/privacy` (Politique de confidentialité)
  - Routes publiques (accessible anonymes + comptes)
  
- **À propos** :
  - Tuile « À propos » ProfilePage
  - Version app : lue via `package_info_plus` → pubspec.yaml `1.0.0+BUILD`
  - BUILD number : injecté CI (GitHub run_number), local (git rev-list --count HEAD)
  - Affichage : « Baillan v1.0.0 (build 123) »
  
- **Page /terms** : CGU v1.0 (2026-07-03) — Markdown rendu Flutter

**Widgets** : ThemeModeSelector, VersionDisplay

**Dependencies** : `package_info_plus` v9.0.1 (ajoutée pubspec.yaml)

---

### CGU v2-2026-07 (intégration FEAT-025)

**Status** : ✅ DONE

**Contenu** :
- **Conditions générales** (v1.0) : acceptation obligatoire signup
- **Politique de confidentialité** (v1.1 mis à jour) : mention collecte support_requests formulaire
- **Acceptance gate** : SignupPage (RGPD checkbox pre-unchecked)
- **Version consent** : bumpée dans Firestore `landlords.rgpdConsentVersion` = 'v2-2026-07' (commit au signup)

---

## Détails par feature (MVP complet)

### FEAT-022 : Redesign login "La Page du Registre" (BAILLAN-M1)

**Status** : 🟢 READY (landing public, routes 3-state intégrées)

**Contenu** :
- **Landing page** (`/`) : publique, carrefour onboarding (create account / essai sans compte)
- **3-state router** : unauthenticated → /login | anonymous → /simulator | fullyAuthenticated → /dashboard
- **Quit demo** : action `quit_demo_dialog.dart` + logout + redirect landing
- **Simulator** : accessible anonymes (CRUD investment_scenarios)

**Files** : LandingPage, app_router.dart (redirect logic), auth_session_provider.dart (3-state enum)

**Tests** : router_auth_refresh_test.dart (couvre signe-in chaud regression 2026-07-02)

---

### FEAT-021 : Vérification email post-signup

**Status** : ✅ DONE

**Contenu** :
- Firebase Auth native email verification link (sent auto post-signup)
- Client UI flow : code + instructions dans SignupPage
- Cloud Function `handleNewUser` provision `landlords/{uid}` doc

**No-op si utilisateur** :
- Skip vérification (cloud function idempotent)
- Ou re-send verification (Firebase API)

---

### FEAT-020 : Rebrand EasyRent → Baillan

**Status** : ✅ DONE (commit e5076c9)

**Contenu** :
- Logo Baillan (identité « acte notarial »)
- Palette sémantique (indigo → teal consistency)
- Asset font EB Garamond (sérif éditorial, remplace Cochin — assets/fonts/)
- Package name interne conservé (easyrent) — imports non cassés

**Files** : pubspec.yaml (fonts), assets/fonts/OFL.txt (license), lib/core/theme/ (palette)

---

### FEAT-019 : Migration Supabase → Firebase

**Status** : ✅ DONE (Phase 1–3, commits 61a5956–85f1be2)

**Justification** : Firestore scale + Cloud Functions trigger native + Anonymous Auth tier system (BAILLAN-M1).

**Phase 1 : Infrastructure** (commit 61a5956)
- Firestore collections : landlords, properties, tenants, leases, payments, receipts, documents, investment_scenarios, paid_plan_interest
- Security rules : isFullyAuthed() + isAnonymous() + isOwner() + preservesImmutables()
- Indexes : 28 composites (soft-delete + cross-filters)
- Firebase Storage rules

**Phase 2 : Callables + Triggers** (commit 52a09c9–85f1be2)
- **Auth trigger** : `handleNewUser` (provision landlord doc)
- **Triggers** : setUpdatedAt (7 collections) + recomputeReceiptStale
- **Callables** : createLease, updateLease, createPayment, updatePayment, generateReceipt, voidReceipt, markReceiptAsSent, createDocument, getDocumentDownloadUrl, softDeleteEntity, finalizeAnonymousUpgrade
- **Scheduled** : cleanupExpiredAnon (cron)
- Tests : `__tests__/*.test.ts` (vitest)

**Phase 3 : Client integration** (commit 07f20a3–07f20a3)
- Firebase Auth native + custom claims (firebase.sign_in_provider)
- Riverpod providers : FirebaseAuth stream + Firestore collection queries
- CRUD UI rewrite (no-code breaking changes — same widget interfaces)

**Piège soft-delete** : Firestore refus WHERE field==null sans index composite → solution indexing systématique (commits 61a5956, 85f1be2).

**Notes architecture** :
- Admin SDK callable bypasse rules (cross-entity validation safe)
- Denormalization (activeLeaseCount, isStale) via CF triggers
- Receipt immutabilité : pas de soft-delete, retention 5 ans

---

### FEAT-018 : Simulateur investissement

**Status** : ✅ DONE

**Collections** : `investment_scenarios/{id}` (CRUD direct, pas CF)

**Routes** :
- `/simulator` — SimulatorPage() list/create
- `/simulator/:id` — SimulatorPage(scenarioId: id) edit

**Accès** : isSignedIn() (anonymes + comptes) — Firestore rules allow 

**Schema** :
- `name` (string, 120 chars max)
- `schemaVersion` (int)
- `scenarioJson` (map serialized inputs)

---

### FEAT-017 : _(Reserve)_

Reserved pour futur feature.

---

### FEAT-016 : RGPD consent persistence _(Archivé Postgres)_

**Status** : ✅ DONE (Postgres migration 20260623020000 — archivé)

**Migré vers Firestore** : `landlords/{uid}.rgpdConsentAt` + `.rgpdConsentVersion` (FEAT-019 Phase 1).

---

### FEAT-015 : Detail pages enrichment

**Status** : ✅ DONE (commit 6959a9e)

**Contenu** :
- PropertyDetailPage expose FEAT-014 Phase 1 (DPE, étage, chauffage, etc.)
- TenantDetailPage expose FEAT-014 Phase 2 (birth, garant, revenus, etc.)
- LeaseDetailPage expose FEAT-014 Phase 3 (type bail, dépôt, IRL, paiement, etc.)

**Widgets** : DetailField custom (label + value + edit button)

---

### FEAT-014 : Forms enrichment FR (32 colonnes) _(Archivé Postgres)_

**Status** : ✅ DONE (Phase 1–4 merged 2026-06-22–2026-06-23) — **archivé Postgres**

**Contenu** (repris dans Firestore FEAT-019 si nécessaire) :

| Phase | Collection | Champs ajoutés | Migration |
|---|---|---|---|
| 1 | properties | rooms, bedrooms, floor, has_elevator, furnished, heating_type, dpe_letter, dpe_value_kwh_m2_year, ges_letter, construction_year, postal_code, city (12) | 20260622220000 |
| 2 | tenants | birth_date, birth_place, nationality, profession, employer, monthly_income_cents, previous_address, guarantor_name, guarantor_email, guarantor_phone (10) | 20260622230000 |
| 3 | leases | lease_type, deposit_amount_cents, payment_day, payment_method, irl_index_value, irl_quarter_ref, agency_fees_cents, solidarity_clause, entry_inventory_done (9) | 20260623000000 |
| 4 | payments | reference (1) | 20260623010000 |

---

### FEAT-013 : UX modernization (2 phases)

**Status** : ✅ DONE (Phase 1+2 merged 2026-06-21–2026-06-22)

**Phase 1** (commit 0e20c80) : AppAppBar standardisé + page transitions smooth
- `AppAppBar` widget : header + title + back + actions
- `AppTransition` enum : fade (auth) + standard (métier)

**Phase 2** (commit ae5fdf1) : Palette color modernisée
- Indigo primary (replace teal)
- Material 3 defaults

---

### FEAT-012 : Cards system (5 phases)

**Status** : ✅ DONE (Phase 0–5 merged commits 2b7506b–9fdf647)

**Foundation** : `lib/core/ui/cards/` (EntityCard, StatusBadge, CardGrid)

| Phase | Contenu | Routes |
|---|---|---|
| 0 | EntityCard foundation + StatusBadge design | — |
| 1 | LeaseCard + status pills (ongoing/upcoming/ended) | /leases |
| 2 | PropertyCard (name, address, type, activeLeaseCount) | /properties |
| 3 | TenantCard (first/last name, email, activeLeaseCount) | /tenants |
| 4 | ReceiptCard (amount, period, voided flag, share button) | /leases/:id/receipts |
| 5 | Dashboard polish (KPI cards, layout, spacing) | /dashboard |

---

### FEAT-011 : Auth email + password (Pivot FEAT-001)

**Status** : ✅ DONE (merged 2026-06-22)

**Contenu** :
- Firebase Auth email + password native
- SignupPage form (email, password×2, full name, RGPD gate)
- LoginPage form (email, password)
- ForgotPasswordPage (reset link request)
- ResetPasswordPage (code validation + new password)

**Cloud Function `handleNewUser`** :
- Trigger `beforeUserCreated` (Firebase Identity Platform)
- Provision `landlords/{uid}` doc (email, fullName, subscriptionTier='free', rgpdConsentVersion)

**Tests** : Couverts par signup_form_test.dart, login_page_test.dart

---

### FEAT-010 : Dashboard + PWA + Prod setup

**Status** : ✅ DONE (commit 643789c)

**Dashboard** :
- 4 KPI : loyers encaissés (30j), dus (30j), retards, renouvellements
- Mini-chart : 6m loyers reçus (fl_chart v0.69.0)
- Activité : top 5 paiements + quittances + documents
- Onboarding : si 0 propriété + 0 locataire (guided wizard)

**PWA** :
- install prompt (1× par semaine via shared_preferences)
- offline shell (service worker)
- manifest.json (icons, theme)

**Prod setup** :
- CI workflows (ci.yml + deploy.yml)
- Firebase Hosting (staging + prod channels)
- CSP headers (fonts.gstatic.com)

---

### FEAT-009 : Upload documents

**Status** : ✅ DONE (commit 20260602100520)

**Collections** : `documents/{id}` (CF exclusive createDocument / softDeleteDocument)

**Features** :
- File picker (PDF, images)
- Storage bucket `/documents/{landlordId}/{documentId}`
- Soft-delete (refuse si legalHold==true — rétention 3–7 ans)
- Category enum : lease / inventory / other

**Routes** : /leases/:id (documents section TBD)

---

### FEAT-008 : Partage quittance natif

**Status** : ✅ DONE

**Pivot** : Web Share API native (replace FEAT-007 Phase 1 Resend edge function)

**Implémentation** : LeaseReceiptsPage share button → navigator.share (PDF blob + filename)

---

### FEAT-007 : Générer quittance PDF conforme loi 1989 (3 phases)

**Status** : ✅ DONE (commit 20260531172904)

**Phase 1** (2026-05-31) : Edge Function `generate-receipt` + Supabase Storage
- PDF generation (pdf + printing packages)
- Mentions légales loi 6 juillet 1989
- Quittance immuable (pas de soft-delete, rétention 5 ans)

**Phase 2** : Client UI — ReceiptCard display + download button

**Phase 3** : Email share (FEAT-008 pivot Web Share API)

**Migré Firestore** : CF callable `generateReceipt` + `markReceiptAsSent` (FEAT-019)

---

### FEAT-006 : CRUD paiements

**Status** : ✅ DONE (commit 20260531102202)

**Routes** : /leases/:id/payments/new, /leases/:id/payments/:pid/edit

**Contenu** :
- PaymentFormPage (amount, paidAt, periodStart/End)
- PaymentEditPage (rare updates)
- Auto-declenche CF `generateReceipt` post-creation

**Collections** (Firestore) : `payments/{id}` (CF exclusive via createPayment/updatePayment)

---

### FEAT-005 : CRUD UI baux

**Status** : ✅ DONE

**Routes** : /leases, /leases/new, /leases/:id, /leases/:id/edit

**Contenu** :
- LeasesListPage (LeaseCard + filter status)
- LeaseFormPage (property picker, tenant picker, dates, loyer, charges)
- LeaseDetailPage (display + payments section + receipts section)
- LeaseEditPage (update form)

**Collections** (Firestore) : `leases/{id}` (CF exclusive via createLease/updateLease)

**Status pills** : ongoing / upcoming / ended (computed from startDate/endDate)

---

### FEAT-004 : CRUD UI locataires

**Status** : ✅ DONE

**Routes** : /tenants, /tenants/new, /tenants/:id, /tenants/:id/edit

**Contenu** :
- TenantsListPage (TenantCard list)
- TenantFormPage (first name, last name, email, phone)
- TenantDetailPage (display all fields + linked leases section)
- TenantEditPage (update form)

**Collections** (Firestore) : `tenants/{id}` (CRUD direct, RLS only)

---

### FEAT-003 : CRUD UI propriétés

**Status** : ✅ DONE

**Routes** : /properties, /properties/new, /properties/:id, /properties/:id/edit

**Contenu** :
- PropertiesListPage (PropertyCard list)
- PropertyFormPage (name, address, type, surface)
- PropertyDetailPage (display all fields + linked leases section)
- PropertyEditPage (update form)

**Collections** (Firestore) : `properties/{id}` (CRUD direct, RLS only)

**Type enum** : appartement / maison / studio / autre

---

### FEAT-002 : Modèle de données + RLS _(Archivé Postgres)_

**Status** : ✅ DONE (migration 20260528120000) — **archivé Postgres**

**Contenus** : landlords, properties, tenants, leases, RLS policies, soft-delete RPCs.

**Migré vers Firestore** : FEAT-019 Phase 1 (firestore.rules + firestore.indexes.json).

---

### FEAT-001 : Auth propriétaire (magic link) _(Refactorisée → FEAT-011)_

**Status** : ✅ REFACTORISÉE (remplacée FEAT-011 email+password 2026-06-22)

**Raison** : Email+password classique plus intuitif (magic link UX friction).

---

## Roadmap Post-MVP (priorité)

| ID | Nom | Phase | Status | Notes |
|---|---|---|---|---|
| P1-001 | Profile utilisateur avancé | — | 📋 planned | password change, avatar, 2FA |
| P1-002 | Rappels paiement automatiques | — | 💡 idea | Callable cron, email notification |
| P1-003 | Export comptable FEC | — | 💡 idea | CSV generation, Callable |
| P1-004 | Multi-utilisateurs (mandataires) | — | 💡 idea | Permissions, invite flow |
| P2-001 | Intégration bancaire | — | 💡 idea | Rapprochement virement auto |
| P2-002 | App native Capacitor | — | 💡 idea | iOS + Android distribué |
