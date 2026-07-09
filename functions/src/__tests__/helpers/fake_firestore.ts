/**
 * Fake Firestore minimal — couvre exactement le sous-ensemble de l'API
 * Admin SDK utilisé par `expenses.ts` / `soft_delete.ts` :
 *   db.doc(path) / db.collection(name).doc()
 *   db.runTransaction(fn) avec tx.get/tx.set/tx.update
 *   admin.firestore.FieldValue.serverTimestamp() / increment()
 *
 * Aucun émulateur Firestore n'est requis : le projet ne fournit pas de
 * harness d'émulateur pour les tests vitest (cf. finalize_anonymous_upgrade
 * .test.ts, seul test existant — unitaire sur fonctions pures). Ce fake
 * permet de tester la logique métier cross-entity (ownership, cohérence
 * lease/property, dérivation catégorie, snapshots) sans dépendance externe.
 *
 * Limites assumées (suffisantes pour les callables couverts) :
 *   - Pas de vraies requêtes `.where()` (non utilisées par expenses.ts).
 *   - `runTransaction` exécute la fonction sur le même store partagé
 *     (pas d'isolation de transaction concurrente — inutile en tests seq).
 *   - `serverTimestamp()` retourne un sentinel résolu en Date au write.
 */

const SERVER_TIMESTAMP_SENTINEL = {__type: "serverTimestamp"} as const;

export function isServerTimestampSentinel(v: unknown): boolean {
  return (
    typeof v === "object" &&
    v !== null &&
    (v as {__type?: string}).__type === "serverTimestamp"
  );
}

class FakeIncrement {
  readonly __type = "increment";
  constructor(public readonly delta: number) {}
}

export function isIncrement(v: unknown): v is FakeIncrement {
  return v instanceof FakeIncrement;
}

export const fakeFieldValue = {
  serverTimestamp: () => SERVER_TIMESTAMP_SENTINEL,
  increment: (delta: number) => new FakeIncrement(delta),
};

type DocData = Record<string, unknown>;

/** Resolves sentinels (serverTimestamp/increment) against existing data. */
function resolveWrite(
  existing: DocData | undefined,
  patch: DocData,
): DocData {
  const resolved: DocData = {...(existing ?? {})};
  for (const [k, v] of Object.entries(patch)) {
    if (isServerTimestampSentinel(v)) {
      resolved[k] = new Date();
    } else if (isIncrement(v)) {
      const existingValue = resolved[k];
      const current = typeof existingValue === "number" ? existingValue : 0;
      resolved[k] = current + v.delta;
    } else {
      resolved[k] = v;
    }
  }
  return resolved;
}

export class FakeDocRef {
  constructor(
    public readonly path: string,
    private readonly store: Map<string, DocData>,
  ) {}

  get id(): string {
    const parts = this.path.split("/");
    return parts[parts.length - 1] as string;
  }

  get(): Promise<FakeDocSnapshot> {
    const data = this.store.get(this.path);
    return Promise.resolve(new FakeDocSnapshot(this.path, data));
  }

  set(data: DocData): Promise<void> {
    this.store.set(this.path, resolveWrite(undefined, data));
    return Promise.resolve();
  }

  update(patch: DocData): Promise<void> {
    const existing = this.store.get(this.path);
    if (existing === undefined) {
      throw new Error(`update() on missing doc: ${this.path}`);
    }
    this.store.set(this.path, resolveWrite(existing, patch));
    return Promise.resolve();
  }
}

export class FakeDocSnapshot {
  constructor(
    public readonly path: string,
    private readonly _data: DocData | undefined,
  ) {}

  get exists(): boolean {
    return this._data !== undefined;
  }

  data(): DocData | undefined {
    return this._data;
  }
}

export class FakeTransaction {
  constructor(private readonly store: Map<string, DocData>) {}

  get(ref: FakeDocRef): Promise<FakeDocSnapshot> {
    return ref.get();
  }

  set(ref: FakeDocRef, data: DocData): void {
    this.store.set(ref.path, resolveWrite(undefined, data));
  }

  update(ref: FakeDocRef, patch: DocData): void {
    const existing = this.store.get(ref.path);
    if (existing === undefined) {
      throw new Error(`update() on missing doc: ${ref.path}`);
    }
    this.store.set(ref.path, resolveWrite(existing, patch));
  }
}

let autoIdCounter = 0;

/**
 * Snapshot de doc retourné par les requêtes (FakeQuery) — expose `ref`
 * en plus de `id`/`data()` pour permettre `batch.delete(doc.ref)`.
 */
export class FakeQueryDocSnapshot extends FakeDocSnapshot {
  constructor(
    path: string,
    data: DocData | undefined,
    public readonly ref: FakeDocRef,
  ) {
    super(path, data);
  }

