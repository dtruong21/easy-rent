# Functions — Leases

> Source d'état — leases. Maintenu par state-keeper.

Baux, `chargeMode` (FEAT-042), régularisation charges (FEAT-041c). Fichiers : `functions/src/callable/lease_payment.ts` (callables) · `functions/src/utils/property_address.ts` (composition adresse, fonction pure). FEAT : 005, 028, 036, 041c, 042.

## Callables

**ADR 0003** : tous les callables écrivant Firestore utilisent `dbForRequest(request)` pour router vers la base prod ou staging par Origin.

### Helper : `composePropertyAddress()` (`functions/src/utils/property_address.ts`)

Fonction pure testée : compose l'adresse COMPLÈTE (rue + code postal + ville) en évitant les doublons. Le formulaire client n'expose que trois champs séparés sur `properties`, et les bailleurs en pratique ne remplissent que la rue (`address`). La quittance doit identifier le logement (loi 6/7/1989) — d'où la composition au seul point d'écriture du bail (callable `createLease`). Miroir Dart : `lib/core/utils/property_address.dart` (même logique client-side pour affichage).

### `createLease` (FEAT-042, étendu multi-paliers FEAT-056)
Client invoke, isFullyAuthed only.
- **Params** : `propertyId, tenantId, rentAmountCents, chargesAmountCents, nonRecoverableChargesCents` (FEAT-036), `chargeMode` (FEAT-042, optionnel, résolu/enforced serveur), `startDate, endDate, status, leaseType, paymentDay, paymentMethod, depositAmountCents, irlIndexValue, irlQuarterRef, agencyFeesCents, solidarityClause, entryInventoryDone`.
- **Validations** : auth uid présent ; FK GET `properties/{propertyId}` + `tenants/{tenantId}` ; ownership `properties.landlordId==tenants.landlordId==uid` ; FEAT-036 `nonRecoverableChargesCents ≥ 0` (pas de total constraint) ; **FEAT-042** `resolveChargeMode(leaseType, chargeMode)` → canonique (coerce type↔mode, rejette incompatible) ; **Forfait** → force `nonRecoverableChargesCents=0` (ventilation interdite) ; `startDate <= endDate` ; status inference `active|terminated|archived` ; **FEAT-056** si `active` → vérifier quota `activeLeases` du plan effectif avant increment.
- **Mutations** (transact) : CREATE `leases/{id}` snapshot denorm (`propertyName, tenantFirstName/LastName, propertyAddress composée via composePropertyAddress()`…) ; persiste `chargesAmountCents` (récupérable) + `nonRecoverableChargesCents` (≥0 ou forcé 0 si forfait) ; persiste `chargeMode` résolu ; si `active` → INCREMENT `properties.activeLeaseCount` + `tenants.activeLeaseCount` + `landlords.activeLeasesCount`. **`propertyAddress` est immuable après création** (snapshot gelée à la création, traçabilité légale).
- **Retour** : `{leaseId}`. **Erreurs** : PERMISSION_DENIED, NOT_FOUND, INVALID_ARGUMENT, FAILED_PRECONDITION (type↔mode conflict), RESOURCE_EXHAUSTED (`lease_limit_reached` si FEAT-056 quota saturé).

