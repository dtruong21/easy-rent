# Cloud Functions et Triggers — snapshot

> Maintenu par `state-keeper`. **Source** : `functions/src/`. **Dernière sync** : 2026-07-05 (FEAT-036 + FEAT-041 V1 merged, `createExpense`, `updateExpense`, `setUpdatedAtExpenses`; `createDocument` v2 FEAT-041b). **Pivot** : FEAT-019 (2026-07-02) — Firebase Cloud Functions (Node.js 20 TypeScript) + Firestore triggers.

## Architecture 3-couches

1. **Firestore Rules** (`firestore.rules`) — ownership + soft-delete + immuabilité
2. **Cloud Functions** (ce document) — mutations cross-entity + soft-delete + denormalization + juridique validation
3. **Firestore Triggers** — setUpdatedAt + recomputeReceiptStale + recomputeChargeRegularization (FEAT-041c, planné)

---

## Auth Trigger (ADR 0001 : GCIP désactivé)

### `handleNewUser` — ⚠️ SUPPRIMÉ (FEAT-030, commit 90eb86f)

**Status** : REMOVED (2026-07-05)

**Raison** : ADR 0001 — GCIP/Identity Platform **non activé** sur le projet. Blocking function `beforeUserCreated` n'existait qu'en code.

**Provisioning 100 % client** (`auth_repository.dart`, Riverpod) :
- Chemins : `signUpWithEmail`, `linkGoogle`, `linkApple`, `signInAnonymously`
- Crée `landlords/{uid}` doc GET-then-create (idempotent)
- Même schéma garantissant cohérence

---

## Firestore Triggers

### Collection Triggers (setUpdatedAt)

**Fonction exportée** : 8 variants (landlords, properties, tenants, leases, payments, documents, **expenses FEAT-041**, investment_scenarios)

**Type** : `onDocumentWritten` (create, update, delete)

**Logique** :
1. Déclenchement post-write : `change.after` avec timestamp serveur
2. Vérifie `deletedAt == null` (ignore soft-deleted)
3. Maj `updatedAt = FieldValue.serverTimestamp()` via Admin SDK
4. Idempotent (clé = docId + timestamp)

**Collections couvertes** :
- landlords
- properties
- tenants
- leases
- payments
- documents
- **expenses** (NEW FEAT-041a)
- investment_scenarios

**Fichier** : `functions/src/triggers/set_updated_at.ts`

**Exports** (8 variants) :
- `setUpdatedAtLandlords`
- `setUpdatedAtProperties`
- `setUpdatedAtTenants`
- `setUpdatedAtLeases`
- `setUpdatedAtPayments`
- `setUpdatedAtDocuments`
- `setUpdatedAtExpenses` (NEW)
- `setUpdatedAtInvestmentScenarios`

### `recomputeReceiptStale`

**Type** : `onDocumentWritten` (payments collection)

**Déclencheur** : Create/update/delete payment

**Logique** :
1. Fetch ALL receipts liées au lease
2. Pour chaque receipt :
   - Si payment.amountCents change → invalidate
   - Maj `isStale = true`
   - CF client (`generateReceipt`) rejoue si stale flag==true
3. Admin SDK batch update

**Fichier** : `functions/src/triggers/recompute_receipt_stale.ts`

**Note** : Quittances immuables (pas de soft-delete) — `isStale` flag seulement.

### `recomputeChargeRegularization` (FEAT-041c)

**Status** : Planné (pas encore déployé, attendre V1.1)

**Type** : `onDocumentWritten` (expenses collection)

**Déclencheur** : Create/update/delete expense

**Logique** (planifiée) :
1. Si expense.category=='recoverable' && expense.leaseId → query lease
2. Alimente `lease.chargeRegularizationFeed` subcollection (draft)
3. Utilisé par FEAT-041c : aggregation charges mensuelles → calcul provision + avis PDF

---

## Callable Cloud Functions (27 total)

### 🔒 Lease Management (FEAT-005, FEAT-036)

#### `createLease`

**Type** : Callable (client invoke, isFullyAuthed only)

**Signature** :
```typescript
export const createLease = onCall(async (request) => {
  const uid = request.auth.uid;
  const data = {
    propertyId, tenantId, rentAmountCents, chargesAmountCents,
    nonRecoverableChargesCents (NEW FEAT-036),
    startDate, endDate, status, leaseType, paymentDay, paymentMethod,
    depositAmountCents, irlIndexValue, irlQuarterRef, agencyFeesCents,
    solidarityClause, entryInventoryDone
  };
});
```

