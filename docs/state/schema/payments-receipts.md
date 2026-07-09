# Schéma — payments-receipts

> Source d'état — payments-receipts. Maintenu par `state-keeper`.

Collections : `payments` (CF exclusive), `receipts` (rules read-only). Patterns transverses → [README](README.md).

---

## `payments/{id}` — CF exclusive (FEAT-006)

Paiement loyer/charges. **CROSS-ENTITY** : leaseId doit appartenir au même landlord. Motif libre sur reçu (FEAT-029).

| Champ | Type | Notes |
|---|---|---|
| `id` | string | UUID, immuable |
| `landlordId` | string | FK → landlords.id, immuable |
| `leaseId` | string | FK → leases.id, immuable, validation CF |
| `propertyId` | string | snapshot leases.propertyId (dénorm) |
| `tenantLastName` | string | snapshot leases.tenantLastName |
| `rentAmountCents` | int | portion loyer versée |
| `chargesAmountCents` | int | portion charges (= leases.chargesAmountCents prorate) versée |
| `amountCents` | int | total (rentAmountCents + chargesAmountCents) |
| `paidDate` | timestamp | date versement |
| `paymentMethod` | string | 'virement' \| 'cheque' \| 'especes' \| 'prelevement' \| 'autre' |
| `notes` | string\|null | motif libre (FEAT-029) → PDF |
| `createdAt` | timestamp | immuable |
| `updatedAt` | timestamp | CF trigger |
| `deletedAt` | timestamp\|null | soft-delete |

**RLS** :
- `get/list` : isOwner(landlordId) && isActive(rsc)
- `create/update/delete` : CF exclusive

**Indexes** :
- landlordId ↑, deletedAt ↑, leaseId ↑, paidDate ↓ (payment history)
- leaseId ↑, deletedAt ↑, paidDate ↓ (payment timeline)

**Callables** : `createPayment`, `updatePayment`.

**Triggers** :
- setUpdatedAt
- recomputeReceiptStale (si payment.amountCents change → flag stale receipts)

---

## `receipts/{id}` — CF exclusive (FEAT-007)

Quittance loyer (loi 6 juillet 1989). **IMMUABLE** : jamais soft-delete (rétention légale 5 ans). Annulation via `voidReceipt` (logique métier, jamais suppression).

| Champ | Type | Notes |
|---|---|---|
| `id` | string | UUID, immuable |
| `landlordId` | string | FK → landlords.id, immuable |
| `leaseId` | string | FK → leases.id, immuable |
| `paymentId` | string\|null | FK → payments.id (null si générée manuellement) |
| `propertyName` | string | snapshot properties.name |
| `tenantName` | string | snapshot tenants lastName |
| `amountCents` | int | montant |
| `periodStart` | timestamp | début période |
| `periodEnd` | timestamp | fin période |
| `receiptNumber` | string | numéro séquentiel |
| `status` | string | 'generated' \| 'voided' \| 'sent' (markers non-exclusifs, bits) |
| `receiptDate` | timestamp | date édition |
| `voidReason` | string\|null | raison annulation (si voided) |
| `accountDeletedAt` | timestamp\|null | FEAT-045 : stamp suppression compte (null si actif) — quittance conservée 5 ans |
| `retentionUntil` | timestamp\|null | FEAT-045 : date limite rétention légale (5 ans après suppression) — purge async après |
| `createdAt` | timestamp | immuable |
| `updatedAt` | timestamp | CF trigger (status only) |
| `deletedAt` | timestamp\|null | null (jamais supprimée en pratique, marquée voided) |

**RLS** :
- `get/list` : isOwner(landlordId) (**pas de filtre isActive** — voided restent lisibles audit)
- `create/update/delete` : CF exclusive (`generateReceipt`, `voidReceipt`, `markReceiptAsSent`)

**Indexes** :
- landlordId ↑, leaseId ↑, receiptDate ↓ (archiving, no isActive)
- landlordId ↑, status ↑, receiptDate ↓ (status tracking)

**Callables** : `generateReceipt`, `voidReceipt`, `markReceiptAsSent`.

**Triggers** :
- setUpdatedAt (status seulement)
- recomputeReceiptStale (si lease/payment change → flag staleness)
