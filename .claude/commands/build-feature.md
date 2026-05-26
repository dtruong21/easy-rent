---
description: Pipeline complet pour développer une feature — architect → dev → QA → review → security → deploy
argument-hint: <story-id> ou description de la feature
---

Tu es l'orchestrateur. Pilote le pipeline complet de développement d'une feature pour EasyRent.

## Feature à développer

$ARGUMENTS

## Pipeline à exécuter

### 1. Préparation
- Si l'argument est un ID de story (`FEAT-XXX`), lis `docs/backlog/<id>-*.md`
- Sinon, invoque `product-owner` pour créer la user story
- Crée une branche : `git checkout -b feat/<slug>`

### 2. Design
- Invoque `architect` avec le chemin de la story
- Vérifie que le plan a bien été écrit dans `docs/plans/`
- Pose à l'utilisateur les questions critiques surfacées par l'architecte AVANT de coder

### 3. Implementation (parallel quand possible)
- Si le plan contient des changements DB → invoque `supabase-dev` en premier (les migrations doivent passer)
- Si le plan contient des PDF/email → invoque `pdf-emailer`
- Invoque `flutter-dev` pour le frontend (après que la DB soit prête)

### 4. Qualité
- Invoque `qa-tester` pour écrire et lancer les tests
- Si verdict ❌ → renvoie à `flutter-dev` ou `supabase-dev` avec le bug report
- Invoque `code-reviewer`
- Si verdict 🟡 ou ❌ → renvoie à dev avec les changements demandés
- Invoque `security-auditor`
- Si verdict ❌ → renvoie au dev concerné

### 5. Livraison
- Confirme à l'utilisateur que tout est vert
- DEMANDE confirmation explicite avant de déployer
- Invoque `deployer` pour staging d'abord, puis prod

## Règles

- **Ne saute jamais une étape de qualité** (qa-tester, code-reviewer, security-auditor sont OBLIGATOIRES avant deploy)
- **Demande confirmation avant production** — jamais d'auto-deploy en prod
- **Surface les blockers immédiatement** plutôt que d'accumuler du travail à jeter
- **Reporte l'état à l'utilisateur** après chaque agent (1-2 lignes)
