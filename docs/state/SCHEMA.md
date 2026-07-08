# Schéma Firestore — snapshot

> Maintenu par `state-keeper`. **Source** : `firestore.rules` + `firestore.indexes.json` + Cloud Functions callables. **Dernière sync** : 2026-07-08 (FEAT-045 : champs `receipts.accountDeletedAt/retentionUntil` pour rétention légale 5 ans ; FEAT-043 i18n sans impact schema). **Pivot** : FEAT-019 (2026-06-30) — migration Supabase Postgres → Firestore camelCase.

## Collections (11 total)

| Collection | Type | Access | Trigger |
|---|---|---|---|
| `landlords` | singleton (uid) | CRUD account | setUpdatedAt |
| `properties` | multi | CRUD account (isFullyAuthed) | setUpdatedAt |
| `tenants` | multi | CRUD account | setUpdatedAt |
| `leases` | multi | CF exclusive | setUpdatedAt |
| `payments` | multi | CF exclusive | setUpdatedAt |
| `receipts` | multi | rules read-only | setUpdatedAt + recomputeReceiptStale |
| `documents` | multi | CF exclusive | setUpdatedAt |
| `expenses` | multi | **CF exclusive (FEAT-041)** | setUpdatedAt |
| `investment_scenarios` | multi | CRUD signed | setUpdatedAt |
| `paid_plan_interest` | singleton (uid) | CRUD account | — |
| `support_requests` | multi | create-only (FEAT-025) | — |

---

### `landlords/{uid}` — docId = Firebase Auth UID

Authentication + account tiers (anonymous/free/pro). BAILLAN-M1 3-state system.

| Champ | Type | Valeur | Immuable | RLS |
|---|---|---|---|---|
| `id` | string | Firebase Auth UID | ✅ | isOwner(uid) |
| `email` | string\|null | null (anon) / email (compte) | ✅ | — |
| `fullName` | string | '' (anon) / nom complet | ✅ | — |
| `isAnonymous` | bool | true (essai) / false (compte) | ✅ | — |
| `subscriptionTier` | string | 'anonymous' / 'free' / 'pro' | ✅ | — |
| `anonExpiresAt` | timestamp | Expiration essai (14j) | — | — |
| `rgpdConsentAt` | timestamp\|null | null (anon) / date signature | ✅ | — |
| `rgpdConsentVersion` | string | v1-2026-06 → v2-2026-07 | ✅ | — |
| `createdAt` | timestamp | Création compte | ✅ | — |
| `updatedAt` | timestamp | Dernière modification | — | CF trigger |
| `deletedAt` | timestamp\|null | null (actif) / soft-delete | — | isActive(rsc) |

**RLS Rules** :
- `get` : isOwner(uid) && (resource==null \|\| isActive(resource))
- `create` (compte complet) : isFullyAuthed() + RGPD consent v2-2026-07
- `create` (anonyme) : isAnonymous() + anonExpiresAt <= now+15j
- `update` (compte) : isFullyAuthed() && preservesImmutables()
- `update` (anonyme) : isAnonymous() && anonExpiresAt valide
- `delete` : interdit (soft-delete via CF `softDeleteLandlord` + scheduled `cleanupExpiredAnon`)

**Triggers** : setUpdatedAt (CF)

---

### `properties/{id}` — CRUD direct, isFullyAuthed only

Bien immobilier (appartement, maison, etc). Anonyme N/A.

| Champ | Type | Notes |
|---|---|---|
| `id` | string | UUID, docId |
| `landlordId` | string | FK → landlords.id, immuable |
| `name` | string | Adresse ou nom |
| `address` | string | Complète (rue + code postal) |
| `type` | string | 'appartement' \| 'maison' \| 'studio' \| 'autre' |
| `activeLeaseCount` | int | Denormalisé (CF increment/decrement) — client read-only |
| `createdAt` | timestamp | Immuable |
| `updatedAt` | timestamp | CF trigger |
| `deletedAt` | timestamp\|null | Soft-delete, isActive filter |

