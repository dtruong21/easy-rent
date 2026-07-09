# Schéma — expenses-documents

> Source d'état — expenses-documents. Maintenu par `state-keeper`.

Collections : `documents`, `expenses`. CF exclusive. Patterns transverses → [README](README.md).

---

## `documents/{id}` — CF exclusive (FEAT-008, FEAT-041b)

Justificatifs (contrats, baux scannés, attestations assurance, **FEAT-041b : reçus de dépenses** cat. `expense_receipt`). **Dénorm** : `legalHold` dérivée serveur depuis `category` (immuable après création).

| Champ | Type | Notes |
|---|---|---|
| `id` | string | UUID, immuable |
| `landlordId` | string | FK → landlords.id, immuable |
| `leaseId` | string\|null | FK → leases.id (optionnel), immuable |
| `propertyId` | string\|null | FK → properties.id (optionnel, context), immuable |
| `expenseId` | string\|null | FK → expenses.id (optionnel, FEAT-041b), immuable |
| `category` | string | 'lease_scan' \| 'insurance' \| 'expense_receipt' \| 'other' — dérivé catégorie juridique |
| `legalHold` | bool | true (lease_scan, insurance) / false (other) — immuable, verrouille soft-delete |
| `fileName` | string | nom fichier original |
| `fileUrl` | string | signed URL (5 min, renouvellement @ access) |
| `fileSizeBytes` | int | taille (validation < 25 MB) |
| `mimeType` | string | 'image/jpeg' \| 'application/pdf' \| … |
| `uploadedDate` | timestamp | date chargement |
| `createdAt` | timestamp | immuable |
| `updatedAt` | timestamp | CF trigger |
| `deletedAt` | timestamp\|null | soft-delete refusée si legalHold==true |

**RLS** :
- `get/list` : isOwner(landlordId) && isActive(rsc)
- `create/update/delete` : CF exclusive (`createDocument`, `softDeleteDocument`)

**Indexes** :
- landlordId ↑, deletedAt ↑, leaseId ↑ (lease documents)
- landlordId ↑, deletedAt ↑, expenseId ↑ (expense receipts, FEAT-041b)
- landlordId ↑, deletedAt ↑, category ↑ (category archiving)

**Callables** : `createDocument`, `softDeleteDocument`.

**Triggers** : setUpdatedAt.

---

## `expenses/{id}` — CF exclusive (FEAT-041a, FEAT-041b, FEAT-041c)

Dépenses immobilières. Registre unifié (nature + catégorie + régularisation + documents). **CROSS-ENTITY** : propertyId (obligatoire) + leaseId (optionnel, cohérence lease.propertyId) + documentId (optionnel). **Dénorm** : propertyName, tenantLastName (snapshots @ update). **Juridique** : `category` dérivée immuable depuis `nature` (décret 87-713), sauf override tracé via `categoryOverridden` (pas de verrouillage natif). FEAT-033 (snapshot figé) absorbé par ce modèle.

| Champ | Type | Notes |
|---|---|---|
| `id` | string | UUID, immuable |
| `landlordId` | string | FK → landlords.id, immuable |
| `propertyId` | string | FK → properties.id (obligatoire), immuable, validation CF |
| `propertyName` | string | snapshot properties.name (dénorm, rafraîchie @ update) |
| `leaseId` | string\|null | FK → leases.id (optionnel), immuable si fourni, validation CF |
| `tenantLastName` | string\|null | snapshot leases.tenantLastName (dénorm) |
| `documentId` | string\|null | FK → documents.id (optionnel, justificatif), immuable |
| `amountCents` | int | montant (centimes, ≥ 1) |
| `expenseDate` | timestamp | date engagement dépense |
| `nature` | string | 'condo_charges' \| 'property_tax' \| 'insurance_pno' \| 'management_fees' \| 'works' \| 'repair_maintenance' \| 'other' — enum immuable (redérivation @ change) |
| `category` | string | 'recoverable' (recoupée locataire) \| 'non_recoverable' (charge bailleur) — **dérivée serveur depuis nature** |
| `categoryOverridden` | bool | true si override autorisé par nature.locked==false |
| `periodYear` | int | exercice fiscal (année rattachement) — dérivé, configurable |
| `periodStart` | timestamp\|null | début période (obligatoire si category==recoverable, FEAT-041c) |
| `periodEnd` | timestamp\|null | fin période (obligatoire si category==recoverable) |
| `notes` | string\|null | notes internes (≤ 2000 chars) |
| `createdAt` | timestamp | immuable |
| `updatedAt` | timestamp | CF trigger |
| `deletedAt` | timestamp\|null | soft-delete |

**Nature → Category (NATURE_DEFAULT_CATEGORY, décret 87-713)** :
- `condo_charges` → recoverable (locked: false, override OK)
- `property_tax` → non_recoverable (locked: true)
- `insurance_pno` → non_recoverable (locked: true)
- `management_fees` → non_recoverable (locked: true)
- `works` → non_recoverable (locked: false)
- `repair_maintenance` → non_recoverable (locked: false)
- `other` → non_recoverable (locked: false)

**Mutable fields** (updateExpense) : amountCents, expenseDate, nature, category, periodStart, periodEnd, periodYear, documentId, notes. Re-dérivation @ nature/category change (category applique verrouillage).

**RLS** :
- `get/list` : isOwner(landlordId) && isActive(rsc)
- `create/update/delete` : CF exclusive (`createExpense`, `updateExpense`, `softDeleteEntity`)

**Indexes** :
- landlordId ↑, deletedAt ↑, propertyId ↑ (property expenses)
- landlordId ↑, deletedAt ↑, category ↑, periodYear ↑ (tax year categorization)
- propertyId ↑, deletedAt ↑, category ↑, periodStart ↓ (regularization feed)

**Callables** : `createExpense`, `updateExpense`.

**Triggers** :
- setUpdatedAt
- recomputeChargeRegularization (FEAT-041c, **planné pas déployé** — si nature change ou category==recoverable → alimente lease.nonRecoverableCharges ; periodStart/periodEnd pour drill-down)
