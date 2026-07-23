# Functions — Properties & Tenants

> Source d'état — properties. Maintenu par state-keeper.

Patrimoine (properties + tenants). **Création CF-exclusive** via callables (FEAT-044). Update/soft-delete via Firestore Rules + `softDeleteEntity`. Fichier callables : `functions/src/callable/property_tenant.ts`. Fichier triggers : `functions/src/triggers/set_updated_at.ts`.

## Callables — FEAT-044

### `createProperty` (FEAT-044)
Client invoke, isFullyAuthed only.
- **Params** : `name, address, type` (immuable) + champs optionnels (city, postalCode, surfaceM2, rooms, bedrooms, floor, hasElevator, furnished, heatingType, dpeLetter, dpeValueKwhM2Year, gesLetter, constructionYear) + FEAT-017 (purchasePriceCents, purchaseDate, notaryFeesCents, isNewProperty, propertyTaxAnnualCents, insurancePnoAnnualCents, condoFeesNonRecoverableCents, loanPrincipalCents, loanRateBps, loanInsuranceBps, loanDurationMonths, loanStartDate, loanMonthlyPaymentOverrideCents).
- **Validations** : auth uid ; tier + `landlords.activePropertiesCount` absent ou < plafond (free=2, paid=∞) ; recompte fail-closed si compteur absent (legacy).
- **Mutations** (transact) : CREATE `properties/{id}` ; si hasCounter → INCREMENT `landlords.activePropertiesCount` else SEED (recomptée + 1). Initialize `activeLeaseCount=0`.
- **Retour** : `{propertyId}`. **Erreurs** : PERMISSION_DENIED, RESOURCE_EXHAUSTED (property_limit_reached si free tier saturé).

### `createTenant` (FEAT-044)
Client invoke, isFullyAuthed only.
- **Params** : `firstName, lastName, email` (immuable) + champs optionnels (phone, birthDate, birthPlace, nationality, profession, employer, monthlyIncomeCents, previousAddress, guarantorName, guarantorEmail, guarantorPhone).
- **Validations** : auth uid ; email regex ; tier + `landlords.activeTenantsCount` absent ou < plafond (free=3, paid=∞) ; recompte fail-closed si compteur absent (legacy).
- **Mutations** (transact) : CREATE `tenants/{id}` ; si hasCounter → INCREMENT `landlords.activeTenantsCount` else SEED (recomptée + 1). Initialize `activeLeaseCount=0`.
- **Retour** : `{tenantId}`. **Erreurs** : PERMISSION_DENIED, RESOURCE_EXHAUSTED (tenant_limit_reached si free tier saturé).

**Plafonds FEAT-044** (par tier) :
- free : 2 biens, 3 locataires, 2 baux actifs
- paid : illimité
- anonymous/autres : 0 (defense-in-depth)

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
