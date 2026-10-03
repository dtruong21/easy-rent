/**
 * createEtatDesLieux — callable (FEAT-037).
 *
 * Écrit un état des lieux immuable (Rules create/update/delete: if false),
 * patron `charge_statements`. Fige parties + adresse depuis le bail (loi
 * 6/7/1989). PDF rendu côté client depuis le snapshot (pas de Storage).
 */
import {FieldValue} from "firebase-admin/firestore";
import {logger} from "firebase-functions/v2";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {
  asBag,
  dataOrFail,
  optionalString,
  requireVerifiedUid,
  requireInt,
  requireString,
  toTimestamp,
} from "../utils/callable_helpers";
import {dbForRequest} from "../utils/db_router";

const TYPES = new Set(["entree", "sortie"]);
const CONDITIONS = new Set(["neuf", "bon", "moyen", "mauvais"]);

interface EdlElement {
  name: string;
  condition: string;
  comment: string | null;
}
interface EdlRoom {
  name: string;
  elements: EdlElement[];
}

/** Valide et normalise les pièces/éléments. Jette invalid-argument sinon. */
export function validateRooms(raw: unknown): EdlRoom[] {
  if (!Array.isArray(raw)) {
    throw new HttpsError("invalid-argument", "rooms must be an array");
  }
  return raw.map((r, i) => {
    const room = asBag(r);
    const elementsRaw = Array.isArray(room.elements) ? room.elements : [];
    const elements: EdlElement[] = elementsRaw.map((e, j) => {
      const el = asBag(e);
      const condition = requireString(el.condition, `rooms[${i}].elements[${j}].condition`);
      if (!CONDITIONS.has(condition)) {
        throw new HttpsError("invalid-argument", `invalid condition: ${condition}`);
      }
      return {
        name: requireString(el.name, `rooms[${i}].elements[${j}].name`),
        condition,
        comment: optionalString(el.comment, `rooms[${i}].elements[${j}].comment`) ?? null,
      };
    });
    return {name: requireString(room.name, `rooms[${i}].name`), elements};
  });
}

export const createEtatDesLieux = onCall(
  {region: "europe-west1"},
  async (request) => {
    const uid = await requireVerifiedUid(request);
    const data = asBag(request.data);

    const leaseId = requireString(data.leaseId, "leaseId");
    const type = requireString(data.type, "type");
    if (!TYPES.has(type)) {
      throw new HttpsError("invalid-argument", `invalid type: ${type}`);
    }
    const date = toTimestamp(data.date, "date");
    const keysCount = requireInt(data.keysCount, "keysCount");
    if (keysCount < 0) {
      throw new HttpsError("invalid-argument", "keysCount must be >= 0");
    }
    const rooms = validateRooms(data.rooms);
    const meter = asBag(data.meterReadings ?? {});
    const meterReadings = {
      waterIndex: optionalString(meter.waterIndex, "waterIndex") ?? null,
      electricityIndex: optionalString(meter.electricityIndex, "electricityIndex") ?? null,
      gasIndex: optionalString(meter.gasIndex, "gasIndex") ?? null,
    };
    const generalComment = optionalString(data.generalComment, "generalComment") ?? null;

    const db = await dbForRequest(request);

    // Landlord (fullName + address légaux : le décret 2016-382 exige le
    // domicile du bailleur sur l'EDL — même exigence que les quittances/régul).
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

    // Lease + ownership + non supprimé ; fige adresse + locataire
    const leaseSnap = await db.doc(`leases/${leaseId}`).get();
    const lease = dataOrFail(leaseSnap, "lease not found");
    if (String(lease.landlordId ?? "") !== uid) {
      throw new HttpsError("permission-denied", "lease not owned");
    }
    if (lease.deletedAt != null) {
      throw new HttpsError("failed-precondition", "lease is deleted");
    }
    const tenantFullName =
      `${String(lease.tenantFirstName ?? "")} ${String(lease.tenantLastName ?? "")}`.trim();
    const propertyAddress = String(lease.propertyAddress ?? "");

    const ref = db.collection("etat_des_lieux").doc();
    const id = ref.id;
    const now = FieldValue.serverTimestamp();
    try {
      await ref.set({
        id,
        landlordId: uid,
        leaseId,
        propertyId: String(lease.propertyId ?? ""),
        type,
        date,
        propertyAddress,
        landlordFullName,
        landlordAddress,
        tenantFullName,
        rooms,
        meterReadings,
        keysCount,
        generalComment,
        createdAt: now,
        schemaVersion: 1,
      });
    } catch (err) {
      logger.error("etat_des_lieux write failed", {uid, id, err});
      throw new HttpsError("internal", "etat_des_lieux_persist_failed");
    }

    logger.info("etat des lieux created", {uid, id, type});
    return {etatDesLieuxId: id};
  },
);
