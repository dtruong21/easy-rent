# Functions — Payments & Receipts

> Source d'état — payments-receipts. Maintenu par state-keeper. Dernière sync : 2026-10-05.

Paiements (FEAT-006/029) + quittances (FEAT-007). Fichiers : `functions/src/callable/lease_payment.ts` (payments), `functions/src/callable/receipts.ts`, `functions/src/triggers/recompute_receipt_stale.ts`, `functions/src/scheduled/purge_expired_receipts.ts`.

## Callables — Payments

**ADR 0003** : tous les callables écrivant Firestore utilisent `await dbForRequest(request)` pour router vers la base prod ou staging : web par Origin, mobile par compte (`dbForLandlordUid`, prod d'abord).

### `createPayment` (FEAT-006)
Client invoke.
- **Params** : `leaseId, rentAmountCents, chargesAmountCents, paidAt, paymentMethod, periodStart, periodEnd, notes` (FEAT-029 — motif libre, max 500 chars).
- **Validations** : auth + FK + ownership (via lease) ; `rentAmountCents > 0` or `chargesAmountCents > 0` ; `notes.length <= 500` (FEAT-029) ; periodStart < periodEnd.
- **Mutations** (transact) : CREATE `payments/{id}` snapshot denorm (propertyId, tenantLastName, etc).
- **Retour** : `{paymentId}`.

> ⚠️ **Pas d'auto-génération de quittance.** L'état affirmait « `generateReceipt` AUTO-INVOKED sur ce paiement » — c'est faux : aucun trigger ni post-write n'appelle `generateReceipt`, il n'est invoqué **que** par le client. Un paiement créé n'a donc **pas** de quittance tant que l'utilisateur ne la génère pas explicitement. Vérifié : `generateReceipt` n'apparaît que dans son propre fichier et l'export `index.ts`.

### `updatePayment` (FEAT-006)
Client invoke.
- **Mutable** : `paidAt, paymentMethod, notes, reference` (immutable : leaseId, rentAmountCents, chargesAmountCents, periodStart, periodEnd, createdAt).
- **Logique** : fetch + ownership + isActive check ; patch cleanPatch (paidAt timestamp-validated) ; les montants sont immuables (le code rejette toute mutation quantitative), donc une quittance déjà émise reste valide — `recomputeReceiptStale` ne se déclenche **pas** sur un `updatePayment` (il ne réagit qu'au soft-delete, voir schéma).
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
| `setUpdatedAtPayments` | `onDocumentUpdated(payments)` | Standard `setUpdatedAt` (voir README). Fichier `set_updated_at.ts` |
| `recomputeReceiptStale` | `onDocumentUpdated(payments)` | **Se déclenche uniquement au changement de `deletedAt`** (soft-delete ou restauration d'un paiement), **pas** au changement de montant. Query les receipts où `paymentIds` array-contains le paiement, relit tous leurs paiements, pose `isStale = (≥ 1 paiement a deletedAt != null)`. Client rejoue `generateReceipt` si stale. Quittances immuables — flag `isStale` seulement. Fichier `recompute_receipt_stale.ts`. |

## Scheduled Functions

| Scheduled | Cron / Région | Logique |
|---|---|---|
| `purgeExpiredReceipts` | Quotidien 03:00 Europe/Paris, région europe-west1 (base `(default)`) | Hard-delete RGPD `receipts where retentionUntil <= now` (champ posé par `stampRetainedReceipts` lors de la suppression de compte, FEAT-045 ; valeur = suppression + 5 ans). Pagination paginée 400, hard-limit MAX_DELETES_PER_RUN 2000/run. Idempotent, aucun accès Storage. Fonction pure `purgeExpiredReceiptsImpl(db, now)`. Fichier `functions/src/scheduled/purge_expired_receipts.ts`. ✅ Testé : `functions/src/__tests__/purge_expired_receipts.test.ts` (5 cas). |
