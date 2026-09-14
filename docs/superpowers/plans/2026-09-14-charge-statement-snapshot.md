# FEAT-033 — Décompte de régularisation figé (snapshot immuable) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persister un instantané immuable (`charge_statements/{id}`) de chaque régularisation annuelle de charges validée, reproductible à l'identique, sur le patron exact des quittances (`receipts`).

**Architecture:** Nouvelle collection `charge_statements/{id}` CF-exclusive et immuable. Trois callables (`finalizeChargeRegularization`, `voidChargeStatement`, `markChargeStatementAsSent`) miroir de `generateReceipt`/`voidReceipt`/`markReceiptAsSent`. Le PDF reste rendu côté client à partir des champs figés (aucun PDF/Storage serveur). La régularisation, aujourd'hui 100 % client volatile, devient CF-backed. Côté Flutter : modèle + repository + contrôleur de finalisation + section historique sur la fiche bail.

**Tech Stack:** Cloud Functions TypeScript (firebase-functions v2, `onCall`, région `europe-west1`, vitest + harness `FakeFirestore`), Firestore Rules + rules-tests (`@firebase/rules-unit-testing`), Flutter/Riverpod (freezed model, `firestoreProvider`, `cloud_functions`), i18n `.arb` FR/EN + `flutter gen-l10n`.

**Spec:** `docs/superpowers/specs/2026-09-14-charge-statement-snapshot-design.md`

## Global Constraints

Chaque tâche hérite implicitement de ces contraintes (valeurs exactes) :

- **ADR 0003 (isolation prod/staging)** : tout callable écrivant Firestore utilise `dbForRequest(request)`. `admin.firestore()` / `getFirestore()` interdits hors crons/triggers — `scripts/check-db-isolation.sh` échoue la PR sinon.
- **Accès Firestore client** : via `firestoreProvider` (`ref.read(firestoreProvider)`) uniquement. `FirebaseFirestore.instance` / `.instanceFor` interdits hors `main.dart`.
- **Immuabilité légale** : `charge_statements` → Rules `create, update, delete: if false`. Écritures exclusivement en callable. Pas de soft-delete (rétention 5 ans, loi 6 juillet 1989).
- **Preuve infalsifiable** : `provisionsCollectedCents` est **recalculé serveur** depuis `payments` — jamais accepté depuis le client.
- **Récupérable uniquement** : seules les charges récupérables entrent dans le solde. Ni `leases.nonRecoverableChargesCents` ni `properties.condoFeesNonRecoverableCents`.
- **Gate légal** : la finalisation n'est autorisée que si le mode de charges effectif du bail est `provisions` (`resolveChargeMode(leaseType, chargeMode) === "provisions"` côté serveur ; `lease.canRegularizeCharges` côté client).
- **Montants** : centimes (`int`), jamais de `double`. Affichage `1 234,56 €`, dates `DD/MM/YYYY`.
- **Dates sur le fil** : écrites `.toUtc().toIso8601String()`, relues `DateTime.parse("…Z")` puis `.toLocal()` avant toute lecture de `.year/.month/.day`.
- **i18n** : nouvelles clés dans `lib/l10n/app_fr.arb` ET `lib/l10n/app_en.arb`, `@description` sur le template EN ; `test/l10n/arb_parity_test.dart` impose la parité. Régénérer via `flutter gen-l10n` (fichiers générés gitignorés).
- **Format CI** : `dart format .` (repo-wide) et `npm run lint` (functions) avant push — la CI lance `dart format --set-exit-if-changed .`.
- **PATH** : `export PATH="/opt/homebrew/bin:$PATH"` en tête de chaque commande shell (flutter/dart/gh/firebase/node).
- **Région callables** : `{region: "europe-west1"}`.

---

## File Structure

**Functions (TypeScript)**
- Create `functions/src/callable/charge_statements.ts` — les 3 callables + helpers purs (recompute provisions, validation lineItems).
- Modify `functions/src/index.ts` — ré-exporter les 3 callables.
- Modify `functions/src/callable/export_account_data.ts` — ajouter `chargeStatements` à `EXPORTED_COLLECTIONS`.
- Create `functions/src/__tests__/charge_statements.test.ts` — tests unitaires (harness `FakeFirestore`).
- Modify `functions/rules-tests/firestore_rules.test.ts` — couvrir `charge_statements`.

**Firestore config**
- Modify `firestore.rules` — bloc `match /charge_statements/{id}`.
- Modify `firestore.indexes.json` — index composite `charge_statements`.

**Flutter (Dart)**
- Create `lib/features/charge_regularization/domain/charge_statement.dart` — modèle freezed figé + `lineItems` + `direction` dérivé.
- Create `lib/features/charge_regularization/data/charge_statement_repository.dart` — lecture + wrappers callables + provider.
- Create `lib/features/charge_regularization/application/charge_statement_finalize_controller.dart` — flux finalize → PDF figé → share → markAsSent.
- Modify `lib/features/charge_regularization/domain/charge_regularization_pdf_renderer.dart` — helper `ChargeRegularizationPdfData.fromStatement(...)` (rendu depuis un snapshot figé).
- Modify `lib/features/charge_regularization/presentation/widgets/charge_regularization_dialog.dart` — action « Finaliser & figer ».
- Create `lib/features/charge_regularization/presentation/widgets/charge_statement_history_section.dart` — historique fiche bail (liste + re-share + void).
- Modify la fiche bail (`LeaseDetailPage`, cf. Task 9) — insérer la section historique.
- Modify `lib/l10n/app_fr.arb` + `lib/l10n/app_en.arb` — clés i18n (Tasks 8 & 9).
- Create tests Dart : `test/unit/charge_statement_test.dart`, `test/unit/charge_statement_repository_test.dart`, `test/unit/charge_statement_finalize_controller_test.dart`, `test/widget/charge_statement_history_section_test.dart`.

**Docs**
- Modify `docs/state/FEATURES.md`, `docs/state/CHANGELOG.md`, `docs/state/schema/leases.md`, `docs/state/functions/leases.md`.

---

## Task 1 — Callable `finalizeChargeRegularization` (+ helpers purs)

**Files:**
- Create: `functions/src/callable/charge_statements.ts`
- Modify: `functions/src/index.ts`
- Test: `functions/src/__tests__/charge_statements.test.ts`

**Interfaces:**
- Consumes (existants) : `functions/src/utils/callable_helpers.ts` → `asBag`, `requireAuthUid`, `requireString`, `requireInt(value, name, {min})`, `toTimestamp(value, name)`, `dataOrFail(snap, msg)` ; `functions/src/utils/db_router.ts` → `dbForRequest(request)` ; `functions/src/callable/lease_payment.ts` → `resolveChargeMode(leaseType, chargeMode)` (retourne `"provisions" | "forfait"`, jette sur incohérence).
- Produces : export `finalizeChargeRegularization` (onCall) ; helpers purs testables `sumProvisionsOverlap(payments, periodStart, periodEnd)`, `validateLineItems(lineItems, actualExpensesCents)`.

**Wire format** attendu par le callable :
- `leaseId: string`
- `periodStart: string` (ISO 8601 UTC), `periodEnd: string` (ISO)
- `actualExpensesCents: number` (int ≥ 0)
- `actualExpensesSource: "expenses" | "manual"`
- `lineItems: Array<{ expenseId: string; nature: string; notes: string; amountCents: number; expenseDate: string }>` (vide si `manual`)

- [ ] **Step 1: Écrire les tests des helpers purs (échouants)**

Dans `functions/src/__tests__/charge_statements.test.ts`, reprendre l'en-tête de mock exact de `functions/src/__tests__/expenses.test.ts` (bloc `vi.mock("firebase-admin", …)` + `makeRequest` + `FakeFirestore`). Ajouter :

```ts
import {beforeEach, describe, expect, it} from "vitest";
import {Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {
  finalizeChargeRegularization,
  sumProvisionsOverlap,
  validateLineItems,
} from "../callable/charge_statements";

describe("sumProvisionsOverlap", () => {
  const ts = (iso: string) => Timestamp.fromDate(new Date(iso));
  const pay = (start: string, end: string, chargesCents: number) => ({
    chargesAmountCents: chargesCents,
    periodStart: ts(start),
    periodEnd: ts(end),
  });

  it("somme les chargesAmountCents des paiements recouvrant la période", () => {
    const total = sumProvisionsOverlap(
      [
        pay("2025-01-01", "2025-01-31", 10000), // dans la période
        pay("2025-12-01", "2025-12-31", 10000), // dans la période
        pay("2024-12-01", "2024-12-31", 9999), // hors période
      ],
      ts("2025-01-01"),
      ts("2025-12-31"),
    );
    expect(total).toBe(20000);
  });

  it("inclut un paiement qui chevauche partiellement une borne", () => {
    const total = sumProvisionsOverlap(
      [pay("2024-12-15", "2025-01-15", 5000)],
      ts("2025-01-01"),
      ts("2025-12-31"),
    );
    expect(total).toBe(5000);
  });
});

describe("validateLineItems", () => {
  const li = (amountCents: number) => ({
    expenseId: "e1", nature: "condo_charges", notes: "",
    amountCents, expenseDate: "2025-06-01T00:00:00.000Z",
  });

  it("accepte quand la somme des lignes == total", () => {
    expect(() => validateLineItems([li(600), li(400)], 1000)).not.toThrow();
  });

  it("rejette quand la somme diverge du total", () => {
    expect(() => validateLineItems([li(600), li(400)], 999)).toThrow(HttpsError);
  });

  it("rejette un amountCents négatif", () => {
    expect(() => validateLineItems([li(-1)], -1)).toThrow(HttpsError);
  });
});
```

