# Dépendances — snapshot

> Maintenu par `state-keeper`. **Source** : `pubspec.yaml` + `supabase/functions/` + `firebase.json`. **Dernière sync** : 2026-06-22 (FEAT-011 — pivot auth password classique, aucune nouvelle dépendance ; supabase_flutter 2.12.4 utilisé pour session PKCE recovery)

## Flutter (pubspec.yaml)

### SDK
- Dart : `^3.11.0`
- Flutter : latest stable

### Dépendances runtime

| Package | Version | Usage |
|---|---|---|
| `supabase_flutter` | `^2.12.4` | Auth, DB, Storage, Edge Functions |
| `flutter_riverpod` | `^2.6.0` | State management |
| `go_router` | `^14.6.0` | Navigation et deep linking |
| `freezed_annotation` | `^2.4.4` | Modèles immutables (code generation) |
| `json_annotation` | `^4.9.0` | Sérialisation JSON (code generation) |
| `pdf` | `^3.11.0` | Génération PDF quittances (FEAT-007) |
| `printing` | `^5.13.0` | Affichage/téléchargement PDF (FEAT-007) |
| `intl` | `^0.19.0` | Locale FR (dates, devise) |
| `logging` | `^1.3.0` | Logs structurés |
| `uuid` | `^4.5.0` | Génération d'identifiants |
| `collection` | `^1.18.0` | Helpers de collection |
| `cupertino_icons` | `^1.0.8` | Icons (compat iOS) |
| `url_launcher` | `^6.3.2` | Ouvre links externes (profil, privacy) |
| `file_picker` | `^11.0.2` | Sélection multi-fichiers (Web + mobile, bytes en mémoire — FEAT-009) |
| `mime` | `^2.0.0` | Détection MIME client-side depuis extension (defense in depth — FEAT-009) |
| `fl_chart` | `^0.69.0` | Barchart 6 mois encaissé/dû (FEAT-010 Dashboard) |
| `shared_preferences` | `^2.3.5` | Persist dismiss install prompt PWA (FEAT-010 PWA) |
| `web` | `^1.1.0` | JS interop beforeinstallprompt + matchMedia (FEAT-010 PWA, remplace dart:html legacy) |

### Dépendances dev

| Package | Version | Usage |
|---|---|---|
| `flutter_test` | sdk | Unit tests Flutter |
| `integration_test` | sdk | Tests E2E |
| `flutter_lints` | `^6.0.0` | Linting (analysis_options.yaml) |
| `build_runner` | `^2.4.13` | Code generation tool |
| `freezed` | `^2.5.7` | Codegen modèles immutables |
| `json_serializable` | `^6.9.0` | Codegen JSON serialization |

### Optional dev (commenté)

