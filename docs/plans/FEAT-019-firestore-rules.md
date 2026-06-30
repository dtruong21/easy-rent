# FEAT-019 — Firestore Security Rules (remplacement RLS Supabase)

> **Auteur** : architect-security
> **Date** : 2026-06-30
> **Scope** : 8 collections Firestore reproduisant 27 policies RLS Supabase + invariants loi 1989
> **Stratégie** : Rules pour CRUD basique + Callable Cloud Functions (Admin SDK) pour mutations sensibles

---

## Modèle de données Firestore

Collections top-level (pas de sous-collections — facilite les requêtes cross-collection) :

| Collection | Doc ID | landlord_id field | Soft-delete | Mutations sensibles |
|---|---|---|---|---|
| `landlords` | `auth.uid()` | `id` (= doc ID) | RPC only | RGPD consent versionné |
| `properties` | autogen | `landlordId` | RPC only | — |
| `tenants` | autogen | `landlordId` | RPC only | — |
| `leases` | autogen | `landlordId` | RPC only | Cross-entity (property + tenant ownership) |
| `payments` | autogen | `landlordId` | RPC only | Cross-entity (lease ownership) |
| `receipts` | autogen | `landlordId` | **Immuable** (loi 1989) | Génération + voiding + send via CF |
| `documents` | autogen | `landlordId` | RPC only (legal_hold check) | Immutabilité 5 cols + legal_hold |
| `userMetadata` (optionnel) | `auth.uid()` | — | — | RGPD consent capture |

**Convention de nommage** : camelCase pour les champs Firestore (vs snake_case Postgres) — `landlordId`, `deletedAt`, `createdAt`, `paymentIds`, `periodStart`, `totalCents`, etc.

---

## Architecture de sécurité — 3 couches

```
┌─────────────────────────────────────────────────────────────┐
│  Couche 1 — Firestore Security Rules (déclaratif, fast)     │
│  • Ownership check (landlordId == auth.uid())                │
│  • Soft-delete filter (deletedAt == null)                    │
│  • Immutabilité de base (landlordId, createdAt jamais modif) │
│  • Whitelist de champs mutables sur update                   │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│  Couche 2 — Callable Cloud Functions (Admin SDK, sécurisé)  │
│  • softDelete<Entity>(id)        — seul chemin vers deletedAt│
│  • generateReceipt(leaseId, ...) — création atomique receipt│
│  • voidReceipt(id, reason)       — voiding (immuable autrement)│
│  • markReceiptAsSent(id, email)  — sent_at + sent_to_email   │
│  • acceptRgpdConsent(version)    — rgpd_consent_at/version   │
│  Toutes : context.auth check + cross-entity validation       │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│  Couche 3 — Firestore Triggers (onCreate/onUpdate, audit)   │
│  • Detection mutations interdites → log + alerting          │
│  • Recompute is_stale sur payment.deletedAt (FEAT-007)      │
└─────────────────────────────────────────────────────────────┘
```

**Principe** : Rules bloquent 95% des attaques (cross-user, mutation immuable, soft-delete bypass). Les 5% restants (cross-entity, génération atomique multi-doc) passent par Cloud Functions où la logique métier vit en Dart/TS avec full Admin SDK.

---

## `firestore.rules` complet

