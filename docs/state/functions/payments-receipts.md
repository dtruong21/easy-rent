# Functions — Payments & Receipts

> Source d'état — payments-receipts. Maintenu par state-keeper.

Paiements (FEAT-006/029) + quittances (FEAT-007). Fichiers : `functions/src/callable/lease_payment.ts` (payments), `functions/src/callable/receipts.ts`, `functions/src/triggers/recompute_receipt_stale.ts`.

## Callables — Payments

### `createPayment` (FEAT-006)
Client invoke.
- **Params** : `leaseId, amountCents, paidDate, paymentMethod, notes` (FEAT-029 — motif libre, max 500 chars).
- **Validations** : auth + FK + ownership (via lease) ; `amountCents > 0` ; `notes.length <= 500` (FEAT-029).
- **Mutations** (transact) : CREATE `payments/{id}` snapshot denorm ; trigger `recomputeReceiptStale` (invalidate liens receipts).
- **Retour** : `{paymentId}`. **Trigger post-write** : auto-invoke `generateReceipt` (async, FEAT-007).

### `updatePayment` (FEAT-006)
Rare — idempotent no-op si amount/period unchanged. Trigger `recomputeReceiptStale` si `amountCents` change.

## Callables — Receipts

### `generateReceipt` (FEAT-007)
Client invoke **OU** triggered post-payment.
- **Params** : `leaseId, paymentId` (optionnel — direct call ou post-payment trigger).
- **Logique** : fetch lease + payment + landlord (auth) ; PDF via `pdf`+`printing` (quittance loi 6/7/1989) ; upload → Storage `/receipts/{leaseId}/{receiptId}.pdf` ; CREATE `receipts/{id}` : `amountCents, periodStart/End, receiptNumber, receiptDate, status='generated', fileUrl`=signed URL (5 min, auto-refresh @access), `createdAt/updatedAt=now(), deletedAt=null`.
- **Retour** : `{receiptId, pdfUrl}`. Chemin trigger : payment creation → auto-invoke async. Chemin client : `LeaseReceiptsPage` bouton « Générer ».
- **Note** : quittance **immuable** (art. L145-40, loi 6/7/1989 — rétention 5 ans).

### `voidReceipt` (FEAT-007)
Fetch receipt + payment lié ; soft-delete payment (`deletedAt=now()`) ; receipt `status |= 'voided'` ; auto-`generateReceipt` remplacement (nouveau doc, relinking `payment.id` optionnel). **Retour** : `{newReceiptId}`.

### `markReceiptAsSent` (FEAT-007)
Fetch receipt ; `status |= 'sent'` ; audit trail (**pas de mail** — Web Share API côté client). **Retour** : `{success:true}`.

## Triggers

| Trigger | Type / collection | Logique |
|---|---|---|
| `setUpdatedAtPayments` | `onDocumentWritten(payments)` | Standard `setUpdatedAt` (voir README). Fichier `set_updated_at.ts` |
| `recomputeReceiptStale` | `onDocumentWritten(payments)` | Create/update/delete payment → fetch ALL receipts liées au lease ; si `payment.amountCents` change → invalidate, `isStale=true` ; client `generateReceipt` rejoue si `isStale==true` ; Admin SDK batch. Quittances immuables (pas de soft-delete) — flag `isStale` seulement. Fichier `recompute_receipt_stale.ts` |

> ⚠️ Le résumé source mentionne `setUpdatedAtReceipts` mais **aucun variant receipts n'existe** dans les exports `setUpdatedAt` (receipts immuables → pas de `updatedAt` recompute).
