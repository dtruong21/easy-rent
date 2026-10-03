/**
 * createExpense / updateExpense — callables.
 *
 * `expenses` est CF-EXCLUSIVE (comme `leases`/`payments`/`documents`) pour
 * 3 raisons qu'aucune Firestore rule ne peut couvrir proprement
 * (cf. docs/plans/FEAT-041-depenses.md §b) :
 *
 *   1. Validation cross-entity : propertyId (obligatoire) + leaseId
 *      (optionnel, cohérence lease.propertyId == propertyId) + documentId
 *      (optionnel) doivent appartenir au même landlord que l'appelant.
 *   2. Invariante juridique décret 87-713 : `category` doit être
 *      dérivée/validée serveur depuis `nature` via `NATURE_DEFAULT_CATEGORY`
 *      — un client ne doit JAMAIS pouvoir forger `category = recoverable`
 *      sur une taxe foncière (sur-facturation illégale au locataire).
 *   3. Dénormalisation (`propertyName`/`tenantLastName`, pattern `payments`)
 *      + soft-delete protégé (`deletedAt` jamais écrit côté client).
 *
 * FEAT-041d : ces callables acceptent en plus `recurrence` /
 * `recurrenceEndDate`. Aucune écriture n'est générée par échéance — la
 * récurrence est virtuelle, les clients la déroulent au calcul. Il n'y a donc
 * rien à ajouter dans `firestore.rules` : la collection est déjà
 * `allow create, update, delete: if false` (écriture 100 % CF), et la lecture
 * est autorisée au document entier, pas champ par champ.
 *
 * `NATURE_DEFAULT_CATEGORY` est la source unique de vérité juridique — elle
 * est répliquée en enum Dart `ExpenseNature` côté client pour la
 * présélection UI uniquement (la dérivation reste serveur, non
 * contournable).
 */

import type * as admin from "firebase-admin";
import {FieldValue} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";


import {makeSetUpdatedAt} from "../triggers/set_updated_at";
import {
  asBag,
  assertOwnedAndActive,
  dataOrFail,
  optionalInt,
  optionalString,
  optionalTimestamp,
  requireVerifiedUid,
  requireInt,
  requireString,
  toTimestamp,
} from "../utils/callable_helpers";
import {dbForRequest} from "../utils/db_router";

export type ExpenseCategory = "recoverable" | "non_recoverable";

export const EXPENSE_NATURES = [
  "condo_charges",
  "property_tax",
  "insurance_pno",
  "management_fees",
  "works",
  "repair_maintenance",
  "other",
] as const;

export type ExpenseNature = (typeof EXPENSE_NATURES)[number];

const EXPENSE_NATURE_SET: ReadonlySet<string> = new Set(EXPENSE_NATURES);

/**
 * Table de dérivation juridique (décret n°87-713 du 26 août 1987) —
 * source unique de vérité. Cf. docs/plans/FEAT-041-depenses.md §a.
 *
 * `locked: true` → override interdit (`failed-precondition`).
 * `locked: false` → override autorisé, tracé via `categoryOverridden`.
 */
export const NATURE_DEFAULT_CATEGORY: Readonly<
  Record<ExpenseNature, {category: ExpenseCategory; locked: boolean}>
> = {
  condo_charges: {category: "recoverable", locked: false},
  property_tax: {category: "non_recoverable", locked: true},
  insurance_pno: {category: "non_recoverable", locked: true},
  management_fees: {category: "non_recoverable", locked: true},
  works: {category: "non_recoverable", locked: false},
  repair_maintenance: {category: "non_recoverable", locked: false},
  other: {category: "non_recoverable", locked: false},
};

/**
 * Périodicité d'une dépense (FEAT-041d) — récurrence VIRTUELLE.
 *
 * Le serveur ne matérialise AUCUNE écriture par échéance : il stocke le
 * rythme et, éventuellement, une date de fin. Ce sont les clients qui
 * déroulent les échéances au moment du calcul (cf.
 * `lib/core/finance/expense_recurrence.dart`). Corriger le montant d'une
 * dépense récurrente corrige donc instantanément toutes ses échéances, sans
 * rattrapage ni cron.
 *
 * Réplique fidèle de l'enum Dart `ExpenseRecurrence`.
 */
