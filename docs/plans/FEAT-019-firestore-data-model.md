# FEAT-019 — Firestore Data Model

> Architect : claude (opus). Date : 2026-06-30. Source : `docs/state/SCHEMA.md` (snapshot 2026-06-25) + `docs/plans/FEAT-018-simulator.md` (investment_scenarios).

## 0. Décisions ancrées

| Décision | Valeur | Justif |
|---|---|---|
| Pattern collections | **Top-level + `landlordId` field** | Requêtes filtrées simples, indexes composites globaux, pas de fan-out subcollection |
| Multi-env | **2 Firestore DBs séparées** : `(default)` = prod ; `dev` = dev | Plus de prefixes, Security Rules identiques, switching CLI propre |
| Région | `europe-west1` (Belgique) | Latence FR, RGPD UE |
| ID strategy | **Conserver UUID Supabase** comme docId | Compat URLs, idempotence migration, FK existantes |
| Soft-delete | Champ `deletedAt: Timestamp \| null` + indexes filtrant `deletedAt == null` | Mime le pattern Postgres |
| Money | `*Cents: number` (int) | Identique Postgres, pas de float |
| Tenant ↔ Landlord auth | `landlordId == request.auth.uid` dans Security Rules | Réplique RLS |

## 1. Collections — structure détaillée

Notation : `?` = nullable. `[IMMUTABLE]` = écriture interdite après création (Security Rules). `[DENORM]` = snapshot d'une autre collection.

### 1.1 `landlords/{uid}`

`docId` = `auth.uid` Firebase (Firebase Auth UID, **mapping** depuis Supabase `auth.users.id`).

```ts
{
  id: string,                          // == docId (redondant, utile pour collectionGroup)
  email: string,
  fullName: string,
  phone?: string,
  address?: string,
  rgpdConsentAt: Timestamp,            // [IMMUTABLE après init]
  rgpdConsentVersion: string,          // 'v1-2026-06' | 'legacy-1'
  createdAt: Timestamp,                // [IMMUTABLE]
  updatedAt: Timestamp,
  deletedAt: Timestamp | null
}
```

- Créé par **Cloud Function `onCreateUser`** (équivalent trigger `handle_new_user()`) — idempotent.
- Pas d'INSERT côté client ; UPDATE auto-soumis aux Security Rules `request.auth.uid == docId`.

### 1.2 `properties/{propertyId}`

```ts
{
  id: string,
  landlordId: string,                  // [IMMUTABLE] — FK
  name: string,
  address: string,
  type: 'appartement' | 'maison' | 'studio' | 'autre',
  surfaceM2?: number,
  rooms?: number,
  bedrooms?: number,
  floor?: number,
  hasElevator: boolean,
  furnished: boolean,
  heatingType?: 'electric'|'gas'|'collective'|'fuel'|'wood'|'heat_pump'|'other',
  dpeLetter?: 'A'|'B'|'C'|'D'|'E'|'F'|'G',
  dpeValueKwhM2Year?: number,
  gesLetter?: 'A'|'B'|'C'|'D'|'E'|'F'|'G',
  constructionYear?: number,
  postalCode?: string,                 // regex ^\d{5}$
  city?: string,
  createdAt: Timestamp,
  updatedAt: Timestamp,
  deletedAt: Timestamp | null,
  activeLeaseCount: number             // [DENORM] — maintenu par Cloud Function (cf. §2.2)
}
```

### 1.3 `tenants/{tenantId}`

```ts
{
  id: string,
  landlordId: string,                  // [IMMUTABLE]
  firstName: string,
  lastName: string,
  email: string,
  phone?: string,
  birthDate?: Timestamp,               // date YYYY-MM-DD en Timestamp UTC midi
  birthPlace?: string,
  nationality?: string,
  profession?: string,
  employer?: string,
  monthlyIncomeCents?: number,
  previousAddress?: string,
  guarantorName?: string,
  guarantorEmail?: string,
  guarantorPhone?: string,
  createdAt: Timestamp,
  updatedAt: Timestamp,
  deletedAt: Timestamp | null,
  activeLeaseCount: number             // [DENORM]
}
```

