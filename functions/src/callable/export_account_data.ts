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
  chargeStatements: "charge_statements",
  etatDesLieux: "etat_des_lieux",
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
