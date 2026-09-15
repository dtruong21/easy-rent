# Functions — Expenses & Documents

> Source d'état — expenses-documents. Maintenu par state-keeper.

Dépenses (FEAT-041a) + documents (FEAT-008, v2 FEAT-041b). Fichiers : `functions/src/callable/{expenses,documents,soft_delete}.ts`.

## Callables — Documents

**ADR 0003** : tous les callables écrivant Firestore utilisent `dbForRequest(request)` pour router vers la base prod ou staging par Origin.

### `createDocument` (v3, FEAT-008/FEAT-041b/FEAT-044/FEAT-056)
Client invoke. **v3 (2026-08-03+) : taille RÉELLE lue depuis Storage, paliers différenciés par tier.**
- **Flow réel** : le client **uploade d'abord** dans Storage (SDK Firebase, Storage Rules `uid == landlordId` dans le path), **puis** appelle ce callable avec le `storagePath`. Il n'y a **pas** de transfert base64 par la callable.
- **Params** : `leaseId` (opt), `propertyId` (opt) — **au moins un des deux requis** ; `category`, `filename`, `storagePath`, `mimeType`, `sizeBytes` (opt, **ignoré**). Il n'existe **pas** de param `expenseId` (le lien se fait dans l'autre sens : `expenses.documentId`).
  - **`sizeBytes` accepté pour rétrocompat** mais volontairement IGNORÉ : déclaré par le client, ne peut pas être source de vérité. Depuis PR #156, la taille persistée vient de `resolveRealSize()` qui lit les métadonnées Storage. C'est ce qui rend le plafond PAR PALIER contraignant (au lieu d'être contournable par un client modifié).
- **Catégories réelles** : `bail_signe` \| `etat_des_lieux` \| `attestation_assurance` \| `quittance_scannee` \| `expense_receipt` \| `autre`.
- **Validations** : auth ; `storagePath` doit commencer par `documents/{uid}/` ; **le fichier doit exister dans Storage** sinon `failed-precondition` (empêche l'enregistrement d'un doc fantôme) ; MIME ∈ {PDF, JPEG, PNG, WEBP} ; ownership du bail et/ou du bien + non soft-deleted ; si les deux fournis → `lease.propertyId == propertyId` sinon `lease_property_mismatch` ; **taille réelle ≥ 1 octet** sinon `document_empty` ; taille réelle **≤ plafond du palier** sinon `file_too_large` (details: `{limitBytes, sizeBytes, upgradeTo}`).
- **Gate multi-paliers (FEAT-056)** — ordre stricte :
  1. `assertDocumentQuota(db, uid)` → applique quota N°1 **NOMBRE** (count), renvoie le plafond N°2 **TAILLE** `documentMaxBytes` du palier. Quota count d'abord : sinon un anon se verrait proposer « fichier trop volumineux » au lieu de « aucun doc autorisé ».
  2. `resolveRealSize(storagePath, uid)` → lit les métadonnées Storage (replace l'ancien `exists()` — même bilan : 404 GCS = doc fantôme). Valide format size, non-vide.
  3. `assertRealSizeWithinPlan(sizeBytes, byteLimit)` → pur et exporté. Applique le plafond du palier à la taille RÉELLE. Rejette après vérification cross-entity pour plus de précision dans le message d'erreur.
  - **Plafond document count** : anonymous=0 · free=10 · pro=50 · max=150 · ultra=∞. **Comptage live** (`count()` where `deletedAt == null`), pas de compteur dénormalisé. SOURCE DE VÉRITÉ.
  - **Plafond par fichier** (documentMaxBytes en **bytes**, FEAT-056) : anonymous=0 · free=10 485 760 (10 Mio) · pro=10 485 760 · max=26 214 400 (25 Mio) · ultra=52 428 800 (50 Mio). Source canonique : `config/entitlements.json`.
  - Effective plan déduit de `(subscriptionTier, planLevel)` par `resolvePlan()`. Landlord absent → `not-found` (fail-closed).
- **Orphelin Storage (depuis PR #156)** : tout refus (quota, ownership, taille, format) emporte l'objet Storage avec lui via `deleteStorageObject(storagePath, uid)` (catch bloc) — le client ne peut pas le faire (storage.rules refuse delete). Idempotent : `ignoreNotFound=true`.
- **`legalHold` dérivé serveur** (immuable) = `category ∈ {bail_signe, etat_des_lieux, expense_receipt}`. Verrouille le soft-delete (immutable 5 ans loi 1989, 10 ans comptable).
- **Retour** : `{documentId, legalHold}`. Fichier `documents.ts`.

### `getDocumentDownloadUrl` (FEAT-008)
Client invoke. Génère une **URL signée court-terme (5 min)** pour télécharger le fichier. Ownership check (`landlordId==uid`) + refus si `deletedAt!=null`. **Retour** : `{downloadUrl, downloadUrlExpiresAt}`. Fichier `documents.ts`.

### `updateDocumentCategory` (FIX 2026-09-15)
Client invoke. **Seule mutation autorisée** sur un document (les Rules posent `update: if false`). Reclasse la `category` (seul champ mutable ; les 5 colonnes immuables restent figées) et **recalcule `legalHold`** depuis la nouvelle catégorie, comme `createDocument`. Ownership check (`landlordId==uid`) + refus si `deletedAt!=null` + validation `ALLOWED_CATEGORIES`. **Garde-fou rétention** : refuse (`FAILED_PRECONDITION` code `document_under_legal_hold`) si le document est **déjà** sous `legalHold` — même logique que `softDeleteEntity`. **Retour** : `{documentId, category, legalHold}`. Fichier `documents.ts`. Client : `FirestoreDocumentsRepository.updateCategory` (relit via `getById`) ; le contrôleur mappe le refus vers `UpdateCategoryErrorReason.legalHold`. ✅ **Testé** : `functions/src/__tests__/update_document_category.test.ts` (8 cas) + `test/unit/update_category_controller_test.dart`. Corrige le stub client qui jetait `UnsupportedError` (action « Modifier la catégorie » cassée en prod).

### Soft-delete de documents — via `softDeleteEntity('documents')` + Storage cleanup
Pas de callable dédié (`softDeleteDocument` n'existe pas) : le soft-delete passe par le `softDeleteEntity` universel (spec canonique → account). Flow : fetch document ; si `legalHold==true` → FAILED_PRECONDITION (immutable) ; sinon `deletedAt=now()` **PUIS** `deleteStorageObject(storagePath, uid)` (best-effort, idempotent). **Retour** : `{success:true, storageDeleted, alreadyDeleted}`. Fichier `soft_delete.ts`. Détail du cleanup → `functions/src/utils/storage_cleanup.ts`.

#### Utilité `deleteStorageObject(storagePath, uid)` — pur serveur
Supprime un objet Storage de manière idempotente (ignoreNotFound=true). **Jamais ne throw** : best-effort. Appelants : `softDeleteEntity('documents')` (post-commit Firestore) ou `createDocument` (catch bloc si refus après upload). Logues les résidus en ERROR + tag `[orphan-document]` pour rejeu par `scripts/purge-orphan-documents.mjs`. Fichier `functions/src/utils/storage_cleanup.ts`. ✅ **Testé** : `functions/src/__tests__/soft_delete_documents_storage.test.ts` (PR #156, 2026-08-01).

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
