# ADR 0003 — Isolation Firestore prod/staging : base nommée `dev` + routage backend par Origin

- **Statut** : **accepté et implémenté (2026-07-24)** — jalons 1-4 livrés (voir Amendement d'implémentation en fin de document). Proposé le 2026-07-23.
- **Contexte technique** : Flutter Web/mobile + Firebase (Firestore, Auth,
  Storage, Cloud Functions), projet unique `easy-rent-54cd4`
- **Impacte** : `docs/ENVIRONMENTS.md` § « Évolution », `lib/core/config/env.dart`
  (commentaire tête de fichier), workflow `deploy.yml`

## Contexte

Aujourd'hui, prod (`baillan.com`) et staging (`stage.baillan.com`) sont **deux
sites Hosting** dans le **même projet Firebase** et **partagent tout le reste** :
Firestore `(default)`, Auth, Storage `easy-rent-54cd4.firebasestorage.app`,
14 Cloud Functions (`europe-west1`), `firestore.rules`, `firestore.indexes.json`,
`storage.rules`, secrets (RevenueCat, Stripe).

Grep vérifié : **21 accès `FirebaseFirestore.instance`** dans `lib/` +
**30+ accès `FirebaseAuth.instance` / `FirebaseFunctions.instance`**. Backend :
9 `onCall`, 1 `onRequest` (webhook RevenueCat), 2 `onSchedule`, 2 triggers
Firestore ; `admin.initializeApp()` unique dans `functions/src/index.ts`.

**Conséquences opérationnelles vécues** :
- Un déploiement de `firestore.rules` depuis `develop` s'applique à la prod.
- Toute donnée créée en test sur staging (bien, bail, quittance, compte) est
  une donnée de production.
- Les Cloud Functions déployées depuis `develop` **tournent aussi sur la prod**
  (mêmes URLs, mêmes triggers). Un bug de callable peut corrompre des données
  prod dès le prochain appel authentifié réel.
- Seul l'émulateur local est isolé.

**Élément déclencheur** : FEAT-044 (paiement Stripe/RevenueCat) rend un incident
data désormais visible (facturation, entitlement `paid`). Le status quo n'est
plus tenable pour du dev/test itératif.

## Décision

**Introduire une base Firestore nommée `dev` dans le projet existant**, avec
**routage backend par en-tête `Origin`** (Option A ci-dessous). Auth, Storage,
Functions et secrets restent partagés — les risques résiduels sont assumés,
documentés et compensés par des conventions.

## Alternatives évaluées

### Option A — Base Firestore nommée `dev` dans le même projet **[retenue]**

**Isolation obtenue** (matrice binaire) :

| Composant | Isolé ? |
|---|---|
| Firestore data | ✅ oui (base `dev` séparée de `(default)`) |
| Firestore rules/indexes | ✅ oui (fichier partagé, déployé sur les 2 bases) |
| Auth | ❌ non |
| Storage | ❌ non |
| Cloud Functions (code déployé) | ❌ non |
| Cloud Functions (writes Firestore) | ✅ oui via routage `Origin` |
| Secrets | ❌ non |

**Coût implémentation : ~4-6 j-h**. Chantiers :

1. **Base `dev`** : créer via console/gcloud (`firebase firestore:databases:create dev --location=eur3`).
2. **`firebase.json`** : passer `firestore` en tableau, ajouter le bloc `dev` :
   ```json
   "firestore": [
     { "database": "(default)", "rules": "firestore.rules", "indexes": "firestore.indexes.json" },
     { "database": "dev",       "rules": "firestore.rules", "indexes": "firestore.indexes.json" }
   ]
   ```
3. **Flutter** : créer `firestoreProvider` Riverpod unique qui renvoie
   `FirebaseFirestore.instanceFor(databaseId: Env.isProd ? '(default)' : 'dev')`.
   Refactor les **21** accès `FirebaseFirestore.instance` (find/replace + injection
   dans les 12 repos concernés). Trivial mécaniquement.
4. **Backend** : helper `dbForRequest(req): Firestore` qui lit
   `req.rawRequest.headers.origin`, route vers `getFirestore(app, 'dev')` si
   `stage.baillan.com`, sinon `(default)`. À utiliser dans les 9 callables et
   le webhook `revenuecat_webhook.ts` (via metadata `env` — voir Réserve).
   Les 2 `onSchedule` restent sur `(default)` (pas de notion d'env pour un cron).
5. **Rules/indexes** : `firebase deploy --only firestore` déploie automatiquement
   sur les 2 bases dès qu'elles sont dans `firebase.json`. **Aucune modif CI.**
6. **Docs** : update `docs/ENVIRONMENTS.md`, supprimer la note « non implémenté »
   de `lib/core/config/env.dart`.

**Impact récurrent** : nul. Un `firebase deploy --only firestore` couvre les
deux bases. Aucune duplication de rotation de secrets, de config OAuth, de
webhook. Un seul dashboard Firebase.

**Coût financier Firebase** : quasi-nul. Le free tier Firestore de 1 GiB /
50k reads/jour / 20k writes/jour s'applique à la base `(default)` uniquement ;
les bases nommées sont facturées **dès le premier read au tarif Blaze
(0,06 $/100k reads, 0,18 $/100k writes, 0,18 $/GiB/mois)**. Usage dev réaliste :
< 1 $/mois. Aucun coût Functions/Storage/Hosting supplémentaire.

**Migration path** : additive, non destructive. Aucune donnée à migrer (la base
`dev` démarre vide). Réversible en 3 commandes : dépublier le provider, retirer
le bloc `firestore.dev` de `firebase.json`, `firebase firestore:databases:delete dev`.

**Risques résiduels** :
- Auth partagée → un compte créé sur staging existe en prod. **Mitigation** :
  convention `dev+<slug>@baillan.local` + purge mensuelle (déjà documentée
  § Maintenance de ENVIRONMENTS.md).
- Storage partagée → uploads test dans le bucket prod. **Mitigation** : faible
  volume, purge périodique. Option C disponible si ça devient un problème.
- Functions déployées depuis `develop` = code prod. **Mitigation** : le routage
  Firestore par `Origin` limite l'impact aux **writes** ; les reads restent
  sûrs. Discipliner la revue des PR touchant `functions/src/`.
- Webhook RevenueCat/Stripe n'a pas de header `Origin` → **cf Réserve principale**.
- Dérive silencieuse si un dev oublie `firestoreProvider` et retape
  `FirebaseFirestore.instance` → **ajouter une lint rule** interdisant l'accès
  direct (analyzer custom ou grep en CI).

### Option B — Second projet Firebase dédié dev

**Isolation obtenue** :

| Composant | Isolé ? |
|---|---|
| Firestore, Auth, Storage, Functions, Secrets | ✅ oui, tout |

**Coût implémentation : ~10-15 j-h**, majoritairement config externe :

- Créer projet `easy-rent-dev-xxxx`, région `eur3`, plan Blaze.
- Second `firebase_options.dart` (via `flutterfire configure --project=...`) +
  bootstrap dans `main.dart` sélectionnant les options par `APP_ENV`.
- `.firebaserc` avec aliases `dev`/`prod` (`firebase use dev` / `firebase use prod`).
- Workflow `deploy.yml` : 2 jobs distincts (ou matrice) avec 2
  `FIREBASE_PROJECT_ID` en secret CI. Ajout d'un `firebase use $env` avant deploy.
- Redéployer **rules + indexes + 14 functions** sur le nouveau projet
  (~90 s → ~3 min à chaque push `develop`).
- **Re-set intégral des secrets** : `RC_WEBHOOK_SECRET`, `STRIPE_SECRET_KEY`,
  `STRIPE_WEBHOOK_SECRET`. Deux jeux à faire tourner en parallèle.
- **OAuth Google Sign-In** : nouveau consent screen, nouveau OAuth client ID
  web + iOS + Android → nouveau SHA-1 pour Android debug builds.
- **RevenueCat** : second projet + nouvel `pro` entitlement + mapping Stripe
  dev + configurer un second webhook endpoint (URL du projet dev).
- **Stripe** : compte test dédié ou reuse du même compte avec 2 webhook
  endpoints ; second `publishable_key` côté client dev.
- **Play Console / App Store Connect** : si un build debug pointe le projet
  dev, référencer un second bundle ID (`com.baillan.app.dev`) ou accepter que
  le SHA-1 debug soit lié aux 2 projets (peut fonctionner mais fragile).
- Hébergement `stage.baillan.com` : à déplacer sur le site par défaut du
  nouveau projet (config DNS + certificat SSL propagés).

**Impact récurrent** : double deploy CF systématique, double rotation secrets,
double dashboard, double surveillance des logs. **Dérive de config = bug
classique** (rule déployée sur un mais pas l'autre).

**Coût financier Firebase** : **doubles quotas gratuits** par projet
(Firestore free tier × 2, Functions 2M invocations/mois × 2). Blaze billing
séparé mais consommation dev négligeable. Coût réel indirect : temps d'ingénierie
récurrent (~1-2 h/mois de maintenance de la config duale).

**Migration path** : réversible en théorie, en pratique la config externe
(OAuth consent screen Google, apps RevenueCat, webhooks Stripe) laisse des
traces gênantes à annuler. Pas de data à migrer (fresh Firestore).

**Risques résiduels** : dérive silencieuse entre les 2 projets ; oubli de
propager une config (rules, index, secret) ; coût cognitif quotidien qui
grossit avec chaque nouvelle intégration.

### Option C — Firestore `dev` + Storage préfixé par env

Extension d'Option A : ajouter un préfixe `envs/{env}/` aux chemins Storage
et une clause `match /envs/{env}/{path=**}` dans `storage.rules`.

**Coût additionnel sur A** : +2 j-h. Refactor des repos qui uploadent
(documents, photos de biens), update `storage.rules`, migration des chemins
existants (les download URLs actuelles sont conservées mais tout nouveau path
sera préfixé — un backfill peut être nécessaire selon la stratégie).

**Financier** : identique à A (bucket unique, quota partagé).

**Rejeté (pour l'instant)** : le gain d'isolation Storage est faible
(volume d'uploads en dev négligeable), et le refactor introduit un risque de
casser les download URLs existantes. À réévaluer si l'usage staging monte.

## Justification du choix

Option A retenue pour 4 raisons hiérarchisées :

1. **80/20** — Option A adresse la fuite de données #1 (rules/indexes/writes
   qui polluent la prod) pour ~4-6 j-h. Option B triple l'effort pour isoler
   Auth/Storage/Functions dont l'exposition est faible dans notre contexte
   actuel (pas d'envoi email serveur, uploads dev rares, secrets peu nombreux).
2. **Réversible** — retour arrière en 3 commandes CLI. Option B pollue de la
   config externe (OAuth, RevenueCat, Stripe) difficile à annuler proprement.
3. **Solo/duo team** — pas la bande passante pour maintenir 2 consoles Firebase,
   2 jeux de secrets, 2 consent screens OAuth. Le coût récurrent d'Option B
   grossit à chaque nouvelle CF / nouveau secret / nouvelle intégration (×2
   partout, permanent).
4. **L'émulateur reste le sandbox principal** — les tests destructifs se font
   déjà en local (seed tiers, RGPD, rules). Staging sert de preview UX, pas
   de bac à sable. Option A suffit pour ce cas d'usage.

**Cette décision est révisable dès qu'un de ces éléments change** :
- (a) apparition d'un envoi email serveur (FEAT-031 rappels auto) → risque
  d'envoyer de vrais emails depuis staging = Option B redevient rentable ;
- (b) équipe > 3 devs simultanés → coût de coordination sur des données
  partagées explose ;
- (c) incident majeur sur la prod dû à une CF déployée depuis `develop`.

## Conséquences

### Positives ✅
- Fuite de données Firestore éliminée (writes, rules, indexes).
- Staging devient un vrai bac à sable pour la data (tests de baux, quittances,
  scénarios simulateur — sans polluer la prod).
- Migration graduelle : Jalon 1 (Flutter) livrable seul apporte déjà la
  moitié du bénéfice.
- Free tier Firebase préservé, coût récurrent quasi-nul.
- Workflow émulateur inchangé.

### Négatives ⚠️
- **Cloud Functions restent partagées.** Un push `develop` déploie du code
  qui tourne aussi sur prod. Le routage `Origin` protège les writes mais pas
  les régressions de logique. Compensation : revue systématique des diffs
  `functions/src/**` avant merge sur `develop`.
- **Discipline requise** — chaque nouveau repo Flutter DOIT passer par
  `firestoreProvider` ; chaque nouvelle callable DOIT utiliser `dbForRequest`.
  Ajouter un check CI (grep interdisant `FirebaseFirestore.instance` hors du
  provider, et `admin.firestore()` sans arg hors du helper).
- **Auth et Storage partagés** — assumés, à documenter dans ENVIRONMENTS.md.

## Réserve principale — webhook RevenueCat/Stripe

Un webhook entrant **n'a pas d'en-tête `Origin`** (c'est un serveur qui appelle,
pas un navigateur). Le routage par Origin ne fonctionne donc pas pour
`revenuecat_webhook.ts` — pourtant c'est **le seul écrivain autoritaire de
`subscriptionTier`** (ADR 0002).

Sans mitigation, **un abonnement de test créé depuis staging basculerait un
compte réel en `paid`** (fuite en amont : le webhook ne saurait pas qu'il vient
d'un flow dev). Impact : facturation Stripe réelle, entitlement RevenueCat
attribué au mauvais compte.

**Mitigation obligatoire dès le Jalon 4** :
- `create_checkout_session.ts` (existant, PR #117) attache une metadata
  `env: 'dev' | 'prod'` (déduite du `Origin` de la requête callable) à la
  Stripe Checkout Session **ET** au `subscription_data.metadata`.
- RevenueCat propage cette metadata dans ses events (via l'intégration Stripe).
- `revenuecat_webhook.ts` lit `event.subscriber.subscriber_attributes.env` (ou
  équivalent selon le mapping RC) et route la DB en conséquence.
- **Test de bout en bout obligatoire** avant d'ouvrir la base `dev` aux users
  de staging.

Alternative envisageable : deux webhook endpoints RevenueCat (URL dédiée dev
pointant vers `revenueCatWebhookDev`), mais dédouble la surface de code
backend — préférer la metadata.

## Plan d'exécution (jalons, ~5 j-h total)

| # | Jalon | Effort | Livrables |
|---|---|---|---|
| 1 | Base `dev` + Flutter provider | 2 j-h | Base créée, `firestoreProvider`, 21 refactors, `firebase.json` mis à jour, rules déployées sur les 2 bases |
| 2 | Backend routage `Origin` | 1-2 j-h | Helper `dbForRequest`, refactor des 9 callables + webhook, tests unitaires du helper |
| 3 | Metadata `env` sur Stripe Sessions | 1 j-h | `create_checkout_session.ts` propage `env`, `revenuecat_webhook.ts` lit et route, test manuel achat dev/prod |
| 4 | Garde-fous + docs | 0.5 j-h | Lint/CI check interdisant les accès directs, update ENVIRONMENTS.md + env.dart, entrée CHANGELOG |

Chaque jalon est indépendamment mergeable et testable. **Ne pas ouvrir la
base `dev` au trafic staging avant le Jalon 3** (sinon fenêtre où un test
d'abonnement peut basculer un compte prod).

## Références

- [`docs/ENVIRONMENTS.md`](../ENVIRONMENTS.md) — état actuel
- [`docs/adr/0002-monetisation-baillan-pro-revenuecat.md`](0002-monetisation-baillan-pro-revenuecat.md) — flux paiement, contexte de la Réserve
- [Firebase — Manage multiple Firestore databases](https://firebase.google.com/docs/firestore/manage-databases)
- [Firebase Admin SDK — `getFirestore(app, databaseId)`](https://firebase.google.com/docs/reference/admin/node/firebase-admin.firestore)
- [Firebase Callable Functions — reading request headers](https://firebase.google.com/docs/functions/callable#function-handler)

## Amendement d'implémentation (2026-07-24)

> **⚠️ Nom de la base : `staging`, pas `dev`.** Le corps de cet ADR parle
> partout de « base `dev` », mais Firestore impose un id de base de **4-63
> caractères** — `dev` (3 car.) est rejeté à la création. L'id réellement
> utilisé est **`staging`** (dans `firebase.json`, `kStagingDatabaseId` Flutter,
> `STAGING_DATABASE_ID` backend). Lire « `dev` » comme « `staging` » dans tout ce
> qui précède.

Implémenté sur la branche `feat/firestore-dev-isolation-adr0003`. Une déviation
notable par rapport au plan initial, sur la **Réserve principale** (routage du
webhook).

### Ce qui a été livré tel que prévu
- **Jalon 1** : base `dev` déclarée dans `firebase.json` (bloc `firestore` en
  tableau), provider Flutter unique `firestoreProvider`
  (`lib/core/config/firestore_provider.dart`) routant `(default)` (émulateur +
  prod) vs `dev` (staging déployé), et refactor des 19 fichiers/21 accès. Note
  d'implémentation : `FirebaseFirestore.instanceFor(...)` exige `app:` sur
  `cloud_firestore ^5.6.12` (pas seulement `databaseId:`).
- **Jalon 2** : helper `dbForRequest(request)` (`functions/src/utils/db_router.ts`)
  routant par en-tête `Origin`, appliqué aux 8 callables qui écrivent Firestore.
  Le chemin `(default)` passe par `admin.firestore()` (et non `getFirestore()`)
  pour préserver le seam de test `vi.mock("firebase-admin")`.
- **Jalon 4** : garde-fou CI `scripts/check-db-isolation.sh` (interdit
  `FirebaseFirestore.instance` hors provider/main.dart et
  `admin.firestore()`/`getFirestore()` dans `callable/`+`http/`).

### Déviation — routage du webhook par présence du landlord, PAS par metadata `env`
> ⚠️ **Remplacé le 2026-09-30** : le webhook est désormais routé par `event.environment` — voir « Amendement 2026-09-30 » en bas de page.

Le plan prévoyait (jalon 3) de propager une metadata `env` sur la Checkout
Session Stripe, que RevenueCat aurait relayée dans ses events, lue par le
webhook. **Abandonné** au profit de `dbForLandlordUid(uid)` : le webhook cherche
le doc `landlords/{uid}` d'abord dans `(default)` (fail-safe prod), puis dans
`dev`, et écrit dans la base qui le porte.

Raisons :
- **Fiabilité** : ne dépend d'AUCUNE config RevenueCat/Stripe (la propagation de
  metadata Stripe → event RC n'est pas garantie/documentée de façon stable).
  Reste correct même si ce mapping change.
- **Simplicité** : aucune modification de `create_checkout_session.ts`, pas de
  nouveau champ metadata à maintenir des deux côtés.
- **Fail-safe identique** : prod testée en premier → jamais mal-router un vrai
  compte prod.

Contrainte inchangée (la « Réserve » demeure, sous une autre forme) : un uid ne
doit exister que dans UNE base. **Pour tester un paiement sur staging, utiliser
un compte JAMAIS utilisé en prod** — sinon son doc `landlords/{uid}` existe aussi
en `(default)` et le webhook (qui teste prod d'abord) basculerait le compte prod.

### Limitations assumées
- **Isolation = staging WEB uniquement.** Le provider Flutter ne route vers
  `dev` que si `kIsWeb && Env.isDev && !useFirebaseEmulator`. **Tout build
  mobile → `(default)`** (fail-safe), quel que soit `APP_ENV`. Raison : la
  commande de release mobile (`docs/MOBILE.md`) ne passe pas `APP_ENV`, qui
  retombe sur son défaut `'dev'` — sans le garde `kIsWeb`, une release mobile
  enverrait les vrais utilisateurs vers la base `dev`. Conséquence : pas de bac à
  sable `dev` pour le mobile (utiliser l'émulateur). Côté callables, un build
  mobile n'a de toute façon pas d'en-tête `Origin` → `dbForRequest` route aussi
  vers `(default)` : les deux couches sont **cohérentes** (mobile = prod partout,
  pas de split-brain). (→ amendé le 2026-09-29, voir « Amendement 2026-09-29 » en
  bas de page.)
- Les crons (`reconcile_entitlements`, `cleanup_expired_anon`) et le trigger
  `recompute_receipt_stale` restent sur `(default)` — ils ne traitent pas la
  base `dev`. Conséquence staging : un entitlement expiré en `dev` n'est pas
  rattrapé par le reconcile (seul l'event webhook `EXPIRATION`/`CANCELLATION`,
  routé vers `dev`, le gère) ; les triggers de dénormalisation ne se déclenchent
  pas sur `dev`. Acceptable pour un environnement de preview.

## Amendement 2026-09-29 — routage mobile par compte

**Motivation.** Lancer un build Android de test sur le Firebase Test Lab (Robo)
sans polluer la prod : le build doit lire/écrire dans la base `staging`. La
limitation « mobile = `(default)` partout » (ci-dessus) empêchait tout bac à
sable mobile — l'émulateur ne couvre pas le Test Lab.

**Décision.**
- `dbForRequest(request)` devient **asynchrone** (`Promise<Firestore>`) ; les 24
  sites d'appel des 13 callables font `await dbForRequest(request)`.
- **Web, inchangé** : Origin présent → routage par l'en-tête `Origin`
  (`https://app.staging.baillan.com` → `staging`, tout le reste → `(default)`).
- **Appels sans Origin** (app native, Origin absent ou vide) → `dbForLandlordUid`
  (`request.auth?.uid`) : base qui porte `landlords/{uid}`, **prod d'abord**
  (fail-safe), puis `staging`, absent des deux → `(default)`.
- **Côté app** : `Env.useMobileStaging` (`MOBILE_STAGING`, désactivé en release
  via `kReleaseMode`) fait viser la base `staging` à `firestoreProvider` ; un
  auto-login à un compte de test dédié (`dart-defines.testlab.json`, gitignoré)
  évite de saisir des identifiants dans Robo.
- **Portée de la limitation antérieure : CLIENT uniquement.** « Tout build mobile
  → `(default)` » reste vrai pour le **client** : un build sans `MOBILE_STAGING`
  (donc toute release) lit/écrit `(default)` en direct. Côté **serveur**, en
  revanche, les callables de **tout** build mobile — release comprise — sont
  désormais routés par compte (`dbForLandlordUid`, prod d'abord).
- **Conséquence : split-brain pour un compte staging-only connecté sur un build
  store/release.** Le client lit `(default)` (vide) alors que ses callables
  écrivent dans `staging`. D'où la discipline ci-dessous : le compte de test
  staging ne doit **jamais** être utilisé sur un build store ni en prod. Pas
  d'exposition cross-user ni de donnée prod : le compte n'existe qu'en `staging`
  et les callables restent bornés à son propre uid.

**Coût.** **+1 lecture Firestore par appel callable mobile** (2 pour le compte de
test staging : prod puis staging). **Toutes les Functions sont à redéployer**
(déploiement manuel, hors CI).

**Discipline.** Le compte de test doit être **staging-only** : créé sur
`app.staging.baillan.com`, doc `landlords/{uid}` présent en `staging` **avant** le
run (sinon repli sur la prod), **jamais utilisé en prod** (même contrainte que
pour le webhook : un uid présent dans les deux bases est routé en prod). Email
vérifié requis (le routeur de l'app bloque les comptes non vérifiés).

**Sécurité.** Un client non-navigateur peut forger l'`Origin`, mais ne route que
ses propres écritures, sans impact cross-user : les callables (Admin SDK, qui
contourne les règles Firestore) sont bornés à `request.auth.uid` par leurs
propres contrôles (`requireAuthUid`, `landlordId === uid`) ; les règles Firestore
protègent, elles, l'accès client direct sur les deux bases. Procédure opérationnelle : [`docs/MOBILE.md`](../MOBILE.md#test-lab-robo).

## Amendement 2026-09-30 — routage du webhook par `event.environment` (OWASP-01)

**Ce qui est remplacé.** La section « Déviation — routage du webhook par
présence du landlord » (`dbForLandlordUid`, prod d'abord) ne décrit plus le
webhook RevenueCat. Elle est conservée telle quelle pour l'historique ; son
affirmation « Fail-safe identique : prod testée en premier → jamais mal-router un
vrai compte prod » était **fausse** pour un achat de test.

**Pourquoi.** Un seul projet Firebase héberge les deux bases, l'Auth est
partagée, le checkout staging est public en Stripe **test** et un **seul**
webhook RevenueCat reçoit tous les events. Un compte prod pouvait donc se
connecter sur le staging, payer avec la carte de test publique, et le webhook —
qui trouvait son doc en prod d'abord — lui accordait un palier payant **en
production** (audit OWASP du 2026-09-30, constat OWASP-01). « La base qui porte
le doc » n'est pas une garde d'environnement : un même uid peut exister dans les
deux bases.

**Décision.** Le webhook choisit la base par l'`environment` de l'event
(`handleRevenueCatEvent` + `firestoreForEnv`, `functions/src/http/revenuecat_webhook.ts`
et `functions/src/utils/db_router.ts`) :
- `SANDBOX` (achat de test) → base `staging` **uniquement** ;
- `PRODUCTION` → base `(default)` **uniquement** ;
- absent ou autre valeur → event ignoré (fail-closed) et journalisé (uid + valeur
  brute bornée) ;
- **aucun repli** sur l'autre base : doc landlord absent de la base routée →
  `no_landlord`.

Mesures associées : `createCheckoutSession` refuse (`failed-precondition` /
`landlord_not_found`) quand `landlords/{uid}` est absent de la base routée ;
le cron `reconcileEntitlements` ignore les entitlements dont le produit est
`is_sandbox: true`. `dbForLandlordUid` reste utilisé uniquement par
`dbForRequest` pour les appels mobiles sans Origin (amendement 2026-09-29).

**Conséquences.**
- La discipline « tester un paiement staging avec un uid jamais utilisé en prod »
  n'est plus nécessaire côté webhook.
- Les achats **sandbox** d'App Review / TestFlight / licence de test Google faits
  avec un compte **prod** sont routés vers `staging` et ne débloquent donc rien :
  à traiter avec la feature achat intégré par une allowlist serveur d'uid prod
  autorisés en sandbox (webhook + cron). Les valeurs réelles d'`environment`
  restent à confirmer sur un event après déploiement.
- **Functions à redéployer manuellement** (webhook, checkout, cron).
- Reste ouvert : l'isolation structurelle (projet Firebase distinct pour le
  staging) — constat OWASP-07, non traité.
