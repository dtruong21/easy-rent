# EasyRent — Pipeline d'agents AI

Ce document décrit le système d'agents qui développe EasyRent de la discovery jusqu'à la livraison.

## Vue d'ensemble

```
┌──────────────────────────────────────────────────────────────────┐
│                       PHASE 1 — DISCOVERY                         │
│  feature-scout (scan code/backlog)  →  product-owner (user story)│
└──────────────────────────────────────────────────────────────────┘
                              ↓
┌──────────────────────────────────────────────────────────────────┐
│                       PHASE 2 — DESIGN                            │
│                  architect (plan technique)                       │
└──────────────────────────────────────────────────────────────────┘
                              ↓
┌──────────────────────────────────────────────────────────────────┐
│                    PHASE 3 — IMPLEMENTATION                       │
│  supabase-dev (DB+RLS) │ flutter-dev (UI) │ pdf-emailer (docs)  │
└──────────────────────────────────────────────────────────────────┘
                              ↓
┌──────────────────────────────────────────────────────────────────┐
│                       PHASE 4 — QUALITY                           │
│  qa-tester  +  code-reviewer  +  security-auditor  +  bug-hunter │
└──────────────────────────────────────────────────────────────────┘
                              ↓
┌──────────────────────────────────────────────────────────────────┐
│                      PHASE 5 — DELIVERY                           │
│              deployer (Firebase Hosting + Supabase)              │
└──────────────────────────────────────────────────────────────────┘
```

## Les 10 agents

| Agent | Rôle | Modèle | Phase |
|---|---|---|---|
| `feature-scout` | Trouve features manquantes en scannant code/docs | haiku | Discovery |
| `product-owner` | Écrit user stories + critères d'acceptation | sonnet | Discovery |
| `architect` | Conçoit schéma DB, RLS, structure code | **opus** | Design |
| `supabase-dev` | Migrations Postgres, RLS, Edge Functions | sonnet | Implementation |
| `flutter-dev` | Code Flutter Web (Riverpod, go_router) | sonnet | Implementation |
| `pdf-emailer` | Génération PDF quittances + envoi emails | sonnet | Implementation |
| `qa-tester` | Tests widget/unit/RLS + QA manuelle | sonnet | Quality |
| `code-reviewer` | Revue qualité, conventions, smells | **opus** | Quality |
| `security-auditor` | RLS coverage, RGPD, secrets, RGPD | **opus** | Quality |
| `bug-hunter` | Scan proactif du codebase pour bugs/dette | **opus** | Quality |
| `state-keeper` | Maintient le cache d'état projet (docs/state/) | haiku | Maintenance |
| `deployer` | Firebase + Supabase deploy, GitHub Actions | haiku | Delivery |

## Slash commands d'orchestration

| Commande | Usage | Effet |
|---|---|---|
| `/discover` | Discovery + backlog grooming | feature-scout → product-owner |
| `/build-feature <id\|desc>` | Pipeline complet d'une feature | architect → devs → QA → deploy |
| `/fix-bug <id\|desc>` | Pipeline de correction de bug | diagnostic → fix → test → deploy |
| `/qa` | Passe QA complète sur la branche | qa-tester + bug-hunter + reviewer + auditor en parallèle |
| `/deliver staging\|prod` | Déploie après vérifs finales | deployer |
| `/auto-loop` | Mode autonome (cycle complet auto) | scout → choix → build → staging |
| `/refresh-state` | Rafraîchit le cache d'état projet | state-keeper |

## Mode automatique — 3 niveaux

### Niveau 1 — Manuel guidé (recommandé pour démarrer)
Tu lances les commandes une par une selon ton besoin :
```
/discover                  # Lundi matin : groomer le backlog
/build-feature FEAT-001    # Travailler une feature
/qa                        # Avant un commit important
/deliver staging           # Tester en staging
/deliver prod              # Mettre en prod (avec confirmation)
```

### Niveau 2 — Boucle locale avec `/loop`
Dans une session Claude Code, lance :
```
/loop 30m /auto-loop
```
→ Toutes les 30 min, Claude scoute le projet, choisit la prochaine unité de travail et la fait avancer jusqu'à staging.

### Niveau 3 — Automatisation GitHub Actions
Crée `.github/workflows/auto-dev.yml` qui :
- Tourne quotidiennement (cron)
- Lance Claude Code en mode headless avec `/auto-loop`
- Crée des PRs automatiquement

Exemple minimal :
```yaml
name: Auto-dev loop
on:
  schedule:
    - cron: '0 6 * * 1-5'  # 6h en semaine
  workflow_dispatch:
jobs:
  auto-loop:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          command: /auto-loop
```

## Workflow recommandé (semaine type)

| Jour | Commande | Pourquoi |
|---|---|---|
| Lundi | `/discover` | Groomer le backlog après le weekend |
| Mar-Jeu | `/build-feature` (× plusieurs) | Travailler les features du sprint |
| Vendredi matin | `/qa` | Passe QA complète avant la fin de semaine |
| Vendredi après-midi | `/deliver staging` | Tester en conditions réelles |
| Lundi suivant | `/deliver prod` | Mise en prod après recul du weekend |

