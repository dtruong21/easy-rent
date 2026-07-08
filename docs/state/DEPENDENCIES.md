# Dépendances — snapshot

> Maintenu par `state-keeper`. **Source** : `pubspec.yaml` + `functions/package.json` + `firebase.json`. **Dernière sync** : 2026-07-08 (FEAT-043 i18n uses gen_l10n native, no new packages ; FEAT-024 mobile no pubspec changes ; FEAT-045 no new deps). **Pivot** : FEAT-019 (2026-07-02) — Firebase Auth + Firestore + Cloud Functions (Node.js 20).

## Flutter (pubspec.yaml)

### SDK

- Dart : `^3.11.0`
- Flutter : latest stable

### Dépendances runtime (23 packages)

| Package | Version | Usage | Ajoutée | Update FEAT |
|---|---|---|---|---|
| `firebase_core` | `^3.6.0` | Init Firebase client (FEAT-019 pivot) | FEAT-019 | — |
| `firebase_auth` | `^5.3.1` | Auth email/password/Google/Apple (FEAT-019 pivot) | FEAT-019 | — |
| `cloud_firestore` | `^5.4.4` | DB read/write (FEAT-019 pivot) | FEAT-019 | — |
| `firebase_storage` | `^12.3.2` | Storage documents (FEAT-019 pivot) | FEAT-019 | — |
| `cloud_functions` | `^5.1.3` | Callable Cloud Functions (FEAT-019 pivot) | FEAT-019 | — |
| `flutter_riverpod` | `^2.6.0` | State management, providers | FEAT-001 | — |
| `go_router` | `^14.6.0` | Navigation + deep linking + redirect guards | FEAT-001 | — |
| `freezed_annotation` | `^2.4.4` | Modèles immutables (code generation) | FEAT-002 | — |
| `json_annotation` | `^4.9.0` | JSON serialization (code generation) | FEAT-002 | — |
| `pdf` | `^3.11.0` | Génération PDF quittances (PDF building) | FEAT-007 | — |
| `printing` | `^5.13.0` | Affichage/print/download PDF | FEAT-007 | — |
| `intl` | `^0.19.0` | Locale FR (dates, devise, formats) | FEAT-003 | — |
| `logging` | `^1.3.0` | Logs structurés client-side | FEAT-001 | — |
| `uuid` | `^4.5.0` | Génération UUIDs client | FEAT-002 | — |
| `collection` | `^1.18.0` | Helpers de collection (List, Map) | FEAT-002 | — |
| `cupertino_icons` | `^1.0.8` | Icons (compat iOS Material) | bootstrap | — |
| `url_launcher` | `^6.3.2` | Ouvre links externes (privacy policy, mailto) | FEAT-010 | — |
| `file_picker` | `^11.0.2` | Sélection fichiers multi-platform (Web bytes) | FEAT-009 | — |
| `mime` | `^2.0.0` | Détection MIME côté client (defense in depth) | FEAT-009 | — |
| `fl_chart` | `^0.69.0` | Barchart 6 mois encaissé/dû | FEAT-010 | — |
| `shared_preferences` | `^2.3.5` | Persist PWA install prompt + thème + période + rail | FEAT-010 | FEAT-023/027/026 |
| `flutter_svg` | `^2.0.10+1` | Rendu SVG (logo Google auth buttons) | FEAT-019 | — |
| `web` | `^1.1.0` | JS interop (install prompt, Web Share API) | FEAT-010, FEAT-008 | — |
| **`package_info_plus`** | **^9.0.1** | **Version app (version.json web, manifest natif)** | **FEAT-023** | — |

**Removed (Supabase pivot → Firebase)** :
- `supabase_flutter` (2.12.4) — remplacée firebase_*
- `supabase` (Deno) — remplacée Cloud Functions

### Dépendances dev (8 packages)

| Package | Version | Usage |
|---|---|---|
| `flutter_test` | sdk | Unit + widget tests |
| `integration_test` | sdk | E2E tests |
| `flutter_lints` | `^6.0.0` | Linting (analysis_options.yaml) |
| `build_runner` | `^2.4.13` | Code generation orchestrator |
| `freezed` | `^2.5.7` | Codegen modèles immutables |
| `json_serializable` | `^6.9.0` | Codegen JSON serde |
| `firebase_auth_mocks` | `^0.14.2` | Mock FirebaseAuth (tests) |
| `fake_cloud_firestore` | `^3.1.0` | Mock Firestore (tests) |

### Dépendances P2 backlog (version upgrades)