  get id(): string {
    return this.ref.id;
  }
}

/**
 * Requête fake — couvre le sous-ensemble utilisé par `delete_account.ts` :
 * `.where(field, "==", value)` (chaînable) + `.limit(n)` + `.get()`.
 */
export class FakeQuery {
  constructor(
    protected readonly collectionName: string,
    protected readonly queryStore: Map<string, DocData>,
    private readonly filters: ReadonlyArray<[string, unknown]> = [],
    private readonly limitCount: number | null = null,
  ) {}

  where(field: string, op: string, value: unknown): FakeQuery {
    if (op !== "==") {
      throw new Error(`FakeQuery: unsupported operator ${op}`);
    }
    return new FakeQuery(
      this.collectionName,
      this.queryStore,
      [...this.filters, [field, value]],
      this.limitCount,
    );
  }

  limit(n: number): FakeQuery {
    return new FakeQuery(
      this.collectionName,
      this.queryStore,
      this.filters,
      n,
    );
  }

  /** Agrégation count() — sous-ensemble de l'API Admin SDK v12. */
  count(): {get: () => Promise<{data: () => {count: number}}>} {
    return {
      get: async () => {
        const res = await this.get();
        return {data: () => ({count: res.size})};
      },
    };
  }

  get(): Promise<{
    docs: FakeQueryDocSnapshot[];
    empty: boolean;
    size: number;
  }> {
    const prefix = `${this.collectionName}/`;
    const docs: FakeQueryDocSnapshot[] = [];
    for (const [path, data] of this.queryStore.entries()) {
      // Ne matche que les docs DIRECTS de la collection (pas de sous-coll).
      if (!path.startsWith(prefix)) continue;
      if (path.slice(prefix.length).includes("/")) continue;
      if (this.filters.every(([field, value]) => data[field] === value)) {
        docs.push(
          new FakeQueryDocSnapshot(
            path,
            data,
            new FakeDocRef(path, this.queryStore),
          ),
        );
      }
      if (this.limitCount !== null && docs.length >= this.limitCount) break;
    }
    return Promise.resolve({docs, empty: docs.length === 0, size: docs.length});
  }
}

export class FakeCollectionRef extends FakeQuery {
  get name(): string {
    return this.collectionName;
  }

  doc(id?: string): FakeDocRef {
    const docId = id ?? `auto-${++autoIdCounter}`;
    return new FakeDocRef(`${this.collectionName}/${docId}`, this.queryStore);
  }
}

/**
 * WriteBatch fake — `delete`/`update`/`set` bufferisés, appliqués au
 * `commit()` (même sémantique atomique-en-apparence que l'Admin SDK pour
 * des tests séquentiels).
 */
export class FakeWriteBatch {
  private readonly ops: Array<() => void> = [];

  constructor(private readonly store: Map<string, DocData>) {}

  delete(ref: FakeDocRef): this {
    this.ops.push(() => this.store.delete(ref.path));
    return this;
  }

  update(ref: FakeDocRef, patch: DocData): this {
    this.ops.push(() => {
      const existing = this.store.get(ref.path);
      if (existing === undefined) {
        throw new Error(`batch.update() on missing doc: ${ref.path}`);
      }
      this.store.set(ref.path, resolveWrite(existing, patch));
    });
    return this;
  }

  set(ref: FakeDocRef, data: DocData): this {
    this.ops.push(() => this.store.set(ref.path, resolveWrite(undefined, data)));
    return this;
  }

  commit(): Promise<void> {
    for (const op of this.ops) op();
    this.ops.length = 0;
    return Promise.resolve();
  }
}

export class FakeFirestore {
  readonly store = new Map<string, DocData>();

  doc(path: string): FakeDocRef {
    return new FakeDocRef(path, this.store);
  }

  collection(name: string): FakeCollectionRef {
    return new FakeCollectionRef(name, this.store);
  }

  runTransaction<T>(fn: (tx: FakeTransaction) => Promise<T>): Promise<T> {
    const tx = new FakeTransaction(this.store);
    return fn(tx);
  }

  batch(): FakeWriteBatch {
    return new FakeWriteBatch(this.store);
  }

  /** Helper de setup de test : injecte un doc directement dans le store. */
  seed(path: string, data: DocData): void {
    this.store.set(path, data);
  }

  /** Helper d'assertion de test : lit un doc directement depuis le store. */
  peek(path: string): DocData | undefined {
    return this.store.get(path);
  }
}

