# Routes — simulator

> Source d'état — simulator (investment_scenarios). Maintenu par state-keeper.

## Simulateur (hors shell, plein écran, BAILLAN-M1, FEAT-018, transition standard)

| Chemin | Page | Type | Guard | Params / notes |
|---|---|---|---|---|
| `/simulator` | SimulatorPage | CRUD | unauthenticated OR anonymous OR fullyAuthenticated | simulateur investissement, essai 14j accessible anonymes |
| `/simulator/:id` | SimulatorPage(scenarioId) | CRUD | idem | `id`=scenario UUID, édition scénario |

Comportement :
- Anonyme redirigé landing → `/simulator` (seul accès métier).
- Compte complet peut `push()` par-dessus shell (modal, retour via pop).
- Scénarios persistés (collection `investment_scenarios`, `landlordId=uid` invariant).

**FEATs** : FEAT-018 (simulateur, 2 routes).
