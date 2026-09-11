# Functions — Account

> Source d'état — account. Maintenu par state-keeper.

Auth/provisioning, cycle de vie compte, soft-delete universel, crons, **facturation multi-paliers Pro/Max/Ultra** (FEAT-056), support, helpers génériques. Fichiers : `functions/src/callable/{finalize_anonymous_upgrade,delete_account,export_account_data,soft_delete,create_checkout_session,manage_subscription,scenarios}.ts`, `functions/src/http/revenuecat_webhook.ts`, `functions/src/scheduled/{cleanup_expired_anon,reconcile_entitlements}.ts`, `functions/src/entitlements/{plan,plan_matrix.generated,stripe_prices}.ts`, `functions/src/utils/callable_helpers.ts`, `functions/src/triggers/set_updated_at.ts`.

## Auth (ADR 0001 : GCIP désactivé)

| Élément | Statut | Note |
|---|---|---|
| `handleNewUser` | ❌ SUPPRIMÉ (FEAT-030, commit 90eb86f, 2026-07-05) | GCIP/Identity Platform non activé ; blocking `beforeUserCreated` n'existait qu'en code |

**Provisioning 100 % client** (`auth_repository.dart`, Riverpod) : chemins `signUpWithEmail`, `linkGoogle`, `linkApple`, `signInAnonymously` → crée `landlords/{uid}` GET-then-create (idempotent), même schéma garanti.

## Callables

### `finalizeAnonymousUpgrade` (BAILLAN-M1, FEAT-019)
Client invoke. Déclencheur : anonyme clique « Créer un compte » après essai 14 j.
- **Validations** : user doit être anonyme ; au moins un provider doit être lié (email/password / Google / Apple) — `providerData.length > 0` ; email non-existant (aucun autre user même email). Garde contre un anonyme pur qui invoquerait la callable.
- **Mutations** (transact Admin SDK) update `landlords/{uid}` : `isAnonymous=false`, `subscriptionTier='free'`, `rgpdConsentAt=now()` (consent signup), `rgpdConsentVersion=CURRENT_RGPD_VERSION` (v3-2026-07), **`email`+`fullName` depuis Firebase Auth** (fonction pure `resolveUpgradeIdentity`), `anonExpiresAt=null`. **Bug corrigé** (commit 2e3c762, 2026-08-08) : l'ancien code ne renseignait pas ces champs — un compte upgradé restait sans nom ni email. Logique v3 : lit `authUser.email`/`displayName` niveau supérieur puis chacun de `providerData` (sur un `linkWithPopup` Google, `displayName` peut être `undefined` au sommet mais présent chez le fournisseur) ; **ne réécrit jamais par-dessus une valeur déjà renseignée** ; dernier repli du nom : l'email. Preserve `investment_scenarios` (landlordId==uid constant, **pas de migration**).
- **Retour** : `{ok:true, tier}`. Fichier `finalize_anonymous_upgrade.ts`. Tests `__tests__/finalize_anonymous_upgrade.test.ts` + `resolveUpgradeIdentity` pur en unitaire.

