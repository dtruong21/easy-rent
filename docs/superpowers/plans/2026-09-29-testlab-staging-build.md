# Build Android de test sur la base staging (Test Lab) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Permettre de lancer l'app Android sur Firebase Test Lab (Robo) contre la base Firestore `staging`, sans jamais toucher la prod ni les builds publiés.

**Architecture:** Côté serveur, `dbForRequest` devient asynchrone : les appels web restent routés par l'en-tête Origin, les appels sans Origin (mobile) sont routés par la base qui porte le doc `landlords/{uid}` (prod d'abord, fonction existante `dbForLandlordUid`). Côté client, un réglage `MOBILE_STAGING` (ignoré en release) fait viser `staging` au mobile et déclenche une connexion automatique avec un compte de test staging-only.

**Tech Stack:** Cloud Functions TS (firebase-functions v6, firebase-admin 12, vitest), Flutter/Riverpod, gcloud Firebase Test Lab.

**Spec :** `docs/superpowers/specs/2026-09-29-testlab-staging-build-design.md`

## Global Constraints

- Web : routage **strictement inchangé** (Origin `https://app.staging.baillan.com` → `staging`, tout autre Origin non vide → `(default)`).
- Mobile (Origin absent ou vide) : `dbForLandlordUid(uid)` — prod d'abord, puis `staging`, absent des deux → `(default)`.
- `MOBILE_STAGING` et l'auto-login n'ont **aucun effet** quand `kReleaseMode` est vrai.
- L'émulateur local (`Env.useFirebaseEmulator`) reste **prioritaire** sur tout routage staging.
- Aucun identifiant réel commité : seul `dart-defines.testlab.example.json` (valeurs vides) est versionné ; `dart-defines.testlab.json` est gitignoré.
- Accès Firestore : jamais `FirebaseFirestore.instance`/`instanceFor` hors `main.dart` et `firestore_provider.dart` ; jamais `admin.firestore()`/`getFirestore()` dans `functions/src/` hors `utils/db_router.ts` et crons/triggers. `scripts/check-db-isolation.sh` doit rester vert.
- Functions : chaque tâche touchant `functions/` lance `npm run lint`, `npm run build`, `npm test` (dans `functions/`).
- Flutter : `export PATH=/opt/homebrew/bin:$PATH` ; `dart format` sur les fichiers touchés (jamais `dart format .`) ; `flutter analyze` sans issue ; `flutter test` vert.
- Commits : `git add` chemins explicites, jamais `-A` ; ne jamais ajouter `firebase.altports.local.json`. Fin de message : `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Aucun déploiement dans ce plan (le déploiement des Functions se fait après merge, sur confirmation humaine).

---

## Structure des fichiers

| Fichier | Rôle |
|---|---|
| `functions/src/utils/db_router.ts` | `dbForRequest` async (Origin → web ; sinon compte) |
| `functions/src/__tests__/helpers/fake_firestore.ts` | holder d'une FakeFirestore « staging » |
| `functions/src/__tests__/helpers/setup_firestore_mock.ts` | `getFirestore(id)` → FakeFirestore staging en test |
| `functions/src/__tests__/db_router.test.ts` | nouveaux cas mobile |
| `functions/src/callable/*.ts` (13 fichiers) | `await dbForRequest(request)` |
| `lib/core/config/env.dart` | `useMobileStaging`, `testAutoLoginCredentials` |
| `lib/core/config/firestore_provider.dart` | `shouldUseStagingDatabase(...)` + provider |
| `lib/main.dart` | auto-login + ruban « STAGING » |
| `dart-defines.testlab.example.json`, `.gitignore` | réglages du build de test |
| `test/unit/firestore_provider_routing_test.dart` | table de vérité du choix de base |
| `docs/MOBILE.md`, `docs/ENVIRONMENTS.md`, `docs/adr/0003-*.md`, `docs/state/*` | documentation |

---

### Task 1: Functions — routage mobile par compte

**Files:**
- Modify: `functions/src/utils/db_router.ts`
- Modify: `functions/src/__tests__/helpers/fake_firestore.ts`
- Modify: `functions/src/__tests__/helpers/setup_firestore_mock.ts`
- Modify: `functions/src/__tests__/db_router.test.ts`
- Modify: the 13 files in `functions/src/callable/` that call `dbForRequest(` (find them with `grep -rln "dbForRequest(" functions/src/callable`)

**Interfaces:**
- Produces: `export async function dbForRequest(request: CallableRequest): Promise<Firestore>`; test helper `fakeStagingFirestoreHolder: {db: FakeFirestore}`.

- [ ] **Step 1: Helper de test « base staging »**

Dans `functions/src/__tests__/helpers/fake_firestore.ts`, à côté de `fakeAdminFirestoreHolder`, ajouter :

```ts
/**
 * Base nommée `staging` en test : `getFirestore(STAGING_DATABASE_ID)` (mocké
 * par `setup_firestore_mock.ts`) renvoie `db`. Vide par défaut — un appel
 * mobile dont le landlord n'est pas en prod retombe donc sur la prod, comme
 * en production quand le doc n'existe nulle part.
 */