**Validations** :
1. Auth : `uid` présent (isFullyAuthed via RLS)
2. FK validation : GET properties/{propertyId}, tenants/{tenantId}
3. Ownership : properties.landlordId == tenants.landlordId == uid
4. **FEAT-036** : nonRecoverableChargesCents validé (≥ 0, pas de total constraint)
5. Date logic : startDate <= endDate
6. Status inference : 'active' | 'terminated' | 'archived'

**Mutations** (transactionnel) :
1. CREATE leases/{id} avec snapshot denorm (propertyName, tenantFirstName/LastName, etc.)
2. **FEAT-036** : persiste chargesAmountCents (récupérable) + nonRecoverableChargesCents (informatif)
3. Si status=='active' : INCREMENT properties/{propertyId}.activeLeaseCount
4. Si status=='active' : INCREMENT tenants/{tenantId}.activeLeaseCount

**Retour** : `{leaseId: string}`

**Erreurs** : PERMISSION_DENIED, NOT_FOUND, INVALID_ARGUMENT

**Fichier** : `functions/src/callable/lease_payment.ts`

#### `updateLease`

**Type** : Callable

**Mutable fields** : rentAmountCents, chargesAmountCents, **nonRecoverableChargesCents (FEAT-036)**, endDate, status, leaseType, depositAmountCents, paymentDay, paymentMethod, irlIndexValue, irlQuarterRef, agencyFeesCents, solidarityClause, entryInventoryDone

**Logique** :
1. Fetch current lease + validate ownership
2. **FEAT-036** : nonRecoverableChargesCents borné (≥ 0), validation cross-entity + re-validation charges
3. Si status change (active → terminated) : DECREMENT activeLeaseCount (CF soft-delete + trigger)
4. Transact : Admin SDK update + denorm re-snapshot propertyName
5. Return `{updated: true}`

**Fichier** : `functions/src/callable/lease_payment.ts`

---

### 💰 Payment Management (FEAT-006)

#### `createPayment`

**Type** : Callable (client invoke)

**Signature** :
```typescript
export const createPayment = onCall(async (request) => {
  const data = {
    leaseId, amountCents, paidDate, paymentMethod,
    notes (NEW FEAT-029 — motif libre, max 500 chars)
  };
});
```

**Validations** :
1. Auth + FK + ownership (via lease)
2. amountCents > 0
3. notes.length <= 500 (FEAT-029)

**Mutations** (transactionnel) :
1. CREATE payments/{id} avec snapshot denorm
2. Trigger recomputeReceiptStale (invalidate liens receipts)

**Retour** : `{paymentId: string}`

**Trigger** : Auto-invoke `generateReceipt` (async post-write, FEAT-007)

**Fichier** : `functions/src/callable/lease_payment.ts`

#### `updatePayment`

**Type** : Callable

**Logique** : Rare — idempotent no-op si amount/period unchanged. Trigger `recomputeReceiptStale` si amountCents change.

**Fichier** : `functions/src/callable/lease_payment.ts`

---

### 📄 Receipt Management (FEAT-007)

#### `generateReceipt`

**Type** : Callable (client invoke OR triggered post-payment)

**Signature** :
```typescript
export const generateReceipt = onCall(async (request) => {
  const data = {
    leaseId, paymentId (optional — direct call ou post-payment trigger)
  };
});
```

**Logique** :
1. Fetch lease, payment, landlord (auth check)
2. Generate PDF via `pdf` + `printing` (quittance loi 6 juillet 1989)
3. Upload → Firebase Storage `/receipts/{leaseId}/{receiptId}.pdf`
4. CREATE receipts/{id} doc :
   - amountCents, periodStart/End, receiptNumber, receiptDate
   - status = 'generated'
   - fileUrl = signed URL (5 min, auto-refresh @ access)
   - createdAt = now(), updatedAt = now()
   - deletedAt = null
5. Retour : `{receiptId: string, pdfUrl: string}`

**Trigger path** : payment creation → CF `generateReceipt` auto-invoke (async)

**Client path** : LeaseReceiptsPage "Générer" button → invoke + show PDF

**Fichier** : `functions/src/callable/receipts.ts`

**Note** : Quittance immuable (art. L145-40, loi 6 juillet 1989 — rétention 5 ans).

#### `voidReceipt`

**Type** : Callable

