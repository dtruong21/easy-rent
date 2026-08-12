/**
 * createLease / updateLease / createPayment / updatePayment — callables.
 *
 * Réplique des triggers Postgres SECURITY DEFINER :
 *   - assert_lease_ownership_consistency : property + tenant doivent
 *     appartenir au même landlord que le lease.
 *   - assert_payment_lease_ownership : payment.lease doit appartenir
 *     au même landlord que le payment.
 *
 * Inclut la snapshot des dénormalisations (FEAT-019 data model §2.2)
 * pour que la liste des cards charge en 1 query sans join client-side.
 *
 * activeLeaseCount maintenu transactionnellement à la création d'un lease
 * actif et au changement de status via updateLease ; la soft-delete d'un
 * bail actif décrémente le compteur dans softDeleteEntity.
 */

import * as admin from "firebase-admin";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {errorCodeFor, quotaLimit, resolvePlan} from "../entitlements/plan";
import {
  asBag,
  assertOwnedAndActive,
  dataOrFail,
  optionalInt,
  optionalNumber,
  optionalString,
  optionalTimestamp,
  requireAuthUid,
  requireBool,
  requireInt,
  requireString,
  toTimestamp,
} from "../utils/callable_helpers";
import {dbForRequest} from "../utils/db_router";
import {composePropertyAddress} from "../utils/property_address";


const LEASE_TYPES = new Set([
  "unfurnished",
  "furnished",
  "mobility",
  "student",
]);
const LEASE_STATUSES = new Set(["active", "terminated", "archived"]);
const PAYMENT_METHODS = new Set([
  "virement",
  "cheque",
  "especes",
  "prelevement",
  "autre",
]);

const IRL_QUARTER_RE = /^T[1-4]-\d{4}$/;

// FEAT-042 : mode de charges (provisions | forfait). Source de vérité
// serveur — voir resolveChargeMode ci-dessous.
const CHARGE_MODES = new Set(["provisions", "forfait"]);

/**
 * Impose la cohérence type de bail ↔ mode de charges et renvoie le mode
 * canonique à persister. C'est la SOURCE DE VÉRITÉ serveur (le client ne
 * peut jamais forcer un mode incohérent) :
 *   - unfurnished (nu) → provisions (forcé, art. 23 loi du 6 juillet 1989)
 *   - mobility          → forfait   (forcé, loi ELAN art. 25-18)
 *   - furnished / student → libre ; défaut provisions si non fourni
 *
 * Rejette explicitement un `requested` incompatible avec un type à mode
 * forcé (ex: forfait demandé sur un bail nu) plutôt que de le silencer.
 */
export function resolveChargeMode(
  leaseType: string,
  requested: unknown,
): string {
  if (leaseType === "unfurnished") {
    if (requested != null && requested !== "provisions") {
      throw new HttpsError(
        "invalid-argument",
        "unfurnished lease must use provisions charge mode",
      );
    }
    return "provisions";
  }
  if (leaseType === "mobility") {
    if (requested != null && requested !== "forfait") {
      throw new HttpsError(
        "invalid-argument",
        "mobility lease must use forfait charge mode",
      );
    }
    return "forfait";
  }
  // furnished | student : libre, défaut provisions.
  if (requested == null) return "provisions";
  if (typeof requested !== "string" || !CHARGE_MODES.has(requested)) {
    throw new HttpsError("invalid-argument", "invalid chargeMode");
  }
  return requested;
}

// FEAT-056 : le plafond de baux ACTIFS vient désormais de la table générée
// (`config/entitlements.json`), résolue sur le PALIER EFFECTIF — plus de
// constante locale ni de switch sur `subscriptionTier`.