### `deleteAccount` (FEAT-045, RGPD art. 17)
Client invoke, **tout compte authentifié y compris anonyme**. Exigence stores : Google Play « Account deletion » (13327111) + App Store 5.1.1(v).
- **Garde** : token non-anonyme dont `auth_time` > 5 min → `failed-precondition` (`recent-login-required`) ; client réauthentifie juste avant (mot de passe/OAuth). Sessions anonymes **exemptées** (Admin SDK `getUser().providerData` vide ; claim `sign_in_provider` reste `'anonymous'` sur tokens émis avant upgrade par linking).
- **Purge (ordre)** : 1. `receipts` du landlord **CONSERVÉES** (loi 6/7/1989, 5 ans) — stamp `accountDeletedAt`+`retentionUntil` (purge différée futur cron) ; 2. hard-delete paginé 400/batch `properties, tenants, leases, payments, documents (y c. legalHold — flux client avertit), expenses, investment_scenarios, support_requests` (`where landlordId==uid`) ; 3. singletons `paid_plan_interest/{uid}`+`landlords/{uid}` ; 4. Storage `deleteFiles(documents/{uid}/)` ; 5. **Auth EN DERNIER** `admin.auth().deleteUser(uid)` (idempotent user-not-found).
- **Invariant** : ordre **inverse** de `cleanupExpiredAnon` — retry porté par l'utilisateur encore connecté, échec en cours laisse Auth vivant pour relancer.
- **Révocation Apple** : côté **CLIENT** avant l'appel (`revokeTokenWithAuthorizationCode` avec authorizationCode de la re-auth ; iOS/macOS, best-effort ailleurs).
- **Retour** : `{deleted:true, receiptsRetained:number}`. Fichier `delete_account.ts`. Tests `delete_account.test.ts` + `rules-tests/firestore_rules.test.ts` (**16 cas**, `npm run test:rules` — l'ancien « 28 tests » ne correspondait à aucun décompte du fichier).

### `exportAccountData` (FEAT-047, RGPD art. 15 accès + art. 20 portabilité)
Client invoke depuis Profil (« Exporter mes données »). Lecture seule, `dbForRequest`. **Même garde d'auth récente** que `deleteAccount` (helper partagé `assertRecentAuthForNonAnonymousAccount`, anonymes exemptés).
- **Lit** (`where landlordId==uid`) : `properties, tenants, leases, payments, receipts, documents, expenses, investment_scenarios, support_requests` + singletons `landlords/{uid}`, `paid_plan_interest/{uid}`. Enregistrements soft-deleted **inclus** (transparence). Fichiers binaires **référencés** (chemins Storage), pas empaquetés.
- **Retour** : JSON structuré unique `{exportedAt, schemaVersion:1, account, paidPlanInterest, <collections>}`, Timestamp → ISO. **Inline** (pas d'objet Storage). Isolation cross-user = filtre `landlordId` sur chaque requête (Admin SDK bypasse les rules). Fichier `export_account_data.ts`, tests `export_account_data.test.ts`.

### `softDeleteEntity` (universel)
Signature `{collection, docId}`. Soft-delete unifié (spec canonique) ; le soft-delete des `documents` passe par ce callable universel — pas de `softDeleteDocument` dédié (voir expenses-documents).
- **Par collection** : `landlords`/`properties`/`tenants` → vérifier no active leases ; `leases` → OK (trigger `activeLeaseCount` decrement) ; `payments` → OK (trigger `recomputeReceiptStale`) ; `receipts` → **REFUSE** (immuable, loi 6/7/1989) ; `documents` → check `legalHold` (refuse si true) ; `expenses` → OK (FEAT-041) ; `investment_scenarios` → OK.
- **Mutations** : `deletedAt=now()` ; si collection in `[properties, tenants]` && `status=='active'` → DECREMENT `activeLeaseCount` ; idempotent.
- **Erreurs** : FAILED_PRECONDITION (legalHold==true / active leases / receipts), NOT_FOUND, PERMISSION_DENIED.
- **Retour** : `{success:true}`. Fichier `soft_delete.ts`.

### `createCheckoutSession` (FEAT-044 paiement web, PR #117 ; étendu 3 paliers FEAT-056)
Signature `{plan: 'monthly'|'annual', level?: 'pro'|'max'|'ultra'}` → `{url, sessionId}`. Crée une **Stripe Checkout Session** d'abonnement et renvoie l'URL hostée. Fichier `callable/create_checkout_session.ts`.
- **Routage Firestore** (ADR 0003) : utilise `dbForRequest(request)` → écrit la base prod ou staging selon l'Origin.
- **N'accorde AUCUN droit** : elle initie le paiement, le déverrouillage reste 100 % serveur via `revenueCatWebhook`.
- **Paliers multi-tiers** (FEAT-056) : `pro` (achetable, `purchasable:true`), `max` (démo UI, `purchasable:false`), `ultra` (démo UI, `purchasable:false`). Seul `pro` rejette le checkout ; les autres renvoient `level_not_purchasable`. Signature de rétrocompatibilité : omission de `level` → `pro`.
- **Lien de compte** : l'App User ID RevenueCat (= UID Firebase) est posé en metadata `rc_app_user_id` sur la **session ET** `subscription_data` (RevenueCat lit les deux) + `client_reference_id` en ceinture-bretelles. ⚠️ La clé DOIT correspondre exactement au champ configuré côté dashboard RevenueCat.
- **Redirections** : `{WEB_APP_BASE_URL}/pro/success?session_id=…` et `/pro/cancel` → routes GoRouter déclarées (voir routes/account).
- **Logique pure testée** : `buildCheckoutSessionParams` (5 cas).

### `manageSubscription` (FEAT-044f art. L215-1-1 « 3 clics », FEAT-056 changement palier)
Signature `{action: 'cancel'|'reactivate'|'change_plan', level?: 'pro'|'max'|'ultra', plan?: 'monthly'|'annual'}` → `{status, cancelAtPeriodEnd}` ou `{status, level, period, effectiveAt}`. Gère le cycle de vie d'un abonnement Stripe **web uniquement** (Mobile IAP renvoie vers le store). Fichier `callable/manage_subscription.ts`.
- **Actions** :
  - `cancel` : programme la résiliation à fin de période (`cancel_at_period_end=true`), conforme art. L215-1-1.
  - `reactivate` : annule une résiliation programmée (`cancel_at_period_end=false`).
  - `change_plan` : passe au palier/périodicité visé. Effet **immédiat, proratisé dans les deux sens** (montée : surplus facturé ; descente : avoir reporté sur factures suivantes).
- **N'ÉCRIT PAS Firestore** : le tier et `planLevel` restent écrits UNIQUEMENT par le webhook RevenueCat (Admin SDK, bypass rules) ; le downgrade vers freemium suivra automatiquement après expiration (cron `reconcileEntitlements`). Source autoritaire unique garantie.
- **Sécurité IDOR** : le client ne fournit JAMAIS d'ID Stripe ; la fonction dérive l'UID puis résout l'abonnement par metadata `rc_app_user_id` (posée au checkout). Aucun palier, aucun item, aucun price ID ne peut être transmis directement.
- **Paliers non vendables** : `max`/`ultra` retournent `level_not_purchasable` si jamais visés (verrouillage serveur).
- **Stockless** : aucune recherche en Firestore ; appel Stripe Search API sur metadata.
- **Idempotence** : `noop` si changement déjà effectué (evite event RevenueCat parasite).

## HTTP — `revenueCatWebhook` (FEAT-044, PR #114)

`onRequest`, **1re fonction HTTP du codebase**. Fichier `http/revenuecat_webhook.ts`. Écrit `landlords/{uid}` via Admin SDK (bypass rules ; tier reste client-immuable).
- **Routage Firestore** (ADR 0003) : utilise `dbForLandlordUid(uid)` qui cherche le doc landlord en **prod d'abord** (fail-safe), puis staging. Ce pattern évite de dépendre d'une metadata Stripe/RevenueCat qui pourrait dériver — le webhook reste correct même si la propagation metadata change. **Discipline** : pour tester un paiement staging, utiliser un uid **jamais utilisé en prod** (sinon le webhook routerait vers la mauvaise base).
- **Auth** : header `Authorization` comparé en **temps constant** (`timingSafeEqual`) au secret `REVENUECAT_WEBHOOK_AUTH`. Non signé → 401. Non-POST → 405.
- **Mapping type → accès** : `INITIAL_PURCHASE`/`RENEWAL`/`UNCANCELLATION`/`PRODUCT_CHANGE`/`SUBSCRIPTION_EXTENDED` → `paid` ; `NON_RENEWING_PURCHASE` → `paid` non renouvelable ; `CANCELLATION`/`BILLING_ISSUE` → `paid` tant que non expiré (délai de grâce) ; `EXPIRATION`/`SUBSCRIPTION_PAUSED` → `free` ; `TRANSFER`/inconnu/`TEST` → no-op.
- **Multi-paliers** (FEAT-056) : l'entitlement `rc_entitlement_id` reçu (ex: `"Bailan Pro"`, typo historique load-bearing) détermine le palier via lookup dans plan_matrix.generated.ts ; seul `pro` existe côté RevenueCat actuellement, donc `max`/`ultra` restent inatteignables côté webhook (pas d'rcEntitlementId).
- **Invariants** : idempotent + **garde d'ordre** `proLastEventAtMs` (un event antérieur au dernier appliqué est ignoré → un RENEWAL retardé n'écrase pas une EXPIRATION) ; ignore les App User ID `$RCAnonymousID:*` et les landlords `isAnonymous` ; ignore les events ne portant pas l'entitlement `pro`.
- **Réponses** : toujours 2xx après traitement ; **500 uniquement sur panne inattendue** (déclenche le retry RevenueCat).
- **Essai gratuit 7 j** : déjà géré (`INITIAL_PURCHASE` period_type TRIAL → `paid` ; fin → `EXPIRATION` → `free`). Reste à câbler `trial_period_days` côté prix Stripe.

