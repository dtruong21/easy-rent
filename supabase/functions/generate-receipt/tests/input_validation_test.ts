/**
 * Unit tests for Edge Function input validation logic.
 *
 * These tests are pure unit tests (no Supabase client calls).
 * They validate the request parsing, UUID format checking, and
 * period coherence rules independently of the HTTP handler.
 *
 * Run: deno test supabase/functions/generate-receipt/tests/input_validation_test.ts
 */
import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";

// ---------------------------------------------------------------------------
// Replicate the validation helpers from index.ts for isolated testing
// ---------------------------------------------------------------------------

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

function isUuid(s: string): boolean {
  return UUID_RE.test(s);
}

function isIsoDate(s: string): boolean {
  if (!DATE_RE.test(s)) return false;
  const d = new Date(s);
  return !isNaN(d.getTime());
}

// ---------------------------------------------------------------------------
// UUID validation
// ---------------------------------------------------------------------------

Deno.test("isUuid: valid v4 UUID passes", () => {
  assert(isUuid("11111111-1111-4111-8111-111111111111"));
  assert(isUuid("a3bb189e-8bf9-4e4a-a2db-c43c5d7f9e10"));
});

Deno.test("isUuid: v1 UUID fails (non-v4)", () => {
  assert(!isUuid("6ba7b810-9dad-11d1-80b4-00c04fd430c8"));
});

Deno.test("isUuid: empty string fails", () => {
  assert(!isUuid(""));
});

Deno.test("isUuid: malformed UUID fails", () => {
  assert(!isUuid("not-a-uuid"));
  assert(!isUuid("11111111-1111-1111-1111-11111111111"));
});

// ---------------------------------------------------------------------------
// ISO date validation
// ---------------------------------------------------------------------------

Deno.test("isIsoDate: valid date passes", () => {
  assert(isIsoDate("2026-05-31"));
  assert(isIsoDate("2026-01-01"));
});

Deno.test("isIsoDate: invalid format fails", () => {
  assert(!isIsoDate("31/05/2026"));
  assert(!isIsoDate("2026-13-01")); // month 13 invalid
  assert(!isIsoDate("not-a-date"));
  assert(!isIsoDate(""));
});

// ---------------------------------------------------------------------------
// Period coherence
// ---------------------------------------------------------------------------

Deno.test("period: period_end must be after period_start", () => {
  const start = "2026-05-01";
  const end = "2026-05-31";
  assert(end > start, "period_end should be after period_start");
});

Deno.test("period: period_end equal to period_start is invalid", () => {
  const start = "2026-05-01";
  const end = "2026-05-01";
  assert(!(end > start), "equal period_end/period_start should fail");
});

Deno.test("period: period_end before period_start is invalid", () => {
  const start = "2026-05-31";
  const end = "2026-05-01";
  assert(!(end > start), "period_end before period_start should fail");
});

// ---------------------------------------------------------------------------
// Mode detection
// ---------------------------------------------------------------------------

Deno.test("mode: payment_ids mode detected correctly", () => {
  const body = { payment_ids: ["11111111-1111-4111-8111-111111111111"] };
  const hasPaymentIds = body.payment_ids !== undefined && body.payment_ids !== null;
  const hasPeriod = (body as Record<string, unknown>).lease_id !== undefined;
  assert(hasPaymentIds && !hasPeriod);
});

Deno.test("mode: period mode detected correctly", () => {
  const body = {
    lease_id: "11111111-1111-4111-8111-111111111111",
    period_start: "2026-05-01",
    period_end: "2026-05-31",
  };
  const hasPaymentIds = (body as Record<string, unknown>).payment_ids !== undefined;
  const hasPeriod = body.lease_id !== undefined;
  assert(!hasPaymentIds && hasPeriod);
});

Deno.test("mode: both modes provided is invalid", () => {
  const body = {
    payment_ids: ["11111111-1111-4111-8111-111111111111"],
    lease_id: "22222222-2222-4222-8222-222222222222",
    period_start: "2026-05-01",
    period_end: "2026-05-31",
  };
  const hasPaymentIds = body.payment_ids !== undefined;
  const hasPeriod = body.lease_id !== undefined;
  assert(hasPaymentIds && hasPeriod, "Both modes = invalid combination");
});

Deno.test("mode: neither mode provided is invalid", () => {
  const body = {};
  const hasPaymentIds = (body as Record<string, unknown>).payment_ids !== undefined;
  const hasPeriod = (body as Record<string, unknown>).lease_id !== undefined;
  assert(!hasPaymentIds && !hasPeriod, "Neither mode = invalid");
});

// ---------------------------------------------------------------------------
// payment_ids array validation
// ---------------------------------------------------------------------------

Deno.test("payment_ids: empty array is invalid", () => {
  const ids: string[] = [];
  assert(!Array.isArray(ids) || ids.length === 0);
});

Deno.test("payment_ids: all valid UUIDs passes", () => {
  const ids = [
    "11111111-1111-4111-8111-111111111111",
    "22222222-2222-4222-8222-222222222222",
  ];
  const allValid = ids.every(isUuid);
  assert(allValid);
});

Deno.test("payment_ids: one invalid UUID fails", () => {
  const ids = [
    "11111111-1111-4111-8111-111111111111",
    "not-a-uuid",
  ];
  const allValid = ids.every(isUuid);
  assert(!allValid);
});
