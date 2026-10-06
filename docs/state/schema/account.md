# Schéma — account

> Source d'état — account. Maintenu par `state-keeper`.

Collections : `landlords`, `paid_plan_interest`, `support_requests`. Patterns transverses → [README](README.md).

---

## `landlords/{uid}` — docId = Firebase Auth UID

Auth + tiers de compte (anonymous/free/paid). BAILLAN-M1 système 3-états.

| Champ | Type | Valeur | Immuable |
|---|---|---|---|
| `id` | string | Firebase Auth UID | ✅ |
| `email` | string\|null | null (anon) / email (compte). **Nullable à dessein depuis commit d7d56cc** (2026-08-08) : `LandlordProfile` pouvait échouer `fromJson` si ce champ était null. Source de vérité pour l'UI : Firebase Auth (fallback). | ✅ |
| `fullName` | string | '' (anon) / nom complet | ✅ |
| `isAnonymous` | bool | true (essai) / false (compte) | ✅ |
| `subscriptionTier` | string | 'anonymous' \| 'free' \| 'paid' (classe d'accès, inchangée) | ✅ |
| `planLevel` | string\|null | **FEAT-056** : 'pro' \| 'max' \| 'ultra' \| null (anonymous/free/anonyme sans upgrade) ; gelé client (immuable règles) | ✅ client |
| `entitlements` | map[string] | **FEAT-056** : état par palier (ex: `{pro: {active, expiresAt}, max: ...}`), gelé client | ✅ client |
| `anonExpiresAt` | timestamp | expiration essai (14j) | — |
| `phone` | string\|null | téléphone (optionnel) | — |
| `address` | string\|null | adresse postale (requis pour quittances) | — |
| `rgpdConsentAt` | timestamp\|null | null (anon) / date signature | ✅ |
| `rgpdConsentVersion` | string | **v3-2026-07** (v1-2026-06 legacy ; v2-2026-07 ancien). Constante serveur `CURRENT_RGPD_VERSION` dans `functions/src/callable/finalize_anonymous_upgrade.ts` — source de vérité. | ✅ |
| `activePropertiesCount` | int | FEAT-044 : biens actifs (dénorm, maintenu CF exclusive) | — |
| `activeTenantsCount` | int | FEAT-044 : locataires actifs (dénorm, maintenu CF exclusive) | — |
| `activeLeasesCount` | int | FEAT-044 : baux actifs (dénorm, maintenu CF createLease/updateLease) | — |
| `createdAt` | timestamp | — | ✅ |
| `updatedAt` | timestamp | CF trigger | — |
| `deletedAt` | timestamp\|null | null (actif) / soft-delete | — |

**Champs `pro*` (FEAT-044 paiement, PR #114)** — écrits UNIQUEMENT par `revenueCatWebhook` / `reconcileEntitlements` via Admin SDK (bypass rules). Cache d'affichage : la source de vérité de l'accès reste `subscriptionTier`.

| Champ | Type | Notes |
|---|---|---|
| `proEntitlementActive` | bool | entitlement `pro` actif. Requêté par le cron (`== true`) |
| `proStore` | string\|null | `app_store` \| `play_store` \| `web` (Stripe/RC Billing) \| `promo` |
| `proProductId` | string\|null | product ID RevenueCat/store |
| `proExpiresAt` | timestamp\|null | échéance de l'entitlement |
| `proWillRenew` | bool | auto-renouvellement actif |
| `proSince` | timestamp\|null | 1re activation, **conservé après downgrade** (audit) |
| `proLastEventAtMs` | int | garde d'ordre : un event antérieur est ignoré (idempotence webhook) |

**Aucun compteur `activeDocumentsCount`** : le quota documents free (10) est compté **live** (`count()` sur `documents` where `deletedAt == null`) — voir [expenses-documents](expenses-documents.md). Choix délibéré : le soft-delete est universel, donc sans compteur il n'y a rien à décrémenter ni à faire dériver.

**Règles Firestore** :
- `get` : isOwner(uid) && (resource==null \|\| isActive(rsc))
- `create` compte : `isSignedIn() && !isAnonymous() && auth.uid == uid` — **volontairement SANS `hasTrustedEmail()`** : `signUpWithPassword` écrit ce doc AVANT l'email de vérification (OWASP-02) ; tout le reste (get/update/données métier) exige un compte vérifié. + `rgpdConsentVersion` **chaîne non vide** (`firestore.rules:85-86` — la rule n'épingle AUCUNE version précise, contrairement à ce que ce shard affirmait jusqu'au 2026-08-11 ; c'est la callable qui impose `CURRENT_RGPD_VERSION`) + `email is string` + `fullName.size() > 0` ; planLevel/entitlements gelés à null/absent (FEAT-056)
- `create` anon : isAnonymous() + anonExpiresAt <= now+15j ; planLevel/entitlements gelés à null/absent (FEAT-056)
- `update` compte : isFullyAuthed() && preservesImmutables() && planLevel/entitlements immuables client (FEAT-056)
- `update` anon : isAnonymous() && anonExpiresAt valide && planLevel/entitlements immuables (FEAT-056)
- `delete` : interdit (soft-delete CF)

**Index** : `isAnonymous ↑, anonExpiresAt ↑` (expiration cleanup). Le cron d'entitlements interroge `proEntitlementActive == true` (égalité simple + filtre d'échéance en mémoire) → **aucun index composite requis**.