| Package | Current | Latest | Status | Raison |
|---|---|---|---|---|
| `flutter_riverpod` | 2.6.0 | 3.x | P2 backlog | Breaking changes, codegen refactor |
| `go_router` | 14.6.0 | 17.x | P2 backlog | Breaking changes, API reshaping |
| `freezed` | 2.5.7 | 3.x | P2 backlog | Breaking changes, output format |

**Recommandation** : Attendre sprint dédié (MVP complet → versions mineures ensuite).

### Dépendances P2 backlog (version upgrades)

| Package | Current | Latest | Status | Raison |
|---|---|---|---|---|
| `flutter_riverpod` | 2.6.0 | 3.x | P2 backlog | Breaking changes, codegen refactor |
| `go_router` | 14.6.0 | 17.x | P2 backlog | Breaking changes, API reshaping |
| `freezed` | 2.5.7 | 3.x | P2 backlog | Breaking changes, output format |

### Assets et fonts

**Flutter build** :
- `uses-material-design: true`
- `generate: true` (l10n auto-generation)

**Fonts bundlées** : `assets/fonts/`
- `EB Garamond` (Regular, Medium, Italic, SemiBoldItalic) — sérif éditorial Baillan (FEAT-020)
- License : OFL (assets/fonts/OFL.txt)
- Subset : latin (~63 Ko par style)

---

### Version app (pubspec.yaml)

```
version: 1.0.0+1
```

- **Sémantique** : 1.0.0 (MVP complet, juillet 2026)
- **BUILD number** : injecté CI (GitHub run_number), local (git rev-list --count HEAD)
- **Affichage** : ProfilePage « À propos » via package_info_plus → « Baillan v1.0.0 (build 123) »

---

## Cloud Functions (Node.js 20 — Firebase)

### package.json

| Clé | Valeur |
|---|---|
| **Node** | 20 (engine) |
| **Main** | lib/index.js (compiled output) |
| **Région** | europe-west1 (firebase.json) |
| **Max instances** | 10 (global, override per-function) |

### Dépendances runtime (2)

| Package | Version | Usage |
|---|---|---|
| `firebase-admin` | `^12.7.0` | Admin SDK (bypasse rules, mutation cross-entity) |
| `firebase-functions` | `^6.0.1` | Function runtime + decorators |

### Dépendances dev (7)

| Package | Version | Usage |
|---|---|---|
| `@types/node` | `^20.14.0` | Type hints Node.js |
| `@typescript-eslint/eslint-plugin` | `^7.18.0` | Linting TypeScript |
| `@typescript-eslint/parser` | `^7.18.0` | Parser TypeScript |
| `eslint` | `^8.57.0` | Code linting |
| `eslint-plugin-import` | `^2.29.1` | Import linting |
| `firebase-functions-test` | `^3.4.1` | Test utilities |
| `typescript` | `^5.5.4` | Compiler |
| `vitest` | `^2.1.1` | Test runner (replace jest) |

### Scripts

```bash
npm run build          # tsc -p tsconfig.build.json → lib/ (FEAT-030: handleNewUser removed)
npm run build:watch   # Watch mode
npm run serve         # Emulators (functions, firestore, auth)
npm run lint          # ESLint check
npm run test          # Vitest (unit tests)
npm run test:watch    # Watch mode
npm run deploy        # Deploy functions only
npm run logs          # Stream logs
```

### Build (tsconfig.build.json)

**FEAT-030 change** : ADR 0001 (GCIP non activé) — `handleNewUser` blocking trigger **supprimé** (2026-07-05, commit 90eb86f).
- Ancien : export 14 callable + handleNewUser beforeUserCreated trigger → deploy échouait si beforeUserCreated inactive
- Nouveau : export 13 callable + 8 triggers + 1 scheduled → deploy exit 0
- Provisioning landlord **100 % client** (auth_repository.dart)

---

## Firestore Configuration

### firestore.indexes.json

**28 composite indexes** pour soft-delete + cross-filters :

