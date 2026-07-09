# Functions — Simulator

> Source d'état — simulator. Maintenu par state-keeper.

Scénarios d'investissement (`investment_scenarios`). CRUD via Firestore Rules + `softDeleteEntity` (voir account) — **aucun callable métier propre**. Fichier trigger : `functions/src/triggers/set_updated_at.ts`.

## Trigger

| Trigger | Type / collection | Logique |
|---|---|---|
| `setUpdatedAtInvestmentScenarios` | `onDocumentWritten(investment_scenarios)` | Standard `setUpdatedAt` (voir README) |

## Cycle de vie

- Soft-delete via `softDeleteEntity('investment_scenarios')` — OK (voir account).
- **Préservés** par `finalizeAnonymousUpgrade` (landlordId==uid constant, pas de migration — voir account).
- Soft-deleted par `cleanupExpiredAnon` sur expiration d'un compte anonyme (voir account).
- Hard-delete lors de `deleteAccount` (voir account).