- [ ] **Step 2: Lancer les tests → échec (module absent)**

Run: `export PATH="/opt/homebrew/bin:$PATH"; cd functions && npx vitest run src/__tests__/charge_statements.test.ts`
Expected: FAIL — `Cannot find module '../callable/charge_statements'`.

- [ ] **Step 3: Écrire `charge_statements.ts` (helpers + finalize)**

```ts
/**
 * finalizeChargeRegularization / voidChargeStatement /
 * markChargeStatementAsSent — callables (FEAT-033).
 *
 * Réplique du patron `receipts` (FEAT-007/019) pour un objet légal immuable :
 *   - charge_statement immuable une fois créé (Rules `create,update,delete:
 *     if false`) ;
 *   - PDF rendu côté client à partir des champs figés (pas de PDF/Storage
 *     serveur) ;
 *   - `provisionsCollectedCents` RECALCULÉ serveur (jamais accepté du client)
 *     — preuve infalsifiable (art. 23 loi 6/7/1989, décret 87-713).
 */
import * as admin from "firebase-admin";
import {logger} from "firebase-functions/v2";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {Timestamp} from "firebase-admin/firestore";

import {
  asBag,
  dataOrFail,
  optionalString,
  requireAuthUid,
  requireInt,
  requireString,
  toTimestamp,
} from "../utils/callable_helpers";
import {dbForRequest} from "../utils/db_router";
import {resolveChargeMode} from "./lease_payment";

interface ProvisionPayment {
  chargesAmountCents: number;
  periodStart: Timestamp;
  periodEnd: Timestamp;
}

/**
 * Somme des `chargesAmountCents` des paiements dont la période recouvre (au
 * moins partiellement) `[periodStart, periodEnd]`. Équivalent serveur
 * autoritatif de `sumChargeProvisionsForPeriod` (Dart). Recouvrement
 * d'intervalle : `p.periodStart <= periodEnd && p.periodEnd >= periodStart`.
 */
export function sumProvisionsOverlap(
  payments: ProvisionPayment[],
  periodStart: Timestamp,
  periodEnd: Timestamp,
): number {
  const start = periodStart.toMillis();
  const end = periodEnd.toMillis();
  let total = 0;
  for (const p of payments) {
    const overlaps =
      p.periodStart.toMillis() <= end && p.periodEnd.toMillis() >= start;
    if (overlaps) total += p.chargesAmountCents;
  }
  return total;
}

interface LineItem {
  expenseId: string;
  nature: string;
  notes: string;
  amountCents: number;
  expenseDate: Timestamp;
}

/**
 * Valide et normalise les lignes de détail. Chaque montant ≥ 0 ; la somme
 * doit égaler `actualExpensesCents` (cohérence détail ↔ total). Jette
 * `HttpsError("invalid-argument")` sinon. Retourne les lignes normalisées
 * (dates converties en Timestamp).
 */
export function validateLineItems(
  raw: Array<Record<string, unknown>>,
  actualExpensesCents: number,
): LineItem[] {
  let sum = 0;
  const items: LineItem[] = raw.map((r, i) => {
    const amountCents = requireInt(r.amountCents, `lineItems[${i}].amountCents`);
    if (amountCents < 0) {
      throw new HttpsError(
        "invalid-argument",
        `lineItems[${i}].amountCents must be >= 0`,
      );
    }
    sum += amountCents;
    return {
      expenseId: requireString(r.expenseId, `lineItems[${i}].expenseId`),
      nature: requireString(r.nature, `lineItems[${i}].nature`),
      notes: optionalString(r.notes, `lineItems[${i}].notes`) ?? "",
      amountCents,
      expenseDate: toTimestamp(r.expenseDate, `lineItems[${i}].expenseDate`),
    };
  });
  if (sum !== actualExpensesCents) {
    throw new HttpsError(
      "invalid-argument",
      "lineItems total must equal actualExpensesCents",
      {sum, actualExpensesCents},
    );
  }
  return items;
}

export const finalizeChargeRegularization = onCall(
  {region: "europe-west1"},
  async (request) => {
    const uid = requireAuthUid(request);
    const data = asBag(request.data);

    const leaseId = requireString(data.leaseId, "leaseId");
    const periodStart = toTimestamp(data.periodStart, "periodStart");
    const periodEnd = toTimestamp(data.periodEnd, "periodEnd");
    if (periodEnd.toMillis() <= periodStart.toMillis()) {
      throw new HttpsError("invalid-argument", "periodEnd must be after periodStart");
    }
    const actualExpensesCents = requireInt(data.actualExpensesCents, "actualExpensesCents");
    if (actualExpensesCents < 0) {
      throw new HttpsError("invalid-argument", "actualExpensesCents must be >= 0");
    }
    const source = requireString(data.actualExpensesSource, "actualExpensesSource");
    if (source !== "expenses" && source !== "manual") {
      throw new HttpsError("invalid-argument", "actualExpensesSource must be expenses|manual");
    }
    const rawLineItems = Array.isArray(data.lineItems)
      ? (data.lineItems as Array<Record<string, unknown>>)
      : [];
    const lineItems =
      source === "expenses"
        ? validateLineItems(rawLineItems, actualExpensesCents)
        : [];

    const db = dbForRequest(request);

    // 1. Landlord (champs légaux fullName + address requis, loi 1989)
    const landlordSnap = await db.doc(`landlords/${uid}`).get();
    const landlordData = dataOrFail(landlordSnap, "landlord not found");
    const landlordFullName = String(landlordData.fullName ?? "").trim();
    const landlordAddress = String(landlordData.address ?? "").trim();
    const missing: string[] = [];
    if (landlordFullName.length === 0) missing.push("fullName");
    if (landlordAddress.length === 0) missing.push("address");
    if (missing.length > 0) {
      throw new HttpsError("failed-precondition", "profile_incomplete", {missing});
    }

    // 2. Lease + ownership + gate légal (mode provisions)
    const leaseSnap = await db.doc(`leases/${leaseId}`).get();
    const lease = dataOrFail(leaseSnap, "lease not found");
    if (String(lease.landlordId ?? "") !== uid) {
      throw new HttpsError("permission-denied", "lease not owned");
    }
    if (lease.deletedAt != null) {
      throw new HttpsError("failed-precondition", "lease is deleted");
    }
    const mode = resolveChargeMode(
      String(lease.leaseType ?? ""),
      (lease.chargeMode as string | null | undefined) ?? null,
    );
    if (mode !== "provisions") {
      throw new HttpsError("failed-precondition", "charge_regularization_not_applicable");
    }

    // 3. Provisions RECALCULÉES serveur (autoritatif)
    const paySnap = await db
      .collection("payments")
      .where("landlordId", "==", uid)
      .where("leaseId", "==", leaseId)
      .where("deletedAt", "==", null)
      .get();
    const payments: ProvisionPayment[] = paySnap.docs.map((d) => {
      const p = d.data();
      return {
        chargesAmountCents: Number(p.chargesAmountCents ?? 0),
        periodStart: p.periodStart as Timestamp,
        periodEnd: p.periodEnd as Timestamp,
      };
    });
    const provisionsCollectedCents = sumProvisionsOverlap(payments, periodStart, periodEnd);
    const balanceCents = actualExpensesCents - provisionsCollectedCents;

    // 4. Écriture du snapshot figé (immuable post-create par Rules)
    const ref = db.collection("charge_statements").doc();
    const statementId = ref.id;
    const now = admin.firestore.FieldValue.serverTimestamp();
    try {
      await ref.set({
        id: statementId,
        landlordId: uid,
        leaseId,
        propertyId: String(lease.propertyId ?? ""),
        landlordFullName,
        landlordAddress,
        tenantFullName: `${String(lease.tenantFirstName ?? "")} ${String(lease.tenantLastName ?? "")}`.trim(),
        tenantFirstName: String(lease.tenantFirstName ?? ""),
        propertyName: String(lease.propertyName ?? ""),
        propertyAddress: String(lease.propertyAddress ?? ""),
        periodStart,
        periodEnd,
        provisionsCollectedCents,
        actualExpensesCents,
        actualExpensesSource: source,
        balanceCents,
        lineItems: lineItems.map((li) => ({
          expenseId: li.expenseId,
          nature: li.nature,
          notes: li.notes,
          amountCents: li.amountCents,
          expenseDate: li.expenseDate,
        })),
        createdAt: now,
        isVoided: false,
        voidedAt: null,
        voidedReason: null,
        sentAt: null,
        sentToEmail: null,
        schemaVersion: 1,
      });
    } catch (err) {
      logger.error("charge_statement write failed", {uid, statementId, err});
      throw new HttpsError("internal", "charge_statement_persist_failed");
    }

    const direction =
      balanceCents > 0 ? "dueByTenant" : balanceCents < 0 ? "dueToTenant" : "balanced";
    logger.info("charge statement finalized", {uid, statementId, balanceCents});
    return {statementId, balanceCents, direction};
  },
);
```