export const fakeStagingFirestoreHolder: {db: FakeFirestore} = {
  db: new FakeFirestore(),
};
```

Dans `functions/src/__tests__/helpers/setup_firestore_mock.ts`, compléter le mock de `firebase-admin/firestore` pour que `getFirestore` renvoie cette base :

```ts
vi.mock("firebase-admin/firestore", async (importOriginal) => {
  const actual = await importOriginal<typeof FirestoreModule>();
  const {fakeFieldValue, fakeStagingFirestoreHolder} = await import(
    "./fake_firestore"
  );
  return {
    ...actual,
    FieldValue: fakeFieldValue,
    // Base nommée (staging) → FakeFirestore dédiée ; la prod passe par
    // `admin.firestore()`, mockée ailleurs.
    getFirestore: () => fakeStagingFirestoreHolder.db,
  };
});
```

(Adapter l'en-tête de commentaire du fichier : il mocke désormais aussi `getFirestore`.)

- [ ] **Step 2: Tests qui échouent**

Dans `functions/src/__tests__/db_router.test.ts`, importer `dbForRequest` et `fakeStagingFirestoreHolder`, puis ajouter :

```ts
describe("dbForRequest — web par Origin, mobile par compte", () => {
  let prod: FakeFirestore;
  let staging: FakeFirestore;

  beforeEach(() => {
    prod = new FakeFirestore();
    staging = new FakeFirestore();
    fakeAdminFirestoreHolder.db = prod;
    fakeStagingFirestoreHolder.db = staging;
  });

  const req = (uid: string, origin?: string) =>
    ({
      auth: {uid},
      rawRequest: {headers: origin === undefined ? {} : {origin}},
    }) as unknown as CallableRequest;

  it("web : Origin staging → staging, même si le compte est en prod", async () => {
    prod.seed("landlords/u1", {id: "u1"});
    expect(await dbForRequest(req("u1", STAGING_ORIGIN))).toBe(staging);
  });

  it("web : Origin prod → prod", async () => {
    staging.seed("landlords/u1", {id: "u1"});
    expect(await dbForRequest(req("u1", "https://baillan.com"))).toBe(prod);
  });

  it("web : Origin inattendu → prod", async () => {
    expect(await dbForRequest(req("u1", "https://evil.example"))).toBe(prod);
  });

  it("mobile : compte en prod → prod", async () => {
    prod.seed("landlords/u1", {id: "u1"});
    staging.seed("landlords/u1", {id: "u1"});
    expect(await dbForRequest(req("u1"))).toBe(prod);
  });

  it("mobile : compte uniquement en staging → staging", async () => {
    staging.seed("landlords/u2", {id: "u2"});
    expect(await dbForRequest(req("u2"))).toBe(staging);
  });

  it("mobile : compte absent → prod (fail-safe)", async () => {
    expect(await dbForRequest(req("u3"))).toBe(prod);
  });

  it("mobile : Origin vide traité comme absent", async () => {
    staging.seed("landlords/u2", {id: "u2"});
    expect(await dbForRequest(req("u2", ""))).toBe(staging);
  });
});
```

(Ajouter `import type {CallableRequest} from "firebase-functions/v2/https";`. Mettre à jour le commentaire en tête du fichier : le chemin staging est désormais mocké.)

Run (dans `functions/`) : `npx vitest run src/__tests__/db_router.test.ts` — Expected: FAIL (dbForRequest non async / cas mobile).

- [ ] **Step 3: Implémentation**

Dans `functions/src/utils/db_router.ts`, remplacer `dbForRequest` par :

```ts
/**
 * Base Firestore pour une requête callable.
 *
 * - **Web** (Origin présent) : routage par l'Origin, inchangé — seul le
 *   staging web va vers `staging`, tout le reste vers `(default)`.
 * - **Mobile** (Origin absent ou vide — une app native n'en envoie pas) :
 *   routage par la base qui porte le doc landlord ([dbForLandlordUid]), prod
 *   d'abord. Un vrai utilisateur mobile a son compte en prod → prod ; le
 *   compte de test du build Test Lab n'existe qu'en staging → staging.
 *
 * Un client non-navigateur pourrait forger l'Origin, mais il ne routerait que
 * SES propres écritures (les règles d'ownership s'appliquent sur les deux
 * bases) — pas d'impact cross-user.
 */
