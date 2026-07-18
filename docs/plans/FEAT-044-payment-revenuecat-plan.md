# FEAT-044 — Paiement Baillan Pro (RevenueCat) : plan de mise en œuvre détaillé

> Décision d'architecture : [ADR 0002](../adr/0002-monetisation-baillan-pro-revenuecat.md) (accepté 2026-07-18).
> Ce plan détaille le **volet paiement** de FEAT-044. Le volet *enforcement*
> (plafonds free) est déjà livré — voir [FEAT-044-freemium-implementation-plan](FEAT-044-freemium-implementation-plan.md).

## 1. TL;DR

Câbler l'achat de **Baillan Pro** (une entitlement, mensuel 7,99 € + annuel 79 €)
sur les deux surfaces via **RevenueCat** : IAP natif sur mobile, RevenueCat Web
Billing (Stripe) sur web. Le paiement ne fait qu'**une chose côté produit** :
basculer `landlords/{uid}.subscriptionTier` entre `free` et `paid`, écrit par un
**webhook serveur** (nouvelle fonction `onRequest`) + réconcilié par un job
`onSchedule`. La serrure (`paid` + enforcement dans les 3 CF) existe déjà.

## 2. Périmètre

**Dans** : produits & prix (mensuel/annuel), SDK client (mobile + web), paywall
réel (remplace « Coming soon »), webhook de déverrouillage, réconciliation,
restauration d'achat, portail de gestion, TVA/facturation, restauration du gating
Pro-only côté simulateur, feature flag de rollout.

**Hors** (itérations ultérieures) : multi-tiers, offre Fondateur 59 € (promo à
activer après le socle), codes promo, essais gratuits, upsell/downsell in-app,
analytics de conversion avancés.

## 3. Prérequis externes — Phase 0 (délai réel, hors code)

| Tâche | Détail | Bloque |
|---|---|---|
| Statut **trader** Play + fiscal/bancaire | déclaration DSA trader (imposée par IAP), infos bancaires/impôts App Store Connect + Play Console | tout paiement mobile |
| Produits d'abonnement magasins | `pro_monthly`, `pro_annual` créés + prix par territoire + soumis à revue | build mobile |
| Projet **RevenueCat** | app iOS + android + web, entitlement **`pro`**, offering `default` mappant les 2 produits | tout |
| **RevenueCat Web Billing** (Stripe) | connecter Stripe, produits web, activer Apple Pay/Google Pay (vérif domaine Apple Pay) | build web |
| **Stripe Tax** | branché sur RC Billing pour la TVA UE (prix TTC UE) | conformité web |
| Secrets | `REVENUECAT_PUBLIC_SDK_KEY` (client), `REVENUECAT_WEBHOOK_AUTH` (serveur) — via le mécanisme de secrets existant (`docs/SECURITY.md`) | webhook + client |

> ⚠️ Re-vérifier au démarrage le stack de frais Apple/Google EU (DMA) — cf. ADR 0002 §Références.

## 4. Modèle de données & API

### `landlords/{uid}` — nouveaux champs (écrits **serveur uniquement**)

| Champ | Type | Notes |
|---|---|---|
| `proEntitlementActive` | bool | cache de l'entitlement `pro` RevenueCat (source : webhook/réconciliation) |
| `proStore` | string\|null | `'app_store'` \| `'play_store'` \| `'web'` \| `'promo'` |
| `proProductId` | string\|null | `pro_monthly` \| `pro_annual` |
| `proSince` | timestamp\|null | 1er achat actif |
| `proExpiresAt` | timestamp\|null | fin de période payée (renouvellement ou expiration) |
| `proWillRenew` | bool | auto-renouvellement actif (pour l'UI « expire le… ») |

`subscriptionTier` reste **dérivé** : `proEntitlementActive === true` ⇒ `'paid'`,
sinon `'free'` (jamais `'anonymous'` : un anon ne peut pas acheter). L'App User ID
RevenueCat **EST** l'UID Firebase (pas de champ de mapping séparé).

### Règles Firestore

- Les nouveaux champs `pro*` sont **client-immuables** (même politique que
  `subscriptionTier`) — seul le webhook/Admin les écrit. Ajouter au
  `preservesImmutables()` de `match /landlords/{uid}`.
- Aucun autre changement : le modèle « seul le serveur écrit le tier » tient.

### Cloud Functions

| Fonction | Type | Rôle |
|---|---|---|
| `revenueCatWebhook` | **`onRequest`** (nouveau pattern) | reçoit les events RC, vérifie l'auth, écrit les champs `pro*` + `subscriptionTier` |
| `reconcileEntitlements` | `onSchedule` (quotidien) | re-sync depuis l'API RC les comptes dont `proExpiresAt` approche/dépassé ou en `BILLING_ISSUE` |

## 5. Plan de build par phase

### Phase 1 — Spike Flutter Web + RC Web Billing (**dérisque le risque n°1**)
- Prototype jetable : `purchases_flutter` (ou SDK web RC) sur Flutter Web →
  afficher l'offering, lancer un checkout sandbox, encaisser un paiement test.
- **Go/No-Go** : si Flutter Web + RC Web Billing n'est pas viable, réévaluer
  l'ADR (repli Stripe-direct web). **Ne rien construire d'autre avant ce Go.**
- Sortie : note de faisabilité + version SDK figée.

### Phase 2 — Backend (déverrouillage autoritaire)
- `functions/src/callable/…` → nouveau `functions/src/http/revenuecat_webhook.ts`
  (`onRequest`, région `europe-west1`) :
  - vérifier l'en-tête `Authorization` (secret partagé RC) — rejeter sinon `401` ;
  - parser l'event ; **idempotence** (event id déjà traité → `200` no-op) ;
  - mapper `type` → action :
    `INITIAL_PURCHASE`/`RENEWAL`/`UNCANCELLATION`/`NON_RENEWING_PURCHASE` → `paid` ;
    `EXPIRATION`/`CANCELLATION`(à expiration) → `free` ;
    `BILLING_ISSUE` → conserver `paid` jusqu'à `proExpiresAt` (grâce), flaguer ;
  - transaction : écrire `pro*` + recalculer `subscriptionTier` ;
  - toujours répondre `200` après traitement (RC retry sur non-2xx).
- `reconcileEntitlements` (`onSchedule`) : requête bornée sur `proExpiresAt`/
  `BILLING_ISSUE`, appel API RC (`GET subscriber`), corrige les dérives.
- **Tests** (harnais `helpers/fake_firestore`, comme les CF existantes) : chaque
  type d'event → bon tier ; idempotence ; signature invalide → 401 ; grâce
  billing ; réconciliation d'un event manqué.
- Déploiement : `firebase deploy --only functions` (ADR 0001 — pas de blocking
  trigger). Indexes si requête de réconciliation le nécessite.

### Phase 3 — Mobile IAP (`purchases_flutter`)
- Ajouter `purchases_flutter` ; init avec `REVENUECAT_PUBLIC_SDK_KEY` ;
  `Purchases.logIn(firebaseUid)` au login, `logOut()` au logout.
- **Paywall réel** : remplacer `ComingSoonPaidPlanSection` / le CTA de
  `ScenarioLimitReachedModal` par un écran d'offering (prix live depuis RC :
  mensuel/annuel) → `Purchases.purchasePackage(...)`.
