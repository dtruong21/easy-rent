# Functions — Account

> Source d'état — account. Maintenu par state-keeper.

Auth/provisioning, cycle de vie compte, soft-delete universel, cron anon, support, helpers génériques. Fichiers : `functions/src/callable/{finalize_anonymous_upgrade,delete_account,soft_delete}.ts`, `functions/src/scheduled/cleanup_expired_anon.ts`, `functions/src/utils/callable_helpers.ts`, `functions/src/triggers/set_updated_at.ts`.

## Auth (ADR 0001 : GCIP désactivé)

| Élément | Statut | Note |
|---|---|---|
| `handleNewUser` | ❌ SUPPRIMÉ (FEAT-030, commit 90eb86f, 2026-07-05) | GCIP/Identity Platform non activé ; blocking `beforeUserCreated` n'existait qu'en code |

**Provisioning 100 % client** (`auth_repository.dart`, Riverpod) : chemins `signUpWithEmail`, `linkGoogle`, `linkApple`, `signInAnonymously` → crée `landlords/{uid}` GET-then-create (idempotent), même schéma garanti.

## Callables

### `finalizeAnonymousUpgrade` (BAILLAN-M1, FEAT-019)
Client invoke. Déclencheur : anonyme clique « Créer un compte » après essai 14 j.
- **Validations** : user doit être anonyme ; email non-existant (aucun autre user même email).
- **Mutations** (transact Admin SDK) update `landlords/{uid}` : `isAnonymous=false`, `subscriptionTier='free'`, `rgpdConsentAt=now()` (consent signup), `rgpdConsentVersion='v2-2026-07'`, `email`+`fullName` from data, `anonExpiresAt=null`. Preserve `investment_scenarios` (landlordId==uid constant, **pas de migration**).
- **Retour** : `{success:true}`. Fichier `finalize_anonymous_upgrade.ts`. Tests `__tests__/finalize_anonymous_upgrade.test.ts`.

### `deleteAccount` (FEAT-045, RGPD art. 17)
Client invoke, **tout compte authentifié y compris anonyme**. Exigence stores : Google Play « Account deletion » (13327111) + App Store 5.1.1(v).
- **Garde** : token non-anonyme dont `auth_time` > 5 min → `failed-precondition` (`recent-login-required`) ; client réauthentifie juste avant (mot de passe/OAuth). Sessions anonymes **exemptées** (Admin SDK `getUser().providerData` vide ; claim `sign_in_provider` reste `'anonymous'` sur tokens émis avant upgrade par linking).
- **Purge (ordre)** : 1. `receipts` du landlord **CONSERVÉES** (loi 6/7/1989, 5 ans) — stamp `accountDeletedAt`+`retentionUntil` (purge différée futur cron) ; 2. hard-delete paginé 400/batch `properties, tenants, leases, payments, documents (y c. legalHold — flux client avertit), expenses, investment_scenarios, support_requests` (`where landlordId==uid`) ; 3. singletons `paid_plan_interest/{uid}`+`landlords/{uid}` ; 4. Storage `deleteFiles(documents/{uid}/)` ; 5. **Auth EN DERNIER** `admin.auth().deleteUser(uid)` (idempotent user-not-found).
- **Invariant** : ordre **inverse** de `cleanupExpiredAnon` — retry porté par l'utilisateur encore connecté, échec en cours laisse Auth vivant pour relancer.
- **Révocation Apple** : côté **CLIENT** avant l'appel (`revokeTokenWithAuthorizationCode` avec authorizationCode de la re-auth ; iOS/macOS, best-effort ailleurs).
- **Retour** : `{deleted:true, receiptsRetained:number}`. Fichier `delete_account.ts`. Tests `delete_account.test.ts` (15 tests) + `rules-tests/firestore_rules.test.ts` (28 tests, `npm run test:rules`).

### `softDeleteEntity` (universel)
Signature `{collection, docId}`. Soft-delete unifié (spec canonique) ; le soft-delete des `documents` passe par ce callable universel — pas de `softDeleteDocument` dédié (voir expenses-documents).
- **Par collection** : `landlords`/`properties`/`tenants` → vérifier no active leases ; `leases` → OK (trigger `activeLeaseCount` decrement) ; `payments` → OK (trigger `recomputeReceiptStale`) ; `receipts` → **REFUSE** (immuable, loi 6/7/1989) ; `documents` → check `legalHold` (refuse si true) ; `expenses` → OK (FEAT-041) ; `investment_scenarios` → OK.
- **Mutations** : `deletedAt=now()` ; si collection in `[properties, tenants]` && `status=='active'` → DECREMENT `activeLeaseCount` ; idempotent.
- **Erreurs** : FAILED_PRECONDITION (legalHold==true / active leases / receipts), NOT_FOUND, PERMISSION_DENIED.
- **Retour** : `{success:true}`. Fichier `soft_delete.ts`.

## Trigger

`setUpdatedAtLandlords` — `onDocumentWritten(landlords)`. Logique standard `setUpdatedAt` (voir README). Fichier `set_updated_at.ts`.

## Scheduled

`cleanupExpiredAnon` (BAILLAN-M1) — Cloud Scheduler + CF, **Daily 2 AM UTC** (configurable `gcloud`/console).
1. Query `landlords` where `isAnonymous==true && anonExpiresAt < now()` ;
2. Batch soft-delete par anonyme expiré : `leases`, `payments`, `receipts`, `properties`, `tenants`, `documents`, `expenses`, `investment_scenarios` ; puis **hard-delete** `landlords/{uid}` (vrai delete — rétention inutile anon) ;
3. Log count (Cloud Logging) ; idempotent (`deletedAt` check).

Fichier `scheduled/cleanup_expired_anon.ts`. Logs `firebase functions:log`.

## Support & intérêt payant

| Élément | Note |
|---|---|
| `support_requests` (FEAT-025) | ✅ DONE — create-only rules, **aucun callable** |
| `paid_plan_interest` | Singleton `{uid}` (purgé par `deleteAccount`) |

## Helpers génériques (`functions/src/utils/callable_helpers.ts`)

| Helper | Signature | Usage |
|---|---|---|
| `requireAuthUid()` | `(request) → string` | Extract + validate auth UID |
| `requireString()` | `(value, name) → string` | Non-empty string |
| `requireInt()` | `(value, name, {min,max}) → number` | Integer borné |
| `optionalString()` | `(value, name) → string\|null` | Optional string |
| `optionalInt()` | `(value, name, bounds) → number\|null` | Optional integer |
| `optionalTimestamp()` | `(value, name) → Timestamp\|null` | Optional timestamp |
| `toTimestamp()` | `(value, name) → Timestamp` | Coerce → Firestore timestamp |
| `asBag()` | `(data) → Record<string,any>` | Cast objet sûr |
| `dataOrFail()` | `(snap, entity) → any` | Extract data ou throw NOT_FOUND |
| `assertOwnedAndActive()` | `(doc, uid, entity) → void` | Ownership + isActive |
