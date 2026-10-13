# FEAT-055 — Comparaison de scénarios de simulation (Pro)

> **Statut** : 💡 Idea (2026-07-23) — captée pendant la revue FAQ, à prioriser dans BACKLOG.md avant de spec'r plus finement.
> **Effort estimé** : S (1-2 j) pour une V1 non-persistée. **Dépend de** : FEAT-018 (simulateur + `investment_scenarios`), FEAT-044 (freemium, `SubscriptionTier.paid`), FEAT-044e (checkout client Pro — 📋 planned).
> **Priorisation parente** : voir [`../BACKLOG.md`](../BACKLOG.md).

## Contexte

FEAT-018 permet de sauvegarder plusieurs scénarios de simulation (collection `investment_scenarios`, [`SavedScenariosRow`](../../lib/features/simulator/presentation/widgets/saved_scenarios_row.dart)). Aujourd'hui chaque scénario s'ouvre isolément via `/simulator/:id` — l'utilisateur doit basculer entre les onglets ou tenir un tableau à part pour comparer deux investissements. Un bailleur qui hésite entre deux biens perd du temps sans réponse claire.

FEAT-055 débloque la **comparaison côte-à-côte** de plusieurs scénarios sauvegardés. Fonction premium, cohérente avec le levier « scénarios illimités » du palier Pro (FEAT-044) : le compte free plafonne à 3 scénarios sauvegardés — comparer 2/3 y garde du sens, mais la vraie valeur du feature s'exprime au-delà.

## User story

**En tant que** bailleur Pro,
**je veux** comparer 2 à 3 scénarios de simulation côte à côte,
**afin de** trancher rapidement entre plusieurs investissements sans passer par un tableur externe.

## Périmètre

### Inclus (V1)
- Bouton « Comparer » dans le rail [`SavedScenariosRow`](../../lib/features/simulator/presentation/widgets/saved_scenarios_row.dart) → bascule en **mode sélection** (2 à 3 scénarios cochés, validation « Comparer les 2 » / « Comparer les 3 »).
- Écran `/simulator/compare?ids=…` : tableau, une colonne par scénario, écart en % vs. le premier scénario mis en évidence (couleur signal ≥ ±5 %).
- KPIs comparés (V1) : **rendement brut, rendement net, cash-flow mensuel, coût total du crédit, apport requis, effort d'épargne**.
- **Gate côté client** au tier `paid` (pattern identique à `chargeRegularizationProOnly`, FEAT-044b) : free voit le bouton grisé + upsell vers `/pro`. Aucune frontière de sécurité (calculs 100 % client).
- Responsive : desktop = colonnes, mobile = accordéons pliables par KPI (place à l'écran).

### Exclus (hors V1)
- Persistance de la paire de scénarios comparée (à réévaluer en V2).
- Export PDF de la comparaison (V2).
- Graphes (radar, barres) — V1 = tableau sec.
- Plus de 3 scénarios simultanément (limite UI ; à réévaluer).
- Comparaison de scénarios non sauvegardés (session in-memory).

## Acceptance criteria

1. **Given** un compte Pro avec ≥ 2 scénarios sauvegardés **When** il tape « Comparer » puis coche 2 scénarios **Then** `/simulator/compare` affiche les 6 KPIs de la V1 en colonnes côte à côte.
2. **Given** un compte free **When** il tente d'accéder à « Comparer » **Then** le bouton est visible mais désactivé, avec un upsell Pro (pattern FEAT-044b).
3. **Given** un compte Pro avec un seul scénario **Then** le bouton « Comparer » est masqué (rien à comparer).
4. **Given** une comparaison affichée **Then** les écarts en % vs. la 1ʳᵉ colonne sont calculés et lisibles.
5. **Given** un scénario supprimé pendant la comparaison **Then** l'écran se rafraîchit gracieusement (colonne retirée, pas de crash).

## Pistes techniques (à valider / affiner par l'architecte)

- **Data** : réutiliser `investmentScenariosListProvider` (déjà en place). Calculs 100 % côté client à partir de `scenarioJson` — aucune Cloud Function, aucun index composite.
- **Gate** : `SubscriptionTier.paid` via `landlordTierProvider` (pattern FEAT-044b). Gate produit, pas frontière de sécurité.
- **Route** : `/simulator/compare` avec query `?ids=a,b,c` (max 3), sous la branche `/simulator` du shell.
- **Widget** : nouveau `ScenarioComparisonTable`, réutilise les formatters existants de [`ScenarioResultsCard`](../../lib/features/simulator/presentation/widgets/scenario_results_card.dart).
- **i18n** : nouvelles clés FR + EN — `simulatorCompareButton`, `simulatorCompareTitle`, `simulatorCompareProOnly`, `simulatorCompareEmpty`, etc.

## Dépendances

- FEAT-018 (simulateur + persistance scénarios) ✅ livré.
- FEAT-044 (freemium, `SubscriptionTier.paid`) ✅ livré.
- **FEAT-044e** (checkout client Pro) — 📋 planned : sans le checkout en prod, le bouton grisé mène nulle part. **Bloquant** — attendre 044e avant de shipper 053.

## Synergie mobile (FEAT-024)

Adapté d'emblée au mobile (accordéons). Aucun conflit avec les chantiers en cours.
