# [FEAT-054] Isolation réelle prod/staging — Firestore, Auth, Storage, Functions

> **Statut** : 📋 Cadré (2026-07-23) — le choix technique (base Firestore nommée vs
> second projet Firebase) est délégué à l'ADR
> [`docs/adr/0003-firestore-prod-staging-isolation.md`](../adr/0003-firestore-prod-staging-isolation.md)
> (architecte, en cours). Cette story fixe le besoin métier et les critères
> d'acceptation, pas le comment.
> **Priorité proposée** : P1 (justification dans [`../BACKLOG.md`](../BACKLOG.md)).
> **État actuel** : décrit dans [`docs/ENVIRONMENTS.md`](../ENVIRONMENTS.md) —
> staging et prod partagent aujourd'hui un seul projet Firebase, une seule
> base Firestore `(default)`, un seul annuaire Auth, un seul bucket Storage
> et les mêmes secrets.

## Contexte

Depuis la mise en place du multi-site Hosting (`baillan.com` /
`stage.baillan.com`), **seul le Hosting est séparé** — Firestore, Auth,
Storage, Cloud Functions et les secrets sont partagés entre staging et prod
(cf. [`docs/ENVIRONMENTS.md`](../ENVIRONMENTS.md)). Concrètement, aujourd'hui :

- Un compte créé sur staging **est** un compte de production — biens,
  locataires, baux, paiements et quittances de test sont des données réelles,
  jamais isolées.
- Un déploiement de `firestore.rules` / `firestore.indexes.json` / Cloud
  Functions depuis `develop` s'applique **immédiatement à la prod**, avant
  même un merge sur `main`.
- Les secrets (webhook RevenueCat, clé Stripe, futures clés d'envoi d'email)
  sont uniques — une fuite ou un mauvais usage côté staging expose
  directement des systèmes de production.

**Pourquoi maintenant** : le palier payant est en prod depuis FEAT-044
(paiement RevenueCat + Stripe). Le mélange staging/prod touche désormais
potentiellement des données de facturation et des locataires réels, plus
seulement des maquettes internes. `docs/ENVIRONMENTS.md` signale aussi que
**FEAT-031** (rappels automatiques de paiement, 📋 planned) est bloquée par ce
même partage de secrets : une fois livrée, staging enverrait de vrais emails
à de vrais locataires. Cette story lève ce prérequis silencieux.

**Risques mitigés** : pollution/fuite de données de production via des tests
staging, incident de sécurité par partage de secrets, non-conformité RGPD
(traitement de données personnelles réelles à des fins de test non
déclarées), blocage de FEAT-031.

## User story

En tant qu'**équipe Baillan (produit + tech)**, je veux que staging et
production soient **réellement isolés** au niveau des données (Firestore,
Auth, Storage) et de l'exécution (Cloud Functions, secrets), afin de pouvoir
tester des scénarios — y compris destructifs ou générateurs de données — sur
staging **sans jamais affecter** les comptes, données ou destinataires
(emails) de production.

## Critères d'acceptation

- **Given** un compte créé sur `stage.baillan.com`, **When** on consulte
  l'annuaire Auth ou les données Firestore de production, **Then** ce compte
  et ses données n'y apparaissent jamais.
- **Given** un scénario de test destructif ou générateur de volume exécuté
  sur staging, **When** il s'exécute, **Then** aucune donnée de production
  (biens, locataires, baux, paiements, quittances) n'est créée, modifiée ou
  supprimée.
- **Given** un déploiement de règles Firestore/Storage, d'index ou de Cloud
  Functions depuis `develop`, **When** il s'exécute, **Then** seul
  l'environnement staging est affecté — la prod reste sur sa version
  précédente tant qu'elle n'a pas été déployée explicitement depuis `main`.
