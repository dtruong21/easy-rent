---
description: Fallback manuel — traite les tickets GitHub mûrs (>3h) sans attendre le cron horaire
argument-hint: [max=N] [force=#N]
---

Tu es l'orchestrateur. Traite manuellement les tickets GitHub éligibles.

## Argument

$ARGUMENTS

Format optionnel :
- `max=N` : nombre max de tickets à traiter dans cette passe (défaut: 1)
- `force=#N` : force le traitement d'un ticket spécifique, sans gate 3h

## Étapes

### 1. Liste les tickets éligibles

```bash
gh issue list \
  --state open \
  --json number,createdAt,labels,title \
  --limit 100 \
  --jq '[.[]
    | {number, createdAt, title, labels: [.labels[].name]}
    | select((.labels | index("bug")) or (.labels | index("feature-request")))
    | select((.labels | index("agent-processing")) | not)
    | select((.labels | index("agent-done")) | not)
    | select((.labels | index("agent-skip")) | not)
    | select((.labels | index("agent-failed")) | not)
    | select((now - (.createdAt | fromdateiso8601)) > 10800)
  ] | sort_by(.createdAt)'
```

Affiche le tableau à l'utilisateur :
```
| # | Title | Age | Labels |
|---|---|---|---|
```

### 2. Sélectionne

- Si `force=#N` : prends celui-là
- Sinon : prends le ou les plus anciens (limite `max`)
- Si liste vide : affiche "🟢 Aucun ticket éligible." et stop

### 3. Demande confirmation utilisateur

Sauf si l'argument contient `auto=true`, affiche les tickets sélectionnés et demande "Continuer ? (oui/non)".

### 4. Pour chaque ticket sélectionné

- Tag : `gh issue edit <N> --add-label agent-processing`
- Commente : "🤖 Pris en charge manuellement via /process-tickets"
- Invoque `ticket-triage` pour valider et router
- Dispatche au bon pipeline :
  - bug → `/fix-bug #<N>`
  - feature → `/build-feature #<N>`
- En cas d'échec : retire `agent-processing`, ajoute `agent-failed`, commente l'erreur

### 5. Récap

Affiche un résumé final :
- Tickets traités : ...
- PRs créées : ...
- Erreurs : ...
