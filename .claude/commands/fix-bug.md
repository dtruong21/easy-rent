---
description: Pipeline pour corriger un bug — diagnostic → fix → test → review → deploy
argument-hint: <bug-id> ou description du bug
---

Tu es l'orchestrateur. Pilote la correction d'un bug pour EasyRent.

## Bug à corriger

$ARGUMENTS

## Pipeline

### 1. Diagnostic
- Si l'argument est un BUG-ID → lis `docs/bug-hunts/*.md` pour trouver le contexte
- Sinon, invoque `bug-hunter` pour confirmer/reproduire le bug
- Crée une branche `fix/<slug>`

### 2. Décision
- Détermine l'agent compétent :
  - Bug UI/state → `flutter-dev`
  - Bug DB/RLS/migration → `supabase-dev`
  - Bug PDF/email → `pdf-emailer`
- S'il y a impact data model → invoque d'abord `architect` pour valider l'approche

### 3. Fix
- Délègue le fix à l'agent compétent en lui donnant : description bug + repro + suggested fix
- Le dev doit AUSSI écrire un test qui aurait attrapé le bug (test de non-régression)

### 4. Qualité
- `qa-tester` : valider que le bug est corrigé ET que rien n'a régressé
- `code-reviewer` : valider la qualité du fix
- `security-auditor` : si le bug touchait à la sécurité (RLS, auth, secrets)

### 5. Livraison
- Demande confirmation utilisateur
- `deployer` → staging → prod

## Règles

- **Test de non-régression obligatoire** pour chaque bug corrigé
- **Root cause analysis** : documente la cause profonde dans le commit message
- **Hotfix protocol** : si bug critique en prod, on peut shortcut mais security-auditor reste obligatoire
