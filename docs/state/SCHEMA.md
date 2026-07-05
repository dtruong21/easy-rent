# Schéma Firestore — snapshot

> Maintenu par `state-keeper`. **Source** : `firestore.rules` + `firestore.indexes.json` + Cloud Functions. **Dernière sync** : 2026-07-05 (FEAT-025 support_requests, FEAT-029 payment.notes). **Pivot** : FEAT-019 (2026-06-30) — migration Supabase Postgres → Firestore.

## Collections (10 total)

| Collection | Type | Access | Indexing | Trigger |
|---|---|---|---|---|
| `landlords` | singleton | CRUD compte | 1 composite | setUpdatedAt |
| `properties` | multi | CRUD account | 2 composite | setUpdatedAt |
| `tenants` | multi | CRUD account | 2 composite | setUpdatedAt |
| `leases` | multi | CF only | 5 composite | setUpdatedAt |
| `payments` | multi | CF only | 3 composite | setUpdatedAt |
| `receipts` | multi | rules only | 3 composite | setUpdatedAt + recomputeReceiptStale |
| `documents` | multi | CF only | 3 composite | setUpdatedAt |
| `investment_scenarios` | multi | CRUD signed | 1 composite | setUpdatedAt |
| `paid_plan_interest` | singleton | CRUD account | — | — |
| **`support_requests`** | multi | **create-only** | **—** | **—** |

---

### `landlords/{uid}` — docId = Firebase Auth UID

Authentication + account tiers (anonymous/free/pro).

| Champ | Type | Valeur | Immuable | RLS |
|---|---|---|---|---|
| `id` | string | Firebase Auth UID | ✅ | isOwner(uid) |
| `email` | string? | null (anon) / email (compte) | ✅ | — |
| `fullName` | string | '' (anon) / nom complet | ✅ | — |
| `isAnonymous` | bool | true (essai) / false (compte) | ✅ | — |
| `subscriptionTier` | string | 'anonymous' / 'free' / 'pro' | ✅ | — |
| `anonExpiresAt` | timestamp | Expiration essai (14j) | — | — |
| `rgpdConsentAt` | timestamp? | null (anon) / date signature | ✅ | — |
| `rgpdConsentVersion` | string | Numéro contrat RGPD | ✅ | — |
| `createdAt` | timestamp | Création compte | ✅ | — |
| `updatedAt` | timestamp | Dernière modification | — | CF trigger |
| `deletedAt` | timestamp? | null (actif) / suppression | — | isActive(rsc) |

**RLS Rules** :
- `get` : isOwner(uid) && isActive(resource)
- `create` (compte) : isFullyAuthed() + RGPD consent obligatoire
- `create` (anonyme) : isAnonymous() + anonExpiresAt valide
- `update` (compte) : isFullyAuthed() && preservesImmutables()
- `update` (anonyme) : isAnonymous() && anonExpiresAt <= now + 15j
- `delete` : interdit (soft-delete via CF `softDeleteLandlord`)

**Indexes** :
- `isAnonymous, anonExpiresAt ASC` (cleanup expiration)

**Triggers** :
- setUpdatedAt (CF)

---

### `properties/{id}` — CRUD direct

Bien immobilier (appartement, maison, etc).

| Champ | Type | Notes |
|---|---|---|
| `id` | string | UUID, docId |
| `landlordId` | string | FK → landlords.id |
| `name` | string | Adresse ou nom |
| `address` | string | Complète (rue + code postal) |
| `type` | string | 'appartement' / 'maison' / 'studio' / 'autre' |
| `activeLeaseCount` | int | Denormalisé (CF) — CRUD client refusé |
| `createdAt` | timestamp | Création |
| `updatedAt` | timestamp | CF trigger |
| `deletedAt` | timestamp? | Soft-delete |

**RLS** :
- `get/list` : isOwner(landlordId) && isActive(resource)
- `create` : isFullyAuthed() + activeLeaseCount==0 à la création
- `update` : isFullyAuthed() + preservesImmutables()
- `delete` : interdit

