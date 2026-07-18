# ADR 0002 — Monétisation Baillan Pro : RevenueCat (IAP mobile + Web Billing)

- **Statut** : accepté (2026-07-18) — plan de mise en œuvre détaillé :
  [`docs/plans/FEAT-044-payment-revenuecat-plan.md`](../plans/FEAT-044-payment-revenuecat-plan.md)
- **Contexte technique** : Flutter (PWA web + apps natives iOS/Android) +
  Firebase (Firestore, Auth, Cloud Functions, Hosting) — projet `easy-rent-54cd4`
- **Feature** : FEAT-044 (monétisation freemium) — volet *paiement*, non couvert
  par l'implémentation actuelle

## Contexte

Le palier **`paid`** existe déjà comme cible d'unlock, mais **aucun chemin
d'achat n'est implémenté**. État actuel constaté :

- Le tier vit sur un seul champ : `landlords/{uid}.subscriptionTier` ∈
  `anonymous | free | paid`.
- **Enforcement à deux couches** : client (`landlordTierProvider` → UI, modales,
  boutons désactivés) et **serveur = source de vérité** — 3 fichiers de Cloud
  Functions gatent la création sur le tier (`property_tenant.ts`,
  `lease_payment.ts`, `finalize_anonymous_upgrade.ts`) → `resource-exhausted`
  au-delà des plafonds free (2 biens / 3 locataires / 2 baux).
- Les **règles Firestore rendent `subscriptionTier` immuable côté client**. Seul
  un write serveur (Admin SDK / Callable) peut le changer ; la seule Callable qui
  y touche (`finalizeAnonymousUpgrade`) n'écrit que `'free'`. **Le seul moyen de
  passer un compte en `paid` aujourd'hui est un write admin manuel.**
- Il n'existe **aucune fonction HTTP** (`onRequest`) dans le codebase — tout est
  `onCall` (24), `onDocumentUpdated` (5), `onSchedule` (2).
- Capture de demande en place : collection `paid_plan_interest` (« M'avertir du
  lancement ») + section UI « Coming soon — Pro plan ».
- Tarifs en test (cf. `docs/backlog/044-monetization-freemium.md`) : **7,99 €
  TTC/mois**, **79 € TTC/an**, offre Fondateur 59 € la 1re année.

### Contrainte structurante : web PWA **+** apps natives

- Sur **iOS/Android**, Apple (Guideline 3.1.1) et Google **imposent leur achat
  intégré (StoreKit / Play Billing)** pour un abonnement numérique déverrouillant
  des fonctionnalités *dans* l'app. Apple Pay / Google Pay sont des *wallets de
  carte* réservés aux biens/services physiques — **ils ne peuvent pas vendre
  l'abonnement dans l'app native** (rejet garanti).
- Sur le **web**, choix libre du processeur de paiement.

### Décisions produit actées (2026-07-18)

1. Vendre Pro sur **web ET mobile**.
2. **Un seul palier Pro** pour commencer (pas de multi-tiers).
3. **Mensuel + annuel**.

## Décision

**Adopter RevenueCat comme couche de monétisation unique**, sur les deux
surfaces :

- **Mobile** : achat intégré natif (StoreKit iOS / Play Billing Android) **wrappé
  par le SDK `purchases_flutter`**.
- **Web** : **RevenueCat Web Billing** (checkout web propulsé par Stripe ;
  Apple Pay / Google Pay disponibles comme boutons wallet *dans* le checkout web).
- **Une entitlement unique `pro`** mappée sur les deux produits (`pro_monthly`,
  `pro_annual`) côté App Store Connect, Play Console et dashboard RevenueCat.
- **Identité** : `Purchases.logIn(firebaseUid)` — la clé d'entitlement RevenueCat
  EST l'UID Firebase, ce qui lie l'abonnement au compte `landlords/{uid}`.
- **Déverrouillage serveur (autoritaire)** : **nouvelle fonction `onRequest`** —
  webhook RevenueCat (signature vérifiée) — qui, sur `INITIAL_PURCHASE` /
  `RENEWAL` / `CANCELLATION` / `EXPIRATION` / `BILLING_ISSUE`, écrit
  `landlords/{uid}.subscriptionTier = 'paid' | 'free'`. C'est le **seul** nouvel
  écrivain du tier ; **les règles Firestore restent inchangées** (tier immuable
  côté client — le modèle de sécurité actuel convient tel quel).
- **Réconciliation** : job `onSchedule` (pattern déjà utilisé) qui re-synchronise
  le tier depuis l'API RevenueCat — **obligatoire**, un webhook peut être manqué.

### Pourquoi RevenueCat plutôt que Stripe-direct-sur-web + IAP-mobile

Le comparatif de coût web penche légèrement vers Stripe-direct (économise le 1 %
MTR RevenueCat), **mais** RevenueCat Web Billing **n'ajoute aucun frais au-delà
du 1 % MTR standard** (gratuit sous 2 500 $ MTR/mois) — seuls s'appliquent les
frais Stripe (~2,9 % + 0,30 $). Au lancement (revenu faible), **RevenueCat est
gratuit**. Le gain d'une **intégration unique** (un SDK, une entitlement, un
webhook, un point de réconciliation) l'emporte sur ~1 % de marge à l'échelle,
d'autant que le mobile passe de toute façon par l'IAP magasin.

## Conséquences

### Positives ✅

- La **cible d'unlock existe déjà** (palier `paid` + enforcement dans les 3 CF) :
  l'intégration n'a qu'à « basculer `subscriptionTier` » quand l'abonnement
  s'active/expire. On câble un paiement sur une serrure déjà posée.
- **Modèle de sécurité inchangé** : `subscriptionTier` reste client-immuable,
  seul le webhook (serveur de confiance) l'écrit — cohérent avec les garde-fous.
