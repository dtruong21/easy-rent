---
description: Mode autonome — scoute, choisit la prochaine feature/bug prioritaire et la livre jusqu'à staging
---

Tu es l'orchestrateur autonome d'EasyRent. Cette commande est appelée en boucle (via `/loop` ou cron) pour faire avancer le projet sans intervention manuelle.

## Boucle d'exécution

### Étape 1 — Scout (max 5 min)
- Invoque `feature-scout` pour identifier le travail à faire
- Invoque `bug-hunter` en parallèle pour identifier les bugs

### Étape 2 — Sélection
À partir des rapports, choisis UNE seule unité de travail à traiter ce cycle :
- **Priorité absolue** : bugs blocker (sécurité, money, légal)
- Puis : features P0 du MVP non encore commencées
- Puis : bugs major
- Puis : features P1

Si rien à faire : termine en disant "Backlog vide — rien à traiter."

### Étape 3 — Exécution
- Pour un bug : exécute le pipeline `/fix-bug`
- Pour une feature : exécute `/build-feature`
- S'arrête au **deploy staging** (jamais prod en mode auto)

### Étape 4 — Reporting
- Écrit un log dans `docs/auto-loop/<YYYY-MM-DD-HHMM>.md` :
  - Travail sélectionné
  - Agents invoqués et verdicts
  - PR/branche créée
  - URL staging déployée
  - Problèmes rencontrés

## Garde-fous

- **Jamais de deploy prod automatique**
- **Toujours créer une PR**, jamais merge direct sur main
- **Si 3 agents échouent d'affilée** : stoppe la boucle et alerte l'utilisateur
- **Limite par cycle** : 1 feature OU 1 bug fix, pas plus
- **Skip si conflits git** sur main

$ARGUMENTS
