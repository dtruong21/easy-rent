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

export class FakeCollectionRef {
  constructor(
    public readonly name: string,
    private readonly store: Map<string, DocData>,
  ) {}

  doc(id?: string): FakeDocRef {
    const docId = id ?? `auto-${++autoIdCounter}`;
    return new FakeDocRef(`${this.name}/${docId}`, this.store);
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
 * `documents.ts` : `admin.storage().bucket().file(path).exists()` et
 * `.getSignedUrl()`. Par défaut tous les fichiers "existent" (upload
 * réputé réussi) ; `existingPaths` permet de simuler un upload manquant
 * pour les tests qui exercent ce garde-fou.
 */
export class FakeStorage {
  existingPaths: Set<string> | null = null; // null = tout existe

  bucket(): {
    file: (path: string) => {
      exists: () => Promise<[boolean]>;
      getSignedUrl: (opts: unknown) => Promise<[string]>;
    };
    } {
    return {
      file: (path: string) => ({
        exists: () =>
          Promise.resolve([
            this.existingPaths === null || this.existingPaths.has(path),
          ]),
        getSignedUrl: () => Promise.resolve([`https://fake-signed-url/${path}`]),
      }),
    };
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
} = {
  db: undefined,
  storage: undefined,
};

/** Factory prête à l'emploi pour `vi.mock("firebase-admin", makeFakeAdminModule)`. */
export function makeFakeAdminModule(): {
  firestore: (() => FakeFirestore | undefined) & {FieldValue: typeof fakeFieldValue};
  storage: () => FakeStorage | undefined;
  } {
  return {
    firestore: Object.assign(
      () => fakeAdminFirestoreHolder.db,
      {FieldValue: fakeFieldValue},
    ),
    storage: () => fakeAdminFirestoreHolder.storage,
  };
}
