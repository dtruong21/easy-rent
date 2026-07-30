# Functions — Index des shards

> Source d'état — index functions. Maintenu par state-keeper.

Architecture 3-couches : (1) **Firestore Rules** (`firestore.rules`) — ownership + soft-delete + immuabilité ; (2) **Cloud Functions** (Node 20 TS ; pivot FEAT-019, 2026-07-02) — mutations cross-entity + soft-delete + denorm + validation juridique ; (3) **Firestore Triggers** — `setUpdatedAt*` + `recompute*`. Région `europe-west1` (override via `runWith({region})`).

**ADR 0003 — isolation prod/staging (2026-07-25)** : Firestore existe en deux bases — `(default)` prod, `staging` staging web. Les callables écrivant vers Firestore **DOIVENT** passer par le helper `dbForRequest(request)` (`functions/src/utils/db_router.ts`), qui route par l'en-tête `Origin` du navigateur. Le webhook RevenueCat (pas d'Origin) utilise `dbForLandlordUid(uid)` qui cherche le doc landlord dans prod d'abord (fail-safe), puis staging. **Interdit** : appeler `admin.firestore()` ou `getFirestore()` directement dans les callables/HTTP (sauf le routing lui-même). Crons et triggers restent sur `(default)` volontairement.

Logique standard `setUpdatedAt*` (fabrique `makeSetUpdatedAt`, `functions/src/triggers/set_updated_at.ts`) : **`onDocumentUpdated`** — se déclenche **uniquement sur update**, jamais sur create ni delete (à la création, la callable pose déjà `createdAt==updatedAt`). Garde anti-boucle : no-op si le client a déjà avancé `updatedAt` (`after.updatedAt > before.updatedAt`) ; sinon pose `updatedAt=FieldValue.serverTimestamp()` via Admin SDK. **Aucun filtre `deletedAt`** — un soft-delete est un update comme un autre. Région `europe-west1`.

> **8 variants** : 7 dans `set_updated_at.ts` (landlords, properties, tenants, leases, payments, documents, investment_scenarios) + `setUpdatedAtExpenses` dans `callable/expenses.ts` (même fabrique). **Pas** de variant `receipts` (collection immuable, sans champ `updatedAt`).
>
> ⚠️ L'état décrivait ces triggers comme `onDocumentWritten (create/update/delete)` et « ignore soft-deleted (`deletedAt==null`) » : **les deux sont faux**. Erreur systémique corrigée dans tous les shards `functions/` (elle subsistait même dans les shards réputés vérifiés au refresh #133).

## Callables (17) → shard

| Callable | Feature | Shard |
|---|---|---|
| `createProperty` | FEAT-044 (gate 2 biens free) | properties |
| `createTenant` | FEAT-044 (gate 3 locataires free) | properties |
| `createLease` | FEAT-005/036/042 | leases |
| `updateLease` | FEAT-005/036/042 | leases |
| `createPayment` | FEAT-006/029 | payments-receipts |
| `updatePayment` | FEAT-006 | payments-receipts |
| `generateReceipt` | FEAT-007 | payments-receipts |
| `voidReceipt` | FEAT-007 | payments-receipts |
| `markReceiptAsSent` | FEAT-007 | payments-receipts |
| `createDocument` (v2) | FEAT-008/041b | expenses-documents |
| `getDocumentDownloadUrl` | FEAT-008 | expenses-documents |
| `createExpense` | FEAT-041a | expenses-documents |
| `updateExpense` | FEAT-041a | expenses-documents |
| `softDeleteEntity` (universel) | — | account |
| `finalizeAnonymousUpgrade` | BAILLAN-M1/FEAT-019 | account |
| `deleteAccount` | FEAT-045 | account |
| `createCheckoutSession` | FEAT-044 paiement web (PR #117) | account |

## HTTP / webhooks (1) → shard

| Fonction | Déclencheur | Shard |
|---|---|---|
| `revenueCatWebhook` (`onRequest`) | POST RevenueCat, header `Authorization` vs `REVENUECAT_WEBHOOK_AUTH` | account |

> **1re et seule fonction `onRequest` du codebase** (PR #114). Écrivain autoritaire de `landlords/{uid}.subscriptionTier` via Admin SDK — les règles Firestore restent inchangées (tier client-immuable).

## Triggers (9 déployés + 1 planned) → shard

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

## Scheduled (2) → shard

| Scheduled | Cadence | Shard |
|---|---|---|
| `cleanupExpiredAnon` (BAILLAN-M1) | `0 3 * * *` **Europe/Paris** | account |
| `reconcileEntitlements` (FEAT-044, PR #114) | `30 3 * * *` Europe/Paris | account |

> ⚠️ Décompte re-vérifié dans `functions/src/index.ts` (2026-07-21) : **17 callables + 9 triggers déployés (8 `setUpdatedAt` + `recomputeReceiptStale`) + 1 HTTP + 2 scheduled**. `recomputeChargeRegularization` est **PLANNED V1.1 (non déployé)** — listé mais hors décompte. `setUpdatedAtReceipts` n'existe pas (receipts immuables).
>
> Corrections de cette passe : la table listait **14** callables et omettait `createProperty`/`createTenant` (livrés en FEAT-044, PR #91) ; `cleanupExpiredAnon` était annoncé « Daily 2 AM UTC » alors que le code dit `0 3 * * *` en `Europe/Paris`.

> FEAT-043 (i18n « 5 ans » / citation loi 6/7/1989) : **no impact** sur les Cloud Functions (sync 2026-07-08).

## Ops

- **Deploy** : `npm run build && firebase deploy --only functions` (redéploie callables + triggers + HTTP + scheduled).
- **Secrets requis AVANT déploiement** (`firebase functions:secrets:set`) : `STRIPE_SECRET_KEY`, `REVENUECAT_WEBHOOK_AUTH`, `REVENUECAT_API_KEY`. Params non secrets : `STRIPE_PRICE_PRO_MONTHLY`, `STRIPE_PRICE_PRO_ANNUAL`, `WEB_APP_BASE_URL` (défaut `https://baillan.com`).
- **Tests** : Vitest — **209 cas** dans `functions/src/__tests__/` (13 fichiers), dont `rental_register_free_e2e.test.ts` (chaîne createProperty→createTenant→createLease→createPayment en tier free), `revenuecat_webhook.test.ts`, `reconcile_entitlements.test.ts`, `create_checkout_session.test.ts`. Rules : `npm run test:rules` → **16 cas** (4 `describe`) dans `functions/rules-tests/firestore_rules.test.ts` (l'ancien « 28 tests » ne correspond à aucun décompte retrouvable).
- **CI** : job `functions` (Node 20, `npm ci` → lint + build + test) depuis PR #115 — la suite n'était validée qu'en local avant.
- **Logs** : `firebase functions:log` (stream/tail), Cloud Logging console.
- **Env** : `.env` local (test), Cloud Secret Manager (prod).
