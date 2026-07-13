# Setup 2 PC — Claude Code Pro + ChatGPT Go

Objectif : deux machines, deux quotas IA indépendants, GitHub comme hub. Aucune synchro directe entre PC (pas de Dropbox/USB) : tout passe par branches + PR.

## PC A — machine principale (Claude Code, plan Pro)

Rôle : développement principal sur le repo — features, Firestore rules, Cloud Functions, refactors, debugging, **tous les déploiements Firebase**.

Checklist d'installation :

1. Git + clone du repo (`gh auth login` pour la CLI GitHub)
2. Flutter épinglé sur la version CI (voir `.github/workflows/ci.yml`), ajouté au PATH
3. Node 20+ (Cloud Functions) et Firebase CLI (`npm i -g firebase-tools`, `firebase login`)
4. Claude Code : `npm i -g @anthropic-ai/claude-code`, connexion avec le compte Pro
5. Dans le repo : `flutter pub get` puis `dart run build_runner build` (les `*.g.dart` sont gitignorés)
6. Android SDK / Xcode uniquement si builds mobiles sur cette machine

Économie de quota (Pro ≈ fenêtre glissante de 5 h, partagée avec claude.ai) :

- Arriver avec une **spec prête** (préparée sur le PC B) → moins d'allers-retours
- Éviter les pipelines multi-agents (`/build-feature` complet, workflows) pour les tâches de routine — travailler en solo, réserver les agents aux gros chantiers
- `/model` → Sonnet pour les tâches mécaniques, garder le modèle fort pour l'architecture
- `/clear` entre tâches sans rapport ; toujours lire `docs/state/` avant de scanner le code

## PC B — machine secondaire (ChatGPT Go)

Rôle : l'amont (specs, recherche) + l'aval (revue de PR) + petites tâches de code via Codex.

Checklist d'installation :

1. Git + clone du repo, VS Code (lecture/édition légère)
2. ChatGPT web (compte Go)
3. Codex CLI : `npm i -g @openai/codex`, connexion avec le compte ChatGPT — inclus dans Go, quota limité
4. Codex lit [`AGENTS.md`](../AGENTS.md) à la racine : périmètre restreint (docs, tests, petits fixes), branches `codex/*`
5. `flutter pub get` + `dart run build_runner build` si Codex doit lancer les tests

⛔ Sur ce PC : **aucun secret** (pas de service account, pas de `firebase login` avec droits de deploy, pas de clé `re_*`). Rien de sensible collé dans ChatGPT — voir [`docs/SECURITY.md`](SECURITY.md).

## Répartition des rôles

| Tâche | Outil |
|---|---|
| Features, backend Firebase, refactors, debugging | Claude Code (PC A) |
| Déploiements (hosting, functions, rules) | PC A uniquement |
| User stories, specs, recherche (légal FR, RGPD, web) | ChatGPT (PC B) |
| Traductions FR/EN, copy marketing/SEO | ChatGPT (PC B) |
| Docs, tests unitaires, petits fixes 1–2 fichiers | Codex (PC B), branches `codex/*` |
| Revue croisée des PR | L'outil qui n'a **pas** écrit le code |

## Flux de travail

1. **Spec** (PC B) : rédiger la user story + critères d'acceptation dans ChatGPT → créer l'issue GitHub (format de [`docs/TICKETING.md`](TICKETING.md))
2. **Implémentation** (PC A) : `/build-feature #N` ou travail solo sur branche `claude/*` → PR vers `develop`
3. **Revue croisée** (PC B) : coller le diff de la PR dans ChatGPT (ou `codex review`) pour un second avis
4. **Merge + deploy** (PC A) : staging (`firebase hosting:channel:deploy staging`) puis prod avec confirmation

Couverture des quotas : les deux fenêtres de 5 h sont indépendantes. Quand Claude Pro est épuisé → basculer sur PC B (préparer la spec suivante, revoir les PR ouvertes, laisser Codex traiter un petit ticket). Et inversement.

## Règles anti-conflit

- Une branche = un outil. Claude sur `claude/*`, Codex sur `codex/*` ; jamais deux outils sur la même branche
- `git pull` systématique avant de démarrer une session sur l'un ou l'autre PC
- `dart format .` avant chaque push (la CI échoue sinon) — vaut aussi pour les commits Codex
- Les décisions d'architecture se prennent sur PC A (Claude a le contexte `docs/state/`) ; ChatGPT sert de contradicteur, pas de décideur