**RLS** :
- `get/list` : isOwner(landlordId) && isActive(resource)
- `create` : isFullyAuthed() && landlordId==uid && activeLeaseCount==0 à la création
- `update` : isFullyAuthed() && isOwner(landlordId) && preservesImmutables()
- `delete` : interdit (soft-delete CF exclusive)

**Indexes** :
- landlordId, deletedAt, name
- landlordId, deletedAt, createdAt DESC

**Triggers** : setUpdatedAt (CF)

---

### `tenants/{id}` — CRUD direct, isFullyAuthed only

Locataire. Anonyme N/A.

| Champ | Type | Notes |
|---|---|---|
| `id` | string | UUID |
| `landlordId` | string | FK → landlords.id, immuable |
| `firstName` | string | Prénom |
| `lastName` | string | Nom |
| `email` | string | Email regex ^[^@\s]+@[^@\s]+\.[^@\s]+$ |
| `activeLeaseCount` | int | Denormalisé (CF) — client read-only |
| `createdAt` | timestamp | Immuable |
| `updatedAt` | timestamp | CF trigger |
| `deletedAt` | timestamp\|null | Soft-delete, isActive filter |

**RLS** :
- `get/list` : isOwner(landlordId) && isActive(resource)
- `create` : isFullyAuthed() && landlordId==uid && activeLeaseCount==0
- `update` : isFullyAuthed() && isOwner(landlordId) && preservesImmutables()
- `delete` : interdit

**Indexes** :
- landlordId, deletedAt, firstName
- landlordId, deletedAt, lastName

**Triggers** : setUpdatedAt (CF)

---

### `leases/{id}` — CF exclusive (FEAT-036, FEAT-042, FEAT-006)

Bail d'habitation. **CROSS-ENTITY** : propertyId + tenantId doivent appartenir au même landlord + validation ownership. Charges = `chargesAmountCents` (récupérable FEAT-036) + `nonRecoverableChargesCents` (informatif bailleur, FEAT-036). **Mode de charges (FEAT-042)** : `chargeMode` (provisions | forfait) détermine l'éligibilité à la régularisation (provisions uniquement).

| Champ | Type | Notes |
|---|---|---|
| `id` | string | UUID, immuable |
| `landlordId` | string | FK → landlords.id, immuable |
| `propertyId` | string | FK → properties.id, immuable, validation CF |
| `tenantId` | string | FK → tenants.id, immuable, validation CF |
| `propertyName` | string | Snapshot properties.name (dénorm) |
| `propertyAddress` | string | Snapshot properties.address |
| `tenantFirstName` | string | Snapshot tenants.firstName |
| `tenantLastName` | string | Snapshot tenants.lastName |
| `tenantEmail` | string | Snapshot tenants.email |
| `rentAmountCents` | int | Loyer mensuel (en centimes) |
| `chargesAmountCents` | int | Part RÉCUPÉRABLE (FEAT-036) — bilancée au locataire via paiement + régularisation (provisions only) |
| `nonRecoverableChargesCents` | int | Part NON-RÉCUPÉRABLE (FEAT-036) — informatif bailleur, jamais bilancée ; forcé à 0 en mode forfait (FEAT-042) |
| `startDate` | timestamp | Début bail |
| `endDate` | timestamp\|null | Fin bail |
| `status` | string | 'active' \| 'terminated' \| 'archived' |
| `leaseType` | string | 'unfurnished' \| 'furnished' \| 'mobility' \| 'student' |
| `chargeMode` | string\|null | **FEAT-042** : 'provisions' (provisions mensuelles + régularisation) \| 'forfait' (montant libératoire, pas de régularisation). Nullable = migration lazy ; effectif dérivé de leaseType si null (voir note) |
| `depositAmountCents` | int\|null | Dépôt garantie |
| `paymentDay` | int | Jour versement (1..28) |
| `paymentMethod` | string | 'virement' \| 'cheque' \| 'especes' \| 'prelevement' \| 'autre' |
| `irlIndexValue` | number\|null | Indice IRL de révision |
| `irlQuarterRef` | string\|null | T[1-4]-YYYY (ex: T4-2025) |
| `agencyFeesCents` | int | Frais agence |
| `solidarityClause` | bool | Clause de solidarité |
| `entryInventoryDone` | bool | Etat des lieux entrée réalisé |
| `createdAt` | timestamp | Immuable |
| `updatedAt` | timestamp | CF trigger |
| `deletedAt` | timestamp\|null | Soft-delete, isActive filter |

