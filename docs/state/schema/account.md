# Schéma — account

> Source d'état — account. Maintenu par `state-keeper`.

Collections : `landlords`, `paid_plan_interest`, `support_requests`. Patterns transverses → [README](README.md).

---

## `landlords/{uid}` — docId = Firebase Auth UID

Auth + tiers de compte (anonymous/free/paid). BAILLAN-M1 système 3-états.

| Champ | Type | Valeur | Immuable |
|---|---|---|---|
| `id` | string | Firebase Auth UID | ✅ |
| `email` | string\|null | null (anon) / email (compte) | ✅ |
| `fullName` | string | '' (anon) / nom complet | ✅ |
| `isAnonymous` | bool | true (essai) / false (compte) | ✅ |
| `subscriptionTier` | string | 'anonymous' \| 'free' \| 'paid' | ✅ |
| `anonExpiresAt` | timestamp | expiration essai (14j) | — |
| `fullName` | string | '' (anon) / nom complet | ✅ |
| `phone` | string\|null | téléphone (optionnel) | — |
| `address` | string\|null | adresse postale (requis pour quittances) | — |
| `rgpdConsentAt` | timestamp\|null | null (anon) / date signature | ✅ |
| `rgpdConsentVersion` | string | v3-2026-07 (v1-2026-06 legacy ; v2-2026-07 ancien) | ✅ |
| `activePropertiesCount` | int | FEAT-044 : biens actifs (dénorm, maintenu CF exclusive) | — |
| `activeTenantsCount` | int | FEAT-044 : locataires actifs (dénorm, maintenu CF exclusive) | — |
| `activeLeasesCount` | int | FEAT-044 : baux actifs (dénorm, maintenu CF createLease/updateLease) | — |
| `createdAt` | timestamp | — | ✅ |
| `updatedAt` | timestamp | CF trigger | — |
| `deletedAt` | timestamp\|null | null (actif) / soft-delete | — |

**RLS** :
- `get` : isOwner(uid) && (resource==null \|\| isActive(rsc))
- `create` compte : isFullyAuthed() + RGPD consent v2-2026-07
- `create` anon : isAnonymous() + anonExpiresAt <= now+15j
- `update` compte : isFullyAuthed() && preservesImmutables()
- `update` anon : isAnonymous() && anonExpiresAt valide
- `delete` : interdit (soft-delete CF)

**Index** : `isAnonymous ↑, anonExpiresAt ↑` (expiration cleanup).

**Triggers** : setUpdatedAt.

**Callables** :
- `softDeleteLandlord` : soft-delete compte
- `cleanupExpiredAnon` (scheduled) : purge anonymes expirés (hard-delete 14j)
- `finalize_anonymous_upgrade` : transition anon → compte (met à jour subscriptionTier)

---

## `paid_plan_interest/{uid}` — docId = Firebase Auth UID, BAILLAN-M1

Marque d'intérêt futur Plan Pro. Singleton par compte complet (anonyme non éligible). **CREATE-ONLY** depuis KPI dashboard.

| Champ | Type | Notes |
|---|---|---|
| `uid` | string | Firebase Auth UID, docId, immuable |
| `features` | array[string] | ex: ['reminders', 'ocr'] |
| `createdAt` | timestamp | immuable |

**RLS** :
- `get` : isOwner(uid)
- `create/update` : isFullyAuthed() && isOwner(uid)
- `delete` : interdit

---

## `support_requests/{id}` — CREATE-ONLY (FEAT-025)

Formulaire « Nous contacter ». Traitement Admin SDK / console (pas de back-office in-app V1).

| Champ | Type | Notes |
|---|---|---|
| `id` | string | UUID, docId, immuable |
| `landlordId` | string | FK → landlords.id, immuable |
| `email` | string | adresse contact |
| `subject` | string | objet (≤ 120 chars) |
| `message` | string | contenu (≤ 2000 chars) |
| `appVersion` | string | ex: 1.0.0+1 |
| `appEnv` | string | dev \| staging \| prod |
| `status` | string | 'new' (jamais changé client) |
| `createdAt` | timestamp | request.time, immuable |

**RLS** :
- `get/list` : false (jamais relu V1)
- `create` : isFullyAuthed() && landlordId==uid + bornes subject/message
- `update/delete` : false
