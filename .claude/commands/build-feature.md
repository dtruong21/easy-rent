---
description: Pipeline complet pour développer une feature — architect → dev → QA → review → security → deploy. Accepte un FEAT-ID, un numéro d'issue GitHub (#N), ou une description.
argument-hint: <#N> | <FEAT-id> | description de la feature
---

Tu es l'orchestrateur. Pilote le pipeline complet de développement d'une feature pour EasyRent.

## Feature à développer

$ARGUMENTS

## Pipeline

### 1. Préparation
- **Si l'argument commence par `#`** (issue GitHub) :
  - Charge l'issue : `gh issue view <N> --json number,title,body,labels`
  - Invoque `ticket-triage` pour valider la complétude
  - Si OK, invoque `product-owner` pour convertir l'issue en user story dans `docs/backlog/<id>-<slug>.md`
- **Si l'argument est un FEAT-ID** : lis `docs/backlog/<id>-*.md`
- **Sinon** : invoque `product-owner` pour créer la user story

- Crée une branche depuis develop : `git checkout develop && git pull && git checkout -b feature/<slug>`

### 2. Design
- Invoque `architect` avec le chemin de la story
- Vérifie que le plan a bien été écrit dans `docs/plans/`
- Pose à l'utilisateur les questions critiques surfacées par l'architecte AVANT de coder
  (en mode workflow automatique : assume les choix par défaut et logue les hypothèses)

### 3. Implementation (parallel quand possible)
- Si le plan contient des changements DB → invoque `supabase-dev` en premier
- Si le plan contient des PDF/email → invoque `pdf-emailer`
- Invoque `flutter-dev` pour le frontend

### 4. Qualité (obligatoire)
- `qa-tester` → tests + acceptance criteria
- `code-reviewer` → revue qualité
- `security-auditor` → audit RLS, secrets, RGPD

### 5. PR + lien à l'issue (si applicable)
- Push la branche
- Crée la PR avec :
  - **Base** : `develop` (toujours, jamais directement sur main)
  - `Closes #N` si l'argument était une issue GitHub
  - Résumé feature + écrans concernés
- Commente sur l'issue d'origine avec le lien PR

### 6. Livraison
- Demande confirmation utilisateur (manuel)
- `deployer` → staging
- Prod : confirmation explicite obligatoire (jamais en auto)

## Règles spéciales mode workflow (cron horaire)

Quand invoqué via `ticket-agent.yml` :
- Pas de question utilisateur → choix par défaut documentés
- Stop avant le deploy prod
- En cas d'échec : `agent-processing` → `agent-failed`, commenter l'erreur