**Charge Mode Resolution (FEAT-042)** : 
- `chargeMode==null` (baux pré-042, migration lazy sans backfill) → getter Dart `effectiveChargeMode` dérive depuis `leaseType` :
  - `unfurnished` → `provisions` (art. 23 loi 6 juillet 1989, forcé serveur)
  - `mobility` → `forfait` (loi ELAN art. 25-18, forcé serveur)
  - `furnished` | `student` → `provisions` (défaut sûr)
- `chargeMode` explicite (baux FEAT-042+) → validé serveur (`resolveChargeMode` impose cohérence type↔mode, rejette changements incohérents)
- **Forfait mode** : `nonRecoverableChargesCents` forcé à 0 serveur (ventilation interdite) — valide aussi pour baux legacy mobilité

**Mutable fields** (updateLease) : rentAmountCents, chargesAmountCents, nonRecoverableChargesCents, endDate, status, leaseType, chargeMode, depositAmountCents, paymentDay, paymentMethod, irlIndexValue, irlQuarterRef, agencyFeesCents, solidarityClause, entryInventoryDone.

**RLS** :
- `get/list` : isOwner(landlordId) && isActive(resource)
- `create/update/delete` : CF exclusive via `createLease`, `updateLease`, `softDeleteEntity`

**Indexes** :
- landlordId, deletedAt, status
- landlordId, deletedAt, startDate DESC
- landlordId, deletedAt, status, startDate DESC
- propertyId, tenantId (unicity check)
- tenantId, deletedAt, status

**Triggers** :
- setUpdatedAt (CF)
- activeLeaseCount increment/decrement (createLease/updateLease/softDelete transactionnel)

---

### `payments/{id}` — CF exclusive (FEAT-006)

Paiement loyer/charges. **CROSS-ENTITY** : leaseId doit appartenir au même landlord. Motif libre sur reçu (FEAT-029).

| Champ | Type | Notes |
|---|---|---|
| `id` | string | UUID, immuable |
| `landlordId` | string | FK → landlords.id, immuable |
| `leaseId` | string | FK → leases.id, immuable, validation CF |
| `propertyId` | string | Snapshot leases.propertyId (dénorm) |
| `tenantLastName` | string | Snapshot leases.tenantLastName |
| `rentAmountCents` | int | Portion loyer versée |
| `chargesAmountCents` | int | Portion charges (= leases.chargesAmountCents prorate) versée |
| `amountCents` | int | Total versé (rentAmountCents + chargesAmountCents) |
| `paidDate` | timestamp | Date de versement |
| `paymentMethod` | string | 'virement' \| 'cheque' \| 'especes' \| 'prelevement' \| 'autre' |
| `notes` | string\|null | Motif libre (FEAT-029) → PDF |
| `createdAt` | timestamp | Immuable |
| `updatedAt` | timestamp | CF trigger |
| `deletedAt` | timestamp\|null | Soft-delete |

**RLS** :
- `get/list` : isOwner(landlordId) && isActive(resource)
- `create/update/delete` : CF exclusive

**Indexes** :
- landlordId, deletedAt, leaseId, paidDate DESC
- leaseId, deletedAt, paidDate DESC

**Triggers** :
- setUpdatedAt (CF)
- recomputeReceiptStale (leases/receipts) si payment.amountCents change

---

### `receipts/{id}` — CF exclusive (FEAT-007)

Quittance loyer (loi 6 juillet 1989). **IMMUABLE** : jamais soft-delete (rétention légale 5 ans). Voiding via Callable `voidReceipt` (logique métier).

