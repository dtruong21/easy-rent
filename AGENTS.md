# EasyRent — Instructions agents (Codex & autres)

> Fichier lu par Codex CLI/IDE. Les règles complètes sont dans [CLAUDE.md](CLAUDE.md) — ce fichier en reprend l'essentiel.

## Contexte

PWA française de gestion locative (+ apps iOS/Android). Stack : **Flutter (web + mobile) + Firebase (Firestore, Auth, Cloud Functions, Storage, Hosting)**. Textes UI en français (i18n FR/EN).

## Règle d'or — lire l'état avant le code

1. Avant tout grep/scan, lis [`docs/state/INDEX.md`](docs/state/INDEX.md) (routeur léger).
2. Charge uniquement le(s) shard(s) du domaine : `docs/state/{schema,functions,routes}/<domaine>.md`.
3. Statut d'une feature → `docs/state/FEATURES.md`.

## Périmètre Codex (PC secondaire)

Codex tourne sur le plan ChatGPT Go (quota limité) : réserve-le aux **tâches légères** :

- ✅ Docs, tests unitaires/widget, petits fixes 1–2 fichiers, refactors localisés
- ⛔ Pas de déploiement Firebase (hosting, functions, rules, indexes) — réservé au PC principal
- ⛔ Pas de modification de `firebase.json`, des règles Firestore ou des workflows CI sans ticket explicite

## Conventions obligatoires

- **Branches** : travaille sur `codex/<sujet>` (jamais sur `main`/`develop`, jamais sur une branche `claude/*` en cours)
- **`dart format .` avant chaque commit** — la CI échoue sur un fichier Dart non formaté (y compris les tests générés)
- `flutter analyze` clean avant de pousser
- Worktree/clone frais : lancer `dart run build_runner build` (les `*.g.dart` sont gitignorés)
- Flutter doit être sur le PATH (version CI épinglée : voir `.github/workflows/ci.yml`)

## Garde-fous (jamais désactiver)

- Règles Firestore deny-by-default sur toutes les collections
- **Secrets** : jamais de service account, clé serveur ou clé `re_*` (Resend) côté client ni dans un prompt — voir [`docs/SECURITY.md`](docs/SECURITY.md)
- Quittances : mentions légales loi du 6 juillet 1989
- RGPD : consentement, export, droit à l'effacement
