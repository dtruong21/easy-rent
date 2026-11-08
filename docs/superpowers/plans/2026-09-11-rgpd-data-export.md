# FEAT-047 — Export des données RGPD — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Permettre au bailleur d'exporter toutes ses données en un JSON structuré unique (RGPD art. 15/20), via une callable et une tuile dans Profil.

**Architecture:** Une callable `exportAccountData` (Cloud Functions) parcourt en LECTURE les mêmes collections que `deleteAccount` (par `landlordId == uid` via `dbForRequest`), protégée par la garde d'auth récente extraite en helper partagé. Côté Flutter : un repository appelle la callable, un contrôleur sérialise le JSON et le remet à l'utilisateur via une méthode générique `deliverFile` ajoutée au service de partage existant (web = téléchargement, mobile = partage natif), déclenchée par une tuile Profil.

**Tech Stack:** Cloud Functions (TypeScript, firebase-functions v2, vitest), Flutter (Riverpod, cloud_functions, share_plus, dart:js_interop web).

## Global Constraints

- **Accès Firestore jamais en direct** : Functions via `dbForRequest(request)` (jamais `admin.firestore()`) ; client via providers/callable (jamais `FirebaseFirestore.instance`).
- **Isolation cross-user** : l'export ne renvoie QUE les documents `landlordId == uid` (+ singletons de cet uid). Testé explicitement.
- **Garde d'auth récente** (< 5 min) pour comptes non-anonymes ; anonymes exemptés (état confirmé via Admin SDK `providerData`).
- **i18n** FR + EN pour tout libellé client ; `@description` sur le gabarit EN (`app_en.arb`) — le test `arb_parity_test` l'impose.
- **Jetons de design uniquement** côté UI ; aucune couleur en dur.
- Toolchain : `export PATH="/opt/homebrew/bin:$PATH"` avant flutter/dart. Functions : `cd functions && npm test` (vitest), lint `npm run lint`.
- **Format** : avant chaque commit, `dart format .` (repo-wide) côté Flutter et `npm run lint` côté functions — le check CI `dart format --set-exit-if-changed .` porte sur TOUT le repo (cf. incidents #177/#178).
- Générés gitignored (Flutter) : après édition arb → `flutter gen-l10n`.
- Commits : chemins EXPLICITES (jamais `git add -A`), message finissant par `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

---

### Task 1: Extraire la garde d'auth récente en helper partagé

Extraire des ~30 lignes de garde d'auth de `delete_account.ts` un helper réutilisable, pour que l'export l'utilise sans dupliquer une logique de sécurité.

**Files:**
- Modify: `functions/src/utils/callable_helpers.ts`
- Modify: `functions/src/callable/delete_account.ts`
- Test: `functions/src/__tests__/delete_account.test.ts` (doit rester vert, inchangé)

**Interfaces:**
- Produces: `RECENT_AUTH_MAX_AGE_SECONDS: number` et
  `assertRecentAuthForNonAnonymousAccount(request: CallableRequest, uid: string): Promise<void>` — throw `HttpsError("failed-precondition","recent-login-required")` si compte non-anonyme au token trop vieux ; no-op si anonyme (confirmé Admin SDK) ; throw `HttpsError("internal", ...)` si `getUser` échoue autrement que `user-not-found`.

- [ ] **Step 1: Ajouter le helper**

Dans `functions/src/utils/callable_helpers.ts`, ajouter (avec les imports nécessaires : `import * as admin from "firebase-admin";`, `import {logger} from "firebase-functions/v2";`, et `HttpsError` depuis `firebase-functions/v2/https` — vérifier ceux déjà présents) :

```ts
/** Fraîcheur maximale de l'authentification pour un compte non-anonyme. */
export const RECENT_AUTH_MAX_AGE_SECONDS = 5 * 60;

/**
 * Rejette si un compte NON-anonyme présente un token d'auth trop vieux
 * (> RECENT_AUTH_MAX_AGE_SECONDS). Un compte anonyme (confirmé AUTORITATIVEMENT
 * via Admin SDK `providerData`, car le claim `sign_in_provider` reste
 * "anonymous" sur les tokens émis avant un upgrade par linking) est exempté.
 */
export async function assertRecentAuthForNonAnonymousAccount(
  request: CallableRequest,
  uid: string,
): Promise<void> {
  const token = request.auth?.token;
  let isAnonymous = token?.firebase?.sign_in_provider === "anonymous";
  if (isAnonymous) {
    try {
      const userRecord = await admin.auth().getUser(uid);
      isAnonymous = userRecord.providerData.length === 0;
    } catch (err) {
      const code =
        typeof err === "object" && err !== null && "code" in err ?
          (err as {code: unknown}).code :
          undefined;
      if (code !== "auth/user-not-found") {
        logger.error(`assertRecentAuth: getUser failed for uid=${uid}`, err);
        throw new HttpsError("internal", "account lookup failed — retry");
      }
    }
  }
  if (!isAnonymous) {
    const authTime =
      typeof token?.auth_time === "number" ? token.auth_time : 0;
    const ageSeconds = Date.now() / 1000 - authTime;
    if (ageSeconds > RECENT_AUTH_MAX_AGE_SECONDS) {
      throw new HttpsError("failed-precondition", "recent-login-required");
    }
  }
}
```

- [ ] **Step 2: Refactorer `delete_account.ts` pour utiliser le helper**

Dans `delete_account.ts` : importer `assertRecentAuthForNonAnonymousAccount` (et retirer la constante locale `RECENT_AUTH_MAX_AGE_SECONDS` en l'important du helper, ou la laisser si utilisée ailleurs — vérifier ; `RECEIPT_RETENTION_MS` reste). Remplacer tout le bloc inline (détermination `isAnonymous` via token + Admin SDK, puis check `auth_time` — actuellement ~lignes 86-116) par :

```ts
    await assertRecentAuthForNonAnonymousAccount(request, uid);

    const db = dbForRequest(request);
```

Conserver le reste (purge, singletons, storage, auth delete) à l'identique.

- [ ] **Step 3: Lancer les tests delete_account — verts, comportement inchangé**

Run: `cd functions && npm test -- delete_account`
Expected: PASS (stale non-anon → rejet ; anonyme → exempté ; frais → succès — inchangé).

- [ ] **Step 4: Lint**

Run: `cd functions && npm run lint`
Expected: pas d'erreur.

- [ ] **Step 5: Commit**

```bash
git add functions/src/utils/callable_helpers.ts functions/src/callable/delete_account.ts
git commit -m "refactor(functions): extrait assertRecentAuthForNonAnonymousAccount (helper partagé)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Callable `exportAccountData`

**Files:**
- Create: `functions/src/callable/export_account_data.ts`
- Modify: `functions/src/index.ts`
- Test: `functions/src/__tests__/export_account_data.test.ts`

**Interfaces:**
- Consumes: `requireAuthUid`, `assertRecentAuthForNonAnonymousAccount` (Task 1), `dbForRequest`.
- Produces: callable `exportAccountData` renvoyant l'objet JSON décrit ci-dessous.

- [ ] **Step 1: Écrire le test (cross-user + garde + sérialisation)**

Créer `functions/src/__tests__/export_account_data.test.ts` sur le modèle de `delete_account.test.ts` (mêmes helpers `FakeFirestore`/`FakeAuthAdmin`/`makeRequest`/`vi.mock("firebase-admin", …)`). Seed deux landlords A et B, puis :

```ts
import type {CallableRequest} from "firebase-functions/v2/https";
import {beforeEach, describe, expect, it, vi} from "vitest";
import {exportAccountData} from "../callable/export_account_data";
import {
  FakeAuthAdmin, FakeFirestore, FakeStorage, fakeAdminFirestoreHolder,
} from "./helpers/fake_firestore";

vi.mock("firebase-admin", async () => {
  const {makeFakeAdminModule} = await import("./helpers/fake_firestore");
  return makeFakeAdminModule();
});

let fakeDb: FakeFirestore;
let fakeAuth: FakeAuthAdmin;
const A = "landlord-a";
const B = "landlord-b";
const FRESH = () => Math.floor(Date.now() / 1000);
const STALE = () => Math.floor(Date.now() / 1000) - 3600;

function makeRequest(uid: string | null, {authTime = FRESH(), signInProvider = "password"} = {}): CallableRequest {
  return {
    data: {},
    auth: uid ? {uid, token: {auth_time: authTime, firebase: {sign_in_provider: signInProvider}} as never, rawToken: ""} : undefined,
    rawRequest: {} as never,
  } as CallableRequest;
}

beforeEach(() => {
  fakeDb = new FakeFirestore();
  fakeAuth = new FakeAuthAdmin();
  fakeAdminFirestoreHolder.db = fakeDb;
  fakeAdminFirestoreHolder.auth = fakeAuth;
  fakeAdminFirestoreHolder.storage = new FakeStorage();
  fakeDb.seed(`landlords/${A}`, {id: A, email: "a@x.fr"});
  fakeDb.seed(`properties/pa`, {landlordId: A, name: "Bien A", createdAt: fakeDb.timestamp(new Date("2026-01-01T00:00:00Z"))});
  fakeDb.seed(`properties/pb`, {landlordId: B, name: "Bien B"});
  fakeDb.seed(`payments/paya`, {landlordId: A, amountCents: 80000});
});

describe("exportAccountData", () => {
  it("renvoie les données du bailleur et EXCLUT celles d'un autre (cross-user)", async () => {
    const res = await exportAccountData.run(makeRequest(A)) as Record<string, any>;
    expect(res.account.id).toBe(A);
    expect(res.properties.map((p: any) => p.name)).toContain("Bien A");
    expect(res.properties.map((p: any) => p.name)).not.toContain("Bien B");
    expect(res.payments).toHaveLength(1);
    expect(res.schemaVersion).toBe(1);
    expect(typeof res.exportedAt).toBe("string");
  });

  it("sérialise les Timestamp en chaînes ISO", async () => {
    const res = await exportAccountData.run(makeRequest(A)) as Record<string, any>;
    const p = res.properties.find((p: any) => p.id === "pa");
    expect(p.createdAt).toBe("2026-01-01T00:00:00.000Z");
  });

  it("singletons absents → null, pas d'erreur", async () => {
    const res = await exportAccountData.run(makeRequest(B)) as Record<string, any>;
    expect(res.account).toBeNull();
    expect(res.paidPlanInterest).toBeNull();
  });

  it("compte non-anonyme au token trop vieux → recent-login-required", async () => {
    await expect(exportAccountData.run(makeRequest(A, {authTime: STALE()})))
      .rejects.toMatchObject({code: "failed-precondition", message: "recent-login-required"});
  });

  it("compte anonyme → exempté de la garde de fraîcheur", async () => {
    fakeAuth.seedUser(A, {providerData: []});
    const res = await exportAccountData.run(makeRequest(A, {authTime: STALE(), signInProvider: "anonymous"})) as Record<string, any>;
    expect(res.account.id).toBe(A);
  });
});
```

Adapter les noms exacts des helpers (`fakeDb.timestamp`, `fakeAuth.seedUser`, `exportAccountData.run`) à ceux réellement fournis par `./helpers/fake_firestore` et par le type `onCall` — inspecter `delete_account.test.ts` et le helper pour les signatures réelles avant de figer.

- [ ] **Step 2: Lancer — échec attendu**

Run: `cd functions && npm test -- export_account_data`
Expected: FAIL — `export_account_data.ts` inexistant.

- [ ] **Step 3: Implémenter la callable**

Créer `functions/src/callable/export_account_data.ts` :

```ts
/**
 * exportAccountData — export RGPD (art. 15 accès + art. 20 portabilité, FEAT-047).
 *
 * Parcourt en LECTURE toutes les collections du bailleur (`landlordId == uid`)
 * + les singletons, et renvoie un JSON structuré unique. Même garde d'auth
 * récente que `deleteAccount` : exporter toutes les PII mérite la protection
 * d'une action sensible. Accès Firestore via `dbForRequest` (ADR 0003).
 */
import {logger} from "firebase-functions/v2";
import {onCall} from "firebase-functions/v2/https";

import {
  assertRecentAuthForNonAnonymousAccount,
  requireAuthUid,
} from "../utils/callable_helpers";
import {dbForRequest} from "../utils/db_router";

/** clé de sortie → nom de collection Firestore. */
const EXPORTED_COLLECTIONS: Record<string, string> = {
  properties: "properties",
  tenants: "tenants",
  leases: "leases",
  payments: "payments",
  receipts: "receipts",
  documents: "documents",
  expenses: "expenses",
  investmentScenarios: "investment_scenarios",
  supportRequests: "support_requests",
};

function isTimestamp(v: unknown): v is {toDate: () => Date} {
  return (
    typeof v === "object" && v !== null &&
    typeof (v as {toDate?: unknown}).toDate === "function"
  );
}

/** Sérialise récursivement en convertissant les Timestamp en ISO 8601 (UTC). */
function serialize(value: unknown): unknown {
  if (isTimestamp(value)) return value.toDate().toISOString();
  if (Array.isArray(value)) return value.map(serialize);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>)
        .map(([k, v]) => [k, serialize(v)]),
    );
  }
  return value;
}

export const exportAccountData = onCall(
  {region: "europe-west1", timeoutSeconds: 120},
  async (request) => {
    const uid = requireAuthUid(request);
    await assertRecentAuthForNonAnonymousAccount(request, uid);

    const db = dbForRequest(request);
    const result: Record<string, unknown> = {
      exportedAt: new Date().toISOString(),
      schemaVersion: 1,
    };

    const landlordSnap = await db.doc(`landlords/${uid}`).get();
    result.account = landlordSnap.exists ?
      serialize({id: landlordSnap.id, ...landlordSnap.data()}) :
      null;
    const ppiSnap = await db.doc(`paid_plan_interest/${uid}`).get();
    result.paidPlanInterest = ppiSnap.exists ?
      serialize({id: ppiSnap.id, ...ppiSnap.data()}) :
      null;

    for (const [key, name] of Object.entries(EXPORTED_COLLECTIONS)) {
      const qs = await db.collection(name)
        .where("landlordId", "==", uid).get();
      result[key] = qs.docs.map((d) => serialize({id: d.id, ...d.data()}));
    }

    logger.info(`exportAccountData: uid=${uid}`);
    return result;
  },
);
```

- [ ] **Step 4: Enregistrer dans index.ts**

Dans `functions/src/index.ts`, à côté de `export {deleteAccount} …`, ajouter :
```ts
export {exportAccountData} from "./callable/export_account_data";
```

- [ ] **Step 5: Lancer — vert + lint**

Run: `cd functions && npm test -- export_account_data && npm run lint`
Expected: PASS, pas d'erreur lint.

- [ ] **Step 6: Commit**

```bash
git add functions/src/callable/export_account_data.ts functions/src/index.ts functions/src/__tests__/export_account_data.test.ts
git commit -m "feat(functions): callable exportAccountData (export RGPD, JSON toutes collections)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: `WebShareService.deliverFile` (livraison de fichier générique)

Ajouter au service de partage existant une méthode générique livrant des bytes en fichier nommé : web = téléchargement (blob), mobile = partage natif (share_plus), desktop/VM = no-op sûr.

**Files:**
- Modify: `lib/features/receipts/data/web_share_service_interface.dart`
- Modify: `lib/features/receipts/data/web_share_service.dart` (impl Web)
- Modify: `lib/features/receipts/data/web_share_service_io.dart` (impl VM/mobile)
- Modify: tout fake/mock de `WebShareService` dans les tests (ajouter la nouvelle méthode) — grep `implements WebShareService` sous `test/`.

**Interfaces:**
- Produces (sur `WebShareService`) :
  `Future<void> deliverFile({required String filename, required String mimeType, required List<int> bytes, String? shareTitle});`
  Web : déclenche un téléchargement du fichier. Mobile : ouvre le share sheet. Desktop/VM non-mobile : no-op.

- [ ] **Step 1: Déclarer la méthode dans l'interface**

Dans `web_share_service_interface.dart`, ajouter à `abstract interface class WebShareService` :

```dart
  /// Remet [bytes] à l'utilisateur sous forme de fichier nommé [filename].
  ///
  /// Web : déclenche un téléchargement (blob). Mobile (Android/iOS) : ouvre le
  /// share sheet natif. Autres plateformes VM (desktop, tests) : no-op sûr.
  /// Générique (tout [mimeType]) — utilisé par l'export RGPD (JSON).
  Future<void> deliverFile({
    required String filename,
    required String mimeType,
    required List<int> bytes,
    String? shareTitle,
  });
```

- [ ] **Step 2: Implémenter côté Web (téléchargement blob)**

Dans `web_share_service.dart` (impl Web, `dart:js_interop`), ajouter `deliverFile` qui crée un `Blob` à partir des bytes + `mimeType`, un `URL.createObjectURL`, un `<a download=filename>` cliqué programmatiquement, puis `revokeObjectURL`. Suivre le même style js_interop que `openPdfBytes` (qui manipule déjà des blobs). Le téléchargement ne dépend pas de `navigator.share` (fiable sur tous les navigateurs desktop).

- [ ] **Step 3: Implémenter côté VM/mobile (share_plus)**

Dans `web_share_service_io.dart`, ajouter `deliverFile` :

```dart
  @override
  Future<void> deliverFile({
    required String filename,
    required String mimeType,
    required List<int> bytes,
    String? shareTitle,
  }) async {
    if (!_isMobile) return; // desktop / tests : no-op sûr
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(Uint8List.fromList(bytes), mimeType: mimeType),
        ],
        fileNameOverrides: [filename],
        subject: shareTitle,
        sharePositionOrigin: const Rect.fromLTWH(0, 0, 1, 1),
      ),
    );
  }
