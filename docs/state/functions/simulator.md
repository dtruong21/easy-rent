# Functions — Simulator

> Source d'état — simulator. Maintenu par state-keeper. Dernière sync : 2026-10-05.

Scénarios d'investissement (`investment_scenarios`). Création gâtée par quota (FEAT-056), lecture/update via Firestore Rules. Fichiers : `functions/src/callable/scenarios.ts`, `functions/src/triggers/set_updated_at.ts`.

## Callables

### `createScenario` (FEAT-056 PR-2b)
Signature `{name, notes, purchasePriceCents, ...}` (financials) → `{id, createdAt}`. Crée un scénario avec gating du quota par palier. Fichier `callable/scenarios.ts`.
- **Pourquoi callable** : jusqu'ici les scénarios étaient quota-free (le client écrivait direct) ; seul le simulateur lui était ouvert aux anonymes. Dès lors que le nombre **différencie** Pro/Max/Ultra, un plafond non-vérifié serveur serait contournable (écrit le document soi-même, bypasse les rules). Les Firestore Rules ne savent ni compter ni agréger → pas d'agrégation possible au create → callable obligatoire. L'ancienne `investment_scenarios/create` est passée à `if false`.
- **Validation** : tout le parsing client de `parseScenarioInputs` — c'est lui qui validait avant dans les rules. Payloads financiers (en centimes), montants positifs, durée et taux dans les bornes, `name` ≤ 120 chars.
- **Quota live, pas de compteur** : compté par `count()` live sur `investment_scenarios where deletedAt==null` pour le UID. Volume petit et borné (max 30 en Ultra) ; soft-delete universel → zéro compteur à entretenir.
- **Routing Firestore** (ADR 0003) : via `await dbForRequest(request)` — web par Origin, mobile par compte (`dbForLandlordUid`, prod d'abord).
- **Idempotence** : deux appels simultanés à la borne peuvent créer un doc de trop (race condition acceptée, volume borné, non lucratif, se résorbe à la suppression suivante — même pattern que documents).

## Trigger

| Trigger | Type / collection | Logique |
|---|---|---|
| `setUpdatedAtInvestmentScenarios` | `onDocumentUpdated(investment_scenarios)` | Standard `setUpdatedAt` (voir README) |

## Cycle de vie

- **Création** : via `createScenario` callable uniquement (FEAT-056).
- Soft-delete via `softDeleteEntity('investment_scenarios')` — OK (voir account).
- **Préservés** par `finalizeAnonymousUpgrade` (landlordId==uid constant, pas de migration — voir account).
- Soft-deleted par `cleanupExpiredAnon` sur expiration d'un compte anonyme (voir account).
- Hard-delete lors de `deleteAccount` (voir account).
