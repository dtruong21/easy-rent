# Build Android de test sur la base staging (Firebase Test Lab) — design

> Date : 2026-09-29 · Statut : validé (brainstorming, approche A)
> Portée : client Flutter (mobile) + Cloud Functions (routage de base) + outillage Test Lab.

## 1. Problème

On veut faire tourner l'app Android sur de vrais appareils via **Firebase Test
Lab (Robo test)** sans polluer la production. Aujourd'hui c'est impossible :

- **Client** : `firestoreProvider` ne vise la base `staging` que pour un build
  **web** de staging (`kIsWeb && Env.isDev && !emulateur`). Tout build mobile
  lit/écrit `(default)` = **prod** (garde volontaire, ADR 0003).
- **Serveur** : les callables choisissent la base via `dbForRequest(request)`,
  qui route par l'en-tête **Origin** (`https://app.staging.baillan.com` →
  `staging`, tout le reste → `(default)`). Une app mobile n'envoie pas d'Origin
  → toutes ses écritures (créer bien, bail, paiement, quittance…) vont en prod.
- **Robo + Flutter** : Flutter peint sur une seule surface ; Robo navigue et
  tape mais remplit mal les champs de connexion. Sans connexion automatique,
  Robo reste bloqué sur l'écran d'accueil.

## 2. Décisions (validées)

| # | Décision |
|---|---|
| D1 | **Approche A — routage par compte** : les callables sans Origin (appels mobiles) sont routés vers la base qui porte le doc `landlords/{uid}`, prod d'abord, via la fonction existante `dbForLandlordUid` (déjà utilisée et relue pour le webhook RevenueCat). |
| D2 | Côté app, un réglage de build **`MOBILE_STAGING`** fait viser la base `staging` au mobile — **ignoré dans tout build release** (stores). |
| D3 | Le build de test **se connecte automatiquement** avec un compte de test staging-only, fourni au build par un fichier local non versionné. |
| D4 | Test Lab : APK **debug**, Robo test sur 3-4 appareils virtuels, via `gcloud`. |
| D5 | Hors périmètre : iOS sur Test Lab, tests de parcours `integration_test`, projet Firebase de staging séparé. |

## 3. Client Flutter

### 3.1 `Env`

Dans `lib/core/config/env.dart` :

- `MOBILE_STAGING` (`bool.fromEnvironment`, défaut `false`) exposé par
  `static bool get useMobileStaging => !kReleaseMode && _mobileStagingFlag;`
  — double garde comme `useFirebaseEmulator` : un build **release** ne peut
  jamais viser staging, même si le dart-define fuit dans la commande.
- `TEST_AUTO_LOGIN_EMAIL` / `TEST_AUTO_LOGIN_PASSWORD`
  (`String.fromEnvironment`, défaut `''`) exposés par un getter
  `testAutoLoginCredentials` qui renvoie `null` si `useMobileStaging` est faux
  ou si l'un des deux est vide.

### 3.2 `firestoreProvider`

Nouvelle règle (l'émulateur reste prioritaire) :

```
useStaging = !Env.useFirebaseEmulator
    && ((kIsWeb && Env.isDev) || Env.useMobileStaging)
```

Le commentaire du provider est mis à jour (la « conséquence assumée : pas
d'isolation mobile » n'est plus vraie pour le build de test).

### 3.3 Connexion automatique

Dans `main.dart`, après l'initialisation Firebase (et le branchement émulateur
éventuel), avant `runApp` : si `Env.testAutoLoginCredentials != null` et
qu'aucun utilisateur n'est connecté, `signInWithEmailAndPassword`. Un échec est
loggé (`Logger`) et n'empêche pas le démarrage (l'app reste sur l'écran de
connexion).

### 3.4 Bandeau

Le `builder` de `MaterialApp.router` affiche un ruban **« STAGING »** (couleur
distincte du ruban « EMULATOR ») quand `Env.useMobileStaging` est vrai.

### 3.5 Fichiers de réglages

