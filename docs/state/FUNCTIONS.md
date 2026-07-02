# Cloud Functions et Triggers — snapshot

> Maintenu par `state-keeper`. **Source** : `functions/src/`. **Pivot** : FEAT-019 (2026-07-02) — Firebase Cloud Functions (Node.js 20 TypeScript) + Firestore triggers.

## Architecture 3-couches

1. **Firestore Rules** (`firestore.rules`) — ownership + soft-delete + immuabilité
2. **Cloud Functions** (ce document) — mutations cross-entity + soft-delete + denormalization
3. **Firestore Triggers** — setUpdatedAt + recomputeReceiptStale + propagation denorm

---

## Auth Trigger

### `handleNewUser`

> ⚠️ **INACTIVE EN PRATIQUE (ADR 0001)** : les blocking functions
> `beforeUserCreated` exigent GCIP/Identity Platform, **non activé** sur le
> projet. Cette fonction existe dans le code (encore exportée dans
> `index.ts` — incohérence relevée par bug-hunter 2026-07-02, un
> `firebase deploy --only functions` échouerait) mais **ne se déclenche
> jamais** : le provisioning du doc landlord est **100 % client**
> (`auth_repository.dart`, chemins signUp*/link*/signInAnonymously).

**Type** : Firebase Identity Platform blocking function (`beforeUserCreated`)

**Déclencheur** : Post-signup (email, Google, Apple)

**Logique** :
1. Vérifie `uid` disponible (GET /landlords/{uid} retourne 404)
2. Lit custom claims de `raw_user_meta_data` :
   - `rgpd_consent_version` (ex: 'v1-2026-07')
   - `email`, `fullName`
3. Provision doc `landlords/{uid}` :
   - `id` = uid
   - `email` = user.email (ou null anonyme)
   - `fullName` = user.displayName (ou '' anonyme)
   - `isAnonymous` = user.isAnonymous
   - `subscriptionTier` = 'free' (compte) / 'anonymous' (essai)
   - `rgpdConsentAt` = now()
   - `rgpdConsentVersion` = custom claim (fallback 'legacy-1')
   - `anonExpiresAt` = now + 14 jours (anonyme) / null (compte)
   - `createdAt` = now()
   - `deletedAt` = null
4. Status code 200 → Auth continue

**Idempotence** :
- Relance (double trigger) → doc existe → GET retourne doc → skip creation
- OR : set({merge:true}) rend création + update atomique

**Fallback si Identity Platform off** :
- Riverpod provisioning côté client après login (check doc exists, create si missing)
- Même schéma — garantit cohérence

**Fichier** : `functions/src/auth/handle_new_user.ts`

**Tests** : `functions/src/__tests__/handle_new_user.test.ts` (vitest)

---

## Firestore Triggers

### Collection Triggers (setUpdatedAt)

**Fonction exportée** : 7 variants (setUpdatedAtLandlords, setUpdatedAtProperties, etc.)

**Type** : `onDocumentWritten` (create, update, delete)

**Logique** :
1. Déclenchement : change.after (post-write)
2. Vérifie deletedAt != null (soft-delete ignore)
3. Maj `updatedAt = now()` via Admin SDK
4. Idempotent (idempotence key = docId)

**Collections couvertes** :
- landlords
- properties
- tenants
- leases
- payments
- documents
- investment_scenarios

**Fichier** : `functions/src/triggers/set_updated_at.ts`

### `recomputeReceiptStale`

**Type** : `onDocumentWritten` (payments collection)

**Déclencheur** : Create/update/delete payment

**Logique** :
1. Fetch ALL receipts liées à ce lease
2. Pour chaque receipt :
   - Check si payment base-amt change invalidate receipt
   - Maj `isStale = true`
   - CF `generateReceipt` client rejoue si stale flag true
3. Admin SDK update batch

**Note** : Quittances elles-mêmes immuables (pas de soft-delete) — `isStale` just flags recompute.

**Fichier** : `functions/src/triggers/recompute_receipt_stale.ts`

---

## Callable Cloud Functions

### Lease Management

#### `createLease`

**Type** : Callable (client invoke)

**Signature** :
```typescript
export const createLease = onCall(async (request) => {
  const data = request.data;
  // { landlordId, propertyId, tenantId, status, startDate, endDate, monthlyRent, charges }
});
```

**Validations** :
1. Auth check : `request.auth.uid == data.landlordId`
2. FK validation : GET properties/{propertyId}, tenants/{tenantId}
3. Ownership check : properties.landlordId == tenantId.landlordId == landlordId
4. Date logic : startDate <= endDate
5. Status inference : compute from startDate/endDate vs now()

