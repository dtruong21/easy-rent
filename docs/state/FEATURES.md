# Features — registre

> Maintenu par `state-keeper`. **Dernière sync** : 2026-05-27

## Légende

- ✅ **done** : code mergé, testé, déployé
- 🟢 **ready** : code mergé, en attente de deploy
- 🚧 **wip** : en cours de développement
- 📋 **planned** : story écrite, pas commencé
- 💡 **idea** : dans le backlog mais pas spec'd

## Features implémentées

| ID | Nom | Statut | Notes |
|---|---|---|---|
| (bootstrap) | Projet Flutter Web + Riverpod + go_router + Supabase init | 🚧 stub | Squelette créé, écrans placeholders |

## Détails

### Bootstrap projet (non-feature)
- **Statut** : 🚧 squelette
- **Fichiers** : `lib/main.dart`, `lib/core/`, `lib/features/auth/`, `lib/features/dashboard/`
- **Routes** : `/`, `/login`
- **Tables Supabase** : _(aucune — infrastructure multi-env mise en place, aucune table métier)_
- **Widgets** : 
  - `LoginPage` : stub avec message "Écran de connexion à implémenter"
  - `DashboardPage` : stub avec message "Dashboard à implémenter"
- **État** : Bootstrap fonctionnel, prêt pour FEAT-001

## Prochaines features (cf. ROADMAP.md)

| ID | Nom | Priorité | Effort |
|---|---|---|---|
| FEAT-001 | Auth propriétaire (signup, login, magic link) | P0 | M |
| FEAT-002 | CRUD biens immobiliers | P0 | M |
| FEAT-003 | CRUD locataires | P0 | M |
| FEAT-004 | CRUD baux | P0 | M |
| FEAT-005 | Enregistrer paiement loyer | P0 | S |
| FEAT-006 | Générer quittance PDF conforme | P0 | M |
| FEAT-007 | Envoyer quittance par email (Edge Function + Resend) | P0 | M |
| FEAT-008 | Upload + stockage documents | P0 | M |
| FEAT-009 | Dashboard récap | P0 | S |
| FEAT-010 | Polish PWA (offline shell, install prompt) | P0 | S |

Les user stories détaillées seront créées par `product-owner` à la première exécution de `/discover`.

## État du backlog

- **Backlog directory** : `docs/backlog/` (empty — à remplir par product-owner lors de `/discover`)
- **Assigné à** : `product-owner` (agent), `feature-scout` (agent)
