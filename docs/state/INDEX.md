# Project State Index

> **Snapshot vivant du projet EasyRent.** Maintenu par l'agent `state-keeper`. Source de vérité pour les agents — à lire AVANT de grep/scanner le codebase.

## Métadonnées

- **Dernière mise à jour** : 2026-05-27T00:00:00Z
- **Commit ref** : `4011843` (init project with claude and flutter)
- **Branche** : `develop`
- **Phase projet** : Bootstrap initial — projet Flutter Web créé, agents IA configurés, infrastructure multi-env en place sur Supabase, aucune feature métier implémentée

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
| Navigation | GoRouter 14.6.0 |
| Backend | Supabase (Postgres + Auth + Storage) |
| PDF | pdf + printing packages |
| Build | build_runner + freezed + json_serializable |
| Hosting | Firebase Hosting (TBD) |
| CI/CD | GitHub Actions (TBD) |

## Incohérences détectées

Aucune incohérence majeure — projet bootstrap en bon état.

### Observations non-critiques

1. **supabase/functions/** : Répertoire n'existe pas → sera créé lors de FEAT-007 (send-receipt)
2. **docs/backlog/** : Répertoire vide → sera rempli par `product-owner` lors de `/discover`
3. **FEAT tables** : Aucune table métier créée → à créer progressivement par feature
4. **Auth tables** : `auth.users` de Supabase non documenté ici (géré par Supabase natif)
