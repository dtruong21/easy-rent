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
| `address` | string | ⚠️ **la RUE seule en pratique**, pas l'adresse complète — voir la note sous ce tableau |
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
| `colorKey` | string\|null | clé de palette PropertyColorKey (rouille, bordeaux, prune, cobalt, ardoise, sauge, moutarde, rosePoudre) — NB : stocke la clé, jamais la couleur brute, pour l'adapter aux 2 thèmes (clair/sombre). Biens existants : repli hash FNV-1a(id) déterministe, widgets doivent toujours résoudre via `PropertyColorKey.resolve(entityId: property.id, stored: property.colorKey)` (FEAT-044d, 2026-08-12) |
| `activeLeaseCount` | int | dénorm (CF increment/decrement via createLease/updateLease) — client read-only |
| `createdAt` | timestamp | immuable |
| `updatedAt` | timestamp | CF trigger |
| `deletedAt` | timestamp\|null | soft-delete, isActive filter |

> ### ⚠️ `address` ne contient QUE la rue (corrigé le 2026-08-12)
>
> Ce shard affirmait que `address` était « complète (rue + code postal) ».
> **C'était faux, et ça a produit un bug visible par l'utilisateur** : le champ
> « Logement » des quittances de loyer n'affichait que la rue, sans code postal
> ni ville — sur un document à valeur légale (loi du 6 juillet 1989).
>
> La réalité : `property_form.dart` étiquette le champ « Adresse complète », mais
> son exemple est « Ex. : 12 rue de la Paix » et il expose `postalCode` et `city`
> en **champs séparés** juste en dessous. Les utilisateurs y saisissent donc la
> rue seule. Rien ne l'impose techniquement — un bien saisi autrement peut
> contenir davantage — d'où la règle ci-dessous.
>
> **Ne concatène jamais toi-même.** Utilise `composePropertyAddress()`
> (`functions/src/utils/property_address.ts` côté serveur,
> `lib/core/utils/property_address.dart` côté client) : elle n'ajoute que les
> composants ABSENTS. Sinon on obtient « …, 95000 Cergy, 95000 Cergy » sur les
> biens dont l'adresse porte déjà le code postal. Deux pièges déjà traités et
> couverts par ses tests : le trait d'union (« Cergy » ne doit pas matcher dans
> « Cergy-Pontoise ») et la position d'insertion du code postal quand l'adresse
> se termine par la ville.
>
> Le `propertyAddress` figé sur `leases` est écrit par `createLease` avec cette
> fonction, et n'est **jamais re-synchronisé** ensuite (exigence loi 1989).
> Corriger un bien après coup ne corrige donc ni les baux existants, ni a
> fortiori les quittances déjà émises — celles-ci sont immuables par les règles.
> Rattrapage des baux : `functions/scripts/backfill-lease-property-address.mjs`
> (dry-run par défaut, base à passer explicitement).

> ### Couleur d'identité — `colorKey` (FEAT-044d, 2026-08-12)
>
> **On stocke une CLÉ, jamais une couleur brute.** Un code hexadécimal figé
> aurait été illisible en mode sombre ; la clé est résolue en `Color` via
> `PropertyColorPalette` selon le thème.
>
> **8 teintes** : rouille, bordeaux, prune, cobalt, ardoise, sauge, moutarde,
> rosePoudre. Choisies pour s'accorder au thème papier/encre/olive — jamais
> criardes, et volontairement à l'écart de l'olive (couleur primaire) et de
> l'oxblood (erreurs).
>
> **Biens existants** (création avant cette fonctionnalité, ou sans couleur
> assignée) : repli **déterministe** sur un hash FNV-1a de l'id (non
> `Object.hashCode` qui n'est pas stable Dart d'une exécution à l'autre).
> Immédiate, sans rattrapage serveur.
>
> **Propagation** (FEAT-044e, visuel) : couleur appliquée aux cartes biens,
> baux, locataires, quittances. Fond : mélange (Color.alphaBlend) de la teinte
> avec le token de surface courant (opacité 8 %) — adapte à chaque thème,
> maintient le contraste AA (WCAG 4,5:1 sur tous les cas).

**Règles Firestore** :
- `get` : isOwner(landlordId) && isActive(rsc)
- `list` : isOwner(landlordId) — **pas d'`isActive`** (délibéré, audit FEAT-045 : le filtrage soft-delete est un choix de requête du propriétaire, pas un enjeu d'accès)
- `create` : **if false** (CF-exclusive via `createProperty`/FEAT-044)
- `update` : isFullyAuthed() && isOwner(landlordId) && isActive(rsc) && preservesImmutables(rsc) && `activeLeaseCount` inchangé (dénorm CF only)
- `delete` : **if false** (soft-delete CF exclusive)

**Indexes** (2, vérifiés dans `firestore.indexes.json`) :
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
- `get` : isOwner(landlordId) && isActive(rsc)
- `list` : isOwner(landlordId) — **pas d'`isActive`** (cf. properties, audit FEAT-045)
- `create` : **if false** (CF-exclusive via `createTenant`/FEAT-044)
- `update` : isFullyAuthed() && isOwner(landlordId) && isActive(rsc) && preservesImmutables(rsc) && `activeLeaseCount` inchangé
- `delete` : **if false**

**Indexes** (2, vérifiés dans `firestore.indexes.json`) :
- landlordId ↑, deletedAt ↑, lastName ↑ (list search)
- landlordId ↑, deletedAt ↑, createdAt ↓ (recent first)

> ⚠️ Il n'existe **pas** d'index `(landlordId, deletedAt, firstName)` — l'état l'annonçait à tort. Un tri par `firstName` échouerait en index manquant.

**Triggers** : setUpdatedAt.