- [ ] **Step 4: Ajouter les tests du callable `finalizeChargeRegularization`**

Ajouter au fichier de test (harness `FakeFirestore`, seed via `fakeDb`) — suivre la structure de `functions/src/__tests__/expenses.test.ts` pour seeder landlord + lease + payments, puis :

```ts
describe("finalizeChargeRegularization", () => {
  const OWNER = "landlord-a";
  const iso = (d: string) => `${d}T00:00:00.000Z`;

  function seedBase() {
    fakeDb.doc("landlords/landlord-a").set({fullName: "Jean Bailleur", address: "1 rue A"});
    fakeDb.doc("leases/lease-1").set({
      landlordId: OWNER, propertyId: "prop-1", leaseType: "unfurnished",
      chargeMode: "provisions", tenantFirstName: "Marie", tenantLastName: "Loc",
      propertyName: "Studio", propertyAddress: "2 rue B", deletedAt: null,
    });
    fakeDb.collection("payments").doc("p1").set({
      landlordId: OWNER, leaseId: "lease-1", deletedAt: null,
      chargesAmountCents: 12000,
      periodStart: Timestamp.fromDate(new Date(iso("2025-06-01"))),
      periodEnd: Timestamp.fromDate(new Date(iso("2025-06-30"))),
    });
  }

  it("recalcule provisions serveur et crée le doc figé", async () => {
    seedBase();
    const res: any = await finalizeChargeRegularization(makeRequest(OWNER, {
      leaseId: "lease-1", periodStart: iso("2025-01-01"), periodEnd: iso("2025-12-31"),
      actualExpensesCents: 15000, actualExpensesSource: "manual", lineItems: [],
    }) as any);
    expect(res.balanceCents).toBe(3000); // 15000 - 12000
    expect(res.direction).toBe("dueByTenant");
    const doc = fakeDb.collection("charge_statements").doc(res.statementId).get
      ? await fakeDb.doc(`charge_statements/${res.statementId}`).get() : null;
    expect((await fakeDb.doc(`charge_statements/${res.statementId}`).get()).data()!.provisionsCollectedCents).toBe(12000);
  });

  it("ignore toute valeur de provisions envoyée par le client", async () => {
    seedBase();
    const res: any = await finalizeChargeRegularization(makeRequest(OWNER, {
      leaseId: "lease-1", periodStart: iso("2025-01-01"), periodEnd: iso("2025-12-31"),
      actualExpensesCents: 15000, actualExpensesSource: "manual", lineItems: [],
      provisionsCollectedCents: 999999, // doit être ignoré
    }) as any);
    expect((await fakeDb.doc(`charge_statements/${res.statementId}`).get()).data()!.provisionsCollectedCents).toBe(12000);
  });

  it("refuse un bail non possédé", async () => {
    seedBase();
    await expect(finalizeChargeRegularization(makeRequest("intrus", {
      leaseId: "lease-1", periodStart: iso("2025-01-01"), periodEnd: iso("2025-12-31"),
      actualExpensesCents: 100, actualExpensesSource: "manual", lineItems: [],
    }) as any)).rejects.toThrow(HttpsError);
  });

  it("refuse un bail au forfait (gate légal)", async () => {
    seedBase();
    fakeDb.doc("leases/lease-1").set({
      landlordId: OWNER, propertyId: "prop-1", leaseType: "furnished",
      chargeMode: "forfait", tenantFirstName: "Marie", tenantLastName: "Loc",
      propertyName: "Studio", propertyAddress: "2 rue B", deletedAt: null,
    });
    await expect(finalizeChargeRegularization(makeRequest(OWNER, {
      leaseId: "lease-1", periodStart: iso("2025-01-01"), periodEnd: iso("2025-12-31"),
      actualExpensesCents: 100, actualExpensesSource: "manual", lineItems: [],
    }) as any)).rejects.toThrow(/not_applicable/);
  });

  it("refuse un profil bailleur incomplet", async () => {
    seedBase();
    fakeDb.doc("landlords/landlord-a").set({fullName: "", address: ""});
    await expect(finalizeChargeRegularization(makeRequest(OWNER, {
      leaseId: "lease-1", periodStart: iso("2025-01-01"), periodEnd: iso("2025-12-31"),
      actualExpensesCents: 100, actualExpensesSource: "manual", lineItems: [],
    }) as any)).rejects.toThrow(/profile_incomplete/);
  });
});
```

> Note : adapter la lecture du doc écrit à l'API réelle de `FakeFirestore` (cf. `expenses.test.ts` pour la forme exacte de `.doc().get()` / `.data()`). Ne pas inventer d'API : copier le style du fichier voisin.

- [ ] **Step 5: Exporter dans `index.ts`**

Modifier `functions/src/index.ts`, après le bloc `export { … } from "./callable/receipts";` :

```ts
export {
  finalizeChargeRegularization,
  voidChargeStatement,
  markChargeStatementAsSent,
} from "./callable/charge_statements";
```

> `voidChargeStatement` et `markChargeStatementAsSent` sont ajoutés en Task 2 ; l'export peut être écrit maintenant (le module les exportera). Si TypeScript compile avant Task 2, commenter temporairement les deux lignes non encore définies, ou faire cet export en Task 2. **Choix retenu : n'exporter que `finalizeChargeRegularization` en Task 1**, ajouter les deux autres à l'export en Task 2.

- [ ] **Step 6: Lancer les tests → succès**

Run: `export PATH="/opt/homebrew/bin:$PATH"; cd functions && npx vitest run src/__tests__/charge_statements.test.ts`
Expected: PASS.

- [ ] **Step 7: Lint + commit**

```bash
export PATH="/opt/homebrew/bin:$PATH"; cd functions && npm run lint
cd .. && git add functions/src/callable/charge_statements.ts functions/src/__tests__/charge_statements.test.ts functions/src/index.ts
git commit -m "feat(functions): finalizeChargeRegularization — snapshot figé (FEAT-033)"
```

---

## Task 2 — Callables `voidChargeStatement` + `markChargeStatementAsSent`

**Files:**
- Modify: `functions/src/callable/charge_statements.ts`
- Modify: `functions/src/index.ts`
- Test: `functions/src/__tests__/charge_statements.test.ts`

**Interfaces:**
- Produces : `voidChargeStatement` (params `statementId`, `reason`) → `{voided: true}` ; `markChargeStatementAsSent` (params `statementId`, `email?`) → `{marked: true}`.

- [ ] **Step 1: Tests (échouants)**

```ts
describe("voidChargeStatement / markChargeStatementAsSent", () => {
  const OWNER = "landlord-a";
  function seedStatement(over: Record<string, unknown> = {}) {
    fakeDb.doc("charge_statements/cs-1").set({
      id: "cs-1", landlordId: OWNER, isVoided: false, voidedAt: null,
      voidedReason: null, sentAt: null, sentToEmail: null, ...over,
    });
  }

  it("void pose les flags, non destructif, idempotent", async () => {
    seedStatement();
    await voidChargeStatement(makeRequest(OWNER, {statementId: "cs-1", reason: "erreur montant"}) as any);
    let d = (await fakeDb.doc("charge_statements/cs-1").get()).data()!;
    expect(d.isVoided).toBe(true);
    expect(d.voidedReason).toBe("erreur montant");
    // idempotent : second appel ne jette pas
    await voidChargeStatement(makeRequest(OWNER, {statementId: "cs-1", reason: "x"}) as any);
  });

  it("void refuse un non-propriétaire", async () => {
    seedStatement();
    await expect(voidChargeStatement(makeRequest("intrus", {statementId: "cs-1", reason: "x"}) as any))
      .rejects.toThrow(HttpsError);
  });

  it("markAsSent pose sentAt et sentToEmail", async () => {
    seedStatement();
    await markChargeStatementAsSent(makeRequest(OWNER, {statementId: "cs-1", email: "loc@ex.fr"}) as any);
    const d = (await fakeDb.doc("charge_statements/cs-1").get()).data()!;
    expect(d.sentToEmail).toBe("loc@ex.fr");
    expect(d.sentAt).not.toBeNull();
  });

  it("markAsSent refuse un décompte annulé", async () => {
    seedStatement({isVoided: true});
    await expect(markChargeStatementAsSent(makeRequest(OWNER, {statementId: "cs-1"}) as any))
      .rejects.toThrow(/voided/);
  });
});
```

