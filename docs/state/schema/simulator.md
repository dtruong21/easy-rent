# Schéma — simulator

> Source d'état — simulator. Maintenu par `state-keeper`.

Collection : `investment_scenarios`. Gating par callable (FEAT-056), patterns transverses → [README](README.md).

## `investment_scenarios/{id}`

Simulateur immobilier. Accessible anonymes + comptes. **CRÉATION : callable-exclusive depuis FEAT-056** (voir functions).

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
- `create` : **`if false` (FEAT-056 PR-2b)** — via callable `createScenario` (Admin SDK) uniquement ; elle impose quota_scenarios par palier effectif
- `update` : isOwner(landlordId) && isActive(rsc) && preservesImmutables(rsc)
- `delete` : **if false** (soft-delete via `softDeleteEntity`)

**Index** (1, vérifié) : landlordId ↑, deletedAt ↑, **updatedAt ↓** (scenarios list).

> ⚠️ L'état annonçait `createdAt ↓` — c'est `updatedAt ↓`. Une liste triée par `createdAt` échouerait en index manquant.

**Triggers** : setUpdatedAt.

**Champs LMNP** (FEAT-061) — posés en racine **et** dans `scenarioJson` ; absents des scénarios anciens (défauts à la lecture) :

| Champ | Type | Défaut | Bornes |
|---|---|---|---|
| `isFurnished` | bool | `false` | — (active la section fiscale) |
| `furnitureCents` | int | 0 | ≥ 0 (centimes, amorti 7 ans) |
| `tmiPercent` | int | 30 | ∈ {0, 11, 30, 41, 45} |
| `landSharePercent` | int | 15 | 0–50 |

**Quotas de scénarios** (FEAT-056) : anonymous=1 · free=3 · pro=15 · max=30 · ultra=null (illimité). Source canonique `config/entitlements.json`, appliqué par la callable `createScenario` (count live, pas de compteur dénormalisé).
