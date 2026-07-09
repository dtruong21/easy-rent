# EasyRent

PWA française de gestion locative (+ apps natives iOS/Android). Stack : **Flutter (web + mobile) + Firebase (Firestore, Auth, Cloud Functions, Storage, Hosting) + GitHub**.

## ⚠️ Règle d'or — économie de tokens

1. **Avant de grep/scanner le code, lis d'abord [`docs/state/INDEX.md`](docs/state/INDEX.md)** — c'est un routeur léger (~800 tokens), pas le contenu.
2. **Charge UNIQUEMENT le(s) shard(s) du domaine concerné** : `docs/state/{schema,functions,routes}/<domaine>.md` (~0,2–1,5k tokens chacun). Ne charge JAMAIS tout l'état d'un coup ; un panorama transverse = le `README.md` du dossier.
3. **Lis ciblé** : `Grep` ou `Read` avec `offset`/`limit` plutôt que des fichiers entiers ; ne relis pas un fichier déjà vu ce tour.
4. **Sous-agents / workflows multi-agents = coûteux** (chaque agent consomme des tokens). Réserve-les aux gros travaux ponctuels (audit, migration en masse) ; pour une tâche de routine, travaille en solo.
5. **`/clear` entre tâches sans rapport** pour repartir d'un contexte propre.
6. Statut d'une feature → `docs/state/FEATURES.md` (matrice) ; historique détaillé → `docs/state/CHANGELOG.md` (rare). Ne re-scan le code que si l'état est manquant, périmé (> 7 j) ou douteux.

## Documents à lire à la demande (PAS auto-chargés)

| Quand tu as besoin de... | Lis ce fichier |
|---|---|
| Conventions de code détaillées | [`docs/CONVENTIONS.md`](docs/CONVENTIONS.md) |
| Concept navigation & UX web+mobile | [`docs/UX_NAVIGATION.md`](docs/UX_NAVIGATION.md) |
| Contraintes légales françaises | [`docs/LEGAL.md`](docs/LEGAL.md) |
| Roadmap MVP et P1/P2 | [`docs/ROADMAP.md`](docs/ROADMAP.md) |
| Backlog ordonné | [`docs/BACKLOG.md`](docs/BACKLOG.md) |
| Pipeline d'agents | [`docs/AGENTS.md`](docs/AGENTS.md) |
| Système de ticketing (GitHub Issues + agents) | [`docs/TICKETING.md`](docs/TICKETING.md) |
| Git Flow (branches, releases, hotfixes) | [`docs/GITFLOW.md`](docs/GITFLOW.md) |
| Stratégie multi-environnement (dev/prod sur 1 projet) | [`docs/ENVIRONMENTS.md`](docs/ENVIRONMENTS.md) |
| App mobile iOS/Android (FEAT-024 : setup, build, décisions) | [`docs/MOBILE.md`](docs/MOBILE.md) |
| Conformité Play Store / App Store (release production) | [`docs/STORE_COMPLIANCE.md`](docs/STORE_COMPLIANCE.md) |
| Gestion des secrets et sécurité | [`docs/SECURITY.md`](docs/SECURITY.md) |
| Schéma Firestore (par domaine) | [`docs/state/schema/`](docs/state/schema/README.md) |
| Cloud Functions (par domaine) | [`docs/state/functions/`](docs/state/functions/README.md) |
| Routes Flutter (par domaine) | [`docs/state/routes/`](docs/state/routes/README.md) |
| Features (matrice de statut) | [`docs/state/FEATURES.md`](docs/state/FEATURES.md) |
| Historique détaillé des changements | [`docs/state/CHANGELOG.md`](docs/state/CHANGELOG.md) |

## Definition of Done (essentiel)

1. Code formaté, `flutter analyze` clean
2. Règles Firestore testées (cross-user)
3. Tests passent
4. `code-reviewer` ✅, `security-auditor` ✅
5. Migration Firestore (rules + indexes) déployée si applicable
6. Déployé sur Firebase Hosting

## Garde-fous (jamais désactiver)

- **Règles Firestore obligatoires** sur toutes les collections (deny-by-default, isFullyAuthed/isOwner)
- **Pas de deploy prod sans confirmation utilisateur**
- **Quittances** : mentions légales loi 6 juillet 1989
- **RGPD** : consentement, export, droit à l'effacement
- **Secrets** : voir [`docs/SECURITY.md`](docs/SECURITY.md) — jamais de secret serveur / service account / clé `re_*` (Resend) côté client
