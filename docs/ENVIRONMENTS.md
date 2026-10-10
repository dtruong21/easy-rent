# Baillan — Stratégie multi-environnement

> **Un seul projet Firebase** (`easy-rent-54cd4`), **deux sites Hosting**
> (`baillan.com` et `app.staging.baillan.com`). Depuis l'**ADR 0003**, les **données
> Firestore** sont isolées (base `staging`) ; **Auth, Storage et le code
> des Cloud Functions restent partagés**.

## ⚠️ À lire en premier

**Depuis l'ADR 0003, les données Firestore de staging sont ISOLÉES** : staging
écrit dans une base Firestore nommée `staging`, la prod dans `(default)`. En
revanche **Auth, Storage et les secrets restent partagés**.

Concrètement :

- Un **bien / bail / quittance / entitlement** créé depuis `app.staging.baillan.com`
  vit dans la base `staging` — **ce n'est plus une donnée de production.**
- Un **compte** créé sur staging existe quand même côté prod (**Auth partagée**),
  mais son doc `landlords/{uid}` et toutes ses données métier sont dans `staging`.
- Les **fichiers uploadés** (justificatifs, photos) vont dans le **bucket prod**
  (Storage non isolé) — rester mesuré sur les uploads de test.
- Le **code** des Cloud Functions déployé depuis `develop` tourne aussi sur la
  prod ; seul le routage des **writes Firestore** est isolé (par Origin côté
  callables web, par compte — présence du landlord — côté appels mobiles sans
  Origin, par `event.environment` côté webhook RevenueCat — cf. « Facturation »
  ci-dessous).
- `firestore.rules` / `firestore.indexes.json` sont **identiques** sur les deux
  bases (même fichier source), mais la CI les déploie **base par base** :
  `develop` → `staging`, `main` → `(default)`. La prod ne bouge donc que sur un
  push `main`.

→ Voir [`docs/adr/0003-firestore-prod-staging-isolation.md`](adr/0003-firestore-prod-staging-isolation.md)
pour le détail, les limitations (crons/triggers sur `(default)`), et la
discipline de test paiement (compte jamais utilisé en prod). L'émulateur local
reste l'environnement le plus isolé (Firestore + Auth + Functions locaux).

## 🧭 Ce qui est séparé, ce qui ne l'est pas

| Composant | Séparé dev/prod ? | Détail |
|---|---|---|
| **Hosting** | ✅ Oui | Quatre sites : app (`easy-rent-54cd4`, `baillan-stage`) + vitrine (`baillan-marketing`, `baillan-marketing-stage`, FEAT-050) |
| **Domaine** | ✅ Oui | `baillan.com` vs `app.staging.baillan.com` |
| **Indexation SEO** | ✅ Oui | `noindex` + robots bloquant sur staging |
| **Firestore (données)** | ✅ **Oui** | Base `staging` vs `(default)` (prod) — ADR 0003 |
| **Auth** | ❌ **Non** | Même annuaire d'utilisateurs |
| **Storage** | ❌ **Non** | Même bucket `easy-rent-54cd4.firebasestorage.app` |
| **Cloud Functions** | ❌ **Non** | Un seul déploiement, région `europe-west1` |
| **Rules & indexes** | ⚠️ **Partiel** | Même fichier source, mais déploiement CI ciblé par base (`develop`→`staging`, `main`→`(default)`) |
| **Secrets** | ❌ **Non** | Un seul jeu (service account CI, secrets Functions) |