Ajouter les imports `voidChargeStatement, markChargeStatementAsSent` à l'import existant du module.

- [ ] **Step 2: Lancer → échec** (`voidChargeStatement is not a function`).

Run: `export PATH="/opt/homebrew/bin:$PATH"; cd functions && npx vitest run src/__tests__/charge_statements.test.ts`

- [ ] **Step 3: Implémenter les deux callables** (append à `charge_statements.ts`) — miroir exact de `voidReceipt`/`markReceiptAsSent` (`functions/src/callable/receipts.ts`) :

```ts
export const voidChargeStatement = onCall(
  {region: "europe-west1"},
  async (request) => {
    const uid = requireAuthUid(request);
    const data = asBag(request.data);
    const statementId = requireString(data.statementId, "statementId");
    const reason = requireString(data.reason, "reason");

    const db = dbForRequest(request);
    const ref = db.doc(`charge_statements/${statementId}`);
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const s = dataOrFail(snap, "charge statement not found");
      if (s.landlordId !== uid) {
        throw new HttpsError("permission-denied", "not owner");
      }
      if (s.isVoided === true) return; // idempotent
      tx.update(ref, {
        isVoided: true,
        voidedAt: admin.firestore.FieldValue.serverTimestamp(),
        voidedReason: reason,
      });
    });
    return {voided: true};
  },
);

export const markChargeStatementAsSent = onCall(
  {region: "europe-west1"},
  async (request) => {
    const uid = requireAuthUid(request);
    const data = asBag(request.data);
    const statementId = requireString(data.statementId, "statementId");
    const email = optionalString(data.email, "email");

    const db = dbForRequest(request);
    const ref = db.doc(`charge_statements/${statementId}`);
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const s = dataOrFail(snap, "charge statement not found");
      if (s.landlordId !== uid) {
        throw new HttpsError("permission-denied", "not owner");
      }
      if (s.isVoided === true) {
        throw new HttpsError("failed-precondition", "cannot mark a voided statement as sent");
      }
      tx.update(ref, {
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
        sentToEmail: email,
      });
    });
    return {marked: true};
  },
);
```

- [ ] **Step 4: Compléter l'export `index.ts`** — remettre les 3 noms dans le bloc `export { … } from "./callable/charge_statements";`.

- [ ] **Step 5: Lancer → succès.**

Run: `export PATH="/opt/homebrew/bin:$PATH"; cd functions && npx vitest run src/__tests__/charge_statements.test.ts`

- [ ] **Step 6: Lint + commit**

```bash
export PATH="/opt/homebrew/bin:$PATH"; cd functions && npm run lint
cd .. && git add functions/src/callable/charge_statements.ts functions/src/__tests__/charge_statements.test.ts functions/src/index.ts
git commit -m "feat(functions): void + markAsSent charge_statement (FEAT-033)"
```

---

## Task 3 — Firestore Rules + rules-tests

**Files:**
- Modify: `firestore.rules`
- Test: `functions/rules-tests/firestore_rules.test.ts`

**Interfaces:**
- Consumes : helpers Rules existants `isOwner(landlordId)`, `isFullyAuthed()`.

- [ ] **Step 1: Ajouter les tests rules (échouants)**

Dans `functions/rules-tests/firestore_rules.test.ts` : ajouter `"charge_statements"` à la constante `LANDLORD_SCOPED_COLLECTIONS` (le seed Admin crée alors automatiquement `charge_statements/doc-a` pour landlord A). Puis ajouter un bloc :

```ts
describe("charge_statements — immuables & owner-scoped (FEAT-033)", () => {
  it("le propriétaire lit son décompte", async () => {
    await assertSucceeds(asOwnerA().doc("charge_statements/doc-a").get());
  });
  it("un autre compte ne lit pas le décompte d'autrui", async () => {
    await assertFails(asOtherB().doc("charge_statements/doc-a").get());
  });
  it("un autre compte ne peut lister les décomptes d'un UID orphelin", async () => {
    await assertFails(
      asOtherB().collection("charge_statements").where("landlordId", "==", "deleted-account-uid").get(),
    );
  });
  it("le client ne peut PAS créer un décompte (CF exclusive)", async () => {
    await assertFails(
      asOwnerA().collection("charge_statements").add({landlordId: LANDLORD_A}),
    );
  });
  it("le client ne peut PAS modifier ni supprimer un décompte", async () => {
    await assertFails(asOwnerA().doc("charge_statements/doc-a").update({balanceCents: 0}));
    await assertFails(asOwnerA().doc("charge_statements/doc-a").delete());
  });
});
```

> `asOwnerA()`, `asOtherB()`, `LANDLORD_A`, `assertSucceeds`, `assertFails` existent déjà dans ce fichier — les réutiliser tels quels.

- [ ] **Step 2: Lancer → échec** (create autorisé faute de règle, ou get refusé faute de match).

Run: `export PATH="/opt/homebrew/bin:$PATH"; cd functions && npm run test:rules`

- [ ] **Step 3: Ajouter le bloc dans `firestore.rules`** — juste après le bloc `match /receipts/{id}` :

```
    // ====================================================================
    // charge_statements/{id} — IMMUABLES (loi 6 juillet 1989) → CF exclusive
    //
    // Décompte de régularisation figé (FEAT-033). Pas de soft-delete
    // (rétention 5 ans). Les décomptes annulés (isVoided) restent lisibles
    // pour audit. Owner-scoped en get ET list (mêmes garanties que receipts :
    // les décomptes d'un compte supprimé restent conservés et ne doivent
    // résoudre pour personne).
    // ====================================================================
    match /charge_statements/{id} {
      allow get:  if isOwner(resource.data.landlordId);
      allow list: if isOwner(resource.data.landlordId);
      // finalize / void / markAsSent en Callable.
      allow create, update, delete: if false;
    }
```

- [ ] **Step 4: Lancer → succès.**

Run: `export PATH="/opt/homebrew/bin:$PATH"; cd functions && npm run test:rules`

- [ ] **Step 5: Commit**

```bash
git add firestore.rules functions/rules-tests/firestore_rules.test.ts
git commit -m "feat(rules): charge_statements immuables owner-scoped (FEAT-033)"
```

---

## Task 4 — Index Firestore + export RGPD