export async function dbForRequest(
  request: CallableRequest,
): Promise<Firestore> {
  const origin = request.rawRequest?.headers?.origin;
  if (typeof origin === "string" && origin.length > 0) {
    return firestoreForEnv(isStagingOrigin(origin));
  }
  return dbForLandlordUid(request.auth?.uid ?? "");
}
```

Mettre à jour le commentaire d'en-tête du module (section « Callables ») : web par Origin, mobile par compte.

- [ ] **Step 4: Appels**

Dans chaque fichier de `functions/src/callable/` : remplacer `dbForRequest(request)` par `await dbForRequest(request)`. Vérifier que chaque fonction englobante est `async` (elles le sont toutes : handlers `onCall(async (request) => …)`). Si un appel est dans une fonction utilitaire non-async, la rendre async et `await` ses appelants.

Run (dans `functions/`) : `npm run lint && npm run build && npm test`, puis à la racine `bash scripts/check-db-isolation.sh`.
Expected : lint/build OK, tous les tests verts (y compris les 7 nouveaux), isolation OK. Si un test de callable existant échoue parce qu'il n'avait pas de doc landlord en prod, vérifier d'abord que la base staging de test est bien vide (holder réinitialisé) — ne pas affaiblir le test.

- [ ] **Step 5: Commit**

```bash
git add functions/src/utils/db_router.ts functions/src/__tests__/helpers/fake_firestore.ts functions/src/__tests__/helpers/setup_firestore_mock.ts functions/src/__tests__/db_router.test.ts functions/src/callable/*.ts
git commit -m "feat(functions): routage mobile par compte (dbForRequest async)"
```

(Lister explicitement les fichiers `callable/*.ts` réellement modifiés plutôt que le glob si un fichier non concerné a changé.)

---

### Task 2: Flutter — réglage `MOBILE_STAGING`, base staging, auto-login, ruban

**Files:**
- Modify: `lib/core/config/env.dart`
- Modify: `lib/core/config/firestore_provider.dart`
- Modify: `lib/main.dart`
- Create: `dart-defines.testlab.example.json`
- Modify: `.gitignore`
- Test: `test/unit/firestore_provider_routing_test.dart` (créé)

**Interfaces:**
- Produces: `Env.useMobileStaging` (`bool`), `Env.testAutoLoginCredentials` (`({String email, String password})?`), `bool shouldUseStagingDatabase({required bool isWeb, required bool isDev, required bool useEmulator, required bool useMobileStaging})`.

- [ ] **Step 1: Test qui échoue**

`test/unit/firestore_provider_routing_test.dart` :

```dart
/// Table de vérité du choix de base Firestore (ADR 0003 + build Test Lab).
library;

import 'package:easyrent/core/config/firestore_provider.dart';
import 'package:flutter_test/flutter_test.dart';

bool _staging({
  bool isWeb = false,
  bool isDev = true,
  bool useEmulator = false,
  bool useMobileStaging = false,
}) => shouldUseStagingDatabase(
  isWeb: isWeb,
  isDev: isDev,
  useEmulator: useEmulator,
  useMobileStaging: useMobileStaging,
);

void main() {
  test('web staging (APP_ENV=dev) → staging', () {
    expect(_staging(isWeb: true), isTrue);
  });
  test('web prod → prod', () {
    expect(_staging(isWeb: true, isDev: false), isFalse);
  });
  test('mobile sans MOBILE_STAGING → prod (même APP_ENV=dev)', () {
    expect(_staging(), isFalse);
  });
  test('mobile avec MOBILE_STAGING → staging', () {
    expect(_staging(useMobileStaging: true), isTrue);
  });
  test('émulateur prioritaire (web)', () {
    expect(_staging(isWeb: true, useEmulator: true), isFalse);
  });
  test('émulateur prioritaire (mobile staging)', () {
    expect(_staging(useMobileStaging: true, useEmulator: true), isFalse);
  });
}
```

Run: `flutter test test/unit/firestore_provider_routing_test.dart` — Expected: FAIL (fonction absente).

- [ ] **Step 2: `Env`**

Dans `lib/core/config/env.dart` : importer `kReleaseMode` (`show kDebugMode, kReleaseMode`), et ajouter après `useFirebaseEmulator` :

```dart
  static const bool _mobileStagingFlag = bool.fromEnvironment(
    'MOBILE_STAGING',
    defaultValue: false,
  );

  /// Build de test mobile (Firebase Test Lab) sur la base `staging`.
  ///
  /// Double garde, comme [useFirebaseEmulator] : `kReleaseMode` garantit qu'un
  /// build publié sur les stores ne vise JAMAIS staging, même si le
  /// dart-define fuit dans la commande de release.
  static bool get useMobileStaging => !kReleaseMode && _mobileStagingFlag;

  static const String _testAutoLoginEmail = String.fromEnvironment(
    'TEST_AUTO_LOGIN_EMAIL',
  );
  static const String _testAutoLoginPassword = String.fromEnvironment(
    'TEST_AUTO_LOGIN_PASSWORD',
  );

  /// Compte de test staging-only pour la connexion automatique du build Test
  /// Lab (Robo ne sait pas remplir un formulaire Flutter). `null` hors build
  /// de test ou si l'un des deux champs est vide. Fourni au build par
  /// `dart-defines.testlab.json` (gitignoré) — jamais commité.
  static ({String email, String password})? get testAutoLoginCredentials {
    if (!useMobileStaging) return null;
    if (_testAutoLoginEmail.isEmpty || _testAutoLoginPassword.isEmpty) {
      return null;
    }
    return (email: _testAutoLoginEmail, password: _testAutoLoginPassword);
  }
```

- [ ] **Step 3: `firestoreProvider`**

Dans `lib/core/config/firestore_provider.dart`, ajouter la fonction pure et l'utiliser :

```dart
/// Choix de la base (ADR 0003 + build Test Lab). L'émulateur est prioritaire ;
/// sinon `staging` pour le web de staging (`APP_ENV=dev`) ou pour le build de
/// test mobile (`MOBILE_STAGING`, ignoré en release) ; sinon `(default)`.
bool shouldUseStagingDatabase({
  required bool isWeb,
  required bool isDev,
  required bool useEmulator,
  required bool useMobileStaging,
}) {
  if (useEmulator) return false;
  return (isWeb && isDev) || useMobileStaging;
}

final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  final useStaging = shouldUseStagingDatabase(
    isWeb: kIsWeb,
    isDev: Env.isDev,
    useEmulator: Env.useFirebaseEmulator,
    useMobileStaging: Env.useMobileStaging,
  );
  if (!useStaging) {
    return FirebaseFirestore.instance;
  }
  return FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: kStagingDatabaseId,
  );
});
```

Mettre à jour le long commentaire du provider : le mobile vise `staging` uniquement dans le build de test (`MOBILE_STAGING`, jamais en release) ; supprimer la phrase « il n'existe pas d'isolation dev pour le mobile ».

- [ ] **Step 4: Auto-login + ruban dans `main.dart`**

Après le bloc `if (Env.useFirebaseEmulator) { … }` et avant le bloc Crashlytics :

```dart
  // Build Test Lab (MOBILE_STAGING, jamais en release) : connexion
  // automatique du compte de test staging-only, Robo ne sachant pas remplir
  // le formulaire de connexion Flutter. Un échec n'empêche pas le démarrage.
  final testCredentials = Env.testAutoLoginCredentials;
  if (testCredentials != null && FirebaseAuth.instance.currentUser == null) {
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: testCredentials.email,
        password: testCredentials.password,
      );
    } catch (e, st) {
      Logger('main').warning('Auto-login Test Lab échoué', e, st);
    }
  }
```

Remplacer le `builder` du `MaterialApp.router` par une version qui gère les deux rubans :

```dart
      // Rubans debug : « EMULATOR » (données locales) ou « STAGING » (build de
      // test Test Lab). No-op en build normal / release.
      builder: Env.useFirebaseEmulator || Env.useMobileStaging
          ? (context, child) => Banner(
              message: Env.useFirebaseEmulator ? 'EMULATOR' : 'STAGING',
              location: BannerLocation.topStart,
              color: Env.useFirebaseEmulator
                  ? Colors.deepOrange
                  : Colors.purple,
              child: child ?? const SizedBox.shrink(),
            )
          : null,
```

- [ ] **Step 5: Fichiers de réglages**

Créer `dart-defines.testlab.example.json` :

```json
{
  "APP_ENV": "dev",
  "MOBILE_STAGING": "true",
  "TEST_AUTO_LOGIN_EMAIL": "",
  "TEST_AUTO_LOGIN_PASSWORD": ""
}
```

Dans `.gitignore`, à côté des autres `dart-defines.*` : ajouter `dart-defines.testlab.json` et, avec les exceptions existantes, `!dart-defines.testlab.example.json`. Vérifier : `git check-ignore -v dart-defines.testlab.json` doit matcher, et `git check-ignore dart-defines.testlab.example.json` ne rien renvoyer.

- [ ] **Step 6: Vérification + commit**

Run: `flutter test test/unit/firestore_provider_routing_test.dart` (PASS), `flutter analyze` (clean), `flutter test` (vert), puis `flutter build apk --debug --dart-define-from-file=dart-defines.testlab.example.json` (Expected : build OK — vérifie que le build Android compile avec le réglage).

```bash
git add lib/core/config/env.dart lib/core/config/firestore_provider.dart lib/main.dart dart-defines.testlab.example.json .gitignore test/unit/firestore_provider_routing_test.dart
git commit -m "feat(mobile): build de test MOBILE_STAGING (base staging, auto-login, ruban)"
```

---

### Task 3: Documentation + état projet

**Files:**
- Modify: `docs/MOBILE.md`
- Modify: `docs/ENVIRONMENTS.md`
- Modify: `docs/adr/0003-firestore-prod-staging-isolation.md`
- Modify: `docs/state/functions/README.md` (section routage `db_router`)
- Modify: `docs/state/CHANGELOG.md`

- [ ] **Step 1: `docs/MOBILE.md` — section « Test Lab (Robo) »**

Ajouter une section contenant, en prose et commandes :
1. Compte de test : créé une seule fois sur `https://app.staging.baillan.com` ; **ne jamais l'utiliser en prod** (le routage mobile cherche la prod d'abord).
2. `cp dart-defines.testlab.example.json dart-defines.testlab.json` puis renseigner `TEST_AUTO_LOGIN_EMAIL` / `TEST_AUTO_LOGIN_PASSWORD` (fichier gitignoré).
3. Build : `flutter build apk --debug --dart-define-from-file=dart-defines.testlab.json`
4. Lancement :
   `gcloud firebase test android run --type robo --app build/app/outputs/flutter-apk/app-debug.apk --device model=MediumPhone.arm,version=34 --device model=Pixel2.arm,version=30 --timeout 300s --project easy-rent-54cd4`
   (lister les modèles disponibles : `gcloud firebase test android models list`).
5. Résultats : console Firebase → Test Lab (plantages, captures, vidéo). Quota gratuit : 10 tests/jour sur appareils virtuels.
6. Prérequis : Functions déployées avec le routage mobile par compte.

- [ ] **Step 2: `docs/ENVIRONMENTS.md`**

- Corriger le domaine de l'app staging : `https://app.staging.baillan.com` (app Flutter) ; `stage.baillan.com` = vitrine (site marketing). Corriger chaque occurrence qui présente `stage.baillan.com` comme l'app.
- Ajouter un paragraphe « Build de test mobile (Test Lab) » : `MOBILE_STAGING` (ignoré en release) → base `staging` ; callables sans Origin routés par compte.

- [ ] **Step 3: ADR 0003 — amendement**

Ajouter en fin d'ADR une section « Amendement 2026-09-29 — routage mobile par compte » : `dbForRequest` asynchrone ; web par Origin inchangé ; appels sans Origin → `dbForLandlordUid` (prod d'abord) ; motivation (build Test Lab sur staging) ; coût (1 lecture par appel mobile) ; discipline (compte de test staging-only).

- [ ] **Step 4: `docs/state`**

- `docs/state/functions/README.md` : là où `dbForRequest` est décrit, signature async et règle web (Origin) / mobile (compte). Les autres shards qui citent `dbForRequest(request)` n'ont pas besoin d'être modifiés.
- `docs/state/CHANGELOG.md`, préfixer dans la période courante :

```markdown
### Build Android de test sur staging — Test Lab (2026-09-29)
- Functions : `dbForRequest` async — web routé par Origin (inchangé), appels mobiles (sans Origin) routés par la base du compte (`dbForLandlordUid`, prod d'abord). **Redéploiement de toutes les Functions requis.**
- App : réglage `MOBILE_STAGING` (ignoré en release) → base `staging`, auto-login d'un compte de test staging-only (`dart-defines.testlab.json`, gitignoré), ruban « STAGING ».
- Doc : `docs/MOBILE.md` (Test Lab / Robo), ADR 0003 amendée, domaine staging corrigé dans `ENVIRONMENTS.md`.
```

- [ ] **Step 5: Commit**

```bash
git add docs/MOBILE.md docs/ENVIRONMENTS.md docs/adr/0003-firestore-prod-staging-isolation.md docs/state/CHANGELOG.md docs/state/functions/README.md
git commit -m "docs: build de test Test Lab sur staging (MOBILE.md, ADR 0003, état)"
```