**Logique** :
1. Fetch receipt + linked payment
2. Soft-delete payment (set deletedAt = now())
3. Mark receipt status |= 'voided'
4. Auto-generateReceipt remplacement (nouveau doc, relinking payment.id optionnel)

**Retour** : `{newReceiptId: string}`

**Fichier** : `functions/src/callable/receipts.ts`

#### `markReceiptAsSent`

**Type** : Callable

**Logique** :
1. Fetch receipt
2. Update status |= 'sent'
3. Audit trail (pas de mail — Web Share API côté client)

**Retour** : `{success: true}`

**Fichier** : `functions/src/callable/receipts.ts`

---

### 📎 Document Management (FEAT-008, FEAT-041b)

#### `createDocument` (v2, FEAT-041b)

**Type** : Callable (client invoke)

**Signature** :
```typescript
export const createDocument = onCall(async (request) => {
  const data = {
    leaseId (optional, nullable),
    propertyId (optional, for context FEAT-041b),
    expenseId (optional, FEAT-041b — lien dépense),
    category,  // 'lease_scan' | 'insurance' | 'expense_receipt' (NEW) | 'other'
    fileName, fileBase64, mimeType
  };
});
```

**Validations** :
1. Auth + ownership
2. Si leaseId : FK + ownership validation
3. Si expenseId : FK + ownership validation (FEAT-041b)
4. MIME whitelist : PDF, JPEG, PNG
5. File size cap : 25 MB

**Mutations** :
1. Upload fileBase64 → Storage `/documents/{landlordId}/{docId}.{ext}`
2. **Derive legalHold from category** (serveur, immuable) :
   - `lease_scan` → legalHold=true (rétention 3 ans)
   - `insurance` → legalHold=true (rétention 3 ans)
   - `expense_receipt` → legalHold=false (FEAT-041b, soft-delete autorisé)
   - `other` → legalHold=false
3. CREATE documents/{id} doc
4. **FEAT-041b** : Si category=='expense_receipt' + expenseId → créer lien bilatéral

**Retour** : `{documentId: string, storageUrl: string}`

**Fichier** : `functions/src/callable/documents.ts`

**Note** : `legalHold` dérivée immuable empêche soft-delete si true (garde-fou légal).

#### `softDeleteDocument`

**Type** : Callable (via `softDeleteEntity`, voir ci-dessous)

**Logique** :
1. Fetch document
2. Si legalHold==true → FAILED_PRECONDITION error (immutable)
3. Sinon : set deletedAt = now()

**Retour** : `{success: true}`

**Fichier** : `functions/src/callable/soft_delete.ts`

---

### 💸 Expense Management (FEAT-041a, FEAT-041b, FEAT-041c)

#### `createExpense` (NEW FEAT-041a)

**Type** : Callable (client invoke, isFullyAuthed only)

**Signature** :
```typescript
export const createExpense = onCall(async (request) => {
  const uid = request.auth.uid;
  const data = {
    propertyId,          // obligatoire
    leaseId,             // optionnel
    expenseId,           // optionnel (FEAT-041b)
    amountCents,         // ≥ 1
    expenseDate,         // timestamp
    nature,              // enum ExpenseNature (obligatoire)
    category,            // optionnel (override si locked:false)
    periodStart, periodEnd,  // obligatoires si category=='recoverable'
    periodYear,          // dérivé de periodStart ou expenseDate
    notes                // optionnel, ≤ 2000 chars
  };
});
```

**Validations** (juridique, décret 87-713) :
1. Auth : uid présent (isFullyAuthed via RLS)
2. FK validation : propertyId (obligatoire), leaseId/documentId (optionnel si fournis)
3. Ownership : tous les FK doivent appartenir au même landlord
4. **Nature validation** : nature in EXPENSE_NATURES (enum)
5. **Category dérivation** : 
   - Récupère `NATURE_DEFAULT_CATEGORY[nature]` → {category, locked}
   - Si requestedCategory fourni ET nature.locked==true → FAILED_PRECONDITION (overridden interdite)
   - Sinon : dérive category + flag categoryOverridden
6. **Recoverable constraint** : Si category=='recoverable' → periodStart && periodEnd requis, periodEnd > periodStart
7. **Period year dérivation** : periodYear fourni > periodStart année > expenseDate année

**Mutations** (transactionnel) :
1. CREATE expenses/{id} :
   - Snapshot dénorm : propertyName (properties.name), tenantLastName (leases.tenantLastName si leaseId)
   - nature, category (dérivée), categoryOverridden (trace)
   - periodYear, periodStart/End (si recoverable)
   - documentId, notes
   - createdAt/updatedAt = now(), deletedAt = null