**Files:**
- Modify: `firestore.indexes.json`
- Modify: `functions/src/callable/export_account_data.ts`
- Test: `functions/src/__tests__/export_account_data.test.ts` (s'il existe ; sinon vérification manuelle décrite ci-dessous)

**Interfaces:**
- Consumes : `EXPORTED_COLLECTIONS` (map clé→collection) dans `export_account_data.ts`.

- [ ] **Step 1: Ajouter l'index composite**

Dans `firestore.indexes.json`, ajouter à la liste `indexes` (miroir du 1er index `receipts`, mais trié sur `createdAt`) :

```json
{
  "collectionGroup": "charge_statements",
  "queryScope": "COLLECTION",
  "fields": [
    {"fieldPath": "landlordId", "order": "ASCENDING"},
    {"fieldPath": "leaseId", "order": "ASCENDING"},
    {"fieldPath": "createdAt", "order": "DESCENDING"}
  ]
}
```

- [ ] **Step 2: Vérifier la validité JSON**

Run: `export PATH="/opt/homebrew/bin:$PATH"; python3 -c "import json; json.load(open('firestore.indexes.json')); print('OK')"`
Expected: `OK`.

- [ ] **Step 3: Ajouter la collection à l'export RGPD**

Dans `functions/src/callable/export_account_data.ts`, dans `EXPORTED_COLLECTIONS`, ajouter la ligne (après `receipts: "receipts",`) :

```ts
  chargeStatements: "charge_statements",
```

- [ ] **Step 4: Test export (si un fichier de test existe)**

Run: `export PATH="/opt/homebrew/bin:$PATH"; cd functions && ls src/__tests__/ | grep export_account_data && npx vitest run src/__tests__/export_account_data.test.ts`

Si un test existe et vérifie la liste des clés exportées, ajouter `chargeStatements` à l'attendu ; sinon, vérifier que `npm run build` compile sans erreur :

Run: `export PATH="/opt/homebrew/bin:$PATH"; cd functions && npm run build`
Expected: build OK.

- [ ] **Step 5: Commit**

```bash
git add firestore.indexes.json functions/src/callable/export_account_data.ts
git commit -m "feat: index charge_statements + export RGPD (FEAT-033)"
```

---

## Task 5 — Modèle Dart `ChargeStatement`

**Files:**
- Create: `lib/features/charge_regularization/domain/charge_statement.dart`
- Create: `lib/features/charge_regularization/domain/charge_statement_line_item.dart`
- Test: `test/unit/charge_statement_test.dart`

**Interfaces:**
- Consumes : `ChargeRegularizationBalanceDirection` (enum existant, `domain/charge_regularization_balance.dart`) ; `firestoreDocToSnakeJson` (`core/firestore_helpers.dart`) pour le mapping snake_case → model côté repository (Task 6).
- Produces : classe `ChargeStatement` (freezed, `fromJson`), getter `direction`, `balanceAbsCents`, `labelFr`, `hasLineItems` ; classe `ChargeStatementLineItem`.

Le projet utilise freezed + json_serializable pour les modèles Firestore relus en snake_case (cf. `expense.dart`). Suivre exactement ce patron.

- [ ] **Step 1: Écrire le test (échouant)**

```dart
import 'package:easyrent/features/charge_regularization/domain/charge_statement.dart';
import 'package:easyrent/features/charge_regularization/domain/charge_regularization_balance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> baseJson() => {
    'id': 'cs-1',
    'landlord_id': 'lord1',
    'lease_id': 'l1',
    'property_id': 'p1',
    'landlord_full_name': 'Jean Bailleur',
    'landlord_address': '1 rue A',
    'tenant_full_name': 'Marie Loc',
    'tenant_first_name': 'Marie',
    'property_name': 'Studio',
    'property_address': '2 rue B',
    'period_start': '2025-01-01T00:00:00.000Z',
    'period_end': '2025-12-31T00:00:00.000Z',
    'provisions_collected_cents': 12000,
    'actual_expenses_cents': 15000,
    'actual_expenses_source': 'manual',
    'balance_cents': 3000,
    'line_items': <dynamic>[],
    'created_at': '2026-01-05T10:00:00.000Z',
    'is_voided': false,
    'voided_at': null,
    'voided_reason': null,
    'sent_at': null,
    'sent_to_email': null,
    'schema_version': 1,
  };

  test('fromJson mappe les champs snake_case', () {
    final s = ChargeStatement.fromJson(baseJson());
    expect(s.id, 'cs-1');
    expect(s.provisionsCollectedCents, 12000);
    expect(s.actualExpensesCents, 15000);
    expect(s.balanceCents, 3000);
    expect(s.isVoided, isFalse);
    expect(s.hasLineItems, isFalse);
  });

  test('direction dérivée du solde signé', () {
    expect(ChargeStatement.fromJson(baseJson()).direction,
        ChargeRegularizationBalanceDirection.dueByTenant);
    expect(ChargeStatement.fromJson({...baseJson(), 'balance_cents': -500}).direction,
        ChargeRegularizationBalanceDirection.dueToTenant);
    expect(ChargeStatement.fromJson({...baseJson(), 'balance_cents': 0}).direction,
        ChargeRegularizationBalanceDirection.balanced);
  });

  test('balanceAbsCents toujours positif', () {
    expect(ChargeStatement.fromJson({...baseJson(), 'balance_cents': -500}).balanceAbsCents, 500);
  });

  test('line_items désérialisés', () {
    final s = ChargeStatement.fromJson({...baseJson(), 'actual_expenses_source': 'expenses', 'line_items': [
      {'expense_id': 'e1', 'nature': 'condo_charges', 'notes': 'T1', 'amount_cents': 15000,
       'expense_date': '2025-06-01T00:00:00.000Z'},
    ]});
    expect(s.hasLineItems, isTrue);
    expect(s.lineItems.single.amountCents, 15000);
    expect(s.lineItems.single.nature, 'condo_charges');
  });
}
```

- [ ] **Step 2: Lancer → échec** (modèle absent).

Run: `export PATH="/opt/homebrew/bin:$PATH"; flutter test test/unit/charge_statement_test.dart`

- [ ] **Step 3: Écrire `charge_statement_line_item.dart`**

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'charge_statement_line_item.freezed.dart';
part 'charge_statement_line_item.g.dart';

/// Ligne de détail figée d'un décompte de régularisation (FEAT-033).
///
/// Copie figée d'une Dépense récupérable au moment du finalize — ne
/// référence PAS la Dépense vivante. `nature` porte la valeur SQL de
/// `ExpenseNature` (rendue via `expense_nature_l10n.dart` à l'affichage) ;
/// `notes` est le libellé libre saisi par le bailleur (peut être vide).
@freezed
class ChargeStatementLineItem with _$ChargeStatementLineItem {
  const factory ChargeStatementLineItem({
    @JsonKey(name: 'expense_id') required String expenseId,
    required String nature,
    @Default('') String notes,
    @JsonKey(name: 'amount_cents') required int amountCents,
    @JsonKey(name: 'expense_date') required DateTime expenseDate,
  }) = _ChargeStatementLineItem;

  factory ChargeStatementLineItem.fromJson(Map<String, dynamic> json) =>
      _$ChargeStatementLineItemFromJson(json);
}
```

- [ ] **Step 4: Écrire `charge_statement.dart`**

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

import 'charge_regularization_balance.dart';
import 'charge_statement_line_item.dart';

part 'charge_statement.freezed.dart';
part 'charge_statement.g.dart';

/// Décompte de régularisation de charges figé et immuable (FEAT-033).
///
/// Snapshot légal (art. 23 loi 6/7/1989) créé par la callable
/// `finalizeChargeRegularization` — reproductible à l'identique, jamais
/// re-synchronisé même si les Dépenses ou paiements sources changent. Miroir
/// du modèle `Receipt`. Le PDF est rendu côté client à partir de ces champs
/// figés (aucun PDF serveur).
@freezed
class ChargeStatement with _$ChargeStatement {
  const ChargeStatement._();

  const factory ChargeStatement({
    required String id,
    @JsonKey(name: 'landlord_id') required String landlordId,
    @JsonKey(name: 'lease_id') required String leaseId,
    @JsonKey(name: 'property_id') required String propertyId,
    @JsonKey(name: 'landlord_full_name') required String landlordFullName,
    @JsonKey(name: 'landlord_address') required String landlordAddress,
    @JsonKey(name: 'tenant_full_name') required String tenantFullName,
    @JsonKey(name: 'tenant_first_name') required String tenantFirstName,
    @JsonKey(name: 'property_name') required String propertyName,
    @JsonKey(name: 'property_address') required String propertyAddress,
    @JsonKey(name: 'period_start') required DateTime periodStart,
    @JsonKey(name: 'period_end') required DateTime periodEnd,
    @JsonKey(name: 'provisions_collected_cents') required int provisionsCollectedCents,
    @JsonKey(name: 'actual_expenses_cents') required int actualExpensesCents,
    @JsonKey(name: 'actual_expenses_source') required String actualExpensesSource,
    @JsonKey(name: 'balance_cents') required int balanceCents,
    @JsonKey(name: 'line_items') @Default(<ChargeStatementLineItem>[])
    List<ChargeStatementLineItem> lineItems,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'is_voided') @Default(false) bool isVoided,
    @JsonKey(name: 'voided_at') DateTime? voidedAt,
    @JsonKey(name: 'voided_reason') String? voidedReason,
    @JsonKey(name: 'sent_at') DateTime? sentAt,
    @JsonKey(name: 'sent_to_email') String? sentToEmail,
    @JsonKey(name: 'schema_version') @Default(1) int schemaVersion,
  }) = _ChargeStatement;

  factory ChargeStatement.fromJson(Map<String, dynamic> json) =>
      _$ChargeStatementFromJson(json);

  bool get hasLineItems => lineItems.isNotEmpty;
  bool get isSent => sentAt != null;

  int get balanceAbsCents => balanceCents.abs();

  /// Sens du solde, dérivé du signe (source de vérité unique = balanceCents).
  ChargeRegularizationBalanceDirection get direction {
    if (balanceCents > 0) return ChargeRegularizationBalanceDirection.dueByTenant;
    if (balanceCents < 0) return ChargeRegularizationBalanceDirection.dueToTenant;
    return ChargeRegularizationBalanceDirection.balanced;
  }

  String get labelFr => direction.labelFr;
}
```

- [ ] **Step 5: Générer le code freezed/json**

Run: `export PATH="/opt/homebrew/bin:$PATH"; dart run build_runner build --delete-conflicting-outputs`
Expected: génère `.freezed.dart` + `.g.dart`.

- [ ] **Step 6: Lancer → succès.**

Run: `export PATH="/opt/homebrew/bin:$PATH"; flutter test test/unit/charge_statement_test.dart`

- [ ] **Step 7: Commit**

```bash
export PATH="/opt/homebrew/bin:$PATH"; dart format lib/features/charge_regularization/domain/ test/unit/charge_statement_test.dart
git add lib/features/charge_regularization/domain/charge_statement.dart lib/features/charge_regularization/domain/charge_statement_line_item.dart test/unit/charge_statement_test.dart
# fichiers .freezed.dart/.g.dart sont gitignorés (générés en build) — ne pas les add
git commit -m "feat(charge): modèle ChargeStatement figé (FEAT-033)"
```

> Vérifier `.gitignore` : si les `*.g.dart`/`*.freezed.dart` NE sont PAS ignorés dans ce repo (certains projets les committent), les ajouter au commit. Regarder comment `expense.g.dart` est traité (`git ls-files lib/features/expenses/domain/expense.g.dart`) et faire pareil.

---

## Task 6 — Repository `ChargeStatementRepository` + provider

**Files:**
- Create: `lib/features/charge_regularization/data/charge_statement_repository.dart`
- Test: `test/unit/charge_statement_repository_test.dart`

**Interfaces:**
- Consumes : `firestoreProvider` (`core/config/firestore_provider.dart`), `firestoreDocToSnakeJson` (`core/firestore_helpers.dart`), `ChargeStatement` (Task 5), `FirebaseFunctions`, `FirebaseAuth`.
- Produces : interface `ChargeStatementRepository` avec `listForLease(String leaseId) → Future<List<ChargeStatement>>`, `getById(String id) → Future<ChargeStatement>`, `finalize({...}) → Future<ChargeStatementFinalizeResult>`, `voidStatement(String id, String reason) → Future<void>`, `markAsSent({required String id, String? email}) → Future<void>` ; classe `ChargeStatementFinalizeResult({statementId, balanceCents, direction})` ; `chargeStatementRepositoryProvider`.

Suivre le patron exact de `lib/features/receipts/data/receipts_repository.dart` (abstract interface + impl Firestore, `_col`, `_callable`, `firestoreDocToSnakeJson`).

- [ ] **Step 1: Écrire le test (échouant)** — tester le mapping de `listForLease` avec un `FakeFirebaseFirestore` (package `fake_cloud_firestore`, déjà utilisé dans le repo — vérifier `grep -rl fake_cloud_firestore test/`). Exemple minimal :

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easyrent/features/charge_regularization/data/charge_statement_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('listForLease relit et mappe, ordonné createdAt desc', () async {
    final fs = FakeFirebaseFirestore();
    await fs.collection('charge_statements').doc('cs-1').set({
      'id': 'cs-1', 'landlordId': 'lord1', 'leaseId': 'l1', 'propertyId': 'p1',
      'landlordFullName': 'J', 'landlordAddress': 'A', 'tenantFullName': 'M Loc',
      'tenantFirstName': 'M', 'propertyName': 'S', 'propertyAddress': 'B',
      'periodStart': Timestamp.fromDate(DateTime.utc(2025, 1, 1)),
      'periodEnd': Timestamp.fromDate(DateTime.utc(2025, 12, 31)),
      'provisionsCollectedCents': 12000, 'actualExpensesCents': 15000,
      'actualExpensesSource': 'manual', 'balanceCents': 3000, 'lineItems': [],
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 5)),
      'isVoided': false, 'voidedAt': null, 'voidedReason': null,
      'sentAt': null, 'sentToEmail': null, 'schemaVersion': 1,
    });
    final auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'lord1'));
    final repo = FirestoreChargeStatementRepository(fs, auth, /* functions */ null);
    final list = await repo.listForLease('l1');
    expect(list, hasLength(1));
    expect(list.single.balanceCents, 3000);
  });
}
```

> Adapter aux mocks réellement disponibles dans le repo (`grep -rn "MockFirebaseAuth\|FakeFirebaseFirestore\|firebase_auth_mocks" test/ pubspec.yaml`). Si le repo teste les repositories différemment (ex. sans mock functions), suivre le patron du test de `receipts_repository` s'il existe (`find test -name '*receipt*repository*'`). Les callables (`finalize`/`void`/`markAsSent`) ne sont pas testés unitairement ici (nécessitent un mock `FirebaseFunctions`) — leur logique vit côté serveur (Tasks 1-2) ; ne tester que la lecture/mapping.

- [ ] **Step 2: Lancer → échec.**

Run: `export PATH="/opt/homebrew/bin:$PATH"; flutter test test/unit/charge_statement_repository_test.dart`

- [ ] **Step 3: Écrire le repository** (patron `receipts_repository.dart`) :

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../core/config/firestore_provider.dart';
import '../../../core/firestore_helpers.dart';
import '../domain/charge_statement.dart';

final _log = Logger('ChargeStatementRepository');

class ChargeStatementFinalizeResult {
  const ChargeStatementFinalizeResult({
    required this.statementId,
    required this.balanceCents,
    required this.direction,
  });
  final String statementId;
  final int balanceCents;
  final String direction; // 'dueByTenant' | 'dueToTenant' | 'balanced'
}

abstract interface class ChargeStatementRepository {
  Future<List<ChargeStatement>> listForLease(String leaseId);
  Future<ChargeStatement> getById(String id);
  Future<ChargeStatementFinalizeResult> finalize({
    required String leaseId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required int actualExpensesCents,
    required String actualExpensesSource, // 'expenses' | 'manual'
    required List<Map<String, dynamic>> lineItems,
  });
  Future<void> voidStatement(String id, String reason);
  Future<void> markAsSent({required String id, String? email});
}

class FirestoreChargeStatementRepository implements ChargeStatementRepository {
  FirestoreChargeStatementRepository(this._firestore, this._auth, this._functions);
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw StateError('Not authenticated — charge statement ops require auth');
    }
    return uid;
  }

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection('charge_statements');

  HttpsCallable _callable(String name) => _functions.httpsCallable(
        name,
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );

  @override
  Future<List<ChargeStatement>> listForLease(String leaseId) async {
    final qs = await _col
        .where('landlordId', isEqualTo: _uid)
        .where('leaseId', isEqualTo: leaseId)
        .orderBy('createdAt', descending: true)
        .limit(200)
        .get();
    return qs.docs
        .map((d) => ChargeStatement.fromJson(firestoreDocToSnakeJson(d.data(), docId: d.id)))
        .toList();
  }

  @override
  Future<ChargeStatement> getById(String id) async {
    final snap = await _col.doc(id).get();
    final data = snap.data();
    if (!snap.exists || data == null || data['landlordId'] != _uid) {
      throw StateError('charge statement not found: $id');
    }
    return ChargeStatement.fromJson(firestoreDocToSnakeJson(data, docId: snap.id));
  }

  @override
  Future<ChargeStatementFinalizeResult> finalize({
    required String leaseId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required int actualExpensesCents,
    required String actualExpensesSource,
    required List<Map<String, dynamic>> lineItems,
  }) async {
    final res = await _callable('finalizeChargeRegularization').call(<String, dynamic>{
      'leaseId': leaseId,
      'periodStart': periodStart.toUtc().toIso8601String(),
      'periodEnd': periodEnd.toUtc().toIso8601String(),
      'actualExpensesCents': actualExpensesCents,
      'actualExpensesSource': actualExpensesSource,
      'lineItems': lineItems,
    });
    final data = (res.data as Map?) ?? const {};
    final statementId = data['statementId'] as String?;
    if (statementId == null) {
      throw StateError('finalizeChargeRegularization did not return a statementId');
    }
    _log.info('charge statement finalized: $statementId');
    return ChargeStatementFinalizeResult(
      statementId: statementId,
      balanceCents: (data['balanceCents'] as int?) ?? 0,
      direction: (data['direction'] as String?) ?? 'balanced',
    );
  }

  @override
  Future<void> voidStatement(String id, String reason) async {
    await _callable('voidChargeStatement').call(<String, dynamic>{
      'statementId': id, 'reason': reason,
    });
  }

  @override
  Future<void> markAsSent({required String id, String? email}) async {
    await _callable('markChargeStatementAsSent').call(<String, dynamic>{
      'statementId': id, 'email': ?email,
    });
  }
}

final chargeStatementRepositoryProvider = Provider<ChargeStatementRepository>((ref) {
  return FirestoreChargeStatementRepository(
    ref.read(firestoreProvider),
    FirebaseAuth.instance,
    FirebaseFunctions.instanceFor(region: 'europe-west1'),
  );
});
```

