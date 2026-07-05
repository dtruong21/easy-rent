# Project State Index

> **Snapshot vivant du projet EasyRent.** Maintenu par l'agent `state-keeper`. Source de vérité pour les agents — à lire AVANT de grep/scanner le codebase.

## Métadonnées

- **Dernière mise à jour** : 2026-07-05T18:30:00Z
- **Commit ref** : `bea8693` (feature/anon-auth-m1 tip, 2026-07-05)
- **Branche** : `feature/anon-auth-m1`
- **Phase projet** : MVP ✅ + Post-MVP M1 ✅ (FEAT-001–030, production-ready staging)

## Pointeurs

| Aspect du projet | Fichier | Contenu clé |
|---|---|---|
| Schéma Firestore (collections, rules, indexes) | [`SCHEMA.md`](SCHEMA.md) | 9 collections, 28 composite indexes, 3-couche rules |
| Routes Flutter et gardiennage d'accès | [`ROUTES.md`](ROUTES.md) | 3-state router, 30+ routes, deep linking |
| Features implémentées et statut | [`FEATURES.md`](FEATURES.md) | FEAT-001–022, MVP ✅ + post-MVP priorité |
| Dépendances pubspec + functions + Firebase | [`DEPENDENCIES.md`](DEPENDENCIES.md) | Firebase 3.6+, Riverpod 2.6, Node.js 20 |
| Cloud Functions (callables, triggers, scheduled) | [`FUNCTIONS.md`](FUNCTIONS.md) | 14 callable + 8 triggers + 1 scheduled, TypeScript vitest |
| Material 3 theme + dark mode | [`THEME.md`](THEME.md) | Indigo palette, EB Garamond serif, shadows |
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
| **Frontend** | Flutter Web 3.x + Dart 3.11+ | PWA, Canvas Kit, EB Garamond serif |
| **State** | Riverpod 2.6.0 | StreamProvider FirebaseAuth + Firestore snapshots |
| **Navigation** | GoRouter 14.6.0 | 3-state redirect guard (via sessionStateProvider) |
| **Auth** | Firebase Auth native | Email/password + Google + Apple + anonymous tier |
| **Backend** | Firestore + Cloud Functions | Node.js 20, vitest, 28 indexes, 3-couche rules |
| **Storage** | Firebase Storage | /documents/, /receipts/, signed URLs 5 min |
| **PDF** | pdf + printing | Quittance loi 6 juillet 1989 |
| **Build** | build_runner + freezed + json_serializable | Code generation, no reflection |
| **Hosting** | Firebase Hosting | Staging + prod channels, CSP (fonts.gstatic.com) |
| **CI/CD** | GitHub Actions | ci.yml (format + analyze) + deploy.yml (manual channel) |

## Changements récents (2026-07-03 — 2026-07-05)

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

## Audit incohérences (2026-07-05)

À la date 2026-07-05 (après merge FEAT-023...FEAT-030, commit bea8693) :

- **✅ Collections Firestore cohérentes** : 10 collections (landlords, properties, tenants, leases, payments, receipts, documents, investment_scenarios, paid_plan_interest, **support_requests**)
- **✅ Règles de sécurité complètes** : 3 couches (rules + CF + triggers), isFullyAuthed() + isAnonymous(), soft-delete filters systématiques
- **✅ 28 composite indexes** : Couvrent tous les soft-delete + cross-filters, zéro WHERE field==null sans index
- **✅ Cloud Functions** : 13 callable (lease, payment, receipt, document, soft-delete, anonymous-upgrade, charges) + 8 triggers (setUpdatedAt×7, recomputeReceiptStale) + 1 scheduled (cleanupExpiredAnon)
- **✅ Routes cohérentes** : 40+ GoRouter routes, 3-state guard via sessionStateProvider (unauthenticated / anonymous / fullyAuthenticated)
- **✅ Features mappées** : FEAT-001–030 tous dans FEATURES.md, matrice + statut + commits
- **✅ Dépendances déclarées** : pubspec.yaml (23 packages + package_info_plus), functions/package.json (firebase-admin/functions), firebase.json (CSP fonts.gstatic.com)
- **✅ Routes cohérentes shell** : StatefulShellRoute.indexedStack 5 branches, NavigationBar <600px / NavigationRail ≥600px repliable (railExpandedProvider persisté)
- **✅ Persistence utilisateur** : themeModeProvider (thème) + chartPeriodProvider (période) + railExpandedProvider (nav collapsed) via SharedPreferences
- **✅ Anonyme tier system** : BAILLAN-M1 complet (14j essai, upgrade transactionnel, quit demo dialog)
- **✅ Nouvelle collection support_requests** : FEAT-025, create-only, capture email/subject/message/appVersion/appEnv, status='new', createdAt=request.time

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
- **App native Capacitor** : iOS + Android distribution

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
                         receipts, documents, investment_scenarios, paid_plan_interest
  Cloud Functions: 14 callables + 8 triggers + 1 scheduled (Node.js 20)
  Storage: signed URLs (5 min), documents + receipts buckets
  
Security:
  Firestore rules: isFullyAuthed() + isAnonymous() + isOwner() + preservesImmutables()
  Cloud Functions: Admin SDK (bypass rules, cross-entity validation)
  RLS: soft-delete filters (28 composite indexes)
  
PDF + Legal:
  pdf + printing packages
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
