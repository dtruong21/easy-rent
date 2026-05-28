# Project State Index

> **Snapshot vivant du projet EasyRent.** Maintenu par l'agent `state-keeper`. Source de vérité pour les agents — à lire AVANT de grep/scanner le codebase.

## Métadonnées

- **Dernière mise à jour** : 2026-05-28T12:00:00Z
- **Commit ref** : `9db2741` (Merge pull request #2 from dtruong21/feature/data-model-rls)
- **Branche** : `develop`
- **Phase projet** : FEAT-001 (auth) + FEAT-002 (data model + RLS) implémentées et mergées. FEAT-003–010 en backlog.

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

Aucune incohérence — état entièrement cohérent avec code.

### Changements majeurs FEAT-002

1. **4 nouvelles tables** : `properties`, `tenants`, `leases` (public + dev) — docs dans `SCHEMA.md` (24 policies, 8 triggers, 8 RPC)
2. **FK change** : `landlords.id → auth.users(id)` : CASCADE → NO ACTION (rétention légale RGPD)
3. **Soft-delete framework** : Pattern tr_00/tr_01/tr_02 pour ordre d'exécution alphabétique stable
4. **RPC SECURITY DEFINER × 2 schémas** : 8 RPC soft-delete (4 tables × 2 schémas)
5. **77 RLS tests** : `rls_landlords.sql`, `rls_properties.sql`, `rls_tenants.sql`, `rls_leases.sql`
6. **Aucun changement Flutter** : FEAT-002 est purement backend
7. **Status upgrades** : FEAT-001 ✅ done, FEAT-002 ✅ done (migration appliquée prod 2026-05-28 12:00 UTC)

### État de la base de code

- Code matches state — aucun drift détecté post-FEAT-002
- Tests RLS exhaustifs (cross-user, soft-delete, cross-FK)
- RLS validée sur Postgres côté backend
- Flutter unchanged — prêt pour FEAT-003+ (UI CRUD)
