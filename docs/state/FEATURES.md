# Features — registre

> Maintenu par `state-keeper`. **Dernière sync** : 2026-07-09 (FEAT-045 i18n FR/EN merged PR #72 + FEAT-049 SEO merged + FEAT-043/045/048/024 all bilingue/multiplateforme).

## Légende

- ✅ **done** : code mergé, Cloud Functions déployées, Firestore rules testées, production-ready
- 🟢 **ready** : code prêt prod, attente déploiement
- 🚧 **wip** : développement en cours
- 📋 **planned** : spec'd, backlog ordonné, attente priorité
- 💡 **idea** : conceptuel

## Matrice features (MVP + Post-MVP M1)

| ID | Nom | Phase | Status | Commit | Notes |
|---|---|---|---|---|---|
| FEAT-001 | Auth propriétaire (magic link) | — | ✅ Refactorisée | — | Remplacée FEAT-011 (email+password 2026-06-22) |
| FEAT-002 | Modèle de données Postgres + RLS | — | ✅ Archivé | — | Supabase — migré Firestore FEAT-019 |
| FEAT-003 | CRUD UI propriétés | — | ✅ done | — | PropertiesListPage, PropertyDetailPage, PropertyFormPage, PropertyEditPage |
| FEAT-004 | CRUD UI locataires | — | ✅ done | — | TenantsListPage, TenantDetailPage, TenantFormPage, TenantEditPage |
| FEAT-005 | CRUD UI baux | — | ✅ done | — | LeasesListPage, LeaseDetailPage, LeaseFormPage, LeaseEditPage + status pills |
| FEAT-006 | CRUD paiements | — | ✅ done | — | PaymentFormPage, PaymentEditPage (nested /leases/:id/payments*) |
| FEAT-007 | Quittance PDF + Web Share | — | ✅ done | — | CF `generateReceipt` + `markReceiptAsSent` (Web Share API native) |
| FEAT-008 | Partage quittance natif | — | ✅ done | — | Web Share API (pivot FEAT-007 Phase 1 Resend) |
| FEAT-009 | Upload documents (PDF, images) | — | ✅ done | — | CF `createDocument`, Storage rules, legalHold logic |
| FEAT-010 | Dashboard + PWA + Prod setup | — | ✅ done | — | 4 KPI + 6m chart + activité + onboarding + install prompt |
| FEAT-011 | Auth email + password | — | ✅ done | — | Pivot FEAT-001 (2026-06-22) — Firebase Auth native |
| FEAT-012 | Cards system | 0–5 | ✅ done | — | EntityCard foundation + phases: Leases, Properties, Tenants, Receipts, Dashboard |
| FEAT-013 | UX modernization | 1+2 | ✅ done | — | AppAppBar + transitions + indigo palette |
| FEAT-014 | Forms enrichment FR | 1–4 | ✅ done | — | 32 champs (DPE, garant, IRL, dépôt) — Firestore |
| FEAT-015 | Detail pages enrichment | — | ✅ done | — | PropertyDetailPage, TenantDetailPage, LeaseDetailPage expose FEAT-014 |
| FEAT-016 | RGPD consent persistence | — | ✅ done | — | Firestore `landlords.rgpdConsentAt/Version` |
| FEAT-017 | _(Reserve)_ | — | 💡 idea | — | — |
| FEAT-018 | Simulateur investissement | — | ✅ done | — | SimulatorPage CRUD investment_scenarios Firestore |
| FEAT-019 | Migration Supabase → Firebase | Phase 1–3 | ✅ done | — | Firestore collections + rules + 28 indexes + Cloud Functions |
| FEAT-020 | Rebrand EasyRent → Baillan | — | ✅ done | — | Logo, palette, asset fonts (EB Garamond) |
| FEAT-021 | Vérification email post-signup | — | ✅ done | — | Firebase Auth verification link |
| FEAT-022 | Redesign login "La Page du Registre" | — | ✅ done | — | Landing publique, simulator carrefour, quit demo dialog |
| FEAT-023 | Réglages app (thème + légal) | — | ✅ done | — | ProfilePage tuiles, themeModeProvider persisté, /terms page |
| **FEAT-024** | **App mobile iOS/Android** | Mobile | ✅ **done** | feature/024-mobile (2026-07-06) | **Plateformes natives (android/, ios/), Firebase apps Android+iOS, bundle ID `com.daki.baillan`, OAuth Google/Apple, share_plus natif, smoke test émulateur ✅, conformité Play/App Store (FEAT-045 bloquant + FEAT-045 levé)** |
| FEAT-025 | Sécurité + support in-app | — | ✅ done | — | Changement mot de passe + formulaire support → support_requests |
| FEAT-025b | /profile HUB de réglages | — | ✅ done | — | Sous-pages /profile/details, /profile/password, /profile/support |
| FEAT-026 | Navigation shell adaptative | — | ✅ done | — | StatefulShellRoute.indexedStack 5 branches, NavigationBar/Rail responsive |
| FEAT-027 | Dashboard — période graphique | — | ✅ done | — | chartPeriodProvider (6/12/24m) persisté, monthlyAmountsProvider découplé |
| FEAT-028 | Détection retards de paiement | — | ✅ done | — | lease_lateness.dart règle métier, LeaseFilter.late, KPI drill-down |
| FEAT-029 | Charges — motif + régularisation | — | ✅ done | — | payment.notes motif libre sur PDF, régularisation annuelle (bail nu) |
| FEAT-029b | Découvrabilité régularisation | — | ✅ done | — | Menu « Régulariser » sur carte/ligne bail nu, ?action=regularize |
| FEAT-030 | Navigation retour corrigée | — | ✅ done | — | Formulaires pop(), tuiles push(), simulateur push() par-dessus shell |
| **FEAT-031** | **Rappels paiement automatiques** | Post-M1 | 📋 **planned** | — | **Cloud Scheduler + Trigger Email, attente infra email** |
| **FEAT-032** | **Dashboard — Trésorerie graphique** | Post-M1 | 📋 planned | — | Encaissé vs dû, détection retards intégré |
| **FEAT-033** | **Archivage régularisations charges** | Post-M1 | 💡 **idea** | — | **FEAT-041 V1 a absorbé le snapshot figé — reliquat V1.1** |
| **FEAT-034** | **Import multi-colonnes** | Post-M1 | 📋 planned | — | Properties/tenants/leases CSV import |
| **FEAT-035** | **2FA TOTP** | Post-M2 | 📋 planned | — | Authenticator app integration |
| **FEAT-036** | **Charges récupérables vs non-récupérables** | M1 | ✅ **done** | PR #66 (2026-07-05) | **nonRecoverableChargesCents, FEAT-036 merged** |
| **FEAT-041** | **Suivi dépenses unifié** | M1 | ✅ **done (V1)** | PR #67 (2026-07-05) | **`expenses` collection, CF exclusive, FEAT-041a/b/c planifiées** |
| **FEAT-042** | **Mode de charges (provisions/forfait) + éligibilité régularisation** | M1 | ✅ **done** | PR #68 (2026-07-06) | **`leases.chargeMode`, `resolveChargeMode` CF, `effectiveChargeMode` getter, `canRegularizeCharges` predicate** |
| **FEAT-043** | **Internationalisation FR/EN (i18n)** | Post-M1 | ✅ **done** | PR #71 (2026-07-08) | **gen_l10n + ARB (app_{en,fr}.arb ~800 clés), localeProvider (SharedPreferences), ValidationErrorL10n + AuthErrorL10n, context.l10n extensions, pattern freezed states → l10n présentation** |
| **FEAT-045** | **Suppression de compte in-app + page publique /delete-account** | Mobile/Stores | ✅ **done** | PR #69 (2026-07-07) | **Bloquant Play « Account deletion » + App Store 5.1.1(v) levé — callable `deleteAccount` (purge Firestore+Storage+Auth, quittances conservées 5 ans), re-auth par provider, révocation token Apple, privacy policy v1.2** |
| **FEAT-048** | **FAQ produit publique /faq** | UX/Support | ✅ **done** | feature/045-account-deletion (2026-07-07) | **11 Q/R (quittances loi 1989, essai anonyme, RGPD, suppression, charges…), page publique + tuile Profil → Aide ; hub /profile réordonné (suppression dans Compte)** |
| **FEAT-049** | **SEO du PWA (quick-wins, Option A)** | Growth | ✅ **done** | PR #73 (2026-07-08) | **Enrichissement `web/index.html` (lang/title/description/canonical/OG/Twitter/JSON-LD + bloc statique crawlable), `web/robots.txt` + `robots.staging.txt` + `sitemap.xml`, firebase.json headers + ignore staging, deploy.yml noindex staging (gated APP_ENV=dev)** |
| **FEAT-050** | **Site marketing statique crawlable (Option B)** | Growth | 📋 **planned** | docs/backlog/050-marketing-site-seo.md | **Topologie confirmée : sous-domaine app.baillan.fr (app Flutter noindex) + baillan.fr (site Astro canonique). À démarrer après lancement MVP** |

---

## Détails par feature (Post-MVP M1 + Mobile, session 2026-07-03–07-08)

### FEAT-024 : App mobile iOS/Android — setup complet (2026-07-06)

**Status** : ✅ DONE (merged feature/024-mobile, 2026-07-06)

- **Plateformes** : `flutter create --platforms=android,ios`, applicationId/bundle ID **`com.daki.baillan`** (définitif stores), label « Baillan. »
- **Firebase** : apps android + ios enregistrées sur `easy-rent-54cd4`, web réutilisée ; `firebase_options.dart` régénéré (flutterfire), `google-services.json` + `GoogleService-Info.plist` committés (clés publiques), SHA-1/256 debug déclarées
- **Auth multiplateforme** : `_signInWithOAuthProvider` + `_defaultLinkWithProvider` (popup web / `signInWithProvider`-`linkWithProvider` mobile) ; codes annulation mobile mappés (`web-context-canceled|cancelled`) ; liens email fallback `Env.publicAppUrl`
- **Partage PDF natif** : `web_share_service_io.dart` (ex-stub) — share sheet Android/iOS via `share_plus` (annulation détectée → `sent_at` fiable), data-URL décodée localement ; quittances + régularisations
- **Android** : `<queries>` https+mailto (url_launcher API 30+), minSdk 24
- **iOS** : URL schemes OAuth (REVERSED_CLIENT_ID) dans Info.plist
- **Validation** : analyze clean, 2386 tests ✅, APK debug ✅, smoke test émulateur Pixel 9 ✅
- **Stores conformité** : Play « Account deletion » (FEAT-045 bloquant) levé ; App Store 5.1.1(v) audit [`STORE_COMPLIANCE.md`](../STORE_COMPLIANCE.md)
- **Référence** : [`docs/MOBILE.md`](../MOBILE.md)

---

### FEAT-043 : Internationalisation FR/EN (i18n)

**Status** : ✅ DONE (merged PR #71, 2026-07-08)

**Contenu** :
- **Fondation gen_l10n** : infra Flutter standard (build_runner) + ARB (app_{en,fr}.arb, ~800+ clés)
- **Locale système** : défaut = `MediaQuery.supportedLocalesOf(context)` (Locale du device)
- **Override manuel** : `/profile` → Apparence → Langue (FR/EN) persisté SharedPreferences via `localeProvider` (Riverpod StateProvider)
- **Errors localisés** : `ValidationError` + `AuthError` enums → `ValidationErrorL10n.message(context)` / `AuthErrorL10n.message(context)` extension (lib/core/i18n/l10n_extensions.dart)
- **Pattern freezed** : states Riverpod (ex: `ScenarioFormState`) stockent `.name` (string, immuable) ; présentation via `l10n.buildString(errorName)` pour déleguer UI
- **Coverage** : leases/properties/tenants/payments/receipts/expenses/charge_regularization/simulator/landing/support/pwa/auth/dashboard/profile/**delete_account** (FEAT-045 i18n PR #72) bilingues
- **Note** : partage e-mails, formatters dates/€/octets restent FR (suivi post-M1) — **flux suppression compte est maintenant bilingue FR/EN** via FEAT-045 i18n

**Tests** : l10n_extensions_test.dart, délégations dans tests features, delete_account_page_test avec l10n

---

### FEAT-045 : Suppression de compte in-app + page publique /delete-account (i18n FR/EN)

**Status** : ✅ DONE — Core PR #69 (2026-07-07) + i18n PR #72 (2026-07-08, merge e25f637)

**Contenu FEAT-045 v1 (Core)** :
- **Routes** : `/delete-account` (public, page demande suppression — login/go profil/essai anonyme) + `/profile/delete-account` (suppression compte complet)
- **CF callable `deleteAccount`** :
  - Fraîcheur token : auth_time < 5 min (non-anonymes), anonymes exemptés
  - Quittances conservées 5 ans (loi 6/7/1989) : stamp `receipts` accountDeletedAt + retentionUntil
  - Purge 8 collections (properties, tenants, leases, payments, documents, expenses, investment_scenarios, support_requests) par 400
  - Storage `documents/{uid}/**`
  - Firebase Auth EN DERNIER (retry porté utilisateur)
- **AuthRepository** : `reauthenticateWithOAuthProvider` (popup web / natif mobile) + `revokeAppleToken` (best-effort App Store 5.1.1(v)) + `deleteAccount` callable + signOut
- **UI/UX** : DeleteAccountPage (tuile Profil → hub /profile réordonné Compte/Apparence/Aide/À propos/Session) → avertissement loi + rétention quittances + re-auth provider + checkbox + confirmation dialog
- **Privacy policy** : v1.2 § 5 (suppression) + § 8 (droit à l'effacement in-app) — rgpdConsentVersion inchangé (clarification)

**Contenu FEAT-045 i18n (PR #72)** :
- **Localisation complète** : `DeleteAccountError` enum + `DeleteAccountErrorL10n` extension (pattern FEAT-043)
- **Clés ARB** : `deleteAccount*` + `deleteAccountRequest*` + `profileHubDeleteAccountTile` (app_{en,fr}.arb)
- **Pages & contrôleur** : DeleteAccountPage, DeleteAccountRequestPage, delete_account_controller bilingues (l10n context)
- **Widget profil** : ProfileDeleteAccountTile → tuile Hub Profil bilingue
- **Rétention légale FR** : mentionner « loi n° 89-462 / loi du 6 juillet 1989 » reste systématiquement en FR (appliquer règle l10n_convention.dart §7)

**Tests** : 11 vitest CF + 22 tests Flutter (repo, controller, pages, tuile profil) + test l10n delete_account_page_test.dart

---

### FEAT-048 : FAQ produit publique + réordonnancement hub Profil

**Status** : ✅ DONE (merged PR #69, 2026-07-07)

**Contenu** :
- **Route** : `/faq` (page publique, accessible anonymes + comptes)
- **Contenu** : 11 Q/R rédigées (quittances loi 1989, essai anonyme, RGPD, suppression de compte, charges récupérables/non-récupérables, …)
- **UI** : ExpansionTiles (Material, recherche optionnelle)
- **Access** : lien landing → /faq ; tuile Profil Aide (hub /profile réordonné Compte/Apparence/Aide)
- **Hub Profil nouvel ordre** : Détails → Mot de passe → **Supprimer mon compte** / Apparence (thème, langue FEAT-043) / **Aide** (**FAQ**, contact, confidentialité, CGU) / À propos (version) / Session (déconnexion)

---

### FEAT-042 : Mode de charges (provisions/forfait) + éligibilité régularisation

**Status** : ✅ DONE — merged PR #68 (2026-07-06)

**Contenu** :

- **Nouveau champ** : `leases.chargeMode` (string? = 'provisions' | 'forfait')
  - **Nullable** : migration lazy sans backfill (baux pré-042 = null)
  - Getter Dart `effectiveChargeMode` → dérive depuis `leaseType` si null :
    - `unfurnished` → provisions (forcé, art. 23 loi 6/7/1989)
    - `mobility` → forfait (forcé, loi ELAN art. 25-18)
    - `furnished` | `student` → provisions (défaut sûr)

- **CF Helper** : `resolveChargeMode(leaseType, requested)` — source unique vérité serveur
  - **Coercive** : refuse changements incohérents (ex: forfait sur nu → INVALID_ARGUMENT)
  - Backfill lazy : persiste toujours le mode résolu à la première mutation (matérialise legacy)

- **Forfait constraint** : Si chargeMode==forfait → force `nonRecoverableChargesCents=0` serveur
  - Ventilation interdite (forfait = montant libératoire unique)
  - Valide aussi baux legacy mobilité (effectiveChargeMode=forfait)

- **Éligibilité régularisation** : Getter `canRegularizeCharges` (remplace ancien gate `leaseType==unfurnished`)
  - **Vrai si et seulement si** : `effectiveChargeMode == provisions`
  - Meublé + provisions → régularisable (nouveau)
  - Étudiant + provisions → régularisable (nouveau)
  - Mobilité + forfait → jamais régularisable (ancien + nouveau, forcé)
  - Mobilité legacy → effectiveChargeMode=forfait → jamais régularisable (backcompat)

- **Horloge injectable** : `FirestoreLeaseRepository.listForDisplay({DateTime? now})`
  - Default : `DateTime.now()` production
  - Override : tests déterministes (FEAT-042 fix horloge pour lateness déterministe)

- **Cloud Functions** :
  - `createLease` : `resolveChargeMode(leaseType, data.chargeMode)` + forfait⇒nonRecoverable=0
  - `updateLease` : inconditional re-resolution (même si patch n'y touche pas — legacy enforcement)

**Schéma Firestore** : `leases.chargeMode` (champ nouveau, rétractivement nullable)

**Tests** : lease_repository_firestore_test.dart (horloge injectable)

**Feature** : /leases/:id?action=regularize (découvrabilité FEAT-029b) éligible seulement si `canRegularizeCharges==true`

---

### FEAT-041 : Suivi dépenses unifié (V1)

**Status** : ✅ DONE — V1 merged PR #67 (2026-07-05)

**Contenu FEAT-041a** (Core CRUD) :
- **Nouvelle collection** : `expenses/{id}` (CF exclusive via `createExpense`, `updateExpense`, soft-delete)
- **Champs principaux** :
  - `propertyId` (obligatoire, immuable)
  - `leaseId` (optionnel, immuable si fourni)
  - `nature` : enum 'condo_charges' | 'property_tax' | 'insurance_pno' | 'management_fees' | 'works' | 'repair_maintenance' | 'other'
  - `category` : 'recoverable' (bilancée locataire) | 'non_recoverable' (charge bailleur) — **dérivée serveur depuis nature** (immuable)
  - `categoryOverridden` : bool (trace override si nature.locked==false)
  - `amountCents` : int
  - `expenseDate` : timestamp
  - `periodStart/End` : timestamp (obligatoires si category=='recoverable')
  - `periodYear` : int (dérivé de periodStart ou expenseDate)
  - `documentId` : optional FK → documents
  - `notes` : string (≤ 2000 chars)
  - Denorms : `propertyName`, `tenantLastName` (rafraîchies @ update)

- **Juridique** (décret 87-713) :
  - `NATURE_DEFAULT_CATEGORY` : source unique de vérité (CF expenses.ts)
  - Mapping immuable (nature → {category, locked}) — override interdit si locked==true
  - Table de dérivation répliquée en enum Dart `ExpenseNature` côté client (UI présélection only)

- **Routes** : `/properties/:id/expenses`, `/properties/:id/expenses/new`, `/properties/:id/expenses/:eid/edit`
- **Features** : PropertyExpensesPage (list), ExpenseFormPage (new + pre-fill leaseId), ExpenseEditPage (update)
- **Tests** : deriveExpenseCategory() pure, deriveExpensePeriodYear() pure

**Contenu FEAT-041b** (Documents v2) :
- **Justificatifs dépenses** : category 'expense_receipt' (FEAT-041b)
- **Champs documents** : `expenseId` (optionnel, FK), `propertyId` (optionnel, context)
- **legalHold dérivation** : 'expense_receipt' → legalHold=false (soft-delete autorisé)
- **CF createDocument v2** : validation expenseId ownership, lien bilatéral (documents.expenseId)

**Contenu FEAT-041c** (Régularisation, planné V1.1) :
- **Trigger** (pas encore déployé) : `recomputeChargeRegularization`
  - Déclenché @ expense.category=='recoverable' create/update
  - Alimente `lease.chargeRegularizationFeed` subcollection (draft)
  - Utilisé par charge_regularization feature pour agrégation + avis PDF
- **Intégration** : FEAT-029 charge_regularization + FEAT-041 expenses data feed

**Schéma Firestore** : `expenses` collection (11 fields), 3 composite indexes

**Cloud Functions** :
- `createExpense` : validation cross-entity + juridique category dérivation
- `updateExpense` : re-dérivation category si nature/category changent
- `setUpdatedAtExpenses` : trigger

**Feature FEAT-033 absorbée** : Snapshot figé dépense = `categoryOverridden` + `nature` enum (version immuable contexte juridique) — V1.1 si besoin complet archive

---

### FEAT-036 : Charges récupérables vs non-récupérables

**Status** : ✅ DONE — merged PR #66 (2026-07-05)

**Contenu** :
- **Nouveau champ** : `leases.nonRecoverableChargesCents` (int, ≥ 0)
- **Signification** :
  - `chargesAmountCents` = part RÉCUPÉRABLE (bilancée au locataire via paiement + régularisation FEAT-029)
  - `nonRecoverableChargesCents` = part NON-RÉCUPÉRABLE (informatif bailleur, jamais bilancée) — décret 87-713
- **Pas de total constraint** : aucun champ total persisté (design FEAT-036 § c)

**Cloud Functions** :
- `createLease` : param `nonRecoverableChargesCents` (default 0)
- `updateLease` : mutable field `nonRecoverableChargesCents` (validation ≥ 0)
- Validation CF : aucune contrainte arithmétique (total librement configuré)

**UI** :
- LeaseFormPage : dual input (charges récupérables + non-récupérables)
- LeaseDetailPage : affiche les deux (non-récupérables « informatif bailleur »)
- LeaseEditPage : update dual inputs

**Tests** : validateNonRecoverableCharges() (unitaire post-revue adversariale, commit 87ec342)

**Intégration FEAT-041** : Complément dépenses — `nonRecoverableChargesCents` + `expenses.category='non_recoverable'` tracent charges bailleur (historique)

---

### FEAT-030 : Navigation retour corrigée

**Status** : ✅ DONE (commit 7db144d)

**Contenu** :
- Formulaires (PropertyEditPage, TenantEditPage, LeaseEditPage, PaymentEditPage) → `pop()` retour fiche (pas liste)
- Tuiles Accueil drill-down → `push()` (empilage, retour possible Accueil)
- Simulateur (comptes) → `push()` par-dessus shell (modal-like, non-destructif)
- Bouton Profil retiré fiche bail (contradictoire avec stack — accessible shell)

**Impact** : QA F-1 through F-4 audit (2026-07-04), correctifs UX naviguabilité

---

### FEAT-029b : Découvrabilité régularisation charges

**Status** : ✅ DONE (commit 514666f)

**Contenu** :
- Menu contextuel « Régulariser les charges » sur card/ligne bail nu
- Query param `/leases/:id?action=regularize` → dialog auto-ouvre chargement fiche
- Accessible via FEAT-029 UI (charge_regularization_form)

---

### FEAT-029 V1 : Charges — motif + régularisation annuelle

**Status** : ✅ DONE (commit 871ebff)

**Contenu** :
- **Motif paiement libre** : champ `payment.notes` (string, optional, ≤ 500 chars)
  - Affiché reçu (quittance PDF)
  - Rendu Web Share API
  
- **Régularisation annuelle** (bail nu uniquement) :
  - Route : `/leases/:id?action=regularize`
  - Feature : `lib/features/charge_regularization/**`
  - Calcul provisions prorata (client-side, testable)
  - Solde annuel (provisions vs charges réelles)
  - Avis PDF (charge_regularization_pdf_renderer.dart)
  - Web Share API (fallback mailto://)
  - PAS d'archivage V1 (dépend functions async — FEAT-041c planné)

**Schema** : `lease.chargeRegularizationHistory` (map, optional) — historique

**Tests** : charge_regularization_balance_test.dart

---

### FEAT-028 : Détection retards de paiement corrigée

**Status** : ✅ DONE (commit 7ac1d03)

**Contenu** :
- Fonction pure `isLeaseLate()` (lib/features/leases/domain/lease_lateness.dart)
  - Règle métier : grâce 5j après échéance, pas proratisation 1ᵉʳ mois, couverture période, troncature locale
  
- **LeaseFilter** enum : nouvelle valeur `late` (« En retard ») — priority > renewable > active
  
- **KPI Dashboard** : retards détectés (rouge), drill-down → `/leases?filter=late`
  
- **Pastille UI** : « En retard » sur LeaseCard, LeaseListItem, LeaseDetailPage

- **Provider** : `leaseLatenessProvider` (FutureProvider, dépend payments stream)

**Tests** : lease_lateness_test.dart

---

### FEAT-027 : Dashboard — période graphique sélectionnable

**Status** : ✅ DONE (commit ba7c12d)

**Contenu** :
- **Sélecteur période** : 6 / 12 / 24 mois (toggle buttons)
- **Persistence** : `chartPeriodProvider` (StateProvider) + SharedPreferences
- **Découplage** : `monthlyAmountsProvider` (FutureProvider) dépend `chartPeriodProvider` (watch)
- **UI Polish** : section « Vue d'ensemble » Accueil, graphique défilable, couleurs par état

**Domain** : lib/features/dashboard/domain/chart_period.dart

**Provider** : chartPeriodProvider (non-autoDispose, persisté session)

---

### FEAT-026 : Navigation shell adaptative web+mobile

**Status** : ✅ DONE (commit ca2d10a)

**Contenu** :
- **Shell 5 branches** : Accueil / Biens / Locataires / Baux / Profil
  - `StatefulShellRoute.indexedStack` (état préservé par branche)
  
- **Responsive** :
  - <600px : NavigationBar bottom (5 destinations)
  - ≥600px : NavigationRail left (5 destinations, repliable)
  
- **Rail repliable** : `railExpandedProvider` (StateProvider, SharedPreferences)
  - Compact : icônes seules
  - Étendu : icônes + libellés full
  
- **Marque Baillan** : entête rail/navbar (logo + wordmark)

- **Hors-shell** : Landing / Auth / Légal / Simulateur (toutes tailles)

**Widgets** : AdaptiveNavigationScaffold, BrandMark, RailExpandedStorage

**Tests** : app navigation integration tests

---

### FEAT-025b : /profile HUB de réglages (mobile-first)

**Status** : ✅ DONE (commit 16ebc77)

**Contenu** :
- ProfilePage refondu : tuiles (cards) au lieu de liste classique
- Sous-pages : `/profile/details`, `/profile/password`, `/profile/support`
- Mobile-first : tuiles full-width, stack vertical

---

### FEAT-025 : Sécurité + support in-app

**Status** : ✅ DONE (commits 0cd54de, f5734b4)

**Contenu** :
- **Changement de mot de passe** (comptes email only) :
  - Route : `/profile/password` (ChangePasswordPage)
  - Workflow : reauthenticateWithPassword() + updatePassword()
  - Gate : `hasPasswordProvider`
  
- **Support formulaire** (« Nous contacter ») :
  - Route : `/profile/support` (SupportPage)
  - Collection : **`support_requests`** (create-only)
  - Schéma : landlordId, email, subject (≤120), message (≤2000), appVersion, appEnv, status='new', createdAt
  
- **RGPD consent** : version v1-2026-06 → v2-2026-07 (CGU v1.0 + politique v1.0)
  - Sync : auth_repository.dart + finalize_anonymous_upgrade.ts

**Widgets** : ChangePasswordForm, SupportForm

**Tests** : support_form_test.dart, change_password_test.dart

---

### FEAT-023 : Réglages app (thème + légal + version)

**Status** : ✅ DONE

**Contenu** :
- **Thème** : Système / Clair / Sombre (themeModeProvider, SharedPreferences)
- **Liens légaux** : `/terms` (CGU) + `/privacy` (Politique)
- **À propos** : version app (package_info_plus) → « Baillan v1.0.0 (build 123) »
- **Page /terms** : CGU v1.0 (2026-07-03)

**Widgets** : ThemeModeSelector, VersionDisplay

**Dependencies** : package_info_plus v9.0.1

---

### FEAT-049 : SEO du PWA (quick-wins, Option A)

**Status** : ✅ DONE (merged PR #73, 2026-07-08)

**Contenu** :
- **Fait structurant** : Flutter Web CanvasKit peint le contenu dans un `<canvas>` → crawlers n'indexent QUE le DOM, pas les pixels canvas.
- **Stratégie A (quick-wins, déployée)** :
  - **`web/index.html` enrichi** : `<html lang="fr">`, title/description riches (mots-clés tête), `<link rel="canonical">` auto-référent, Open Graph (og:title/description/image/url/type/locale/site_name), Twitter Card
  - **JSON-LD structuré** : 3 blocs (Organization, SoftwareApplication + applicationCategory/offers, WebSite)
  - **Bloc HTML statique crawlable** : en tête de `<body>` avant scripts de boot FEAT-019 (H1 + copy landing + liens internes), invisible via CSS (`clip`) → respecte a11y, flutter le remplace au boot
  - **`web/robots.txt`** (prod) : Allow: / sauf sections privées (/dashboard, /properties, /tenants, /leases, /profile, /reset-password), reference sitemap
  - **`web/robots.staging.txt`** : Disallow: * (bloquant total, appliqué par `.github/workflows/deploy.yml` sur APP_ENV=dev)
  - **`web/sitemap.xml`** : URLs publiques (/, /faq, /privacy, /terms, /delete-account, /simulator), domain-paramétrisé placeholder
  - **`firebase.json` headers** : Cache-Control robots/sitemap (1h), ignore `robots.staging.txt` en deploy
  - **`.github/workflows/deploy.yml` étape « noindex staging »** : swap robots, retire sitemap, bascule `<meta robots>` en noindex (gated APP_ENV=dev)
- **Références** : `docs/SEO.md` (stratégie complète + checklist lancement domaine custom), `web/index.html` commentaires §3-4
- **Impact SEO** : partage social propre, metadata valides, crawl produit guidé, staging protégé contre indexation accidentelle

---

### FEAT-050 : Site marketing statique crawlable (Option B)

**Status** : 📋 PLANNED (cadré, attendre après lancement MVP)

**Contenu** :
- **Contexte** : Option A (FEAT-049) gère la home. Option B est le SEUL levier pour ranker sur non-brand keywords (« simulateur investissement immobilier », « régularisation charges locatives », etc.) et i18n-SEO réelle (URLs avec `/fr/` `/en/`)
- **Topologie confirmée** :
  - **Domaine principal** : `baillan.fr` (site Astro/Hugo statique pré-rendu, landing/blog/outils/guides, contenu crawlable par page)
  - **Sous-domaine app** : `app.baillan.fr` (app Flutter CanvasKit, noindex, cible domaine canonique)
  - **Implications** : base-href Flutter `/`, redirects post-login vers app.baillan.fr, OAuth callback dual-domaine, manifest `start_url`, i18n pipeline contenu (ARB → markdown/frontmatter)
- **Spec détaillée** : `docs/backlog/050-marketing-site-seo.md`
- **Dépendances** : FEAT-049 complet (staging noindex opérationnel), domaine custom provisioning
- **Timing** : Post-lancement MVP (après que les stores et mobile soient stables)

---

## Détails par feature (MVP)

_(Features FEAT-001 à FEAT-022 résumées, tous ✅ DONE — cf. version antérieure FEATURES.md pour détails complets)_

---

## Roadmap Post-MVP (priorité)

| ID | Nom | Phase | Status | Notes |
|---|---|---|---|---|
| **FEAT-049** | **SEO du PWA (quick-wins, Option A)** | Growth | ✅ **done** | **Metadata enrichies, robots/sitemap, noindex staging, JSON-LD, bloc HTML statique crawlable** |
| **FEAT-050** | **Site marketing statique (Option B)** | Growth | 📋 planned | **Topologie confirmée (baillan.fr statique + app.baillan.fr Flask), attendre post-lancement** |
| **FEAT-031** | **Rappels paiement automatiques** | Post-M1 | 📋 planned | **Cloud Scheduler + Trigger Email, attente infra email** |
| **FEAT-032** | **Dashboard — Trésorerie graphique** | Post-M1 | 📋 planned | Encaissé vs dû, détection retards intégré |
| **FEAT-033** | **Archivage régularisations charges** | Post-M1 | 💡 idea | **FEAT-041 V1 a absorbé snapshot figé — reliquat V1.1** |
| **FEAT-034** | **Import multi-colonnes** | Post-M1 | 📋 planned | Properties/tenants/leases CSV import |
| **FEAT-035** | **2FA TOTP** | Post-M2 | 📋 planned | Authenticator app integration |
| P2-001 | Intégration bancaire | — | 💡 idea | Rapprochement virement auto |
| P2-002 | App native Capacitor | — | 💡 idea | iOS + Android distributed |

---

## Statut Commits Récents

```
650b62f develop (HEAD) — docs: FEAT-049/050 dans roadmap + backlog (section Croissance/SEO) (2026-07-08)
d340bf6 docs(backlog): FEAT-050 — topologie confirmée (sous-domaine)
409bfa4 docs(backlog): FEAT-050 — cadrage site marketing statique (SEO Option B)
bde1862 Merge pull request #73 from dtruong21/feature/049-seo
72d60fe feat(seo): FEAT-049 — quick-wins SEO (meta/OG/JSON-LD, robots, sitemap, noindex staging)
a9fee64 chore(seo): FEAT-049 — agent seo-specialist + workflow seo-audit (pipeline Growth)
9a03fb5 docs(state): rafraîchit le cache après merges FEAT-043/045/048/024
205188b Merge pull request #71 from dtruong21/feature/043-i18n
1934c9d fix(i18n): FEAT-043 — delete_account _mapAuthError gère popup OAuth annulée
604e109 test(i18n): FEAT-043 — délégués l10n dans delete_account_page_test
```

---

## Résumé Phase Actuelle

**MVP** : ✅ COMPLETE (FEAT-001–030, production-ready staging)
**Post-MVP M1** : ✅ COMPLETE (FEAT-001–042, `expenses` collection + charge modes live, Firestore camelCase stable)
**Mobile + Stores prep** : ✅ COMPLETE (FEAT-024 iOS/Android setup, FEAT-043 i18n FR/EN, FEAT-045 suppression compte, FEAT-048 FAQ — prêt release mobile)
**Growth — SEO** : ✅ COMPLETE (FEAT-049 quick-wins live, metadata/robots/sitemap/noindex-staging déployés ; FEAT-050 topologie confirmée, attendre post-lancement)
**Agents pipeline** : agent `seo-specialist.md` + workflow `seo-audit.js` enregistrés pour phase Growth
**Prochaines** : FEAT-031 (rappels email, attente infra), FEAT-032 (graph trésorerie), FEAT-034 (import CSV), FEAT-035 (2FA TOTP)
