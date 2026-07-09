# Project State Index

> **Snapshot vivant du projet EasyRent.** Maintenu par l'agent `state-keeper`. Source de vérité pour les agents — à lire AVANT de grep/scanner le codebase.

## Métadonnées

- **Dernière mise à jour** : 2026-07-08T14:30:00Z
- **Commit ref** : `650b62f` (develop, FEAT-049 SEO quick-wins + FEAT-050 cadrage site marketing)
- **Branche** : `develop`
- **Phase projet** : MVP ✅ + Post-MVP M1 ✅ + Mobile + Stores ✅ (FEAT-024 iOS/Android, FEAT-043 i18n FR/EN, FEAT-045 suppression, FEAT-048 FAQ) + Growth/SEO ✅ (FEAT-049 quick-wins, FEAT-050 topologie confirmée)

## Pointeurs

| Aspect du projet | Fichier | Contenu clé |
|---|---|---|
| Schéma Firestore (collections, rules, indexes) | [`SCHEMA.md`](SCHEMA.md) | **11 collections** (+ `expenses` FEAT-041), 28+ composite indexes, 3-couche rules, Firestore camelCase, **chargeMode FEAT-042**, **receipts.accountDeletedAt/retentionUntil FEAT-045** |
| Routes Flutter et gardiennage d'accès | [`ROUTES.md`](ROUTES.md) | 3-state router, 50+ routes, deep linking, `/properties/:id/expenses*` (FEAT-041), **/faq, /delete-account, /profile/delete-account** (FEAT-045/048) |
| Features implémentées et statut | [`FEATURES.md`](FEATURES.md) | FEAT-001–050, MVP ✅ + Post-MVP M1 ✅ + Mobile ✅ (FEAT-024 iOS/Android, FEAT-043 i18n, FEAT-045 deletion, FEAT-048 FAQ merged) + Growth ✅ (FEAT-049 SEO quick-wins merged, FEAT-050 topologie confirmée) |
| Dépendances pubspec + functions + Firebase | [`DEPENDENCIES.md`](DEPENDENCIES.md) | Firebase 3.6+, Riverpod 2.6, Node.js 20 |
| Cloud Functions (callables, triggers, scheduled) | [`FUNCTIONS.md`](FUNCTIONS.md) | **28 callables** (+ `deleteAccount` FEAT-045) + 8 triggers + 1 scheduled; **`resolveChargeMode` FEAT-042 helper** |
| Thème Baillan + dark mode | [`THEME.md`](THEME.md) | Palette papier/encre/olive (FEAT-020), `ColorScheme` écrit main (plus de seed), EB Garamond serif, `themeMode` utilisateur |
| Design tokens (sémantique métier) | [`DESIGN_TOKENS.md`](DESIGN_TOKENS.md) | Couleurs (error, warning, success), spacing (4dp grid) |

## Comment l'utiliser

**Tu es un agent IA travaillant sur EasyRent ?**

1. Lis ce fichier en premier. Repère la date de mise à jour.
2. Si la date est < 7 jours → fais confiance aux fichiers d'état listés ci-dessus.
3. Si la date est ≥ 7 jours OU manquante → flag-le à l'utilisateur et propose `/refresh-state` AVANT de continuer.
4. Ne grep/scan le codebase QUE si l'état ne couvre pas ton besoin.

**Économie attendue** : un agent qui consulte `SCHEMA.md` (250 tokens) au lieu de grep Firestore rules (3000 tokens) divise sa consommation par 12.

## Quand mettre à jour cet état

- Après chaque feature mergée → `state-keeper` met à jour automatiquement
- Avant un sprint de features → `/refresh-state` pour reset propre
- Si un agent détecte une incohérence → flag immédiat à l'utilisateur

## Stack résumé

| Couche | Tech | Notes |
|---|---|---|
| **Frontend** | Flutter 3.x + Dart 3.11+ (web + Android + iOS, FEAT-024) | PWA CanvasKit web, natif mobile `com.daki.baillan`, EB Garamond serif |
| **State** | Riverpod 2.6.0 | StreamProvider FirebaseAuth + Firestore snapshots |
| **Navigation** | GoRouter 14.6.0 | 3-state redirect guard (via sessionStateProvider) |
| **Auth** | Firebase Auth native | Email/password + Google + Apple + anonymous tier |
| **Backend** | Firestore + Cloud Functions | Node.js 20, vitest, 28 indexes, 3-couche rules |
| **Storage** | Firebase Storage | /documents/, /receipts/, signed URLs 5 min |
| **PDF** | pdf (rendu) + share_plus (partage mobile) | Quittance loi 6 juillet 1989 |
| **Build** | build_runner + freezed + json_serializable | Code generation, no reflection |
| **Hosting** | Firebase Hosting | Staging + prod channels, CSP (fonts.gstatic.com) |
| **CI/CD** | GitHub Actions | ci.yml (format + analyze) + deploy.yml (manual channel) |

