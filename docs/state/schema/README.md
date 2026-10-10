# Schéma Firestore — index des shards

> Source d'état — README (transverse). Maintenu par `state-keeper`.

**Source** : `firestore.rules` + `firestore.indexes.json` + Cloud Functions callables. **Dernière sync** : 2026-07-21 (FEAT-044 paiement : champs `pro*` sur `landlords` ; quota documents free). **Pivot** : FEAT-019 (2026-06-30) — migration du backend vers Firestore camelCase (plus de backend SQL ; les sections de garde s'appellent désormais « Règles Firestore »).

## 14 collections → shard

| Collection | Type | Access | Shard |
|---|---|---|---|
| `landlords` | singleton (uid) | CRUD account | [account](account.md) |
| `paid_plan_interest` | singleton (uid) | CRUD account (create-only) | [account](account.md) |
| `support_requests` | multi | create-only (FEAT-025) | [account](account.md) |
| `properties` | multi | CRUD account (isFullyAuthed) | [properties](properties.md) |
| `tenants` | multi | CRUD account (isFullyAuthed) | [properties](properties.md) |
| `leases` | multi | CF exclusive | [leases](leases.md) |
| `charge_statements` | multi | CF exclusive (FEAT-033) | [leases](leases.md) |
| `etat_des_lieux` | multi | CF exclusive, immuable (FEAT-037) | [leases](leases.md) |
| `payments` | multi | CF exclusive | [payments-receipts](payments-receipts.md) |
| `receipts` | multi | rules read-only | [payments-receipts](payments-receipts.md) |
| `documents` | multi | CF exclusive | [expenses-documents](expenses-documents.md) |
| `expenses` | multi | CF exclusive (FEAT-041) | [expenses-documents](expenses-documents.md) |
| `investment_scenarios` | multi | CRUD signed (anon OK) | [simulator](simulator.md) |
| `_ops` | config serveur globale | aucun accès client (Functions seules) | [account](account.md) |

## Patterns transverses

**Convention champs** : camelCase (pivot FEAT-019 depuis snake_case Postgres). Montants en centimes (`*Cents`, int). Dates = `timestamp`. IDs = UUID string (sauf `landlords`/`paid_plan_interest` docId = Firebase Auth UID).

**Soft-delete** : `deletedAt` timestamp\|null sur toutes les multi-tenant sauf `receipts`/`paid_plan_interest`/`support_requests`. Filtre `isActive(rsc)` = `deletedAt == null`. Aucun hard-delete client (sauf purge anonyme 14j). `delete` = interdit partout (soft-delete via CF).

**Immutables** (jamais changés client, `preservesImmutables()`) : `landlordId`, `createdAt`, `deletedAt`. Par collection : voir shard.

**Accès Firestore côté Flutter (ADR 0003)** : **via `firestoreProvider`** (`lib/core/config/firestore_provider.dart`) **uniquement**. `FirebaseFirestore.instance` interdit hors `main.dart` — un check CI (`scripts/check-db-isolation.sh`) l'impose. La règle sépare prod (base `(default)`) de staging web (base `staging`).

**Helper functions (Firestore rules, Couche 1)** — default deny + allowlist :
- `isOwner(uid)` : `auth.uid == document.landlordId` ET (`isAnonymous()` OU `hasTrustedEmail()`) — un compte email/mot de passe NON vérifié n'est propriétaire de rien (OWASP-02)
- `isActive(rsc)` : `resource.data.deletedAt == null`
- `preservesImmutables(rsc)` : garde-fou mutations
- `hasTrustedEmail()` : `request.auth.token.get('email_verified', false) == true` OU `sign_in_provider in ['google.com','apple.com']` (OWASP-02)
- `isFullyAuthed()` : `isSignedIn() && !isAnonymous() && hasTrustedEmail()` (email/pwd **vérifié**, Google, Apple)
- `isAnonymous()` : claim `firebase.sign_in_provider == 'anonymous'` (BAILLAN-M1)
- `isSignedIn()` : auth non-null (anon inclus)

**List owner-scoped (audit FEAT-045 H1)** : `allow list: if isOwner(resource.data.landlordId)` sur les 8 collections multi-tenant → toute query DOIT porter `where('landlordId','==',uid)` (rules ≠ filtres ; ancien `isSignedIn()` = lecture cross-tenant). Vérifié `npm run test:rules` (émulateur).

**Trigger transverse `setUpdatedAt`** (×8) : landlords, properties, tenants, leases, payments, documents, expenses, investment_scenarios. ⚠️ **`setUpdatedAtReceipts` n'existe pas** (receipts immuables) — corrigé 2026-07-21, cette liste comptait 9 entrées à tort. Note : delete triggers = soft-delete logic CF.

**Callable transverse `softDeleteEntity`** : soft-delete unifié (landlords, properties, tenants, leases, payments, documents, expenses, investment_scenarios). Receipts exclus (rétention légale, voir payments-receipts).

**Callables cross-entity/cross-tenant (Couche 2)** : listés par shard. Détail (signatures TS, error handling, tests) → [`../functions/README.md`](../functions/README.md) puis le shard du domaine.

## Indexes composites (37 total)

Décompte vérifié 2026-07-21 (`firestore.indexes.json`, 0 `fieldOverrides`) — l'ancien chiffre **28 était périmé**. Par collection : `leases` 10 · `expenses` 7 · `payments` 7 · `receipts` 4 · `documents` 3 · `properties` 2 · `tenants` 2 · `landlords` 1 · `investment_scenarios` 1. Tous `Collection > Composite`. Filtrage `deletedAt` systématique (sauf `receipts`). Détail par shard.

## Audit (2026-07-05, décomptes rafraîchis 2026-07-21)

✅ 11 collections mappées 1:1 routes+features ; 37 indexes couvrent soft-delete + cross-filters ; 3 couches de garde (règles Firestore + CF + triggers) zéro `WHERE field==null` sans index ; dénorm (propertyName, tenantLastName, propertyId snapshots) systématique.
⚠️ FEAT-041c (`recomputeChargeRegularization`) planné, pas déployé (V1.1). FEAT-033 (snapshot figé dépense) **absorbé** par FEAT-041 V1 (categoryOverridden + nature enum immuable).
