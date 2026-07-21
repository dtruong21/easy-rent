# Baillan — Stratégie multi-environnement

> **Un seul projet Firebase** (`easy-rent-54cd4`), **deux sites Hosting**
> (`baillan.com` et `stage.baillan.com`). La séparation est **au niveau du
> Hosting uniquement** — pas au niveau des données.

## ⚠️ À lire en premier

**Staging et prod partagent le même plan de données.** Même base Firestore
`(default)`, même base Auth, même bucket Storage, mêmes Cloud Functions.

Concrètement :

- Un compte créé sur `stage.baillan.com` existe aussi pour `baillan.com`.
- Un bien / bail / quittance créé en test depuis staging est **une donnée de
  production**.
- Un déploiement de `firestore.rules` depuis `develop` s'applique **à la prod**.

→ **Ne teste jamais un scénario destructif ou générateur de données sur
staging.** Pour ça, il y a l'émulateur local (voir plus bas).

## 🧭 Ce qui est séparé, ce qui ne l'est pas

| Composant | Séparé dev/prod ? | Détail |
|---|---|---|
| **Hosting** | ✅ Oui | Deux sites : `easy-rent-54cd4` et `baillan-stage` |
| **Domaine** | ✅ Oui | `baillan.com` vs `stage.baillan.com` |
| **Indexation SEO** | ✅ Oui | `noindex` + robots bloquant sur staging |
| **Firestore** | ❌ **Non** | Base `(default)` partagée |
| **Auth** | ❌ **Non** | Même annuaire d'utilisateurs |
| **Storage** | ❌ **Non** | Même bucket `easy-rent-54cd4.firebasestorage.app` |
| **Cloud Functions** | ❌ **Non** | Un seul déploiement, région `europe-west1` |
| **Rules & indexes** | ❌ **Non** | Un seul `firestore.rules` / `firestore.indexes.json` |
| **Secrets** | ❌ **Non** | Un seul jeu (service account CI, secrets Functions) |

## 🌐 Hosting multi-site

Deux sites Firebase, chacun déployé sur son canal **live** via une cible
`.firebaserc` :

| Branche | Cible | Site | URL |
|---|---|---|---|
| `main` | `prod` | `easy-rent-54cd4` | https://baillan.com |
| `develop` | `stage` | `baillan-stage` | https://stage.baillan.com |

```json
// .firebaserc
{
  "projects": { "default": "easy-rent-54cd4" },
  "targets": {
    "easy-rent-54cd4": {
      "hosting": { "prod": ["easy-rent-54cd4"], "stage": ["baillan-stage"] }
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

`APP_ENV` pilote **uniquement des comportements applicatifs** — le SEO
(`noindex`), les URLs publiques, l'affichage de bandeaux de dev. **Il ne
change ni le projet, ni la base Firestore, ni le bucket.** Le défaut est `dev`,
c'est-à-dire le mode le moins exposé.

> 📌 Le commentaire en tête de `env.dart` mentionne une séparation
> `(default)` vs base Firestore `dev`. **Ce n'est pas implémenté** : les 21
> points d'accès Firestore de `lib/` utilisent `FirebaseFirestore.instance`
> (donc `(default)`), et `firebase.json` ne déclare que `(default)`. À traiter
> si on veut une vraie isolation (voir « Évolution »).

### Fichiers de dart-defines

| Fichier | Usage |
|---|---|
| `dart-defines.prod.example.json` | Build prod |
| `dart-defines.dev.example.json` | Build staging |
| `dart-defines.emulator.example.json` | Dev local sur émulateurs |
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

Un seul jeu, partagé. **Un déploiement depuis `develop` impacte la prod.**

| Artefact | Fichier | Portée |
|---|---|---|
| Règles Firestore | `firestore.rules` | Projet entier |
| Index composites | `firestore.indexes.json` | Base `(default)` |
| Règles Storage | `storage.rules` | Bucket unique |
| Cloud Functions | `functions/src/` | Projet entier |

Tests des règles avant tout déploiement :

```bash
npm --prefix functions run test:rules   # émulateur, projet demo-easyrent
```

## 🚫 SEO — noindex sur staging

`stage.baillan.com` est un domaine réellement crawlable : le `noindex` n'est pas
optionnel. Le workflow l'applique sur `build/web` juste avant le deploy quand
`APP_ENV=dev` :

- `web/robots.staging.txt` → `robots.txt` (tout-bloquant)
- `sitemap.xml` retiré
- `<meta name="robots" content="noindex">`

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

| Push sur | Cible Hosting | `APP_ENV` | Résultat |
|---|---|---|---|
| `develop` | `stage` | `dev` | https://stage.baillan.com (noindex) |
| `main` | `prod` | `prod` | https://baillan.com |

Le workflow ([`deploy.yml`](../.github/workflows/deploy.yml)) résout la cible
depuis la branche, ou via `workflow_dispatch` avec l'input `target`. Un seul
secret `FIREBASE_PROJECT_ID` — seul `--only hosting:<target>` diffère.

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
