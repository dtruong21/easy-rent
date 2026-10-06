# FEAT-044e — Lot 1 : liste blanche sandbox (serveur) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Autoriser une liste d'uids prod (compte de démo App Review / Play, testeurs) à recevoir Pro via un achat **SANDBOX**, au webhook RevenueCat et au cron de réconciliation, sans rien ouvrir aux autres comptes.

**Architecture:** Un document Firestore prod `_ops/sandboxAllowlist` (`uids: string[]`) lu par un petit module `utils/sandbox_allowlist.ts`. Le webhook garde sa règle (SANDBOX → `staging`, PRODUCTION → `(default)`) et ajoute une exception : SANDBOX d'un uid listé → `(default)`. Le cron traite un entitlement sandbox d'un uid listé comme un vrai droit. Toute lecture en échec retombe sur le comportement actuel (fail-closed) avec `logger.error`. Une règle Firestore refuse explicitement tout accès client à `_ops`.

**Tech Stack:** Cloud Functions v2 (TypeScript, Node 22), firebase-admin, Vitest + FakeFirestore (`functions/src/__tests__/helpers/fake_firestore.ts`), règles Firestore testées par `@firebase/rules-unit-testing` (`npm run test:rules`).

**Spec :** [`docs/superpowers/specs/2026-10-05-iap-revenuecat-mobile-design.md`](../specs/2026-10-05-iap-revenuecat-mobile-design.md) §2. Lots 2 et 3 (app) : plans séparés.

## Global Constraints

