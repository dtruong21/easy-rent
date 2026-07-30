# Functions — Expenses & Documents

> Source d'état — expenses-documents. Maintenu par state-keeper.

Dépenses (FEAT-041a) + documents (FEAT-008, v2 FEAT-041b). Fichiers : `functions/src/callable/{expenses,documents,soft_delete}.ts`.

## Callables — Documents

**ADR 0003** : tous les callables écrivant Firestore utilisent `dbForRequest(request)` pour router vers la base prod ou staging par Origin.

### `createDocument` (v2, FEAT-008/FEAT-041b/FEAT-044)
Client invoke. **⚠️ Section corrigée le 2026-07-21 — l'état décrivait une signature et des catégories qui n'existent pas dans le code.**
- **Flow réel** : le client **uploade d'abord** dans Storage (SDK Firebase, Storage Rules `uid == landlordId` dans le path), **puis** appelle ce callable avec le `storagePath`. Il n'y a **pas** de transfert base64 par la callable.
- **Params** : `leaseId` (opt), `propertyId` (opt) — **au moins un des deux requis** ; `category`, `filename`, `storagePath`, `mimeType`, `sizeBytes`. Il n'existe **pas** de param `expenseId` (le lien se fait dans l'autre sens : `expenses.documentId`).
- **Catégories réelles** : `bail_signe` \| `etat_des_lieux` \| `attestation_assurance` \| `quittance_scannee` \| `expense_receipt` \| `autre`. (L'état listait `lease_scan`/`insurance`/`other` — inexistantes.)
- **Validations** : auth ; ownership du bail et/ou du bien + non soft-deleted ; si les deux fournis → `lease.propertyId == propertyId` sinon `lease_property_mismatch` ; MIME ∈ {PDF, JPEG, PNG, **WEBP**} ; `sizeBytes` ∈ [1, **10 MiB**] (et non 25 MB) ; `storagePath` doit commencer par `documents/{uid}/` ; **le fichier doit exister dans Storage** sinon `failed-precondition` (empêche l'enregistrement d'un doc fantôme).
- **Gate free/Pro (FEAT-044, PR #120)** : `assertDocumentQuota` s'exécute **AVANT** tout travail coûteux → `resource-exhausted` / `document_limit_reached`. Plafond de documents **actifs** : anonyme 0 · free **10** · paid illimité. **Comptage live** (`count()` where `deletedAt == null`), pas de compteur dénormalisé — le soft-delete étant universel, il n'y aurait rien à décrémenter. C'est la SOURCE DE VÉRITÉ ; l'UI (`SubscriptionTier.documentLimit`) n'est qu'un miroir. Landlord absent → `not-found` (fail-closed).
- **`legalHold` dérivé serveur** (immuable) = `category ∈ {bail_signe, etat_des_lieux, expense_receipt}`. ⚠️ **`expense_receipt` EST sous rétention** (10 ans, comptable) — l'état affirmait l'inverse (« soft-delete autorisé ») ; `attestation_assurance` ne l'est **pas** (l'état disait `insurance`→true).
- **Retour** : `{documentId, legalHold}` (et non `{documentId, storageUrl}`). Fichier `documents.ts`.

### `getDocumentDownloadUrl` (FEAT-008)
Client invoke. Génère une **URL signée court-terme (5 min)** pour télécharger le fichier. Ownership check (`landlordId==uid`) + refus si `deletedAt!=null`. **Retour** : `{downloadUrl, downloadUrlExpiresAt}`. Fichier `documents.ts`.

### Soft-delete de documents — via `softDeleteEntity('documents')`
Pas de callable dédié (`softDeleteDocument` n'existe pas) : le soft-delete passe par le `softDeleteEntity` universel (spec canonique → account). Fetch document ; si `legalHold==true` → FAILED_PRECONDITION (immutable) ; sinon `deletedAt=now()`. **Retour** : `{success:true}`. Fichier `soft_delete.ts`.

## Callables — Expenses

### `createExpense` (FEAT-041a)
Client invoke, isFullyAuthed only. Validation juridique **décret 87-713**.
- **Params** : `propertyId` (**obligatoire**), `leaseId` (opt), `expenseId` (opt, FEAT-041b), `amountCents` (≥1), `expenseDate` (timestamp), `nature` (enum `ExpenseNature`, **obligatoire**), `category` (opt override si `locked:false`), `periodStart/periodEnd` (**obligatoires si** `category=='recoverable'`), `periodYear` (dérivé), `notes` (opt, ≤2000 chars).
- **Validations** : auth uid ; FK `propertyId` obligatoire + `leaseId`/`documentId` opt ; ownership même landlord ; `nature in EXPENSE_NATURES` ; **category dérivation** via `NATURE_DEFAULT_CATEGORY[nature]`→`{category,locked}` — si `requestedCategory` fourni ET `nature.locked==true` → FAILED_PRECONDITION (override interdit), sinon dérive + flag `categoryOverridden` ; **recoverable** → `periodStart && periodEnd` requis, `periodEnd > periodStart` ; **periodYear** = fourni > année `periodStart` > année `expenseDate`.
- **Mutations** (transact) : CREATE `expenses/{id}` snapshot denorm (`propertyName`=properties.name, `tenantLastName`=leases.tenantLastName si leaseId), `nature`, `category` dérivée, `categoryOverridden` (trace), `periodYear`, `periodStart/End` (si recoverable), `documentId`, `notes`, timestamps ; trigger `setUpdatedAtExpenses` ; trigger `recomputeChargeRegularization` (FEAT-041c planné, voir leases).
- **Retour** : `{expenseId, category, categoryOverridden}`. **Erreurs** : PERMISSION_DENIED (landlordId mismatch), NOT_FOUND, INVALID_ARGUMENT, FAILED_PRECONDITION (`category_locked_for_nature`).
- **Note** : `NATURE_DEFAULT_CATEGORY` = source unique de vérité juridique ; répliquée en enum Dart `ExpenseNature` côté client (présélection UI uniquement). Fichier `expenses.ts`.

### `updateExpense` (FEAT-041a)
- **Immutable** : `propertyId, leaseId, landlordId, createdAt, deletedAt`.
- **Mutable** : `amountCents, expenseDate, nature, category, periodStart, periodEnd, periodYear, documentId, notes`.
- **Logique** : fetch + ownership ; re-dérivation category si `nature`/`category` changent (verrou `NATURE_DEFAULT_CATEGORY[nature].locked`, throw FAILED_PRECONDITION si override interdit) ; si nouvelle `category=='recoverable'` → validate `periodStart/End` ; periodYear re-dérivation si `periodStart`/`expenseDate` changent ; `propertyName` re-snapshot chaque update (pattern `payments`) ; transact update + denorm refresh. **Retour** : `{updated:true}`. Fichier `expenses.ts`.

## Triggers

| Trigger | Type / collection | Logique |
|---|---|---|
| `setUpdatedAtDocuments` | `onDocumentUpdated(documents)` | Standard `setUpdatedAt` (voir README). Fichier `set_updated_at.ts` |
| `setUpdatedAtExpenses` (FEAT-041a) | `onDocumentUpdated(expenses)` | Standard `setUpdatedAt`. Fichier `expenses.ts` (re-exported par `index.ts`) |