```

- [ ] **Step 4: Mettre à jour les fakes de test**

`grep -rln "implements WebShareService" test/` ; dans chaque fake, ajouter une implémentation `deliverFile` (no-op ou enregistrant l'appel selon le test). Lancer la suite des reçus pour confirmer qu'elle reste verte :

Run: `flutter test test/unit/share_receipt_controller_test.dart`
Expected: PASS (aucune régression du partage de quittance).

- [ ] **Step 5: analyze + format + commit**

Run: `flutter analyze && dart format .`
```bash
git add lib/features/receipts/data/web_share_service_interface.dart lib/features/receipts/data/web_share_service.dart lib/features/receipts/data/web_share_service_io.dart test/
git commit -m "feat(share): WebShareService.deliverFile (fichier générique — web download / mobile share)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Repository + contrôleur d'export

**Files:**
- Create: `lib/features/account/data/account_export_repository.dart`
- Create: `lib/features/account/application/export_data_controller.dart`
- Test: `test/unit/export_data_controller_test.dart`

**Interfaces:**
- Consumes: `WebShareService.deliverFile` (Task 3) via `webShareServiceProvider` ; la callable `exportAccountData` (Task 2) par son nom.
- Produces:
  - `accountExportRepositoryProvider` → `AccountExportRepository` avec `Future<Map<String, dynamic>> exportAccountData()`.
  - `exportDataControllerProvider` (`AutoDisposeNotifierProvider<ExportDataController, ExportDataState>`) où `ExportDataState` = `{ status: idle|loading|success|error, errorKind: none|recentLoginRequired|generic }` (enum simple, pas freezed obligatoire) et méthode `Future<void> export()`.