- Document : `_ops/sandboxAllowlist` dans la base **prod `(default)`** uniquement ; champ `uids: string[]`.
- Webhook : SANDBOX + uid listé → base `(default)` UNIQUEMENT ; SANDBOX non listé → `staging` (inchangé) ; PRODUCTION → `(default)` (inchangé) ; autre/absent → ignoré (inchangé).
- La liste n'est lue **que** pour les events SANDBOX (aucune lecture pour PRODUCTION).
- Lecture de la liste en échec → comportement par défaut (webhook : `staging` ; cron : aucun uid listé) + `logger.error`. Jamais de crash, jamais de déblocage prod.
- Cron : liste lue **une fois par passage** ; uid listé → entitlement sandbox traité comme un vrai droit ; non listé → `sandboxShadowed` (inchangé, #209).
- Règle : `match /_ops/{docId} { allow read, write: if false; }` (explicite).
- `admin.firestore()` / `getFirestore()` interdits hors crons/triggers (`scripts/check-db-isolation.sh`) : le webhook passe par `firestoreForEnv(false)`.
- Ne jamais renommer l'entitlement RevenueCat « Bailan Pro » (typo porteuse).
- Lint Functions : `max-len` 100, guillemets doubles, `require-await`. Chaque tâche lance `npm run lint` + `npm run build` + Vitest.
- Commentaires et messages en français, comme le code environnant.

---

### Task 1: Module `sandbox_allowlist`

**Files:**
- Create: `functions/src/utils/sandbox_allowlist.ts`
- Test: `functions/src/__tests__/sandbox_allowlist.test.ts`

**Interfaces:**
- Produces:
  - `export const SANDBOX_ALLOWLIST_DOC = "_ops/sandboxAllowlist";`
  - `export function parseSandboxAllowlist(data: unknown): ReadonlySet<string>`
  - `export async function readSandboxAllowlist(db: Firestore): Promise<ReadonlySet<string>>` — lève si la lecture échoue (`Firestore` = `import type {Firestore} from "firebase-admin/firestore"`, le type que rend `firestoreForEnv`)
  - `export async function readSandboxAllowlistOrEmpty(db: Firestore, context: string): Promise<ReadonlySet<string>>` — ne lève jamais (`logger.error` + ensemble vide)

- [ ] **Step 1: Write the failing test**

Create `functions/src/__tests__/sandbox_allowlist.test.ts`:

```ts
import type {Firestore} from "firebase-admin/firestore";
import {describe, expect, it} from "vitest";

import {
  SANDBOX_ALLOWLIST_DOC,
  parseSandboxAllowlist,
  readSandboxAllowlist,
  readSandboxAllowlistOrEmpty,
} from "../utils/sandbox_allowlist";

import {FakeFirestore} from "./helpers/fake_firestore";

const asDb = (db: unknown) => db as Firestore;

/** Base dont toute lecture échoue (réseau, permissions…). */
const failingDb = asDb({
  doc: () => ({get: () => Promise.reject(new Error("unavailable"))}),
});

describe("parseSandboxAllowlist", () => {
  it("doc absent ou vide → aucun uid", () => {
    expect([...parseSandboxAllowlist(undefined)]).toEqual([]);
    expect([...parseSandboxAllowlist({})]).toEqual([]);
  });

  it("uids pas un tableau → aucun uid", () => {
    expect([...parseSandboxAllowlist({uids: "u1"})]).toEqual([]);
  });

  it("ne garde que des chaînes non vides, sans espaces autour", () => {
    const set = parseSandboxAllowlist({uids: ["u1", " u2 ", "", 42, null]});
    expect([...set].sort()).toEqual(["u1", "u2"]);
  });
});

describe("readSandboxAllowlist", () => {
  it("lit les uids du document prod", async () => {
    const db = new FakeFirestore();
    db.seed(SANDBOX_ALLOWLIST_DOC, {uids: ["review-demo"]});
    const set = await readSandboxAllowlist(asDb(db));
    expect(set.has("review-demo")).toBe(true);
  });

  it("document absent → ensemble vide", async () => {
    const set = await readSandboxAllowlist(asDb(new FakeFirestore()));
    expect(set.size).toBe(0);
  });

  it("lecture en échec → lève (l'appelant décide)", async () => {
    await expect(readSandboxAllowlist(failingDb)).rejects.toThrow("unavailable");
  });
});

describe("readSandboxAllowlistOrEmpty", () => {
  it("lecture en échec → ensemble vide, sans lever (fail-closed)", async () => {
    const set = await readSandboxAllowlistOrEmpty(failingDb, "test");
    expect(set.size).toBe(0);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd functions && npx vitest run src/__tests__/sandbox_allowlist.test.ts`
Expected: FAIL — `Failed to resolve import "../utils/sandbox_allowlist"`.

- [ ] **Step 3: Write minimal implementation**

Create `functions/src/utils/sandbox_allowlist.ts`:

```ts
/**
 * Liste blanche SANDBOX (FEAT-044e, #209) — uids PROD autorisés à recevoir un
 * droit payant via un achat de TEST.
 *
 * App Review (Apple) et les testeurs Google achètent en SANDBOX sur l'app de
 * PRODUCTION. Sans exception, le webhook route ces achats vers `staging`
 * (OWASP-01) : le compte de démo de la review n'obtient jamais Pro et l'app
 * est refusée. Ce document prod liste les rares comptes pour lesquels un achat
 * sandbox vaut un vrai droit. Il est édité à la main (console Firebase) et lu
 * uniquement par les Functions — aucun accès client (règle `_ops`).
 *
 * Fail-closed : une liste illisible vaut « aucun uid » — jamais de déblocage
 * prod par défaut.
 */

import type {Firestore} from "firebase-admin/firestore";
import {logger} from "firebase-functions/v2";

/** Chemin du document, dans la base prod `(default)`. */
export const SANDBOX_ALLOWLIST_DOC = "_ops/sandboxAllowlist";

/** PURE — uids valides du document (`uids: string[]`), sans doublon. */
export function parseSandboxAllowlist(data: unknown): ReadonlySet<string> {
  const raw =
    typeof data === "object" && data !== null ?
      (data as {uids?: unknown}).uids :
      undefined;
  if (!Array.isArray(raw)) return new Set();
  const uids = raw
    .filter((u): u is string => typeof u === "string")
    .map((u) => u.trim())
    .filter((u) => u.length > 0);
  return new Set(uids);
}

/** Lit la liste dans [db] (base prod). Lève si la lecture échoue. */
export async function readSandboxAllowlist(
  db: Firestore,
): Promise<ReadonlySet<string>> {
  const snap = await db.doc(SANDBOX_ALLOWLIST_DOC).get();
  return parseSandboxAllowlist(snap.exists ? snap.data() : undefined);
}

/**
 * Comme [readSandboxAllowlist], sans jamais lever : en cas d'échec, journalise
 * et rend un ensemble vide (comportement par défaut, fail-closed).
 *
 * @param context Préfixe du log (nom de la fonction appelante).
 */
export async function readSandboxAllowlistOrEmpty(
  db: Firestore,
  context: string,
): Promise<ReadonlySet<string>> {
  try {
    return await readSandboxAllowlist(db);
  } catch (err) {
    logger.error(
      `${context}: liste blanche sandbox illisible → aucun uid appliqué`,
      err,
    );
    return new Set();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd functions && npx vitest run src/__tests__/sandbox_allowlist.test.ts && npm run lint && npm run build`
Expected: PASS (7 tests), lint 0 problème, build OK.

- [ ] **Step 5: Commit**

```bash
git add functions/src/utils/sandbox_allowlist.ts functions/src/__tests__/sandbox_allowlist.test.ts
git commit -m "feat(billing): module liste blanche sandbox (_ops/sandboxAllowlist)"
```

---

### Task 2: Webhook — exception SANDBOX pour un uid listé

**Files:**
- Modify: `functions/src/http/revenuecat_webhook.ts` (fonction `handleRevenueCatEvent`, ~l. 320-362, et son docblock)
- Test: `functions/src/__tests__/revenuecat_webhook.test.ts` (nouveau `describe` en fin de fichier)

**Interfaces:**
- Consumes: `readSandboxAllowlist(db)` (Task 1).
- Produces:
  - `export type SandboxAllowlistReader = () => Promise<ReadonlySet<string>>;`
  - `handleRevenueCatEvent(event: RcEvent, nowMs: number, readAllowlist: SandboxAllowlistReader = readProdSandboxAllowlist): Promise<RcOutcome>` — 3ᵉ paramètre optionnel (injection pour les tests ; l'appel du handler HTTP reste `handleRevenueCatEvent(event, Date.now())`).

- [ ] **Step 1: Write the failing test**

Append to `functions/src/__tests__/revenuecat_webhook.test.ts` (les helpers `evt`, `UID`, `NOW`, `FakeFirestore`, `fakeAdminFirestoreHolder`, `fakeStagingFirestoreHolder` existent déjà dans ce fichier ; ajouter `vi` à l'import vitest s'il n'y est pas) :

```ts
// FEAT-044e (#209) — App Review / testeurs Google achètent en SANDBOX sur
// l'app de PROD. Un uid de la liste blanche reçoit ce droit en prod ; tous
// les autres restent routés vers staging (OWASP-01 inchangé).
describe("handleRevenueCatEvent — liste blanche sandbox (FEAT-044e)", () => {
  let prodDb: FakeFirestore;
  let stagingDb: FakeFirestore;

  beforeEach(() => {
    prodDb = new FakeFirestore();
    stagingDb = new FakeFirestore("staging");
    fakeAdminFirestoreHolder.db = prodDb;
    fakeStagingFirestoreHolder.db = stagingDb;
    for (const db of [prodDb, stagingDb]) {
      db.seed(`landlords/${UID}`, {
        id: UID,
        landlordId: UID,
        isAnonymous: false,
        subscriptionTier: "free",
        deletedAt: null,
      });
    }
  });

  const listed = () => Promise.resolve(new Set([UID]) as ReadonlySet<string>);
  const empty = () => Promise.resolve(new Set<string>() as ReadonlySet<string>);
  const failing = () => Promise.reject(new Error("unavailable"));

  it("SANDBOX + uid listé → droit appliqué en PROD, staging intact", async () => {
    const outcome = await handleRevenueCatEvent(
      evt({environment: "SANDBOX"}),
      NOW,
      listed,
    );

    expect(outcome).toBe("applied");
    expect(prodDb.peek(`landlords/${UID}`)?.subscriptionTier).toBe("paid");
    expect(stagingDb.peek(`landlords/${UID}`)?.subscriptionTier).toBe("free");
  });

  it("SANDBOX + uid non listé → staging (comportement inchangé)", async () => {
    await handleRevenueCatEvent(evt({environment: "SANDBOX"}), NOW, empty);

    expect(stagingDb.peek(`landlords/${UID}`)?.subscriptionTier).toBe("paid");
    expect(prodDb.peek(`landlords/${UID}`)?.subscriptionTier).toBe("free");
  });

  it("SANDBOX + liste illisible → staging (fail-closed), prod intacte", async () => {
    await handleRevenueCatEvent(evt({environment: "SANDBOX"}), NOW, failing);

    expect(stagingDb.peek(`landlords/${UID}`)?.subscriptionTier).toBe("paid");
    expect(prodDb.peek(`landlords/${UID}`)?.subscriptionTier).toBe("free");
  });

  it("PRODUCTION → la liste n'est jamais lue", async () => {
    const reader = vi.fn(listed);

    await handleRevenueCatEvent(evt({environment: "PRODUCTION"}), NOW, reader);

    expect(reader).not.toHaveBeenCalled();
    expect(prodDb.peek(`landlords/${UID}`)?.subscriptionTier).toBe("paid");
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd functions && npx vitest run src/__tests__/revenuecat_webhook.test.ts`
Expected: FAIL — « SANDBOX + uid listé » : `subscriptionTier` prod reste `"free"` (l'event part en staging).

- [ ] **Step 3: Write minimal implementation**

In `functions/src/http/revenuecat_webhook.ts`:

1. Add the import next to `import {firestoreForEnv} from "../utils/db_router";`:

```ts
import {readSandboxAllowlist} from "../utils/sandbox_allowlist";
```

2. Just above the docblock of `handleRevenueCatEvent`, add:

```ts
/** Lecteur de la liste blanche sandbox (injectable pour les tests). */
export type SandboxAllowlistReader = () => Promise<ReadonlySet<string>>;

/** Lecteur de production : document `_ops/sandboxAllowlist` de la base prod. */
const readProdSandboxAllowlist: SandboxAllowlistReader = () =>
  readSandboxAllowlist(firestoreForEnv(false));

/**
 * `true` si [uid] est dans la liste blanche sandbox (FEAT-044e). Liste
 * illisible → `false` : règle par défaut (staging), jamais de déblocage prod.
 */
async function isSandboxAllowlisted(
  uid: string,
  read: SandboxAllowlistReader,
): Promise<boolean> {
  try {
    return (await read()).has(uid);
  } catch (err) {
    logger.error(
      "revenueCatWebhook: liste blanche sandbox illisible → staging " +
        `app_user_id=${uid}`,
      err,
    );
    return false;
  }
}
```

3. In the docblock of `handleRevenueCatEvent`, replace the line
` *   - \`"SANDBOX"\`    → base \`staging\` UNIQUEMENT ;`
with:

```ts
 *   - `"SANDBOX"`    → base `staging` UNIQUEMENT — sauf un uid de la liste
 *     blanche sandbox (`_ops/sandboxAllowlist`, FEAT-044e : compte de démo
 *     App Review, testeurs) → base `(default)` UNIQUEMENT ;
```

4. Change the signature and the SANDBOX branch:

```ts
export async function handleRevenueCatEvent(
  event: RcEvent,
  nowMs: number,
  readAllowlist: SandboxAllowlistReader = readProdSandboxAllowlist,
): Promise<RcOutcome> {
  if (event.type === "TEST") return "ignored";

  let isStaging: boolean;
  if (event.environment === "SANDBOX") {
    // Liste lue UNIQUEMENT pour un event SANDBOX : aucun coût sur les achats
    // réels.
    const allowlisted = await isSandboxAllowlisted(
      event.app_user_id,
      readAllowlist,
    );
    if (allowlisted) {
      logger.info(
        "revenueCatWebhook: SANDBOX d'un uid de la liste blanche → prod " +
          `app_user_id=${event.app_user_id}`,
      );
    }
    isStaging = !allowlisted;
  } else if (event.environment === "PRODUCTION") {
```

(the rest of the function — the `else` branch logging unknown environments and the final `return applyRevenueCatEvent(firestoreForEnv(isStaging), event, nowMs);` — stays unchanged).

- [ ] **Step 4: Run test to verify it passes**

Run: `cd functions && npx vitest run src/__tests__/revenuecat_webhook.test.ts && npm run lint && npm run build && cd .. && bash scripts/check-db-isolation.sh`
Expected: PASS (tous les tests du fichier, dont les 4 nouveaux et les tests OWASP-01 existants inchangés), lint 0 problème, build OK, garde d'isolation OK.

- [ ] **Step 5: Commit**

```bash
git add functions/src/http/revenuecat_webhook.ts functions/src/__tests__/revenuecat_webhook.test.ts
git commit -m "feat(billing): webhook — achat sandbox d'un uid de la liste blanche appliqué en prod"
```

---

### Task 3: Cron de réconciliation — uids de la liste blanche

**Files:**
- Modify: `functions/src/scheduled/reconcile_entitlements.ts` (`entitlementStatesFromSubscriber`, `makeRevenueCatFetcher`, handler `reconcileEntitlements`)
- Test: `functions/src/__tests__/reconcile_entitlements.test.ts` (nouveau `describe` en fin de fichier)

**Interfaces:**
- Consumes: `readSandboxAllowlistOrEmpty(db, context)` (Task 1).
- Produces: `entitlementStatesFromSubscriber(subscriber: RcSubscriber | undefined, options: {sandboxAllowed?: boolean} = {}): Partial<Record<LevelId, RcReportedState>>` — `sandboxAllowed: true` → un entitlement sandbox est rapporté comme un vrai droit (`{expiresMs}`), pas `sandboxShadowed`.

- [ ] **Step 1: Write the failing test**

Append to `functions/src/__tests__/reconcile_entitlements.test.ts` (les helpers `seedActivePro`, `fakeDb`, `NOW`, `IN_30D`, `IN_60D`, `rcEntitlementIdFor`, `entitlementStatesFromSubscriber`, `reconcileExpiredEntitlements` existent déjà dans ce fichier) :

```ts
// FEAT-044e — un uid de la liste blanche sandbox (compte de démo App Review,
// testeurs) : son achat sandbox vaut un vrai droit, pour le cron aussi.
describe("reconcile — uid de la liste blanche sandbox (FEAT-044e)", () => {
  const PRO_ID = rcEntitlementIdFor("pro") as string;
  const iso = (ms: number) => new Date(ms).toISOString();
  const sandboxBody = {
    entitlements: {
      [PRO_ID]: {expires_date: iso(IN_60D), product_identifier: "pro_sandbox"},
    },
    subscriptions: {pro_sandbox: {is_sandbox: true}},
  };

  it("sandboxAllowed → entitlement sandbox rapporté comme un vrai droit", () => {
    expect(
      entitlementStatesFromSubscriber(sandboxBody, {sandboxAllowed: true}),
    ).toEqual({pro: {expiresMs: IN_60D}});
  });

  it("sans option → masqué (comportement #209 inchangé)", () => {
    expect(entitlementStatesFromSubscriber(sandboxBody)).toEqual({
      pro: {expiresMs: null, sandboxShadowed: true},
    });
  });

  it("bout en bout : uid listé → échéance sandbox reprise (prolongée)", async () => {
    seedActivePro("review-demo", IN_30D);

    await reconcileExpiredEntitlements(
      fakeDb,
      () =>
        Promise.resolve(
          entitlementStatesFromSubscriber(sandboxBody, {sandboxAllowed: true}),
        ),
      NOW,
    );

    const doc = fakeDb.peek("landlords/review-demo");
    expect(doc?.subscriptionTier).toBe("paid");
    expect((doc?.proExpiresAt as {toMillis(): number}).toMillis()).toBe(IN_60D);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd functions && npx vitest run src/__tests__/reconcile_entitlements.test.ts`
Expected: FAIL — « sandboxAllowed → … » reçoit `{pro: {expiresMs: null, sandboxShadowed: true}}`.

- [ ] **Step 3: Write minimal implementation**

In `functions/src/scheduled/reconcile_entitlements.ts`:

1. Add the import after the `plan_matrix.generated` import:

```ts
import {readSandboxAllowlistOrEmpty} from "../utils/sandbox_allowlist";
```

2. Replace the signature of `entitlementStatesFromSubscriber` and its sandbox test:

```ts
export function entitlementStatesFromSubscriber(
  subscriber: RcSubscriber | undefined,
  options: {sandboxAllowed?: boolean} = {},
): Partial<Record<LevelId, RcReportedState>> {
```

and

```ts
    if (
      productId &&
      subscriptions[productId]?.is_sandbox === true &&
      options.sandboxAllowed !== true
    ) {
      // Jamais accordé ni prolongé ; l'état prod du palier est inconnu (#209).
      // Exception : uid de la liste blanche sandbox (FEAT-044e).
      states[level.id] = {expiresMs: null, sandboxShadowed: true};
      continue;
    }
```

3. Add one line to the docblock of `entitlementStatesFromSubscriber`, after the sentence ending « (#209). » :

```ts
 * Avec `sandboxAllowed` (uid de `_ops/sandboxAllowlist`, FEAT-044e : compte
 * de démo App Review, testeurs), l'achat sandbox vaut un vrai droit.
```

4. Replace `makeRevenueCatFetcher`:

```ts
function makeRevenueCatFetcher(
  apiKey: string,
  sandboxAllowlist: ReadonlySet<string>,
): EntitlementStatesFetcher {
  return async (uid) => {
    const resp = await fetch(
      `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(uid)}`,
      {headers: {Authorization: `Bearer ${apiKey}`}},
    );
    if (!resp.ok) throw new Error(`RevenueCat API ${resp.status}`);
    const body = (await resp.json()) as {subscriber?: RcSubscriber};
    return entitlementStatesFromSubscriber(body.subscriber, {
      sandboxAllowed: sandboxAllowlist.has(uid),
    });
  };
}
```

5. In the `reconcileEntitlements` handler, replace the two lines

```ts
    const db = admin.firestore();
    const fetcher = makeRevenueCatFetcher(revenueCatApiKey.value());
```

with:

```ts
    const db = admin.firestore();
    // Liste lue une fois par passage ; illisible → aucun uid (fail-closed).
    const sandboxAllowlist = await readSandboxAllowlistOrEmpty(
      db,
      "reconcileEntitlements",
    );
    const fetcher = makeRevenueCatFetcher(
      revenueCatApiKey.value(),
      sandboxAllowlist,
    );
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd functions && npx vitest run src/__tests__/reconcile_entitlements.test.ts && npm run lint && npm run build`
Expected: PASS (tous les tests du fichier, dont les 3 nouveaux et ceux de #209 inchangés), lint 0 problème, build OK.

- [ ] **Step 5: Commit**

```bash
git add functions/src/scheduled/reconcile_entitlements.ts functions/src/__tests__/reconcile_entitlements.test.ts
git commit -m "feat(billing): cron — achat sandbox d'un uid de la liste blanche traité comme un vrai droit"
```

---

### Task 4: Règle Firestore `_ops` (aucun accès client)

**Files:**
- Modify: `firestore.rules` (avant le bloc « Fallback — tout le reste bloqué »)
- Test: `functions/rules-tests/firestore_rules.test.ts` (seed + nouveau `describe`)

**Interfaces:**
- Consumes: rien.
- Produces: règle `match /_ops/{docId}` refusant lecture et écriture à tout client.

- [ ] **Step 1: Write the failing test**

In `functions/rules-tests/firestore_rules.test.ts`:

1. In the `beforeAll` seed (inside the existing `env.withSecurityRulesDisabled(async (ctx) => { … })`, after the loop over `LANDLORD_SCOPED_COLLECTIONS`), add:

```ts
    // FEAT-044e — liste blanche sandbox, lue uniquement par les Functions.
    await db.doc("_ops/sandboxAllowlist").set({uids: [LANDLORD_A]});
```

2. Append at the end of the file:

```ts
describe("_ops — configuration serveur, aucun accès client (FEAT-044e)", () => {
  it("un compte (même listé) ne lit pas la liste blanche sandbox", async () => {
    await assertFails(asOwnerA().doc("_ops/sandboxAllowlist").get());
  });
  it("un compte ne peut pas s'ajouter à la liste", async () => {
    await assertFails(
      asOwnerA().doc("_ops/sandboxAllowlist").set({uids: [LANDLORD_A]}),
    );
  });
  it("un compte ne peut pas créer d'autre document _ops", async () => {
    await assertFails(asOwnerA().doc("_ops/autre").set({x: 1}));
  });
});
```

- [ ] **Step 2: Run test to verify it fails or passes for the right reason**

Run: `cd functions && npm run test:rules`
Expected: PASS already (le fallback `match /{document=**}` refuse tout). Ce test fige le refus : il doit rester vert APRÈS l'ajout de la règle explicite, et échouerait si quelqu'un ouvrait `_ops`. Vérifier qu'il a bien tourné (3 tests `_ops` dans la sortie).

- [ ] **Step 3: Add the explicit rule**

In `firestore.rules`, just before the comment block `// Fallback — tout le reste bloqué`, add:

```
    // ====================================================================
    // _ops — configuration lue UNIQUEMENT par les Cloud Functions (Admin SDK)
    // FEAT-044e : `_ops/sandboxAllowlist` (uids prod autorisés à recevoir un
    // droit via un achat sandbox). Aucun accès client, explicitement — le
    // fallback le refuse déjà, mais ouvrir ce chemin par erreur donnerait Pro
    // gratuit en s'auto-ajoutant à la liste.
    // ====================================================================
    match /_ops/{docId} {
      allow read, write: if false;
    }

```

- [ ] **Step 4: Run tests**

Run: `cd functions && npm run test:rules`
Expected: PASS (dont les 3 tests `_ops`).

- [ ] **Step 5: Commit**

```bash
git add firestore.rules functions/rules-tests/firestore_rules.test.ts
git commit -m "feat(rules): _ops refusé à tout client (liste blanche sandbox)"
```

---

### Task 5: Docs, état du projet, vérification complète, PR

**Files:**
- Modify: `docs/SECURITY.md` (puce « Facturation (OWASP-01) » de la section audit OWASP)
- Modify: `docs/state/functions/README.md` (ligne `reconcileEntitlements` du tableau « Scheduled »)
- Modify: `docs/state/CHANGELOG.md` (nouvelle entrée en tête de la période courante)
- Modify: `docs/ENVIRONMENTS.md` (section « Facturation », si elle décrit le routage SANDBOX)

**Interfaces:** aucune (docs).

- [ ] **Step 1: Mettre à jour les docs**

1. `docs/SECURITY.md` — dans la puce « **Facturation (OWASP-01)** », après « aucun repli sur l'autre base. », ajouter :

```
Exception FEAT-044e : un event `SANDBOX` d'un uid de `_ops/sandboxAllowlist` (base prod, aucun accès client, édité dans la console) est appliqué à `(default)` — compte de démo App Review, testeurs ; le cron traite aussi leur achat sandbox comme un vrai droit. Liste illisible → comportement par défaut.
```

2. `docs/state/functions/README.md` — dans la ligne `reconcileEntitlements` du tableau « Scheduled », après « (#209) », ajouter :

```
 ; uid de `_ops/sandboxAllowlist` → achat sandbox traité comme un vrai droit (FEAT-044e, liste lue une fois par passage)
```

3. `docs/ENVIRONMENTS.md` — `grep -n "SANDBOX" docs/ENVIRONMENTS.md` ; là où le routage SANDBOX → `staging` est décrit, ajouter la même exception en une phrase.

4. `docs/state/CHANGELOG.md` — insérer en tête de la section « Changements (…) » :

```
### FEAT-044e lot 1 : liste blanche sandbox (2026-10-05)
- Document prod `_ops/sandboxAllowlist` (`uids`), édité dans la console, refusé à tout client (règle explicite + test). Le webhook RevenueCat applique en prod un event `SANDBOX` d'un uid listé (compte de démo App Review, testeurs) ; tous les autres restent routés vers `staging` (OWASP-01). Le cron de réconciliation traite leur achat sandbox comme un vrai droit. Liste illisible → comportement par défaut + `logger.error` (fail-closed). Prérequis de la soumission des apps avec achat intégré (#207).
```

- [ ] **Step 2: Vérification complète**

Run:
```bash
cd functions && npm run lint && npm run build && npx vitest run && npm run test:rules && cd .. && bash scripts/check-db-isolation.sh && bash scripts/check-stripe-isolation.sh && bash scripts/check-secrets.sh --all
```
Expected: lint 0 problème ; build OK ; Vitest tout vert (≈ 689 tests : 675 + 7 + 4 + 3) ; rules vertes ; les trois garde-fous OK.

- [ ] **Step 3: Commit docs**

```bash
git add docs/SECURITY.md docs/state/functions/README.md docs/state/CHANGELOG.md docs/ENVIRONMENTS.md
git commit -m "docs(billing): liste blanche sandbox (FEAT-044e lot 1)"
```

- [ ] **Step 4: Push + PR vers `develop`**

```bash
git push -u origin feat/044e-iap-server
gh pr create --base develop --title "feat(billing): liste blanche sandbox pour la review des apps (FEAT-044e lot 1)" --body-file /tmp/pr-044e-lot1.md
```

Le fichier `/tmp/pr-044e-lot1.md` (à écrire avant la commande) contient : la spec, les 4 points (module, webhook, cron, règle), les tests ajoutés, et **« Déploiement : `firebase deploy --only functions` après merge (Daki) ; la règle `_ops` part par la CI (staging sur `develop`, prod à la release). Rien ne change tant que le document `_ops/sandboxAllowlist` n'existe pas. »** Refs #207, #209.
