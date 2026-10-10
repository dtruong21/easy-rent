# EasyRent

PWA française de gestion locative (+ apps natives iOS/Android). Stack : **Flutter (web + mobile) + Firebase (Firestore, Auth, Cloud Functions, Storage, Hosting) + GitHub**.

## ⚠️ Règle d'or — économie de tokens

1. **Avant de grep/scanner le code, lis d'abord [`docs/state/INDEX.md`](docs/state/INDEX.md)** — c'est un routeur léger (~1,5k tokens), pas le contenu.
2. **Charge UNIQUEMENT le(s) shard(s) du domaine concerné** : `docs/state/{schema,functions,routes}/<domaine>.md` (~0,2–1,5k tokens chacun). Ne charge JAMAIS tout l'état d'un coup ; un panorama transverse = le `README.md` du dossier.
3. **Lis ciblé** : `Grep` ou `Read` avec `offset`/`limit` plutôt que des fichiers entiers ; ne relis pas un fichier déjà vu ce tour.
4. **Sous-agents / workflows multi-agents = coûteux** (chaque agent consomme des tokens). Réserve-les aux gros travaux ponctuels (audit, migration en masse) ; pour une tâche de routine, travaille en solo.
5. **`/clear` entre tâches sans rapport** pour repartir d'un contexte propre.
6. Statut d'une feature → `docs/state/FEATURES.md` (matrice) ; historique détaillé → `docs/state/CHANGELOG.md` (rare). Ne re-scan le code que si l'état est manquant, périmé (> 7 j) ou douteux.
7. **Un shard périmé coûte PLUS cher qu'un grep honnête** : tu lui fais confiance, tu écris du code faux, un garde-fou te bloque, tu recommences. Le hook `SessionStart` lance [`scripts/check-state-drift.sh`](scripts/check-state-drift.sh) (coût zéro) et te dit quels shards sont suspects — **pour ceux-là, vérifie le code, ne fais pas confiance au shard**. Silence du hook = état frais.

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
| Versioning & releases (tags, codenames, build number) | [`docs/VERSIONING.md`](docs/VERSIONING.md) |
| Stratégie multi-environnement (dev/prod sur 1 projet) | [`docs/ENVIRONMENTS.md`](docs/ENVIRONMENTS.md) |
| App mobile iOS/Android (FEAT-024 : setup, build, décisions) | [`docs/MOBILE.md`](docs/MOBILE.md) |
| Conformité Play Store / App Store (release production) | [`docs/STORE_COMPLIANCE.md`](docs/STORE_COMPLIANCE.md) |
| Gestion des secrets et sécurité | [`docs/SECURITY.md`](docs/SECURITY.md) |
| Setup 2 PC (Claude Code Pro + ChatGPT Go/Codex) | [`docs/DUAL_PC_SETUP.md`](docs/DUAL_PC_SETUP.md) |
| Schéma Firestore (par domaine) | [`docs/state/schema/`](docs/state/schema/README.md) |
| Cloud Functions (par domaine) | [`docs/state/functions/`](docs/state/functions/README.md) |
| Routes Flutter (par domaine) | [`docs/state/routes/`](docs/state/routes/README.md) |
| Features (matrice de statut) | [`docs/state/FEATURES.md`](docs/state/FEATURES.md) |
| Changements récents (période courante, ~1k tokens) | [`docs/state/CHANGELOG.md`](docs/state/CHANGELOG.md) |
| Historique ancien (archives mensuelles, ~10k tokens — n'ouvrir qu'en dernier recours) | [`docs/state/changelog/`](docs/state/changelog/) |

## Definition of Done (essentiel)

1. Code formaté, `flutter analyze` clean
2. Règles Firestore testées (cross-user)
3. Tests passent
4. `code-reviewer` ✅, `security-auditor` ✅
5. **`docs/state/` à jour pour le(s) domaine(s) touché(s)** — `state-keeper` sur ces shards seulement, pas une passe complète. Sauter cette étape est ce qui fait exploser les tokens des sessions suivantes (cf. règle d'or n°7).
6. Rules + indexes : **déployés automatiquement par la CI** (`develop` → base `staging`, `main` → `(default)`, cf. [`docs/ENVIRONMENTS.md`](docs/ENVIRONMENTS.md)). Rien à faire à la main. Les **Cloud Functions** restent hors CI : déploiement manuel délibéré.
7. Déployé sur Firebase Hosting

> Checklist rapide avant PR : `/feature-ready <FEAT-ID>` (lecture seule,
> advisory, ne bloque rien). Elle liste ce qui manque — elle ne remplace ni la
> revue ni la QA.

## Garde-fous (jamais désactiver)

- **Accès Firestore : jamais en direct** (ADR 0003, isolation prod/staging).
  Flutter → `firestoreProvider` ([`lib/core/config/firestore_provider.dart`](lib/core/config/firestore_provider.dart)) ;
  `FirebaseFirestore.instance` / `.instanceFor` interdits hors `main.dart`.
  Functions → `dbForRequest(request)` pour les callables, `event.environment`
  (`firestoreForEnv`) pour le webhook RevenueCat ; `admin.firestore()` /
  `getFirestore()` interdits ailleurs dans `functions/src/` (crons et triggers
  exceptés, volontairement sur `(default)`).
  [`scripts/check-db-isolation.sh`](scripts/check-db-isolation.sh) l'impose en CI —
  un accès direct fait échouer la PR.
- **Règles Firestore obligatoires** sur toutes les collections (deny-by-default, isFullyAuthed/isOwner)
- **Pas de deploy prod sans confirmation utilisateur**
- **Quittances** : mentions légales loi 6 juillet 1989
- **RGPD** : consentement, export, droit à l'effacement
- **Secrets** : voir [`docs/SECURITY.md`](docs/SECURITY.md) — jamais de secret serveur / service account / clé `re_*` (Resend) côté client
