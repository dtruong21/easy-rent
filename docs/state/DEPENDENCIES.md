# Dépendances — snapshot

> Maintenu par `state-keeper`. **Source** : `pubspec.yaml` + `supabase/functions/` + `firebase.json`. **Dernière sync** : 2026-06-02 (FEAT-009 — nouveau bucket Storage documents)

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
| `pdf` | `^3.11.0` | Génération PDF quittances |
| `printing` | `^5.13.0` | Affichage/téléchargement PDF |
| `intl` | `^0.19.0` | Locale FR (dates, devise) |
| `logging` | `^1.3.0` | Logs structurés |
| `uuid` | `^4.5.0` | Génération d'identifiants |
| `collection` | `^1.18.0` | Helpers de collection |
| `cupertino_icons` | `^1.0.8` | Icons (compat iOS) |
| `file_picker` | `^11.0.2` | Sélection multi-fichiers (Web + mobile), bytes en mémoire (FEAT-009) |
| `mime` | `^2.0.0` | Détection MIME client-side depuis extension (defense in depth, FEAT-009) |
| `fl_chart` | `^0.69.0` | Barchart 6 mois encaissé/dû (FEAT-010 Dashboard) |
| `shared_preferences` | `^2.3.5` | Persist dismiss install prompt PWA (FEAT-010 PWA) |
| `web` | `^1.1.0` | JS interop `beforeinstallprompt` + `matchMedia` (FEAT-010 PWA, remplace dart:html legacy) |

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

- `GoRouterRefreshStream` : Custom class wrapper pour écouter `authRepository.authStateChanges` et déclencher GoRouter redirect logic

## Edge Functions (Deno)

**`generate-receipt`** (créée FEAT-007 Phase 2) :

- **Structure** : Deno TS dans `supabase/functions/generate-receipt/`
  - `index.ts` : Orchestration (fetch payments → build PDF → upload Storage → INSERT DB)
  - `pdf_layout.ts` : Template PDF (pdf-lib 1.17.1, loi 1989 art. 21)
  - `types.ts` : Interfaces TS
  - `deps.ts` : Imports (pdf-lib, @supabase/supabase-js)
  - `deno.json` : imports resolver
  - `tests/generate_receipt_test.ts` : Unit tests
  - `deno.lock` : Lockfile dépendances

- **Dépendances** :
  - `pdf-lib@1.17.1` (esm.sh)
  - `@supabase/supabase-js@2.45.0` (esm.sh)

- **Invocation** : POST `/functions/v1/generate-receipt` avec JWT + body `{lease_id, schema}`

- **Blockers fixes** (FEAT-007 Round 2) :
  - CORS allowlist : Edge Function accessible depuis Flutter Web
  - Timeout : Edge Function respecte limite 540s (PDF build + Storage upload)
  - Privacy : pas d'export sensitive data en logs

**`send-receipt`** (créée FEAT-008) :

- **Structure** : Deno TS dans `supabase/functions/send-receipt/`
  - `index.ts` : Orchestration (charge receipt + tenant → fetch PDF → envoi Resend → RPC mark_receipt_as_sent)
  - `email_template.ts` : Template HTML minimal FR (sujet + corps, loi 1989 art. 21)
  - `resend_client.ts` : Wrapper `fetch` Resend REST API (pas de SDK)
  - `types.ts` : Interfaces TS (SendReceiptRequest, SuccessResponse, ErrorResponse, ReceiptRow)
  - `deps.ts` : Imports (@supabase/supabase-js)
  - `deno.json` : imports resolver
  - `tests/` : 6 fichiers de tests Deno (62 tests)

- **Dépendances** :
  - `@supabase/supabase-js@2.45.0` (esm.sh)
  - `fetch` natif Deno (appel Resend REST API — pas de SDK tiers)

- **Secrets requis** :
  - `RESEND_API_KEY` : clé Bearer Resend (ex: `re_xxx`)
  - `RESEND_FROM_EMAIL` : adresse expéditeur vérifiée (ex: `EasyRent <noreply@easyrent.app>`)

- **Provisionner avant déploiement** :
  ```bash
  supabase secrets set RESEND_API_KEY="re_xxx" RESEND_FROM_EMAIL="EasyRent <noreply@<domaine>>"
  supabase functions deploy send-receipt --project-ref tbgttutodbqffrvsvkoz
  ```

