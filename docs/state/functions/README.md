# Functions — Index des shards

> Source d'état — index functions. Maintenu par state-keeper.

Architecture 3-couches : (1) **Firestore Rules** (`firestore.rules`) — ownership + soft-delete + immuabilité ; (2) **Cloud Functions** (Node 20 TS ; pivot FEAT-019, 2026-07-02) — mutations cross-entity + soft-delete + denorm + validation juridique ; (3) **Firestore Triggers** — `setUpdatedAt*` + `recompute*`. Région `europe-west1` (override via `runWith({region})`).

Logique standard `setUpdatedAt*` (partagée par les 8 variants, `functions/src/triggers/set_updated_at.ts`) : `onDocumentWritten` (create/update/delete), post-write `change.after`, ignore soft-deleted (`deletedAt==null`), `updatedAt=FieldValue.serverTimestamp()` via Admin SDK, idempotent (clé docId+ts).

## Callables (14 documentés) → shard

| Callable | Feature | Shard |
|---|---|---|
| `createLease` | FEAT-005/036/042 | leases |
| `updateLease` | FEAT-005/036/042 | leases |
| `createPayment` | FEAT-006/029 | payments-receipts |
| `updatePayment` | FEAT-006 | payments-receipts |
| `generateReceipt` | FEAT-007 | payments-receipts |
| `voidReceipt` | FEAT-007 | payments-receipts |
| `markReceiptAsSent` | FEAT-007 | payments-receipts |
| `createDocument` (v2) | FEAT-008/041b | expenses-documents |
| `softDeleteDocument` | FEAT-008 | expenses-documents |
| `createExpense` | FEAT-041a | expenses-documents |
| `updateExpense` | FEAT-041a | expenses-documents |
| `softDeleteEntity` (universel) | — | account |
| `finalizeAnonymousUpgrade` | BAILLAN-M1/FEAT-019 | account |
| `deleteAccount` | FEAT-045 | account |

## Triggers (10) → shard

| Trigger | Collection écoutée | Shard |
|---|---|---|
| `setUpdatedAtLandlords` | landlords | account |
| `setUpdatedAtProperties` | properties | properties |
| `setUpdatedAtTenants` | tenants | properties |
| `setUpdatedAtLeases` | leases | leases |
| `setUpdatedAtPayments` | payments | payments-receipts |
| `setUpdatedAtDocuments` | documents | expenses-documents |
| `setUpdatedAtExpenses` | expenses | expenses-documents |
| `setUpdatedAtInvestmentScenarios` | investment_scenarios | simulator |
| `recomputeReceiptStale` | payments | payments-receipts |
| `recomputeChargeRegularization` (📋 PLANNED V1.1) | expenses | leases |

## Scheduled (1) → shard

| Scheduled | Cadence | Shard |
|---|---|---|
| `cleanupExpiredAnon` (BAILLAN-M1) | Daily 2 AM UTC | account |

> ⚠️ Le header source revendique « 28 callables + 8 triggers + 1 scheduled ». Ce snapshot documente nommément **14 callables + 10 triggers (8 `setUpdatedAt` + 2 `recompute`) + 1 scheduled**. L'écart de compteur (28 vs 14) est un drift du header non corrigé ici (fidélité à la source). Le résumé source mentionne aussi `setUpdatedAtReceipts` — inexistant dans les exports (receipts immuables) — voir payments-receipts.

> FEAT-043 (i18n « 5 ans » / citation loi 6/7/1989) : **no impact** sur les Cloud Functions (sync 2026-07-08).

## Ops

- **Deploy** : `npm run build && firebase deploy --only functions` (source ~50 KB compilée ; redéploie tous callables + triggers + scheduled).
- **Tests** : Vitest (`functions/src/__tests__/*.test.ts`). `npm run build` → `npm run test` (one-shot) / `npm run test:watch`. Rules : `npm run test:rules` (28 tests émulateur, `functions/rules-tests/firestore_rules.test.ts`). Couverts : `finalize_anonymous_upgrade.test.ts`, `delete_account.test.ts` (15 tests). TBD : expense/payment/receipt/soft-delete.
- **Logs** : `firebase functions:log` (stream/tail), Cloud Logging console.
- **Env** : `.env` local (test), Cloud Secret Manager (prod).
