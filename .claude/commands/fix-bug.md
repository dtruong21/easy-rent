---
description: Pipeline pour corriger un bug — diagnostic → fix → test → review → deploy. Accepte un BUG-ID local, un numéro d'issue GitHub (#N), ou une description.
argument-hint: <#N> | <bug-id> | description du bug
---

Tu es l'orchestrateur. Pilote la correction d'un bug pour EasyRent.

## Bug à corriger

$ARGUMENTS

## Pipeline

### 1. Diagnostic (et chargement contexte)
- **Si l'argument commence par `#`** (issue GitHub) :
  - Charge l'issue : `gh issue view <N> --json number,title,body,labels,author,createdAt`
  - Invoque `ticket-triage` pour valider la complétude (sortie : OK ou needs-info)
  - Si needs-info : commenter, retirer `agent-processing`, ajouter `agent-needs-info`, STOP
- **Si l'argument est un BUG-ID** : lis `docs/bug-hunts/*.md` pour le contexte
- **Sinon** : invoque `bug-hunter` pour confirmer/reproduire le bug

### 1bis. Choisir la branche de base
- **Hotfix prod (label `hotfix` ou sévérité blocker en prod)** : `git checkout main && git pull && git checkout -b hotfix/<slug>`
- **Bug standard (par défaut)** : `git checkout develop && git pull && git checkout -b fix/<slug>`
- Le pipeline PR cible la même branche que la source (hotfix → main, fix → develop)

### 2. Décision
- Détermine l'agent compétent :
  - Bug UI/state → `flutter-dev`
  - Bug Firestore (rules, indexes, Cloud Functions) → traite-le directement dans
    `firestore.rules`, `firestore.indexes.json` ou `functions/src/`
  - Bug PDF/partage → `pdf-emailer`
- S'il y a impact data model → invoque d'abord `architect` pour valider l'approche

### 3. Fix
- Délègue le fix à l'agent compétent avec : description bug + repro + suggested fix
- Le dev doit AUSSI écrire un **test de non-régression** qui aurait attrapé le bug

### 4. Qualité (obligatoire)
- `qa-tester` : valider que le bug est corrigé ET que rien n'a régressé
- `code-reviewer` : valider la qualité du fix
- `security-auditor` : si le bug touchait à la sécurité (Firestore Rules, auth, secrets)

### 5. PR + lien à l'issue (si applicable)
- Push la branche
- Crée la PR avec :
  - **Base** : `develop` pour un fix standard, `main` pour un hotfix
  - `Closes #N` si l'argument était une issue GitHub
  - Description du fix et root cause
  - Tests ajoutés
- Commente sur l'issue d'origine avec le lien PR
- Le workflow `ticket-done.yml` tagguera `agent-done` automatiquement au merge
- **Pour un hotfix** : après merge dans `main`, ouvrir une seconde PR `main → develop` pour propager le fix

### 6. Livraison
- Demande confirmation utilisateur (sauf en mode workflow automatique → staging only)
- `deployer` → staging
- **Jamais** prod automatiquement (cf. garde-fous)

## Règles spéciales mode workflow (cron horaire)

Quand invoqué via `ticket-agent.yml`, donc sans utilisateur en ligne :
- Pas de question utilisateur → assume les choix par défaut
- Stop avant le deploy prod, deploy staging OK
- En cas d'échec : retirer `agent-processing`, ajouter `agent-failed`, commenter l'erreur