### 1.4 `leases/{leaseId}`

```ts
{
  id: string,
  landlordId: string,                  // [IMMUTABLE]
  propertyId: string,                  // [IMMUTABLE]
  tenantId: string,                    // [IMMUTABLE]

  // [DENORM] snapshots — évite N lectures sur listing cards (FEAT-012)
  propertyName: string,
  propertyAddress: string,
  tenantFirstName: string,
  tenantLastName: string,
  tenantEmail: string,

  rentAmountCents: number,             // > 0
  chargesAmountCents: number,          // >= 0
  startDate: Timestamp,                // [IMMUTABLE après émission de la 1re quittance] — cf. §2.3
  endDate?: Timestamp,
  status: 'active'|'terminated'|'archived',

  leaseType: 'unfurnished'|'furnished'|'mobility'|'student',
  depositAmountCents?: number,
  paymentDay: number,                  // 1..28
  paymentMethod: 'virement'|'cheque'|'especes'|'prelevement'|'autre',
  irlIndexValue?: number,
  irlQuarterRef?: string,              // ^T[1-4]-\d{4}$
  agencyFeesCents: number,
  solidarityClause: boolean,
  entryInventoryDone: boolean,

  createdAt: Timestamp,
  updatedAt: Timestamp,
  deletedAt: Timestamp | null
}
```

### 1.5 `payments/{paymentId}`

```ts
{
  id: string,
  landlordId: string,                  // [IMMUTABLE]
  leaseId: string,                     // [IMMUTABLE]

  // [DENORM] pour timeline + tri sans join
  propertyName: string,
  tenantLastName: string,

  periodStart: Timestamp,              // [IMMUTABLE] — loi 1989 ancrage période
  periodEnd: Timestamp,                // [IMMUTABLE]
  paidAt: Timestamp,
  rentAmountCents: number,             // > 0 [IMMUTABLE]
  chargesAmountCents: number,          // [IMMUTABLE]
  paymentMethod: string,
  notes?: string,
  reference?: string,                  // numéro de chèque/virement
  createdAt: Timestamp,
  updatedAt: Timestamp,
  deletedAt: Timestamp | null
}
```

### 1.6 `receipts/{receiptId}` — **document légal immuable**

```ts
{
  id: string,
  landlordId: string,                  // [IMMUTABLE]
  leaseId: string,                     // [IMMUTABLE]
  paymentIds: string[],                // [IMMUTABLE] — array, >=1, max ~20 paiements/quittance

  // [DENORM] snapshot complet à l'émission — loi 6 juillet 1989
  // (jamais re-synchronisé même si le lease change ensuite)
  propertyName: string,                // [IMMUTABLE]
  propertyAddress: string,             // [IMMUTABLE]
  landlordFullName: string,            // [IMMUTABLE]
  tenantFullName: string,              // [IMMUTABLE]

  periodStart: Timestamp,              // [IMMUTABLE]
  periodEnd: Timestamp,                // [IMMUTABLE]
  rentCents: number,                   // [IMMUTABLE]
  chargesCents: number,                // [IMMUTABLE]
  totalCents: number,                  // [IMMUTABLE] = rent+charges
  documentType: 'quittance' | 'recu',  // [IMMUTABLE]
  pdfPath: string,                     // [IMMUTABLE] — receipts/{landlordId}/{receiptId}.pdf

  generatedAt: Timestamp,              // [IMMUTABLE]
  createdAt: Timestamp,                // [IMMUTABLE]

  // Flags mutables (via Cloud Function uniquement)
  isVoided: boolean,
  voidedAt: Timestamp | null,
  voidedReason: string | null,
  isStale: boolean,                    // marqué true si un payment est soft-deleted
  sentAt: Timestamp | null,
  sentToEmail: string | null
}
```

**Pas de `deletedAt`** : receipts ne se suppriment **jamais** (rétention légale 5 ans).