| Champ | Type | Notes |
|---|---|---|
| `id` | string | UUID, immuable |
| `landlordId` | string | FK → landlords.id, immuable |
| `leaseId` | string | FK → leases.id, immuable |
| `paymentId` | string\|null | FK → payments.id (null si générée manuellement) |
| `propertyName` | string | Snapshot properties.name |
| `tenantName` | string | Snapshot tenants lastName |
| `amountCents` | int | Montant |
| `periodStart` | timestamp | Début période |
| `periodEnd` | timestamp | Fin période |
| `receiptNumber` | string | Numéro séquentiel |
| `status` | string | 'generated' \| 'voided' \| 'sent' (markers non-exclusifs, bits) |
| `receiptDate` | timestamp | Date édition |
| `voidReason` | string\|null | Raison annulation (si voided) |
| `accountDeletedAt` | timestamp\|null | **FEAT-045** : stamp suppression compte (null si compte actif) — quittance conservée 5 ans |
| `retentionUntil` | timestamp\|null | **FEAT-045** : date limite de rétention légale (5 ans après suppression) — purge async après |
| `createdAt` | timestamp | Immuable |
| `updatedAt` | timestamp | CF trigger (status only) |
| `deletedAt` | timestamp\|null | null (jamais supprimée en practice, marquée voided) |

**RLS** :
- `get/list` : isOwner(landlordId) (pas de filtrage isActive — voided restent lisibles audit)
- `create/update/delete` : CF exclusive via `generateReceipt`, `voidReceipt`, `markReceiptAsSent`

**Indexes** :
- landlordId, leaseId, receiptDate DESC
- landlordId, status, receiptDate DESC

**Triggers** :
- setUpdatedAt (CF, status seulement)
- recomputeReceiptStale (si la lease/payment change, flags staleness)

---

### `documents/{id}` — CF exclusive (FEAT-008, FEAT-041b)

