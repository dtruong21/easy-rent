# Functions — Expenses & Documents

> Source d'état — expenses-documents. Maintenu par state-keeper.

Dépenses (FEAT-041a) + documents (FEAT-008, v2 FEAT-041b). Fichiers : `functions/src/callable/{expenses,documents,soft_delete}.ts`.

## Callables — Documents

### `createDocument` (v2, FEAT-008/FEAT-041b)
Client invoke.
- **Params** : `leaseId` (opt/nullable), `propertyId` (opt, contexte FEAT-041b), `expenseId` (opt, FEAT-041b — lien dépense), `category` (`'lease_scan'|'insurance'|'expense_receipt'` NEW`|'other'`), `fileName, fileBase64, mimeType`.
- **Validations** : auth + ownership ; si `leaseId` → FK + ownership ; si `expenseId` → FK + ownership (FEAT-041b) ; MIME whitelist PDF/JPEG/PNG ; size cap **25 MB**.
- **Mutations** : upload → Storage `/documents/{landlordId}/{docId}.{ext}` ; **derive `legalHold` from category** (serveur, immuable) : `lease_scan`→true (rétention 3 ans), `insurance`→true (3 ans), `expense_receipt`→false (soft-delete autorisé), `other`→false ; CREATE `documents/{id}` ; si `expense_receipt`+`expenseId` → lien bilatéral.
- **Retour** : `{documentId, storageUrl}`. **Note** : `legalHold` dérivée immuable empêche soft-delete si true (garde-fou légal). Fichier `documents.ts`.

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
| `setUpdatedAtDocuments` | `onDocumentWritten(documents)` | Standard `setUpdatedAt` (voir README). Fichier `set_updated_at.ts` |
| `setUpdatedAtExpenses` (FEAT-041a) | `onDocumentWritten(expenses)` | Standard `setUpdatedAt`. Fichier `expenses.ts` (re-exported par `index.ts`) |