/**
 * Fake Storage minimal — couvre le sous-ensemble utilisé par
 * `documents.ts` (`bucket().file(path).exists()` / `.getSignedUrl()`) et
 * `delete_account.ts` (`bucket().deleteFiles({prefix})`). Par défaut tous
 * les fichiers "existent" (upload réputé réussi) ; `existingPaths` permet
 * de simuler un upload manquant pour les tests qui exercent ce garde-fou.
 * `deletedPrefixes` enregistre les purges par préfixe ; `deleteFilesError`
 * simule un échec GCS.
 */
export class FakeStorage {
  existingPaths: Set<string> | null = null; // null = tout existe
  readonly deletedPrefixes: string[] = [];
  deleteFilesError: Error | null = null;

  bucket(): {
    file: (path: string) => {
      exists: () => Promise<[boolean]>;
      getSignedUrl: (opts: unknown) => Promise<[string]>;
    };
    deleteFiles: (opts: {prefix: string}) => Promise<void>;
    } {
    return {
      file: (path: string) => ({
        exists: () =>
          Promise.resolve([
            this.existingPaths === null || this.existingPaths.has(path),
          ]),
        getSignedUrl: () => Promise.resolve([`https://fake-signed-url/${path}`]),
      }),
      deleteFiles: (opts: {prefix: string}) => {
        if (this.deleteFilesError) return Promise.reject(this.deleteFilesError);
        this.deletedPrefixes.push(opts.prefix);
        return Promise.resolve();
      },
    };
  }
}

/**
 * Fake Auth Admin minimal — couvre `admin.auth().deleteUser(uid)` et
 * `admin.auth().getUser(uid)` (delete_account.ts). `deleteUserError` /
 * `getUserError` simulent un échec (ex. objet avec `code:
 * "auth/user-not-found"` pour les chemins idempotents). `providerDataByUid`
 * pilote la vérification autoritative de l'exemption anonyme (M1) — par
 * défaut, aucun provider lié (vrai compte anonyme).
 */
export class FakeAuthAdmin {
  readonly deletedUids: string[] = [];
  deleteUserError: unknown = null;
  getUserError: unknown = null;
  readonly providerDataByUid = new Map<string, Array<{providerId: string}>>();

  private static toError(raw: unknown): Error {
    return raw instanceof Error ?
      raw :
      Object.assign(new Error("auth error"), raw);
  }

  deleteUser(uid: string): Promise<void> {
    if (this.deleteUserError != null) {
      return Promise.reject(FakeAuthAdmin.toError(this.deleteUserError));
    }
    this.deletedUids.push(uid);
    return Promise.resolve();
  }

  getUser(uid: string): Promise<{
    uid: string;
    providerData: Array<{providerId: string}>;
  }> {
    if (this.getUserError != null) {
      return Promise.reject(FakeAuthAdmin.toError(this.getUserError));
    }
    return Promise.resolve({
      uid,
      providerData: this.providerDataByUid.get(uid) ?? [],
    });
  }
}

/**
 * Holder mutable partagé avec le mock `vi.mock("firebase-admin", ...)`.
 *
 * Le factory passé à `vi.mock` est hoisted par vitest au-dessus des
 * imports : il ne peut donc pas fermer sur une variable `let` déclarée
 * dans le fichier de test (zone morte temporelle). En revanche, il PEUT
 * importer ce module (comme n'importe quel import normal, résolu après
 * le hoisting du mock lui-même) et lire un champ mutable dessus au moment
 * de l'appel — d'où cet objet exporté plutôt qu'une variable module-level
 * classique.
 */
export const fakeAdminFirestoreHolder: {
  db: FakeFirestore | undefined;
  storage: FakeStorage | undefined;
  authAdmin: FakeAuthAdmin | undefined;
} = {
  db: undefined,
  storage: undefined,
  authAdmin: undefined,
};

/**
 * `admin.firestore.Timestamp` fake — `fromMillis`/`fromDate` retournent des
 * `Date` (suffisant pour asserter les champs écrits dans le store).
 */
export const fakeTimestamp = {
  fromMillis: (ms: number) => new Date(ms),
  fromDate: (d: Date) => d,
  now: () => new Date(),
};

/** Factory prête à l'emploi pour `vi.mock("firebase-admin", makeFakeAdminModule)`. */
export function makeFakeAdminModule(): {
  firestore: (() => FakeFirestore | undefined) & {
    FieldValue: typeof fakeFieldValue;
    Timestamp: typeof fakeTimestamp;
  };
  storage: () => FakeStorage | undefined;
  auth: () => FakeAuthAdmin | undefined;
  } {
  return {
    firestore: Object.assign(
      () => fakeAdminFirestoreHolder.db,
      {FieldValue: fakeFieldValue, Timestamp: fakeTimestamp},
    ),
    storage: () => fakeAdminFirestoreHolder.storage,
    auth: () => fakeAdminFirestoreHolder.authAdmin,
  };
}