2. Trigger setUpdatedAtExpenses (auto)
3. Trigger recomputeChargeRegularization (FEAT-041c, planné)

**Retour** : `{expenseId: string, category: string, categoryOverridden: boolean}`

**Erreurs** :
- PERMISSION_DENIED : landlordId mismatch
- NOT_FOUND : propertyId/leaseId/documentId inexistant
- INVALID_ARGUMENT : nature/category/period invalid
- FAILED_PRECONDITION : category_locked_for_nature

**Fichier** : `functions/src/callable/expenses.ts`

**Note** : `NATURE_DEFAULT_CATEGORY` est source unique de vérité juridique — répliquée en enum Dart `ExpenseNature` côté client pour présélection UI uniquement.

#### `updateExpense` (NEW FEAT-041a)

**Type** : Callable

**Immutable fields** : propertyId, leaseId, landlordId, createdAt, deletedAt

**Mutable fields** : amountCents, expenseDate, nature, category, periodStart, periodEnd, periodYear, documentId, notes

**Logique** :
1. Fetch current expense + validate ownership
2. **Re-dérivation category** si nature ou category changent :
   - Applique verrouillage NATURE_DEFAULT_CATEGORY[nature].locked
   - Throw FAILED_PRECONDITION si override interdit
3. **Recoverable constraint** : Si nouvelle category=='recoverable' → validate periodStart/End
4. **Period year re-dérivation** : Si periodStart/expenseDate changent
5. **Property name re-snapshot** : Rafraîchie à chaque update (pattern `payments`)
6. Transact : Admin SDK update + denorm refresh
7. Return `{updated: true}`

**Fichier** : `functions/src/callable/expenses.ts`

#### `setUpdatedAtExpenses` (Trigger)

**Type** : `onDocumentWritten` (expenses collection)

**Logique** : Identique aux autres `setUpdatedAt*` triggers.

**Fichier** : `functions/src/callable/expenses.ts` (exported + re-exported par index.ts)

---

### 🗑️ Soft Delete (unifié)

#### `softDeleteEntity`

**Type** : Callable (universal soft-delete)

**Signature** :
```typescript
export const softDeleteEntity = onCall(async (request) => {
  const data = { collection, docId };
});
```

**Logique** par collection :
1. **landlords** → Vérifier no active leases, soft-delete OK
2. **properties** → Vérifier no active leases, soft-delete OK
3. **tenants** → Vérifier no active leases, soft-delete OK
4. **leases** → Soft-delete OK, trigger activeLeaseCount decrement
5. **payments** → Soft-delete OK, trigger recomputeReceiptStale
6. **receipts** → **REFUSE** (immuable, loi 6 juillet 1989)
7. **documents** → Check legalHold (refuse si true), soft-delete OK
8. **expenses** → Soft-delete OK (FEAT-041)
9. **investment_scenarios** → Soft-delete OK

**Mutations** :
1. Update deletedAt = now()
2. Si collection in ['properties', 'tenants'] && status=='active' → DECREMENT activeLeaseCount
3. Idempotent (deletedAt check)

**Erreurs** :
- FAILED_PRECONDITION : legalHold==true / active leases exist / receipts
- NOT_FOUND : entity inexistant
- PERMISSION_DENIED : landlordId mismatch

**Retour** : `{success: true}`

**Fichier** : `functions/src/callable/soft_delete.ts`

---

### 🔐 Anonymous Upgrade (BAILLAN-M1, FEAT-019)

#### `finalizeAnonymousUpgrade`

**Type** : Callable (client invoke)

**Déclencheur** : Anonyme clique "Créer un compte" après essai 14j

**Logique** :
1. Fetch current user doc (doit être anonyme)
2. Validate email non-existant (aucun autre user same email)
3. Transact (Admin SDK) :
   - Update `landlords/{uid}` :
     - isAnonymous = false
     - subscriptionTier = 'free'
     - rgpdConsentAt = now() (signup consent)
     - rgpdConsentVersion = v2-2026-07 (current)
     - email, fullName from request.data
     - anonExpiresAt = null
   - Preserve investment_scenarios (landlordId == uid constant)
4. Return `{success: true}`

**Safety** : Investment scenarios restent accessibles (pas de migration).

**Fichier** : `functions/src/callable/finalize_anonymous_upgrade.ts`

