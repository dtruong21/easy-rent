# Routes — simulator

> Source d'état — simulator (investment_scenarios). Maintenu par state-keeper. Dernière sync : 2026-07-30.

## Simulateur + comparaison (hors shell, plein écran, BAILLAN-M1, FEAT-018 + FEAT-055, transition standard)

| Chemin | Page | Type | Guard | Params / notes |
|---|---|---|---|---|
| `/simulator` | SimulatorPage | CRUD | unauthenticated OR anonymous OR fullyAuthenticated | simulateur investissement, essai 14j accessible anonymes |
| `/simulator/:id` | SimulatorPage(scenarioId) | CRUD | idem | `id`=scenario UUID, édition scénario |
| `/simulator/compare` | ScenarioComparisonPage | Read-only (Pro) | idem | query param `ids=` (CSV, max 3), comparaison côte-à-côte scénarios (FEAT-055) |

Comportement :
- Anonyme redirigé landing → `/simulator` (seul accès métier).
- Compte complet peut `push()` par-dessus shell (modal, retour via pop).
- Scénarios persistés (collection `investment_scenarios`, `landlordId=uid` invariant).
- Comparaison : accès par feature gate (Pro + statut entitlement) ⚠️ *pas encore gâté côté route* (cf. FEAT-055 wip dans la page elle-même).
- **Apps iOS/Android sans achat intégré** (2026-09-30 — aucun achat hors achat intégré ; prédicat `canOfferUpgrade` faux depuis FEAT-044e lot 2, 2026-10-09) : modale de limite de scénarios sans CTA d'upgrade vers `/pro` (fermeture libellée « Fermer » ; le cas anonyme garde « Créer un compte » + « Plus tard ») ; `/simulator/compare` sans CTA « Passer à Pro » (message seul) ; tuile verrouillée « comparer » des scénarios sauvegardés masquée. Section « Prochainement — Plan Pro » (`ComingSoonPaidPlanSection`) masquée dès `isStoreApp`.

**FEATs** : FEAT-018 (simulateur, 2 routes) + FEAT-055 (comparaison, 1 route, 2026-07-30).
