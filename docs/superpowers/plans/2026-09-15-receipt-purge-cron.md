# FEAT-046 — Purge différée des quittances (cron RGPD) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Livrer une Cloud Function planifiée quotidienne qui hard-delete les quittances (`receipts`) dont l'échéance de rétention (`retentionUntil`) est passée, honorant la limitation de conservation RGPD (art. 5.1.e).

**Architecture:** Une seule scheduled function `purgeExpiredReceipts` (patron `cleanupExpiredAnon`), sur la base `(default)` via `admin.firestore()` direct (exception crons à ADR 0003). Requête d'inégalité mono-champ `retentionUntil <= now`, hard-delete paginé. Prérequis technique : le harness de test `FakeQuery` ne supporte aujourd'hui que `==` — il faut d'abord lui ajouter les opérateurs de comparaison.

**Tech Stack:** Cloud Functions v2 (`onSchedule`), Firestore Admin SDK, vitest + `FakeFirestore`.

## Global Constraints

- **Base `(default)` uniquement** : le cron utilise `admin.firestore()` direct (PAS `dbForRequest` — les crons/triggers sont l'exception documentée à ADR 0003, cf. CLAUDE.md). N'agit donc que sur la prod ; staging non purgé (assumé, cohérent avec les crons existants).
- **Patron identique à `functions/src/scheduled/cleanup_expired_anon.ts`** : `onSchedule({schedule, timeZone, region})`, `admin.firestore()`, batch borné, logs `logger.info`.
- **Cadence** : `schedule: "0 3 * * *"`, `timeZone: "Europe/Paris"`, `region: "europe-west1"`.
- **Taille de page** : `PAGE_SIZE = 400` (aligné sur `PURGE_PAGE_SIZE` de `delete_account.ts`).
- **Sécurité de purge** : seules les quittances d'un compte supprimé portent `retentionUntil` (posé uniquement par `stampRetainedReceipts`) ; une quittance sans le champ ne doit JAMAIS être supprimée.
- **Aucun nettoyage Storage** : les quittances n'ont pas d'objet Storage côté serveur (`pdfPath` jamais écrit par une Function).
- Lint (`eslint`), build (`tsc`) et suite vitest complète doivent rester verts. Format Dart repo-wide non concerné (aucun fichier Dart).

---

### Task 1: Étendre `FakeQuery` aux opérateurs de comparaison (`<=`, `<`, `>=`, `>`)

**Contexte projet :** le harness `FakeFirestore` partagé (`functions/src/__tests__/helpers/fake_firestore.ts`) ne supporte que `where(field, "==", value)` et lève sur tout autre opérateur. Le cron interroge `where("retentionUntil", "<=", now)` — il faut d'abord étendre le fake, sans casser les ~492 tests existants qui n'utilisent que `==`.

**Files:**
- Modify: `functions/src/__tests__/helpers/fake_firestore.ts` (classe `FakeQuery`, lignes ~157-219)

**Interfaces:**
- Consumes: rien (helper de test autonome).
- Produces: `FakeQuery.where(field, op, value)` accepte désormais `op ∈ {"==","<=","<",">=",">"}` ; comparaison numérique pour `number`, `Date` (via `getTime()`) et objets `Timestamp` réels (via `toMillis()`) ; un document dont le champ est **absent/null ne matche jamais** un opérateur de comparaison (sémantique Firestore). `==` reste une égalité stricte inchangée.

- [ ] **Step 1: Écrire le test d'extension du fake (échoue)**

Créer `functions/src/__tests__/helpers/fake_query_operators.test.ts` :

```ts
import {beforeEach, describe, expect, it} from "vitest";

import {FakeFirestore} from "./fake_firestore";

describe("FakeQuery — opérateurs de comparaison", () => {
  let db: FakeFirestore;

  beforeEach(() => {
    db = new FakeFirestore();
    db.seed("receipts/r-past", {id: "r-past", retentionUntil: new Date(1_000)});
    db.seed("receipts/r-future", {
      id: "r-future",
      retentionUntil: new Date(9_999_999_999_999),
    });
    db.seed("receipts/r-none", {id: "r-none"}); // pas de retentionUntil
  });

  it("<= retourne les docs dont le champ est <= la valeur (champ absent exclu)", async () => {
    const now = new Date(5_000);
    const snap = await db
      .collection("receipts")
      .where("retentionUntil", "<=", now)
      .get();
    const ids = snap.docs.map((d) => d.id).sort();
    expect(ids).toEqual(["r-past"]);
  });

  it("== reste une égalité stricte inchangée", async () => {
    const snap = await db
      .collection("receipts")
      .where("id", "==", "r-future")
      .get();
    expect(snap.docs.map((d) => d.id)).toEqual(["r-future"]);
  });

  it("lève sur un opérateur non supporté", async () => {
    expect(() =>
      db.collection("receipts").where("id", "array-contains", "x"),
    ).toThrow();
  });
});
```

- [ ] **Step 2: Lancer le test — échoue**

Run: `cd functions && npx vitest run src/__tests__/helpers/fake_query_operators.test.ts`
Expected: FAIL — `FakeQuery: unsupported operator <=` levé par `where`.

- [ ] **Step 3: Étendre `FakeQuery`**

Dans `functions/src/__tests__/helpers/fake_firestore.ts` :

a. Changer le type des filtres (constructeur `FakeQuery`, ligne ~161) de `ReadonlyArray<[string, unknown]>` vers `ReadonlyArray<[string, string, unknown]>` (field, op, value).

b. Remplacer `where` (lignes ~165-175) par :

```ts
  where(field: string, op: string, value: unknown): FakeQuery {
    if (!["==", "<=", "<", ">=", ">"].includes(op)) {
      throw new Error(`FakeQuery: unsupported operator ${op}`);
    }
    return new FakeQuery(
      this.collectionName,
      this.queryStore,
      [...this.filters, [field, op, value]],
      this.limitCount,
    );
  }
```

c. Dans `get` (ligne ~207), remplacer le prédicat `this.filters.every(([field, value]) => data[field] === value)` par `this.filters.every((f) => matchesFilter(data, f))`.

d. Ajouter, au niveau module (au-dessus de `class FakeQuery`), les deux helpers :

```ts
/** Convertit une valeur comparable (number, Date, Timestamp) en millis, sinon null. */
function toComparable(v: unknown): number | null {
  if (typeof v === "number") return v;
  if (v instanceof Date) return v.getTime();
  if (v && typeof (v as {toMillis?: () => number}).toMillis === "function") {
    return (v as {toMillis: () => number}).toMillis();
  }
  return null;
}

/** Applique un filtre [field, op, value] à un document. */
function matchesFilter(
  data: DocData,
  [field, op, value]: [string, string, unknown],
): boolean {
  if (op === "==") return data[field] === value;
  const actual = data[field];
  // Sémantique Firestore : un champ absent ne matche jamais une comparaison.
  if (actual === undefined || actual === null) return false;
  const a = toComparable(actual);
  const b = toComparable(value);
  if (a === null || b === null) return false;
  switch (op) {
    case "<=":
      return a <= b;
    case "<":
      return a < b;
    case ">=":
      return a >= b;
    case ">":
      return a > b;
    default:
      return false;
  }
}
```

> Note : `DocData` est déjà le type des valeurs du store dans ce fichier. Si `matchesFilter`/`toComparable` doivent être placés après leur usage, aucune importance — ce sont des `function` hoisted.

- [ ] **Step 4: Lancer le test d'extension — passe**

Run: `cd functions && npx vitest run src/__tests__/helpers/fake_query_operators.test.ts`
Expected: PASS (3 tests).

- [ ] **Step 5: Non-régression — suite complète verte**

Run: `cd functions && npm test`
Expected: PASS — tous les fichiers (les ~492 tests existants n'utilisent que `==`, comportement inchangé).

- [ ] **Step 6: Commit**

```bash
git add functions/src/__tests__/helpers/fake_firestore.ts functions/src/__tests__/helpers/fake_query_operators.test.ts
git commit -m "test(functions): FakeQuery supporte les opérateurs de comparaison (<=, <, >=, >)"
```

---

### Task 2: Cloud Function `purgeExpiredReceipts` (TDD)

**Contexte projet :** livrable central. Cron quotidien qui hard-delete les `receipts` expirées. Suit le patron de `functions/src/scheduled/cleanup_expired_anon.ts`.

**Files:**
- Create: `functions/src/scheduled/purge_expired_receipts.ts`
- Create: `functions/src/__tests__/purge_expired_receipts.test.ts`
- Modify: `functions/src/index.ts` (export du scheduled)

**Interfaces:**
- Consumes: `FakeQuery` étendu (Task 1) pour `where("retentionUntil", "<=", now)` ; `admin.firestore.Timestamp.now()` (fake = `new Date()`).
- Produces: `export const purgeExpiredReceipts` (scheduled function v2, point d'entrée) **et** `export async function purgeExpiredReceiptsImpl(db, now): Promise<number>` (logique pure, retourne le nombre purgé). Le wrapper `onSchedule` appelle `purgeExpiredReceiptsImpl`. **Convention repo** : les tests ciblent la fonction pure, pas le wrapper — identique à `reconcile_entitlements.test.ts` qui teste `reconcileExpiredEntitlements(db, …)` et non `.run()`.

- [ ] **Step 1: Écrire les tests (échouent)**

Créer `functions/src/__tests__/purge_expired_receipts.test.ts` :

```ts
import {beforeEach, describe, expect, it, vi} from "vitest";

import {FakeFirestore, fakeAdminFirestoreHolder} from "./helpers/fake_firestore";

vi.mock("firebase-admin", async () => {
  const {makeFakeAdminModule} = await import("./helpers/fake_firestore");
  return makeFakeAdminModule();
});

// On teste la fonction PURE (convention repo, cf. reconcile_entitlements.test.ts
// qui teste reconcileExpiredEntitlements(db, …), pas le wrapper onSchedule).
import {purgeExpiredReceiptsImpl} from "../scheduled/purge_expired_receipts";

let fakeDb: FakeFirestore;

/** Invoque la logique pure avec le fake db et « maintenant ». */
function runCron(): Promise<number> {
  return purgeExpiredReceiptsImpl(
    fakeDb as never,
    new Date() as never,
  );
}

const PAST = new Date(Date.now() - 1000);
const FUTURE = new Date(Date.now() + 100 * 365 * 24 * 60 * 60 * 1000);

function seedReceipt(id: string, retentionUntil?: Date) {
  fakeDb.seed(`receipts/${id}`, {
    id,
    landlordId: "l1",
    ...(retentionUntil ? {retentionUntil} : {}),
  });
}

beforeEach(() => {
  fakeDb = new FakeFirestore();
  fakeAdminFirestoreHolder.db = fakeDb;
});

describe("purgeExpiredReceipts", () => {
  it("supprime les quittances dont retentionUntil est passé", async () => {
    seedReceipt("r1", PAST);
    seedReceipt("r2", PAST);

    await runCron();

    expect(fakeDb.peek("receipts/r1")).toBeUndefined();
    expect(fakeDb.peek("receipts/r2")).toBeUndefined();
  });

  it("épargne les quittances dont retentionUntil est futur", async () => {
    seedReceipt("r-future", FUTURE);

    await runCron();

    expect(fakeDb.peek("receipts/r-future")).toBeDefined();
  });

  it("épargne les quittances sans retentionUntil (compte actif)", async () => {
    seedReceipt("r-active"); // pas de champ retentionUntil

    await runCron();

    expect(fakeDb.peek("receipts/r-active")).toBeDefined();
  });

  it("purge au-delà d'une page (pagination multi-batch)", async () => {
    for (let i = 0; i < 405; i++) seedReceipt(`r${i}`, PAST);

    await runCron();

    expect(fakeDb.peek("receipts/r0")).toBeUndefined();
    expect(fakeDb.peek("receipts/r404")).toBeUndefined();
  });

  it("run sans donnée ne lève pas", async () => {
    await expect(runCron()).resolves.not.toThrow();
  });
});
```

> `FakeFirestore` expose `peek(path)` (utilisé par `documents.test.ts`) — vérifié. Le test cible `purgeExpiredReceiptsImpl` directement (fonction pure), comme `reconcile_entitlements.test.ts` cible `reconcileExpiredEntitlements` — pas le wrapper `onSchedule`.

- [ ] **Step 2: Lancer les tests — échouent**

Run: `cd functions && npx vitest run src/__tests__/purge_expired_receipts.test.ts`
Expected: FAIL — module `../scheduled/purge_expired_receipts` introuvable.

- [ ] **Step 3: Implémenter le cron**

Créer `functions/src/scheduled/purge_expired_receipts.ts` :

```ts
/**
 * purgeExpiredReceipts — cron quotidien qui purge les quittances archivées
 * dont l'échéance de rétention est passée (RGPD art. 5.1.e — limitation de la
 * conservation).
 *
 * À la suppression d'un compte (FEAT-045), `deleteAccount` CONSERVE les
 * quittances 5 ans et pose sur chacune `retentionUntil` (= suppression + 5 ans)
 * via `stampRetainedReceipts`. Ce cron exécute la purge promise à l'échéance.
 *
 * Base `(default)` via `admin.firestore()` direct : les crons sont l'exception
 * documentée à l'isolation ADR 0003 (pas de `request` porteur d'Origin, donc
 * pas de `dbForRequest`). Même patron que `cleanupExpiredAnon`.
 *
 * Sécurité : seules les quittances d'un compte supprimé portent
 * `retentionUntil`. Une quittance de compte actif n'a pas le champ et n'est
 * jamais retournée par `where("retentionUntil", "<=", now)`.
 *
 * Idempotent : supprimer un doc déjà parti est un no-op ; un run borné par
 * MAX_DELETES_PER_RUN laisse le reste au lendemain (horizon 5 ans, sans enjeu).
 */

import * as admin from "firebase-admin";
import {logger} from "firebase-functions/v2";
import {onSchedule} from "firebase-functions/v2/scheduler";

type Firestore = admin.firestore.Firestore;
type Timestamp = admin.firestore.Timestamp;

const PAGE_SIZE = 400;
const MAX_DELETES_PER_RUN = 2000; // 5 pages — large devant tout volume réaliste

/**
 * Logique pure, testable avec le FakeFirestore (convention repo — cf.
 * reconcileExpiredEntitlements). Retourne le nombre de quittances purgées.
 */
export async function purgeExpiredReceiptsImpl(
  db: Firestore,
  now: Timestamp,
): Promise<number> {
  let purged = 0;

  while (purged < MAX_DELETES_PER_RUN) {
    const snap = await db
      .collection("receipts")
      .where("retentionUntil", "<=", now)
      .limit(PAGE_SIZE)
      .get();

    if (snap.empty) break;

    const batch = db.batch();
    for (const doc of snap.docs) batch.delete(doc.ref);
    await batch.commit();
    purged += snap.size;

    if (snap.size < PAGE_SIZE) break; // dernière page
  }

  if (purged === 0) {
    logger.info("purgeExpiredReceipts: no expired receipts");
  } else {
    logger.info(`purgeExpiredReceipts: purged ${purged} expired receipts`);
  }
  return purged;
}

export const purgeExpiredReceipts = onSchedule(
  {schedule: "0 3 * * *", timeZone: "Europe/Paris", region: "europe-west1"},
  async () => {
    await purgeExpiredReceiptsImpl(
      admin.firestore(),
      admin.firestore.Timestamp.now(),
    );
  },
);
```

- [ ] **Step 4: Exporter dans `index.ts`**

Ajouter, à côté des autres exports scheduled (`cleanupExpiredAnon`, `reconcileEntitlements`) dans `functions/src/index.ts` :

```ts
export {purgeExpiredReceipts} from "./scheduled/purge_expired_receipts";
```

- [ ] **Step 5: Lancer les tests du cron — passent**

Run: `cd functions && npx vitest run src/__tests__/purge_expired_receipts.test.ts`
Expected: PASS (5 tests).

- [ ] **Step 6: Lint + build + suite complète**

Run: `cd functions && npm run lint && npm run build && npm test`
Expected: lint clean, `tsc` clean, tous les tests verts.

- [ ] **Step 7: Commit**

```bash
git add functions/src/scheduled/purge_expired_receipts.ts functions/src/__tests__/purge_expired_receipts.test.ts functions/src/index.ts
git commit -m "feat(FEAT-046): cron purgeExpiredReceipts (purge RGPD des quittances expirées)"
```

---

### Task 3: Documentation d'état (DoD)

**Contexte projet :** mettre à jour les shards d'état pour le domaine touché (payments-receipts) — sinon les sessions suivantes travaillent sur un état périmé (règle d'or n°7 CLAUDE.md).

**Files:**
- Modify: `docs/state/functions/payments-receipts.md` (ajouter la scheduled)
- Modify: `docs/state/FEATURES.md` (FEAT-046 → done)
- Modify: `docs/state/CHANGELOG.md` (entrée FEAT-046)
- Modify: `docs/state/INDEX.md` (décompte scheduled 2 → 3)

**Interfaces:** aucune (documentation).

- [ ] **Step 1: Shard functions payments-receipts**

Ajouter une section décrivant `purgeExpiredReceipts` : cron quotidien 03:00 Europe/Paris, base `(default)`, hard-delete `receipts where retentionUntil <= now` (posé par `stampRetainedReceipts`/FEAT-045), pagination 400, idempotent, aucun Storage. Fichier `functions/src/scheduled/purge_expired_receipts.ts`. ✅ Testé : `functions/src/__tests__/purge_expired_receipts.test.ts`.

- [ ] **Step 2: FEATURES.md**

Passer la ligne FEAT-046 à `✅ done` (réf : ce plan / la PR).

- [ ] **Step 3: CHANGELOG.md**

Ajouter une entrée `### FEAT-046 — Purge différée des quittances (cron RGPD)` en tête de la période courante : ce que fait le cron, base `(default)`, déploiement manuel functions requis.

- [ ] **Step 4: INDEX.md**

Mettre à jour le décompte des scheduled dans la section Stack (« 2 scheduled » → « 3 scheduled »).

- [ ] **Step 5: Commit**

```bash
git add docs/state/functions/payments-receipts.md docs/state/FEATURES.md docs/state/CHANGELOG.md docs/state/INDEX.md
git commit -m "docs(state): FEAT-046 purgeExpiredReceipts (shard + FEATURES + CHANGELOG + INDEX)"
```

---

## Self-Review

- **Spec coverage** : cron quotidien (Task 2), base `(default)` (Global Constraints + impl), `retentionUntil <= now` + hard-delete paginé (Task 2), pas de Storage (constraint + impl sans Storage), tests des 5 cas du spec (Task 2 Step 1), extension fake requise par le `<=` (Task 1), DoD docs (Task 3). ✅
- **Placeholder scan** : aucun TODO/à-compléter ; tout le code est fourni.
- **Type consistency** : `purgeExpiredReceipts` nommé identiquement dans l'impl, l'export index.ts, les tests et les docs. `PAGE_SIZE`/`MAX_DELETES_PER_RUN` définis une fois. `matchesFilter`/`toComparable` cohérents avec le type de filtre `[string, string, unknown]`.
- **Invocation en test** : résolu — Task 2 teste la fonction pure `purgeExpiredReceiptsImpl(db, now)` (convention repo confirmée sur `reconcile_entitlements.test.ts`), pas le wrapper `onSchedule`. Aucun risque de harness.
