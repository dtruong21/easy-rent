# Project State Index

> **Snapshot vivant du projet EasyRent.** Maintenu par l'agent `state-keeper`. Source de vérité pour les agents — à lire AVANT de grep/scanner le codebase.

## Métadonnées

- **Dernière mise à jour** : 2026-05-31T00:00:00Z
- **Commit ref** : `129e398` (refactor(leases): extract _kMaxAmountCents constant)
- **Branche** : `fix/lease-input-hardening`
- **Phase projet** : FEAT-001 ✅ + FEAT-002 ✅ + FEAT-003 ✅ + FEAT-004 ✅ + FEAT-005 ✅ implémentées. FEAT-006–010 en backlog.

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

## Changements majeurs FEAT-004

1. **15 nouveaux fichiers Dart** : `lib/features/tenants/` (data/domain/application/presentation + widgets)
2. **4 nouvelles routes GoRouter** : `/tenants`, `/tenants/new`, `/tenants/:id`, `/tenants/:id/edit`
3. **Dashboard modifié** : ListTile "Mes locataires" ajouté pour naviger vers `/tenants`
4. **1 nouveau helper** : `lib/core/utils/tenant_form_validators.dart` (réutilisable FEAT-005)
5. **1 widget réutilisable** : `lib/core/widgets/archive_confirm_dialog.dart` (déplacé de properties → core)
6. **Modèle `Tenant`** : freezed + json_serializable, snake_case via `@JsonKey`
7. **Widget `TenantLeaseSummary`** : Affiche les baux actifs pour un locataire (prépare FEAT-005)
8. **80+ tests nouveaux** : repositories, providers, form validators, widget tests
9. **Aucune dépendance pubspec ajoutée** : Réutilise freezed + json_serializable
10. **Aucune migration SQL** : FEAT-004 est purement frontend, table `tenants` existe déjà depuis FEAT-002

### Incohérences détectées

Aucune incohérence — état entièrement cohérent avec code.

## État de la base de code

- Code matches state — aucun drift détecté post-FEAT-004
- ~3500 lignes de tests totales (80+ tests créés en FEAT-004)
- RLS validée sur Postgres côté backend (FEAT-002)
- Flutter stable — 4 features complètes, prêt pour FEAT-005 (leases CRUD)
