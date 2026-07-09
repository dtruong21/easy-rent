# Functions — Properties & Tenants

> Source d'état — properties. Maintenu par state-keeper.

Patrimoine (properties + tenants). CRUD via Firestore Rules + `softDeleteEntity` (voir account) — **aucun callable métier propre**. Fichier triggers : `functions/src/triggers/set_updated_at.ts`.

## Triggers

| Trigger | Type / collection | Logique |
|---|---|---|
| `setUpdatedAtProperties` | `onDocumentWritten(properties)` | Standard `setUpdatedAt` (voir README) |
| `setUpdatedAtTenants` | `onDocumentWritten(tenants)` | Standard `setUpdatedAt` (voir README) |

## Denorm — `activeLeaseCount`

Compteur dénormalisé sur `properties` **et** `tenants`, maintenu par les callables baux/soft-delete (pas par un trigger properties/tenants) :
- INCREMENT par `createLease` si `status=='active'` (voir leases) ;
- DECREMENT par `updateLease` (active→terminated) et `softDeleteEntity` (properties/tenants avec `status=='active'`) (voir leases, account).

Soft-delete `properties`/`tenants` refusé s'il reste des baux actifs (`softDeleteEntity`, voir account).
