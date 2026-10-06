# FEAT-044e — Achat intégré mobile (RevenueCat) — design

> Statut : validé par Daki le 2026-10-05 (brainstorming). Issue de suivi :
> #207 (bloquant pour la sortie des apps), #209 (liste blanche sandbox).
> Cadre : [ADR 0002](../../adr/0002-monetisation-baillan-pro-revenuecat.md)
> (RevenueCat, `purchases_flutter`, identité = uid Firebase).

## Objectif

Vendre l'abonnement **Pro** (mensuel et annuel) par l'**achat intégré** dans les
apps iOS et Android, conformément aux règles App Store 3.1.1 / 3.1.2 / 3.1.3(b)
et à la règle Paiements de Google Play, sans changer la source de vérité des
droits (Firestore, écrite par le webhook RevenueCat).

## Décisions produit (2026-10-05)

| Sujet | Décision |
|---|---|
| Écran d'achat | Écran Flutter maison : la page `/pro` existante en **mode store** (pas le paywall RevenueCat) |
| Produits v1 | **Pro mensuel + Pro annuel** uniquement (Max / Ultra : plus tard) |
| Prix stores | **Identiques au web** : 7,99 € / mois, 79 € / an |
| Essai gratuit | **Aucun** en v1 (cohérent avec le web ; l'offre gratuite existe) |
| Liste blanche sandbox | **Document Firestore prod** `_ops/sandboxAllowlist`, édité dans la console ; **achats App Store / Google Play uniquement** (amendement 2026-10-06) |
| Approche | **A** — le serveur reste la seule vérité ; l'achat est derrière un interrupteur `IAP_ENABLED`. Les approches « l'app débloque d'après `CustomerInfo` » et « Web Billing RevenueCat » sont **rejetées** |

## Contrainte de calendrier

Créer les produits exige l'accord **Paid Apps** (App Store Connect : identité,
banque, fiscalité) et un **profil marchand** (Google Play) — tous deux
dépendent de la micro-entreprise de Daki. Le code avance avant, testé avec un
faux service ; l'essai réel en sandbox vient après. D'où l'interrupteur
`IAP_ENABLED` (coupé par défaut) : chaque lot se merge sans effet visible.

## 1. Côté app

### Interrupteur et configuration — `lib/core/config/store_billing.dart`

- `isInAppPurchaseEnabled` = `isStoreApp && Env.iapEnabled`
  (`IAP_ENABLED`, `bool.fromEnvironment`, défaut `false`).
- `canOfferUpgrade` = `!isStoreApp || isInAppPurchaseEnabled`. Prédicat unique
  des textes d'incitation (§3).
- Clés publiques RevenueCat par dart-define : `REVENUECAT_APPLE_API_KEY`
  (`appl_…`), `REVENUECAT_GOOGLE_API_KEY` (`goog_…`). Publiques par nature (clés
  SDK) ; `scripts/check-secrets.sh` ne les cible pas. Clé absente alors que
  l'interrupteur est activé → achat désactivé et log d'erreur, jamais de crash.
- Override de test (`debugInAppPurchaseEnabledOverride`), sur le modèle de
  `debugIsStoreAppOverride`.

### Service d'achat — `lib/features/paid_plan/data/store_billing_service.dart`

Interface `StoreBillingService` + implémentation `RevenueCatStoreBillingService`
(seule classe qui importe `purchases_flutter`) + provider Riverpod :

| Méthode | Rôle |
|---|---|
| `configure()` | Au démarrage, seulement si `isInAppPurchaseEnabled` ; clé de la plateforme |
| `logIn(String uid)` / `logOut()` | Branchés sur `sessionStateProvider` : `logIn` pour un compte **complet** (`fullyAuthenticated`), `logOut` à la déconnexion. Jamais pour un anonyme |
| `fetchProOffer()` | Offre courante → `ProStoreOffer { monthly, annual }`, chacun avec `priceString` et période **lus dans le store** (localisés) — jamais les `priceLabel` figés de `config/entitlements.json` |
| `purchase(ProStorePackage)` | → `PurchaseOutcome` : `success`, `cancelled`, `pending` (contrôle parental, paiement différé), `error(code)` |
| `restore()` | « Restaurer les achats » → `success` / `nothingToRestore` / `error` |
| `managementUrl()` | URL de gestion de l'abonnement dans le store, si disponible |

