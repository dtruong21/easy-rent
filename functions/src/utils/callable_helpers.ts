/**
 * Helpers de typage pour les Callables (input validation + Firestore doc reads).
 *
 * Les Callable Cloud Functions reçoivent `request.data` typé `unknown`/`any`
 * — donc toute déstructuration sans validation runtime déclenche les
 * @typescript-eslint/no-unsafe-* rules. Ce module fournit une trousse de
 * helpers typés qui retournent des `unknown` puis valident, gardant le
 * code des handlers propre et type-safe.
 */

import type {DocumentSnapshot} from "firebase-admin/firestore";
import {Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import type {CallableRequest} from "firebase-functions/v2/https";

/** Cast input → bag typé. À utiliser comme première ligne d'un handler. */
export function asBag(input: unknown): Record<string, unknown> {
  if (input == null || typeof input !== "object") return {};
  return input as Record<string, unknown>;
}

export function requireAuthUid<T = unknown>(request: CallableRequest<T>): string {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "sign-in required");
  }
  return request.auth.uid;
}

export function requireString(value: unknown, name: string): string {
  if (typeof value !== "string" || value.length === 0) {
    throw new HttpsError(
      "invalid-argument",
      `${name} must be a non-empty string`,
    );
  }
  return value;
}

export function optionalString(value: unknown, name: string): string | null {
  if (value == null) return null;
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${name} must be a string`);
  }
  return value;
}

export function requireInt(
  value: unknown,
  name: string,
  opts?: {min?: number; max?: number},
): number {
  if (typeof value !== "number" || !Number.isInteger(value)) {
    throw new HttpsError("invalid-argument", `${name} must be an integer`);
  }
  if (opts?.min !== undefined && value < opts.min) {
    throw new HttpsError("invalid-argument", `${name} must be >= ${opts.min}`);
  }
  if (opts?.max !== undefined && value > opts.max) {
    throw new HttpsError("invalid-argument", `${name} must be <= ${opts.max}`);
  }
  return value;
}

export function optionalInt(
  value: unknown,
  name: string,
  opts?: {min?: number; max?: number},
): number | null {
  if (value == null) return null;
  return requireInt(value, name, opts);
}

export function optionalNumber(value: unknown, name: string): number | null {
  if (value == null) return null;
  if (typeof value !== "number") {
    throw new HttpsError("invalid-argument", `${name} must be a number`);
  }
  return value;
}

export function requireBool(value: unknown, _name: string): boolean {
  return value === true;
}

export function toTimestamp(value: unknown, name: string): Timestamp {
  if (value instanceof Timestamp) return value;
  if (typeof value === "string") {
    const d = new Date(value);
    if (Number.isNaN(d.getTime())) {
      throw new HttpsError("invalid-argument", `${name} not a valid date`);
    }
    return Timestamp.fromDate(d);
  }
  if (typeof value === "number") {
    return Timestamp.fromMillis(value);
  }
  throw new HttpsError("invalid-argument", `${name} must be a date`);
}

export function optionalTimestamp(
  value: unknown,
  name: string,
): Timestamp | null {
  if (value == null) return null;
  return toTimestamp(value, name);
}

/**
 * Lit les données d'un snapshot en garantissant un type Record (vs DocumentData
 * qui est `any`). Throw si le doc n'existe pas.
 */
export function dataOrFail(
  snap: DocumentSnapshot,
  notFoundMessage: string,
): Record<string, unknown> {
  if (!snap.exists) {
    throw new HttpsError("not-found", notFoundMessage);
  }
  const d = snap.data();
  if (!d) throw new HttpsError("internal", "empty doc data");
  return d as Record<string, unknown>;
}

/**
 * Vérifie l'ownership et le non-deleted d'une ressource (équivalent commun
 * aux RLS Postgres "USING landlord_id = auth.uid() AND deleted_at IS NULL").
 */
export function assertOwnedAndActive(
  data: Record<string, unknown>,
  uid: string,
  what: string,
): void {
  if (data.landlordId !== uid) {
    throw new HttpsError("permission-denied", `not owner of ${what}`);
  }
  if (data.deletedAt != null) {
    throw new HttpsError("failed-precondition", `${what} is deleted`);
  }
}
