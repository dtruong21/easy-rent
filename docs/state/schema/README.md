# Schéma Firestore — index des shards

> Source d'état — README (transverse). Maintenu par `state-keeper`.

**Source** : `firestore.rules` + `firestore.indexes.json` + Cloud Functions callables. **Dernière sync** : 2026-07-08 (FEAT-045 rétention 5 ans ; FEAT-043 i18n sans impact schema). **Pivot** : FEAT-019 (2026-06-30) — Supabase Postgres → Firestore camelCase.

## 11 collections → shard

| Collection | Type | Access | Shard |
|---|---|---|---|
| `landlords` | singleton (uid) | CRUD account | [account](account.md) |
| `paid_plan_interest` | singleton (uid) | CRUD account (create-only) | [account](account.md) |
| `support_requests` | multi | create-only (FEAT-025) | [account](account.md) |
| `properties` | multi | CRUD account (isFullyAuthed) | [properties](properties.md) |
| `tenants` | multi | CRUD account (isFullyAuthed) | [properties](properties.md) |
| `leases` | multi | CF exclusive | [leases](leases.md) |
| `payments` | multi | CF exclusive | [payments-receipts](payments-receipts.md) |
| `receipts` | multi | rules read-only | [payments-receipts](payments-receipts.md) |
| `documents` | multi | CF exclusive | [expenses-documents](expenses-documents.md) |
| `expenses` | multi | CF exclusive (FEAT-041) | [expenses-documents](expenses-documents.md) |
| `investment_scenarios` | multi | CRUD signed (anon OK) | [simulator](simulator.md) |

## Patterns transverses

**Convention champs** : camelCase (pivot FEAT-019 depuis snake_case Postgres). Montants en centimes (`*Cents`, int). Dates = `timestamp`. IDs = UUID string (sauf `landlords`/`paid_plan_interest` docId = Firebase Auth UID).

**Soft-delete** : `deletedAt` timestamp\|null sur toutes les multi-tenant sauf `receipts`/`paid_plan_interest`/`support_requests`. Filtre `isActive(rsc)` = `deletedAt == null`. Aucun hard-delete client (sauf purge anonyme 14j). `delete` = interdit partout (soft-delete via CF).

**Immutables** (jamais changés client, `preservesImmutables()`) : `landlordId`, `createdAt`, `deletedAt`. Par collection : voir shard.

**Helper functions (Firestore rules, Couche 1)** — default deny + allowlist :
- `isOwner(uid)` : `auth.uid == document.landlordId`
- `isActive(rsc)` : `resource.data.deletedAt == null`
- `preservesImmutables(rsc)` : garde-fou mutations
- `isFullyAuthed()` : `isSignedIn() && !isAnonymous()` (email/pwd, Google, Apple)
- `isAnonymous()` : claim `firebase.sign_in_provider == 'anonymous'` (BAILLAN-M1)
- `isSignedIn()` : auth non-null (anon inclus)

**List owner-scoped (audit FEAT-045 H1)** : `allow list: if isOwner(resource.data.landlordId)` sur les 8 collections multi-tenant → toute query DOIT porter `where('landlordId','==',uid)` (rules ≠ filtres ; ancien `isSignedIn()` = lecture cross-tenant). Vérifié `npm run test:rules` (émulateur).

**Trigger transverse `setUpdatedAt`** (×9) : landlords, properties, tenants, leases, payments, documents, expenses, investment_scenarios, receipts (receipts = status only). Note : delete triggers = soft-delete logic CF.

**Callable transverse `softDeleteEntity`** : soft-delete unifié (landlords, properties, tenants, leases, payments, documents, expenses, investment_scenarios). Receipts exclus (rétention légale, voir payments-receipts).

**Callables cross-entity/cross-tenant (Couche 2)** : listés par shard. Détail (signatures TS, error handling, tests) → [`../FUNCTIONS.md`](../FUNCTIONS.md).

## Indexes composites (28 total)

23 soft-delete patterns + 5 cross-entity. Tous `Collection > Composite`. Filtrage `deletedAt` systématique (sauf `receipts`). Détail par shard.

## Audit (2026-07-05)

✅ 11 collections mappées 1:1 routes+features ; 28 indexes couvrent soft-delete + cross-filters ; 3 couches RLS (rules+CF+triggers) zéro `WHERE field==null` sans index ; dénorm (propertyName, tenantLastName, propertyId snapshots) systématique.
⚠️ FEAT-041c (`recomputeChargeRegularization`) planné, pas déployé (V1.1). FEAT-033 (snapshot figé dépense) **absorbé** par FEAT-041 V1 (categoryOverridden + nature enum immuable).
