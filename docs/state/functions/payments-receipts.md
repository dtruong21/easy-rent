# Functions — Payments & Receipts

> Source d'état — payments-receipts. Maintenu par state-keeper.

Paiements (FEAT-006/029) + quittances (FEAT-007). Fichiers : `functions/src/callable/lease_payment.ts` (payments), `functions/src/callable/receipts.ts`, `functions/src/triggers/recompute_receipt_stale.ts`.

## Callables — Payments

### `createPayment` (FEAT-006)
Client invoke.
- **Params** : `leaseId, rentAmountCents, chargesAmountCents, paidAt, paymentMethod, periodStart, periodEnd, notes` (FEAT-029 — motif libre, max 500 chars).
- **Validations** : auth + FK + ownership (via lease) ; `rentAmountCents > 0` or `chargesAmountCents > 0` ; `notes.length <= 500` (FEAT-029) ; periodStart < periodEnd.
- **Mutations** (transact) : CREATE `payments/{id}` snapshot denorm (propertyId, tenantLastName, etc) ; trigger `recomputeReceiptStale` (flag receipts liées staleness si montants changent).
- **Retour** : `{paymentId}`. **Post-write async** : `generateReceipt` AUTO-INVOKED sur ce paiement (crée/met à jour quittance associée).

### `updatePayment` (FEAT-006)
Client invoke.
- **Mutable** : `paidAt, paymentMethod, notes, reference` (immutable : leaseId, rentAmountCents, chargesAmountCents, periodStart, periodEnd, createdAt).
- **Logique** : fetch + ownership + isActive check ; patch cleanPatch (paidAt timestamp-validated) ; update transaction + trigger `recomputeReceiptStale` si montants changeaient (défense — code rejette les mutations quantitatives).
- **Retour** : `{updated:true}`.

## Callables — Receipts

### `generateReceipt` (FEAT-007)
Client invoke.
- **Params** : `leaseId` (immuable) + **soit** `paymentIds: string[]` **soit** `(periodStart, periodEnd)` pour requêter les paiements sur la période.
- **Logique** : fetch lease + landlord (auth + fields fullName/address requis loi 1989) ; load paiements (par IDs ou par période) ; calcul totaux (rentCents, chargesCents, totalCents) + période min/max + lastPaidAt ; dérive documentType (quittance si total ≥ loyer+charges, sinon reçu) ; CREATE `receipts/{id}` snapshot complet (propertyName, landlordFullName, tenantFullName, etc) + flags (isVoided=false, isStale=false, sentAt=null).
- **Retour** : `{receiptId, documentType, totalCents}`. **Pas de PDF côté serveur** — client (Flutter) génère via package `pdf` Dart à partir des champs immuables stockés ici. **Pas de Storage upload**.
- **Note** : quittance **immuable** post-création (art. L145-40 loi 6/7/1989 — rétention légale 5 ans).

### `voidReceipt` (FEAT-007)
Fetch receipt (auth + owner check) ; transaction : set `isVoided=true`, `voidedAt=now()`, `voidedReason=<motif>`. Idempotent (noop si déjà voided). **Retour** : `{voided:true}`.

### `markReceiptAsSent` (FEAT-007)
Fetch receipt (auth + owner check) ; transaction : set `sentAt=now()`, `sentToEmail=<optionnel>`. Audit trail (enregistre tentative d'envoi Web Share API côté client). **Pas de mail serveur** — Web Share API natif. **Retour** : `{sent:true}`.

## Triggers

| Trigger | Type / collection | Logique |
|---|---|---|
| `setUpdatedAtPayments` | `onDocumentWritten(payments)` | Standard `setUpdatedAt` (voir README). Fichier `set_updated_at.ts` |
| `recomputeReceiptStale` | `onDocumentWritten(payments)` | Create/update/delete payment → query ALL receipts où `leaseId==lease.id && paymentIds.contains(payment.id)` ; si montant (`rentAmountCents`, `chargesAmountCents`) change → flag `isStale=true` sur chaque receipt. Client rejoue `generateReceipt` si reçu stale. Admin SDK batch update. Quittances immuables (jamais update post-create, jamais soft-delete) — flag `isStale` seulement. Fichier `recompute_receipt_stale.ts`. |
