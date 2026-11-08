# Schéma — payments-receipts

> Source d'état — payments-receipts. Maintenu par `state-keeper`.

Collections : `payments` (CF exclusive), `receipts` (rules read-only). Patterns transverses → [README](README.md).

---

## `payments/{id}` — CF exclusive (FEAT-006)

Paiement loyer/charges. **CROSS-ENTITY** : leaseId doit appartenir au même landlord. Motif libre sur reçu (FEAT-029).

| Champ | Type | Notes |
|---|---|---|
| `id` | string | UUID, immuable |
| `landlordId` | string | FK → landlords.id, immuable |
| `leaseId` | string | FK → leases.id, immuable, validation CF |
| `propertyId` | string | snapshot leases.propertyId (dénorm) |
| `tenantLastName` | string | snapshot leases.tenantLastName |
| `rentAmountCents` | int | portion loyer versée (immuable) |
| `chargesAmountCents` | int | portion charges versée (immuable) |
| `periodStart` | timestamp | début période (immuable) |
| `periodEnd` | timestamp | fin période (immuable) |
| `paidAt` | timestamp | date versement (mutable) |
| `paymentMethod` | string | 'virement' \| 'cheque' \| 'especes' \| 'prelevement' \| 'autre' (mutable) |
| `notes` | string\|null | motif libre, max 500 chars (FEAT-029, mutable) → snapshot reçu PDF |
| `reference` | string\|null | référence externe/comptable (mutable) |
| `createdAt` | timestamp | immuable |
| `updatedAt` | timestamp | CF trigger |
| `deletedAt` | timestamp\|null | soft-delete |

**Règles Firestore** :
- `get` : isOwner(landlordId) && isActive(rsc)
- `list` : isOwner(landlordId) — **pas d'`isActive`** (cf. properties, audit FEAT-045)
- `create/update/delete` : **if false** (CF exclusive)

**Indexes** (**7**, vérifiés dans `firestore.indexes.json` — l'état n'en annonçait que 2, tous deux faux) :
- landlordId ↑, deletedAt ↑, paidAt ↓
- landlordId ↑, leaseId ↑, deletedAt ↑, paidAt ↓
- landlordId ↑, leaseId ↑, deletedAt ↑, periodStart ↓
- landlordId ↑, deletedAt ↑, periodStart ↓
- deletedAt ↑, landlordId ↑, createdAt ↓
- deletedAt ↑, landlordId ↑, periodStart ↑
- deletedAt ↑, landlordId ↑, paidAt ↑

> ⚠️ L'**ordre des champs** compte dans un index composite Firestore. L'état donnait `(landlordId, deletedAt, leaseId, paidAt ↓)` alors que le réel est `(landlordId, leaseId, deletedAt, paidAt ↓)`, et annonçait un index préfixé `leaseId` qui **n'existe pas**.

**Callables** : `createPayment`, `updatePayment`.

