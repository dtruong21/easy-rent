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
- `get/list` : isOwner(landlordId) && isActive(rsc)
- `create` : isSignedIn() (anon OK) && landlordId==uid
- `update` : isOwner(landlordId) && preservesImmutables()
- `delete` : interdit (soft-delete via `softDeleteEntity`)

**Index** : landlordId ↑, deletedAt ↑, createdAt ↓ (scenarios list).

**Triggers** : setUpdatedAt.