## Changements récents (2026-07-03 — 2026-07-08)

### FEAT-049 : SEO du PWA (quick-wins, Option A)

**Status** : ✅ DONE (merged PR #73, 2026-07-08)

- **Contenu enrichi** : `web/index.html` avec `<html lang="fr">`, title/description riches (mots-clés tête), Open Graph + Twitter Card, JSON-LD (Organization/SoftwareApplication/WebSite), bloc HTML statique crawlable en tête de `<body>` (texte visible crawlers + a11y-compatible)
- **Plomberie SEO** : `web/robots.txt` (prod Allow + reference sitemap), `web/robots.staging.txt` (Disallow *), `web/sitemap.xml` (URLs publiques, domaine-paramétrisé), `firebase.json` headers (Cache-Control 1h robots/sitemap, ignore robots.staging.txt)
- **Noindex staging** : `.github/workflows/deploy.yml` étape (gated APP_ENV=dev) → swap robots, retire sitemap, bascule meta robots en noindex
- **Pipeline Growth** : agent `.claude/agents/seo-specialist.md` + workflow `.claude/workflows/seo-audit.js` enregistrés
- **Documentation** : `docs/SEO.md` stratégie complète (Option A/B/C, fait structurant CanvasKit, audit checklist)
- **Note** : Fait structurant = Flutter CanvasKit peint canvas (non indexable) → Option A = quick-wins (partage social), Option B (site marketing statique) = seul vrai levier non-brand keywords

### FEAT-050 : Site marketing statique crawlable (Option B)

**Status** : 📋 PLANNED (cadré, attendre post-lancement MVP)

- **Topologie confirmée** : `baillan.fr` (site Astro/Hugo statique, landing/blog/outils/guides, contenu crawlable par page) + `app.baillan.fr` (app Flutter, noindex, cible canonique)
- **Dépendances** : FEAT-049 complet (noindex staging opérationnel), domaine custom provisionné
- **Spec détaillée** : `docs/backlog/050-marketing-site-seo.md`
- **Timing** : Post-lancement MVP (après stores + mobile stabilisés) — cible phase croissance SEO

## Changements précédents (2026-07-03 — 2026-07-08)

### FEAT-043 : Internationalisation FR/EN (i18n)

**Status** : ✅ DONE (merged PR #71, 2026-07-08)

- **Fondation gen_l10n** : ARB files (app_{en,fr}.arb ~800+ clés), localeProvider (SharedPreferences), locale système défaut
- **Errors localisés** : ValidationError + AuthError → ValidationErrorL10n.message(context) / AuthErrorL10n.message(context)
- **Pattern freezed** : states stockent error `.name` (string) → présentation via l10n extensions
- **Coverage** : toutes les features bilingues (leases, properties, tenants, payments, receipts, expenses, charge_regularization, simulator, landing, support, auth, dashboard, profile)
- **Note** : flux suppression compte, e-mails, formatters dates/€ restent FR (suivi post-M1)

### FEAT-048 : FAQ produit publique + réordonnancement hub Profil

**Status** : ✅ DONE (merged PR #69, 2026-07-07)

- **Route** : `/faq` (page publique, anonymes+comptes)
- **Contenu** : 11 Q/R (quittances loi 1989, essai anonyme, RGPD, suppression, charges…)
- **UI** : ExpansionTiles, accessible lien landing + tuile Profil Aide
- **Hub Profil réordonné** : Compte (détails, mot de passe, **suppression**) / Apparence / Aide (**FAQ**, contact, légal) / À propos / Session

### FEAT-045 : Suppression de compte in-app + page publique /delete-account

**Status** : ✅ DONE (merged PR #69, 2026-07-07)

- **Bloquant stores levé** : Google Play « Account deletion » (13327111) + App Store 5.1.1(v) — cf. [docs/STORE_COMPLIANCE.md](../STORE_COMPLIANCE.md)
- **CF callable `deleteAccount`** : garde fraîcheur token (auth_time < 5 min, anonymes exemptés), quittances CONSERVÉES 5 ans (loi 6/07/1989, stamp accountDeletedAt + retentionUntil), hard-delete paginé 8 collections + singletons + Storage documents/{uid}/, Auth supprimé EN DERNIER (retry porté par l'utilisateur)
- **AuthRepository** : `reauthenticateWithOAuthProvider` (popup web / provider natif mobile), `revokeAppleToken` (best-effort, App Store 5.1.1(v)), `deleteAccount` (callable + signOut)
- **UI** : tuile « Supprimer mon compte » (hub /profile) → `/profile/delete-account` (avertissement + rétention quittances annoncée + re-auth par provider + checkbox + dialog) ; page publique `/delete-account` (URL fiche Play, essai anonyme supprimable directement)
- **Privacy policy v1.2** : §5 suppression de compte + rétention quittances, §8 droit à l'effacement in-app (rgpdConsentVersion inchangé — clarification, pas de nouvelle finalité)
- **Tests** : 11 vitest CF + 22 tests Flutter (repo, controller, 2 pages widget, tuile profil)

### FEAT-024 : App mobile iOS/Android — setup + parité (2026-07-06)

**Status** : ✅ DONE (merged feature/024-mobile, 2026-07-06)

- **Plateformes natives** : `android/` + `ios/` ajoutées au projet (une seule base de code) — applicationId/bundle ID **`com.daki.baillan`** (définitif stores)
- **Firebase** : apps Android + iOS enregistrées sur `easy-rent-54cd4`, `firebase_options.dart` couvre web/android/ios, SHA debug déclarées
- **Auth** : OAuth Google/Apple via `signInWithProvider`/`linkWithProvider` sur mobile (popup conservé web) ; liens email fallback `Env.publicAppUrl`
- **Partage quittances/régularisations** : share sheet natif `share_plus` (`web_share_service_io.dart`, annulation détectée → invariant `sent_at` préservé)
- **Validé** : analyze clean, 2386 tests, APK debug, parcours anonyme complet sur émulateur Pixel 9, build iOS simulateur
- **Conformité stores (2026-07-07)** : audit complet Play/App Store/UE dans [`STORE_COMPLIANCE.md`](../STORE_COMPLIANCE.md) — targetSdk 36 conforme (SDK 37 requis ~08/2027), PrivacyInfo.xcprivacy + ITSAppUsesNonExemptEncryption faits ; **bloquants release** : suppression de compte in-app (FEAT-045), formulaires consoles, DSA trader, mentions LCEN
- **Reste** : FEAT-045 + signing release, capability Apple Sign-In, icônes natives, QA devices — détail dans [`MOBILE.md`](../MOBILE.md)

### FEAT-042 : Mode de charges (provisions/forfait) + éligibilité régularisation

**Status** : ✅ DONE (merged PR #68, 2026-07-06)

- **Nouveau champ** : `leases.chargeMode` (string?, 'provisions' | 'forfait')
- **Migration lazy** : null dérivé du leaseType (nu→provisions, mobilité→forfait)
- **CF helper** : `resolveChargeMode(leaseType, requested)` — source vérité serveur (type↔mode cohérence)
- **Forfait constraint** : nonRecoverableChargesCents forcé à 0 (ventilation interdite)
- **Éligibilité régularisation** : Prédicat `canRegularizeCharges` (effectiveChargeMode==provisions, remplace ancien gate)
- **Horloge injectable** : `listForDisplay({DateTime? now})` — tests déterministes (FEAT-042 fix lateness)
- **Dart domain** : `lib/features/leases/domain/{lease.dart, charge_mode.dart}` — getters calculés, enum + coercion

### FEAT-041 : Suivi dépenses unifié (V1)

**Status** : ✅ DONE (merged PR #67, 2026-07-05)

- **Nouvelle collection** : `expenses/{id}` (CF exclusive, `createExpense`/`updateExpense`/`softDeleteEntity`)
- **Juridique** : `NATURE_DEFAULT_CATEGORY` (décret 87-713) — category dérivée serveur depuis nature (immuable, sauf override autorisé)
- **Nature enum** : 'condo_charges' | 'property_tax' | 'insurance_pno' | 'management_fees' | 'works' | 'repair_maintenance' | 'other'
- **Category** : 'recoverable' (bilancée locataire) | 'non_recoverable' (charge bailleur)
- **Champs** : propertyId (obligatoire), leaseId (optionnel), nature, category, categoryOverridden, amountCents, expenseDate, periodStart/End (si recoverable), notes
- **Routes** : `/properties/:id/expenses`, `/properties/:id/expenses/new`, `/properties/:id/expenses/:eid/edit`
- **FEAT-041b** : Documents v2 (category 'expense_receipt', lien bilatéral documents.expenseId)
- **FEAT-041c** (planné V1.1) : `recomputeChargeRegularization` trigger → charge_regularization feed
- **Firestore indexes** : 3 composites (propertyId, category/periodYear, etc.)
- **CloudFunctions** : 2 callables (`createExpense`, `updateExpense`) + 1 trigger (`setUpdatedAtExpenses`)

### FEAT-036 : Charges récupérables vs non-récupérables

**Status** : ✅ DONE (merged PR #66, 2026-07-05)

- **Nouveau champ** : `leases.nonRecoverableChargesCents` (int, ≥ 0)
- **Signification** : `chargesAmountCents` = récupérable (bilancée), `nonRecoverableChargesCents` = informatif bailleur (décret 87-713)
- **UI** : LeaseFormPage + LeaseEditPage dual inputs (charges récupérables + non-récupérables)
- **CloudFunctions** : `createLease`/`updateLease` supportent param (default 0)
- **Tests** : validateNonRecoverableCharges() (commit 87ec342, post-revue adversariale)
- **Intégration FEAT-041** : Complément dépenses (expenses.category='non_recoverable' traces charges bailleur)

### FEAT-030 : Navigation retour corrigée

**Status** : ✅ DONE (commit 7db144d)

- Formulaires → pop() (retour fiche, pas index list)
- Tuiles Accueil → push() (stack conservée)
- Bouton Profil retiré de la fiche bail
- Simulateur → push() par-dessus shell

### FEAT-029b : Découvrabilité régularisation

**Status** : ✅ DONE (commit 514666f)

- Menu « Régulariser les charges » sur carte/ligne bail nu
- `/leases/:id?action=regularize` auto-ouvre dialog

### FEAT-029 V1 : Charges — motif + régularisation

**Status** : ✅ DONE (commit 871ebff)

- Motif libre sur reçu (payment.notes → PDF)
- Régularisation annuelle (bail nu) : `lib/features/charge_regularization/**`
- Calcul provisions client + avis PDF partagé (Web Share)
- PAS d'archivage (V2, dépend functions)

### FEAT-028 : Détection retards corrigée

**Status** : ✅ DONE (commit 7ac1d03)

- `lease_lateness.dart` : isLeaseLate() testable, règle métier (grâce 5j, pas prorata 1ᵉʳ mois, couverture périodes)
- LeaseFilter.late + KPI drill-down
- Pastille « En retard » sur cartes/tableau/fiche
- Priority affichage : en retard > renewable > active

### FEAT-027 : Dashboard — période graphique sélectionnable

**Status** : ✅ DONE (commit ba7c12d)

- chartPeriodProvider (6/12/24 mois) persisté SharedPreferences
- monthlyAmountsProvider découplé
- UI ✅, polish Accueil ✅

### FEAT-026 : Navigation shell adaptative

**Status** : ✅ DONE (commit ca2d10a)

- StatefulShellRoute.indexedStack 5 branches (Accueil/Biens/Locataires/Baux/Profil)
- Responsive : NavigationBar <600px / NavigationRail ≥600px repliable
- railExpandedProvider persisté
- Marque Baillan en tête (BrandMark logo + wordmark)
- Simulateur + landing + auth + légal hors shell (3-états inchangée)

### FEAT-025b : /profile HUB de réglages

**Status** : ✅ DONE (commit 16ebc77)

- ProfilePage tuiles + sous-pages mobil-first
- `/profile/details`, `/profile/password`, `/profile/support`
- Sécurité + support injectées

### FEAT-025 : Sécurité + support

**Status** : ✅ DONE (commits 0cd54de, f5734b4)

- Changement de mot de passe in-app (reauthenticateWithPassword + updatePassword, gate hasPasswordProvider)
- Support : formulaire « Nous contacter » → **nouvelle collection `support_requests`** (create-only, rules : isFullyAuthed + landlordId==uid + bornes sujet≤120/message≤2000 + status 'new' + createdAt==request.time)
- Politique de confidentialité v1.1

### FEAT-023 : Réglages app

**Status** : ✅ DONE

- Thème Système/Clair/Sombre persisté (themeModeProvider, SharedPreferences)
- Liens légaux (/terms + /privacy)
- Section « À propos » (version via package_info_plus)

### CGU v2-2026-07

**Status** : ✅ DONE

- Page `/terms` (publique, FEAT-023)
- Acceptation CGU + confidentialité au signup
- rgpdConsentVersion bumpé : `v1-2026-06` → `v2-2026-07`
- Sync : auth_repository.dart + functions finalize_anonymous_upgrade

### Functions : handleNewUser supprimé

**Status** : ✅ DONE (commit 90eb86f)

- ADR 0001 : GCIP non activé (assumé)
- handleNewUser (beforeUserCreated blocking trigger) **supprimé** → deploy functions débloqué
- Provisioning landlord **100 % client** (auth_repository.dart, signUp*/link*/signInAnonymously)
- build = tsc -p tsconfig.build.json

### FEAT-018 : Simulateur investissement

**Status** : ✅ DONE

- `/simulator` (list/create) + `/simulator/:id` (edit)
- Accessible anonymes + comptes (investment_scenarios CRUD direct)

## Audit incohérences (2026-07-06)

À la date 2026-07-06 (après merge FEAT-036 + FEAT-041 V1 + FEAT-042, commit 6367a8c) :

- **✅ Collections Firestore cohérentes** : **11 collections** (landlords, properties, tenants, leases, payments, receipts, documents, **expenses (NEW FEAT-041)**, investment_scenarios, paid_plan_interest, support_requests) — Firestore camelCase stable
- **✅ Règles de sécurité complètes** : 3 couches (rules + CF + triggers), isFullyAuthed() + isAnonymous(), soft-delete filters systématiques, expenses CF exclusive (cross-entity + juridique validation)
- **✅ 28+ composite indexes** : Couvrent tous les soft-delete + cross-filters, zéro WHERE field==null sans index (includes expenses 3 indexes)
- **✅ Cloud Functions** : **27 callables** (lease, payment, receipt, document, soft-delete, anonymous-upgrade, **createExpense, updateExpense** FEAT-041) + **8 triggers** (setUpdatedAt×8 includes expenses, recomputeReceiptStale) + 1 scheduled (cleanupExpiredAnon)
- **✅ Routes cohérentes** : **45+ GoRouter routes**, 3-state guard via sessionStateProvider (unauthenticated / anonymous / fullyAuthenticated), **`/properties/:id/expenses*` (FEAT-041)** intégrées
- **✅ Features mappées** : FEAT-001–041 V1 tous dans FEATURES.md, matrice + statut + commits, FEAT-036 + FEAT-041 merged
- **✅ Dépendances déclarées** : pubspec.yaml (23 packages + package_info_plus), functions/package.json (firebase-admin/functions), firebase.json (CSP fonts.gstatic.com)
- **✅ Routes cohérentes shell** : StatefulShellRoute.indexedStack 5 branches, NavigationBar <600px / NavigationRail ≥600px repliable (railExpandedProvider persisté)
- **✅ Persistence utilisateur** : themeModeProvider (thème) + chartPeriodProvider (période) + railExpandedProvider (nav collapsed) via SharedPreferences
- **✅ Anonyme tier system** : BAILLAN-M1 complet (14j essai, upgrade transactionnel, quit demo dialog)
- **✅ FEAT-036 intégration** : nonRecoverableChargesCents + chargesAmountCents dual tracking (leases), validation CF, tests coverage
- **✅ FEAT-041 V1 intégration** : expenses collection live + juridique category derivation (NATURE_DEFAULT_CATEGORY) + FEAT-041b docs v2 (expense_receipt category) + routes PropertyExpensesPage
- **✅ FEAT-041c planné** : recomputeChargeRegularization trigger (attendre V1.1, non déployé)
- **✅ FEAT-042 intégration** : chargeMode champ nullable + resolveChargeMode CF helper (type↔mode cohérence) + effectiveChargeMode getter + canRegularizeCharges predicate (remplace ancien gate leaseType==unfurnished) + forfait⇒nonRecoverable=0 forcing + horloge injectable listForDisplay

## Prochaines étapes (priorité)

### P1 (Post-MVP M1, juillet 2026)

- **FEAT-031** : Notifications email paiements retard (Cloud Scheduler + Trigger Email extension)
- **FEAT-032** : Dashboard — graphique « Trésorerie » (encaissé vs dû, détection retards intégré)
- **FEAT-033** : Archivage régularisations charges (V2, dépend functions)
- **FEAT-034** : Import multi-colonnes (properties CSV, tenants CSV, leases CSV)

### P2 (Post-MVP M2, août 2026)

- **FEAT-035** : 2FA TOTP (authenticator) — ProfilePage security section
- **FEAT-036** : Audit trail (logs immuables, Firestore subcollection)
- **FEAT-037** : Web Share amélioré (fallback email + clipboard copy)
- **Staging dédié** : GitHub Actions manual channel deploy (actuellement main)

### P3 (nice-to-have)

- **Riverpod 3.x upgrade** : Breaking changes, codegen refactor
- **GoRouter 17.x upgrade** : API reshaping, breaking navigation changes
- **OCR de baux scannés** : Firebase ML Kit + document ingestion
- ~~App native Capacitor~~ → **FEAT-024** : cibles natives Flutter iOS/Android (en cours, 2026-07-06)

## Dépendances P2 backlog (version upgrades)

| Package | Current | Latest | Raison |
|---|---|---|---|
| `flutter_riverpod` | 2.6.0 | 3.x | Breaking changes, codegen refactor |
| `go_router` | 14.6.0 | 17.x | Breaking changes, API reshaping |
| `freezed` | 2.5.7 | 3.x | Breaking changes, output format |

**Recommandation** : Attendre sprint dédié (MVP complet → versions mineures ensuite).

## Contacts et ressources

| Rôle | Resource |
|---|---|
| Conventions code | [`docs/CONVENTIONS.md`](../CONVENTIONS.md) |
| Contraintes légales | [`docs/LEGAL.md`](../LEGAL.md) |
| Roadmap détaillé | [`docs/ROADMAP.md`](../ROADMAP.md) |
| Backlog ordonné | [`docs/BACKLOG.md`](../BACKLOG.md) |
| Pipeline agents | [`docs/AGENTS.md`](../AGENTS.md) |

## Stack technique détaillé (pour copilote)

```
Frontend:
  Framework: Flutter Web 3.x
  Lang: Dart 3.11+
  State: Riverpod 2.6.0 (StreamProvider, FutureProvider, family)
  Navigation: GoRouter 14.6.0 + custom transitions (fade/standard)
  
Auth:
  Firebase Auth native (email/password + Google + Apple + anonymous)
  Custom claims: firebase.sign_in_provider (anonymous detection)
  Session: SessionState enum (3-branch) via StreamProvider + Firestore cache
  
Backend:
  Firestore collections: landlords, properties, tenants, leases, payments,
                         receipts (accountDeletedAt/retentionUntil FEAT-045), documents,
                         expenses (FEAT-041), investment_scenarios, paid_plan_interest,
                         support_requests (FEAT-025)
  Cloud Functions: 28 callables + 8 triggers + 1 scheduled (Node.js 20)
                   FEAT-041: createExpense, updateExpense, setUpdatedAtExpenses
                   FEAT-045: deleteAccount (RGPD art. 17, rétention quittances 5 ans)
  Storage: signed URLs (5 min), documents + receipts buckets
  
Security:
  Firestore rules: isFullyAuthed() + isAnonymous() + isOwner() + preservesImmutables()
  Cloud Functions: Admin SDK (bypass rules, cross-entity validation)
  RLS: soft-delete filters (28 composite indexes)
  
PDF + Legal:
  pdf (rendu) + share_plus (partage mobile) packages
  Quittance loi 6 juillet 1989 (rétention 5 ans, immuable)
  Web Share API native (fallback mailto://)
  
Hosting:
  Firebase Hosting (staging + prod channels)
  CSP: default-src 'self'; fonts.gstatic.com; unsafe-inline (CanvasKit)
  Service worker: offline shell
  
Build:
  build_runner + freezed (immutable models) + json_serializable (serde)
  CI: dart format (all files), flutter analyze, tests
  Deploy: firebase deploy --only functions + manual channel selection
```