- [ ] **Step 1: Écrire le test du contrôleur**

Créer `test/unit/export_data_controller_test.dart` : fake repository renvoyant une Map, fake `WebShareService` enregistrant l'appel `deliverFile`. Vérifier :

```dart
// - export() succès : status passe loading → success ; deliverFile appelé
//   avec filename commençant par 'baillan-export-' et se terminant par '.json',
//   mimeType 'application/json', et des bytes qui décodent en la Map exportée.
// - export() erreur générique : repo throw → status error, errorKind generic.
// - export() recent-login-required : repo throw FirebaseFunctionsException(
//   code 'failed-precondition', message 'recent-login-required') → status error,
//   errorKind recentLoginRequired.
```

(Écrire les 3 `test(...)` complets avec un `ProviderScope` overridant `accountExportRepositoryProvider` et `webShareServiceProvider` par les fakes ; asserter `container.read(exportDataControllerProvider)` après `await ...export()`.)

- [ ] **Step 2: Lancer — échec attendu**

Run: `flutter test test/unit/export_data_controller_test.dart`
Expected: FAIL — fichiers inexistants.

- [ ] **Step 3: Implémenter le repository**

`account_export_repository.dart` : classe appelant la callable via `FirebaseFunctions.instanceFor(region: 'europe-west1').httpsCallable('exportAccountData', options: HttpsCallableOptions(timeout: const Duration(seconds: 120)))`, `.call()`, et retournant `Map<String, dynamic>.from(res.data as Map)`. Exposer `accountExportRepositoryProvider`. Suivre le style de `receipts_repository.dart` (injection de `FirebaseFunctions`, provider en bas de fichier).