| Collection | Fields | Filtre-clé | Note |
|---|---|---|---|
| `landlords` | isAnonymous, anonExpiresAt ASC | — | Cleanup anonyme expiré |
| `properties` | landlordId, deletedAt, name | Listing par landlord |
| `properties` | landlordId, deletedAt, createdAt DESC | Tri création |
| `tenants` | landlordId, deletedAt, lastName | Listing par landlord |
| `tenants` | landlordId, deletedAt, createdAt DESC | Tri création |
| `leases` | landlordId, deletedAt, status, startDate DESC | Status filter (ongoing, upcoming, ended) |
| `leases` | landlordId, propertyId, deletedAt | FK property |
| `leases` | landlordId, tenantId, deletedAt | FK tenant |
| `leases` | landlordId, status, endDate ASC | Status + end date |
| `leases` | landlordId, deletedAt, startDate DESC | Listing |
| `payments` | landlordId, deletedAt, paidAt DESC | Timeline paiements |
| `payments` | landlordId, leaseId, deletedAt, paidAt DESC | Paiements par bail |
| `payments` | landlordId, leaseId, deletedAt, periodStart DESC | Paiements historique bail |
| `payments` | landlordId, deletedAt, periodStart DESC | Timeline global |
| `receipts` | landlordId, leaseId, periodStart DESC | Quittances par bail |
| `receipts` | landlordId, periodStart DESC | Timeline quittances |
| `receipts` | landlordId, isVoided, periodStart DESC | Voided filter |
| `receipts` | landlordId, isStale, periodStart DESC | Stale recalc |
| `documents` | landlordId, leaseId, deletedAt, uploadedAt DESC | Documents par bail |
| `documents` | landlordId, deletedAt, category | Category filter |
| `investment_scenarios` | landlordId, deletedAt, updatedAt DESC | Scenario listing |

**Piège** : Firestore refuse WHERE field==null sans index composite. Solution : indexer systématiquement sur deletedAt (commits 61a5956, 85f1be2).

### firestore.rules

- **isActive()** helper : rsc.data.deletedAt == null (soft-delete filter)
- **isOwner(uid)** : auth.uid == uid
- **isFullyAuthed()** : signé && !anonyme
- **isAnonymous()** : firebase.sign_in_provider == 'anonymous'
- **preservesImmutables()** : landlordId, createdAt, deletedAt immuables côté client

---

## Firebase Configuration (firebase.json)

| Clé | Valeur | Notes |
|---|---|---|
| `hosting.public` | public | Build output (Flutter Web) |
| `hosting.cleanUrls` | true | Rewrite /file → /file.html |
| `hosting.rewrites` | [{source: "**", destination: "/index.html"}] | PWA deep linking |
| `hosting.headers` | CSP + cache | fonts.gstatic.com, max-age |
| `functions.source` | functions | Directory root |
| `functions.runtime` | nodejs20 | Node version |
| `functions.region` | europe-west1 | Default region |

**CSP Header** (feedback_csp_fonts_gstatic.md) :
```
Content-Security-Policy: default-src 'self'; script-src 'unsafe-inline' 'unsafe-eval'; font-src 'self' https://fonts.gstatic.com; ...
```
(CanvasKit Flutter Web exige fonts.gstatic.com + unsafe-inline script)

---

## CLI Tools (local development)

| Outil | Version | Usage |
|---|---|---|
| `firebase-cli` | latest | Deploy, emulators, functions logs |
| `flutter` | 3.x | Build, run, analyze |
| `dart` | 3.11+ | Formatting, analysis |

### Dart format (CI requirement)

- Pre-commit hook : `dart format lib/` (tous les fichiers doivent être formatés)
- CI fail si non-formaté (feedback_dart_format_ci.md)

---

## Environment Variables

### Client (.env, Firebase config)

```
FIREBASE_API_KEY=...
FIREBASE_AUTH_DOMAIN=...
FIREBASE_PROJECT_ID=...
FIREBASE_STORAGE_BUCKET=...
FIREBASE_MESSAGING_SENDER_ID=...
FIREBASE_APP_ID=...
FIREBASE_MEASUREMENT_ID=... (optional, analytics)
APP_ENV=dev|staging|prod
```

### Functions (runtime)

- GOOGLE_APPLICATION_CREDENTIALS (automated)
- NODE_ENV (automated)

---

## Staging vs Prod Deployment

| Aspect | Staging | Prod |
|---|---|---|
| **Firebase project** | easyrent-staging | easyrent-prod |
| **Hosting channel** | staging | main (default) |
| **Functions region** | europe-west1 | europe-west1 |
| **Firestore database** | (dev) | (prod) |
| **Storage bucket** | staging | prod |
| **Deploy command** | `firebase hosting:channel:deploy staging` | `firebase deploy` |
| **APP_ENV** | staging | prod |

**CI automation** : `deploy.yml` (GitHub Actions) — select channel via input.

---

## Known Dependencies Issues

| Issue | Status | Workaround |
|---|---|---|
| **Riverpod 3.x breaking** | P2 backlog | Stay 2.6.0 for MVP |
| **GoRouter 17.x breaking** | P2 backlog | Stay 14.6.0 for MVP |
| **Flutter Web CanvasKit CSP** | ✅ Fixed | fonts.gstatic.com CSP whitelist (firebase.json) |
| **Firebase deploy retry race** | ⚠️ Known | FAILED_PRECONDITION « current active version » = idempotent no-op (content already live) |