> `FirebaseFunctions.instanceFor(region: 'europe-west1')` : reprendre exactement la façon dont `receipts_repository.dart` / son provider obtient `FirebaseFunctions` (région, éventuel provider dédié). Aligner sur l'existant, ne pas diverger.

- [ ] **Step 4: Générer + lancer → succès.**

Run: `export PATH="/opt/homebrew/bin:$PATH"; flutter test test/unit/charge_statement_repository_test.dart`

- [ ] **Step 5: Commit**

```bash
export PATH="/opt/homebrew/bin:$PATH"; dart format lib/features/charge_regularization/data/ test/unit/charge_statement_repository_test.dart
git add lib/features/charge_regularization/data/charge_statement_repository.dart test/unit/charge_statement_repository_test.dart
git commit -m "feat(charge): repository ChargeStatement + provider (FEAT-033)"
```

---

## Task 7 — PDF depuis snapshot figé + contrôleur de finalisation

**Files:**
- Modify: `lib/features/charge_regularization/domain/charge_regularization_pdf_renderer.dart`
- Create: `lib/features/charge_regularization/application/charge_statement_finalize_controller.dart`
- Test: `test/unit/charge_statement_finalize_controller_test.dart`

**Interfaces:**
- Consumes : `ChargeStatement` (Task 5), `ChargeStatementRepository` (Task 6), `ChargeRegularizationBalance` + renderer existant, `WebShareService` (`receipts/data/web_share_service_bridge.dart`), `ChargeRegularizationSharePayloadBuilder`.
- Produces : `ChargeRegularizationPdfData.fromStatement(ChargeStatement)` ; contrôleur `ChargeStatementFinalizeController` (StateNotifier) exposant `finalizeAndShare({...})` et re-share `shareExisting(ChargeStatement)`.