- [ ] **Step 4: Implémenter le contrôleur**

`export_data_controller.dart` : `ExportDataState` (enum status + enum errorKind), `ExportDataController extends AutoDisposeNotifier<ExportDataState>` avec `build()` → idle et `Future<void> export()` :
1. state = loading.
2. `final data = await ref.read(accountExportRepositoryProvider).exportAccountData();`
3. `final bytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(data));`
4. `final filename = 'baillan-export-${_todayIso()}.json';` (`_todayIso` = `DateTime.now().toIso8601String().split('T').first`).
5. `await ref.read(webShareServiceProvider).deliverFile(filename: filename, mimeType: 'application/json', bytes: bytes, shareTitle: '<export>');`
6. state = success.
Catch `FirebaseFunctionsException` avec `code == 'failed-precondition' && message == 'recent-login-required'` → errorKind recentLoginRequired ; tout autre → generic ; state = error dans les deux cas.

- [ ] **Step 5: Lancer — vert + analyze + format**

Run: `flutter test test/unit/export_data_controller_test.dart && flutter analyze && dart format .`
Expected: PASS, No issues found!

- [ ] **Step 6: Commit**

```bash
git add lib/features/account/data/account_export_repository.dart lib/features/account/application/export_data_controller.dart test/unit/export_data_controller_test.dart
git commit -m "feat(account): repository + contrôleur d'export RGPD (callable → JSON → deliverFile)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Tuile « Exporter mes données » dans Profil

**Files:**
- Create: `lib/features/account/presentation/widgets/export_data_tile.dart`
- Modify: `lib/features/profile/presentation/profile_page.dart` (insérer la tuile dans la section compte, près de `tile_delete_account`)
- Modify: `lib/l10n/app_fr.arb`, `lib/l10n/app_en.arb`
- Test: `test/widget/export_data_tile_test.dart`

**Interfaces:**
- Consumes: `exportDataControllerProvider` (Task 4).
- Produces: `ExportDataTile` (`ConsumerWidget`), clé `Key('tile_export_data')`.

- [ ] **Step 1: Écrire le test widget**

Créer `test/widget/export_data_tile_test.dart` : monter `ExportDataTile` dans un `ProviderScope` overridant `exportDataControllerProvider` (ou le repo + share fakes). Vérifier :

```dart
// - la tuile Key('tile_export_data') est présente avec le libellé d'export ;
// - tap → appelle export() (repo fake enregistre l'appel) ;
// - pendant loading, un indicateur de progression est visible ;
// - après succès, un SnackBar de succès s'affiche ;
// - après erreur recentLoginRequired, le message 'reconnectez-vous' s'affiche.
```

(Écrire les `testWidgets` complets avec `theme: AppTheme.light`, delegates l10n, locale fr.)

- [ ] **Step 2: Lancer — échec attendu**

Run: `flutter test test/widget/export_data_tile_test.dart`
Expected: FAIL — `export_data_tile.dart` inexistant.

- [ ] **Step 3: Ajouter les clés i18n (FR + EN) + gen-l10n**

Dans `app_fr.arb` :
```json
  "profileExportDataTile": "Exporter mes données",
  "profileExportDataSubtitle": "Recevez une copie de vos données au format JSON",
  "profileExportDataSuccess": "Export prêt",
  "profileExportDataError": "L'export a échoué. Réessayez.",
  "profileExportDataRecentLogin": "Reconnectez-vous, puis réessayez l'export.",