// ============================================================================
// createLease
// ============================================================================
export const createLease = onCall(
  {region: "europe-west1"},
  async (request) => {
    const uid = requireAuthUid(request);
    const data = asBag(request.data);

    const propertyId = requireString(data.propertyId, "propertyId");
    const tenantId = requireString(data.tenantId, "tenantId");
    const rentAmountCents = requireInt(
      data.rentAmountCents,
      "rentAmountCents",
      {min: 1},
    );
    const chargesAmountCents = requireInt(
      data.chargesAmountCents ?? 0,
      "chargesAmountCents",
      {min: 0},
    );
    // FEAT-036 : part non récupérable (à charge du bailleur, informatif).
    // chargesAmountCents reste la part récupérable, inchangée. Pas de
    // contrainte total = récupérable + non-récupérable : aucun champ total
    // n'est persisté (voir plan FEAT-036 §c).
    let nonRecoverableChargesCents = requireInt(
      data.nonRecoverableChargesCents ?? 0,
      "nonRecoverableChargesCents",
      {min: 0},
    );
    const startDate = toTimestamp(data.startDate, "startDate");
    const endDate = optionalTimestamp(data.endDate, "endDate");
    const status = requireString(data.status ?? "active", "status");
    if (!LEASE_STATUSES.has(status)) {
      throw new HttpsError("invalid-argument", `invalid status: ${status}`);
    }
    const leaseType = requireString(data.leaseType, "leaseType");
    if (!LEASE_TYPES.has(leaseType)) {
      throw new HttpsError(
        "invalid-argument",
        `invalid leaseType: ${leaseType}`,
      );
    }
    // FEAT-042 : mode de charges résolu/imposé serveur (voir
    // resolveChargeMode). Un forfait est un montant unique libératoire —
    // il ne se ventile pas : on force la part non récupérable à 0.
    const chargeMode = resolveChargeMode(leaseType, data.chargeMode);
    if (chargeMode === "forfait") {
      nonRecoverableChargesCents = 0;
    }
    const paymentDay = requireInt(data.paymentDay, "paymentDay", {
      min: 1,
      max: 28,
    });
    const paymentMethod = requireString(data.paymentMethod, "paymentMethod");
    if (!PAYMENT_METHODS.has(paymentMethod)) {
      throw new HttpsError(
        "invalid-argument",
        `invalid paymentMethod: ${paymentMethod}`,
      );
    }
    const depositAmountCents = optionalInt(
      data.depositAmountCents,
      "depositAmountCents",
      {min: 0},
    );
    const irlIndexValue = optionalNumber(data.irlIndexValue, "irlIndexValue");
    const irlQuarterRef = optionalString(data.irlQuarterRef, "irlQuarterRef");
    if (irlQuarterRef !== null && !IRL_QUARTER_RE.test(irlQuarterRef)) {
      throw new HttpsError(
        "invalid-argument",
        "irlQuarterRef format T[1-4]-YYYY",
      );
    }
    const agencyFeesCents = requireInt(
      data.agencyFeesCents ?? 0,
      "agencyFeesCents",
      {min: 0},
    );
    const solidarityClause = requireBool(
      data.solidarityClause,
      "solidarityClause",
    );
    const entryInventoryDone = requireBool(
      data.entryInventoryDone,
      "entryInventoryDone",
    );

    const db = dbForRequest(request);
    const leaseRef = db.collection("leases").doc();
    const propertyRef = db.doc(`properties/${propertyId}`);
    const tenantRef = db.doc(`tenants/${tenantId}`);
    const landlordRef = db.doc(`landlords/${uid}`);

    // FEAT-044 : fail-closed sur activeLeasesCount absent (compte legacy) —
    // recompte les baux ACTIFS en direct pour fermer le gate. Pertinent
    // uniquement si on crée un bail actif. count() n'existe pas en transaction.
    let seededLeaseCount: number | null = null;
    if (status === "active") {
      const preSnap = await landlordRef.get();
      if (preSnap.exists) {
        const preData = (preSnap.data() ?? {}) as Record<string, unknown>;
        if (typeof preData.activeLeasesCount !== "number") {
          const agg = await db
            .collection("leases")
            .where("landlordId", "==", uid)
            .where("status", "==", "active")
            .where("deletedAt", "==", null)
            .count()
            .get();
          seededLeaseCount = agg.data().count;
        }
      }
    }

    return await db.runTransaction(async (tx) => {
      const [propertySnap, tenantSnap, landlordSnap] = await Promise.all([
        tx.get(propertyRef),
        tx.get(tenantRef),
        tx.get(landlordRef),
      ]);

      const property = dataOrFail(propertySnap, "property not found");
      assertOwnedAndActive(property, uid, "property");
      const tenant = dataOrFail(tenantSnap, "tenant not found");
      assertOwnedAndActive(tenant, uid, "tenant");
      const landlord = dataOrFail(landlordSnap, "landlord not found");

      // FEAT-044 : plafond de baux actifs (uniquement pour un bail actif).
      const leaseRawCount = landlord.activeLeasesCount;
      const leaseHasCounter = typeof leaseRawCount === "number";
      if (status === "active") {
        const limit = quotaLimit(resolvePlan(landlord), "activeLeases");
        const count = leaseHasCounter ? leaseRawCount : (seededLeaseCount ?? 0);
        if (limit !== null && count >= limit) {
          throw new HttpsError(
            "resource-exhausted",
            errorCodeFor("activeLeases"),
          );
        }
      }

      const now = admin.firestore.FieldValue.serverTimestamp();
      tx.set(leaseRef, {
        id: leaseRef.id,
        landlordId: uid,
        propertyId,
        tenantId,
        propertyName: property.name,
        // Adresse COMPLÈTE (rue + code postal + ville) : `properties` porte
        // ces trois champs séparément et le formulaire ne met en pratique que
        // la rue dans `address`. Cette snapshot alimente la quittance, où le
        // logement doit être identifiable (loi du 6 juillet 1989) — d'où la
        // composition ici, au seul point d'écriture du champ. Voir
        // `utils/property_address.ts` pour la robustesse aux doublons.
        propertyAddress: composePropertyAddress({
          address: property.address,
          postalCode: property.postalCode,
          city: property.city,
        }),
        tenantFirstName: tenant.firstName,
        tenantLastName: tenant.lastName,
        tenantEmail: tenant.email,
        rentAmountCents,
        chargesAmountCents,
        nonRecoverableChargesCents,
        startDate,
        endDate,
        status,
        leaseType,
        chargeMode,
        depositAmountCents,
        paymentDay,
        paymentMethod,
        irlIndexValue,
        irlQuarterRef,
        agencyFeesCents,
        solidarityClause,
        entryInventoryDone,
        createdAt: now,
        updatedAt: now,
        deletedAt: null,
      });

      if (status === "active") {
        tx.update(propertyRef, {
          activeLeaseCount: admin.firestore.FieldValue.increment(1),
        });
        tx.update(tenantRef, {
          activeLeaseCount: admin.firestore.FieldValue.increment(1),
        });
        // FEAT-044 : compteur de baux actifs du bailleur — sème la vraie valeur
        // (recomptée) sur un compte legacy sans compteur, sinon incrémente.
        if (leaseHasCounter) {
          tx.update(landlordRef, {
            activeLeasesCount: admin.firestore.FieldValue.increment(1),
          });
        } else {
          tx.update(landlordRef, {
            activeLeasesCount: (seededLeaseCount ?? 0) + 1,
          });
        }
      }

      return {leaseId: leaseRef.id};
    });
  },
);