- **Given** un secret applicatif (webhook de paiement, future clé d'envoi
  d'email), **When** il est configuré pour staging, **Then** il est distinct
  de son équivalent de production — une fuite ou un mauvais usage côté
  staging n'expose jamais un système ou un tiers de prod.
- **Given** FEAT-031 (rappels automatiques) livrée une fois l'isolation en
  place, **When** elle s'exécute sur staging, **Then** elle ne peut jamais
  envoyer un email à un vrai locataire de production.
- **Given** un document, une photo ou un PDF de quittance déposé pendant un
  test sur staging, **When** on consulte le bucket Storage de production,
  **Then** ce fichier n'y apparaît pas.
- **Given** un audit RGPD ou un contrôle interne, **When** on inspecte les
  données présentes sur staging, **Then** on n'y trouve aucune donnée
  personnelle réelle de bailleur ou de locataire de production — uniquement
  des données de test.

## Non-goals

- Migrer ou nettoyer les données historiques déjà mélangées en production
  (comptes de test créés depuis staging avant cette isolation) — sujet
  distinct, traité par la maintenance périodique existante
  (`docs/ENVIRONMENTS.md`) ou par un ticket de nettoyage dédié une fois
  l'isolation livrée.
- Choisir l'implémentation technique (base Firestore nommée vs second projet
  Firebase) — tranché par l'ADR
  [`docs/adr/0003-firestore-prod-staging-isolation.md`](../adr/0003-firestore-prod-staging-isolation.md),
  pas par cette story.
- Ajouter de nouveaux environnements (preview par PR, environnement de
  recette QA dédié) — seul le couple staging/prod existant est concerné.
- Modifier l'émulateur local (`npm --prefix functions run serve`) — déjà
  isolé, hors sujet.
- Automatiser la purge des données de test sur staging (cron de nettoyage) —
  amélioration possible mais pas une condition d'acceptation de cette story.
- Renommer les domaines ou changer la topologie Hosting (`baillan.com` /
  `stage.baillan.com` restent inchangés).

## Dépendances / risques

- **Bloquant** : dépend de l'ADR
  `docs/adr/0003-firestore-prod-staging-isolation.md` (architecte, en cours)
  — cette story ne peut pas être chiffrée avant l'arbitrage Option A (base
  nommée) vs Option B (second projet).
- Risque de périmètre selon l'option retenue : Option A ne protège que
  Firestore (Auth/Storage/secrets resteraient partagés) ; Option B protège
  tout mais impose un second jeu de `firebase_options`, un double déploiement
  rules/indexes/Functions et une duplication complète des secrets.
- Risque de régression transverse : selon l'option, le routage Firestore peut
  toucher les 21 points d'accès `FirebaseFirestore.instance` de `lib/` —
  surface de test large.
- Dépendance croisée avec FEAT-044c/d (paiement RevenueCat/Stripe déjà en
  prod) : dupliquer le secret webhook exige de revalider tout le flux
  paiement sur le nouvel environnement staging, au-delà du protocole actuel
  de test sur émulateur.
- FEAT-031 (rappels automatiques) reste bloquée tant que cette story n'est
  pas livrée — dépendance dans l'autre sens, déjà documentée dans
  `docs/ENVIRONMENTS.md`.
- Risque de dérive calendaire silencieuse : aucune donnée de prod n'est
  visiblement cassée tant que rien n'incident, ce qui rend la priorité facile
  à repousser indéfiniment malgré un risque réel et croissant (base payante
  déjà en prod).

## Chantiers pressentis

Haut niveau, sans trancher Option A vs B — précisés par l'ADR puis par
l'architecte au chiffrage :

- Provisionnement de l'environnement staging isolé (nouvelle base nommée ou
  nouveau projet Firebase).
- Déploiement dupliqué des règles Firestore/Storage, des index composites et
  des Cloud Functions.
- Routage applicatif du client Flutter vers le bon backend selon `APP_ENV`
  (Firestore, Auth, Storage).
- Duplication et gestion des secrets par environnement (webhook RevenueCat,
  clé Stripe, futures clés email).
- Adaptation du pipeline CI/CD (`deploy.yml`) pour déployer
  rules/indexes/Functions vers le bon environnement selon la branche.
- Peuplement de données de test réalistes sur le nouveau staging (script de
  seed dédié, distinct de `seed_tiers.mjs` qui cible l'émulateur).
- Mise à jour de `docs/ENVIRONMENTS.md` une fois l'isolation livrée (le
  document décrit aujourd'hui l'état non isolé).
