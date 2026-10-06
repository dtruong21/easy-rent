# Functions — Index des shards

> Source d'état — index functions. Maintenu par state-keeper.

Architecture 3-couches : (1) **Firestore Rules** (`firestore.rules`) — ownership + soft-delete + immuabilité ; (2) **Cloud Functions** (Node 20 TS ; pivot FEAT-019, 2026-07-02) — mutations cross-entity + soft-delete + denorm + validation juridique ; (3) **Firestore Triggers** — `setUpdatedAt*` + `recompute*`. Région `europe-west1` (override via `runWith({region})`).

**ADR 0003 — isolation prod/staging (2026-07-25)** : Firestore existe en deux bases — `(default)` prod, `staging` staging web + build de test mobile. Les callables écrivant vers Firestore **DOIVENT** passer par le helper `await dbForRequest(request)` (`functions/src/utils/db_router.ts` ; **async** depuis 2026-09-29, `Promise<Firestore>`). Règle de routage : **web** (en-tête `Origin` non vide) → par `Origin` (`https://app.staging.baillan.com` → staging, tout le reste → prod) ; **mobile** (pas d'Origin) → par compte via `dbForLandlordUid(request.auth?.uid ?? "")` (+1 lecture par appel ; sert le build Test Lab sur staging, cf. `docs/MOBILE.md`). Le webhook RevenueCat (pas d'Origin) est routé par **`event.environment`** (OWASP-01, 2026-09-30 — `handleRevenueCatEvent` + `firestoreForEnv`) : `SANDBOX` → `staging` uniquement, `PRODUCTION` → `(default)` uniquement, autre/absent → ignoré ; **aucun repli** sur l'autre base (détail dans le shard `account`). **Interdit** : appeler `admin.firestore()` ou `getFirestore()` directement dans les callables/HTTP (sauf le routing lui-même). Crons et triggers restent sur `(default)` volontairement.

Logique standard `setUpdatedAt*` (fabrique `makeSetUpdatedAt`, `functions/src/triggers/set_updated_at.ts`) : **`onDocumentUpdated`** — se déclenche **uniquement sur update**, jamais sur create ni delete (à la création, la callable pose déjà `createdAt==updatedAt`). Garde anti-boucle : no-op si le client a déjà avancé `updatedAt` (`after.updatedAt > before.updatedAt`) ; sinon pose `updatedAt=FieldValue.serverTimestamp()` via Admin SDK. **Aucun filtre `deletedAt`** — un soft-delete est un update comme un autre. Région `europe-west1`.

> **8 variants** : 7 dans `set_updated_at.ts` (landlords, properties, tenants, leases, payments, documents, investment_scenarios) + `setUpdatedAtExpenses` dans `callable/expenses.ts` (même fabrique). **Pas** de variant `receipts` (collection immuable, sans champ `updatedAt`).
>
> ⚠️ L'état décrivait ces triggers comme `onDocumentWritten (create/update/delete)` et « ignore soft-deleted (`deletedAt==null`) » : **les deux sont faux**. Erreur systémique corrigée dans tous les shards `functions/` (elle subsistait même dans les shards réputés vérifiés au refresh #133).

## Callables (25) → shard

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
| `createCheckoutSession` | FEAT-056 (checkout Stripe 3 paliers) | account |
| `manageSubscription` | FEAT-056 (cancel/reactivate/change_plan actions) | account |
| `createScenario` | FEAT-056 (création scénario gâtée par quota) | simulator |
| `exportAccountData` | FEAT-047 (export RGPD art. 15/20) | account |
| `updateDocumentCategory` | FIX 2026-09-15 | expenses-documents |
| `finalizeChargeRegularization` | FEAT-033 (snapshot régularisation charges) | leases |
| `voidChargeStatement` | FEAT-033 | leases |
| `markChargeStatementAsSent` | FEAT-033 | leases |
| `createEtatDesLieux` | FEAT-037 | leases |

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

## Scheduled (3) → shard