**Indexes** :
- landlordId, deletedAt, name
- landlordId, deletedAt, createdAt DESC

---

### `tenants/{id}` — CRUD direct

Locataire.

| Champ | Type | Notes |
|---|---|---|
| `id` | string | UUID |
| `landlordId` | string | FK → landlords.id |
| `firstName` | string | Prénom |
| `lastName` | string | Nom |
| `email` | string | Valide regex |
| `activeLeaseCount` | int | Denormalisé |
| `createdAt` | timestamp | — |
| `updatedAt` | timestamp | CF trigger |
| `deletedAt` | timestamp? | Soft-delete |

**RLS** :
- `get/list` : isOwner(landlordId) && isActive(resource)
- `create` : isFullyAuthed() + activeLeaseCount==0
- `update` : isFullyAuthed() + preservesImmutables()
- `delete` : interdit

**Indexes** :
- landlordId, deletedAt, lastName
- landlordId, deletedAt, createdAt DESC

---

### `leases/{id}` — CROSS-ENTITY (CF exclusive)

Bail (lien bien ↔ locataire).

| Champ | Type | Notes |
|---|---|---|
| `id` | string | UUID |
| `landlordId` | string | FK → landlords.id |
| `propertyId` | string | FK → properties.id |
| `tenantId` | string | FK → tenants.id |
| `status` | string | 'ongoing' / 'upcoming' / 'ended' |
| `startDate` | date | Date début bail |
| `endDate` | date | Date fin bail |
| `monthlyRent` | int | En centimes |
| `charges` | int | En centimes |
| `createdAt` | timestamp | — |
| `updatedAt` | timestamp | CF trigger |
| `deletedAt` | timestamp? | Soft-delete |

**RLS** :
- `get/list` : isOwner(landlordId) && isActive(resource)
- `create/update/delete` : interdit (CF exclusive)

**Indexes** (composite) :
- landlordId, deletedAt, status, startDate DESC
- landlordId, propertyId, deletedAt
- landlordId, tenantId, deletedAt
- landlordId, status, endDate ASC
- landlordId, deletedAt, startDate DESC
- deletedAt, landlordId, status, endDate
- deletedAt, landlordId, status, startDate
- deletedAt, landlordId, tenantId, startDate DESC

---

### `payments/{id}` — CROSS-ENTITY (CF exclusive)

Paiement de loyer.

| Champ | Type | Notes |
|---|---|---|
| `id` | string | UUID |
| `landlordId` | string | FK → landlords.id |
| `leaseId` | string | FK → leases.id |
| `amount` | int | Montant en centimes |
| `paidAt` | timestamp | Date/heure paiement |
| `periodStart` | date | Début période couverte |
| `periodEnd` | date | Fin période couverte |
| `notes` | string? | **Motif paiement libre (FEAT-029)** — affiché quittance PDF |
| `createdAt` | timestamp | — |
| `updatedAt` | timestamp | CF trigger |
| `deletedAt` | timestamp? | Soft-delete |

**RLS** :
- `get/list` : isOwner(landlordId) && isActive(resource)
- `create/update/delete` : interdit (CF exclusive)

**Indexes** :
- landlordId, deletedAt, paidAt DESC
- landlordId, leaseId, deletedAt, paidAt DESC
- landlordId, leaseId, deletedAt, periodStart DESC
- landlordId, deletedAt, periodStart DESC
- deletedAt, landlordId, createdAt DESC
- deletedAt, landlordId, periodStart ASC
- deletedAt, landlordId, paidAt ASC

---

### `receipts/{id}` — IMMUABLES (CF exclusive)

Quittance de paiement (loi 6 juillet 1989 — rétention 5 ans).