```rules
rules_version = '2';

service cloud.firestore {
  match /databases/{database}/documents {

    // ========================================================================
    // Helpers globaux
    // ========================================================================
    function isSignedIn() {
      return request.auth != null;
    }

    function isOwner(landlordId) {
      return isSignedIn() && request.auth.uid == landlordId;
    }

    function isActive(resource) {
      return resource.data.deletedAt == null;
    }

    // Whitelist des champs qu'un client peut écrire (ban des champs serveur-only)
    function noServerOnlyFields(data) {
      return !data.diff(resource.data).affectedKeys()
        .hasAny(['createdAt', 'deletedAt', 'landlordId']);
    }

    // Pour create : empêche le client de set des champs immuables ou serveur-only
    function createNoServerFields(data, allowedDeletedAt) {
      return data.deletedAt == null
        && data.createdAt is timestamp
        // createdAt sera overwritten par CF si fraude — on tolère + audit
        && data.landlordId == request.auth.uid;
    }

    // ========================================================================
    // landlords/{uid}
    // ========================================================================
    match /landlords/{uid} {
      allow get: if isOwner(uid) && isActive(resource);
      allow list: if false; // pas de listing — chaque user ne voit que lui-même

      // CREATE interdit côté client — handled par Cloud Function `onAuthUserCreate`
      // (mirror de Supabase `handle_new_user()` trigger)
      allow create: if false;

      // UPDATE : profil propre, jamais id ni rgpd_consent_* ni deletedAt
      allow update: if isOwner(uid)
        && isActive(resource)
        && request.resource.data.id == resource.data.id
        && request.resource.data.deletedAt == resource.data.deletedAt
        && request.resource.data.createdAt == resource.data.createdAt
        && request.resource.data.rgpdConsentAt == resource.data.rgpdConsentAt
        && request.resource.data.rgpdConsentVersion == resource.data.rgpdConsentVersion;

      // DELETE interdit — soft-delete via CF `softDeleteLandlord`
      allow delete: if false;
    }

    // ========================================================================
    // properties/{id}
    // ========================================================================
    match /properties/{id} {
      allow get: if isOwner(resource.data.landlordId) && isActive(resource);
      allow list: if isSignedIn(); // filtré par query .where('landlordId','==',uid)

      allow create: if isSignedIn()
        && request.resource.data.landlordId == request.auth.uid
        && request.resource.data.deletedAt == null
        && request.resource.data.name is string
        && request.resource.data.name.size() > 0
        && request.resource.data.address is string
        && request.resource.data.type in ['appartement','maison','studio','autre'];

      allow update: if isOwner(resource.data.landlordId)
        && isActive(resource)
        && request.resource.data.landlordId == resource.data.landlordId
        && request.resource.data.deletedAt == resource.data.deletedAt
        && request.resource.data.createdAt == resource.data.createdAt;

      allow delete: if false; // soft-delete via CF
    }

    // ========================================================================
    // tenants/{id}
    // ========================================================================
    match /tenants/{id} {
      allow get: if isOwner(resource.data.landlordId) && isActive(resource);
      allow list: if isSignedIn();

      allow create: if isSignedIn()
        && request.resource.data.landlordId == request.auth.uid
        && request.resource.data.deletedAt == null
        && request.resource.data.firstName is string
        && request.resource.data.firstName.size() > 0
        && request.resource.data.lastName is string
        && request.resource.data.email is string
        && request.resource.data.email.matches('^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$');

      allow update: if isOwner(resource.data.landlordId)
        && isActive(resource)
        && request.resource.data.landlordId == resource.data.landlordId
        && request.resource.data.deletedAt == resource.data.deletedAt
        && request.resource.data.createdAt == resource.data.createdAt;

      allow delete: if false;
    }

    // ========================================================================
    // leases/{id} — CROSS-ENTITY guard via Cloud Function uniquement
    // ========================================================================
    match /leases/{id} {
      allow get: if isOwner(resource.data.landlordId) && isActive(resource);
      allow list: if isSignedIn();

      // CREATE et UPDATE bloqués côté Rules — must go via CF `createLease` / `updateLease`
      // qui valide propertyId.landlordId == tenantId.landlordId == uid via Admin SDK
      // → évite 2 reads get() coûteux dans Rules + impossibilité de checker dans Rules
      //   que tenant et property existent ET ne sont pas soft-deleted
      allow create: if false;
      allow update: if false;
      allow delete: if false;
    }

    // ========================================================================
    // payments/{id} — CROSS-ENTITY guard (lease.landlordId)
    // ========================================================================
    match /payments/{id} {
      allow get: if isOwner(resource.data.landlordId) && isActive(resource);
      allow list: if isSignedIn();

      // Option A retenue : CF exclusive (cf. section "Cross-entity guards" ci-dessous)
      allow create: if false;
      allow update: if false;
      allow delete: if false;
    }

    // ========================================================================
    // receipts/{id} — IMMUABLES (loi 1989). CF exclusive.
    // ========================================================================
    match /receipts/{id} {
      allow get: if isOwner(resource.data.landlordId);
      // Listing TOUTES les receipts (y compris voided) — diff vs payments
      allow list: if isSignedIn();

      // Aucune écriture client. Tout passe par CF :
      //   • generateReceipt → create
      //   • voidReceipt → update (is_voided, voided_at, voided_reason)
      //   • markReceiptAsSent → update (sent_at, sent_to_email)
      //   • Recompute is_stale → CF trigger onUpdate(payments)
      allow create, update, delete: if false;
    }

    // ========================================================================
    // documents/{id} — Immutabilité 5 colonnes + legal_hold
    // ========================================================================
    match /documents/{id} {
      allow get: if isOwner(resource.data.landlordId) && isActive(resource);
      allow list: if isSignedIn();

      // CREATE : CF exclusive (calcule legal_hold depuis category, valide lease ownership)
      allow create: if false;

      // UPDATE : seule `category` est mutable — mais legal_hold dépend de category,
      // donc en pratique on bloque update client et on force CF
      allow update: if false;

      allow delete: if false;
    }

    // ========================================================================
    // Fallback : tout le reste interdit
    // ========================================================================
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

---

## Invariants critiques loi 1989 — receipts

**Champs immuables après création** : `paymentIds`, `periodStart`, `periodEnd`, `rentCents`, `chargesCents`, `totalCents`, `documentType`, `pdfPath`, `generatedAt`, `landlordId`, `leaseId`.

**Champs mutables sous contrôle CF** : `isVoided` + `voidedAt` + `voidedReason` (atomique), `sentAt` + `sentToEmail` (atomique), `isStale` (recompute trigger).

### Approche recommandée : **Callable Cloud Function exclusive (Admin SDK)**

Rules bloquent **toutes** les écritures sur `receipts` (`create, update, delete: if false`). Le client appelle :

```ts
// functions/src/receipts.ts
export const generateReceipt = onCall({ region: 'europe-west1' }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', '...');
  const uid = request.auth.uid;
  const { leaseId, paymentIds, periodStart, periodEnd } = request.data;

  // 1. Validation lease ownership (cross-entity)
  const leaseSnap = await db.doc(`leases/${leaseId}`).get();
  if (!leaseSnap.exists || leaseSnap.data().landlordId !== uid) {
    throw new HttpsError('permission-denied', 'lease ownership');
  }

  // 2. Validation payment_ids ownership + same lease
  const paymentDocs = await db.getAll(...paymentIds.map(pid => db.doc(`payments/${pid}`)));
  for (const p of paymentDocs) {
    if (!p.exists || p.data().landlordId !== uid || p.data().leaseId !== leaseId) {
      throw new HttpsError('permission-denied', 'payment ownership/lease mismatch');
    }
  }

  // 3. Compute totals + write atomique
  const rentCents = paymentDocs.reduce((s, p) => s + p.data().rentAmountCents, 0);
  const chargesCents = paymentDocs.reduce((s, p) => s + p.data().chargesAmountCents, 0);

  return await db.collection('receipts').add({
    landlordId: uid, leaseId, paymentIds, periodStart, periodEnd,
    rentCents, chargesCents, totalCents: rentCents + chargesCents,
    documentType: 'quittance',
    generatedAt: FieldValue.serverTimestamp(),
    createdAt: FieldValue.serverTimestamp(),
    isVoided: false, voidedAt: null, voidedReason: null,
    isStale: false, sentAt: null, sentToEmail: null,
    pdfPath: `receipts/${uid}/${docId}.pdf`,
  });
});
```

### Comparaison Rules-only vs CF-exclusive

| Aspect | Rules-only (whitelist update) | **CF exclusive (retenu)** |
|---|---|---|
| Surface attaque | Élevée (tout client peut tenter write) | Minimale (`write: if false`) |
| Validation cross-entity | Coûteux (`get()` × 2-N, +50ms par read) | Admin SDK natif, 1 batch read |
| Atomicité multi-doc | Impossible (Rules = single doc) | `db.runTransaction()` natif |
| Computation server-side (totals) | Impossible (client envoie totalCents) | Fait côté serveur |
| Code review / audit | Rules lisibles mais complexes | Code TS testable unitairement |
| Évolution (FEAT-008 sent_at) | Trigger PG + GUC bypass | Nouvelle CF, propre |
| Coût Firestore | 0 (Rules `get()` gratuit jusqu'à 10/req) | 1 read + 1 write par opération |

**→ Recommandation forte : CF exclusive.** La surface d'attaque réduite, l'atomicité native et la maintenance long-terme dominent largement le coût marginal d'un appel Cloud Function (€0.0000004/invocation).

---

## Cross-entity guards (payment → lease ownership)

**Problème Supabase** : `assert_payment_lease_ownership()` trigger SECURITY DEFINER vérifie que `payment.lease_id.landlord_id == payment.landlord_id` à chaque INSERT/UPDATE.

### Approche A — `get()` dans Rules

```rules
match /payments/{id} {
  allow create: if isSignedIn()
    && request.resource.data.landlordId == request.auth.uid
    && get(/databases/$(database)/documents/leases/$(request.resource.data.leaseId))
         .data.landlordId == request.auth.uid
    && get(/databases/$(database)/documents/leases/$(request.resource.data.leaseId))
         .data.deletedAt == null;
}
```

**Limites** :
- Chaque `get()` = 1 read facturé + ~50ms latence + 10 `get()`/request max.
- 2 `get()` identiques dans une seule rule → comptés 2× (pas de mémoïsation pré 2025).
- Pas possible de valider que `paymentIds[]` (array sur receipts) sont tous owned — Rules ne peuvent pas itérer.

### Approche B — Cloud Function blocking (recommandée)

Rules bloquent : `allow create, update: if false` sur `payments`, `leases`, `documents`, `receipts`.
Toutes les mutations passent par CF Callable :
- `createPayment({ leaseId, ... })` → CF lit lease, vérifie ownership, écrit payment via Admin SDK
- `createLease({ propertyId, tenantId, ... })` → CF lit property + tenant, vérifie ownership croisé
- `createDocument({ leaseId, ... })` → CF lit lease, calcule `legalHold` depuis `category`

| Critère | A (`get()` Rules) | **B (CF blocking) — retenu** |
|---|---|---|
| Coût read | 1-2 reads / mutation client | 1 read Admin SDK / mutation |
| Latence | +50-100ms par rule eval | +200-300ms cold start, ~50ms warm |
| Atomicité (array `paymentIds`) | Impossible | Transaction native |
| Soft-deleted check | Possible mais ajoute 1 `get()` | Trivial (1 read serveur) |
| Validation regex/range métier | Lisible | TS/Dart côté CF (testable) |
| Surface attaque | Moyenne (client peut tenter et observer) | Minimale (`write: if false`) |

**→ Recommandation : Approche B (CF blocking).** Cohérent avec la stratégie CF-exclusive sur `receipts`. Permet de centraliser **toute** la logique métier (validation regex postal_code, DPE A-G, montants > 0, etc.) qu'on devrait dupliquer entre Rules et client.

**Exception tolérée** : `properties`, `tenants` peuvent rester en CRUD direct via Rules — pas de cross-entity à valider, seulement ownership self.

---

## Migration mapping Supabase → Firestore

| RLS Supabase | Firestore équivalent |
|---|---|
| `SELECT WHERE landlord_id = auth.uid()` | `allow get: if isOwner(resource.data.landlordId)` + query `.where('landlordId','==',uid)` |
| `INSERT WITH CHECK landlord_id = auth.uid()` | `allow create: if request.resource.data.landlordId == request.auth.uid` |
| `UPDATE USING + WITH CHECK` | `allow update: if isOwner(...) && immutable fields == old` |
| `tr_01_prevent_protected_columns_change` (deleted_at, created_at) | Rules whitelist : `request.resource.data.deletedAt == resource.data.deletedAt` |
| `assert_payment_lease_ownership()` trigger | CF blocking `createPayment` lit `leases/{id}` Admin SDK |
| `assert_lease_ownership_consistency()` | CF blocking `createLease` lit property + tenant |
| `assert_receipt_lease_ownership()` | CF `generateReceipt` |
| `soft_delete_X()` RPC + GUC `allow_deleted_at_change` | CF `softDeleteX(id)` Admin SDK |
| `void_receipt()` RPC | CF `voidReceipt(id, reason)` |
| `mark_receipt_as_sent()` RPC | CF `markReceiptAsSent(id, email)` |
| `tr_03_set_receipt_stale_on_payment_archive` | Firestore trigger `onUpdate(payments/{id})` |
| `tr_00b_compute_legal_hold` | CF `createDocument` calcule legalHold avant write |
| `tr_01b_protect_immutable_documents` | Rules : `allow update: if false` sur documents |
| `handle_new_user()` trigger | Auth trigger `onCreate(user)` → write `landlords/{uid}` |

---

## Tests émulateur — 10 scénarios cross-user à automatiser

Utiliser `@firebase/rules-unit-testing` + `firebase emulators:exec`. Setup : 2 users U1 et U2, données préseed.

1. **CROSS-USER READ — properties**
   - U1 crée `properties/P1` (landlordId=U1).
   - U2 fait `db.doc('properties/P1').get()` → **doit échouer** (permission-denied).
   - U2 query `.where('landlordId','==','U1')` → **doit retourner 0 docs**.

2. **CROSS-USER UPDATE — tenants**
   - U1 crée `tenants/T1`. U2 fait `update({ firstName: 'hacked' })` → **doit échouer**.

3. **SOFT-DELETE FILTER — leases**
   - U1 crée `leases/L1`, CF `softDeleteLease(L1)` → `deletedAt` set.
   - U1 `db.doc('leases/L1').get()` → **doit échouer** (isActive false).
   - U1 query `.where('landlordId','==','U1')` → L1 **absent** (filtré).

4. **IMMUTABILITY — receipts**
   - U1 a un receipt R1 généré via CF. U1 tente `update({ totalCents: 1 })` → **doit échouer** (write: if false).
   - U1 tente `update({ paymentIds: [] })` → **doit échouer**.
   - U1 tente `delete()` → **doit échouer**.

5. **VOID RECEIPT — flow CF only**
   - U1 appelle CF `voidReceipt(R1, reason="erreur")` → succès, `isVoided=true`.
   - U2 appelle CF `voidReceipt(R1)` → **doit échouer** (CF ownership check).

6. **CROSS-ENTITY — payment.leaseId**
   - U1 a `leases/L1`. U2 appelle CF `createPayment({ leaseId: 'L1', ... })` → **doit échouer** (CF cross-entity).
   - U1 tente `db.collection('payments').add({ landlordId: 'U1', leaseId: 'L1', ... })` direct → **doit échouer** (Rules `create: if false`).

7. **CROSS-ENTITY — lease.propertyId + lease.tenantId**
   - U1 a `properties/P1`. U2 a `tenants/T2`. U1 appelle CF `createLease({ propertyId: P1, tenantId: T2 })` → **doit échouer** (T2 owned by U2).

8. **PROTECTED COLUMNS — properties**
   - U1 crée `properties/P1` puis tente `update({ createdAt: timestamp(2020) })` → **doit échouer**.
   - U1 tente `update({ landlordId: 'U2' })` (transfert) → **doit échouer**.
   - U1 tente `update({ deletedAt: serverTimestamp() })` direct → **doit échouer** (soft-delete CF only).

9. **LANDLORDS — RGPD consent immutable client-side**
   - U1 tente `update({ rgpdConsentVersion: 'fake' })` → **doit échouer**.
   - U1 tente `update({ id: 'U2' })` → **doit échouer**.
   - U1 update `{ phone: '06...' }` → **succès**.

10. **DOCUMENTS — legal_hold immutability**
    - U1 crée `documents/D1` (category=`bail_signe`, legalHold=true) via CF.
    - U1 tente `update({ category: 'autre' })` direct → **doit échouer** (`update: if false`).
    - U1 appelle CF `softDeleteDocument(D1)` → renvoie `{ hardDeleted: false }` (legal_hold actif).
    - U1 crée `documents/D2` (category=`autre`, legalHold=false), CF `softDeleteDocument(D2)` → `{ hardDeleted: true }`.

**Bonus (à ajouter Phase 2)** :
11. UNAUTHENTICATED — tout endpoint avec `auth=null` → **doit échouer** sur read + write.
12. RECEIPT IS_STALE — soft-delete d'un payment référencé → trigger CF recompute `isStale=true` sur receipt liée.
13. SENT RECEIPT — `markReceiptAsSent` puis tentative re-mark → idempotent (overwrite OK).
14. RECEIPT VOIDED — `markReceiptAsSent` sur receipt `isVoided=true` → **doit échouer** (CF guard).

---

## Plan d'implémentation FEAT-019

1. **Phase 1 — Setup Firestore + Rules de base** (J1)
   - Créer Firestore database (mode production, région europe-west1)
   - Déployer `firestore.rules` ci-dessus
   - Tests émulateur scénarios 1-4, 8-9 (Rules-only)

2. **Phase 2 — Cloud Functions** (J2-J3)
   - `onAuthUserCreate` (mirror `handle_new_user`)
   - `softDelete<Entity>` × 5
   - `createLease`, `createPayment`, `createDocument`
   - `generateReceipt`, `voidReceipt`, `markReceiptAsSent`
   - Trigger `onUpdate(payments)` → recompute `isStale`
   - Tests émulateur scénarios 5-7, 10

3. **Phase 3 — Indexes Firestore** (J3)
   - `properties (landlordId ASC, deletedAt ASC)`
   - `payments (landlordId ASC, leaseId ASC, periodStart DESC, deletedAt ASC)`
   - `receipts (landlordId ASC, leaseId ASC, periodStart DESC)`
   - `documents (landlordId ASC, leaseId ASC, deletedAt ASC)`

4. **Phase 4 — Audit** (J4)
   - security-auditor review du fichier Rules + CF
   - Tests cross-user émulateur en CI
   - Penetration manuel (tentatives bypass via SDK direct)

---

## Notes finales

- **Pas de schémas dev/public** sur Firestore — utiliser 2 projets Firebase (`easyrent-prod` / `easyrent-dev`) ou 2 databases dans le même projet (Firestore multi-database GA 2024).
- **Migration legacy** : script one-shot Cloud Function lit Supabase via REST + écrit Firestore via Admin SDK (bypass Rules par design).
- **Rollback** : Rules versionnées (Firebase console garde historique), CF deploy `--force` pour rollback rapide.