**Triggers** : setUpdatedAt.

**Écrivains du `subscriptionTier`** (le client ne peut JAMAIS l'écrire — immuable par les règles) :
- `finalizeAnonymousUpgrade` (callable) : anon → `free`. N'écrit jamais `paid`.
- `revenueCatWebhook` (HTTP) : `free` ⇄ `paid` selon l'entitlement. **Seul chemin vers `paid`.**
- `reconcileEntitlements` (scheduled) : filet de sécurité, corrige `paid` → `free` sur webhook manqué.

**Écrivains du `planLevel` et `entitlements`** (écrits UNIQUEMENT via Admin SDK, jamais client) :
- `revenueCatWebhook` (HTTP) : écrit `planLevel` et `entitlements` selon le produit reçu du webhook. **Source autoritaire unique.**
- `reconcileEntitlements` (scheduled) : met à jour `entitlements` lors du downgrade (expiration).
- **Jamais le client** : champs gelés par les règles Firestore à la création ET en update (`preservesImmutables`).

**Callables** :
- `softDeleteEntity` : soft-delete compte (nom réel de la callable universelle)
- `finalizeAnonymousUpgrade` : transition anon → compte (met à jour subscriptionTier)
- `deleteAccount` : suppression RGPD (FEAT-045)
- `createCheckoutSession` : initie le paiement web multi-paliers — **n'accorde aucun droit** (FEAT-056)
- `manageSubscription` : gère subscription Stripe web (cancel/reactivate/change_plan) — **n'écrit pas Firestore** (FEAT-056)

---

## `paid_plan_interest/{uid}` — docId = Firebase Auth UID, BAILLAN-M1

Marque d'intérêt futur Plan Pro. Singleton par compte complet (anonyme non éligible). **CREATE-ONLY** depuis KPI dashboard.

| Champ | Type | Notes |
|---|---|---|
| `uid` | string | Firebase Auth UID, docId, immuable |
| `features` | array[string] | ex: ['reminders', 'ocr'] |
| `createdAt` | timestamp | immuable |

**Règles Firestore** :
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

**Règles Firestore** :
- `get/list` : false (jamais relu V1)
- `create` : isFullyAuthed() && landlordId==uid + bornes subject/message
- `update/delete` : false

## `_ops/{docId}` — configuration serveur globale (FEAT-044e)

Aucune donnée de bailleur : hors export RGPD et hors purge `deleteAccount` (exemption dans le test de parité de `delete_account.test.ts`). Lu **uniquement** par les Functions (Admin SDK), **dans la base prod `(default)`** — un doc `_ops` en staging n'a aucun effet.

### `_ops/sandboxAllowlist`

| Champ | Type | Notes |
|---|---|---|
| `uids` | string[] | uids prod dont un achat RevenueCat **sandbox App Store / Google Play** vaut un vrai droit (compte de démo App Review, testeurs). Jamais un achat Stripe test. Entrées non-chaînes ou vides ignorées, espaces retirés |

Édité à la main dans la console Firebase (aucune expiration : retirer l'uid après la review, et avant de supprimer le compte de démo — `deleteAccount` ne touche pas à la liste). Lu par le webhook `revenueCatWebhook` (events `SANDBOX` seulement) et par le cron `reconcileEntitlements` (une fois par passage) — cf. [functions/account](../functions/account.md). Absent ou illisible → aucun uid (fail-closed).

**Règles Firestore** :
- `match /_ops/{docId}` : `allow read, write: if false` — explicite en plus du fallback. Un compte capable d'écrire ce doc s'y ajouterait et obtiendrait Pro gratuit. Testé (`firestore_rules.test.ts`, describe `_ops`).