| Champ | Type | Notes |
|---|---|---|
| `id` | string | UUID |
| `landlordId` | string | FK → landlords.id |
| `leaseId` | string | FK → leases.id |
| `paymentId` | string | FK → payments.id |
| `amount` | int | Montant en centimes |
| `periodStart` | date | Début période |
| `periodEnd` | date | Fin période |
| `isVoided` | bool | Annulé = création nouvelle + soft-delete paiment |
| `isStale` | bool | Périmé (recalc CF si paiement annulé ou loyer change) |
| `pdfUrl` | string? | Lien Storage (CF remplit) |
| `sentAt` | timestamp? | Envoi par email |
| `createdAt` | timestamp | — |
| `updatedAt` | timestamp | CF trigger |

**RLS** :
- `get/list` : isOwner(landlordId) (pas de deletedAt filtré — audit trail)
- `create/update/delete` : interdit (CF exclusive)

**Indexes** :
- landlordId, leaseId, periodStart DESC
- landlordId, periodStart DESC
- landlordId, isVoided, periodStart DESC
- landlordId, isStale, periodStart DESC

---

### `documents/{id}` — CF exclusive

Document (bail scanned, état des lieux, etc).

| Champ | Type | Notes |
|---|---|---|
| `id` | string | UUID |
| `landlordId` | string | FK → landlords.id |
| `leaseId` | string? | FK → leases.id (optionnel) |
| `category` | string | 'lease' / 'inventory' / 'other' |
| `legalHold` | bool | true = non-supprimable (rétention 3–7 ans) |
| `title` | string | Nom affichage |
| `storageUrl` | string | Lien Storage (CF) |
| `uploadedAt` | timestamp | — |
| `createdAt` | timestamp | — |
| `updatedAt` | timestamp | CF trigger |
| `deletedAt` | timestamp? | Soft-delete (refusé si legalHold==true) |

**RLS** :
- `get/list` : isOwner(landlordId) && isActive(resource)
- `create/update/delete` : interdit (CF exclusive)

**Indexes** :
- landlordId, leaseId, deletedAt, uploadedAt DESC
- landlordId, deletedAt, category
- deletedAt, landlordId, uploadedAt DESC

---

### `investment_scenarios/{id}` — CRUD direct

Simulateur d'investissement (accessible anonymes).

| Champ | Type | Notes |
|---|---|---|
| `id` | string | UUID |
| `landlordId` | string | FK → landlords.id |
| `name` | string | Nom scénario (120 chars max) |
| `schemaVersion` | int | Version structure JSON |
| `scenarioJson` | map | Inputs simulateur sérialisés |
| `createdAt` | timestamp | — |
| `updatedAt` | timestamp | CF trigger |
| `deletedAt` | timestamp? | Soft-delete |

**RLS** :
- `get/list` : isSignedIn() (anonymes + comptes)
- `create` : isSignedIn() (anonymes + comptes)
- `update` : isOwner(landlordId) + preservesImmutables()
- `delete` : interdit

**Indexes** :
- landlordId, deletedAt, updatedAt DESC

---

### `paid_plan_interest/{uid}` — BAILLAN-M1

Marque d'intérêt futur Plan Pro (docId = Firebase Auth UID).

| Champ | Type | Notes |
|---|---|---|
| `features` | array | Features souhaitées |
| `createdAt` | timestamp | — |

**RLS** :
- `get` : isOwner(uid)
- `create/update` : isFullyAuthed() && isOwner(uid)
- `delete` : interdit

---

### `support_requests/{id}` — CREATE-ONLY (FEAT-025)

Formulaire « Nous contacter ». Client écrit demande à son propre nom ; pas de back-office in-app V1. Traitement via Admin SDK / console + Trigger Email extension (notifications, V2).

| Champ | Type | Valeur | Immuable | Validation |
|---|---|---|---|---|
| `id` | string | UUID, docId | ✅ | auto |
| `landlordId` | string | Firebase Auth UID | ✅ | == request.auth.uid |
| `email` | string | Adresse email | ✅ | size() > 0 |
| `subject` | string | Objet message | ✅ | 0 < size() ≤ 120 |
| `message` | string | Corps message | ✅ | 0 < size() ≤ 2000 |
| `appVersion` | string | Version app (v1.0.0+BUILD) | ✅ | size() > 0 |
| `appEnv` | string | Environment (dev/staging/prod) | ✅ | size() > 0 |
| `status` | string | État traitement | ✅ | == 'new' (création) |
| `createdAt` | timestamp | Soumission | ✅ | == request.time |