### 1.7 `documents/{documentId}`

```ts
{
  id: string,
  landlordId: string,                  // [IMMUTABLE]
  leaseId: string,                     // [IMMUTABLE]
  category: 'bail_signe'|'etat_des_lieux'|'attestation_assurance'|'quittance_scannee'|'autre',
  filename: string,                    // [IMMUTABLE]
  storagePath: string,                 // [IMMUTABLE]
  mimeType: 'application/pdf'|'image/jpeg'|'image/png'|'image/webp', // [IMMUTABLE]
  sizeBytes: number,                   // [IMMUTABLE]
  legalHold: boolean,                  // [IMMUTABLE] — true ssi category ∈ {bail_signe, etat_des_lieux}
  uploadedAt: Timestamp,               // [IMMUTABLE]
  createdAt: Timestamp,                // [IMMUTABLE]
  updatedAt: Timestamp,
  deletedAt: Timestamp | null          // null si legalHold=true (interdit hard-delete)
}
```

Storage path : `{env}/{landlordId}/{documentId}.{ext}` — bucket Firebase Storage avec règles MIME + 10MB max.

### 1.8 `investment_scenarios/{scenarioId}` (FEAT-018)

```ts
{
  id: string,
  landlordId: string,                  // [IMMUTABLE]
  name: string,                        // 1..120
  scenarioJson: object,                // map Firestore (≤ 1 MiB)
  schemaVersion: number,               // >0
  notes?: string,                      // ≤ 2000
  createdAt: Timestamp,
  updatedAt: Timestamp,
  deletedAt: Timestamp | null
}
```

## 2. Relations cross-collection

### 2.1 Modèle de référence
Pas de Firestore `reference` field (overkill). On stocke des `string` ids — la lib Dart fait la résolution côté client.

### 2.2 Propagation des dénormalisations (snapshot vs sync)

| Champ source | Champs miroirs | Stratégie |
|---|---|---|
| `properties.name`, `properties.address` | `leases.propertyName/Address`, `payments.propertyName` | **Cloud Function `onUpdate(properties)`** — fan-out batch sur leases actifs + payments des 6 derniers mois (limite 500/batch). Receipts **jamais** mises à jour (immuables). |
| `tenants.firstName/lastName/email` | `leases.tenant*`, `payments.tenantLastName` | **Cloud Function `onUpdate(tenants)`** — même pattern. |
| `landlords.fullName` | `receipts.landlordFullName` | **Aucune propagation** (immutable, snapshot légal). |

Performance : tous les listings (FEAT-012 cards) lisent **uniquement** les denorms → 1 query au lieu de N.

### 2.3 Soft-delete avec dépendances (équivalent FK RESTRICT)

| Action | Garde-fou |
|---|---|
| Soft-delete `properties` avec `activeLeaseCount > 0` | **Cloud Function** rejette + retourne erreur 'property_has_active_leases'. Le compteur denorm est maintenu par les fonctions onCreate/onDelete(leases). |
| Soft-delete `tenants` avec `activeLeaseCount > 0` | Idem. |
| Soft-delete `leases` avec `payments` (non-deleted) | Autorisé (mime Postgres : on soft-delete le lease, les payments restent visibles pour archive). |
| Soft-delete `payment` lié à une `receipt` | Cloud Function pose `receipts.isStale = true` (réplique trigger `tr_03`). |
| Hard-delete `documents` avec `legalHold=true` | **Interdit** Security Rules + Cloud Function refuse. |

Tous ces gardes sont en **Cloud Functions callable** ou en **Security Rules** (pas de trigger Postgres équivalent → fonction métier).

## 3. Indexes composites

Firestore génère automatiquement les indexes single-field. Les **composites** doivent être déclarés dans `firestore.indexes.json`. Liste exhaustive dérivée des écrans FEAT-012 et des queries existantes.

