# Schéma — leases

> Source d'état — leases. Maintenu par `state-keeper`.

Collections : `leases`, `charge_statements` (FEAT-033). CF exclusive (FEAT-036, FEAT-042, FEAT-044, FEAT-006, FEAT-033). Patterns transverses → [README](README.md).

**CROSS-ENTITY** : propertyId + tenantId doivent appartenir au même landlord (validation ownership CF). Charges = `chargesAmountCents` (récupérable, FEAT-036) + `nonRecoverableChargesCents` (informatif bailleur, FEAT-036). `chargeMode` (FEAT-042) détermine éligibilité régularisation (provisions uniquement). **FEAT-044 : compteurs dénormalisés** sur `landlords.activeLeasesCount` (baux actifs), `properties.activeLeaseCount`, `tenants.activeLeaseCount` — maintenus transactionnellement par createLease/updateLease/softDeleteEntity.

## `leases/{id}`

| Champ | Type | Notes |
|---|---|---|
| `id` | string | UUID, immuable |
| `landlordId` | string | FK → landlords.id, immuable |
| `propertyId` | string | FK → properties.id, immuable, validation CF |
| `tenantId` | string | FK → tenants.id, immuable, validation CF |
| `propertyName` | string | snapshot properties.name (dénorm) |
| `propertyAddress` | string | adresse COMPLÈTE composée (rue + code postal + ville) via `composePropertyAddress()` — immuable après création, identifie le logement pour la quittance (loi 6/7/1989). Non mutable. |
| `tenantFirstName` | string | snapshot tenants.firstName |
| `tenantLastName` | string | snapshot tenants.lastName |
| `tenantEmail` | string | snapshot tenants.email |
| `rentAmountCents` | int | loyer mensuel (centimes) |
| `chargesAmountCents` | int | part RÉCUPÉRABLE (FEAT-036) — bilancée locataire via paiement + régularisation (provisions only) |
| `nonRecoverableChargesCents` | int | part NON-RÉCUPÉRABLE (FEAT-036) — informatif ; forcé à 0 en mode forfait (FEAT-042) |
| `startDate` | timestamp | début bail |
| `endDate` | timestamp\|null | fin bail |
| `status` | string | 'active' \| 'terminated' \| 'archived' |
| `leaseType` | string | 'unfurnished' \| 'furnished' \| 'mobility' \| 'student' |
| `chargeMode` | string\|null | FEAT-042 : 'provisions' (mensuelles + régularisation) \| 'forfait' (libératoire, pas de régularisation). Nullable = migration lazy ; dérivé de leaseType si null |
| `depositAmountCents` | int\|null | dépôt garantie |
| `paymentDay` | int | jour versement (1..28) |
| `paymentMethod` | string | 'virement' \| 'cheque' \| 'especes' \| 'prelevement' \| 'autre' |
| `irlIndexValue` | number\|null | indice IRL de révision |
| `irlQuarterRef` | string\|null | T[1-4]-YYYY (ex: T4-2025) |
| `agencyFeesCents` | int | frais agence |
| `solidarityClause` | bool | clause de solidarité |
| `entryInventoryDone` | bool | état des lieux entrée réalisé |
| `createdAt` | timestamp | immuable |
| `updatedAt` | timestamp | CF trigger |
| `deletedAt` | timestamp\|null | soft-delete, isActive filter |

**Charge Mode Resolution (FEAT-042)** :
- `chargeMode==null` (baux pré-042, migration lazy sans backfill) → getter Dart `effectiveChargeMode` dérive de `leaseType` :
  - `unfurnished` → `provisions` (art. 23 loi 6 juillet 1989, forcé serveur)
  - `mobility` → `forfait` (loi ELAN art. 25-18, forcé serveur)
  - `furnished` \| `student` → `provisions` (défaut sûr)
- `chargeMode` explicite (FEAT-042+) → validé serveur (`resolveChargeMode` impose cohérence type↔mode, rejette incohérences)
- **Forfait** : `nonRecoverableChargesCents` forcé à 0 serveur (ventilation interdite) — vaut aussi pour baux legacy mobilité

**Mutable fields** (updateLease) : rentAmountCents, chargesAmountCents, nonRecoverableChargesCents, endDate, status, leaseType, chargeMode, depositAmountCents, paymentDay, paymentMethod, irlIndexValue, irlQuarterRef, agencyFeesCents, solidarityClause, entryInventoryDone.