L'implémentation mappe les erreurs du SDK (`PurchasesErrorCode`) vers ces
issues. Les tests d'écran utilisent un **faux** de l'interface.

### Écran d'achat — page `/pro` en mode store

Actif quand `isInAppPurchaseEnabled` :
- Pro mensuel et annuel aux prix du store ; bouton d'achat par offre.
- **« Restaurer les achats »**.
- Mentions 3.1.2 : renouvellement automatique, résiliation dans les réglages du
  store, liens CGU et Politique de confidentialité.
- Max et Ultra affichés « bientôt », sans achat.
- Compte **déjà Pro** (toute origine : web, autre store, liste blanche) :
  « Vous êtes déjà abonné » + où gérer, **aucun bouton d'achat**.
- Après `success` : écran **« Activation en cours… »** qui observe
  `landlordTierProvider` jusqu'au passage en Pro (écrit par le webhook).
  Au-delà de **60 s** : message rassurant + « Restaurer » + « Réessayer ».
- `pending` : message « Achat en attente de validation » (pas d'échec).
- `cancelled` : retour silencieux à l'écran.

Interrupteur coupé dans une app store : comportement actuel inchangé (message
neutre, aucun prix, aucun achat).

### Gérer son abonnement — section abonnement du profil

- Abonné via un store (`proStore` `app_store` / `play_store`) : bouton
  « Gérer dans l'App Store / Google Play » (`managementUrl()`, repli sur l'URL
  générique de gestion de la plateforme).
- Abonné web sur mobile : inchangé (statut + « Résilier », #206).

## 2. Côté serveur — liste blanche sandbox

### Document

`_ops/sandboxAllowlist` dans la base **prod `(default)`** (hors collection
`landlords`), champ `uids: string[]`.
- Règles Firestore : `match /_ops/{doc} { allow read, write: if false; }`
  (explicite, en plus du refus par défaut) + test de règles.
- Lu uniquement par les Functions (Admin SDK). Édité par Daki dans la console.

### Webhook RevenueCat (`handleRevenueCatEvent`)

Règle actuelle inchangée par défaut (SANDBOX → `staging`, PRODUCTION →
`(default)`, autre → ignoré). Exception :
- event **SANDBOX** d'un achat **App Store / Google Play** dont `app_user_id`
  est dans `uids` → appliqué à la base **prod** `(default)` uniquement ;
- un achat Stripe test (web staging) n'est jamais concerné, uid listé ou non ;
- la liste n'est lue que pour ces events (aucune lecture en plus pour les
  achats réels) ;
- lecture en échec → l'erreur remonte : 500, RevenueCat retente, rien n'est
  écrit (fail-closed).

> **Amendement 2026-10-06 (Daki)** : « au plus simple » — mobile = stores via
> RevenueCat, web = Stripe via RevenueCat. La liste ne couvre donc que les
> stores : sans cette restriction, un compte listé qui paie en carte test
> Stripe sur le staging obtenait en prod un Pro qui n'expire jamais. Lecture
> en échec : la règle initiale (staging + 200) perdait l'achat d'App Review,
> RevenueCat ne le renvoyant jamais ; un 500 le fait retenter.

### Cron `reconcileEntitlements`

