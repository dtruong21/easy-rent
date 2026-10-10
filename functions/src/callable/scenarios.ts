/**
 * createScenario — création d'un scénario de simulateur, avec gating du
 * plafond par palier (FEAT-056 §5.3, lot PR-2b).
 *
 * Pourquoi côté serveur, maintenant : jusqu'ici `investment_scenarios` était le
 * SEUL quota appliqué par le client seul (le simulateur écrivait le document en
 * direct, gardé par les seules Firestore rules). Tant que la grille ne
 * différenciait pas les scénarios entre paliers, c'était un choix assumé. Dès
 * lors que le nombre de scénarios devient un **différenciateur commercial**
 * entre Pro, Max et Ultra, un plafond non vérifié côté serveur est un plafond
 * contournable : il suffit d'écrire le document soi-même. Les rules ne savent
 * ni agréger ni réserver → il faut une callable, et la rule `create` passe à
 * `if false` (CF-exclusive, même patron que `properties` et `tenants`).
 *
 * **Comptage live, pas de compteur dénormalisé** — choix délibéré, aligné sur
 * `documents.ts` plutôt que sur `property_tenant.ts` :
 *   - le volume est petit et borné (1 en anonyme, 3 en gratuit) ;
 *   - le soft-delete passe par `softDeleteEntity`, qui ne connaît aucun
 *     compteur de scénarios : en introduire un demanderait un backfill des
 *     comptes existants + un décrément, donc deux nouvelles sources de dérive ;
 *   - sans compteur, il n'y a rien qui puisse dériver — le `count()` filtré sur
 *     `deletedAt == null` est toujours la vérité.
 * Contrepartie assumée, identique à celle de `createDocument` : deux appels
 * exactement simultanés à la borne peuvent créer un scénario de trop. Le
 * dépassement est borné, non lucratif, et se résorbe à la suppression suivante.
 */

import {FieldValue} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {errorCodeFor, quotaLimit, resolvePlan} from "../entitlements/plan";
import {
  asBag,
  optionalInt,
  optionalString,
  requireVerifiedUid,
  requireBool,
  requireInt,
  requireString,
} from "../utils/callable_helpers";
import {dbForRequest} from "../utils/db_router";

/** Miroir de la contrainte `name.size() <= 120` de l'ancienne rule `create`. */
const MAX_NAME_LENGTH = 120;

/** Version du schéma du document — miroir du client (`schemaVersion: 1`). */
const SCHEMA_VERSION = 1;

/** Durée d'emprunt par défaut, miroir du défaut Dart (20 ans). */
const DEFAULT_LOAN_DURATION_MONTHS = 240;

/** Paramètres financiers d'un scénario (tous en centimes, sauf indication). */
export interface ScenarioInputs {
  readonly name: string;
  readonly notes: string | null;
  readonly purchasePriceCents: number;
  readonly notaryFeesCents: number;
  readonly worksInitialCents: number;
  readonly isNewProperty: boolean;
  readonly downPaymentCents: number;
  readonly loanPrincipalCents: number;
  readonly loanRateBps: number;
  readonly loanDurationMonths: number;
  readonly monthlyRentHcCents: number;
  readonly propertyTaxAnnualCents: number;
  readonly insurancePnoAnnualCents: number;
  readonly condoFeesNonRecoverableCents: number;
}

/**
 * PURE — valide et normalise le payload client. La callable devient la seule
 * gardienne de la forme du document (la rule `create` ne valide plus rien,
 * elle refuse tout), donc cette fonction reprend mot pour mot les contraintes
 * que la rule imposait, plus les bornes des montants.
 */
