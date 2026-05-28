# Dépendances — snapshot

> Maintenu par `state-keeper`. **Source** : `pubspec.yaml`. **Dernière sync** : 2026-05-28 (FEAT-003, aucun changement)

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

_(aucune fonction créée — `supabase/functions/` n'existe pas)_

À créer lors de FEAT-007 (envoi quittance email).

Structure prévue :
- Deno runtime (TS)
- `import_map.json` pour dépendances externes (Resend, Supabase client, etc.)

## Outils CLI requis localement

| Outil | Version | Usage | Status |
|---|---|---|---|
| `flutter` | stable | `flutter pub`, `flutter run` | ✅ requis |
| `dart` | ✅ inclus | `dart analyze`, `dart format` | ✅ requis |
| `git` | any | VCS | ✅ requis |
| `supabase` CLI | latest | Migrations locales, emulator | ⚠️ optionnel (fallback: web UI) |
| `firebase` CLI | latest | Firebase Hosting deploy | ✅ requis (staging + prod) |
| `gh` | latest | GitHub API, PR automation | ✅ requis (agent ticketing) |

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
