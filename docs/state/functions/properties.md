# Functions — Properties & Tenants

> Source d'état — properties. Maintenu par state-keeper. Dernière sync : 2026-09-05.

Patrimoine (properties + tenants). **Création CF-exclusive** via callables (FEAT-044). Update/soft-delete via Firestore Rules + `softDeleteEntity`. Couleur d'identité (`colorKey`) assignée côté client au chargement (repli hash déterministe, FEAT-044d). Fichier callables : `functions/src/callable/property_tenant.ts`. Fichier triggers : `functions/src/triggers/set_updated_at.ts`.

## Callables — FEAT-044

**ADR 0003** : tous les callables écrivant Firestore utilisent `dbForRequest(request)` pour router vers la base prod ou staging par Origin.

### `createProperty` (FEAT-044, étendu multi-paliers FEAT-056)
Client invoke, isFullyAuthed only.
- **Params** : `name, address, type` (immuable) + champs optionnels (city, postalCode, surfaceM2, rooms, bedrooms, floor, hasElevator, furnished, heatingType, dpeLetter, dpeValueKwhM2Year, gesLetter, constructionYear) + FEAT-017 (purchasePriceCents, purchaseDate, notaryFeesCents, isNewProperty, propertyTaxAnnualCents, insurancePnoAnnualCents, condoFeesNonRecoverableCents, loanPrincipalCents, loanRateBps, loanInsuranceBps, loanDurationMonths, loanStartDate, loanMonthlyPaymentOverrideCents).
- **Validations** : auth uid ; effective plan (via `resolvePlan(landlord)` du pair entitlements.json) + `landlords.activePropertiesCount` absent ou < quota ; recompte fail-closed si compteur absent (legacy).
- **Mutations** (transact) : CREATE `properties/{id}` ; si hasCounter → INCREMENT `landlords.activePropertiesCount` else SEED (recomptée + 1). Initialize `activeLeaseCount=0`.
- **Retour** : `{propertyId}`. **Erreurs** : PERMISSION_DENIED, RESOURCE_EXHAUSTED (`property_limit_reached` si saturé).

### `createTenant` (FEAT-044, étendu multi-paliers FEAT-056)
Client invoke, isFullyAuthed only.
- **Params** : `firstName, lastName, email` (immuable) + champs optionnels (phone, birthDate, birthPlace, nationality, profession, employer, monthlyIncomeCents, previousAddress, guarantorName, guarantorEmail, guarantorPhone).
- **Validations** : auth uid ; email regex ; effective plan + `landlords.activeTenantsCount` absent ou < quota ; recompte fail-closed si compteur absent (legacy).
- **Mutations** (transact) : CREATE `tenants/{id}` ; si hasCounter → INCREMENT `landlords.activeTenantsCount` else SEED (recomptée + 1). Initialize `activeLeaseCount=0`.
- **Retour** : `{tenantId}`. **Erreurs** : PERMISSION_DENIED, RESOURCE_EXHAUSTED (`tenant_limit_reached` si saturé).

**Quotas** (FEAT-056, source `config/entitlements.json`) :
- properties : anonymous=0 · free=2 · pro=5 · max=15 · ultra=null
- tenants : anonymous=0 · free=3 · pro=8 · max=20 · ultra=null
- activeLeases : anonymous=0 · free=2 · pro=5 · max=15 · ultra=null
Effective plan déduit de `(subscriptionTier, planLevel)` par `resolvePlan()` (null planLevel sur `paid` → pro).

## Triggers

| Trigger | Type / collection | Logique |
|---|---|---|
| `setUpdatedAtProperties` | `onDocumentUpdated(properties)` | Standard `setUpdatedAt` (voir README) |
| `setUpdatedAtTenants` | `onDocumentUpdated(tenants)` | Standard `setUpdatedAt` (voir README) |

## Denorm — Compteurs & `activeLeaseCount`

Compteur dénormalisé sur `properties` **et** `tenants`, maintenu par les callables baux/soft-delete (pas par un trigger properties/tenants) :
- INCREMENT par `createLease` si `status=='active'` (voir leases) ;
- DECREMENT par `updateLease` (active→terminated) et `softDeleteEntity` (properties/tenants avec `status=='active'`) (voir leases, account).

Soft-delete `properties`/`tenants` refusé s'il reste des baux actifs (`softDeleteEntity`, voir account).