// ============================================================================
// updateLease — champs mutables uniquement (propertyId/tenantId immuables)
// ============================================================================
const LEASE_MUTABLE_FIELDS = new Set([
  "rentAmountCents",
  "chargesAmountCents",
  "nonRecoverableChargesCents",
  "endDate",
  "status",
  "leaseType",
  "chargeMode",
  "depositAmountCents",
  "paymentDay",
  "paymentMethod",
  "irlIndexValue",
  "irlQuarterRef",
  "agencyFeesCents",
  "solidarityClause",
  "entryInventoryDone",
]);

export const updateLease = onCall(
  {region: "europe-west1"},
  async (request) => {
    const uid = requireAuthUid(request);
    const data = asBag(request.data);
    const id = requireString(data.id, "id");
    const patch = asBag(data.patch);

    const cleanPatch: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(patch)) {
      if (!LEASE_MUTABLE_FIELDS.has(k)) {
        throw new HttpsError(
          "invalid-argument",
          `field ${k} is immutable or unknown`,
        );
      }
      if (k === "endDate") {
        cleanPatch[k] = v == null ? null : toTimestamp(v, "endDate");
      } else {
        cleanPatch[k] = v;
      }
    }
    if (cleanPatch.status !== undefined) {
      if (
        typeof cleanPatch.status !== "string" ||
        !LEASE_STATUSES.has(cleanPatch.status)
      ) {
        throw new HttpsError("invalid-argument", "invalid status");
      }
    }
    if (cleanPatch.leaseType !== undefined) {
      if (
        typeof cleanPatch.leaseType !== "string" ||
        !LEASE_TYPES.has(cleanPatch.leaseType)
      ) {
        throw new HttpsError("invalid-argument", "invalid leaseType");
      }
    }
    // FEAT-036 : nonRecoverableChargesCents transite par cleanPatch sans
    // transformation de type (comme agencyFeesCents) ; on borne juste ici,
    // à l'instar de status/paymentMethod ci-dessus.
    if (cleanPatch.nonRecoverableChargesCents !== undefined) {
      if (
        typeof cleanPatch.nonRecoverableChargesCents !== "number" ||
        !Number.isInteger(cleanPatch.nonRecoverableChargesCents) ||
        cleanPatch.nonRecoverableChargesCents < 0
      ) {
        throw new HttpsError(
          "invalid-argument",
          "nonRecoverableChargesCents must be an integer >= 0",
        );
      }
    }

    const db = dbForRequest(request);
    const leaseRef = db.doc(`leases/${id}`);

    // FEAT-044 : fail-closed sur activeLeasesCount absent (compte legacy) —
    // même recompte que createLease, pour que la RÉACTIVATION d'un bail ne
    // contourne pas le plafond tant que le compteur n'a pas été semé.
    // count() n'existe pas en transaction. Pertinent uniquement si le patch
    // peut réactiver (status demandé = active).
    let seededLeaseCount: number | null = null;
    if (cleanPatch.status === "active") {
      const preSnap = await db.doc(`landlords/${uid}`).get();
      if (preSnap.exists) {
        const preData = (preSnap.data() ?? {}) as Record<string, unknown>;
        if (typeof preData.activeLeasesCount !== "number") {
          const agg = await db
            .collection("leases")
            .where("landlordId", "==", uid)
            .where("status", "==", "active")
            .where("deletedAt", "==", null)
            .count()
            .get();
          seededLeaseCount = agg.data().count;
        }
      }
    }

    return await db.runTransaction(async (tx) => {
      const snap = await tx.get(leaseRef);
      const lease = dataOrFail(snap, "lease not found");
      assertOwnedAndActive(lease, uid, "lease");

      const oldStatus = typeof lease.status === "string" ? lease.status : "";
      const newStatusUnknown = cleanPatch.status;
      const newStatus =
        typeof newStatusUnknown === "string" ? newStatusUnknown : oldStatus;
      const wasActive = oldStatus === "active";
      const isActive = newStatus === "active";
      const delta = isActive === wasActive ? 0 : isActive ? 1 : -1;

      // FEAT-044 : sur transition de status, lire le doc landlord AVANT toute
      // écriture (reads-before-writes) pour (a) re-vérifier le plafond en cas
      // de réactivation et (b) maintenir activeLeasesCount. Lu uniquement si le
      // status change (delta !== 0).
      let landlordActiveLeases: number | null = null;
      if (delta !== 0) {
        const lsnap = await tx.get(db.doc(`landlords/${uid}`));
        const ldata = (lsnap.data() ?? {}) as Record<string, unknown>;
        const raw = ldata.activeLeasesCount;
        landlordActiveLeases = typeof raw === "number" ? raw : null;
        if (delta === 1) {
          // Réactivation (terminé/archivé → actif) : le bien et le locataire
          // doivent encore exister et ne pas être soft-deleted — sinon on
          // ressusciterait leur activeLeaseCount et on produirait un bail
          // actif pointant vers une entité supprimée.
          const propertyId = lease.propertyId;
          const tenantId = lease.tenantId;
          if (typeof propertyId === "string" && typeof tenantId === "string") {
            const [psnap, tsnap] = await Promise.all([
              tx.get(db.doc(`properties/${propertyId}`)),
              tx.get(db.doc(`tenants/${tenantId}`)),
            ]);
            const property = dataOrFail(psnap, "property not found");
            assertOwnedAndActive(property, uid, "property");
            const tenant = dataOrFail(tsnap, "tenant not found");
            assertOwnedAndActive(tenant, uid, "tenant");
          }
          // Re-vérifier le plafond. Compteur absent (legacy) → fail-closed
          // sur le recompte pré-transaction (miroir createLease).
          const limit = quotaLimit(resolvePlan(ldata), "activeLeases");
          const count = landlordActiveLeases ?? seededLeaseCount ?? 0;
          if (limit !== null && count >= limit) {
            throw new HttpsError(
              "resource-exhausted",
              errorCodeFor("activeLeases"),
            );
          }
        }
      }

      // FEAT-042 : le type de bail est mutable → re-résoudre la cohérence
      // type↔mode sur l'état FINAL (après patch), pas seulement sur le
      // patch. Cela coerce aussi les baux existants qui basculent vers un
      // type à mode forcé (ex: meublé forfait → mobilité reste forfait ;
      // meublé forfait → nu redevient provisions).
      //
      // La résolution est INCONDITIONNELLE : on dérive toujours le mode
      // EFFECTIF via resolveChargeMode, même si le patch ne touche ni
      // leaseType ni chargeMode. C'est indispensable pour les baux LEGACY
      // pré-042 dont le `chargeMode` n'est pas persisté (undefined) : un
      // mobilité legacy a un mode effectif forfait bien que rien ne soit
      // stocké. Sans cette dérivation, un patch qui ne touche ni leaseType
      // ni chargeMode (ex: {nonRecoverableChargesCents: 999}) sauterait le
      // forçage forfait⇒0 et laisserait persister une ventilation illégale.
      //
      // Le "requested" passé à resolveChargeMode ne doit être le
      // `chargeMode` PERSISTÉ que si le leaseType ne change pas (validation
      // d'un changement de mode isolé, contre le type courant). Si le
      // leaseType change, seul un `chargeMode` explicitement fourni dans CE
      // patch compte comme une intention client à valider/rejeter — l'ancien
      // `chargeMode` persisté (qui reflète l'ancien type) doit être ignoré
      // pour laisser resolveChargeMode dériver librement le défaut du
      // nouveau type, plutôt que d'être traité comme un conflit explicite.
      // Pour un legacy sans leaseType patché, `requestedChargeMode` vaut
      // `lease.chargeMode` (undefined) → resolveChargeMode dérive le défaut
      // du type courant (ex: mobility → forfait).
      const leaseTypeChanged = cleanPatch.leaseType !== undefined;
      const finalLeaseType = leaseTypeChanged ?
        (cleanPatch.leaseType as string) :
        (lease.leaseType as string);
      const requestedChargeMode =
        cleanPatch.chargeMode !== undefined ?
          cleanPatch.chargeMode :
          leaseTypeChanged ? undefined : lease.chargeMode;
      const finalChargeMode = resolveChargeMode(
        finalLeaseType,
        requestedChargeMode,
      );
      // Backfill lazy : on persiste toujours le mode effectif résolu, ce qui
      // matérialise le mode d'un bail legacy à la première mutation.
      cleanPatch.chargeMode = finalChargeMode;
      // Forfait ⇒ pas de ventilation : un forfait est un montant unique
      // libératoire, on force la part non récupérable à 0 côté serveur, sur
      // le mode EFFECTIF (donc y compris pour un mobilité legacy dont le mode
      // n'était pas encore persisté).
      if (finalChargeMode === "forfait") {
        cleanPatch.nonRecoverableChargesCents = 0;
      }

      tx.update(leaseRef, {
        ...cleanPatch,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      if (delta !== 0) {
        const propertyId = lease.propertyId;
        const tenantId = lease.tenantId;
        if (typeof propertyId === "string" && typeof tenantId === "string") {
          tx.update(db.doc(`properties/${propertyId}`), {
            activeLeaseCount: admin.firestore.FieldValue.increment(delta),
          });
          tx.update(db.doc(`tenants/${tenantId}`), {
            activeLeaseCount: admin.firestore.FieldValue.increment(delta),
          });
        }
        // FEAT-044 : compteur de baux actifs du bailleur. Écriture absolue
        // clampée à 0 (basée sur la valeur relue en transaction → race-safe),
        // jamais négative. Compteur absent (legacy) : la réactivation sème la
        // vraie valeur recomptée +1 (miroir createLease) ; la désactivation ne
        // touche à rien (le compteur sera semé au prochain create/réactivation).
        if (landlordActiveLeases !== null) {
          tx.update(db.doc(`landlords/${uid}`), {
            activeLeasesCount: Math.max(0, landlordActiveLeases + delta),
          });
        } else if (delta === 1) {
          tx.update(db.doc(`landlords/${uid}`), {
            activeLeasesCount: (seededLeaseCount ?? 0) + 1,
          });
        }
      }

      return {updated: true};
    });
  },
);

// ============================================================================
// createPayment — cross-entity (lease ownership)
// ============================================================================
export const createPayment = onCall(
  {region: "europe-west1"},
  async (request) => {
    const uid = requireAuthUid(request);
    const data = asBag(request.data);

    const leaseId = requireString(data.leaseId, "leaseId");
    const periodStart = toTimestamp(data.periodStart, "periodStart");
    const periodEnd = toTimestamp(data.periodEnd, "periodEnd");
    const paidAt = toTimestamp(data.paidAt, "paidAt");
    const rentAmountCents = requireInt(
      data.rentAmountCents,
      "rentAmountCents",
      {min: 1},
    );
    const chargesAmountCents = requireInt(
      data.chargesAmountCents ?? 0,
      "chargesAmountCents",
      {min: 0},
    );
    const paymentMethod = requireString(data.paymentMethod, "paymentMethod");
    if (!PAYMENT_METHODS.has(paymentMethod)) {
      throw new HttpsError("invalid-argument", "invalid paymentMethod");
    }
    const notes = optionalString(data.notes, "notes");
    const reference = optionalString(data.reference, "reference");

    const db = dbForRequest(request);
    const leaseRef = db.doc(`leases/${leaseId}`);
    const paymentRef = db.collection("payments").doc();

    return await db.runTransaction(async (tx) => {
      const leaseSnap = await tx.get(leaseRef);
      const lease = dataOrFail(leaseSnap, "lease not found");
      assertOwnedAndActive(lease, uid, "lease");

      const now = admin.firestore.FieldValue.serverTimestamp();
      tx.set(paymentRef, {
        id: paymentRef.id,
        landlordId: uid,
        leaseId,
        propertyName: lease.propertyName,
        tenantLastName: lease.tenantLastName,
        periodStart,
        periodEnd,
        paidAt,
        rentAmountCents,
        chargesAmountCents,
        paymentMethod,
        notes,
        reference,
        createdAt: now,
        updatedAt: now,
        deletedAt: null,
      });

      return {paymentId: paymentRef.id};
    });
  },
);

// ============================================================================
// updatePayment — champs mutables uniquement
// ============================================================================
const PAYMENT_MUTABLE_FIELDS = new Set([
  "paidAt",
  "paymentMethod",
  "notes",
  "reference",
]);

export const updatePayment = onCall(
  {region: "europe-west1"},
  async (request) => {
    const uid = requireAuthUid(request);
    const data = asBag(request.data);
    const id = requireString(data.id, "id");
    const patch = asBag(data.patch);

    const cleanPatch: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(patch)) {
      if (!PAYMENT_MUTABLE_FIELDS.has(k)) {
        throw new HttpsError(
          "invalid-argument",
          `field ${k} immutable/unknown`,
        );
      }
      if (k === "paidAt") {
        cleanPatch[k] = toTimestamp(v, "paidAt");
      } else {
        cleanPatch[k] = v;
      }
    }
    if (cleanPatch.paymentMethod !== undefined) {
      if (
        typeof cleanPatch.paymentMethod !== "string" ||
        !PAYMENT_METHODS.has(cleanPatch.paymentMethod)
      ) {
        throw new HttpsError("invalid-argument", "invalid paymentMethod");
      }
    }

    const db = dbForRequest(request);
    const ref = db.doc(`payments/${id}`);
    const snap = await ref.get();
    const p = dataOrFail(snap, "payment not found");
    assertOwnedAndActive(p, uid, "payment");

    await ref.update({
      ...cleanPatch,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {updated: true};
  },
);
