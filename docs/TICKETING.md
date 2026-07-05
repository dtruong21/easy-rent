# EasyRent — Système de ticketing

> Tu crées des tickets sur GitHub Issues. Après 3h d'incubation, un agent IA prend le plus ancien éligible et lance le pipeline approprié. Tu reviewes la PR au bout.

## 📊 Vue d'ensemble

```
Tu  ──── crée issue ────►  GitHub Issues
                              │
                              │ 3h d'incubation
                              ▼
GitHub Actions (cron horaire :15)
                              │
                              │ Pick oldest eligible (>3h, pas de label opt-out)
                              ▼
                  Tag "agent-processing"
                              │
                              ▼
                       Claude Code (action)
                              │
                              │ /fix-bug #N ou /build-feature #N
                              ▼
                  Pipeline complet → PR
                              │
                              ▼
                  Tu reviewes la PR
                              │
                              ▼
              Merge → ticket-done.yml → "agent-done"
```

## 🎫 Comment créer un ticket

### Depuis le web/mobile
1. Va sur ton repo GitHub → onglet **Issues** → **New issue**
2. Choisis un template :
   - **🐛 Bug** — bugs trouvés en utilisation
   - **✨ Feature request** — nouvelle fonctionnalité
   - **❓ Question** — pas traité automatiquement
