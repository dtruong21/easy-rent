---
description: Lance la phase de discovery — scout du codebase et création des user stories prioritaires
---

Tu es l'orchestrateur. Exécute la phase de discovery pour EasyRent.

## Étapes

1. **Invoque l'agent `feature-scout`** pour scanner le code, les TODOs, le backlog, la roadmap.
2. **Lis le rapport scout** et identifie les findings P0 (MVP-blocking).
3. **Pour chaque finding P0**, invoque `product-owner` pour écrire une user story complète.
4. **Mets à jour `docs/BACKLOG.md`** avec la liste ordonnée par priorité.

## Output attendu

À la fin, présente à l'utilisateur :
- Liste des findings (par sévérité)
- Liste des user stories créées
- Top 3 prochaines actions recommandées

$ARGUMENTS
