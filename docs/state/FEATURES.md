# Features — registre

> Maintenu par `state-keeper`. **Dernière sync** : 2026-05-26

## Légende

- ✅ **done** : code mergé, testé, déployé
- 🟢 **ready** : code mergé, en attente de deploy
- 🚧 **wip** : en cours de développement
- 📋 **planned** : story écrite, pas commencé
- 💡 **idea** : dans le backlog mais pas spec'd

## Features

| ID | Nom | Statut | Notes |
|---|---|---|---|
| (bootstrap) | Projet Flutter Web + Riverpod + go_router + Supabase init | 🚧 stub | Squelette créé, écrans placeholders |

## Détails

### Bootstrap projet (non-feature)
- **Statut** : 🚧 squelette
- **Fichiers** : `lib/main.dart`, `lib/core/`, `lib/features/auth/`, `lib/features/dashboard/`
- **Routes** : `/`, `/login`
- **Tables Supabase** : _(aucune — projet Supabase pas encore initialisé)_
- **Note** : Les écrans LoginPage et DashboardPage sont des stubs avec texte "à implémenter".

## Prochaines features prévues (cf. ROADMAP.md)

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