3. Remplis le formulaire (les champs obligatoires sont nécessaires pour l'agent)
4. Submit

### Depuis le terminal (avec `gh` installé)
```bash
gh issue create --label bug \
  --title "[BUG] Le calcul des charges arrondit mal" \
  --body "Voir details..."
```

## ⏱ Période d'incubation (3h)

**Pourquoi 3h** : te laisser le temps de :
- Compléter le ticket avec plus de détails
- Le fermer si finalement c'est pas un vrai bug
- Le marquer `agent-skip` si tu veux le traiter toi-même
- Le marquer urgent et lancer `/process-tickets force=#N` immédiatement

**Pendant l'incubation** :
- Aucun label automatique
- L'issue est invisible pour l'agent

**Après 3h** :
- Le cron horaire (à `:15` de chaque heure) prend le plus ancien éligible
- Tag `agent-processing` ajouté
- Commentaire automatique sur l'issue

## 🏷 Labels du système

| Label | Posé par | Effet |
|---|---|---|
| `bug` | Toi (via template) | Sera traité par `/fix-bug` après 3h |
| `feature-request` | Toi (via template) | Sera traité par `/build-feature` après 3h |
| `question` | Template question | Auto-ignoré par les agents |
| `agent-skip` | Toi | Exclut l'issue du traitement auto, même après 3h |
| `agent-processing` | Workflow | En cours de traitement — ne pas toucher |
| `agent-needs-info` | `ticket-triage` | Manque d'infos — édite l'issue puis retire ce label |
| `agent-failed` | Workflow | Pipeline a échoué — investiguer manuellement |
| `agent-done` | Workflow `ticket-done` | PR mergée — ticket clos |

## 🛡 Comment opt-out un ticket spécifique

Tu vois que la formulation est ambiguë, tu veux d'abord en parler ?
```bash
# Via web : ajoute le label "agent-skip" dans la sidebar de l'issue
# Via CLI :
gh issue edit <N> --add-label agent-skip
```
L'agent ne touchera jamais cette issue tant que le label est présent.

## 🔥 Forcer le traitement immédiat (urgence)

Si tu trouves un bug critique et veux pas attendre 3h :

**Option 1 — Manuel via Claude Code** (recommandé) :
```
/process-tickets force=#42
```

**Option 2 — Trigger le workflow GitHub** :
1. Actions → "Ticket Agent (autonomous)"
2. "Run workflow" → entre le numéro d'issue → Run

## ⚙️ Configuration nécessaire (à faire une fois)

### 1. Activer les labels système

Crée les labels suivants dans ton repo (Settings → Labels, ou via CLI) :

```bash
gh label create bug --color d73a4a --description "Bug confirmé"
gh label create feature-request --color a2eeef --description "Nouvelle fonctionnalité"
gh label create question --color d876e3 --description "Question (pas auto-traitée)"
gh label create agent-skip --color cccccc --description "Exclure du traitement auto"
gh label create agent-processing --color fbca04 --description "En cours par un agent IA"
gh label create agent-needs-info --color e99695 --description "Manque d'infos pour traiter"
gh label create agent-failed --color b60205 --description "Pipeline échoué"
gh label create agent-done --color 0e8a16 --description "Mergé par un agent IA"
```

### 2. GitHub Actions secrets

Dans Repo → Settings → Secrets and variables → Actions, ajoute :
- `CLAUDE_CODE_OAUTH_TOKEN` — token OAuth lié à ton abonnement Claude (gratuit, juste ta cap mensuelle)
  - Générer : `claude setup-token` dans un terminal
  - Détails : voir `.github/SECRETS.md`
- Plus les secrets de deploy (cf. `.github/SECRETS.md`)

### 3. (Optionnel) Désactiver le cron

Si tu veux passer en mode manuel uniquement :
- Repo → Settings → Actions → Workflows → "Ticket Agent" → Disable workflow
- Tu peux toujours déclencher manuellement via Actions → Run workflow

## 💰 Coût

Avec **`CLAUDE_CODE_OAUTH_TOKEN`** (auth via abonnement Claude) :
- **0 € en facturation directe** — l'usage compte sur la cap mensuelle de ton plan Claude (Team/Pro/Max)
- Le cron qui ne pick rien : aucune consommation
- Chaque `/fix-bug` réel : ~50-100k tokens consommés sur ta cap
- Chaque `/build-feature` : ~100-300k tokens consommés sur ta cap

**Si tu utilises l'API à la place** (`ANTHROPIC_API_KEY`) :

| Élément | Estimation |
|---|---|
| 1 cycle `/fix-bug` (simple) | 50k-100k tokens (~0,50-1,50 €) |
| 1 cycle `/build-feature` (P0) | 100k-300k tokens (~1,50-4 €) |
| Max théorique : 24 tickets/jour | ~12-100 € / jour |

→ **Recommandé** : reste sur l'OAuth subscription (gratuit dans ta cap). Pour limiter quand même la consommation de cap, voir section suivante.

## ⏱ Limiter la consommation

- **Désactiver la nuit** : remplace `'15 * * * *'` par `'15 8-20 * * 1-5'` (heures de bureau, jours ouvrés)
- **Quotidien au lieu d'horaire** : `'15 8 * * *'` (1 ticket/jour max)
- **Max 1 ticket à la fois** : déjà par défaut dans le workflow
- **Mode manuel** : Settings → Actions → Ticket Agent → Disable. Lance via `/process-tickets` quand tu veux

## 🚨 Garde-fous

- **Jamais de deploy prod auto** — l'agent stoppe au deploy staging
- **PR obligatoire** — l'agent crée une PR, jamais de push direct sur `main`
- **3 échecs consécutifs** sur le même ticket → `agent-failed`, à investiguer manuellement
- **Concurrency lock** : un seul agent à la fois sur l'ensemble du repo (`concurrency: ticket-agent`)
- **Idempotence** : le tag `agent-processing` empêche le double-traitement

## 🐛 Debug

**L'agent n'a pas pris mon ticket** ?
- Vérifie l'âge : il faut > 3h
- Vérifie les labels : pas de `agent-skip`, `agent-processing`, `agent-done`, `agent-failed`
- Vérifie qu'il a `bug` ou `feature-request`
- Regarde Actions → "Ticket Agent" → dernier run

**L'agent a échoué (`agent-failed`)** ?
- Lis le commentaire automatique sur l'issue
- Va dans Actions → run concerné → logs
- Corrige le problème → retire `agent-failed` → relance via `workflow_dispatch`
