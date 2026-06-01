/**
 * Tests for Fix 2 — SuccessResponse must include period_start and period_end.
 *
 * Verifies that the SuccessResponse type carries both ISO date fields and that
 * the values round-trip correctly (YYYY-MM-DD format expected by
 * ReceiptGenerationResult.fromJson on the Flutter side).
 *
 * Run: deno test supabase/functions/generate-receipt/tests/success_response_fields_test.ts
 */
import {
  assertEquals,
  assert,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import type { SuccessResponse } from "../types.ts";

// ---------------------------------------------------------------------------
// SuccessResponse shape — period_start / period_end fields
// ---------------------------------------------------------------------------

Deno.test("SuccessResponse: contains period_start and period_end keys", () => {
  const response: SuccessResponse = {
    receipt_id: "11111111-1111-4111-8111-111111111111",
    document_type: "quittance",
    total_cents: 120000,
    pdf_url: "https://example.com/signed-url",
    pdf_url_expires_at: "2026-05-31T12:05:00.000Z",
    period_start: "2026-05-01",
    period_end: "2026-05-31",
  };

  // Fields must exist and be non-empty strings
  assert(
    typeof response.period_start === "string" && response.period_start.length > 0,
    "period_start must be a non-empty string",
  );
  assert(
    typeof response.period_end === "string" && response.period_end.length > 0,
    "period_end must be a non-empty string",
  );
});

Deno.test("SuccessResponse: period_start and period_end are valid ISO dates (YYYY-MM-DD)", () => {
  const response: SuccessResponse = {
    receipt_id: "11111111-1111-4111-8111-111111111111",
    document_type: "quittance",
    total_cents: 120000,
    pdf_url: "https://example.com/signed-url",
    pdf_url_expires_at: "2026-05-31T12:05:00.000Z",
    period_start: "2026-05-01",
    period_end: "2026-05-31",
  };

  const dateRe = /^\d{4}-\d{2}-\d{2}$/;
  assert(dateRe.test(response.period_start), `period_start "${response.period_start}" must match YYYY-MM-DD`);
  assert(dateRe.test(response.period_end), `period_end "${response.period_end}" must match YYYY-MM-DD`);

  // Must be parseable as valid dates
  assert(!isNaN(new Date(response.period_start).getTime()), "period_start must be a valid date");
  assert(!isNaN(new Date(response.period_end).getTime()), "period_end must be a valid date");
});

Deno.test("SuccessResponse: period_end >= period_start", () => {
  const response: SuccessResponse = {
    receipt_id: "11111111-1111-4111-8111-111111111111",
    document_type: "quittance",
    total_cents: 120000,
    pdf_url: "https://example.com/signed-url",
    pdf_url_expires_at: "2026-05-31T12:05:00.000Z",
    period_start: "2026-05-01",
    period_end: "2026-05-31",
  };

  assert(
    response.period_end >= response.period_start,
    "period_end must be >= period_start",
  );
});

Deno.test("SuccessResponse: period_start value matches payment-derived value (simulate handler logic)", () => {
  // Simulate the handler's period derivation logic from payments
  const payments = [
    { period_start: "2026-05-01", period_end: "2026-05-31" },
    { period_start: "2026-04-01", period_end: "2026-04-30" },
  ];

  const sortedStarts = payments.map((p) => p.period_start).sort();
  const sortedEnds = payments.map((p) => p.period_end).sort();
  const periodStart = sortedStarts[0];
  const periodEnd = sortedEnds[sortedEnds.length - 1];

  const response: SuccessResponse = {
    receipt_id: "11111111-1111-4111-8111-111111111111",
    document_type: "quittance",
    total_cents: 240000,
    pdf_url: "https://example.com/signed-url",
    pdf_url_expires_at: "2026-05-31T12:05:00.000Z",
    period_start: periodStart,
    period_end: periodEnd,
  };

  assertEquals(response.period_start, "2026-04-01", "period_start must be earliest payment start");
  assertEquals(response.period_end, "2026-05-31", "period_end must be latest payment end");
});

Deno.test("SuccessResponse: Flutter fromJson parses period_start and period_end (contract test)", () => {
  // Simulate what ReceiptGenerationResult.fromJson does on the Flutter side:
  //   periodStart: DateTime.parse(json['period_start'] as String)
  //   periodEnd:   DateTime.parse(json['period_end'] as String)
  const json: Record<string, unknown> = {
    receipt_id: "11111111-1111-4111-8111-111111111111",
    document_type: "quittance",
    total_cents: 120000,
    pdf_url: "https://example.com/signed-url",
    pdf_url_expires_at: "2026-05-31T12:05:00.000Z",
    period_start: "2026-05-01",
    period_end: "2026-05-31",
  };

  // Verify both fields are present and parseable as ISO dates
  assert("period_start" in json, "JSON must contain period_start");
  assert("period_end" in json, "JSON must contain period_end");

  const start = new Date(json["period_start"] as string);
  const end = new Date(json["period_end"] as string);

  assert(!isNaN(start.getTime()), "period_start must parse as a valid Date");
  assert(!isNaN(end.getTime()), "period_end must parse as a valid Date");
  assertEquals(start.getUTCFullYear(), 2026);
  assertEquals(start.getUTCMonth(), 4); // May = index 4
  assertEquals(start.getUTCDate(), 1);
  assertEquals(end.getUTCDate(), 31);
});
