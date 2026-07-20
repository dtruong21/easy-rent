# FEAT-044 — Paiement Baillan Pro : checklist vivante

> Suivi actionnable du volet **paiement** de FEAT-044. Cocher au fur et à mesure.
> Décision : [ADR 0002](../adr/0002-monetisation-baillan-pro-revenuecat.md)
> (+ §Amendement web) · Plan : [FEAT-044-payment-revenuecat-plan](FEAT-044-payment-revenuecat-plan.md).
>
> Architecture : **RevenueCat = plan de gestion** (source de vérité entitlements),
> checkout par plateforme — web → Stripe Checkout → RevenueCat ; mobile →
> StoreKit / Play Billing → RevenueCat → `revenueCatWebhook` → `subscriptionTier`.
>
> Dernière mise à jour : 2026-07-20.

## 🔴 À faire en premier — blocages & décisions

| # | Tâche | Resp. | Notes |
|---|---|---|---|
| 1 | ~~Rétablir le quota GitHub Actions~~ | Toi | ✅ **RÉSOLU 2026-07-20** — dépôt passé en **public** → Actions illimitées. Staging redéployé (build 305) + CI verte (dont le job `functions`). Peut repasser en privé plus tard : l'historique a été scanné, **aucun secret** exposé. |
| 3 | Décider : **offre Fondateur 59 €** au lancement ou plus tard ? | Toi | ⏳ ouvert — impacte le setup produits |
| 4 | ~~Décider : essai gratuit~~ | Toi | ✅ **DÉCIDÉ 2026-07-20 : essai gratuit de 7 jours** → voir #27 |
| 5 | Décider : **web avant mobile** ? | Toi | ⏳ ouvert — recommandé (pas de revue store sur le web) |

## 🎯 Matrice free / Pro (validée 2026-07-20)

| Fonctionnalité | Free | Pro | Note |
|---|---|---|---|
| Registre (biens / locataires / baux) | 2 / 3 / 2 | illimité | déjà en place (FEAT-044 enforcement) |
| Scénarios simulateur | 3 | illimité | déjà en place |
| **Quittance PDF + partage natif** | ✅ **OUI** | ✅ | 🔒 **NE PAS GATER** — voir encadré |
| Upload documents | quota (ex. 10) | illimité | coût stockage réel → #29 |
| Régularisation annuelle des charges | ❌ | ✅ | fonction « comptable » avancée → #28 |
| Rappels / envoi auto par email (FEAT-031) | ❌ | ✅ | **le vrai levier email** → #30 |
| Annonces multi-portails (FEAT-051) | ❌ | ✅ | déjà réservé Pro |
| Comparateur, sensibilité taux, LMNP, export PDF pro | ❌ | ✅ | déjà promis dans le paywall → #24 |

> 🔒 **La génération et le partage de quittance restent GRATUITS — décision ferme.**
> C'est le cœur de la promesse produit et l'instrument légal (loi 6 juillet 1989
> art. 21 : le bailleur doit fournir la quittance gratuitement sur demande). La
> gater viderait le tier free de sa valeur et donnerait l'impression de monétiser
> une obligation légale. **Ne pas revenir dessus sans réévaluer cet arbitrage.**

> ℹ️ **Précision « quittance par mail »** : il n'existe **aucun envoi d'email
> serveur** dans Baillan. La quittance est générée en PDF **côté client** puis
> partagée via **Web Share natif** (fallback download + `mailto:`) — donc le
> client mail de l'utilisateur, sans coût pour nous. Le vrai candidat au gating
> est l'**envoi automatisé serveur** (FEAT-031), qui reste à construire.

## 🟣 Setup dashboards RevenueCat + Stripe + stores (toi)

