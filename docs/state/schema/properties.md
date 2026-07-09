# Schéma — properties

> Source d'état — properties. Maintenu par `state-keeper`.

Collections : `properties`, `tenants` (patrimoine). CRUD direct client, isFullyAuthed only (anonyme N/A). Patterns transverses → [README](README.md).

---

## `properties/{id}`

Bien immobilier (appartement, maison, etc).

| Champ | Type | Notes |
|---|---|---|
| `id` | string | UUID, docId |
| `landlordId` | string | FK → landlords.id, immuable |
| `name` | string | adresse ou nom |
| `address` | string | complète (rue + code postal) |
| `type` | string | 'appartement' \| 'maison' \| 'studio' \| 'autre' |
| `activeLeaseCount` | int | dénorm (CF increment/decrement) — client read-only |
| `createdAt` | timestamp | immuable |
| `updatedAt` | timestamp | CF trigger |
| `deletedAt` | timestamp\|null | soft-delete, isActive filter |

**RLS** :
- `get/list` : isOwner(landlordId) && isActive(rsc)
- `create` : isFullyAuthed() && landlordId==uid && activeLeaseCount==0 à la création
- `update` : isFullyAuthed() && isOwner(landlordId) && preservesImmutables()
- `delete` : interdit (soft-delete CF exclusive)

**Indexes** :
- landlordId ↑, deletedAt ↑, name ↑ (list actives)
- landlordId ↑, deletedAt ↑, createdAt ↓ (recent first)

**Triggers** : setUpdatedAt.

---

## `tenants/{id}`

Locataire.

| Champ | Type | Notes |
|---|---|---|
| `id` | string | UUID |
| `landlordId` | string | FK → landlords.id, immuable |
| `firstName` | string | prénom |
| `lastName` | string | nom |
| `email` | string | regex `^[^@\s]+@[^@\s]+\.[^@\s]+$` |
| `activeLeaseCount` | int | dénorm (CF) — client read-only |
| `createdAt` | timestamp | immuable |
| `updatedAt` | timestamp | CF trigger |
| `deletedAt` | timestamp\|null | soft-delete, isActive filter |

**RLS** :
- `get/list` : isOwner(landlordId) && isActive(rsc)
- `create` : isFullyAuthed() && landlordId==uid && activeLeaseCount==0
- `update` : isFullyAuthed() && isOwner(landlordId) && preservesImmutables()
- `delete` : interdit

**Indexes** :
- landlordId ↑, deletedAt ↑, firstName ↑ (list search)
- landlordId ↑, deletedAt ↑, lastName ↑ (list search)

**Triggers** : setUpdatedAt.