- **Invocation** : POST `/functions/v1/send-receipt` avec JWT + body `{receipt_id, schema}`

## Storage Buckets (Supabase)

| Bucket | Visibilité | MIME whitelist | Taille max | Policies | Path format |
|---|---|---|---|---|---|
| `receipts` | privé | `application/pdf` | 10 MB | SELECT + INSERT (segment[1]=landlord_id) | `{landlord_id}/{receipt_id}.pdf` |
| `documents` | privé | `application/pdf`, `image/jpeg`, `image/png`, `image/webp` | 10 MB | SELECT + INSERT + DELETE (segment[2]=landlord_id) | `{env}/{landlord_id}/{document_id}.{ext}` |

**Note path** : `documents` utilise le préfixe env (segment[1]) contrairement à `receipts` — isolation stricte dev/prod. Conséquence : policy isolation sur segment [2] (et non [1] comme receipts).

## Outils CLI requis localement

| Outil | Version | Usage | Status |
|---|---|---|---|
| `flutter` | stable | `flutter pub`, `flutter run` | ✅ requis |
| `dart` | ✅ inclus | `dart analyze`, `dart format` | ✅ requis |
| `git` | any | VCS | ✅ requis |
| `supabase` CLI | latest | Migrations locales, emulator | ⚠️ optionnel (fallback: web UI) |
| `firebase` CLI | latest | Firebase Hosting deploy | ✅ requis (staging + prod) |
| `gh` | latest | GitHub API, PR automation | ✅ requis (agent ticketing) |

## Hosting & Security (firebase.json)

**Source** : `firebase.json` (commit e322c87)

### Headers & CSP

| Header | Value | Notes |
|---|---|---|
| HSTS | `max-age=31536000; includeSubDomains; preload` | Force HTTPS for 1 year |
| X-Content-Type-Options | `nosniff` | Prevent MIME type sniffing |
| X-Frame-Options | `DENY` | Block embedding in iframes |
| Referrer-Policy | `strict-origin-when-cross-origin` | Privacy-safe referer leakage |
| Permissions-Policy | (all disabled) | No camera, microphone, geolocation, payment APIs |
| **Content-Security-Policy** | See below | Strict, with exceptions for Supabase + Google Fonts |

### CSP Details (post-#16 fix)

```
default-src 'self'
script-src 'self' 'wasm-unsafe-eval' https://www.gstatic.com
style-src 'self' 'unsafe-inline'
img-src 'self' data: blob: https://www.gstatic.com
font-src 'self' data: https://www.gstatic.com https://fonts.gstatic.com
connect-src 'self' https://*.supabase.co wss://*.supabase.co https://www.gstatic.com https://fonts.gstatic.com
manifest-src 'self'
worker-src 'self' blob:
frame-ancestors 'none'
base-uri 'self'
form-action 'self'
object-src 'none'
```

**Key allowances** :
- `script-src 'wasm-unsafe-eval'` : Flutter Web WASM runtime
- `font-src https://fonts.gstatic.com` : Google Fonts (fix #16 — was invisible in dark mode)
- `connect-src https://*.supabase.co` : Supabase Auth + DB + Storage + Functions
- `style-src 'unsafe-inline'` : Material 3 dynamic theming

### Cache headers

- Static assets (js, css, woff2, woff, ttf, otf, wasm) : `max-age=31536000, immutable` (1 year)
- `index.html` : `no-cache, no-store, must-revalidate` (always fetch fresh)

## Build configuration

### pubspec.yaml flags

- `generate: true` : Active Flutter code generation (`lib/generated_plugins.dart`, etc.)

### CI/CD build steps (GitHub Actions)

- `deploy.yml` : `dart run build_runner build` exécutée avant `flutter build web`
- `ci.yml` : `flutter analyze`, `flutter test`, `flutter build web --release`

## Architecture notes

- **State management** : Riverpod (provider-based, NOT hooks-based) + provider watchers
- **Navigation** : GoRouter with Riverpod-based redirect logic (voir `GoRouterRefreshStream`)
- **Freezed** : Used for immutable models (domain models, form state)
- **JSON serialization** : json_serializable (not used in FEAT-001, planned for FEAT-002+)
- **PDF** : pdf + printing packages for receipt generation (FEAT-006+)
- **Locale** : intl for FR formatting (dates, devise, etc.)
