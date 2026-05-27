# Dépendances — snapshot

> Maintenu par `state-keeper`. **Source** : `pubspec.yaml`. **Dernière sync** : 2026-05-27

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

## Edge Functions (Deno)

_(aucune fonction créée — `supabase/functions/` n'existe pas encore)_

À créer lors de FEAT-007 (envoi quittance email).

## Outils CLI requis localement

- `flutter` : stable ✅ (pour `flutter pub`, `flutter run`)
- `dart` : ✅ inclus dans Flutter (pour `dart analyze`, `dart format`)
- `git` : ✅ (`git push`, `git rebase`)
- `supabase` CLI : ❓ à vérifier (pour migrations locales)
- `firebase` CLI : ❓ à vérifier (pour Firebase Hosting deploy)
- `gh` : ❓ à vérifier (pour GitHub API / PR automation)

## Architecture notes

- **State management** : Riverpod (hooks-based, not provider-based) + code generation ready
- **Navigation** : GoRouter with Riverpod integration
- **Freezed** : Used for immutable models (TBD per feature)
- **JSON serialization** : json_serializable (TBD per model)
- **PDF** : pdf + printing packages for receipt generation
- **Locale** : intl for FR formatting
