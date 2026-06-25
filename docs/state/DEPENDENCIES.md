# Dépendances — snapshot

> Maintenu par `state-keeper`. **Source** : `pubspec.yaml` + `supabase/functions/` + `firebase.json`. **Dernière sync** : 2026-06-25 (FEAT-008 Web Share pivot, FEAT-014/015/016 ✅)

## Flutter (pubspec.yaml)

### SDK

- Dart : `^3.11.0`
- Flutter : latest stable

### Dépendances runtime (19 packages)

| Package | Version | Usage | Added |
|---|---|---|---|
| `supabase_flutter` | `^2.12.4` | Auth, DB, Storage, Edge Functions | FEAT-001 |
| `flutter_riverpod` | `^2.6.0` | State management, providers | FEAT-001 |
| `go_router` | `^14.6.0` | Navigation + deep linking + redirect guards | FEAT-001 |
| `freezed_annotation` | `^2.4.4` | Modèles immutables (code generation) | FEAT-002 |
| `json_annotation` | `^4.9.0` | JSON serialization (code generation) | FEAT-002 |
| `pdf` | `^3.11.0` | Génération PDF quittances (PDF building) | FEAT-007 |
| `printing` | `^5.13.0` | Affichage/print/download PDF | FEAT-007 |
| `intl` | `^0.19.0` | Locale FR (dates, devise, formats) | FEAT-003 |
| `logging` | `^1.3.0` | Logs structurés client-side | FEAT-001 |
| `uuid` | `^4.5.0` | Génération UUIDs client | FEAT-002 |
| `collection` | `^1.18.0` | Helpers de collection (List, Map) | FEAT-002 |
| `cupertino_icons` | `^1.0.8` | Icons (compat iOS Material) | bootstrap |
| `url_launcher` | `^6.3.2` | Ouvre links externes (privacy policy, mailto) | FEAT-010 |
| `file_picker` | `^11.0.2` | Sélection fichiers multi-platform (Web bytes) | FEAT-009 |
| `mime` | `^2.0.0` | Détection MIME côté client (defense in depth) | FEAT-009 |
| `fl_chart` | `^0.69.0` | Barchart 6 mois encaissé/dû | FEAT-010 |
| `shared_preferences` | `^2.3.5` | Persist PWA install prompt dismiss (1 week TTL) | FEAT-010 |
| `web` | `^1.1.0` | JS interop (beforeinstallprompt, navigator.share, matchMedia) | FEAT-010, FEAT-008 |

### Dépendances dev (7 packages)

| Package | Version | Usage |
|---|---|---|
| `flutter_test` | sdk | Unit + widget tests |
| `integration_test` | sdk | E2E tests |
| `flutter_lints` | `^6.0.0` | Linting (analysis_options.yaml) |
| `build_runner` | `^2.4.13` | Code generation orchestrator |
| `freezed` | `^2.5.7` | Codegen modèles immutables |
| `json_serializable` | `^6.9.0` | Codegen JSON serde |

### Optional dev (commenté)

- `riverpod_generator` : Codegen Riverpod (optionnel, non activé)
- `custom_lint` : Support custom lints
- `riverpod_lint` : Custom lints for Riverpod

### Dépendances P2 backlog (version upgrades)

| Package | Current | Latest | Status | Reason |
|---|---|---|---|---|
| `flutter_riverpod` | 2.6.0 | 3.x | P2 backlog | Breaking changes, codegen refactor |
| `go_router` | 14.6.0 | 17.x | P2 backlog | Breaking changes, API reshaping |
| `freezed` | 2.5.7 | 3.x | P2 backlog | Breaking changes, output format |

**Recommandation** : Attendre sprint dédié (MVP complet → versions mineures ensuite)

---

## Edge Functions (Deno / TypeScript)

### Fonctions déployées (2)

#### 1. `generate-receipt` (FEAT-007 Phase 2 — ✅ active)

| Propriété | Valeur |
|---|---|
| Dossier | `supabase/functions/generate-receipt/` |
| Dépendances | pdf-lib@1.17.1, @supabase/supabase-js@2.45.0 |
| Invocation | POST `/functions/v1/generate-receipt` (JWT required) |
| Body | `{lease_id: uuid, schema: 'public' \| 'dev'}` |
| Retour | `{receipt_id: uuid, pdf_url: string (5 min signed)}` |
| Secrets | _(none)_ |
| Priorité | P0 (critical prod) |

