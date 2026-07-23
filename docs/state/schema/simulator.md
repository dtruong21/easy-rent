# Schéma — simulator

> Source d'état — simulator. Maintenu par `state-keeper`.

Collection : `investment_scenarios`. CRUD direct (FEAT-018). Patterns transverses → [README](README.md).

## `investment_scenarios/{id}`

Simulateur immobilier. Accessible anonymes + comptes (CRUD direct client).

| Champ | Type | Notes |
|---|---|---|
| `id` | string | UUID, immuable |
| `landlordId` | string | FK → landlords.id, immuable |
| `name` | string | nom scénario (≤ 120 chars) |
| `schemaVersion` | int | version données (versionning) |
| `scenarioJson` | object | snapshot sérialisé |
| `createdAt` | timestamp | immuable |
| `updatedAt` | timestamp | CF trigger |
| `deletedAt` | timestamp\|null | soft-delete |

**Règles Firestore** :
- `get` : isOwner(landlordId) && isActive(rsc)
- `list` : isOwner(landlordId) — **pas d'`isActive`** (cf. properties, audit FEAT-045)
- `create` : isSignedIn() (anon OK) && landlordId==uid && deletedAt==null && id==docId && `name` string 1–120 chars && `schemaVersion` int > 0 && `scenarioJson` is map — **la validation de payload vit dans les rules**, pas seulement côté client
- `update` : isOwner(landlordId) && isActive(rsc) && preservesImmutables(rsc)
- `delete` : **if false** (soft-delete via `softDeleteEntity`)

**Index** (1, vérifié) : landlordId ↑, deletedAt ↑, **updatedAt ↓** (scenarios list).

> ⚠️ L'état annonçait `createdAt ↓` — c'est `updatedAt ↓`. Une liste triée par `createdAt` échouerait en index manquant.

**Triggers** : setUpdatedAt.