- [ ] **Step 1: Test du helper `fromStatement` (échouant)**

```dart
import 'package:easyrent/features/charge_regularization/domain/charge_regularization_pdf_renderer.dart';
import 'package:easyrent/features/charge_regularization/domain/charge_statement.dart';
import 'package:flutter_test/flutter_test.dart';
// … réutiliser le helper baseJson() du test Task 5 (ou dupliquer localement).

void main() {
  test('fromStatement construit un PdfData depuis les champs figés', () {
    final s = ChargeStatement.fromJson(/* baseJson() */);
    final d = ChargeRegularizationPdfData.fromStatement(s);
    expect(d.landlordFullName, s.landlordFullName);
    expect(d.propertyAddress, s.propertyAddress);
    expect(d.balance.provisionsCollectedCents, s.provisionsCollectedCents);
    expect(d.balance.actualExpensesCents, s.actualExpensesCents);
    expect(d.generatedAt, s.createdAt); // le PDF re-rendu reflète la date de finalisation figée
  });
}
```

- [ ] **Step 2: Lancer → échec** (`fromStatement` absent).

Run: `export PATH="/opt/homebrew/bin:$PATH"; flutter test test/unit/charge_statement_finalize_controller_test.dart`

- [ ] **Step 3: Ajouter `fromStatement`** dans `charge_regularization_pdf_renderer.dart` (factory sur `ChargeRegularizationPdfData`) :

```dart
  /// Construit les données PDF à partir d'un décompte figé (FEAT-033) — le
  /// PDF re-rendu est identique à celui émis lors de la finalisation.
  factory ChargeRegularizationPdfData.fromStatement(ChargeStatement s) {
    return ChargeRegularizationPdfData(
      landlordFullName: s.landlordFullName,
      landlordAddress: s.landlordAddress,
      tenantFullName: s.tenantFullName,
      propertyAddress: s.propertyAddress,
      balance: ChargeRegularizationBalance(
        periodStart: s.periodStart,
        periodEnd: s.periodEnd,
        provisionsCollectedCents: s.provisionsCollectedCents,
        actualExpensesCents: s.actualExpensesCents,
      ),
      generatedAt: s.createdAt,
    );
  }
```

Ajouter les imports `charge_statement.dart` + `charge_regularization_balance.dart` en tête du fichier.

- [ ] **Step 4: Écrire le contrôleur de finalisation**

`ChargeStatementFinalizeController` réutilise la mécanique de partage de `charge_regularization_share_controller.dart` (états preparing/shared/error, `WebShareService`, payload builder) mais insère l'appel `finalize` AVANT le rendu, puis `markAsSent` après un partage réussi. Reprendre l'état freezed existant `ChargeRegularizationShareState` si réutilisable, sinon un état simple. Structure :

```dart
// finalizeAndShare :
// 1. state = preparing
// 2. result = await repo.finalize(leaseId, period, actualExpensesCents, source, lineItems)
// 3. statement = await repo.getById(result.statementId)   // relit le doc figé
// 4. pdfBytes = await renderChargeRegularizationPdf(ChargeRegularizationPdfData.fromStatement(statement))
// 5. payload = ChargeRegularizationSharePayloadBuilder.build(balance: <depuis statement>, ...)
// 6. partage via WebShareService (même branche canShareFiles / fallback que le contrôleur existant)
// 7. sur succès du partage : await repo.markAsSent(id: statement.id, email: tenantEmail)
// 8. state = shared
// Gérer ShareAbortedException (retour idle sans markAsSent), erreurs → state error.
//
// shareExisting(ChargeStatement s) : re-rend depuis le figé (étapes 4-7) sans
// re-finaliser — utilisé par l'historique (re-partage d'un décompte existant).
```

Écrire le contrôleur complet en s'appuyant sur `charge_regularization_share_controller.dart` comme référence directe (copier la logique de partage `WebShareService`, adapter les entrées).

- [ ] **Step 5: Test du contrôleur** — tester le happy path avec un `ChargeStatementRepository` factice (fake in-memory implémentant l'interface) : vérifier l'ordre finalize → getById → markAsSent et la transition d'état vers `shared`. Ne pas tester le rendu PDF réel (lourd) : injecter/mocker le renderer si le contrôleur le permet, ou vérifier au minimum que `finalize` et `markAsSent` sont appelés une fois chacun sur le repo factice. Suivre le style des tests de contrôleurs existants (`grep -rln StateNotifier test/`).

- [ ] **Step 6: Lancer → succès.**

Run: `export PATH="/opt/homebrew/bin:$PATH"; flutter test test/unit/charge_statement_finalize_controller_test.dart`

- [ ] **Step 7: Commit**

```bash
export PATH="/opt/homebrew/bin:$PATH"; dart format lib/features/charge_regularization/ test/unit/charge_statement_finalize_controller_test.dart
git add lib/features/charge_regularization/domain/charge_regularization_pdf_renderer.dart lib/features/charge_regularization/application/charge_statement_finalize_controller.dart test/unit/charge_statement_finalize_controller_test.dart
git commit -m "feat(charge): PDF depuis snapshot figé + contrôleur finalisation (FEAT-033)"
```

---

## Task 8 — UI : action « Finaliser & figer » dans le dialog

**Files:**
- Modify: `lib/features/charge_regularization/presentation/widgets/charge_regularization_dialog.dart`
- Modify: `lib/l10n/app_fr.arb`, `lib/l10n/app_en.arb`
- Test: `test/l10n/arb_parity_test.dart` (déjà présent — doit rester vert)

**Interfaces:**
- Consumes : `ChargeStatementFinalizeController` (Task 7), le solde calculé et les `lineItems` déjà présents dans le dialog (via `filterRecoverableExpensesForPeriod`).

Le dialog calcule déjà `ChargeRegularizationBalance` (provisions pré-remplies + dépenses réelles). Aujourd'hui il propose « générer & partager » (volatile). On remplace/complète cette action par **« Finaliser & figer le décompte »** qui appelle `finalizeAndShare`.

- [ ] **Step 1: Ajouter les clés i18n** dans `app_en.arb` (template, avec `@description`) puis `app_fr.arb` :

```json
// app_en.arb
"chargeStatementFinalizeAction": "Finalize & lock the statement",
"@chargeStatementFinalizeAction": {"description": "Button that persists the immutable charge regularization statement then shares it"},
"chargeStatementFinalizeConfirmTitle": "Lock this statement?",
"@chargeStatementFinalizeConfirmTitle": {"description": "Confirmation dialog title before finalizing a charge statement"},
"chargeStatementFinalizeConfirmBody": "Once locked, this statement is immutable and kept for 5 years (legal proof). You can void and reissue it if needed.",
"@chargeStatementFinalizeConfirmBody": {"description": "Confirmation dialog body explaining immutability before finalizing"}
```

```json
// app_fr.arb
"chargeStatementFinalizeAction": "Finaliser & figer le décompte",
"chargeStatementFinalizeConfirmTitle": "Figer ce décompte ?",
"chargeStatementFinalizeConfirmBody": "Une fois figé, ce décompte est immuable et conservé 5 ans (preuve légale). Vous pourrez l'annuler et le réémettre si besoin."
```

- [ ] **Step 2: Régénérer l10n + vérifier la parité**

Run: `export PATH="/opt/homebrew/bin:$PATH"; flutter gen-l10n && flutter test test/l10n/arb_parity_test.dart`
Expected: PASS.

- [ ] **Step 3: Câbler l'action** dans `charge_regularization_dialog.dart` : bouton `chargeStatementFinalizeAction` → confirmation (title/body ci-dessus) → appel `finalizeAndShare` du contrôleur (Task 7) avec `leaseId`, période, `actualExpensesCents`, `actualExpensesSource` (`'expenses'` si le total vient de l'agrégation des dépenses, `'manual'` si le bailleur a saisi/ajusté), et `lineItems` construits depuis `filterRecoverableExpensesForPeriod(...)` :

```dart
// Construction des lineItems (source == 'expenses') :
final lineItems = recoverableExpenses.map((e) => <String, dynamic>{
  'expenseId': e.id,
  'nature': e.nature.sqlValue,
  'notes': e.notes ?? '',
  'amountCents': e.amountCents,
  'expenseDate': e.expenseDate.toUtc().toIso8601String(),
}).toList();
// Si le bailleur a ajusté manuellement le total, source = 'manual' et lineItems = [].
```

Afficher l'état du contrôleur (preparing → spinner ; shared → fermeture + snackbar succès ; error → message). Réutiliser les états d'affichage déjà en place pour le partage.