export const EXPENSE_RECURRENCES = [
  "none",
  "monthly",
  "quarterly",
  "yearly",
] as const;

export type ExpenseRecurrence = (typeof EXPENSE_RECURRENCES)[number];

const EXPENSE_RECURRENCE_SET: ReadonlySet<string> = new Set(
  EXPENSE_RECURRENCES,
);

function isExpenseNature(value: string): value is ExpenseNature {
  return EXPENSE_NATURE_SET.has(value);
}

function isExpenseRecurrence(value: string): value is ExpenseRecurrence {
  return EXPENSE_RECURRENCE_SET.has(value);
}

function isExpenseCategory(value: string): value is ExpenseCategory {
  return value === "recoverable" || value === "non_recoverable";
}

/**
 * Dérive/valide `category` à partir de `nature` et d'une éventuelle
 * catégorie fournie par le client.
 *
 * Fonction pure (aucune dépendance Firebase) — extraite pour rester
 * testable en unitaire sans émulateur.
 */
export function deriveExpenseCategory(
  nature: ExpenseNature,
  requestedCategory: ExpenseCategory | null,
): {category: ExpenseCategory; categoryOverridden: boolean} {
  const rule = NATURE_DEFAULT_CATEGORY[nature];

  if (requestedCategory === null || requestedCategory === rule.category) {
    return {category: rule.category, categoryOverridden: false};
  }

  if (rule.locked) {
    throw new HttpsError(
      "failed-precondition",
      "category_locked_for_nature",
    );
  }

  return {category: requestedCategory, categoryOverridden: true};
}

/**
 * Dérive l'exercice (`periodYear`) de rattachement.
 *
 * Priorité : `periodYear` fourni explicitement > année de `periodStart` >
 * année de `expenseDate`. Fonction pure — extraite pour tests unitaires.
 */
export function deriveExpensePeriodYear(opts: {
  periodYear: number | null;
  periodStart: admin.firestore.Timestamp | null;
  expenseDate: admin.firestore.Timestamp;
}): number {
  if (opts.periodYear !== null) return opts.periodYear;
  if (opts.periodStart !== null) return opts.periodStart.toDate().getUTCFullYear();
  return opts.expenseDate.toDate().getUTCFullYear();
}

/**
 * Valide et normalise le couple (périodicité, fin de récurrence).
 *
 * Règles :
 *  - absence de `recurrence` → `none` (dépenses créées avant FEAT-041d : elles
 *    restent ponctuelles, aucune migration n'est faite ni nécessaire) ;
 *  - une dépense ponctuelle ne peut pas porter de fin de récurrence — la
 *    valeur est **normalisée à null** plutôt que refusée : le client qui
 *    repasse une dépense en « ponctuelle » n'a pas à penser à effacer aussi
 *    la date de fin, et un document ne peut jamais se retrouver dans cet
 *    état incohérent ;
 *  - la fin de récurrence ne peut pas précéder `expenseDate`, qui est la
 *    PREMIÈRE échéance : une telle récurrence n'aurait aucune échéance.
 *
 * Fonction pure (hors type Timestamp) — testable sans émulateur.
 */
export function resolveExpenseRecurrence(opts: {
  recurrence: string | null;
  recurrenceEndDate: admin.firestore.Timestamp | null;
  expenseDate: admin.firestore.Timestamp;
}): {
  recurrence: ExpenseRecurrence;
  recurrenceEndDate: admin.firestore.Timestamp | null;
} {
  const raw = opts.recurrence ?? "none";
  if (!isExpenseRecurrence(raw)) {
    throw new HttpsError("invalid-argument", `invalid recurrence: ${raw}`);
  }

  if (raw === "none") {
    return {recurrence: "none", recurrenceEndDate: null};
  }

  const end = opts.recurrenceEndDate;
  if (end !== null && end.toMillis() < opts.expenseDate.toMillis()) {
    throw new HttpsError(
      "invalid-argument",
      "recurrence_end_before_expense_date",
    );
  }

  return {recurrence: raw, recurrenceEndDate: end};
}