```
Dans `app_en.arb` (avec `@` description pour chaque) :
```json
  "profileExportDataTile": "Export my data",
  "@profileExportDataTile": { "description": "Profile tile that triggers a RGPD data export (JSON)." },
  "profileExportDataSubtitle": "Get a copy of your data as JSON",
  "@profileExportDataSubtitle": { "description": "Subtitle under the export-my-data profile tile." },
  "profileExportDataSuccess": "Export ready",
  "@profileExportDataSuccess": { "description": "Snackbar shown after the data export succeeds." },
  "profileExportDataError": "Export failed. Please try again.",
  "@profileExportDataError": { "description": "Snackbar shown when the data export fails." },
  "profileExportDataRecentLogin": "Please sign in again, then retry the export.",
  "@profileExportDataRecentLogin": { "description": "Message shown when the export requires a recent login." },
```
Run: `flutter gen-l10n`.

- [ ] **Step 4: Implémenter la tuile**

`export_data_tile.dart` : `ExportDataTile extends ConsumerWidget`. `ref.listen(exportDataControllerProvider, ...)` pour afficher un `SnackBar` succès / erreur (message selon `errorKind`). La tuile : `ListTile(key: const Key('tile_export_data'), leading: Icon(Icons.download_outlined), title: Text(l10n.profileExportDataTile), subtitle: Text(l10n.profileExportDataSubtitle), trailing: état loading ? petit CircularProgressIndicator : null, onTap: état loading ? null : () => ref.read(exportDataControllerProvider.notifier).export())`. Jetons de design uniquement.

- [ ] **Step 5: Insérer dans `profile_page.dart`**

Dans la `Column` de la section compte de `profile_page.dart`, insérer `const ExportDataTile()` juste avant la tuile `Key('tile_delete_account')` (l'export avant la suppression, ordre logique). Ajouter l'import.

- [ ] **Step 6: Lancer — vert + analyze + format**

Run: `flutter test test/widget/export_data_tile_test.dart test/widget/... (profile page si test existant) && flutter analyze && dart format .`
Expected: PASS, No issues found!

- [ ] **Step 7: Commit**

```bash
git add lib/features/account/presentation/widgets/export_data_tile.dart lib/features/profile/presentation/profile_page.dart lib/l10n/app_fr.arb lib/l10n/app_en.arb test/widget/export_data_tile_test.dart
git commit -m "feat(profile): tuile « Exporter mes données » (export RGPD)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Vérification finale (après les 5 tâches)

- Functions : `cd functions && npm test && npm run lint` → verts.
- Flutter : `flutter analyze` clean ; `dart format --output=none --set-exit-if-changed .` → exit 0 (repo-wide) ; `flutter test` → suite verte.
- `docs/state/` : nouvelle callable → mettre à jour `docs/state/functions/account.md` (ou le shard functions adéquat) ; entrée `docs/state/CHANGELOG.md` à la finition de branche (référence PR). `docs/LEGAL.md:28` (`GET /export`) : la promesse est désormais tenue (reformuler « via l'app » si besoin — hors périmètre strict).
- Manuel (staging, optionnel) : Profil → « Exporter mes données » → un `baillan-export-AAAA-MM-JJ.json` est téléchargé (web) / partagé (mobile) et contient les collections du bailleur.