export function parseScenarioInputs(
  data: Record<string, unknown>,
): ScenarioInputs {
  const name = requireString(data.name, "name").trim();
  if (name.length === 0 || name.length > MAX_NAME_LENGTH) {
    throw new HttpsError(
      "invalid-argument",
      `name must be 1..${MAX_NAME_LENGTH} characters`,
    );
  }
  const rawNotes = optionalString(data.notes, "notes");
  const notes = rawNotes === null || rawNotes.trim().length === 0 ?
    null :
    rawNotes.trim();

  return {
    name,
    notes,
    purchasePriceCents: requireInt(
      data.purchasePriceCents,
      "purchasePriceCents",
      {min: 0},
    ),
    monthlyRentHcCents: requireInt(
      data.monthlyRentHcCents,
      "monthlyRentHcCents",
      {min: 0},
    ),
    notaryFeesCents:
      optionalInt(data.notaryFeesCents, "notaryFeesCents", {min: 0}) ?? 0,
    worksInitialCents:
      optionalInt(data.worksInitialCents, "worksInitialCents", {min: 0}) ?? 0,
    isNewProperty: requireBool(data.isNewProperty, "isNewProperty"),
    downPaymentCents:
      optionalInt(data.downPaymentCents, "downPaymentCents", {min: 0}) ?? 0,
    loanPrincipalCents:
      optionalInt(data.loanPrincipalCents, "loanPrincipalCents", {min: 0}) ?? 0,
    loanRateBps: optionalInt(data.loanRateBps, "loanRateBps", {min: 0}) ?? 0,
    loanDurationMonths:
      optionalInt(data.loanDurationMonths, "loanDurationMonths", {min: 0}) ??
      DEFAULT_LOAN_DURATION_MONTHS,
    propertyTaxAnnualCents:
      optionalInt(data.propertyTaxAnnualCents, "propertyTaxAnnualCents", {
        min: 0,
      }) ?? 0,
    insurancePnoAnnualCents:
      optionalInt(data.insurancePnoAnnualCents, "insurancePnoAnnualCents", {
        min: 0,
      }) ?? 0,
    condoFeesNonRecoverableCents:
      optionalInt(
        data.condoFeesNonRecoverableCents,
        "condoFeesNonRecoverableCents",
        {min: 0},
      ) ?? 0,
  };
}

/**
 * PURE — document Firestore d'un scénario.
 *
 * Les paramètres financiers sont écrits DEUX fois, à l'identique : dans la map
 * `scenarioJson` (schéma FEAT-019) et en racine (le modèle Dart les attend en
 * top-level). C'est la forme exacte que le client écrivait ; la reproduire ici
 * garantit qu'aucun scénario existant ne devient illisible.
 */
export function buildScenarioDocument(args: {
  id: string;
  landlordId: string;
  inputs: ScenarioInputs;
  now: unknown;
}): Record<string, unknown> {
  const {id, landlordId, inputs, now} = args;
  const financials = {
    purchasePriceCents: inputs.purchasePriceCents,
    notaryFeesCents: inputs.notaryFeesCents,
    worksInitialCents: inputs.worksInitialCents,
    isNewProperty: inputs.isNewProperty,
    downPaymentCents: inputs.downPaymentCents,
    loanPrincipalCents: inputs.loanPrincipalCents,
    loanRateBps: inputs.loanRateBps,
    loanDurationMonths: inputs.loanDurationMonths,
    monthlyRentHcCents: inputs.monthlyRentHcCents,
    propertyTaxAnnualCents: inputs.propertyTaxAnnualCents,
    insurancePnoAnnualCents: inputs.insurancePnoAnnualCents,
    condoFeesNonRecoverableCents: inputs.condoFeesNonRecoverableCents,
  };
  return {
    id,
    landlordId,
    name: inputs.name,
    notes: inputs.notes,
    schemaVersion: SCHEMA_VERSION,
    scenarioJson: {...financials},
    ...financials,
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
  };
}

export const createScenario = onCall(
  {region: "europe-west1"},
  async (request) => {
    const uid = await requireVerifiedUid(request);
    const inputs = parseScenarioInputs(asBag(request.data));

    const db = await dbForRequest(request);
    const landlordSnap = await db.doc(`landlords/${uid}`).get();
    if (!landlordSnap.exists) {
      throw new HttpsError("not-found", "landlord not found");
    }
    const landlord = (landlordSnap.data() ?? {}) as Record<string, unknown>;

    const limit = quotaLimit(resolvePlan(landlord), "scenarios");
    if (limit !== null) {
      const agg = await db
        .collection("investment_scenarios")
        .where("landlordId", "==", uid)
        .where("deletedAt", "==", null)
        .count()
        .get();
      if (agg.data().count >= limit) {
        throw new HttpsError("resource-exhausted", errorCodeFor("scenarios"));
      }
    }

    const ref = db.collection("investment_scenarios").doc();
    await ref.set(
      buildScenarioDocument({
        id: ref.id,
        landlordId: uid,
        inputs,
        now: FieldValue.serverTimestamp(),
      }),
    );

    return {scenarioId: ref.id};
  },
);
