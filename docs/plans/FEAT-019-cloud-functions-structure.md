# FEAT-019 — Cloud Functions Structure (Node 20 + TypeScript)

Architect plan to replace Supabase Postgres triggers and Edge Functions with
Firebase Cloud Functions (Gen 2, Node 20, TypeScript, `firebase-functions` v6).

---

## 1. Mapping triggers Postgres → Cloud Functions

| Source (Postgres / Edge)                          | Cloud Function (Gen 2)                                       | Type                              | Module                                   |
|---------------------------------------------------|--------------------------------------------------------------|-----------------------------------|------------------------------------------|
| `handle_new_user()` on `auth.users INSERT`        | `beforeUserCreated` (Identity Platform blocking)             | Auth blocking                     | `src/auth/handle_new_user.ts`            |
| `set_updated_at` (universal `UPDATE`)             | Firestore `onDocumentUpdated` per collection                 | Firestore trigger                 | `src/triggers/set_updated_at.ts`         |
| `prevent_protected_columns_change`                | Firestore `onDocumentUpdated` (revert via merge)             | Firestore trigger                 | `src/triggers/prevent_immutable.ts`      |
| `recompute_receipt_stale_on_payment_archive`      | Firestore `onDocumentUpdated` on `payments`                  | Firestore trigger                 | `src/triggers/recompute_receipt_stale.ts`|
| `assert_payment_lease_ownership`                  | Firestore `onDocumentWritten` on `payments` (validate)       | Firestore trigger                 | `src/triggers/assert_ownership.ts`       |
| `assert_receipt_lease_ownership`                  | Firestore `onDocumentWritten` on `receipts` (validate)       | Firestore trigger                 | `src/triggers/assert_ownership.ts`       |
| Edge `generate-receipt`                           | `onCall` HTTPS callable                                      | Callable (auth-checked)           | `src/callable/generate_receipt.ts`       |
| Future `void_receipt`, `mark_receipt_as_sent`     | `onCall` HTTPS callable                                      | Callable                          | `src/callable/*.ts`                      |

**Notes** :
- `set_updated_at` est dupliqué par collection (pas de wildcard universel Gen 2).
  Factoriser via une factory `makeSetUpdatedAt('properties')`.
- `prevent_protected_columns_change` : compare `before` vs `after`, si col
  immuable change → restore via `event.data.after.ref.update({col: before[col]})`.
  Logger l'incident (audit trail).
- Ownership asserts : déplacés en **Firestore Security Rules** prioritairement
  (cheaper + atomic). CF servent de **double-check async** + audit log.

---

## 2. Structure dossier `/functions/`

```
functions/
├── package.json              # Node 20, firebase-functions ^6, firebase-admin ^12
├── tsconfig.json             # strict, target ES2022
├── .eslintrc.cjs             # google config + custom
├── src/
│   ├── index.ts              # entry point — exporte toutes les functions
│   ├── auth/
│   │   └── handle_new_user.ts          # beforeUserCreated
│   ├── triggers/
│   │   ├── set_updated_at.ts           # factory per collection
│   │   ├── prevent_immutable.ts        # factory per collection
│   │   ├── recompute_receipt_stale.ts  # on payments update
│   │   └── assert_ownership.ts         # payments + receipts
│   ├── callable/
│   │   ├── generate_receipt.ts         # port de l'Edge Function
│   │   ├── void_receipt.ts
│   │   └── mark_receipt_as_sent.ts
│   ├── pdf/
│   │   ├── layout.ts                   # port direct de pdf_layout.ts
│   │   └── helpers.ts
│   ├── utils/
│   │   ├── firestore_helpers.ts        # getOrFail, ownerOf, withSchema
│   │   ├── validation.ts               # zod schemas
│   │   └── audit.ts                    # audit log writer
│   └── types/
│       └── index.ts                    # shared types (Landlord, Lease, Payment…)
└── test/
    ├── unit/                 # vitest
    └── integration/          # firebase-functions-test + emulator
```

**`src/index.ts`** exporte avec `region('europe-west1')` + `runWith({memory, timeoutSeconds})`.

---

## 3. PDF generation : `pdf-lib` (décision)

**Choix : `pdf-lib` (pure Node, déjà utilisé en Deno)**

| Critère              | pdf-lib                       | pdfkit                        | puppeteer                       |
|----------------------|-------------------------------|-------------------------------|---------------------------------|
| Cold start CF        | ~200 ms (pure JS, no native)  | ~250 ms (pure JS)             | ~3-5 s (Chrome headless)        |
| Memory               | 128–256 MB suffit             | 128–256 MB                    | 1 GB minimum (Chrome)           |
| Coût CF              | ~ €0.001/PDF                  | ~ €0.001/PDF                  | ~ €0.01/PDF (10x)               |
| Migration depuis Deno| **Zéro refacto** (même API)   | Réécriture complète           | Réécriture HTML template        |
| Polices custom       | StandardFonts OK + embed TTF  | Limité                        | CSS/HTML full                   |

**Verdict** : `pdf-lib` v1.17+. Le fichier `pdf_layout.ts` (416 lignes) se copie
**presque verbatim** : changer `import "./deps.ts"` → `import "pdf-lib"`,
`Deno.serve` → callable handler, `Uint8Array` reste compatible (Node 20 stream).

PDF stocké dans Cloud Storage (`gs://easyrent-receipts/<receipt_id>.pdf`),
signed URL 7j via `getSignedUrl()` (admin SDK).

---

## 4. Tests

- **Unit** : `vitest` + `@firebase/rules-unit-testing`
  - `src/pdf/layout.test.ts` : snapshot des bytes header PDF + assertions
    métadonnées (Title, Author, mentions légales loi 1989).
  - `src/utils/validation.test.ts` : schémas zod.
- **Integration** : `firebase-functions-test` (offline mode)
  + Firestore emulator pour triggers.
  - `test/integration/handle_new_user.test.ts` : sign-up → vérifie landlord doc créé.
  - `test/integration/generate_receipt.test.ts` : callable → vérifie PDF + Firestore.
- **Cross-tenant** : test ownership refusé (lease d'un autre landlord).
- CI : job dédié `functions-ci` (Node 20, cache npm, `npm test`).

---

## 5. Dépendances `package.json` (clés)

```json
{
  "engines": { "node": "20" },
  "main": "lib/index.js",
  "dependencies": {
    "firebase-admin": "^12.6.0",
    "firebase-functions": "^6.0.0",
    "pdf-lib": "^1.17.1",
    "zod": "^3.23.0"
  },
  "devDependencies": {
    "typescript": "^5.5.0",
    "vitest": "^2.0.0",
    "firebase-functions-test": "^3.4.0",
    "@types/node": "^20.0.0"
  }
}
```

---

## 6. Prochaines étapes (Phase 3 Setup)

1. `mkdir functions && cd functions && firebase init functions` (Node 20 + TS).
2. Scaffold dossiers ci-dessus (vide sauf `index.ts`).
3. Implem `handle_new_user` en premier (gate auth) → unblock FEAT-019 Phase 4.
4. Port `generate-receipt` (Phase 5 — biggest chunk, ~2j).
5. Triggers `set_updated_at` + `prevent_immutable` (Phase 6).