- **« Restaurer les achats »** (exigence Apple) + gestion des états
  (achat en cours, annulé, erreur).
- L'UI de tier reste pilotée par `landlordTierProvider` (Firestore) — le SDK RC
  sert à *acheter*, la vérité d'accès vient du webhook → Firestore.

### Phase 4 — Web billing
- Bouton « Passer à Pro » (web) → checkout RC Web Billing (Stripe ; Apple Pay/
  Google Pay comme wallets).
- **Portail de gestion** (hébergé) : changer/annuler l'abonnement, moyen de
  paiement, factures.
- Parité avec le paywall mobile (mêmes prix TTC).

### Phase 5 — Conformité, légal, QA
- **TVA** : Stripe Tax actif, prix TTC UE, factures conformes.
- **Rétractation UE 14 j** : consentement explicite à l'exécution immédiate au
  moment de l'achat (renonciation) ; **CGV** mises à jour ; mentions
  d'auto-renouvellement.
- **Revue magasins** : paywall fonctionnel (zéro « coming soon »), « Restaurer »,
  parité de prix (Guideline 3.1.3). Cocher `docs/STORE_COMPLIANCE.md`.
- **QA multi-plateforme** : sandbox App Store / Play + Stripe test — achat,
  renouvellement, annulation, expiration, échec de paiement, restauration ; +
  test que le webhook bascule bien `subscriptionTier` (émulateur, cf.
  `tool/seed/seed_tiers.mjs` et le toggle émulateur pour QA UI).

### Phase 6 — Gating Pro-only (dépend du paiement)
- Débrider côté `paid` les fonctionnalités Pro promises dans le paywall
  (comparateur multi-scénarios, sensibilité taux, LMNP/LMP, export PDF — cf.
  la liste « Coming soon » actuelle). À planifier feature par feature.

## 6. Rollout

- **Feature flag** `PRO_PURCHASE_ENABLED` (dart-define, comme le toggle émulateur)
  pour masquer le paywall jusqu'à validation store — évite un « coming soon » vu
  en revue et permet un lancement web avant mobile.
- Ordre conseillé : **web d'abord** (itération rapide, pas de revue store), puis
  mobile après approbation des produits d'abonnement.

## 7. Risques & à vérifier au build

- **Flutter Web + RC Web Billing** (maturité) → Phase 1 est un *gate*.
- **Fiabilité webhook** → la réconciliation `onSchedule` est **obligatoire**.
- **Premier `onRequest`** du codebase → sécuriser signature + idempotence + tests.
- **Stack de frais Apple/Google EU (DMA)** → re-vérifier (ADR 0002).
- **TVA merchant-of-record web** → ne pas lancer le web sans Stripe Tax + factures.
- **Revue store** → paywall complet + restauration, sinon rejet.

## 8. Questions ouvertes (à trancher)

1. Offre **Fondateur 59 €** : promo RC dès le lancement ou après le socle ?
2. **Essai gratuit** (7/14 j) au lancement, ou pas ?
3. Web **avant** mobile (recommandé) ou simultané ?
4. Adopter l'extension Firebase Stripe pour le web, ou 100 % RC Web Billing
   (l'ADR tranche pour RC Web Billing — confirmer au spike Phase 1) ?

## 9. Prochaine étape immédiate

**Phase 0 (comptes/produits) en parallèle du spike Phase 1.** Aucun autre
développement tant que le Go/No-Go du spike Flutter Web + RC Web Billing n'est pas
posé.