Justificatifs (contrats, baux scannés, attestations d'assurance, **FEAT-041b : reçus de dépenses** avec catégorie `expense_receipt`). **Dénormalisation** : `legalHold` dérivée serveur depuis `category` (immuable après création).

| Champ | Type | Notes |
|---|---|---|
| `id` | string | UUID, immuable |
| `landlordId` | string | FK → landlords.id, immuable |
| `leaseId` | string\|null | FK → leases.id (optionnel), immuable |
| `propertyId` | string\|null | FK → properties.id (optionnel, for context), immuable |
| `expenseId` | string\|null | FK → expenses.id (optionnel, FEAT-041b), immuable |
| `category` | string | 'lease_scan' \| 'insurance' \| 'expense_receipt' \| 'other' — dérivé catégorie juridique |
| `legalHold` | bool | true (lease_scan, insurance) / false (other) — immuable, verrouille soft-delete |
| `fileName` | string | Nom fichier original |
| `fileUrl` | string | Signed URL (5 min, renouvellement @ access) |
| `fileSizeBytes` | int | Taille (validation < 25 MB) |
| `mimeType` | string | 'image/jpeg' \| 'application/pdf' \| … |
| `uploadedDate` | timestamp | Date chargement |
| `createdAt` | timestamp | Immuable |
| `updatedAt` | timestamp | CF trigger |
| `deletedAt` | timestamp\|null | Soft-delete refusée si legalHold==true |

**RLS** :
- `get/list` : isOwner(landlordId) && isActive(resource)
- `create/update/delete` : CF exclusive via `createDocument`, `softDeleteDocument`

**Indexes** :
- landlordId, deletedAt, leaseId
- landlordId, deletedAt, expenseId (FEAT-041b)
- landlordId, deletedAt, category

**Triggers** : setUpdatedAt (CF)

---

### `expenses/{id}` — CF exclusive (FEAT-041a, FEAT-041b, FEAT-041c)

Dépenses immobilières. **NEW FEAT-041** : registre unifié (nature + catégorie + régularisation + documents). **CROSS-ENTITY** : propertyId (obligatoire) + leaseId (optionnel, cohérence lease.propertyId) + documentId (optionnel). **Dénorm** : propertyName, tenantLastName (snapshots, rafraîchis @ update). **Juridique** : `category` dérivée immuable depuis `nature` (décret 87-713), sauf override tracé via `categoryOverridden` (pas de verrouillage natif).

| Champ | Type | Notes |
|---|---|---|
| `id` | string | UUID, immuable |
| `landlordId` | string | FK → landlords.id, immuable |
| `propertyId` | string | FK → properties.id (obligatoire), immuable, validation CF |
| `propertyName` | string | Snapshot properties.name (dénorm, rafraîchie @ update) |
| `leaseId` | string\|null | FK → leases.id (optionnel), immuable si fourni, validation CF |
| `tenantLastName` | string\|null | Snapshot leases.tenantLastName (dénorm) |
| `documentId` | string\|null | FK → documents.id (optionnel, justificatif), immuable |
| `amountCents` | int | Montant (centimes, ≥ 1) |
| `expenseDate` | timestamp | Date engagement dépense |
| `nature` | string | 'condo_charges' \| 'property_tax' \| 'insurance_pno' \| 'management_fees' \| 'works' \| 'repair_maintenance' \| 'other' — enum immuable (redérivation @ nature change) |
| `category` | string | 'recoverable' (recoupée au locataire) \| 'non_recoverable' (à charge bailleur) — **dérivée serveur depuis nature** |
| `categoryOverridden` | bool | true si override autorisé par nature.locked==false |
| `periodYear` | int | Exercice fiscal (année de rattachement) — dérivé, configurable |
| `periodStart` | timestamp\|null | Début période (obligatoire si category==recoverable, FEAT-041c) |
| `periodEnd` | timestamp\|null | Fin période (obligatoire si category==recoverable) |
| `notes` | string\|null | Notes internes (≤ 2000 chars) |
| `createdAt` | timestamp | Immuable |
| `updatedAt` | timestamp | CF trigger |
| `deletedAt` | timestamp\|null | Soft-delete |

**Nature → Category mapping (NATURE_DEFAULT_CATEGORY, décret 87-713)** :
- `condo_charges` → recoverable (locked: false, override OK)
- `property_tax` → non_recoverable (locked: true)
- `insurance_pno` → non_recoverable (locked: true)
- `management_fees` → non_recoverable (locked: true)
- `works` → non_recoverable (locked: false)
- `repair_maintenance` → non_recoverable (locked: false)
- `other` → non_recoverable (locked: false)

**Mutable fields** (updateExpense) : amountCents, expenseDate, nature, category, periodStart, periodEnd, periodYear, documentId, notes. **Re-dérivation** @ nature/category change : category applique verrouillage.

**RLS** :
- `get/list` : isOwner(landlordId) && isActive(resource)
- `create/update/delete` : CF exclusive via `createExpense`, `updateExpense`, `softDeleteEntity`

**Indexes** :
- landlordId, deletedAt, propertyId
- landlordId, deletedAt, category, periodYear
- propertyId, deletedAt, category, periodStart DESC

**Triggers** :
- setUpdatedAt (CF)
- recomputeChargeRegularization (FEAT-041c, alimente lease.nonRecoverableCharges si nature change ou category==recoverable → periodStart/periodEnd utilisés pour drill-down)

---

### `investment_scenarios/{id}` — CRUD direct (FEAT-018)

Simulateur immobilier. Accessible anonymes + comptes (CRUD direct).

| Champ | Type | Notes |
|---|---|---|
| `id` | string | UUID, immuable |
| `landlordId` | string | FK → landlords.id, immuable |
| `name` | string | Nom scénario (≤ 120 chars) |
| `schemaVersion` | int | Version données (versionning) |
| `scenarioJson` | object | Snapshot séralisé |
| `createdAt` | timestamp | Immuable |
| `updatedAt` | timestamp | CF trigger |
| `deletedAt` | timestamp\|null | Soft-delete |

**RLS** :
- `get/list` : isOwner(landlordId) && isActive(resource)
- `create` : isSignedIn() (anon OK) && landlordId==uid
- `update` : isOwner(landlordId) && preservesImmutables()
- `delete` : interdit

**Triggers** : setUpdatedAt (CF)

---

### `paid_plan_interest/{uid}` — docId = Firebase Auth UID, BAILLAN-M1

Marque d'intérêt futur Plan Pro. Singleton par utilisateur complet (anonyme non élligible). **CREATE-ONLY** depuis le KPI dashboard.

| Champ | Type | Notes |
|---|---|---|
| `uid` | string | Firebase Auth UID, docId, immuable |
| `features` | array[string] | Features intéressantes (ex: ['reminders', 'ocr']) |
| `createdAt` | timestamp | Immuable |

**RLS** :
- `get` : isOwner(uid)
- `create/update` : isFullyAuthed() && isOwner(uid)
- `delete` : interdit

---

### `support_requests/{id}` — CREATE-ONLY (FEAT-025)

Formulaire « Nous contacter ». Capture email, subject, message, appVersion, appEnv. Traitement via Admin SDK / console (pas de back-office in-app V1).

| Champ | Type | Notes |
|---|---|---|
| `id` | string | UUID, docId, immuable |
| `landlordId` | string | FK → landlords.id, immuable |
| `email` | string | Adresse contact |
| `subject` | string | Objet (≤ 120 chars) |
| `message` | string | Contenu (≤ 2000 chars) |
| `appVersion` | string | Version app (ex: 1.0.0+1) |
| `appEnv` | string | Environnement (dev, staging, prod) |
| `status` | string | 'new' (initial, jamais changé client) |
| `createdAt` | timestamp | request.time, immuable |

**RLS** :
- `get/list` : false (l'utilisateur ne relit jamais ses demandes V1)
- `create` : isFullyAuthed() && landlordId==uid + validations subject/message bornes
- `update/delete` : false

---

## Composite Indexes (28 total)

Tous les indices sont **Collection > Composite** sauf indication. Filtrages soft-delete systématiques (deletedAt ASC/DESC pour isActive()).

### Soft-Delete Patterns (23 indexes)

| Chemin | Composition | Usage |
|---|---|---|
| properties | landlordId ↑, deletedAt ↑, name ↑ | List actives par bailleur |
| properties | landlordId ↑, deletedAt ↑, createdAt ↓ | Recent first |
| tenants | landlordId ↑, deletedAt ↑, firstName ↑ | List search |
| tenants | landlordId ↑, deletedAt ↑, lastName ↑ | List search |
| leases | landlordId ↑, deletedAt ↑, status ↑ | Filter status (active/terminated) |
| leases | landlordId ↑, deletedAt ↑, startDate ↓ | Recent first |
| leases | landlordId ↑, deletedAt ↑, status ↑, startDate ↓ | KPI drill-down |
| leases | tenantId ↑, deletedAt ↑, status ↑ | Tenants leases |
| payments | landlordId ↑, deletedAt ↑, leaseId ↑, paidDate ↓ | Payment history |
| payments | leaseId ↑, deletedAt ↑, paidDate ↓ | Payment timeline |
| receipts | landlordId ↑, leaseId ↑, receiptDate ↓ | Receipt archiving (no isActive, voided lisible) |
| receipts | landlordId ↑, status ↑, receiptDate ↓ | Status tracking |
| documents | landlordId ↑, deletedAt ↑, leaseId ↑ | Lease documents |
| documents | landlordId ↑, deletedAt ↑, expenseId ↑ | Expense receipts (FEAT-041b) |
| documents | landlordId ↑, deletedAt ↑, category ↑ | Category archiving |
| expenses | landlordId ↑, deletedAt ↑, propertyId ↑ | Property expenses |
| expenses | landlordId ↑, deletedAt ↑, category ↑, periodYear ↑ | Tax year categorization |
| expenses | propertyId ↑, deletedAt ↑, category ↑, periodStart ↓ | Regularization feed |
| investment_scenarios | landlordId ↑, deletedAt ↑, createdAt ↓ | Scenarios list |
| landlords | isAnonymous ↑, anonExpiresAt ↑ | Expiration cleanup |

### Cross-Entity Indexes (5 indexes)

| Chemin | Composition | Usage |
|---|---|---|
| leases | propertyId ↑, tenantId ↑ | Unicity check (CF validation) |
| leases | propertyId ↑, deletedAt ↑ | Property lease count |
| leases | tenantId ↑, deletedAt ↑, status ↑ | Tenant active leases |

---

## Rules Architecture (3 couches)

### Couche 1 : Firestore Security Rules (ce fichier)

**Stratégie** : default deny + allowlist explicite. Aucune mutation cross-entity côté client (leases, payments, receipts, documents, expenses = CF exclusive).

- **isOwner(uid)** : claim auth.uid == document.landlordId
- **list owner-scoped (audit FEAT-045 H1)** : `allow list: if isOwner(resource.data.landlordId)` sur les 8 collections multi-tenant — toute query DOIT porter `where('landlordId','==',uid)` (les rules ne sont pas des filtres ; l'ancien `isSignedIn()` permettait la lecture cross-tenant par UID). Vérifié par tests émulateur (`npm run test:rules`)
- **isActive(rsc)** : resource.data.deletedAt == null (filtrage systématique)
- **preservesImmutables(rsc)** : Garde-fou mutations (landlordId, createdAt, deletedAt jamais changés client)
- **isFullyAuthed()** : Compte complet (email/password, Google, Apple) — isSignedIn() && !isAnonymous()
- **isAnonymous()** : Custom claim firebase.sign_in_provider == 'anonymous' (BAILLAN-M1)

### Couche 2 : Callable Cloud Functions

6 functions cross-entity + cross-tenant :
- `createLease`, `updateLease` : validation propertyId/tenantId ownership + activeLeaseCount transactionnel
- `createPayment`, `updatePayment` : validation leaseId ownership + denorm snapshots
- `generateReceipt`, `voidReceipt`, `markReceiptAsSent` : immuabilité + status tracking
- `createDocument`, `softDeleteDocument` : legalHold dérivée + locking
- `createExpense`, `updateExpense` : cross-entity + juridique category dérivation (FEAT-041)
- `softDeleteEntity` : soft-delete unifié (landlords, properties, tenants, leases, payments, documents, expenses, investment_scenarios)
- `finalize_anonymous_upgrade` : transition anon → compte (subscriptionTier)

### Couche 3 : Firestore Triggers

8 triggers setUpdatedAt + metadata recomputation :
- **setUpdatedAt×7** : landlords, properties, tenants, leases, payments, documents, expenses, investment_scenarios, receipts
- **recomputeReceiptStale** : Si payment/lease changent → marked stale (audit denorm)
- **recomputeChargeRegularization** : (FEAT-041c, planné) Si expense.category==recoverable → alimente lease charge regularization feed

**Note** : delete triggers = soft-delete logic CF (aucun hard-delete sauf purge anonyme 14j).

---

## Erreurs & Inconsistencies (audit 2026-07-05)

✅ **Cohérent** :
- 11 collections déclarées, mappées 1:1 aux routes + features
- 28+ composite indexes couvrent tous les soft-delete + cross-filters
- 3-couche RLS : rules + CF + triggers, zéro WHERE field==null sans index
- Dénormalisation (propertyName, tenantLastName, propertyId snapshots) systématique (pattern `payments` appliqué partout)
- FEAT-041 (expenses) intégré : CF exclusive + juridique category.locked + categoryOverridden trace + FEAT-041c (regularization feed) prévu

⚠️ **À surveiller** :
- FEAT-041c (recomputeChargeRegularization trigger) planné, pas encore déployé (attendre V1.1)
- FEAT-033 (snapshot figé dépense) **absorbé** par FEAT-041 V1 (categoryOverridden + nature enum = version immuable du contexte juridique)

---

## Cloud Functions & Triggers Callables

Cf. [`FUNCTIONS.md`](FUNCTIONS.md) pour détail (signatures TypeScript, error handling, tests).