## Trigger

`setUpdatedAtLandlords` — `onDocumentUpdated(landlords)`. Logique standard `setUpdatedAt` (voir README). Fichier `set_updated_at.ts`.

## Scheduled

### `cleanupExpiredAnon` (BAILLAN-M1)
Cloud Scheduler + CF, **`0 3 * * *` en `Europe/Paris`** (et non « 2 AM UTC » comme indiqué jusqu'au 2026-07-21).
1. Query `landlords` where `isAnonymous==true && anonExpiresAt < now()` ;
2. Batch soft-delete par anonyme expiré : `leases`, `payments`, `receipts`, `properties`, `tenants`, `documents`, `expenses`, `investment_scenarios` ; puis **hard-delete** `landlords/{uid}` (vrai delete — rétention inutile anon) ;
3. Log count (Cloud Logging) ; idempotent (`deletedAt` check).

Fichier `scheduled/cleanup_expired_anon.ts`. Logs `firebase functions:log`.

### `reconcileEntitlements` (FEAT-044, PR #114 ; multi-paliers FEAT-056)
`onSchedule` **`30 3 * * *` `Europe/Paris`**, région `europe-west1`, secret `REVENUECAT_API_KEY`. Filet de sécurité des webhooks manqués. Fichier `scheduled/reconcile_entitlements.ts`.
1. Query `landlords` where `proEntitlementActive == true` (ensemble borné, `limit` 200), **filtre l'échéance dépassée EN MÉMOIRE** → aucun index composite requis ;
2. Re-vérifie chaque compte via l'API REST RevenueCat v1 (`/subscribers/{uid}`) ;
3. Corrige : plus d'entitlement → `free` (`downgraded`, applique un downgrade du palier effectif) ; échéance repoussée → conserve `paid` + met à jour `proExpiresAt` (`renewed`, cas du RENEWAL manqué).
- **Ne fait jamais d'upgrade** (`free` → `paid` reste du ressort du webhook seul). 
- **Multi-paliers** : pour l'instant ne gère que le retrait du seul entitlement `pro` existant ; max/ultra restent out-of-scope webhook. Fetcher injectable → coeur testable sans réseau.

## Support & intérêt payant

| Élément | Note |
|---|---|
| `support_requests` (FEAT-025) | ✅ DONE — create-only rules, **aucun callable** |
| `paid_plan_interest` | Singleton `{uid}` (purgé par `deleteAccount`) |

## Helpers génériques (`functions/src/utils/callable_helpers.ts`)

| Helper | Signature | Usage |
|---|---|---|
| `requireAuthUid()` | `(request) → string` | Extract + validate auth UID |
| `assertRecentAuthForNonAnonymousAccount()` | `(request, uid) → Promise<void>` | Rejette `recent-login-required` si compte non-anonyme au token > 5 min ; anonyme exempté (providerData). Partagé par `deleteAccount` + `exportAccountData` |
| `requireString()` | `(value, name) → string` | Non-empty string |
| `requireInt()` | `(value, name, {min,max}) → number` | Integer borné |
| `optionalString()` | `(value, name) → string\|null` | Optional string |
| `optionalInt()` | `(value, name, bounds) → number\|null` | Optional integer |
| `optionalTimestamp()` | `(value, name) → Timestamp\|null` | Optional timestamp |
| `toTimestamp()` | `(value, name) → Timestamp` | Coerce → Firestore timestamp |
| `asBag()` | `(data) → Record<string,any>` | Cast objet sûr |
| `dataOrFail()` | `(snap, entity) → any` | Extract data ou throw NOT_FOUND |
| `assertOwnedAndActive()` | `(doc, uid, entity) → void` | Ownership + isActive |