- Lit la liste **une fois par passage**.
- uid listé : un entitlement adossé à un achat sandbox **App Store / Google
  Play** (`store` de l'API v1) est traité comme un vrai droit (prolonge,
  corrige le palier, retire ; le cron n'accorde jamais `free → paid`), au lieu
  d'être `sandboxShadowed`. Achat Stripe test : masqué comme pour tout uid.
- uid non listé : comportement actuel (#209 : masqué, n'accorde ni ne prolonge).
- Lecture en échec : passage sans liste (comportement actuel), `logger.error`.

### Expiration

Pas d'expiration dans la liste : l'abonnement sandbox Apple expire de lui-même
en quelques heures. Daki retire le compte quand la review est finie, et avant
de supprimer le compte de démo (`deleteAccount` ne touche pas à la liste).

## 3. Conformité et cas particuliers

- **3.1.1 / Paiements Play** : dans les apps, seul l'achat intégré est proposé ;
  ni Stripe, ni lien vers le web, ni prix web.
- **3.1.2** : cf. écran d'achat.
- **3.1.3(b)** : un abonné web retrouve Pro dans l'app (Firestore) et
  l'abonnement est achetable en achat intégré.
- **Textes d'incitation** (#207) passés sur `canOfferUpgrade` — actionnables
  (vers `/pro`) quand l'achat est actif, masqués sinon :
  `propertiesErrorLimitReached`, `tenantsErrorLimitReached`,
  `leasesErrorLimitReached`, `documentsUploadErrorFileTooLargeWithUpgrade`,
  `simulatorLimitReachedContentFree` / `Paid`, `chargeRegularizationProOnly`,
  `simulatorCompareProOnly`.
- **Pas de double abonnement** : compte déjà Pro → aucun achat proposé.
- **iOS ↔ Android** : uid partagé → Pro partout ; « Gérer » pointe vers le store
  d'origine.
- **Suppression du compte** : l'avertissement actuel reste (le serveur ne peut
  pas résilier un achat intégré).
- **Mentions légales (2.1)** : éditeur (Daki Studio, SIRET) — hors feature,
  prérequis de soumission (checklist de sortie).

## 4. Déroulé, tests, actions de Daki

### Lots (une PR chacun, interrupteur coupé)

1. **Serveur** : liste blanche (webhook + cron + règle + tests). Redéploie les
   Functions.
2. **App — fondations** : dépendance `purchases_flutter`, `IAP_ENABLED`,
   `StoreBillingService` + faux, `logIn`/`logOut` sur la session,
   `canOfferUpgrade` sur les textes d'incitation.
3. **App — parcours** : `/pro` en mode store, « Activation en cours… »,
   « Restaurer », « Gérer dans le store », « Vous êtes déjà abonné ».

### Tests automatiques

- App (faux service) : achat réussi / annulé / en attente / erreur ; délai
  d'activation dépassé ; restauration ; compte déjà Pro ; interrupteur coupé
  (textes masqués, aucun achat) ; `logIn` seulement pour un compte complet.
- Serveur : webhook SANDBOX store listé → prod, non listé → staging, Stripe
  test listé → staging, lecture en échec → 500 sans écriture ; cron listé /
  non listé / Stripe test / lecture en échec ; règle `_ops` refusée à tout
  client.

### Actions de Daki (après la micro-entreprise — checklist sur #207)

- **App Store Connect** : accord Paid Apps ; groupe d'abonnement « Pro »
  (mensuel 7,99 €, annuel 79 €, sans essai) ; testeur sandbox.
- **Play Console** : profil marchand ; abonnement Pro, offres de base mensuelle
  et annuelle (mêmes prix) ; testeurs de licence.
- **RevenueCat** : relier les deux stores ; attacher les produits à
  l'entitlement existant **« Bailan Pro »** (typo à conserver telle quelle) ;
  offre par défaut ; récupérer les clés `appl_` / `goog_`.
- **Compte de démo review** : créé en prod, uid ajouté à `_ops/sandboxAllowlist`.
- **Activation** : build avec `IAP_ENABLED=true` + clés ; essai sandbox (achat →
  Pro → restauration) ; soumission.

## Hors périmètre

Max / Ultra dans les stores, essai gratuit, codes promo, Sign in with Apple,
paywall RevenueCat, Web Billing RevenueCat.
