# FEAT-044f — Résiliation d'abonnement Pro (conformité loi FR)

> Sous-feature de la série paiement FEAT-044. Prérequis livrés :
> 044c (webhook RevenueCat + reconcile), 044d (Stripe Checkout web), 044e (paywall web).

## User story

**En tant que** propriétaire abonné à Baillan Pro sur le web,
**je veux** résilier mon abonnement facilement depuis mon profil,
**afin de** ne plus être facturé et repasser en formule gratuite, comme la loi
française m'y autorise.

## Contexte légal — pourquoi c'est obligatoire

Art. **L215-1-1** du Code de la consommation (« résiliation en trois clics »,
applicable depuis le **1ᵉʳ juin 2023**) : pour un contrat conclu en ligne, le
professionnel doit offrir une fonctionnalité de résiliation **aussi simple** que
la souscription, accessible en ligne, gratuitement. Baillan permet de souscrire
en ligne (Stripe Checkout) → il **doit** permettre de résilier en ligne.

`docs/LEGAL.md` ne couvre aujourd'hui que le *désabonnement email* — la
résiliation d'abonnement est une lacune à combler dans cette feature.

## Décisions produit (verrouillées par l'utilisateur — ne pas re-poser)

| Décision | Choix | Conséquence |
|---|---|---|
| Mécanisme web | **Bouton natif in-app** dans /profile → Cloud Function `cancelSubscription` → Stripe | Contrôle UX total pour la conformité 3-clics, pas de portail tiers |
| Effet | **Fin de période payée** (`cancel_at_period_end=true`) | Garde Pro jusqu'à `proExpiresAt`, puis freemium automatique |
| Périmètre | **Web d'abord** | Mobile IAP pas encore construit ; résiliation mobile = deep-link système, différée |

## Critères d'acceptation

1. Un abonné Pro voit dans /profile un bouton « Résilier mon abonnement ».
2. Après confirmation, l'abonnement Stripe passe en `cancel_at_period_end=true`.
3. Le profil affiche alors « Pro jusqu'au JJ/MM/AAAA, puis Gratuit » (lu depuis
   `proEntitlementActive` + `proWillRenew:false` + `proExpiresAt`, sans appel Stripe).
4. À la fin de la période, le compte repasse `subscriptionTier: free`
   **automatiquement** via le chemin RevenueCat→webhook / reconcile existant
   (aucune réimplémentation du downgrade).
5. Un utilisateur ne peut résilier **que son propre** abonnement (autorisation
   serveur via `context.auth.uid` ; le client ne fournit jamais d'ID Stripe).
6. Idempotent : re-cliquer « Résilier » quand c'est déjà programmé ne casse rien.
7. Réactivation possible tant que la période court (`cancel_at_period_end=false`).
8. Le compte redevenu gratuit qui dépasse les plafonds free est géré
   proprement (politique à trancher par l'architecte : grandfather lecture seule
   vs blocage création — vérifier le comportement DÉJÀ en place côté gating
   FEAT-044/044b avant d'en écrire un nouveau).

## Hors périmètre v1

- Résiliation mobile (IAP Apple/Google) — dépend de FEAT-044e mobile non livré ;
  passera par l'UI système (`showManageSubscriptions` / deep-link).
- Remboursement au prorata (choix = fin de période, pas de remboursement).

## Réutilisation imposée

- `functions/src/scheduled/reconcile_entitlements.ts` — downgrade freemium (ne PAS refaire).
- `functions/src/http/revenuecat_webhook.ts` — applique les events, écrit `proWillRenew`/`proExpiresAt`.
- `functions/src/callable/create_checkout_session.ts` — modèle du callable + `RC_APP_USER_ID_METADATA_KEY` + secret `STRIPE_SECRET_KEY`.