#### 2. `_shared` (Support utilities)

| Propriété | Valeur |
|---|---|
| Dossier | `supabase/functions/_shared/` |
| Dépendances | Utility types + constants (PDF layouts, legal notices) |
| Usage | Imported by generate-receipt |
| Secrets | _(none)_ |

### Fonctions supprimées

#### `send-receipt` (FEAT-008 Phase 1 — SUPPRIMÉE 2026-06-22)

**Raison** : Pivot Web Share API native (zéro dépendance backend email, zéro secret Resend)

**Remplacement** : `web_share_service.dart` (JS interop `navigator.share()`) + RPC `mark_receipt_as_sent()`

---

## Deno import maps

**Chaque fonction** (`generate-receipt/deno.json`) déclare imports ES modules :

```json
{
  "imports": {
    "pdf-lib": "https://cdn.jsdelivr.net/npm/pdf-lib@1.17.1/+esm",
    "@supabase/supabase-js": "https://esm.sh/@supabase/supabase-js@2.45.0"
  }
}
```

**Versions fixées** : pdf-lib 1.17.1, supabase-js 2.45.0 (reproduisibilité)

---

## Firebase Hosting

### firebase.json (config deployment + CSP)

**CSP (Content Security Policy)** — dernière mise à jour 2026-06-22 (fonts.gstatic.com fix) :

```json
"headers": [
  {
    "key": "Content-Security-Policy",
    "value": "default-src 'self'; font-src 'self' https://fonts.gstatic.com; connect-src 'self' *.supabase.co https://fonts.gstatic.com; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; img-src 'self' data: https:; base-uri 'self'; form-action 'self';"
  }
]
```

**Rewriting** :
- `/index.html` fallback pour SPA routing (GoRouter Deep linking)
- Assets caching avec max-age heuristics

**Service Worker** (FEAT-010 PWA) :
- Offline-first caching strategy
- Cache busting via hash versioning

### CI/CD workflows

#### `.github/workflows/deploy.yml` (FEAT-010 Section C — enhanced)

**Targets** : staging vs prod branch + input selection

```yaml
firebase hosting:channel:deploy ${{ env.CHANNEL }}
```

**Steps** :
1. `flutter pub get`
2. `dart run build_runner build` (freezed + json_serializable)
3. `flutter build web --release --dart-define-from-file=dart-defines.prod.json`
4. Firebase deploy (channel: staging or prod)

#### `.github/workflows/migrate-prod.yml` (FEAT-010 Section C — new)

**Trigger** : `workflow_dispatch` + input `confirm=yes/no`

**Steps** :
1. Checkout code + setup Supabase CLI
2. `supabase db push --linked` (prod database migration)
3. Logging versioned + rollback plan documented

**Manual approval** : confirm=yes requise avant push prod

#### `.github/workflows/ci.yml` (existing)

**CI gates** :
- `flutter analyze` (linting clean)
- `flutter test` (all tests passing)
- `dart run build_runner build` (code generation success)
- `dart format --set-exit-if-changed` (formatting enforced)

---

## Supabase Migrations

### Migration files (16 total)

Chronologiquement dans `supabase/migrations/` :

| # | Filename | Feature | Colonne(s) ajoutées |
|---|---|---|---|
| 0 | `00000000000000_init_dev_schema.sql` | init | créé schéma dev |
| 1 | `20260527081533_feat001_landlords_auth.sql` | FEAT-001 | landlords table |
| 2 | `20260528120000_feat002_data_model.sql` | FEAT-002 | properties, tenants, leases + FK + RLS (37k lignes) |
| 3 | `20260529120000_lease_date_bounds.sql` | FEAT-005 | date hardening (bornes 1900-01-01 à 2100-12-31) |
| 4 | `20260531102202_feat006_payments.sql` | FEAT-006 | payments table (890 lignes) |
| 5 | `20260531172904_feat007_receipts.sql` | FEAT-007 | receipts table + document_type enum + RPC void_receipt |
| 6 | `20260531200000_feat007_receipts_stale_bidirectional.sql` | FEAT-007 | trigger is_stale CASCADE when payment archived |
| 7 | `20260601103751_feat008_email_quittance.sql` | FEAT-008 | receipts.sent_at, sent_to_email + RPC mark_receipt_as_sent |
| 8 | `20260602100520_feat009_documents.sql` | FEAT-009 | documents table + document_category enum |
| 9 | `20260622130000_feat011_handle_new_user_fullname.sql` | FEAT-011 | trigger handle_new_user() refactor (full_name from metadata) |
| 10 | `20260622200000_fix_landlord_id_default_auth_uid.sql` | FEAT-011 fix | DEFAULT auth.uid() sur FK landlord_id (all tables) |
| 11 | `20260622220000_feat014_phase1_property_enrichment.sql` | FEAT-014 P1 | properties +12 colonnes (rooms, dpe, ges, etc.) |
| 12 | `20260622230000_feat014_phase2_tenant_enrichment.sql` | FEAT-014 P2 | tenants +10 colonnes (birth, garant, revenus, etc.) |
| 13 | `20260623000000_feat014_phase3_lease_enrichment.sql` | FEAT-014 P3 | leases +9 colonnes (deposit, irl, payment_method, etc.) |
| 14 | `20260623010000_feat014_phase4_payment_reference.sql` | FEAT-014 P4 | payments.reference (1 colonne) |
| 15 | `20260623020000_feat016_rgpd_consent.sql` | FEAT-016 | landlords.rgpd_consent_at, rgpd_consent_version + backfill |