| # | Collection | Champs (order) | Usage |
|---|---|---|---|
| 1 | `properties` | `landlordId ASC, deletedAt ASC, name ASC` | Liste properties triées alpha |
| 2 | `properties` | `landlordId ASC, deletedAt ASC, createdAt DESC` | Liste properties tri création |
| 3 | `tenants` | `landlordId ASC, deletedAt ASC, lastName ASC` | Liste tenants triés alpha |
| 4 | `tenants` | `landlordId ASC, deletedAt ASC, createdAt DESC` | Liste tenants tri création |
| 5 | `leases` | `landlordId ASC, deletedAt ASC, status ASC, startDate DESC` | Cards FEAT-012 phase1 (filtre status) |
| 6 | `leases` | `landlordId ASC, propertyId ASC, deletedAt ASC` | Leases d'une property (detail page) |
| 7 | `leases` | `landlordId ASC, tenantId ASC, deletedAt ASC` | Leases d'un tenant (detail page) |
| 8 | `leases` | `landlordId ASC, status ASC, endDate ASC` | Filtre baux qui se terminent bientôt (dashboard) |
| 9 | `payments` | `landlordId ASC, deletedAt ASC, paidAt DESC` | Timeline globale dashboard |
| 10 | `payments` | `landlordId ASC, leaseId ASC, deletedAt ASC, paidAt DESC` | Timeline paiements d'un bail (detail) |
| 11 | `payments` | `landlordId ASC, leaseId ASC, deletedAt ASC, periodStart DESC` | Tri par période (regroupement quittance) |
| 12 | `payments` | `landlordId ASC, deletedAt ASC, periodStart DESC` | Stats portfolio par période |
| 13 | `receipts` | `landlordId ASC, leaseId ASC, periodStart DESC` | Timeline quittances d'un bail (FEAT-012 phase 4) |
| 14 | `receipts` | `landlordId ASC, periodStart DESC` | Liste globale receipts |
| 15 | `receipts` | `landlordId ASC, isVoided ASC, periodStart DESC` | Filtrer valides vs annulées |
| 16 | `receipts` | `landlordId ASC, isStale ASC, periodStart DESC` | Alertes quittances obsolètes |
| 17 | `documents` | `landlordId ASC, leaseId ASC, deletedAt ASC, uploadedAt DESC` | Liste documents d'un bail |
| 18 | `documents` | `landlordId ASC, deletedAt ASC, category ASC` | Filtre par catégorie (quota par type) |
| 19 | `investment_scenarios` | `landlordId ASC, deletedAt ASC, updatedAt DESC` | Liste scénarios récents |

**Total : 19 indexes composites.** Single-field auto pour : `id`, `landlordId`, `createdAt`, `updatedAt`, `deletedAt`, `status`, `category`, etc.

## 4. Migration data plan

### 4.1 Mapping champ-à-champ (résumé)

| Postgres | Firestore | Transformation |
|---|---|---|
| `id uuid` | docId | identique |
| `landlord_id uuid` | `landlordId` | identique |
| `*_cents integer` | `*Cents: number` | identique |
| `created_at timestamptz` | `createdAt: Timestamp` | `Timestamp.fromDate(...)` |
| `date` (period_start, paid_at) | `Timestamp` UTC midi | `Timestamp.fromMillis(date.getTime())` |
| `text[]` (payment_ids) | `string[]` | identique |
| `boolean` | `boolean` | identique |
| `enum` (document_category, document_type) | `string` | identique (Security Rules valident) |
| `jsonb` (scenario_json) | `map` | parsing JSON → Firestore map |
| FK (`property_id`, `tenant_id`, `lease_id`) | `string` field | identique + ajout denorm snapshot |

### 4.2 Stratégie ETL

**Choix : Node.js script standalone** (pas Cloud Function batch).

Justifications :
- Volume MVP < 10k docs/collection → fits dans 1 process
- Contrôle full sur l'ordre (landlords → properties+tenants → leases → payments → receipts → documents → scenarios)
- Re-runs idempotents (Firestore `.set()` avec UUID conservés)
- Logs locaux, rollback facile (script peut hard-delete sa propre run via marker `migrationBatchId`)
- Cloud Function 9min timeout serait risqué