**Mutations** :
1. CREATE leases/{id} (Admin SDK, bypass rules)
2. INCREMENT properties/{propertyId}.activeLeaseCount
3. INCREMENT tenants/{tenantId}.activeLeaseCount

**Retour** : `{leaseId: string}`

**Erreurs** :
- PERMISSION_DENIED : landlordId mismatch
- NOT_FOUND : propertyId ou tenantId inexistant
- INVALID_ARGUMENT : date logic failure

**Fichier** : `functions/src/callable/lease_payment.ts`

#### `updateLease`

**Type** : Callable (client invoke)

**Logique** :
1. Fetch current lease
2. Validate ownership (lease.landlordId == auth.uid)
3. Recalc status si startDate/endDate change
4. Admin SDK update (bypass rules soft-delete immutables)
5. Return `{success: true}`

**Fichier** : `functions/src/callable/lease_payment.ts`

---

### Payment Management

#### `createPayment`

**Type** : Callable (client invoke)

**Signature** :
```typescript
export const createPayment = onCall(async (request) => {
  const data = request.data;
  // { landlordId, leaseId, amount, paidAt, periodStart, periodEnd }
});
```

**Validations** :
1. Auth + FK + ownership (via lease)
2. Amount > 0 sanity check
3. periodStart <= periodEnd

**Mutations** :
1. CREATE payments/{id}
2. Trigger Cloud Function `generateReceipt` (async)

**Retour** : `{paymentId: string}`

**Fichier** : `functions/src/callable/lease_payment.ts`

#### `updatePayment`

**Type** : Callable

**Logique** : Rare — idempotent no-op si amount/period unchanged.

**Fichier** : `functions/src/callable/lease_payment.ts`

---

### Receipt Management

#### `generateReceipt`

**Type** : Callable (client invoke OR triggered post-payment)

**Signature** :
```typescript
export const generateReceipt = onCall(async (request) => {
  const data = request.data;
  // { leaseId, paymentId (optional — si client appel direct) }
});
```

**Logique** :
1. Fetch lease, payment, landlord (auth check)
2. Generate PDF via `pdf` library
3. Upload to Firebase Storage `/receipts/{leaseId}/{receiptId}.pdf`
4. CREATE receipts/{id} doc :
   - amount, periodStart/End
   - pdfUrl = signed URL (5 min)
   - isVoided = false
   - isStale = false
   - createdAt = now()
5. Retour : `{receiptId: string, pdfUrl: string}`

**Trigger path** : payment creation → CF `generateReceipt` auto-invoke (async)

**Client path** : LeaseReceiptsPage "Générer" button → invoke + show PDF

**Fichier** : `functions/src/callable/receipts.ts`

#### `voidReceipt`

**Type** : Callable (client invoke)

**Logique** :
1. Fetch receipt + linked payment
2. Soft-delete payment (set deletedAt)
3. Mark receipt isVoided = true
4. Auto-generateReceipt remplacement (nouveau doc)

**Retour** : `{newReceiptId: string}`

**Fichier** : `functions/src/callable/receipts.ts`

#### `markReceiptAsSent`

**Type** : Callable (client invoke)

**Logique** :
1. Fetch receipt
2. Update sentAt = now()
3. Audit trail (pas de mail envoyé — Web Share API côté client)

**Retour** : `{success: true}`

**Fichier** : `functions/src/callable/receipts.ts`

---

### Document Management

#### `createDocument`

**Type** : Callable (client invoke)

**Signature** :
```typescript
export const createDocument = onCall(async (request) => {
  const data = request.data;
  // { leaseId (optional), category, title, fileBase64, mimeType }
});
```

**Validations** :
1. Auth + leaseId ownership (if present)
2. MIME whitelist (PDF, JPEG, PNG)
3. File size cap (50 MB)

**Mutations** :
1. Upload fileBase64 to Storage `/documents/{leaseId}/{docId}.{ext}`
2. Compute legalHold from category :
   - 'lease' → legalHold = true (rétention 3 ans)
   - 'inventory' → legalHold = true (rétention 7 ans)
   - 'other' → legalHold = false (soft-delete autorisé)
3. CREATE documents/{id} doc

**Retour** : `{documentId: string, storageUrl: string}`

**Fichier** : `functions/src/callable/documents.ts`

#### `getDocumentDownloadUrl`

**Type** : Callable (client invoke)

**Logique** :
1. Fetch document
2. Gen signed URL (5 min expiry)
3. Return URL