- **Une seule intégration** cross-plateforme (vs deux billing systems à
  réconcilier).
- **Coût maîtrisé au lancement** : RevenueCat gratuit sous 2 500 $ MTR ; sur
  mobile le magasin reste *merchant of record* (il collecte/remet la TVA).
- Apple Pay / Google Pay récupérés **au bon endroit** : boutons wallet du
  checkout web Stripe.

### Obligations & risques ⚠️

- **Maturité Flutter Web + RevenueCat Web Billing** = risque n°1. À prototyper
  tôt (spike) avant d'engager le reste.
- **Nouvelle fonction `onRequest`** = premier récepteur HTTP du codebase :
  vérification de signature, idempotence, tests — nouveau pattern à sécuriser.
- **TVA (web uniquement)** : sur le web, **Baillan devient *merchant of record***
  (contrairement au mobile où Apple/Google le sont). Obligation de **collecter et
  reverser la TVA UE** (régime OSS/TVA sur services numériques), via **Stripe Tax**
  branché sur RevenueCat Billing (tarifs TTC pour l'UE ; frais Stripe Tax
  par transaction en sus). Facturation conforme à émettre.
- **Droit de la consommation UE** : abonnement = contrat ; **droit de rétractation
  14 j** (renonçable au moment de l'achat pour un service numérique — flux à
  prévoir), **CGV** à mettre à jour, mentions d'auto-renouvellement.
- **Revue magasins** : le paywall doit être **fonctionnel** (pas de « coming
  soon »), proposer **« Restaurer les achats »** (exigence Apple), et respecter la
  **parité de prix** (Guideline 3.1.3) si un jour on renvoie vers le tarif web.
- **Fiabilité webhook** → la **réconciliation `onSchedule` n'est pas optionnelle**
  (sinon un compte reste `paid`/`free` à tort après un event manqué).
- **Coût mobile** : commission magasin **15 %** (programme petites entreprises,
  < 1 M$/an) **ou 30 %**, **+ éventuels frais DMA UE** (Apple a introduit mi-2025
  une *Core Technology Commission* de 5 % applicable aux chemins de distribution
  UE ; empilement de frais mouvant). **À vérifier** : le stack de frais exact
  Apple/Google EU au moment du build (voir Références — cadre en évolution rapide).
- **Un seul mode de paiement par app sur une storefront UE** : Apple interdit
  d'offrir *à la fois* l'IAP magasin **et** un paiement alternatif dans la même app
  sur la même storefront UE. Notre choix (IAP magasin sur mobile) est le chemin
  **standard et compatible** — il évite volontairement la complexité DMA du
  paiement alternatif.

## Alternatives considérées (rejetées)

| Alternative | Rejet |
|---|---|
| **Stripe direct (web) + RevenueCat (mobile)** | Légèrement moins cher sur le web, mais **deux** intégrations + **deux** webhooks à réconcilier. Simplicité perdue pour un gain marginal au lancement. |
| **Apple Pay / Google Pay pour l'abonnement mobile** | **Interdit** (Guideline 3.1.1 / Play Payments) pour un abonnement numérique in-app → rejet magasin. |
| **StoreKit / Play Billing bruts (sans RevenueCat)** | Pas de frais RC, mais toute la validation de reçus, l'état d'abonnement cross-plateforme et le webhook à construire soi-même. |
| **Achat web uniquement (pas d'IAP mobile)** | Évite la commission mobile, mais **UX mobile dégradée** (pas d'upgrade in-app) et **risque de politique Apple** élevé. Option stratégique à instruire séparément, pas un simple câblage. |

## Plan de mise en œuvre (esquisse — plan détaillé à part)

0. **Décisions/comptes (externe, délai réel)** : App Store Connect + Play Console
   (produits d'abonnement, prix, fiscalité/bancaire, statut *trader* Play),
   projet + entitlement `pro` + offerings RevenueCat, Stripe (via RC Web Billing)
   + Stripe Tax.
1. **Spike Flutter Web + RC Web Billing** — dérisque le risque n°1 avant tout.
2. **Backend** : fonction `onRequest` webhook → write `subscriptionTier` +
   idempotence + tests ; job `onSchedule` de réconciliation.
3. **Mobile** : `purchases_flutter`, `logIn(uid)`, paywall réel (remplace « Coming
   soon »), achat + **restaurer les achats**.
4. **Web** : RC Web Billing (checkout + Apple Pay/Google Pay), portail de gestion.
5. **Conformité** : TVA/Stripe Tax, CGV + rétractation, checklist
   `docs/STORE_COMPLIANCE.md`, QA multi-plateforme.

## Références

- [Apple — Update on apps distributed in the EU (DMA)](https://developer.apple.com/support/dma-and-apps-in-the-eu/)
- [Apple — Communication and promotion of offers on the App Store in the EU](https://developer.apple.com/support/communication-and-promotion-of-offers-on-the-app-store-in-the-eu/)
- [RevenueCat — Apple EU DMA update (June 2025) : one entitlement, three fees, CTF 2026 sunset](https://www.revenuecat.com/blog/growth/apple-eu-dma-update-june-2025/)
- [RevenueCat — Web Billing](https://www.revenuecat.com/billing)
- [RevenueCat — Web Billing : Sales Tax & VAT](https://www.revenuecat.com/docs/web/web-billing/tax)
- [RevenueCat — Pricing & Plans](https://www.revenuecat.com/pricing)

> ⚠️ Le cadre de frais/politique magasins UE (DMA, liens externes, paiement
> alternatif) évolue vite. Les taux et règles ci-dessus datent de mi-2026 et
> **doivent être re-vérifiés** auprès d'Apple/Google au démarrage du build.