// ============================================================================
// createExpense
// ============================================================================
export const createExpense = onCall(
  {region: "europe-west1"},
  async (request) => {
    const uid = await requireVerifiedUid(request);
    const data = asBag(request.data);

    const propertyId = requireString(data.propertyId, "propertyId");
    const leaseId = optionalString(data.leaseId, "leaseId");
    const amountCents = requireInt(data.amountCents, "amountCents", {min: 1});
    const expenseDate = toTimestamp(data.expenseDate, "expenseDate");

    const natureRaw = requireString(data.nature, "nature");
    if (!isExpenseNature(natureRaw)) {
      throw new HttpsError("invalid-argument", `invalid nature: ${natureRaw}`);
    }
    const nature = natureRaw;

    const requestedCategoryRaw = optionalString(data.category, "category");
    let requestedCategory: ExpenseCategory | null = null;
    if (requestedCategoryRaw !== null) {
      if (!isExpenseCategory(requestedCategoryRaw)) {
        throw new HttpsError(
          "invalid-argument",
          `invalid category: ${requestedCategoryRaw}`,
        );
      }
      requestedCategory = requestedCategoryRaw;
    }

    const {category, categoryOverridden} = deriveExpenseCategory(
      nature,
      requestedCategory,
    );

    const periodStart = optionalTimestamp(data.periodStart, "periodStart");
    const periodEnd = optionalTimestamp(data.periodEnd, "periodEnd");
    if (category === "recoverable") {
      if (periodStart === null) {
        throw new HttpsError(
          "invalid-argument",
          "periodStart is required for recoverable expenses",
        );
      }
      if (periodEnd === null) {
        throw new HttpsError(
          "invalid-argument",
          "periodEnd is required for recoverable expenses",
        );
      }
      if (periodEnd.toMillis() <= periodStart.toMillis()) {
        throw new HttpsError(
          "invalid-argument",
          "periodEnd must be after periodStart",
        );
      }
    }

    const periodYearInput = optionalInt(data.periodYear, "periodYear");
    const periodYear = deriveExpensePeriodYear({
      periodYear: periodYearInput,
      periodStart,
      expenseDate,
    });

    const {recurrence, recurrenceEndDate} = resolveExpenseRecurrence({
      recurrence: optionalString(data.recurrence, "recurrence"),
      recurrenceEndDate: optionalTimestamp(
        data.recurrenceEndDate,
        "recurrenceEndDate",
      ),
      expenseDate,
    });

    const documentId = optionalString(data.documentId, "documentId");
    const notes = optionalString(data.notes, "notes");
    if (notes !== null && notes.length > 2000) {
      throw new HttpsError("invalid-argument", "notes must be <= 2000 chars");
    }

    const db = await dbForRequest(request);
    const propertyRef = db.doc(`properties/${propertyId}`);
    const leaseRef = leaseId ? db.doc(`leases/${leaseId}`) : null;
    const documentRef = documentId ? db.doc(`documents/${documentId}`) : null;
    const expenseRef = db.collection("expenses").doc();

    return await db.runTransaction(async (tx) => {
      const [propertySnap, leaseSnap, documentSnap] = await Promise.all([
        tx.get(propertyRef),
        leaseRef ? tx.get(leaseRef) : Promise.resolve(null),
        documentRef ? tx.get(documentRef) : Promise.resolve(null),
      ]);

      const property = dataOrFail(propertySnap, "property not found");
      assertOwnedAndActive(property, uid, "property");

      let tenantLastName: string | null = null;
      if (leaseSnap) {
        const lease = dataOrFail(leaseSnap, "lease not found");
        assertOwnedAndActive(lease, uid, "lease");
        if (lease.propertyId !== propertyId) {
          throw new HttpsError(
            "failed-precondition",
            "lease_property_mismatch",
          );
        }
        tenantLastName =
          typeof lease.tenantLastName === "string" ?
            lease.tenantLastName :
            null;
      }

      if (documentSnap) {
        const document = dataOrFail(documentSnap, "document not found");
        assertOwnedAndActive(document, uid, "document");
      }

      const now = FieldValue.serverTimestamp();
      tx.set(expenseRef, {
        id: expenseRef.id,
        landlordId: uid,
        propertyId,
        propertyName: property.name,
        leaseId,
        tenantLastName,
        amountCents,
        expenseDate,
        nature,
        category,
        categoryOverridden,
        periodYear,
        periodStart,
        periodEnd,
        recurrence,
        recurrenceEndDate,
        documentId,
        notes,
        createdAt: now,
        updatedAt: now,
        deletedAt: null,
      });

      return {expenseId: expenseRef.id, category, categoryOverridden};
    });
  },
);