**Immutable fields** : id, landlordId, propertyId, tenantId, propertyAddress (snapshot immuable composée à création), propertyName, tenantFirstName, tenantLastName, tenantEmail, startDate, createdAt, deletedAt. Aucun de ces champs ne peut être modifié ou re-synchronisé après création — `propertyAddress` en particulier est gelée au moment du `createLease` pour garantir traçabilité dans les quittances (loi 6/7/1989, exigence légale d'identifiabilité du logement).

**Réactivation (PR #94, 2026-07-10)** : Transition `terminated|archived → active` verrouillée via `updateLease` :
- Le bien (propertyId) et locataire (tenantId) doivent exister et ne pas être soft-deleted (failed-precondition sinon) — sinon on créerait un bail pointant vers une entité supprimée.
- Recompte fail-closed du plafond `landlords.activeLeasesCount` si compteur absent (legacy) — même pattern que `createLease`.
- Vérification atomique du plafond free-tier dans la même transaction que la mutation (bail_limit_reached si saturé).

**Règles Firestore** :
- `get/list` : isOwner(landlordId) && isActive(rsc)
- `create/update/delete` : CF exclusive (`createLease`, `updateLease`, `softDeleteEntity`)

**Indexes** :
- landlordId ↑, deletedAt ↑, status ↑ (filter status)
- landlordId ↑, deletedAt ↑, startDate ↓ (recent first)
- landlordId ↑, deletedAt ↑, status ↑, startDate ↓ (KPI drill-down)
- tenantId ↑, deletedAt ↑, status ↑ (tenant active leases)
- propertyId ↑, tenantId ↑ (unicity check, CF validation)
- propertyId ↑, deletedAt ↑ (property lease count)

**Callables** : `createLease`, `updateLease`.

**Triggers** :
- setUpdatedAt
- activeLeaseCount increment/decrement (createLease/updateLease/softDelete transactionnel → properties/tenants)

## `charge_statements/{id}` (FEAT-033)

Décompte de régularisation de charges **figé** (snapshot immuable) au moment de la finalisation — preuve légale (art. 23 loi 6/7/1989, décret 87-713). CF exclusive. Éligible uniquement pour les baux en mode `provisions` (gate serveur `resolveChargeMode`, FEAT-042 — forfait exclu). Callables : `functions/src/callable/charge_statements.ts` ; détail params/validations → [`functions/leases.md`](../functions/leases.md).

| Champ | Type | Notes |
|---|---|---|
| `id` | string | = doc id |
| `landlordId` | string | FK → landlords.id, immuable |
| `leaseId` | string | FK → leases.id, immuable |
| `propertyId` | string | snapshot lease.propertyId à la finalisation |
| `landlordFullName` | string | snapshot landlords.fullName (identité figée, requis non-vide) |
| `landlordAddress` | string | snapshot landlords.address (requis non-vide) |
| `tenantFullName` | string | snapshot `tenantFirstName + tenantLastName` du lease |
| `tenantFirstName` | string | snapshot lease.tenantFirstName |
| `propertyName` | string | snapshot lease.propertyName |
| `propertyAddress` | string | snapshot lease.propertyAddress (déjà composée, cf. `leases/{id}`) |
| `periodStart` | timestamp | début période régularisée |
| `periodEnd` | timestamp | fin période régularisée |
| `provisionsCollectedCents` | int | **RECALCULÉ serveur** (jamais accepté du client) — somme `payments.chargesAmountCents` dont la période recouvre `[periodStart, periodEnd]` |
| `actualExpensesCents` | int | dépenses réelles de la période, ≥ 0 |
| `actualExpensesSource` | string | `'expenses'` (dérivé de `lineItems`, somme validée == `actualExpensesCents`) \| `'manual'` (saisie libre, `lineItems` vide) |
| `balanceCents` | int | **signé** = `actualExpensesCents - provisionsCollectedCents` (positif = dû par le locataire, négatif = dû au locataire) |
| `lineItems` | array\<map\> | figé — `{expenseId, nature, notes, amountCents, expenseDate}` ; vide si `actualExpensesSource==='manual'` |
| `createdAt` | timestamp | immuable, `serverTimestamp()` |
| `isVoided` | bool | défaut `false` — annulation non destructive (pas de soft-delete) |
| `voidedAt` | timestamp\|null | posé par `voidChargeStatement` |
| `voidedReason` | string\|null | motif requis à l'annulation |
| `sentAt` | timestamp\|null | posé par `markChargeStatementAsSent` (audit d'envoi, pas de mail serveur) |
| `sentToEmail` | string\|null | optionnel |
| `schemaVersion` | int | `1` |

**Immutabilité** : **aucun soft-delete** — rétention légale 5 ans (décret 87-713), les décomptes annulés (`isVoided`) restent lisibles pour audit, jamais supprimés. Tous les champs financiers/identité sont figés à la création ; seuls `isVoided*` et `sentAt*` sont mutables, et uniquement via les callables dédiés (jamais en écriture directe cliente).

**Règles Firestore** :
- `get, list` : `isOwner(resource.data.landlordId)`
- `create, update, delete` : `if false` — CF exclusive (`finalizeChargeRegularization`, `voidChargeStatement`, `markChargeStatementAsSent`)

**Index** :
- `landlordId` ↑, `leaseId` ↑, `createdAt` ↓ (historique par bail, `listForLease`)

**Callables** : `finalizeChargeRegularization`, `voidChargeStatement`, `markChargeStatementAsSent`.

**Déploiement** : Rules + index déployés **automatiquement par la CI** (`develop` → base `staging`, `main` → `(default)`, cf. `docs/ENVIRONMENTS.md`). Rien à faire à la main. Les **Cloud Functions restent hors CI — déploiement manuel délibéré** (ADR 0003) : sans `firebase deploy --only functions:finalizeChargeRegularization,functions:voidChargeStatement,functions:markChargeStatementAsSent`, l'action « Finaliser » échoue en staging (callable introuvable) même client déployé.

**Export RGPD** : inclus dans `exportAccountData` (clé `chargeStatements`).

## `etat_des_lieux/{id}` (FEAT-037)

Collection **immuable, CF exclusive** — état des lieux digitalisé. Parties + adresse bien + **domicile du bailleur** (décret 2016-382) sont figés à la création. Aucun soft-delete (document légal) ; rétention 5 ans (décret 2016-382).

| Champ | Type | Notes |
|---|---|---|
| `id` | string | = doc id |
| `landlordId` | string | FK → landlords.id, immuable |
| `leaseId` | string | FK → leases.id, immuable |
| `propertyId` | string | snapshot lease.propertyId à la création |
| `type` | string | `'entree'` \| `'sortie'` — type d'état des lieux |
| `date` | timestamp | date de l'EDL saisie par le bailleur (distincte de `createdAt`) |
| `propertyAddress` | string | snapshot lease.propertyAddress (adresse composée figée) |
| `landlordFullName` | string | snapshot landlords.fullName (identité figée, requis non-vide, décret 2016-382) |
| `landlordAddress` | string | snapshot landlords.address — **domicile du bailleur** figé (décret 2016-382, requis non-vide) |
| `tenantFullName` | string | snapshot `tenantFirstName + tenantLastName` du lease |
| `rooms` | array\<map\> | figé — `[{name, elements: [{name, condition, comment}]}]` ; `condition` ∈ `neuf`\|`bon`\|`moyen`\|`mauvais` |
| `meterReadings` | map | figé — `{waterIndex, electricityIndex, gasIndex}` (chaînes\|null, relevés d'index) |
| `keysCount` | int | nombre de clés remises (figé, ≥ 0) |
| `generalComment` | string\|null | commentaire général optionnel (figé) |
| `createdAt` | timestamp | immuable, `serverTimestamp()` |
| `schemaVersion` | int | `1` |

**Immutabilité** : tous les champs sont figés à la création. Aucune mutation, aucun soft-delete, rétention légale 5 ans (décret 2016-382 : document probant).

**Règles Firestore** :
- `get, list` : `isOwner(resource.data.landlordId)` (propriétaire seul)
- `create, update, delete` : `if false` — CF exclusive (callable `createEtatDesLieux`)

**Index** :
- `landlordId` ↑, `leaseId` ↑, `createdAt` ↓ (historique par bail, `listForLease`)

**Callables** : `createEtatDesLieux`.

**Export RGPD** : inclus dans `exportAccountData` (clé `etatDesLieux`).