- `dart-defines.testlab.example.json` (versionné, sans secret) :
  `APP_ENV=dev`, `MOBILE_STAGING=true`, `TEST_AUTO_LOGIN_EMAIL=""`,
  `TEST_AUTO_LOGIN_PASSWORD=""`.
- `dart-defines.testlab.json` (réel, **gitignoré**) : rempli localement avec le
  compte de test. `.gitignore` : ajouter `dart-defines.testlab.json` et
  l'exception `!dart-defines.testlab.example.json`.

## 4. Cloud Functions

### 4.1 `dbForRequest` asynchrone

Dans `functions/src/utils/db_router.ts` :

```ts
export async function dbForRequest(request: CallableRequest): Promise<Firestore> {
  const origin = request.rawRequest?.headers?.origin;
  if (typeof origin === "string" && origin.length > 0) {
    return firestoreForEnv(isStagingOrigin(origin));   // web : inchangé
  }
  return dbForLandlordUid(request.auth?.uid ?? "");     // mobile : par compte
}
```

- **Web** : comportement strictement identique (staging web → `staging`, prod
  et origines inattendues → `(default)`).
- **Mobile** : prod d'abord (fail-safe — un vrai utilisateur a son doc en prod),
  puis `staging` ; absent des deux → `(default)`.
- Coût : une lecture Firestore de plus par appel mobile (deux pour le compte de
  test). Aucun coût pour le web.

### 4.2 Appels

Les ~24 appels dans 13 fichiers `functions/src/callable/*.ts` passent de
`dbForRequest(request)` à `await dbForRequest(request)` (toutes les fonctions
appelantes sont déjà `async`). `scripts/check-db-isolation.sh` doit rester vert.

### 4.3 Déploiement

Après merge : `firebase deploy --only functions` (les Functions sont partagées
prod/staging) — **sur confirmation explicite de l'utilisateur**. Aucun
changement de rules ni d'index.

## 5. Compte de test et Test Lab

- Compte créé **une seule fois** sur `https://app.staging.baillan.com`
  (doc `landlords/{uid}` dans `staging`). **Ne jamais l'utiliser en prod** :
  s'il y existait, le routage (prod d'abord) l'y enverrait.
- Build :
  `flutter build apk --debug --dart-define-from-file=dart-defines.testlab.json`
- Lancement (exemple, documenté dans `docs/MOBILE.md`) :
  `gcloud firebase test android run --type robo --app build/app/outputs/flutter-apk/app-debug.apk --device model=MediumPhone.arm,version=34 --device model=Pixel2.arm,version=30 --timeout 300s --project easy-rent-54cd4`
- Résultats (plantages, captures, vidéo) : console Firebase → Test Lab.
- Quota gratuit : 10 tests/jour sur appareils virtuels.

## 6. Tests

- **Functions** (`db_router` + un callable représentatif) :
  - Origin staging → `staging` ; Origin prod → `(default)` ; Origin inattendu → `(default)` ;
  - sans Origin, doc landlord en prod → `(default)` ;
  - sans Origin, doc landlord uniquement en staging → `staging` ;
  - sans Origin, doc absent → `(default)`.
- **Flutter** : le choix de base est extrait dans une fonction pure testable
  `bool shouldUseStagingDatabase({required bool isWeb, required bool isDev, required bool useEmulator, required bool useMobileStaging})`
  (utilisée par `firestoreProvider`) — table de vérité testée, dont
  « émulateur prioritaire » et « mobile sans `MOBILE_STAGING` → prod ».
  `useMobileStaging` faux en release est garanti par `kReleaseMode` (constante
  de compilation, pas testable en unitaire) : documenté.
- Suites existantes vertes (Flutter + functions lint/build/test).

## 7. Documentation

- `docs/MOBILE.md` : section « Test Lab (Robo) » (compte, build, commande, lecture des résultats).
- `docs/ENVIRONMENTS.md` : routage mobile de test ; corriger le domaine staging
  de l'app (`app.staging.baillan.com` ; `stage.baillan.com` = vitrine).
- ADR 0003 : amendement court (routage mobile par compte).
- `docs/state` : shard functions (routage) + CHANGELOG.