**Retour** : `{downloadUrl: string}`

**Fichier** : `functions/src/callable/documents.ts`

---

### Soft Delete

#### `softDeleteEntity`

**Type** : Callable (universal soft-delete)

**Signature** :
```typescript
export const softDeleteEntity = onCall(async (request) => {
  const data = request.data;
  // { collection, docId }
});
```

**Logique** :
1. Route par collection :
   - `landlords` → check no active leases
   - `properties` → check no active leases
   - `tenants` → check no active leases
   - `leases` → soft-delete OK
   - `payments` → soft-delete OK
   - `receipts` → REFUSE (immutable)
   - `documents` → check legalHold (refuse si true)
2. Update deletedAt = now()
3. Decrement activeLeaseCount (properties, tenants)

**Erreurs** :
- FAILED_PRECONDITION : legalHold true / active leases exist

**Retour** : `{success: true}`

**Fichier** : `functions/src/callable/soft_delete.ts`

---

### Upgrade Flow

#### `finalizeAnonymousUpgrade`

**Type** : Callable (client invoke)

**Déclencheur** : Anonyme clique "Créer un compte" après essai

**Logique** :
1. Fetch current user doc (anonyme)
2. Validate email non-existant (aucun autre user same email)
3. Transact :
   - Update `landlords/{uid}` :
     - isAnonymous = false
     - subscriptionTier = 'free'
     - rgpdConsentAt = now() (signup consent)
     - rgpdConsentVersion = custom claim version
     - email, fullName from request.data
     - anonExpiresAt = null
   - Preserve investment_scenarios (car landlordId constant = uid)
4. Return `{success: true}`

**Safety** : Investment scenarios restent accessibles (pas de migration).

**Fichier** : `functions/src/callable/finalize_anonymous_upgrade.ts`

**Tests** : `functions/src/__tests__/finalize_anonymous_upgrade.test.ts`

---

## Scheduled Functions (Cron)

### `cleanupExpiredAnon`

**Type** : Cloud Scheduler + Cloud Function

**Schedule** : Daily 2 AM UTC (config via `gcloud` ou console)

**Logique** :
1. Query `landlords` where isAnonymous==true && anonExpiresAt < now()
2. Batch soft-delete :
   - Soft-delete ALL leases/payments/receipts (landlordId)
   - Soft-delete properties, tenants, documents
   - Soft-delete investment_scenarios
   - Delete landlords/{uid} doc (vrai delete, pas soft — retention inutile anon)
3. Log count deleted
4. Idempotent (deletedAt check)

**Fichier** : `functions/src/scheduled/cleanup_expired_anon.ts`

**Logs** : Cloud Logging, queryable via `firebase functions:log`

---

## Helper Utilities

**Fichier** : `functions/src/utils/callable_helpers.ts`

| Helper | Signature | Usage |
|---|---|---|
| `validateOwnership()` | `(auth.uid, landlordId) → void` | Auth check (throw if mismatch) |
| `validateFK()` | `(db, collection, docId, expected) → void` | FK validation |
| `validateImmutables()` | `(oldData, newData) → void` | Immutable fields check |
| `softDeleteCollection()` | `(db, collection, docId) → Promise<void>` | Generic soft-delete |
| `incrementCounter()` | `(db, path, field, delta) → Promise<void>` | Denorm counter update |

---

## Test Coverage

**Framework** : Vitest (replace Jest)

**Files** : `functions/src/__tests__/*.test.ts`

| Test | Coverage |
|---|---|
| `handle_new_user.test.ts` | Provision doc creation, custom claims parsing |
| `finalize_anonymous_upgrade.test.ts` | Upgrade logic, email validation, investment_scenarios preservation |
| _(more TBD)_ | Payment creation, receipt generation, soft-delete validation |

**Run** :
```bash
npm run test          # One-shot
npm run test:watch   # Watch mode
```

---

## Deployment

**Command** : `firebase deploy --only functions`

**Output** : Tous les callables + triggers + scheduled redéployés (source ~40 KB compiled lib/)

**Région** : europe-west1 (default, override per-function via `runWith()`)

**Logs** : `firebase functions:log` (stream or tail 20 min)

---

## Known Issues + Workarounds

| Issue | Status | Note |
|---|---|---|
| **Payment creation idempotence** | ✅ Fixed | Receipt generation retry → no-op if exists |
| **Soft-delete cascade** | ✅ Designed | softDeleteEntity handles all cascades (no orphans) |
| **Stale receipt recompute** | ✅ Implemented | recomputeReceiptStale CF trigger post-payment |
