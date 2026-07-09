# Schéma — leases

> Source d'état — leases. Maintenu par `state-keeper`.

Collection : `leases`. CF exclusive (FEAT-036, FEAT-042, FEAT-006). Patterns transverses → [README](README.md).

**CROSS-ENTITY** : propertyId + tenantId doivent appartenir au même landlord (validation ownership CF). Charges = `chargesAmountCents` (récupérable, FEAT-036) + `nonRecoverableChargesCents` (informatif bailleur, FEAT-036). `chargeMode` (FEAT-042) détermine éligibilité régularisation (provisions uniquement).

## `leases/{id}`

| Champ | Type | Notes |
|---|---|---|
| `id` | string | UUID, immuable |
| `landlordId` | string | FK → landlords.id, immuable |
| `propertyId` | string | FK → properties.id, immuable, validation CF |
| `tenantId` | string | FK → tenants.id, immuable, validation CF |
| `propertyName` | string | snapshot properties.name (dénorm) |
| `propertyAddress` | string | snapshot properties.address |
| `tenantFirstName` | string | snapshot tenants.firstName |
| `tenantLastName` | string | snapshot tenants.lastName |
| `tenantEmail` | string | snapshot tenants.email |
| `rentAmountCents` | int | loyer mensuel (centimes) |
| `chargesAmountCents` | int | part RÉCUPÉRABLE (FEAT-036) — bilancée locataire via paiement + régularisation (provisions only) |
| `nonRecoverableChargesCents` | int | part NON-RÉCUPÉRABLE (FEAT-036) — informatif ; forcé à 0 en mode forfait (FEAT-042) |
| `startDate` | timestamp | début bail |
| `endDate` | timestamp\|null | fin bail |
| `status` | string | 'active' \| 'terminated' \| 'archived' |
| `leaseType` | string | 'unfurnished' \| 'furnished' \| 'mobility' \| 'student' |
| `chargeMode` | string\|null | FEAT-042 : 'provisions' (mensuelles + régularisation) \| 'forfait' (libératoire, pas de régularisation). Nullable = migration lazy ; dérivé de leaseType si null |
| `depositAmountCents` | int\|null | dépôt garantie |
| `paymentDay` | int | jour versement (1..28) |
| `paymentMethod` | string | 'virement' \| 'cheque' \| 'especes' \| 'prelevement' \| 'autre' |
| `irlIndexValue` | number\|null | indice IRL de révision |
| `irlQuarterRef` | string\|null | T[1-4]-YYYY (ex: T4-2025) |
| `agencyFeesCents` | int | frais agence |
| `solidarityClause` | bool | clause de solidarité |
| `entryInventoryDone` | bool | état des lieux entrée réalisé |
| `createdAt` | timestamp | immuable |
| `updatedAt` | timestamp | CF trigger |
| `deletedAt` | timestamp\|null | soft-delete, isActive filter |

**Charge Mode Resolution (FEAT-042)** :
- `chargeMode==null` (baux pré-042, migration lazy sans backfill) → getter Dart `effectiveChargeMode` dérive de `leaseType` :
  - `unfurnished` → `provisions` (art. 23 loi 6 juillet 1989, forcé serveur)
  - `mobility` → `forfait` (loi ELAN art. 25-18, forcé serveur)
  - `furnished` \| `student` → `provisions` (défaut sûr)
- `chargeMode` explicite (FEAT-042+) → validé serveur (`resolveChargeMode` impose cohérence type↔mode, rejette incohérences)
- **Forfait** : `nonRecoverableChargesCents` forcé à 0 serveur (ventilation interdite) — vaut aussi pour baux legacy mobilité

**Mutable fields** (updateLease) : rentAmountCents, chargesAmountCents, nonRecoverableChargesCents, endDate, status, leaseType, chargeMode, depositAmountCents, paymentDay, paymentMethod, irlIndexValue, irlQuarterRef, agencyFeesCents, solidarityClause, entryInventoryDone.

**RLS** :
- `get/list` : isOwner(landlordId) && isActive(rsc)
- `create/update/delete` : CF exclusive (`createLease`, `updateLease`, `softDeleteEntity`)

**Indexes** :
- landlordId ↑, deletedAt ↑, status ↑ (filter status)
- landlordId ↑, deletedAt ↑, startDate ↓ (recent first)
- landlordId ↑, deletedAt ↑, status ↑, startDate ↓ (KPI drill-down)
- tenantId ↑, deletedAt ↑, status ↑ (tenant active leases)
- propertyId ↑, tenantId ↑ (unicity check, CF validation)
- propertyId ↑, deletedAt ↑ (property lease count)

**Callables** : `createLease`, `updateLease`.

**Triggers** :
- setUpdatedAt
- activeLeaseCount increment/decrement (createLease/updateLease/softDelete transactionnel → properties/tenants)