## Comment ajouter un nouvel agent

1. Crée `.claude/agents/<nom>.md` avec frontmatter :
   ```yaml
   ---
   name: nom-agent
   description: Quand l'utiliser (cette description sert au matching automatique)
   model: sonnet | opus | haiku
   tools: Read, Write, Edit, Bash, Grep, Glob
   ---
   ```
2. Écris un prompt système clair (rôle, scope, règles, format de sortie)
3. Référence-le dans un slash command si pertinent
4. Mets à jour ce document

## Garde-fous critiques (ne jamais désactiver)

1. **RLS obligatoire** sur toutes les tables Supabase (enforced par `supabase-dev` et `security-auditor`)
2. **Pas de deploy prod sans confirmation utilisateur explicite** (enforced par `deployer` et `/deliver`)
3. **PR obligatoire** vers `main`, jamais de push direct (enforced par GitHub branch protection)
4. **Security audit obligatoire** avant chaque deploy (enforced par `/build-feature` et `/deliver`)
5. **Mentions légales obligatoires** sur les quittances (enforced par `pdf-emailer` et `qa-tester`)

## 💰 Stratégie d'optimisation des tokens

Le système est conçu pour **minimiser les tokens consommés à chaque session** et **éviter les re-scans inutiles**.

### Mécanisme : cache d'état projet (`docs/state/`)

Au lieu de re-scanner le codebase à chaque session, les agents lisent un **snapshot compact** maintenu sur disque :

```
docs/state/
├── INDEX.md          ← Point d'entrée (à lire en premier)
├── SCHEMA.md         ← Tables Postgres + policies RLS (compact)
├── ROUTES.md         ← Routes Flutter actuelles
├── FEATURES.md       ← Features implémentées et statut
├── DEPENDENCIES.md   ← Packages et versions
└── FUNCTIONS.md      ← Edge Functions déployées
```

### Économie typique

| Action | Sans cache | Avec cache | Gain |
|---|---|---|---|
| Architecte qui lit toutes les migrations | ~5k tokens | ~300 tokens (lit SCHEMA.md) | **94%** |
| Reviewer qui cherche les routes existantes | ~3k tokens | ~200 tokens | **93%** |
| Auditeur sécu qui vérifie RLS coverage | ~8k tokens | ~400 tokens | **95%** |
| Session démarrée (CLAUDE.md auto-chargé) | ~3k tokens | ~800 tokens | **73%** |

### Cycle de vie du cache

1. **À l'init du projet** : `state-keeper` est invoqué une fois pour construire l'état
2. **Après chaque feature mergée** : `state-keeper` rafraîchit (automatique via le pipeline)
3. **Manuellement** : `/refresh-state` quand on suspecte une dérive
4. **Détection auto** : les agents flag à l'utilisateur si `INDEX.md` date de > 7 jours

### Règle d'or pour les agents

Tous les agents ont reçu l'instruction : **lis `docs/state/` AVANT de grep le codebase**. Re-scan uniquement si l'état est manquant ou périmé.

### Modèles optimisés par coût

- **Opus** réservé aux décisions critiques (architect, code-reviewer, security-auditor, bug-hunter)
- **Sonnet** pour le développement (flutter-dev, supabase-dev, pdf-emailer, qa-tester, product-owner)
- **Haiku** pour les tâches mécaniques (feature-scout, deployer, state-keeper)

### Cache de prompt Anthropic (5 min TTL)

CLAUDE.md a été slimmé à ~800 tokens, stables → ils sont mis en cache automatiquement par l'API Anthropic dans une fenêtre de 5 minutes. **Tant que tu travailles activement, le coût marginal de CLAUDE.md est quasi-nul.**

### Fichier `.claudeignore`

Présent à la racine : exclut `build/`, `.dart_tool/`, fichiers générés (`*.g.dart`, `*.freezed.dart`), etc. Les scans Glob/Grep ne voient plus ces dossiers.

### Anti-pattern à éviter

❌ Lancer `/refresh-state` à chaque session
❌ Demander à un agent de "scanner tout le projet" sans préciser
❌ Garder des `docs/state/*.md` > 200 lignes (signal de re-scan nécessaire)

✅ Faire confiance au cache tant qu'il est récent
✅ Cibler les requêtes ("regarde la feature X") plutôt qu'ouvrir
✅ Laisser le pipeline rafraîchir l'état automatiquement après chaque merge

## Limites connues

- Les agents ne peuvent pas remplacer les **décisions produit** : invoque l'utilisateur pour les arbitrages
- L'IA peut **inventer des features** si tu ne cadres pas — d'où le rôle de `feature-scout` qui n'agit que sur des signaux concrets
- **Coûts API** : Opus est cher. Les 4 agents sur Opus (architect, code-reviewer, security-auditor, bug-hunter) sont sur Opus parce que la qualité d'analyse y est critique. Tu peux les passer en Sonnet si le budget devient un problème.