> **Facturation (OWASP-01, 2026-09-30).** Vraisemblablement un seul webhook
> RevenueCat (à confirmer dans la console RevenueCat ; un seul secret
> `REVENUECAT_WEBHOOK_AUTH` côté Functions) sert les deux environnements, et le checkout
> staging public tourne en Stripe **test**. Le webhook route donc chaque event
> par son champ `environment` : `SANDBOX` (achat de test : Stripe test, sandbox
> App Store, licence de test Google) → base `staging` **uniquement** ;
> `PRODUCTION` → `(default)` **uniquement** ; absent ou autre valeur → ignoré et
> journalisé. Il n'y a **aucun repli** sur l'autre base : un achat de test ne peut
> plus accorder un palier sur un compte prod, et `createCheckoutSession` refuse
> (`landlord_not_found`) un compte sans doc dans la base routée. Contrepartie : un
> achat sandbox (App Review, TestFlight) fait avec un compte **prod** ne débloque
> rien, sauf **exception FEAT-044e** : si l'uid figure dans la liste blanche
> `_ops/sandboxAllowlist` (champ `uids`, base prod, éditée dans la console, refusée
> à tout client), son achat sandbox **App Store / Google Play** est appliqué à
> `(default)` et le cron le traite comme un vrai droit. Un achat Stripe test (web
> staging) reste en staging, uid listé ou non. Liste illisible : le webhook répond
> 500 sans rien écrire (RevenueCat retente) ; le cron passe sans liste
> (`logger.error`). Pour tout autre uid, le cron `reconcileEntitlements`
> n'accorde ni ne prolonge rien d'après un achat sandbox (état enregistré conservé
> jusqu'à son échéance, #209). Côté RevenueCat, vérifier dans les
> réglages du webhook si une option de filtrage par environnement existe
> (« Production only ») — action manuelle, non vérifiée par l'audit.
>
> **À confirmer après le déploiement des Functions** : les valeurs réelles
> d'`environment` envoyées par RevenueCat. Un achat de test sur le staging avec
> une carte de test Stripe doit produire un log `env="SANDBOX"` et écrire dans la
> base `staging` (jamais dans `(default)`). Si la valeur diffère, l'event est
> ignoré (fail-closed) : aucun palier accordé, à corriger avant d'ouvrir l'abonnement.

## 🌐 Hosting multi-site

Deux sites Firebase, chacun déployé sur son canal **live** via une cible
`.firebaserc` :

| Branche | Cible | Site | URL | Sert |
|---|---|---|---|---|
| `main` | `prod` | `easy-rent-54cd4` | https://baillan.com (à basculer) | app Flutter |
| `develop` | `stage` | `baillan-stage` | https://app.staging.baillan.com | app Flutter |
| `main` | `marketing` | `baillan-marketing` | (domaine non branché) | vitrine Astro (FEAT-050) |
| `develop` | `marketing-stage` | `baillan-marketing-stage` | https://stage.baillan.com (baillan-marketing-stage.web.app) | vitrine Astro |

> **FEAT-050** a ajouté les deux cibles `marketing`. La vitrine est un site
> **Astro statique** (`site/`), servi depuis `site/dist` — distinct de l'app
> Flutter (`build/web`). À terme (bascule de domaine, runbook séparé) : la
> vitrine prend `baillan.com`, l'app déménage sur `app.baillan.com`. En
> attendant, `marketing` prod sert un `X-Robots-Tag: noindex` **transitoire**
> (retiré par le runbook) et son domaine n'est pas encore branché.

```json
// .firebaserc
{
  "projects": { "default": "easy-rent-54cd4" },
  "targets": {
    "easy-rent-54cd4": {
      "hosting": {
        "prod": ["easy-rent-54cd4"], "stage": ["baillan-stage"],
        "marketing": ["baillan-marketing"], "marketing-stage": ["baillan-marketing-stage"]
      }
    }
  }
}
```

Pourquoi deux sites plutôt qu'un preview channel : **un preview channel ne peut
pas porter de domaine personnalisé** (les domaines s'attachent au canal live
d'un site). L'ancienne URL à hash `*--staging-*.web.app` n'est donc plus
alimentée.

> ⚠️ Les *sites* Hosting ne sont pas des *projets*. `baillan-stage` est un site
> à l'intérieur de `easy-rent-54cd4` — c'est précisément pourquoi les données
> sont communes.

## ⚙️ `APP_ENV` — ce qu'il fait réellement

Le build injecte `--dart-define=APP_ENV=dev|prod`
([`lib/core/config/env.dart`](../lib/core/config/env.dart)) :

```dart
static const String appEnv = String.fromEnvironment('APP_ENV', defaultValue: 'dev');
static bool get isProd => appEnv == 'prod';
```

`APP_ENV` pilote des comportements applicatifs (SEO `noindex`, URLs publiques,
bandeaux de dev) **et, depuis l'ADR 0003, la base Firestore sur le web** : un
build web `APP_ENV=dev` route vers la base `staging` (via `firestoreProvider`).
Il ne change en revanche **ni le projet Firebase, ni Auth, ni le bucket
Storage**. Le défaut est `dev`, c'est-à-dire le mode le moins exposé.

> 📌 **Isolation implémentée (ADR 0003).** Les accès Firestore de `lib/` passent
> désormais par `firestoreProvider` (`lib/core/config/firestore_provider.dart`),
> et `firebase.json` déclare les deux bases `(default)` + `staging`. Le routage
> est **fail-safe vers `(default)`** : seuls un build **web** de staging
> (`kIsWeb && APP_ENV=dev`) et le build de test mobile (debug, `MOBILE_STAGING`,
> ci-dessous) visent `staging` ; tout build mobile de release reste sur
> `(default)`.

### Build de test mobile (Test Lab)

Un build **debug** mobile peut viser la base `staging` avec le dart-define
`MOBILE_STAGING=true` (`Env.useMobileStaging`, **ignoré en release** : jamais
actif dans un build store). Il sert au Firebase Test Lab (Robo), qui ne doit pas
écrire en prod — procédure dans [`MOBILE.md`](MOBILE.md#test-lab-robo).

- **App** : `firestoreProvider` route vers la base `staging` (l'émulateur garde
  la priorité) et l'app se connecte seule à un compte de test staging-only
  (`TEST_AUTO_LOGIN_EMAIL` / `TEST_AUTO_LOGIN_PASSWORD`, fichier gitignoré).
- **Functions** : un callable **sans en-tête `Origin`** (cas d'une app native)
  est routé **par compte** (`dbForLandlordUid` : base qui porte le doc
  `landlords/{uid}`, prod d'abord) ; le web reste routé par `Origin`. Requiert
  des Functions redéployées avec ce routage — cf. ADR 0003, amendement
  2026-09-29.
- **Discipline** : l'utilisateur Auth du compte de test est **partagé** (Auth
  n'est pas séparé par environnement) ; ce sont le doc `landlords/{uid}` et les
  données métier qui n'existent qu'en `staging`. Le compte n'est **jamais utilisé
  en prod** (sinon le doc existerait aussi en `(default)` et le routage mobile le
  renverrait en prod).

### Fichiers de dart-defines

| Fichier | Usage |
|---|---|
| `dart-defines.prod.example.json` | Build prod |
| `dart-defines.dev.example.json` | Build staging |
| `dart-defines.emulator.example.json` | Dev local sur émulateurs |
| `dart-defines.testlab.example.json` | Build de test mobile (Test Lab) sur `staging` |
| `dart-defines.example.json` | Gabarit générique |

Ce sont des **exemples** : copie-les sans le `.example` (les vrais fichiers ne
sont pas versionnés).

## 🧪 Tester sans risque : l'émulateur local

C'est le **seul** environnement réellement isolé. Toute manipulation de données
de test (tiers free/Pro, quotas, scénarios de bail) passe par là.

```bash
# Émulateurs Firestore + Auth + Functions
npm --prefix functions run serve

# Seed des jeux d'essai (tiers free/Pro)
node tool/seed/seed_tiers.mjs

# App branchée sur les émulateurs (build DEBUG obligatoire)
flutter run --dart-define-from-file=dart-defines.emulator.json
```

Garde-fous côté code :

- `Env.useFirebaseEmulator` = `kDebugMode && USE_FIREBASE_EMULATOR` — un build
  release ne peut **jamais** pointer les émulateurs, même si le flag fuit.
- Hôte par défaut `127.0.0.1` (pas `localhost` : sur le web Chromium résout
  `localhost` en IPv6 `::1`, que les émulateurs n'écoutent pas — l'app
  retombait alors silencieusement sur le backend **prod**). Émulateur Android :
  `--dart-define=FIREBASE_EMULATOR_HOST=10.0.2.2`.
- Ports alignés `firebase.json` / `env.dart` / `seed_tiers.mjs` : Firestore
  `8080`, Auth `9099`.

## 🔒 Rules, indexes et Functions

Un seul jeu de **fichiers**, mais depuis la CI le déploiement est **ciblé par
environnement** (voir « Déploiement ») :

| Artefact | Fichier | Portée | Déployé par la CI depuis |
|---|---|---|---|
| Règles Firestore | `firestore.rules` | Par base | `develop` → base `staging` ; `main` → `(default)` |
| Index composites | `firestore.indexes.json` | Par base | idem |
| Règles Storage | `storage.rules` | Bucket unique (partagé) | `main` uniquement (`deploy.yml`, cible `storage`) |
| Cloud Functions | `functions/src/` | Projet entier (partagé) | **personne — déploiement manuel** |

> ⚠️ **Les Cloud Functions restent le point non isolé.** Un seul déploiement
> sert staging ET prod : `firebase deploy --only functions` depuis `develop`
> pousse du code non relu en production. C'est volontairement **hors CI** pour
> qu'aucun push ne le déclenche par accident (ADR 0003, « Limitations
> assumées »). Déployer les Functions est un geste manuel et délibéré, depuis
> `main` de préférence.

> ⚠️ **Ne JAMAIS lancer `firebase deploy` sans `--only`.** Sans filtre, la CLI
> déploie les rules sur **les deux bases** (donc la prod) et les Functions —
> depuis n'importe quelle branche. Toujours cibler : `--only
> "firestore:staging"`, `--only "firestore:(default)"`, etc.

Tests des règles avant tout déploiement :

```bash
npm --prefix functions run test:rules   # émulateurs Firestore + Storage, projet demo-easyrent
```

## 🚫 SEO — noindex sur staging

**Depuis FEAT-050, l'app Flutter est `noindex` en permanence**, dans tous les
environnements : `web/robots.txt` est `Disallow: /` global, `web/sitemap.xml`
supprimé, `<meta name="robots" content="noindex, nofollow">` inconditionnel.
Son contenu n'est de toute façon pas indexable (CanvasKit peint le texte dans un
canvas) ; la surface crawlable est la **vitrine** (`baillan.com`, cible
`marketing`).

L'étape staging du workflow (`APP_ENV=dev` : `web/robots.staging.txt` →
`robots.txt`, `sitemap.xml` retiré, meta `noindex`) subsiste comme **filet
idempotent** — elle ne change plus rien puisque le défaut est déjà `noindex`.

La **vitrine de staging** (`marketing-stage`) est `noindex` par un
`X-Robots-Tag: noindex, nofollow` servi sur `**` (config Hosting), et son
`robots.txt` répond `Disallow: /` quand `SITE_ENV=staging`.

## 🔐 Secrets

Partagés entre les deux environnements (projet unique) :

- Une fuite de clé côté staging expose la prod.
- Les secrets serveur (webhook RevenueCat, clé Stripe…) se posent via
  `firebase functions:secrets:set` — **une seule fois pour les deux
  environnements**, puisqu'il n'y a qu'un projet.

> **Aucun envoi d'email serveur aujourd'hui.** `RESEND_API_KEY` a été éliminé
> au pivot FEAT-008 (2026-06-22) : les quittances sont générées en PDF **côté
> client** puis partagées via **Web Share natif** (repli `mailto:`), donc via
> le client mail de l'utilisateur — zéro secret email backend, et rien ne part
> « tout seul » depuis staging.
>
> ⚠️ À rouvrir quand **FEAT-031** (rappels automatiques, encore `📋 planned`
> faute d'infra email) arrivera : les secrets étant partagés, staging enverra
> alors de **vrais emails à de vrais locataires**. Prévoir un domaine
> d'expédition de test — ou couper l'envoi quand `APP_ENV=dev`.

Détail et rotation : [`SECURITY.md`](SECURITY.md).

## 🚀 Déploiement

| Push sur | Cibles `--only` | `APP_ENV` | Résultat |
|---|---|---|---|
| `develop` | `hosting:stage,hosting:marketing-stage,firestore:staging` | `dev` | app + vitrine staging (noindex) |
| `main` | `hosting:prod,hosting:marketing,firestore:(default),storage` | `prod` | app + vitrine prod |

Le workflow ([`deploy.yml`](../.github/workflows/deploy.yml)) résout les cibles
depuis la branche (sortie `deploy_targets` du job `determine-env`), ou via
`workflow_dispatch` avec l'input `target`. Un seul secret
`FIREBASE_PROJECT_ID` — seules les cibles `--only` diffèrent.

**Le ciblage par base est ce qui protège la prod** : `firestore:staging` ne
touche que la base `staging`, `firestore:(default)` que la prod. Un push sur
`develop` ne peut donc plus modifier les rules de production. Si
`deploy_targets` était vide, la step échoue au lieu de lancer un `deploy` sans
filtre (qui viserait les deux bases).

> Pas de preview deploy sur les PR : `ci.yml` et `deploy.yml` ne se déclenchent
> que sur `[main, develop]`.

## 🧹 Maintenance périodique

~1×/mois :

- [ ] Purger les comptes de test créés depuis staging (ils sont en prod)
- [ ] Auditer les données orphelines générées par les tests manuels
- [ ] Vérifier que `firestore.indexes.json` couvre les queries récentes
- [ ] Rejouer `npm --prefix functions run test:rules` après tout changement de
      rules

## ⏭️ Évolution — obtenir une vraie isolation

Deux options, par ordre de coût croissant :

**1. Base Firestore nommée (`dev`) dans le même projet.** Firestore supporte le
multi-base. Il faut : créer la base, déclarer un second bloc `firestore` dans
`firebase.json`, déployer rules+indexes sur les deux, et surtout **router les 21
appels `FirebaseFirestore.instance`** vers
`FirebaseFirestore.instanceFor(databaseId: …)` selon `APP_ENV` (typiquement via
un provider Riverpod unique). Auth et Storage resteraient partagés.

**2. Second projet Firebase dédié au dev.** Isolation complète (Firestore, Auth,
Storage, Functions, secrets). Il faut : un second jeu de `firebase_options`
sélectionné par `APP_ENV`, des alias `.firebaserc` (`dev`/`prod`), deux secrets
`FIREBASE_PROJECT_ID` dans le workflow, et un double déploiement
rules/indexes/functions. C'est la seule option qui protège aussi Auth et
Storage.

Tant qu'aucune des deux n'est faite : **l'émulateur est le seul bac à sable.**