| Scheduled | Cadence | Shard |
|---|---|---|
| `cleanupExpiredAnon` (BAILLAN-M1 ; purge aussi Storage `documents/{uid}/`, OWASP-04 ; **ne purge pas** les comptes dont `getUser().providerData` est non vide : leur `anonExpiresAt` est remis à `null` pour les sortir de la requête, avec une alerte `logger.error`, #209 ; `timeoutSeconds: 300`) | `0 3 * * *` **Europe/Paris** | account |
| `reconcileEntitlements` (FEAT-044, PR #114 ; un palier dont l'entitlement RevenueCat pointe vers un achat sandbox est rapporté `sandboxShadowed` → état enregistré conservé jusqu'à son échéance, #209) | `30 3 * * *` Europe/Paris | account |
| `purgeExpiredReceipts` (FEAT-045, rétention RGPD des quittances) | `0 3 * * *` Europe/Paris | payments-receipts |

> ⚠️ Décompte re-vérifié dans `functions/src/index.ts` (2026-08-12) : **25 callables (recompté 2026-09-30 : grep `export const … onCall` dans `functions/src/callable/`) + 9 triggers déployés (`setUpdatedAt` sur 8 collections + `recomputeReceiptStale`) + 1 HTTP + 3 scheduled** (recompté le 2026-10-04 sur la sortie de `firebase deploy --only functions` : 38 fonctions). `recomputeChargeRegularization` est **PLANNED V1.1 (non déployé)** — listé mais hors décompte. `setUpdatedAtReceipts` n'existe pas (receipts immuables, pas de champ `updatedAt`).
>
> Passe 2026-08-12 : table des callables corrigée (19, non 17) — manquaient `createCheckoutSession` + `manageSubscription` (FEAT-056, PR #154). Tests Vitest : 430 cas ; tests rules : 80 cas (l'ancien état disait 209 / 16, largement en retard).
>
> Passe 2026-09-05 : rajout de `createScenario` à la table des callables (était documentée en shard simulator.md mais absente de cette table maître — aucun changement au code, juste correction du shard). Refresh domaines dashboard/properties/functions : aucun changement aux callables/triggers/HTTP/scheduled, syncs visuelles seulement (MonthlyCashflow + colorKey properties).

> FEAT-043 (i18n « 5 ans » / citation loi 6/7/1989) : **no impact** sur les Cloud Functions (sync 2026-07-08).

## Ops & Infra

- **Deploy** : `npm run build && firebase deploy --only functions` (redéploie callables + triggers + HTTP + scheduled). ⚠️ Cloud Functions restent **HORS CI** (déploiement manuel délibéré, ADR 0003) — seules Firestore Rules + Indexes sont déployés par la CI.
- **Prix Stripe** (`entitlements/stripe_prices.ts`, reliquat de #138) : `readPriceTable(env)` lit `STRIPE_PRICE_<PALIER>_<PÉRIODE>` en `live`, et `…_TEST` en `test` (staging / émulateur), avec un repli offre par offre sur le paramètre canonique si le `…_TEST` est vide. `createCheckoutSession` et `manageSubscription/change_plan` choisissent `env` par l'Origin, comme la clé. Au passage en live : prix live dans les paramètres canoniques ET prix de test dans les `…_TEST` (checklist #207).
- **Secrets requis AVANT déploiement** (`firebase functions:secrets:set`) : `STRIPE_SECRET_KEY` (mode live), `STRIPE_SECRET_KEY_TEST` (mode test, servi aux origines staging/émulateur — issue #138), `REVENUECAT_WEBHOOK_AUTH`, `REVENUECAT_API_KEY`. La clé Stripe est choisie par `resolveStripeKeyOrThrow` (`utils/stripe_env.ts`) selon l'en-tête `Origin` de l'appel : une origine inconnue est refusée, et une clé dont le préfixe ne correspond pas au mode attendu est rejetée. Exceptions (2026-09-30), pour ARRÊTER une facturation : `deleteAccount` (Origin ignoré) et `manageSubscription` `cancel` **sans Origin** (apps natives ; `reactivate`/`change_plan` y restent refusés `origin_not_allowed`) passent par `resolveStripeKeyForDb`, qui choisit selon la **base routée du compte** (`staging` → clé test, `(default)` → clé live), avec les mêmes contrôles de préfixe ; `deleteAccount` lie donc `STRIPE_SECRET_KEY` **et** `STRIPE_SECRET_KEY_TEST`. Params non secrets : `STRIPE_PRICE_PRO_MONTHLY`, `STRIPE_PRICE_PRO_ANNUAL`, `STRIPE_PRICE_MAX_MONTHLY`, `STRIPE_PRICE_MAX_ANNUAL`, `STRIPE_PRICE_ULTRA_MONTHLY`, `STRIPE_PRICE_ULTRA_ANNUAL` (FEAT-056, 6 prix Stripe en mode test), `WEB_APP_BASE_URL` (défaut `https://baillan.com`).
- **Cloud Run quota** (2026-08-03, commit `8068fee`) : `setGlobalOptions({cpu: "gcf_gen1"})` bascule du défaut gen2 (1 vCPU par instance) au ratio gen1 (~0,167 vCPU/256 Mio). Quota régional « Total CPU allocation » = `nb_fonctions × maxInstances × cpu` : était 16 × 2 × 1 = 32 vCPU (dépassement), passe à 16 × 2 × 0,167 = ~5,3 vCPU. Ces callables sont E/S-bound (Firestore), pas CPU-bound. ⚠️ Ne pas réintroduire de calcul intensif sans re-audit du quota.
- **Entitlements parity** (FEAT-056) : `scripts/check-entitlements-parity.sh` (obligatoire en CI, exit 2 si défaut) valide : (1) source canonique `config/entitlements.json` bien formée ; (2) les deux miroirs (Dart + TS) sont régénérés et à jour ; (3) `sourceSha` embarqué matche le JSON ; (4) grille valide (aucun trou, palier payant a rcEntitlementId, pas de marqueur « À DÉFINIR ») ; (5) `storage.rules` max ≥ `documentMaxBytes` max (sinon plafond inatteignable en silence). Génération : `tool/gen_entitlements.dart` (Dart) + `functions/tool/gen_entitlements.mjs` (TS).
- **Tests** : Vitest — **648 cas** dans `functions/src/__tests__/` (30 fichiers, mesuré le 2026-09-30 après les correctifs OWASP), dont e2e `rental_register_free_e2e.test.ts` (createProperty→createTenant→createLease→createPayment en tier free), `revenuecat_webhook.test.ts`, `reconcile_entitlements.test.ts`, `create_checkout_session.test.ts`, `manage_subscription.test.ts`, `property_address.test.ts`, coverage plans/matrices. Rules : `npm run test:rules` (émulateurs **Firestore + Storage**) → **158 cas** (mesuré le 2026-09-30) : 124 dans `functions/rules-tests/firestore_rules.test.ts` + 34 dans `functions/rules-tests/storage_rules.test.ts` (OWASP-04/21).
- **CI** : job `functions` (Node 20, `npm ci` → lint + build + test) depuis PR #115 — la suite n'était validée qu'en local avant.
- **Logs** : `firebase functions:log` (stream/tail), Cloud Logging console.
- **Env** : `.env` local (test), Cloud Secret Manager (prod).
