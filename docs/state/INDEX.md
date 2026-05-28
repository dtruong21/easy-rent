# Project State Index

> **Snapshot vivant du projet EasyRent.** Maintenu par l'agent `state-keeper`. Source de vérité pour les agents — à lire AVANT de grep/scanner le codebase.

## Métadonnées

- **Dernière mise à jour** : 2026-05-28T00:00:00Z
- **Commit ref** : `5a4bcac` (fix: disable service worker on staging builds)
- **Branche** : `develop`
- **Phase projet** : FEAT-001 (auth magic link) implémentée et mergée — staging validée bout-en-bout. FEAT-002–010 en backlog.

## Pointeurs

| Aspect du projet | Fichier |
|---|---|
| Schéma Postgres (tables, colonnes, RLS, fonctions) | [`SCHEMA.md`](SCHEMA.md) |
| Routes Flutter et widgets principaux | [`ROUTES.md`](ROUTES.md) |
| Features implémentées et statut | [`FEATURES.md`](FEATURES.md) |
| Dépendances (pubspec, Deno imports, CLI tools) | [`DEPENDENCIES.md`](DEPENDENCIES.md) |
| Edge Functions déployées et planifiées | [`FUNCTIONS.md`](FUNCTIONS.md) |

## Comment l'utiliser

**Tu es un agent IA travaillant sur EasyRent ?**

1. Lis ce fichier en premier. Repère la date de mise à jour.
2. Si la date est < 7 jours → fais confiance aux fichiers d'état listés ci-dessus.
3. Si la date est ≥ 7 jours OU manquante → flag-le à l'utilisateur et propose `/refresh-state` AVANT de continuer.
4. Ne grep/scan le codebase QUE si l'état ne couvre pas ton besoin.

**Économie attendue** : un agent qui consulte `SCHEMA.md` (200 tokens) au lieu de grep toutes les migrations (5000 tokens) divise sa consommation par 25.

## Quand mettre à jour cet état

- Après chaque feature mergée → `state-keeper` met à jour automatiquement
- Avant un sprint de features → `/refresh-state` pour reset propre
- Si un agent détecte une incohérence → flag immédiat à l'utilisateur

## Stack résumé

| Couche | Tech |
|---|---|
| Frontend | Flutter Web 3.x + Dart 3.11+ |
| State | Riverpod 2.6.0 |
| Navigation | GoRouter 14.6.0 + GoRouterRefreshStream (custom) |
| Auth | Supabase Auth (magic link via PKCE) |
| Backend | Supabase (Postgres + Auth + Storage) |
| PDF | pdf + printing packages |
| Build | build_runner + freezed + json_serializable |
| Hosting | Firebase Hosting (staging ✅, prod TBD) |
| CI/CD | GitHub Actions (ci.yml + deploy.yml avec build_runner step) |

## Incohérences détectées

Aucune incohérence majeure — état cohérent avec code.

### Observations

1. **FEAT-001 status upgrade** : À mettre à jour dans `FEATURES.md` (était "📋 planned", maintenant "✅ done" + staging déployée)
2. **Routes** : `/privacy` ajoutée (public, RGPD) — à documenter dans `ROUTES.md`
3. **Nouvelle structure auth** : `lib/features/auth/` complète (domain/data/application/presentation) — document dans `FEATURES.md`
4. **CI/CD update** : `deploy.yml` a maintenant `dart run build_runner build` step + `--pwa-strategy=none` sur staging
5. **Firebase config** : `.firebaserc` et `firebase.json` ajoutés (projet `easy-rent-54cd4`)

### Pas d'incohérences de code

- Code matches state — aucun drift détecté
- Tests présents (unit + widget + RLS)
- RLS validée cross-user en staging