**RLS** :
- `get` : false (pas relecture client)
- `list` : false
- `create` : isFullyAuthed() + isOwner(landlordId) + validations ci-dessus
- `update` : false
- `delete` : false

**Indexes** :
- None (V1 — pas de requêtes optimisées, accès Admin console/Cloud Function)

**Traitement V2** (post-M1) :
- Cloud Function listener sur `support_requests` create
- Appel Trigger Email extension → email propriétaire
- Update status → 'acknowledged' / 'resolved' (Admin SDK)

---

## Règles de sécurité (firestore.rules)

**3 couches** :
1. **Rules** (ce fichier) — ownership self + immuabilité base + soft-delete filter
2. **Callable Cloud Functions** — mutations cross-entity + soft-delete + denormalization
3. **Triggers Firestore** — setUpdatedAt + recomputeReceiptStale + propagation denorm

**Helpers clés** :
- `isSignedIn()` : user authentifié
- `isAnonymous()` : firebase.sign_in_provider == 'anonymous'
- `isFullyAuthed()` : signé && !anonyme
- `isOwner(uid)` : auth.uid == uid
- `isActive(rsc)` : rsc.data.deletedAt == null
- `preservesImmutables(rsc)` : landlordId, createdAt, deletedAt non modifiés

**Défense en profondeur** :
- Anonymes : jamais CRUD collections métier (properties, leases, etc.) — simulateur uniquement
- Immutables : landlordId, createdAt immuables côté client (CF bypass via Admin SDK)
- Soft-delete : aucune route client ne crée `deletedAt` (CF exclusive)
- Anonexpiresät : plafond now + 15j (tolérance décalage horloge vs renouvellement 14j CF)

---

## Cloud Functions (callables + triggers)

| Fonction | Type | Rôle |
|---|---|---|
| `handleNewUser` | auth trigger | Provisionne doc landlord post-signup |
| `setUpdatedAt*` | triggers (7×) | Maintient updatedAt à chaque write |
| `recomputeReceiptStale` | trigger | Marque quittances périmées |
| `createLease` | callable | Valide FK + crée lease + incrémente activeLeaseCount |
| `updateLease` | callable | Maj lease + recalc status |
| `createPayment` | callable | Crée payment + trigger generateReceipt |
| `updatePayment` | callable | Maj payment (rare — idempotent) |
| `generateReceipt` | callable | PDF + storage URL |
| `voidReceipt` | callable | Marque isVoided + crée remplacement |
| `markReceiptAsSent` | callable | Marque sentAt |
| `createDocument` | callable | Upload Storage + legalHold depuis category |
| `getDocumentDownloadUrl` | callable | Signe URL Storage (5 min) |
| `softDeleteEntity` | callable | Marque deletedAt (refus si legalHold==true) |
| `finalizeAnonymousUpgrade` | callable | Upgrade anon → fully authed (tier change + RGPD consent) |
| `cleanupExpiredAnon` | scheduled (cron) | Purge landlords anonymes expirés |

---

## Notes d'architecture

**Piège isEqualTo: null** :
- Firestore refus WHERE field == null sans index composite.
- Solution : `WHERE field == null` génère error ; utilise CF pour filtrer isActive() côté code.
- Tous les soft-deletes couverts par composite index (deletedAt, [autres fields]).
- Commits référence : 61a5956, 52a09c9, 85f1be2.

**Dénormalisation** :
- `activeLeaseCount` (properties, tenants) = recalc CF post create/soft-delete lease
- Quittances : `isStale` recalculé CF si paiement change
- Indexing : 28 composites documentent dépendance cf. firestore.indexes.json

**Anonyme (BAILLAN-M1)** :
- Essai 14j gratuit, renouvellable avant expiration
- Accès simulateur uniquement, pas de CRUD métier
- Upgrade → création compte full (transactionnel CF `finalizeAnonymousUpgrade`)