**Script** : `scripts/migrate-supabase-to-firestore.ts`

Pipeline :
1. **Pre-flight** : dump Postgres → JSON par table (via `supabase db dump --data-only` ou `pg_dump -t`).
2. **Validation** : sanity checks (count rows, FK integrity, no orphan denorms).
3. **Auth mapping** : `auth.users.id → firebaseAuth.uid` — table de correspondance générée par un Cloud Function qui crée chaque user Firebase Auth depuis email + envoie email reset password.
4. **Write order** :
   1. `landlords` (clé étrangère de tout le reste — set avec docId = firebase uid)
   2. `properties` + `tenants` (parallèle)
   3. `leases` (calcul des denorms en lisant les 2 collections précédentes en mémoire)
   4. `payments` + `documents` (parallèle, lisent `leases` en mémoire pour denorms)
   5. `receipts` (lisent `leases` + `landlords` pour snapshot complet immuable)
   6. `investment_scenarios`
5. **Batch writes** : `WriteBatch` Firestore (500 ops max) — boucle par chunks.
6. **Post-flight** : reconciliation count Firestore vs Postgres → assertion `assert(firestoreCount == postgresCount)` par collection.
7. **Index build** : `firebase deploy --only firestore:indexes` **avant** la migration (build en arrière-plan ~minutes pour MVP volume).

**Estimation durée** : < 10 minutes pour 10k docs total.

**Rollback** : la stratégie est "Postgres reste source de vérité durant la phase de bascule" — l'app peut switcher data source via feature flag `useFirestore` côté Flutter. En cas de problème : flag à false, données Postgres intactes.

## 5. Security Rules — squelette

```
match /databases/{db}/documents {
  match /landlords/{uid} {
    allow read, update: if request.auth.uid == uid && resource.data.deletedAt == null;
    allow create, delete: if false;     // create via Cloud Function, delete via RPC soft-delete
  }
  match /{col}/{id} where col in ['properties','tenants','leases','payments','documents','investment_scenarios'] {
    allow read: if isOwner() && resource.data.deletedAt == null;
    allow create: if isOwner() && request.resource.data.deletedAt == null;
    allow update: if isOwner()
                  && resource.data.deletedAt == null
                  && request.resource.data.landlordId == resource.data.landlordId
                  && request.resource.data.createdAt == resource.data.createdAt;
    allow delete: if false;             // soft-delete via Callable Function uniquement
  }
  match /receipts/{id} {
    allow read: if isOwner();           // pas de filtre deletedAt (pas de soft-delete)
    allow create: if isOwner();
    allow update, delete: if false;     // immuable; voiding via Callable
  }
}
function isOwner() {
  return request.auth != null
    && request.resource.data.landlordId == request.auth.uid;
}
```

## 6. Risques résiduels

1. **Dénormalisation drift** : si une Cloud Function de propagation échoue silencieusement, les denorms divergent. → Mitigation : ajouter un cron de réconciliation hebdo + tests E2E.
2. **Émulation `FK RESTRICT`** : sans contrainte DB, c'est la responsabilité applicative. Un bug dans la Cloud Function de soft-delete pourrait laisser des leases orphelins.
3. **Limites Firestore** : doc ≤ 1 MiB (gros `scenario_json` ou nombreux `paymentIds` → OK pour MVP, à monitorer).
4. **Transactions cross-collection** : un soft-delete `lease` + flag `isStale` sur N receipts dépasse vite la limite de 500 ops/transaction. → batcher.
5. **Coûts reads** : indexes composites avec `landlordId` premier → reads facturées. Avec FEAT-012 cards (1-2 listings + 1-2 detail pages par session), on reste largement sous la facturation significative.
6. **Backfill `activeLeaseCount`** : à initialiser pendant la migration ; si bug, denorm faux.
7. **Index build delay** : sur volume futur (> 100k docs), build initial peut prendre des heures. À faire en amont.