// ============================================================================
// updateExpense — champs mutables uniquement
//
// Immuables : propertyId / leaseId / landlordId / createdAt / deletedAt
// (changer de bien ou de bail = supprimer + recréer, cf. plan §12).
// ============================================================================
const EXPENSE_MUTABLE_FIELDS = new Set([
  "amountCents",
  "expenseDate",
  "nature",
  "category",
  "periodStart",
  "periodEnd",
  "periodYear",
  "recurrence",
  "recurrenceEndDate",
  "documentId",
  "notes",
]);

export const updateExpense = onCall(
  {region: "europe-west1"},
  async (request) => {
    const uid = await requireVerifiedUid(request);
    const data = asBag(request.data);
    const id = requireString(data.id, "id");
    const patch = asBag(data.patch);

    for (const k of Object.keys(patch)) {
      if (!EXPENSE_MUTABLE_FIELDS.has(k)) {
        throw new HttpsError(
          "invalid-argument",
          `field ${k} is immutable or unknown`,
        );
      }
    }

    const db = await dbForRequest(request);
    const expenseRef = db.doc(`expenses/${id}`);

    return await db.runTransaction(async (tx) => {
      const snap = await tx.get(expenseRef);
      const expense = dataOrFail(snap, "expense not found");
      assertOwnedAndActive(expense, uid, "expense");

      const cleanPatch: Record<string, unknown> = {};

      // amountCents
      if (patch.amountCents !== undefined) {
        cleanPatch.amountCents = requireInt(patch.amountCents, "amountCents", {
          min: 1,
        });
      }

      // expenseDate
      const expenseDate =
        patch.expenseDate !== undefined ?
          toTimestamp(patch.expenseDate, "expenseDate") :
          (expense.expenseDate as admin.firestore.Timestamp);
      if (patch.expenseDate !== undefined) {
        cleanPatch.expenseDate = expenseDate;
      }

      // nature — re-dérive category si nature change (re-applique verrouillage).
      let nature = expense.nature as ExpenseNature;
      let natureChanged = false;
      if (patch.nature !== undefined) {
        const natureRaw = requireString(patch.nature, "nature");
        if (!isExpenseNature(natureRaw)) {
          throw new HttpsError(
            "invalid-argument",
            `invalid nature: ${natureRaw}`,
          );
        }
        nature = natureRaw;
        natureChanged = true;
        cleanPatch.nature = nature;
      }

      // requestedCategory reste `null` si le patch ne fournit pas de
      // category explicite (dérivation par défaut de la nature, sans
      // override) — que la nature ait changé ou non.
      let requestedCategory: ExpenseCategory | null = null;
      if (patch.category !== undefined) {
        const categoryRaw = requireString(patch.category, "category");
        if (!isExpenseCategory(categoryRaw)) {
          throw new HttpsError(
            "invalid-argument",
            `invalid category: ${categoryRaw}`,
          );
        }
        requestedCategory = categoryRaw;
      }

      let category = expense.category as ExpenseCategory;
      let categoryOverridden = expense.categoryOverridden === true;
      if (natureChanged || patch.category !== undefined) {
        const derived = deriveExpenseCategory(nature, requestedCategory);
        category = derived.category;
        categoryOverridden = derived.categoryOverridden;
        cleanPatch.category = category;
        cleanPatch.categoryOverridden = categoryOverridden;
      }

      // periodStart / periodEnd
      const periodStart =
        patch.periodStart !== undefined ?
          optionalTimestamp(patch.periodStart, "periodStart") :
          ((expense.periodStart as admin.firestore.Timestamp | null) ?? null);
      const periodEnd =
        patch.periodEnd !== undefined ?
          optionalTimestamp(patch.periodEnd, "periodEnd") :
          ((expense.periodEnd as admin.firestore.Timestamp | null) ?? null);
      if (patch.periodStart !== undefined) cleanPatch.periodStart = periodStart;
      if (patch.periodEnd !== undefined) cleanPatch.periodEnd = periodEnd;

      if (category === "recoverable") {
        if (periodStart === null) {
          throw new HttpsError(
            "invalid-argument",
            "periodStart is required for recoverable expenses",
          );
        }
        if (periodEnd === null) {
          throw new HttpsError(
            "invalid-argument",
            "periodEnd is required for recoverable expenses",
          );
        }
        if (periodEnd.toMillis() <= periodStart.toMillis()) {
          throw new HttpsError(
            "invalid-argument",
            "periodEnd must be after periodStart",
          );
        }
      }

      // periodYear — re-dérive si non fourni explicitement mais que
      // periodStart/expenseDate a changé.
      if (patch.periodYear !== undefined) {
        cleanPatch.periodYear = requireInt(patch.periodYear, "periodYear");
      } else if (patch.periodStart !== undefined || patch.expenseDate !== undefined) {
        cleanPatch.periodYear = deriveExpensePeriodYear({
          periodYear: null,
          periodStart,
          expenseDate,
        });
      }

      // recurrence / recurrenceEndDate — l'invariante « la fin ne précède pas
      // la première échéance » est revérifiée à CHAQUE update, même quand le
      // patch ne touche que `expenseDate` : déplacer la date de la dépense
      // après la fin de récurrence produirait une récurrence sans aucune
      // échéance.
      const resolvedRecurrence = resolveExpenseRecurrence({
        recurrence:
          patch.recurrence !== undefined ?
            requireString(patch.recurrence, "recurrence") :
            ((expense.recurrence as string | undefined) ?? null),
        recurrenceEndDate:
          patch.recurrenceEndDate !== undefined ?
            optionalTimestamp(patch.recurrenceEndDate, "recurrenceEndDate") :
            ((expense.recurrenceEndDate as
              | admin.firestore.Timestamp
              | null
              | undefined) ?? null),
        expenseDate,
      });
      if (
        patch.recurrence !== undefined ||
        patch.recurrenceEndDate !== undefined
      ) {
        cleanPatch.recurrence = resolvedRecurrence.recurrence;
        cleanPatch.recurrenceEndDate = resolvedRecurrence.recurrenceEndDate;
      }

      // documentId — ownership re-validée si changé.
      if (patch.documentId !== undefined) {
        const documentId = optionalString(patch.documentId, "documentId");
        if (documentId !== null) {
          const documentSnap = await tx.get(db.doc(`documents/${documentId}`));
          const document = dataOrFail(documentSnap, "document not found");
          assertOwnedAndActive(document, uid, "document");
        }
        cleanPatch.documentId = documentId;
      }

      // notes
      if (patch.notes !== undefined) {
        const notes = optionalString(patch.notes, "notes");
        if (notes !== null && notes.length > 2000) {
          throw new HttpsError(
            "invalid-argument",
            "notes must be <= 2000 chars",
          );
        }
        cleanPatch.notes = notes;
      }

      // Re-snapshot propertyName si le nom du bien a changé depuis la
      // création (pattern payments : dénorm rafraîchie à chaque mutation).
      const propertyId = expense.propertyId;
      if (typeof propertyId === "string") {
        const propertySnap = await tx.get(db.doc(`properties/${propertyId}`));
        if (propertySnap.exists) {
          const property = propertySnap.data();
          if (
            property &&
            typeof property.name === "string" &&
            property.name !== expense.propertyName
          ) {
            cleanPatch.propertyName = property.name;
          }
        }
      }

      tx.update(expenseRef, {
        ...cleanPatch,
        updatedAt: FieldValue.serverTimestamp(),
      });

      return {updated: true};
    });
  },
);

// ============================================================================
// Trigger updatedAt — pattern des 7 triggers existants (set_updated_at.ts).
// Exporté ici (pas dans triggers/set_updated_at.ts) car couplé à la logique
// métier `expenses` du même fichier ; ré-exporté par index.ts comme les
// autres.
// ============================================================================
export const setUpdatedAtExpenses = makeSetUpdatedAt("expenses");
