# Schéma — expenses-documents

> Source d'état — expenses-documents. Maintenu par `state-keeper`.

Collections : `documents`, `expenses`. CF exclusive. Patterns transverses → [README](README.md).

---

## `documents/{id}` — CF exclusive (FEAT-008, FEAT-041b)

Justificatifs (contrats, baux scannés, attestations assurance, **FEAT-041b : reçus de dépenses** cat. `expense_receipt`). **Dénorm** : `legalHold` dérivée serveur depuis `category` (immuable après création).

| Champ | Type | Notes |
|---|---|---|
> ⚠️ **Table corrigée le 2026-07-21** contre le `set()` réel de `createDocument` : plusieurs champs listés ici n'existaient pas (`expenseId`, `fileUrl`) et quatre portaient un nom faux (`fileName`, `fileSizeBytes`, `uploadedDate`, et les valeurs de `category`).

| Champ | Type | Notes |
|---|---|---|
| `id` | string | docId auto Firestore, immuable |
| `landlordId` | string | FK → landlords.id, immuable |
| `leaseId` | string\|null | FK → leases.id (optionnel), immuable |
| `propertyId` | string\|null | FK → properties.id (optionnel), immuable — **au moins un de leaseId/propertyId requis** |
| `category` | string | `bail_signe` \| `etat_des_lieux` \| `attestation_assurance` \| `quittance_scannee` \| `expense_receipt` \| `autre` |
| `legalHold` | bool | dérivé serveur : true si category ∈ {`bail_signe`, `etat_des_lieux`, `expense_receipt`} — immuable, verrouille le soft-delete |
| `filename` | string | nom fichier original (minuscule `n`) |
| `storagePath` | string | chemin Storage, doit commencer par `documents/{uid}/` ; l'existence du fichier est vérifiée à la création |
| `sizeBytes` | int | taille en **octets**, lue depuis Storage metadata (FEAT-056 PR #156) — **jamais celle déclarée par le client** qui est ignorée depuis v3. Plafond par palier : anonymous=0 · free=10,485,760 · pro=10,485,760 · max=26,214,400 · ultra=52,428,800 |
| `mimeType` | string | PDF \| JPEG \| PNG \| WEBP |
| `uploadedAt` | timestamp | date chargement (serverTimestamp) |
| `createdAt` | timestamp | immuable |
| `updatedAt` | timestamp | CF trigger |
| `deletedAt` | timestamp\|null | soft-delete refusée si legalHold==true |

**Pas de `fileUrl` stocké** : l'URL signée (5 min) est générée à la demande par `getDocumentDownloadUrl`, jamais persistée.

**Lien dépense ↔ justificatif** : porté par `expenses.documentId` (sens expense → document). Il n'y a **pas** de champ `expenseId` sur `documents`.

**Rétention légale** : `bail_signe`/`etat_des_lieux` (loi 6/07/1989) et `expense_receipt` (10 ans, obligation comptable — cf. `docs/LEGAL.md`). `attestation_assurance` n'est **pas** sous legalHold.

**Quotas** (FEAT-056, source canonique `config/entitlements.json`) :
- **NOMBRE de documents actifs** : anonymous=0 · free=10 · pro=50 · max=150 · ultra=∞. **Comptage live** côté `createDocument` (pas de compteur dénormalisé). SOURCE DE VÉRITÉ.
- **Écriture Storage (OWASP-04, 2026-09-30)** : `storage.rules` n'accepte la création sous `documents/{uid}/` que pour un compte **non anonyme à email de confiance** (`hasTrustedEmail()`, dupliquée de `firestore.rules`), avec un nom d'objet `{id 20 car. alphanum.}.(pdf|jpg|png|webp)` (format produit par `DocumentsRepository.upload` : tout changement de ce format côté client doit suivre dans la règle) ; un anonyme (quota « documents » = 0) ne peut plus déposer d'objet. Le client ne peut ni lire, ni modifier, ni supprimer. Purge : `cleanupExpiredAnon` (anonymes expirés) et `deleteAccount` suppriment `documents/{uid}/` ; les objets jamais rattachés à un doc `documents` (orphelins) restent à purger (reporté). Tests : `functions/rules-tests/storage_rules.test.ts`.
- **TAILLE par fichier** (documentMaxBytes, en octets) : anonymous=0 · free=10 485 760 · pro=10 485 760 · max=26 214 400 · ultra=52 428 800. Appliquée à la taille RÉELLE (Storage metadata, pas celle déclarée par le client). Défense à trois niveaux : (1) `storage.rules` plafonne l'upload à **50 Mio** (maximum de la grille, garde-fou anti-abus grossier) ; (2) `createDocument` applique le plafond du PALIER via `assertRealSizeWithinPlan()` ; (3) client pré-vérifie via `quotaLimitProvider`. Stockage Rules ne peut pas lire Firestore que sur la base par défaut (ADR 0003, staging base nommée, bucket partagé) → ne peut pas dépendre du palier → plafonne au maximum.

**Règles Firestore** :
- `get/list` : isOwner(landlordId) && isActive(rsc)
- `create/update/delete` : CF exclusive (`createDocument` ; soft-delete via `softDeleteEntity` universel + purge Storage)

**Indexes** (3, relevés dans `firestore.indexes.json` le 2026-07-21) :
- landlordId ↑, leaseId ↑, deletedAt ↑, uploadedAt ↓ (documents d'un bail)
- landlordId ↑, deletedAt ↑, category ↑ (archivage par catégorie)
- deletedAt ↑, landlordId ↑, uploadedAt ↓ (registre documentaire, tri récent)

⚠️ L'index `landlordId, deletedAt, expenseId` précédemment listé **n'existe pas** (le champ non plus).

**Callables** : `createDocument` (v3 : taille réelle + paliers différenciés), `getDocumentDownloadUrl` ; soft-delete via `softDeleteEntity` (universel + purge Storage).

**Triggers** : setUpdatedAt + `softDeleteEntity` trigger cleanup Storage (PR #156, 2026-08-01).

**Utils** : `deleteStorageObject()` (idempotent, best-effort, gère `[orphan-document]` tagging pour rejeu). Tests : `soft_delete_documents_storage.test.ts`.

---

## `expenses/{id}` — CF exclusive (FEAT-041a, FEAT-041b, FEAT-041c)

Dépenses immobilières. Registre unifié (nature + catégorie + régularisation + documents). **CROSS-ENTITY** : propertyId (obligatoire) + leaseId (optionnel, cohérence lease.propertyId) + documentId (optionnel). **Dénorm** : propertyName, tenantLastName (snapshots @ update). **Juridique** : `category` dérivée immuable depuis `nature` (décret 87-713), sauf override tracé via `categoryOverridden` (pas de verrouillage natif). FEAT-033 (snapshot figé) absorbé par ce modèle.

| Champ | Type | Notes |
|---|---|---|
| `id` | string | UUID, immuable |
| `landlordId` | string | FK → landlords.id, immuable |
| `propertyId` | string | FK → properties.id (obligatoire), immuable, validation CF |
| `propertyName` | string | snapshot properties.name (dénorm, rafraîchie @ update) |
| `leaseId` | string\|null | FK → leases.id (optionnel), immuable si fourni, validation CF |
| `tenantLastName` | string\|null | snapshot leases.tenantLastName (dénorm) |
| `documentId` | string\|null | FK → documents.id (optionnel, justificatif), immuable |
| `amountCents` | int | montant (centimes, ≥ 1) |
| `expenseDate` | timestamp | date engagement dépense |
| `nature` | string | 'condo_charges' \| 'property_tax' \| 'insurance_pno' \| 'management_fees' \| 'works' \| 'repair_maintenance' \| 'other' — enum immuable (redérivation @ change) |
| `category` | string | 'recoverable' (recoupée locataire) \| 'non_recoverable' (charge bailleur) — **dérivée serveur depuis nature** |
| `categoryOverridden` | bool | true si override autorisé par nature.locked==false |
| `periodYear` | int | exercice fiscal (année rattachement) — dérivé, configurable |
| `periodStart` | timestamp\|null | début période (obligatoire si category==recoverable, FEAT-041c) |
| `periodEnd` | timestamp\|null | fin période (obligatoire si category==recoverable) |
| `notes` | string\|null | notes internes (≤ 2000 chars) |
| `createdAt` | timestamp | immuable |
| `updatedAt` | timestamp | CF trigger |
| `deletedAt` | timestamp\|null | soft-delete |

**Nature → Category (NATURE_DEFAULT_CATEGORY, décret 87-713)** :
- `condo_charges` → recoverable (locked: false, override OK)
- `property_tax` → non_recoverable (locked: true)
- `insurance_pno` → non_recoverable (locked: true)
- `management_fees` → non_recoverable (locked: true)
- `works` → non_recoverable (locked: false)
- `repair_maintenance` → non_recoverable (locked: false)
- `other` → non_recoverable (locked: false)

**Mutable fields** (updateExpense) : amountCents, expenseDate, nature, category, periodStart, periodEnd, periodYear, documentId, notes. Re-dérivation @ nature/category change (category applique verrouillage).

**Règles Firestore** :
- `get/list` : isOwner(landlordId) && isActive(rsc)
- `create/update/delete` : CF exclusive (`createExpense`, `updateExpense`, `softDeleteEntity`)

**Indexes** :
- landlordId ↑, deletedAt ↑, propertyId ↑ (property expenses)
- landlordId ↑, deletedAt ↑, category ↑, periodYear ↑ (tax year categorization)
- propertyId ↑, deletedAt ↑, category ↑, periodStart ↓ (regularization feed)

**Callables** : `createExpense`, `updateExpense`.

**Triggers** :
- setUpdatedAt
- recomputeChargeRegularization (FEAT-041c, **planné pas déployé** — si nature change ou category==recoverable → alimente lease.nonRecoverableCharges ; periodStart/periodEnd pour drill-down)