- [ ] **Step 4: Analyse + tests**

Run: `export PATH="/opt/homebrew/bin:$PATH"; flutter analyze lib/features/charge_regularization && flutter test test/l10n/arb_parity_test.dart`

- [ ] **Step 5: Commit**

```bash
export PATH="/opt/homebrew/bin:$PATH"; dart format lib/features/charge_regularization/
git add lib/features/charge_regularization/presentation/widgets/charge_regularization_dialog.dart lib/l10n/app_fr.arb lib/l10n/app_en.arb
git commit -m "feat(charge): action Finaliser & figer dans le dialog régul (FEAT-033)"
```

---

## Task 9 — UI : section historique des décomptes sur la fiche bail

**Files:**
- Create: `lib/features/charge_regularization/presentation/widgets/charge_statement_history_section.dart`
- Modify: la page fiche bail qui monte déjà `ChargeRegularizationSection` (localiser via `grep -rl "ChargeRegularizationSection(" lib/features/leases`)
- Modify: `lib/l10n/app_fr.arb`, `lib/l10n/app_en.arb`
- Test: `test/widget/charge_statement_history_section_test.dart`

**Interfaces:**
- Consumes : `chargeStatementRepositoryProvider` (Task 6) via un `FutureProvider.family` par `leaseId` ; `ChargeStatementFinalizeController.shareExisting` (Task 7) ; `ChargeStatement` (`labelFr`, `balanceAbsCents`, `isVoided`, `isSent`).
- Produces : widget `ChargeStatementHistorySection({required String leaseId})`.

- [ ] **Step 1: Ajouter les clés i18n** (EN template + FR) :

```json
// app_en.arb
"chargeStatementHistoryTitle": "Locked statements",
"@chargeStatementHistoryTitle": {"description": "Section title listing finalized charge regularization statements on the lease page"},
"chargeStatementHistoryEmpty": "No locked statement yet.",
"@chargeStatementHistoryEmpty": {"description": "Empty state when a lease has no finalized charge statement"},
"chargeStatementBadgeSent": "Sent",
"@chargeStatementBadgeSent": {"description": "Badge shown on a statement that was shared to the tenant"},
"chargeStatementBadgeVoided": "Voided",
"@chargeStatementBadgeVoided": {"description": "Badge shown on a voided statement"},
"chargeStatementActionReshare": "Re-share",
"@chargeStatementActionReshare": {"description": "Action to re-render and re-share an existing locked statement"},
"chargeStatementActionVoid": "Void",
"@chargeStatementActionVoid": {"description": "Action to void a locked statement"},
"chargeStatementVoidReasonHint": "Reason for voiding",
"@chargeStatementVoidReasonHint": {"description": "Hint text for the void reason input"}
```

```json
// app_fr.arb
"chargeStatementHistoryTitle": "Décomptes figés",
"chargeStatementHistoryEmpty": "Aucun décompte figé pour l'instant.",
"chargeStatementBadgeSent": "Envoyé",
"chargeStatementBadgeVoided": "Annulé",
"chargeStatementActionReshare": "Re-partager",
"chargeStatementActionVoid": "Annuler",
"chargeStatementVoidReasonHint": "Motif d'annulation"
```

- [ ] **Step 2: Régénérer + parité**

Run: `export PATH="/opt/homebrew/bin:$PATH"; flutter gen-l10n && flutter test test/l10n/arb_parity_test.dart`

- [ ] **Step 3: Écrire un provider de liste** (dans le repository file ou un `application/` dédié) :

```dart
final chargeStatementsForLeaseProvider =
    FutureProvider.family.autoDispose<List<ChargeStatement>, String>((ref, leaseId) {
  return ref.read(chargeStatementRepositoryProvider).listForLease(leaseId);
});
```

- [ ] **Step 4: Écrire la section** — `ConsumerWidget` affichant :
  - titre `chargeStatementHistoryTitle` ;
  - `when` sur le provider : loading (spinner sobre), error (message), data ;
  - liste vide → `chargeStatementHistoryEmpty` ;
  - chaque décompte : période (`FrenchDate.format`), solde `balanceAbsCents` formaté `1 234,56 €` + `labelFr`, badges `Envoyé`/`Annulé` (couleurs `AppColors` `.info`/`.neutral`), boutons `Re-partager` (→ `shareExisting`) et `Annuler` (→ dialog motif `chargeStatementVoidReasonHint` puis `voidStatement`, avec `ref.invalidate(chargeStatementsForLeaseProvider(leaseId))` au retour). Un décompte `isVoided` masque l'action « Annuler ».

Suivre le style visuel de la section quittances (`grep -rl "listForLease" lib/features/receipts/presentation`) pour rester cohérent (tuiles, tokens, espacements `AppSpacing`).

- [ ] **Step 5: Monter la section** sur la fiche bail, sous `ChargeRegularizationSection` (mêmes conditions de visibilité PRO/légal ne s'appliquent pas à la lecture de l'historique — un décompte figé reste consultable même si le bail passe au forfait ; afficher l'historique dès qu'il existe au moins un décompte).

- [ ] **Step 6: Test widget** — pump la section avec un `chargeStatementRepositoryProvider` overridé (fake retournant 1 décompte envoyé + 1 annulé) ; vérifier l'affichage du solde, des badges, et la présence du bouton « Re-partager ». Suivre le patron d'un widget test existant (`ls test/widget/ | head`).

- [ ] **Step 7: Analyse + tests**

Run: `export PATH="/opt/homebrew/bin:$PATH"; flutter analyze lib/features/charge_regularization && flutter test test/widget/charge_statement_history_section_test.dart test/l10n/arb_parity_test.dart`

- [ ] **Step 8: Commit**

```bash
export PATH="/opt/homebrew/bin:$PATH"; dart format lib/features/charge_regularization/ test/widget/charge_statement_history_section_test.dart
git add lib/features/charge_regularization/ lib/l10n/app_fr.arb lib/l10n/app_en.arb test/widget/charge_statement_history_section_test.dart
# + le fichier fiche bail modifié
git commit -m "feat(charge): historique des décomptes figés sur la fiche bail (FEAT-033)"
```

---

## Task 10 — Documentation d'état (Definition of Done)

**Files:**
- Modify: `docs/state/FEATURES.md`, `docs/state/CHANGELOG.md`, `docs/state/functions/leases.md`, `docs/state/schema/leases.md`

- [ ] **Step 1: FEATURES.md** — passer la ligne `FEAT-033` de `💡 idea` à `✅ done` (colonne domaine `leases`, commit/PR à renseigner).

- [ ] **Step 2: CHANGELOG.md** — ajouter une entrée `PR #NN — FEAT-033` : collection `charge_statements` immuable, 3 callables (`finalizeChargeRegularization`/`voidChargeStatement`/`markChargeStatementAsSent`), provisions recalculées serveur, rules + index, historique fiche bail, ajout export RGPD.

- [ ] **Step 3: functions/leases.md** (ou `payments-receipts.md`) — documenter les 3 nouveaux callables (params, validations, gate légal serveur, recompute provisions, immuabilité).

- [ ] **Step 4: schema/leases.md** — ajouter la collection `charge_statements` (champs figés, `lineItems`, flags void/sent, `create/update/delete: if false`, index composite). Noter : Rules + index déployés par la CI (`develop` → staging) ; **Cloud Functions en déploiement manuel délibéré**.

- [ ] **Step 5: Commit**

```bash
git add docs/state/FEATURES.md docs/state/CHANGELOG.md docs/state/functions/leases.md docs/state/schema/leases.md
git commit -m "docs(state): FEAT-033 — charge_statements (CHANGELOG + shards)"
```

---

## Final verification (avant finishing-a-development-branch)

- [ ] Functions : `export PATH="/opt/homebrew/bin:$PATH"; cd functions && npm run lint && npm run build && npx vitest run && npm run test:rules`
- [ ] Flutter : `export PATH="/opt/homebrew/bin:$PATH"; flutter analyze && flutter test`
- [ ] Format repo-wide : `export PATH="/opt/homebrew/bin:$PATH"; dart format --output=none --set-exit-if-changed .`
- [ ] `check-db-isolation.sh` : `bash scripts/check-db-isolation.sh` (aucun accès Firestore direct).

## Notes de déploiement

- Rules + indexes : déployés **automatiquement** par la CI au merge sur `develop` (staging). Rien à faire à la main.
- **Cloud Functions : déploiement manuel délibéré** (hors CI) — `firebase deploy --only functions:finalizeChargeRegularization,functions:voidChargeStatement,functions:markChargeStatementAsSent`. Sans ce déploiement, l'action « Finaliser » échouera en staging (callable introuvable) même si le client est déployé. Prévenir l'utilisateur : ce déploiement functions nécessite sa confirmation (garde-fou CLAUDE.md).
- Le nouvel index composite `charge_statements` doit être bâti côté Firestore avant que `listForLease` ne fonctionne — le déploiement CI des indexes s'en charge sur staging.
