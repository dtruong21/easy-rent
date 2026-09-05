# [FEAT-057] Activation commerciale des paid plans (sortie du gate `SUBSCRIPTIONS_ENABLED`)

## User story

En tant que **propriétaire de Baillan**, je veux **ouvrir commercialement les
paliers payants Pro/Max/Ultra en production** afin de **générer du revenu à
partir d'une base technique (FEAT-056) déjà développée et mergée**, sans
exposer l'entreprise à un risque de facturation en environnement de test ou
de fuite de clé Stripe live.

## Context & motivation

FEAT-056 (3 paliers payants, grille de quotas, callables Stripe/RevenueCat,
webhook + cron de réconciliation) est **développée et mergée**, mais
volontairement tenue fermée en production via le flag `SUBSCRIPTIONS_ENABLED
= false`. Le plan d'implémentation (`docs/plans/FEAT-056-multi-tier-subscriptions.md`,
ligne 1301) l'indique explicitement : l'ouverture commerciale est **« une
décision distincte, subordonnée à l'issue #138 »**.

L'issue **#138 (OPEN, sévérité S1)** documente que les Cloud Functions sont
aujourd'hui aveugles à `APP_ENV` pour la sélection de la clé Stripe :
`createCheckoutSession` peut émettre une session en clé **`sk_live`** même
si l'appel provient de **staging**. Tant que ce défaut existe, activer une
clé Stripe live n'importe où dans le système revient à l'activer aussi côté
staging — un environnement de test où des comptes de démonstration créent
des sessions de paiement. C'est un bloqueur dur, pas une précaution
optionnelle.

Cette story couvre uniquement le **chemin vers l'activation prod** (fermer
#138, basculer la clé Stripe en live, lever le flag, vérifier), **pas** de
nouveau développement produit sur les paliers eux-mêmes (déjà livrés par
FEAT-056).

## Acceptance criteria (Gherkin)

- **Given** l'issue #138 est ouverte, **When** `createCheckoutSession` est
  appelée depuis `stage.baillan.com`, **Then** elle utilise obligatoirement
  une clé Stripe de test (jamais `sk_live`), et ce comportement est prouvé
  par un test automatisé (pas seulement une relecture de code) avant de
  considérer #138 close.
- **Given** #138 est fermée et vérifiée, **When** on bascule la clé Stripe
  serveur de `sk_test_` vers `sk_live_` en production, **Then** un appel
  `createCheckoutSession` depuis `stage.baillan.com` continue de renvoyer une
  session en clé test (isolation confirmée en conditions réelles, pas
  seulement en test unitaire).
- **Given** la clé live est en place et vérifiée isolée, **When** le
  propriétaire met `SUBSCRIPTIONS_ENABLED=true` en production, **Then** le
  paywall `/pro/*` devient accessible aux utilisateurs prod et un achat réel
  (carte de test Stripe en mode live désactivée — donc premier test avec une
  carte réelle à très faible montant, ou palier le moins cher) aboutit à un
  entitlement correctement posé (`landlords/{uid}`) et à une facture Stripe
  cohérente.
- **Given** un abonnement Pro souscrit en prod, **When** l'utilisateur va
  dans `/profile` → « Résilier mon abonnement », **Then** le parcours de
  résiliation en 3 clics (déjà livré, FEAT-044f, art. L215-1-1 C. conso.)
  fonctionne de bout en bout avec la clé live (pas seulement testé en clé
  test lors de FEAT-044f).
- **Given** l'ouverture commerciale, **When** le cron de réconciliation
  quotidienne (FEAT-044c) tourne pour la première fois en régime live,
  **Then** son exécution est surveillée (logs Cloud Functions) sur au moins
  un cycle complet avant de considérer l'activation stable.
- **Given** l'activation prod, **When** le propriétaire consulte le
  dashboard Stripe, **Then** le webhook `createCheckoutSession`/réconciliation
  reçoit et traite correctement les événements live (pas de désynchronisation
  entre l'entitlement Firestore et l'état réel de l'abonnement Stripe).

## Out of scope

- Toute nouvelle fonctionnalité produit sur les paliers Pro/Max/Ultra
  (contenu déjà livré par FEAT-056).
- L'intégration IAP mobile (achats in-app iOS/Android) — FEAT-044e la
  signale encore en 📋, hors périmètre de cette activation web.
- La migration du domaine (sujet « app.\<domaine\> ») et le site vitrine — non
  liés techniquement à cette activation, traités comme sujets séparés.
- Une éventuelle renégociation tarifaire ou changement de grille de quotas.

## Dependencies

- **Bloquant dur** : issue GitHub **#138** (S1) doit être fermée et vérifiée
  avant tout changement de clé Stripe.
- Collections Firestore : `landlords` (entitlement), et tout ce que touche
  déjà FEAT-056 (`properties`, `leases`, `expenses`, simulations — quotas).
- Features bloquantes : FEAT-056 (paliers, callables, webhook, cron) — déjà
  ✅ mergée sur `develop` (la branche de feature a été supprimée), doit être
  sur `main` et déployée avant d'envisager l'activation (vérifier l'état de la
  PR de release `develop → main` v1.1.0 actuellement ouverte).
- La clé Stripe live doit être créée/récupérée côté compte Stripe du
  propriétaire (hors périmètre technique de cette story, action manuelle
  propriétaire).

## Legal / compliance notes

- Résiliation en ligne « 3 clics » (art. L215-1-1 C. conso., décret
  2023-182) : déjà conforme côté web (FEAT-044f, cf. `docs/LEGAL.md`), mais
  doit être re-testée en régime de clé live avant l'annonce commerciale — un
  parcours qui fonctionne en clé test n'est pas une garantie suffisante pour
  de l'argent réel.
- RGPD / mentions légales des emails transactionnels (reçus de paiement,
  confirmations d'abonnement) : vérifier que les mentions obligatoires
  (`docs/LEGAL.md` — nom du responsable de traitement, lien désabonnement
  sauf transactionnel) sont bien présentes sur les emails Stripe/RevenueCat
  envoyés en prod, pas seulement en environnement de test.
- Le passage en clé live change la nature juridique des transactions
  (argent réel, droit de rétractation standard e-commerce sauf exception
  contenu numérique fourni immédiatement avec renoncement exprès — à
  vérifier que le tunnel Stripe Checkout capture bien ce renoncement si
  applicable).
- Facturation : la clé live active la génération de factures réelles côté
  Stripe — vérifier la configuration fiscale (TVA, SIREN si applicable au
  statut du propriétaire) avant le premier encaissement réel.

## Priority

P1 — rang 2 de la priorisation transverse du 2026-09-05 (`docs/BACKLOG.md`).
Le déblocage du revenu est la valeur la plus immédiate du lot, mais la story
est **bloquée par l'issue #138**, qui occupe le rang 1. Elle ne peut donc pas
être P0 : rien ici ne peut démarrer avant la fermeture de #138.

## Estimated effort

S — quelques heures, **hors correction de #138**. La correction de #138
(isolation `APP_ENV` côté Stripe, estimée 1-2 jours) est un sujet distinct de
rang 1 : son effort ne doit pas être compté ici, sous peine de le facturer
deux fois dans le plan. Une fois #138 fermée, il ne reste sur cette story que
la bascule de clé, la levée du flag et les vérifications — aucun
développement produit.