**Stratégie** : Toutes les migrations appliquées aux schémas public (PROD) + dev (DEV) simultanément

---

## Secrets & Environment management

### Local development

**Fichiers `.gitignored`** :
- `supabase/.env` — Supabase local dev (API keys, DB URL)
- `.env.local` — Flutter build vars (BASE_URL, etc.)
- `firebase-credentials.json` — Firebase local auth

### CI/CD Secrets (GitHub Actions)

**Set via repo Settings → Secrets** :
- `SUPABASE_ACCESS_TOKEN` (Supabase CLI)
- `FIREBASE_TOKEN` (Firebase CLI)
- Autres : pas de secrets requis MVP (FEAT-008 send-receipt supprimée)

### Example files (commités)

- `dart-defines.example.json` → `dart-defines.prod.example.json` (FEAT-010 template)

---

## PWA Assets

### Icons (FEAT-010 Section B)

**Générées via ImageMagick script** :
- `web/icons/Icon-192.png` (192×192, EasyRent logo indigo — FEAT-013)
- `web/icons/Icon-512.png` (512×512)
- `web/icons/Icon-maskable-192.png` (maskable variant)
- `web/icons/Icon-maskable-512.png` (maskable variant)

### Manifest & HTML

- `web/manifest.json` — PWA metadata (name, description, theme_color #4F46E5 indigo, categories)
- `web/index.html` — manifest ref + background-color CSS

---

## Code generation & Build

### Pre-commit

**Enforced CI gate** : `dart format --set-exit-if-changed`

**Must run before commit** :
```bash
dart run build_runner build  # freezed + json_serializable
dart format lib test
```

### CI/CD step

**In `.github/workflows/ci.yml`** :
```yaml
- run: dart run build_runner build
```

Fail-fast : si fichier non formaté → CI fail (ne pas commiter)

---

## Custom implementations

### `GoRouterRefreshStream`

**File** : `lib/core/router/go_router_refresh_stream.dart`

Custom ChangeNotifier wrapper listening to `authRepository.authStateChanges` Stream, decouples GoRouter refresh logic from Riverpod providers (manual stream subscription management).

### Custom Material 3 theme

**File** : `lib/core/theme/material3_theme.dart`

- Color scheme : indigo primary (FEAT-013 Phase 2, replaces teal)
- Dark mode support : Material 3 defaults
- Typography : FR-friendly font scales

---

## Testing

### Unit + Widget tests

- `flutter test` — all Dart tests in `test/`
- Target : 1093 tests passing (as of 2026-06-25)

### E2E tests

- `flutter test integration_test/` — router integration tests

### RLS tests (Postgres)

- `supabase/tests/` (SQL files, 126 tests total across all tables)

---

## Notes

- **Flutter Web CanvasKit** : Requires fonts.gstatic.com in CSP (text glyphs invisible otherwise) — FIXED firebase.json FEAT-010
- **build_runner** : Format Dart files before commit (CI enforces)
- **Riverpod codegen** : Optional, currently disabled (manual provider definitions sufficient)
- **Multi-env strategy** : Same Supabase project, two schemas (public PROD, dev DEV)
- **Web Share API** : Navigator.share() native support (fallback mailto:// older browsers)