| # | Tâche | Resp. | Doit correspondre à |
|---|---|---|---|
| 6 | Créer le projet RevenueCat + **entitlement `pro`** | Toi | id `pro` (code) |
| 7 | Créer les produits/prix Stripe : **`pro_monthly` (7,99 €)**, **`pro_annual` (79 €)** | Toi | → `STRIPE_PRICE_PRO_MONTHLY/ANNUAL` |
| 8 | **Connecter le compte Stripe** à RevenueCat | Toi | — |
| 9 | Mapper les product IDs Stripe → entitlement `pro` | Toi | — |
| 10 | Configurer le champ metadata RevenueCat = **`rc_app_user_id`** | Toi | ⚠️ **exactement** = `RC_APP_USER_ID_METADATA_KEY` (code) |
| 11 | Activer **External Purchase Tracking** + pointer Stripe Server Notifications → RevenueCat | Toi | approche A |
| 12 | Récupérer les **public SDK keys** (iOS `appl_…`, Android `goog_…`) | Toi | pour le SDK client (≠ clé secrète) |
| 13 | Définir un **secret d'auth webhook** RevenueCat → pointer son webhook sur l'URL de la fonction déployée | Toi | → secret `REVENUECAT_WEBHOOK_AUTH` |
| 14 | Mobile : produits d'abonnement App Store Connect + Play Console, **statut trader** (Play), bancaire/fiscal | Toi | avant l'IAP mobile |

## 🟢 Config déploiement — secrets/params (toi, au moment de déployer)

| # | Commande / valeur | Pour |
|---|---|---|
| 15 | `firebase functions:secrets:set REVENUECAT_WEBHOOK_AUTH` | webhook |
| 16 | `firebase functions:secrets:set REVENUECAT_API_KEY` | réconciliation (clé REST secrète) |
| 17 | `firebase functions:secrets:set STRIPE_SECRET_KEY` | checkout |
| 18 | Params : `STRIPE_PRICE_PRO_MONTHLY`, `STRIPE_PRICE_PRO_ANNUAL`, `WEB_APP_BASE_URL` | checkout |
| 19 | `firebase deploy --only functions` (après 15–18) | livre webhook + reconcile + checkout |

## 🔵 Reste à construire (moi — surtout client)

| # | Tâche | Resp. | Dépend de |
|---|---|---|---|
| 20 | **Spike Flutter Web** — viabilité redirection Stripe Checkout | Moi | — (gate Go/No-Go) |
| 21 | UI paywall (remplace « Coming soon » ; prix live RevenueCat) | Moi | #6–7 |
| 22 | Web : redirection vers l'URL Stripe Checkout (appelle `createCheckoutSession`) | Moi | #7, #17–18 |
| 23 | Mobile : `purchases_flutter` (IAP + **Restaurer les achats**) | Moi | #12, #14 |
| 24 | Débrider les **fonctions Pro-only** pour `paid` (comparateur, export PDF, etc.) | Moi | — |
| 25 | Verrouiller les champs `pro*` dans les règles Firestore (durcissement optionnel) | Moi | — |
| 26 | ~~Ajouter la suite `functions` à la CI~~ | Moi | ✅ **fait** (#115) — job vert depuis le passage en public |
| 27 | **Essai gratuit 7 j** : `trial_period_days=7` sur le prix Stripe (dashboard, zéro code) **ou** dans `createCheckoutSession` (code) ; mobile = offre introductive App Store/Play | Toi ou Moi | décision #4. ✅ **Le webhook gère déjà l'essai** : `INITIAL_PURCHASE` (period_type TRIAL) → `paid` ; fin sans conversion → `EXPIRATION` → `free`. Aucun changement back-end. |
| 28 | Gating Pro : **régularisation annuelle des charges** | Moi | matrice 🎯 |
| 29 | Gating Pro : **quota documents** (free ~10 / Pro illimité) | Moi | matrice 🎯 — coût stockage |
| 30 | Gating Pro : **rappels + envoi auto email** — nécessite d'abord de construire l'infra email (FEAT-031) | Moi | matrice 🎯 |

## ✅ Déjà livré

| Élément | PR |
|---|---|
| Webhook RevenueCat (déverrouillage, 3 plateformes) + réconciliation | #114 |
| Stripe Checkout Session (web, approche A) | #117 |
| ADR 0002 + amendement web + plan détaillé | #113, #116 |
| Job CI suite functions | #115 |
| Seed tiers + tests contrat/e2e + toggle émulateur (outillage QA) | #108–#112 |

---

**Chemin critique** : ~~#1 débloquer Actions~~ ✅ → **#6–11 (dashboards RevenueCat/Stripe)**
→ me lancer sur #20/#22. Tout le 🔵 est côté moi une fois le 🟣 (tes dashboards) en place.

**Décisions restant ouvertes** : #3 (offre Fondateur 59 €) · #5 (web avant mobile).
