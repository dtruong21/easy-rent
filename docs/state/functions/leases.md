# Functions — Leases

> Source d'état — leases. Maintenu par state-keeper.

Baux, `chargeMode` (FEAT-042), régularisation charges (FEAT-041c). Fichier callables/constants : `functions/src/callable/lease_payment.ts`. FEAT : 005, 028, 036, 041c, 042.

## Callables

### `createLease` (FEAT-042)
Client invoke, isFullyAuthed only.
- **Params** : `propertyId, tenantId, rentAmountCents, chargesAmountCents, nonRecoverableChargesCents` (FEAT-036), `chargeMode` (FEAT-042, optionnel, résolu/enforced serveur), `startDate, endDate, status, leaseType, paymentDay, paymentMethod, depositAmountCents, irlIndexValue, irlQuarterRef, agencyFeesCents, solidarityClause, entryInventoryDone`.
- **Validations** : auth uid présent ; FK GET `properties/{propertyId}` + `tenants/{tenantId}` ; ownership `properties.landlordId==tenants.landlordId==uid` ; FEAT-036 `nonRecoverableChargesCents ≥ 0` (pas de total constraint) ; **FEAT-042** `resolveChargeMode(leaseType, chargeMode)` → canonique (coerce type↔mode, rejette incompatible) ; **Forfait** → force `nonRecoverableChargesCents=0` (ventilation interdite) ; `startDate <= endDate` ; status inference `active|terminated|archived`.
- **Mutations** (transact) : CREATE `leases/{id}` snapshot denorm (`propertyName, tenantFirstName/LastName`…) ; persiste `chargesAmountCents` (récupérable) + `nonRecoverableChargesCents` (≥0 ou forcé 0 si forfait) ; persiste `chargeMode` résolu ; si `active` → INCREMENT `properties.activeLeaseCount` + `tenants.activeLeaseCount`.
- **Retour** : `{leaseId}`. **Erreurs** : PERMISSION_DENIED, NOT_FOUND, INVALID_ARGUMENT, FAILED_PRECONDITION (type↔mode conflict).

### `updateLease` (FEAT-042)
- **Mutable** : `rentAmountCents, chargesAmountCents, nonRecoverableChargesCents` (FEAT-036), `endDate, status, leaseType, chargeMode` (FEAT-042), `depositAmountCents, paymentDay, paymentMethod, irlIndexValue, irlQuarterRef, agencyFeesCents, solidarityClause, entryInventoryDone`.
- **Logique** : fetch + ownership ; `nonRecoverableChargesCents` borné (≥0) + re-validation charges cross-entity ; **FEAT-042 (inconditionnel)** `resolveChargeMode(finalLeaseType, requestedChargeMode)` même si patch n'y touche pas (baux legacy appliquent le forçage) — si `leaseType` inchangé → `requested` du patch ou ancien persisté si omis ; si `leaseType` change → `requested` du patch seul (ancien ignoré) ; **backfill lazy** persiste toujours le mode résolu (matérialise legacy à la 1ère mutation) ; **Forfait** → force `nonRecoverableChargesCents=0` (inclus baux legacy mobilité) ; si `active→terminated` → DECREMENT `activeLeaseCount` ; transact update + re-snapshot `propertyName` + `chargeMode` matérialisé.
- **Retour** : `{updated:true}`.

## Constants & helpers `chargeMode` (`lease_payment.ts`)

| Constant/Helper | Valeur/Signature | Usage |
|---|---|---|
| `CHARGE_MODES` | `Set(["provisions","forfait"])` | FEAT-042 : validation enum |
| `resolveChargeMode()` | `(leaseType, requested?) → string` | FEAT-042 : source unique vérité serveur, cohérence type↔mode + dérivation legacy |

**`resolveChargeMode`** : `unfurnished` → forcé `'provisions'` (art. 23 loi 6/7/1989 ; rejette forfait explicite) ; `mobility` → forcé `'forfait'` (loi ELAN art. 25-18 ; rejette provisions explicite) ; `furnished`|`student` → libre, défaut `'provisions'` si omis.

## Triggers

| Trigger | Type / collection | Logique |
|---|---|---|
| `setUpdatedAtLeases` | `onDocumentWritten(leases)` | Standard `setUpdatedAt` (voir README). Fichier `set_updated_at.ts` |
| `recomputeChargeRegularization` (FEAT-041c) | `onDocumentWritten(expenses)` — 📋 **PLANNED V1.1** (pas déployé) | Si `expense.category=='recoverable' && expense.leaseId` → query lease ; alimente `lease.chargeRegularizationFeed` subcollection (draft) ; agrège charges mensuelles → provision + avis PDF |

## Dart repository — getter calculé

`FirestoreLeaseRepository.listForDisplay({DateTime? now})` — `lib/features/leases/data/lease_repository.dart`. Query `landlordId==uid && deletedAt==null`, sort `startDate DESC` (200 limit) ; fetch ALL payments baux **actifs** (FEAT-028 : évite baux terminés) ; **clock injectable** `now ?? DateTime.now()` (tests déterministes, FEAT-042) ; `isLeaseLate(lease, payments, now)` → retard coloré + filtre (FEAT-028) ; return `List<LeaseListItem>`. Utilisé par `leasesListProvider` (Riverpod FutureProvider).
