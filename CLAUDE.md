# EasyRent

PWA française de gestion locative. Stack : **Flutter Web + Supabase + Firebase Hosting + GitHub**.

## ⚠️ Règle d'or pour économiser les tokens

**Avant de grep/scanner le codebase, lis toujours d'abord [`docs/state/INDEX.md`](docs/state/INDEX.md).**
Cet index pointe vers un snapshot à jour du schéma, des routes, des features et des dépendances. Ne re-scan le code que si l'état est manquant, périmé (> 7 jours), ou si tu as un doute légitime.

## Documents à lire à la demande (PAS auto-chargés)

| Quand tu as besoin de... | Lis ce fichier |
|---|---|
| Conventions de code détaillées | [`docs/CONVENTIONS.md`](docs/CONVENTIONS.md) |
| Contraintes légales françaises | [`docs/LEGAL.md`](docs/LEGAL.md) |
| Roadmap MVP et P1/P2 | [`docs/ROADMAP.md`](docs/ROADMAP.md) |
| Backlog ordonné | [`docs/BACKLOG.md`](docs/BACKLOG.md) |
| Pipeline d'agents | [`docs/AGENTS.md`](docs/AGENTS.md) |
| Schéma Supabase courant | [`docs/state/SCHEMA.md`](docs/state/SCHEMA.md) |
| Routes Flutter courantes | [`docs/state/ROUTES.md`](docs/state/ROUTES.md) |
| Features implémentées | [`docs/state/FEATURES.md`](docs/state/FEATURES.md) |

## Definition of Done (essentiel)

1. Code formaté, `flutter analyze` clean
2. RLS testée (cross-user)
3. Tests passent
4. `code-reviewer` ✅, `security-auditor` ✅
5. Migration Supabase appliquée
6. Déployé sur Firebase Hosting

## Garde-fous (jamais désactiver)

- **RLS obligatoire** sur toutes les tables
- **Pas de deploy prod sans confirmation utilisateur**
- **Quittances** : mentions légales loi 6 juillet 1989
- **RGPD** : consentement, export, droit à l'effacement
