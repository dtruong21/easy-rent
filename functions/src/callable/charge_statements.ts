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
 *
 * `voidChargeStatement` et `markChargeStatementAsSent` arrivent en Task 2 —
 * seul `finalizeChargeRegularization` est exporté depuis `index.ts` ici.
 */
import * as admin from "firebase-admin";
import type {Timestamp} from "firebase-admin/firestore";
import {logger} from "firebase-functions/v2";
import {HttpsError, onCall} from "firebase-functions/v2/https";

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
    const rawLineItems = Array.isArray(data.lineItems) ?
      (data.lineItems as Array<Record<string, unknown>>) :
      [];
    const lineItems =
      source === "expenses" ?
        validateLineItems(rawLineItems, actualExpensesCents) :
        [];

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
        tenantFullName:
          `${String(lease.tenantFirstName ?? "")} ${String(lease.tenantLastName ?? "")}`.trim(),
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