**Tests** : `functions/src/__tests__/finalize_anonymous_upgrade.test.ts`

---

## Scheduled Functions (Cron)

### `cleanupExpiredAnon` (BAILLAN-M1)

**Type** : Cloud Scheduler + Cloud Function

**Schedule** : Daily 2 AM UTC (configurable via `gcloud` ou console Firebase)

**Logique** :
1. Query `landlords` where isAnonymous==true && anonExpiresAt < now()
2. Batch soft-delete pour chaque anonyme expiré :
   - Soft-delete ALL leases/payments/receipts (landlordId)
   - Soft-delete properties, tenants, documents, expenses
   - Soft-delete investment_scenarios
   - Hard-delete `landlords/{uid}` doc (vrai delete, pas soft — rétention inutile anon)
3. Log count deleted (Cloud Logging)
4. Idempotent (deletedAt check)

**Fichier** : `functions/src/scheduled/cleanup_expired_anon.ts`

**Logs** : `firebase functions:log`, queryable via Cloud Logging console

---

## Helper Utilities

**Fichier** : `functions/src/utils/callable_helpers.ts`

| Helper | Signature | Usage |
|---|---|---|
| `requireAuthUid()` | `(request) → string` | Extract + validate auth UID |
| `requireString()` | `(value, name) → string` | Require non-empty string |
| `requireInt()` | `(value, name, {min, max}) → number` | Require integer with bounds |
| `optionalString()` | `(value, name) → string \| null` | Optional string or null |
| `optionalInt()` | `(value, name, bounds) → number \| null` | Optional integer |
| `optionalTimestamp()` | `(value, name) → Timestamp \| null` | Optional Firebase timestamp |
| `toTimestamp()` | `(value, name) → Timestamp` | Coerce to Firestore timestamp |
| `asBag()` | `(data) → Record<string, any>` | Safely cast to object bag |
| `dataOrFail()` | `(snap, entity) → any` | Extract doc data or throw NOT_FOUND |
| `assertOwnedAndActive()` | `(doc, uid, entity) → void` | Check ownership + isActive |

---

## Test Coverage

**Framework** : Vitest (replace Jest)

**Files** : `functions/src/__tests__/*.test.ts`

| Test | Coverage |
|---|---|
| `finalize_anonymous_upgrade.test.ts` | Upgrade logic, email validation, investment_scenarios preservation |
| _(more TBD)_ | Expense creation (nature/category derivation), payment creation, receipt generation, soft-delete |

**Run** :
```bash
npm run build       # TypeScript compilation
npm run test        # One-shot vitest
npm run test:watch # Watch mode
```

---

## Deployment

**Command** : 
```bash
npm run build
firebase deploy --only functions
```

**Output** : Tous les callables + triggers + scheduled redéployés (source ~50 KB compiled)

**Région** : europe-west1 (default, override per-function via `runWith({region: '…'})`)

**Logs** : `firebase functions:log` (stream or tail last 20 minutes)

**Env vars** : `.env` local (test), Cloud Secret Manager (prod)

---

## Summary — Callables by Feature

| Feature | Callables | Triggers | Status |
|---|---|---|---|
| **FEAT-005** (Baux) | createLease, updateLease | setUpdatedAtLeases | ✅ DONE |
| **FEAT-006** (Paiements) | createPayment, updatePayment | setUpdatedAtPayments, recomputeReceiptStale | ✅ DONE |
| **FEAT-007** (Quittances) | generateReceipt, voidReceipt, markReceiptAsSent | setUpdatedAtReceipts | ✅ DONE |
| **FEAT-008** (Documents) | createDocument, softDeleteDocument | setUpdatedAtDocuments | ✅ DONE (v2 FEAT-041b) |
| **FEAT-025** (Support) | — | — | ✅ DONE (create-only rules) |
| **FEAT-029** (Motif) | — (payment.notes field) | — | ✅ DONE |
| **FEAT-036** (Charges) | createLease, updateLease (nonRecoverableChargesCents) | — | ✅ DONE |
| **FEAT-041a** (Dépenses CRUD) | **createExpense, updateExpense** | **setUpdatedAtExpenses** | ✅ DONE |
| **FEAT-041b** (Documents v2) | **createDocument v2** (expenseId, category=expense_receipt, legalHold) | — | ✅ DONE |
| **FEAT-041c** (Régularisation) | — | **recomputeChargeRegularization** (planned) | 📋 PLANNED V1.1 |
