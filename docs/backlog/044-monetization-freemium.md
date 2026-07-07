# FEAT-044 — Monétisation freemium (Pro à prix fixe, mobile-first)

> **Statut** : 📋 Cadré (2026-07-06) — décision de direction prise. **À construire plus tard** (probablement avec/après FEAT-024 mobile, car mobile-first + IAP). Rien n'est implémenté.
> **Benchmark source** : recherche concurrentielle FR (Rentila, Gérer Seul, Smovin, Qlower, BailFacile) — voir synthèse ci-dessous.

## Mindset (le point clé)
On ne convertit **pas en frustrant** (couper une feature = paywall punitif, mauvaises notes sur mobile). On convertit en **apportant de la valeur au bon moment**, avec un modèle **simple, pas cher, mobile-first**, et **plus généreux + moins cher que les concurrents**.

## Modèle retenu
- **Anonyme** : simulateur d'investissement seul (inchangé, déjà géré par `scenarioLimit`).
- **Gratuit (généreux)** : jusqu'à **2 biens · 2 baux actifs · 3 locataires actifs** (plafonds comptés sur les **ACTIFS** — turnover-safe : un bail terminé/archivé ou soft-deleted ne compte pas ; le +large sur les locataires laisse passer une petite **colocation**). Gestion quotidienne **complète et illimitée en usage** dans ces limites — quittances (obligation légale), paiements, régularisation manuelle, dépenses, détection retards, dashboard, upload documents (quota de stockage). Le petit bailleur (majorité du marché) **ne paie jamais** → acquisition, bonnes notes stores, bouche-à-oreille.
- **Pro — un SEUL plan à PRIX FIXE** (~**4,90 €/mois** ou ~**39-49 €/an**, prix exact à confirmer) : **le prix NE monte PAS avec le patrimoine**. Débloque : **biens illimités** + **automatisation** (rappels auto FEAT-031, rapports de rentabilité multi-biens, export comptable/fiscal FEC/2044, multi-utilisateurs/mandataire, archivage de régularisation FEAT-033) + stockage étendu.
- (Option à doser) **Achat « à vie »** (IAP one-time) pour les allergiques à l'abonnement — écartée pour l'instant, rouvrable.

## Value metric
**Nombre de biens** — metric primaire, seuil du gratuit (≤2). Garde-fous secondaires en free : **≤2 baux actifs** et **≤3 locataires actifs** (comptés sur les actifs, pas l'historique). Mais le Pro est **flat** : au-delà, un seul prix, aucune facturation par bien/bail/locataire. C'est le **différenciateur central** (les concurrents facturent par bien → coût explosif).

## Conversion (aux moments de valeur, pas frontal)
Nudges **contextuels** : ajout d'un 3ᵉ bien · approche de la déclaration fiscale (export) · envie d'automatiser les relances (fini les échanges gênants) · partage avec conjoint/comptable. **Essai gratuit** du Pro. **Abonnement unique** via App Store / Play (mobile-first) + Stripe (web). Réutiliser `paid_plan_interest/{uid}` comme paywall « coming soon » tant que le paiement réel n'est pas intégré.

## Garde-fous légaux/éthiques (non négociables)
- Ne **jamais** bloquer l'émission d'une **quittance** d'un bail existant (obligation art. 21 loi 6/7/1989).
- Ne **jamais** bloquer l'accès/téléchargement des **documents déjà uploadés** (litige/contrôle).
- **Export/effacement RGPD** gratuit pour tous les paliers.
- **Downgrade** (Pro→gratuit) au-delà de la limite = biens excédentaires en **lecture seule**, jamais supprimés/inaccessibles.

## Enforcement (technique)
- **Côté serveur** (source de vérité) : les Cloud Functions **`createProperty`, `createLease` ET `createTenant`** vérifient `landlords.subscriptionTier` + les **compteurs dénormalisés d'ACTIFS** (`activePropertiesCount`, `activeLeasesCount`, `activeTenantsCount`, maintenus par CF à la création/soft-delete/changement de statut — exclure terminé/archivé/supprimé) ; refusent la création au-delà du plafond free (`resource-exhausted`). Firestore rules en défense.
- **UI** : bouton désactivé + écran d'upgrade contextuel au moment de valeur.
- Modèle de tiers déjà en place : enum `SubscriptionTier {anonymous, free, paid}`, `LandlordTierRepository`, collection `paid_plan_interest`.

## Paiement / facturation — RevenueCat (décidé 2026-07-06)
**RevenueCat** comme couche d'abonnement unifiée : wrappe **Stripe (web)** + **App Store IAP (iOS)** + **Play Billing (Android)** derrière un SDK unique + un **entitlement** (« user Pro »).
- **Flux** : achat (Stripe web / IAP mobile, via RevenueCat) → **webhook RevenueCat** → **Cloud Function** → écrit `landlords.subscriptionTier = 'paid'`. Le tier Firestore reste la **seule source de vérité** du gating serveur (createProperty…). Le fournisseur ne fait que **basculer le tier**.
- **Pourquoi** : mobile-first → App Store/Play imposent l'IAP (~15-30 %) pour un abonnement numérique in-app ; RevenueCat unifie iOS/Android/web, évite de maintenir 3 stacks de facturation, et donne un statut Pro cohérent multi-plateforme.
- **Coût** : commissions stores ~15-30 % (mobile) vs Stripe ~2 % (web) ; RevenueCat gratuit sous un seuil de revenu puis petit %. Mitigations : privilégier l'**annuel** (moins de transactions) + inciter à l'abonnement **web** là où c'est permis (moins de commission).
- **`paid_plan_interest`** = paywall « coming soon » (capture d'intérêt) **jusqu'à** l'intégration RevenueCat réelle.
- **⚠️ % de commission et règles store (IAP obligatoire, exceptions EU DMA / US) à revérifier au moment du build.**

## Benchmark concurrents (2025-2026, sourcé)
| Concurrent | Gratuit permanent ? | Limite gratuit | Prix payant | Metric |
|---|---|---|---|---|
| Rentila | ✅ | 1 lot | 4,90 € (2-5 lots) / 9,90 € illimité | lots |
| Smovin | ✅ | 2 unités (sans automatisation) | 4 / 6 / 8 € **par unité**/mois | unités |
| Qlower | ✅ (quittances gratuites) | — | 269 €/an +130 €/bien | biens |
| Gérer Seul | ❌ (essai 15 j) | — | 9,75 €/mois/bien | biens |
| BailFacile | ❌ (essai 7 j) | — | 9,99–12,99 €/mois/bien | biens |

**Lecture** : metric = biens partout (jamais bail/locataire). Baillan à **2 biens gratuits** > Rentila (1) et > Gérer Seul/BailFacile (aucun). **Pro flat** imbat le par-bien : à 5 biens, Baillan ~4,90 € vs Smovin 30 € vs BailFacile ~50 €.

## Décisions ouvertes (à figer avant build)
- Prix exact du Pro (mensuel + annuel) ; inclure une option « à vie » ?
- Quota de stockage documents en gratuit.
- ~~Mécanisme de paiement~~ → **décidé : RevenueCat** (Stripe web + IAP iOS/Android unifiés) — voir section dédiée.
- Timing de build (recommandé : avec/après FEAT-024 mobile).

## Dépendances
FEAT-024 (mobile, pour l'IAP) · FEAT-031 (rappels = feature Pro) · intégration paiement.