- `riverpod_generator` : Codegen Riverpod (optionnel — non activé pour l'instant)
- `custom_lint` : Support custom lints
- `riverpod_lint` : Custom lints for Riverpod

### Custom implementations

- `GoRouterRefreshStream` : Custom class wrapper pour écouter `authRepository.authStateChanges` et déclencher GoRouter redirect logic (dans `lib/core/router/go_router_refresh_stream.dart`)

## Edge Functions (Deno)

**3 fonctions déployées/planifiées** :

### 1. `generate-receipt` (FEAT-007 Phase 2, ✅ active)

- **Structure** : Deno TS dans `supabase/functions/generate-receipt/`
- **Fichiers** : index.ts, pdf_layout.ts, types.ts, deps.ts, deno.json, tests/
- **Invocation** : POST `/functions/v1/generate-receipt` (JWT required)
- **Body** : `{lease_id: uuid, schema: 'public' | 'dev'}`
- **Retour** : `{receipt_id: uuid, pdf_url: string (5 min signed)}`
- **Dépendances** :
  - `pdf-lib@1.17.1` (PDF building, loi 1989 art. 21)
  - `@supabase/supabase-js@2.45.0` (client SDK)
- **Secrets** : aucun
- **Priorité** : P0

### 2. `send-receipt` (FEAT-008, ✅ implémentée — déploiement attente secrets)

- **Structure** : Deno TS dans `supabase/functions/send-receipt/`
- **Fichiers** : index.ts, email_template.ts, resend_client.ts, types.ts, deps.ts, deno.json, tests/
- **Invocation** : POST `/functions/v1/send-receipt` (JWT required)
- **Body** : `{receipt_id: uuid, schema: 'public' | 'dev'}`
- **Retour** : `{success: true, sent_at: ISO, sent_to_email: string, resend_id: string}`
- **Dépendances** :
  - `@supabase/supabase-js@2.45.0`
  - Fetch natif Deno (pas de SDK Resend — direct HTTP)
- **Secrets** :
  - `RESEND_API_KEY` (attente production, domaine non vérifié)
  - `RESEND_FROM_EMAIL` (attente production)
  - `ALLOWED_ORIGINS` (optionnel)
- **Priorité** : P0
- **Blockers** : Resend domaine verification

### 3. `_shared` (Utilitaire, ✅ en place)

- **Structure** : Deno TS partagée
- **Fichiers** : cors.ts, db_helpers.ts, types.ts
- **Usage** : CORS utilities, database helpers réutilisées par autres functions

## Deno (supabase/functions/)

### deno.json (par fonction)

Chaque fonction a son `deno.json` déclarant dépendances ES modules :

```json
{
  "imports": {
    "pdf-lib": "https://cdn.jsdelivr.net/npm/pdf-lib@1.17.1/+esm",
    "@supabase/supabase-js": "https://esm.sh/@supabase/supabase-js@2.45.0"
  }
}
```

**Versions fixées** : pdf-lib 1.17.1, supabase-js 2.45.0 (pas de wildcard)

## Firebase Hosting

### firebase.json (configuration deployment)

**CSP (Content Security Policy)** : dernière mise à jour 2026-06-22 (FEAT-010 Section C, fix fonts.gstatic.com)

```json
"headers": [
  {
    "key": "Content-Security-Policy",
    "value": "default-src 'self'; font-src 'self' https://fonts.gstatic.com; connect-src 'self' *.supabase.co https://fonts.gstatic.com; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; img-src 'self' data: https:; base-uri 'self'; form-action 'self';"
  }
]
```

**Rewriting** :
- `/index.html` fallback pour SPA routing (GoRouter)
- Assets caching avec max-age

**Service Worker caching** (FEAT-010 Section C) :
- Offline-first strategy
- Cache busting via hash

### deploy.yml (CI/CD — FEAT-010 Section C)

**Staging** : `firebase hosting:channel:deploy staging`
**Prod** : `firebase hosting:channel:deploy prod` (workflow_dispatch avec input confirm)

**Steps** :
1. `flutter pub get`
2. `dart run build_runner build` (freezed + json_serializable)
3. `flutter build web --release`
4. Firebase deploy (staging vs prod based on workflow input)

### migrate-prod.yml (nouveau — FEAT-010 Section C)

**Trigger** : workflow_dispatch + input `confirm=yes/no`
**Steps** :
1. Checkout code
2. Setup Supabase CLI
3. `supabase db push` (PROD database push)
4. Logging versioned + rollback-ready

## Schémas Supabase

**Schémas gérés** : `public` (prod) + `dev` (dev environment)

**Migrations** :
- `supabase/migrations/` : SQL files chronologiquement nommés
- 9 migrations à date (FEAT-001 à FEAT-009) :
  1. 00000000000000_init_dev_schema.sql
  2. 20260527081533_feat001_landlords_auth.sql
  3. 20260528120000_feat002_data_model.sql
  4. 20260529120000_lease_date_bounds.sql
  5. 20260531102202_feat006_payments.sql
  6. 20260531172904_feat007_receipts.sql
  7. 20260531200000_feat007_receipts_stale_bidirectional.sql
  8. 20260601103751_feat008_email_quittance.sql
  9. 20260602100520_feat009_documents.sql

**Stratégie** : multi-env via Supabase projects (public pour prod, dev pour staging)

## Secrets management

**Fichiers secrets** (`.gitignored`) :
- `supabase/.env` (Supabase local dev)
- `firebase-credentials.json` (Firebase local)
- `pubspec.lock` (generated, committed)

**Fichiers examples** (commités) :
- `dart-defines.example.json` → `dart-defines.prod.example.json` (FEAT-010)
- CI/CD : secrets via GitHub Actions secrets (RESEND_API_KEY, etc.)

## PWA Web Assets

**Icons** (FEAT-010 Section B) :
- `web/icons/Icon-192.png` (192x192, EasyRent logo teal)
- `web/icons/Icon-512.png` (512x512, EasyRent logo teal)
- `web/icons/Icon-maskable-192.png` (maskable variant)
- `web/icons/Icon-maskable-512.png` (maskable variant)

**Manifest** :
- `web/manifest.json` : PWA metadata (name, description, theme_color #0F766E, categories productivity/business/finance)

**HTML** :
- `web/index.html` : manifest ref, background-color CSS pour cohérence loading

## Build & Code generation

**Step CI/CD** : `dart run build_runner build`
- Génère : freezed models, json_serializable serde
- Output : `*.freezed.dart`, `*.g.dart`
- Fail-fast : si fichier non formaté → CI fail

**Linting** : `flutter analyze`
- Rules : `analysis_options.yaml`

**Testing** :
- Unit : `flutter test`
- Widget : `flutter test`
- E2E : `flutter test integration_test/`

## Notes de maintenance

- **Flutter Web CanvasKit** : Nécessite fonts.gstatic.com dans CSP (sinon glyphs invisibles) — fix appliqué firebase.json FEAT-010
- **build_runner** : Prendre soin de formater avant commit (CI fail sinon)
- **Riverpod** : CodeGen optionnel — à activer si needed (commenté dans pubspec.yaml)
- **Resend** : Attente domaine verification pour prod deploy FEAT-008
- **PWA install prompt** : Nécessite web package (dart:html deprecié), SharedPreferences pour persistance dismiss
