# Project State Index

> **Snapshot vivant du projet EasyRent.** Maintenu par l'agent `state-keeper`. Source de vérité pour les agents — à lire AVANT de grep/scanner le codebase.

## Métadonnées

- **Dernière mise à jour** : 2026-07-02T14:00:00Z
- **Commit ref** : `8300d07` (Merge branch 'feature/anon-auth-m1' into claude/friendly-gates-07efcd)
- **Branche** : `claude/friendly-gates-07efcd` (worktree, tip feature/anon-auth-m1)
- **Phase projet** : MVP ✅ complet (FEAT-001–018), Pivot Firebase FEAT-019 ✅, Rebrand FEAT-020 ✅, Auth refinement FEAT-021 ✅, Router redesign FEAT-022 ✅

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

## Changements récents (2026-06-30 — 2026-07-02)

### FEAT-022 : Redesign login "La Page du Registre"

**Status** : 🟢 READY (landing public, routes mergées)

- Landing page `/` publique (carrefour onboarding)
- 3-state router (unauthenticated → /login | anonymous → /simulator | fullyAuthenticated → /dashboard)
- Simulator accessible anonymes + comptes (investment_scenarios CRUD)
- Quit demo dialog + action logout
- AppAppBar absent landing (standalone page)

### FEAT-021 : Vérification email post-signup

**Status** : ✅ DONE

- Firebase Auth email verification link (auto post-signup)
- Cloud Function `handleNewUser` provision landlord doc

### FEAT-020 : Rebrand EasyRent → Baillan

**Status** : ✅ DONE (commit e5076c9)

- Logo Baillan, palette indigo, EB Garamond serif (assets/fonts/)
- Package name interne conservé (imports non-cassés)

### FEAT-019 : Migration Supabase → Firebase (3 phases)

**Status** : ✅ DONE (commits 61a5956–85f1be2)

**Phase 1** : Firestore collections (9) + rules + indexes (28 composite)
**Phase 2** : Cloud Functions callables (14) + triggers (8) + scheduled (1)
**Phase 3** : Client integration (Riverpod + CRUD UI, no breaking changes)

**Piège soft-delete** : Firestore refus WHERE field==null sans index → solution systematic indexing (commits 61a5956, 85f1be2).

### FEAT-018 : Simulateur investissement

**Status** : ✅ DONE

- `/simulator` (list/create) + `/simulator/:id` (edit)
- Accessible anonymes + comptes (investment_scenarios CRUD direct)

## Audit incohérences (2026-07-02)

À la date 2026-07-02 (après merge FEAT-019 + BAILLAN-M1, commit 8300d07) :

- **✅ Collections Firestore cohérentes** : 9 collections (landlords, properties, tenants, leases, payments, receipts, documents, investment_scenarios, paid_plan_interest)
- **✅ Règles de sécurité complètes** : 3 couches (rules + CF + triggers), isFullyAuthed() + isAnonymous(), soft-delete filters systématiques
- **✅ 28 composite indexes** : Couvrent tous les soft-delete + cross-filters, zéro WHERE field==null sans index
- **✅ Cloud Functions** : 14 callable (lease, payment, receipt, document, soft-delete, anonymous-upgrade) + 8 triggers (setUpdatedAt×7, recomputeReceiptStale) + 1 scheduled (cleanupExpiredAnon)
- **✅ Routes cohérentes** : 30+ GoRouter routes, 3-state guard via sessionStateProvider (unauthenticated / anonymous / fullyAuthenticated)
- **✅ Features mappées** : FEAT-001–022 tous dans FEATURES.md, matrice + statut + commits
- **✅ Dépendances déclarées** : pubspec.yaml (23 packages), functions/package.json (firebase-admin/functions), firebase.json (CSP fonts.gstatic.com)
- **✅ Aucune route sans feature** : 30 routes couverts par features implémentées
- **✅ Anonyme tier system** : BAILLAN-M1 complet (14j essai, upgrade transactionnel, quit demo dialog)
- **✅ Router refresh fix** : 07f20a3 couvre signe-in chaud regression (ref.listen sessionStateProvider vs GoRouterRefreshStream brut)

## Prochaines étapes (priorité)

### P1 (post-MVP)

- **FEAT-012 Phase 1.5** : LeaseCard polish (denorm loyer+charges dans la card)
- **Staging dédié** : GitHub Actions manual channel deploy (actuellement sur main)
- **Password change + 2FA** : ProfilePage + Firebase Auth password API
- **Rappels paiement** : Cloud Scheduler cron + email notifications

### P2 (nice-to-have)

- **Riverpod 3.x upgrade** : Breaking changes, codegen refactor (attendre sprint dédié)
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
