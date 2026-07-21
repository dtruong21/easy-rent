# Schéma — properties

> Source d'état — properties. Maintenu par `state-keeper`.

Collections : `properties`, `tenants` (patrimoine). **CRÉATION CF-exclusive** (callables `createProperty`/`createTenant`, FEAT-044). Patterns transverses → [README](README.md).

---

## `properties/{id}` — FEAT-044 : création CF-exclusive

Bien immobilier (appartement, maison, etc). **Création exclusively via callable `createProperty`** (Admin SDK, impose plafond free-tier + gating atomique sur `landlords.activePropertiesCount`).

| Champ | Type | Notes |
|---|---|---|
| `id` | string | UUID, docId |
| `landlordId` | string | FK → landlords.id, immuable |
| `name` | string | adresse ou nom |
| `address` | string | complète (rue + code postal) |
| `type` | string | 'appartement' \| 'maison' \| 'studio' \| 'autre', immuable |
| `surfaceM2` | number\|null | surface habitable (FEAT-017) |
| `postalCode` | string\|null | code postal |
| `city` | string\|null | ville |
| `rooms` | int\|null | nombre de pièces |
| `bedrooms` | int\|null | nombre de chambres |
| `floor` | int\|null | étage |
| `hasElevator` | bool | ascenseur |
| `furnished` | bool | meublé/vide |
| `heatingType` | string\|null | mode chauffage (FEAT-017) |
| `dpeLetter` | string\|null | performance énergétique (A–G) |
| `dpeValueKwhM2Year` | int\|null | consommation énergie (kWh/m²/an) |
| `gesLetter` | string\|null | émissions CO₂ (A–G) |
| `constructionYear` | int\|null | année construction |
| `purchasePriceCents` | int\|null | prix achat (centimes, FEAT-017) |
| `purchaseDate` | timestamp\|null | date achat (FEAT-017) |
| `notaryFeesCents` | int\|null | frais notaire (FEAT-017) |
| `isNewProperty` | bool | neuf (FEAT-017, défaut false) |
| `propertyTaxAnnualCents` | int\|null | taxe foncière annuelle (FEAT-017) |
| `insurancePnoAnnualCents` | int\|null | assurance PNO annuelle (FEAT-017) |
| `condoFeesNonRecoverableCents` | int\|null | charges copro non-récupérables (FEAT-017) |
| `loanPrincipalCents` | int\|null | capital prêt (FEAT-017) |
| `loanRateBps` | int\|null | taux prêt (basis points, FEAT-017) |
| `loanInsuranceBps` | int\|null | assurance prêt (bps, FEAT-017) |
| `loanDurationMonths` | int\|null | durée prêt (mois, FEAT-017) |
| `loanStartDate` | timestamp\|null | démarrage prêt (FEAT-017) |
| `loanMonthlyPaymentOverrideCents` | int\|null | override mensualité (FEAT-017) |
| `activeLeaseCount` | int | dénorm (CF increment/decrement via createLease/updateLease) — client read-only |
| `createdAt` | timestamp | immuable |
| `updatedAt` | timestamp | CF trigger |
| `deletedAt` | timestamp\|null | soft-delete, isActive filter |

**Règles Firestore** :
- `get/list` : isOwner(landlordId) && (isActive ou sans filtre)
- `create` : **if false** (CF-exclusive via `createProperty`/FEAT-044)
- `update` : isFullyAuthed() && isOwner(landlordId) && isActive(rsc) && preservesImmutables()
- `delete` : interdit (soft-delete CF exclusive)

**Indexes** :
- landlordId ↑, deletedAt ↑, name ↑ (list actives)
- landlordId ↑, deletedAt ↑, createdAt ↓ (recent first)

**Triggers** : setUpdatedAt.

---

## `tenants/{id}` — FEAT-044 : création CF-exclusive

Locataire. **Création exclusively via callable `createTenant`** (Admin SDK, impose plafond free-tier + gating atomique sur `landlords.activeTenantsCount`).

| Champ | Type | Notes |
|---|---|---|
| `id` | string | UUID |
| `landlordId` | string | FK → landlords.id, immuable |
| `firstName` | string | prénom |
| `lastName` | string | nom |
| `email` | string | regex `^[^@\s]+@[^@\s]+\.[^@\s]+$`, immuable |
| `phone` | string\|null | téléphone (optionnel) |
| `birthDate` | timestamp\|null | date de naissance (optionnel) |
| `birthPlace` | string\|null | lieu de naissance (optionnel) |
| `nationality` | string\|null | nationalité (optionnel) |
| `profession` | string\|null | profession (optionnel) |
| `employer` | string\|null | employeur (optionnel) |
| `monthlyIncomeCents` | int\|null | revenu mensuel net (centimes) |
| `previousAddress` | string\|null | adresse précédente (optionnel) |
| `guarantorName` | string\|null | nom garant (optionnel) |
| `guarantorEmail` | string\|null | email garant (optionnel) |
| `guarantorPhone` | string\|null | téléphone garant (optionnel) |
| `activeLeaseCount` | int | dénorm (CF increment/decrement via createLease/updateLease) — client read-only |
| `createdAt` | timestamp | immuable |
| `updatedAt` | timestamp | CF trigger |
| `deletedAt` | timestamp\|null | soft-delete, isActive filter |

**Règles Firestore** :
- `get/list` : isOwner(landlordId) && (isActive ou sans filtre)
- `create` : **if false** (CF-exclusive via `createTenant`/FEAT-044)
- `update` : isFullyAuthed() && isOwner(landlordId) && isActive(rsc) && preservesImmutables() && activeLeaseCount unchanged
- `delete` : interdit

**Indexes** :
- landlordId ↑, deletedAt ↑, firstName ↑ (list search)
- landlordId ↑, deletedAt ↑, lastName ↑ (list search)

**Triggers** : setUpdatedAt.