### `updateLease` (FEAT-042, PR #94 ; étendu FEAT-056)
- **Mutable** : `rentAmountCents, chargesAmountCents, nonRecoverableChargesCents` (FEAT-036), `endDate, status, leaseType, chargeMode` (FEAT-042), `depositAmountCents, paymentDay, paymentMethod, irlIndexValue, irlQuarterRef, agencyFeesCents, solidarityClause, entryInventoryDone`.
- **Logique** : fetch + ownership ; `nonRecoverableChargesCents` borné (≥0) + re-validation charges cross-entity ; **FEAT-042 (inconditionnel)** `resolveChargeMode(finalLeaseType, requestedChargeMode)` même si patch n'y touche pas (baux legacy appliquent le forçage) — si `leaseType` inchangé → `requested` du patch ou ancien persisté si omis ; si `leaseType` change → `requested` du patch seul (ancien ignoré) ; **backfill lazy** persiste toujours le mode résolu (matérialise legacy à la 1ère mutation) ; **Forfait** → force `nonRecoverableChargesCents=0` (inclus baux legacy mobilité).
- **Réactivation (PR #94, 2026-07-10)** : Transition `active` (nouvelle status) depuis `terminated|archived` verrouille :
  - Le bien (propertyId) et locataire (tenantId) doivent exister + ne pas être soft-deleted (failed-precondition sinon) — prévient la résurrection de baux pointant vers entités supprimées.
  - Recompte fail-closed du plafond `landlords.activeLeasesCount` si compteur absent (legacy).
  - **FEAT-056** : vérification atomique du quota `activeLeases` du plan effectif dans la transaction → RESOURCE_EXHAUSTED (`lease_limit_reached`) si saturé.
- **Compteurs (FEAT-044)** : si `active→terminated` ou `terminated→active` (delta ≠ 0) → DECREMENT/INCREMENT `activeLeaseCount` sur properties/tenants et `activeLeasesCount` sur landlords.
- **Retour** : `{updated:true}`.

## Constants & helpers (`lease_payment.ts`)

| Constant/Helper | Valeur/Signature | Usage |
|---|---|---|
| `CHARGE_MODES` | `Set(["provisions","forfait"])` | FEAT-042 : validation enum |
| `resolveChargeMode()` | `(leaseType, requested?) → string` | FEAT-042 : source unique vérité serveur, cohérence type↔mode + dérivation legacy |
| `FREE_ACTIVE_LEASE_LIMIT` | `2` | FEAT-044 : plafond baux actifs, tier free |
| `activeLeaseLimitForTier()` | `(tier) → number \| null` | FEAT-044 : résout plafond par tier (free=2, paid=null∞, autre=0) |

**`resolveChargeMode`** : `unfurnished` → forcé `'provisions'` (art. 23 loi 6/7/1989 ; rejette forfait explicite) ; `mobility` → forcé `'forfait'` (loi ELAN art. 25-18 ; rejette provisions explicite) ; `furnished`|`student` → libre, défaut `'provisions'` si omis.

**Quotas** (FEAT-056, source `config/entitlements.json`) :
- **activeLeases** : anonymous=0 · free=2 · pro=5 · max=15 · ultra=null (illimité)
Effective plan déduit de `(subscriptionTier, planLevel)` par `resolvePlan()` (null planLevel sur `paid` → pro).

## Triggers

| Trigger | Type / collection | Logique |
|---|---|---|
| `setUpdatedAtLeases` | `onDocumentUpdated(leases)` | Standard `setUpdatedAt` (voir README). Fichier `set_updated_at.ts` |
| `recomputeChargeRegularization` (FEAT-041c) | type à déterminer — 📋 **PLANNED V1.1** (pas déployé, aucun code) | Si `expense.category=='recoverable' && expense.leaseId` → query lease ; alimente `lease.chargeRegularizationFeed` subcollection (draft) ; agrège charges mensuelles → provision + avis PDF |

## Dart repository — gestion de l'affichage

**`FirestoreLeaseRepository.listForDisplay({DateTime? now})`** — `lib/features/leases/data/lease_repository.dart`. Query `landlordId==uid && deletedAt==null`, sort `startDate DESC` (200 limit) ; fetch ALL payments baux **actifs** (FEAT-028 : évite baux terminés) ; **clock injectable** `now ?? DateTime.now()` (tests déterministes, FEAT-042) ; `isLeaseLate(lease, payments, now)` → retard coloré + filtre (FEAT-028) ; return `List<LeaseListItem>`. Utilisé par `leasesListProvider` (Riverpod FutureProvider).

**`listActiveLeasesForProperty(propertyId)`** — `lib/features/leases/data/lease_repository.dart` ligne 43 ; retourne baux actifs d'un bien (format Map brut snake_case). Consommé par section « Baux actifs » du détail bien + section « Baux liés » du détail locataire. Réutilise l'index composite existant `landlordId, propertyId, deletedAt, startDate DESC`.

⚠️ **Statut « en retard » est DÉRIVÉ** : `isLeaseLate()` se calcule à chaque affichage, jamais stocké. Conséquence : toute action modifiant les paiements (ajout, archive) doit invalider `leasesListProvider` + `leaseDetailProvider(leaseId)` dans le même scope, sinon le statut affiché reste périmé. Codifié dans `PaymentFormController` (submit + archive). Exemple : commit `c185929` corrige oubli d'invalidation lors de l'encaissement.