**Triggers** :
- `setUpdatedAtPayments`
- `recomputeReceiptStale` — voir `receipts` ci-dessous (déclenché par le **soft-delete** d'un paiement, pas par un changement de montant)

---

## `receipts/{id}` — CF exclusive, immuable (FEAT-007)

Quittance loyer (loi 6 juillet 1989 art. L145-40) ou reçu (paiement partiel). **Immuable** : jamais soft-delete ni update post-création (rétention légale 5 ans). Annulation logique via `voidReceipt` (flags `isVoided`/`voidedAt`/`voidedReason`). **PDF généré côté client** via package `pdf` Dart (pas de Storage, pas de génération serveur) — le doc Firestore est la preuve légale.

| Champ | Type | Notes |
|---|---|---|
| `id` | string | UUID, immuable |
| `landlordId` | string | FK → landlords.id, immuable |
| `leaseId` | string | FK → leases.id, immuable |
| `paymentIds` | array[string] | FK → payments.id[] (paiement(s) versée(s) à l'origine) |
| `propertyName` | string | snapshot properties.name (immuable, audit) |
| `propertyAddress` | string | snapshot properties.address (immuable, audit) |
| `landlordFullName` | string | snapshot landlords.fullName (requis loi 1989 art. 21) |
| `landlordAddress` | string | snapshot landlords.address (requis loi 1989 art. 21) |
| `tenantFullName` | string | snapshot `${tenants.firstName} ${tenants.lastName}` |
| `rentCents` | int | loyer versé (somme paiements) |
| `chargesCents` | int | charges versées (somme paiements) |
| `totalCents` | int | total = rentCents + chargesCents |
| `documentType` | string | 'quittance' (≥ loyer+charges dus) \| 'recu' (< loyer+charges dus) |
| `periodStart` | timestamp | début période (earliest paymentId.periodStart) |
| `periodEnd` | timestamp | fin période (latest paymentId.periodEnd) |
| `lastPaidAt` | timestamp | date dernier versement (max paymentId.paidAt) |
| `generatedAt` | timestamp | horodatage génération (= createdAt) |
| `isVoided` | bool | annulation logique (jamais suppression physique) |
| `voidedAt` | timestamp\|null | horodatage annulation (si isVoided) |
| `voidedReason` | string\|null | motif annulation (si isVoided) |
| `isStale` | bool | marquage staleness si paiement/lease change après génération (client rejoue `generateReceipt` si stale=true) |
| `sentAt` | timestamp\|null | horodatage envoi (Web Share API côté client, audit only) |
| `sentToEmail` | string\|null | email destinataire (optionnel, audit) |
| `accountDeletedAt` | timestamp\|null | FEAT-045 : stamp suppression compte (null si actif) — quittance conservée 5 ans post-suppression |
| `createdAt` | timestamp | immuable |

**Règles Firestore** :
- `get/list` : isOwner(landlordId) (**pas de filtre isActive** — annulées restent lisibles audit ; ici `get` non plus n'a pas d'`isActive`, contrairement aux autres collections)
- `create/update/delete` : **if false** (CF-exclusive via `generateReceipt`, `voidReceipt`, `markReceiptAsSent`)

**Indexes** (**4**, vérifiés — tous ordonnés par `periodStart`, jamais par `generatedAt`) :
- landlordId ↑, leaseId ↑, periodStart ↓
- landlordId ↑, periodStart ↓
- landlordId ↑, isVoided ↑, periodStart ↓ (status tracking)
- landlordId ↑, isStale ↑, periodStart ↓ (relance des quittances périmées)

> ⚠️ L'état annonçait un tri par `generatedAt ↓` sur deux index : aucun n'existe sous cette forme. Une requête `orderBy('generatedAt')` échouerait en index manquant.

**Callables** : `generateReceipt`, `voidReceipt`, `markReceiptAsSent`.

**Triggers** :
- `recomputeReceiptStale` ([`triggers/recompute_receipt_stale.ts`](../../../functions/src/triggers/recompute_receipt_stale.ts)) — **un seul trigger**, `onDocumentUpdated` sur `payments/{paymentId}` uniquement.
  - **Condition de déclenchement** : changement de `deletedAt` (soft-delete ou restauration d'un paiement) — **pas** un changement de montant.
  - **Règle métier** : `isStale = true` ssi ≥ 1 paiement parmi `paymentIds` a `deletedAt != null`. Recalcul complet (relit tous les paiements de la quittance), pas un simple flag.
  - Réplique du trigger Postgres `tr_03_set_receipt_stale_on_payment_archive` d'avant FEAT-019.

> ⚠️ L'état décrivait **deux** triggers `onDocumentWritten` (dont un sur `leases`, pour les champs snapshot) et un déclenchement sur `amountCents`. Ni le trigger `leases`, ni le champ `amountCents` n'existent : un changement de `propertyName` sur un bail ne marque **rien** comme périmé.
