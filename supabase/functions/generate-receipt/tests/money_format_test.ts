/**
 * Unit tests for money formatting helpers used in the PDF.
 * Validates French locale number formatting per LEGAL.md.
 *
 * Run: deno test supabase/functions/generate-receipt/tests/money_format_test.ts
 */
import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  formatEurosFromCents,
  formatDateFr,
  formatMonthYearFr,
} from "../../_shared/money_format.ts";

// ---------------------------------------------------------------------------
// formatEurosFromCents
// ---------------------------------------------------------------------------

// money_format.ts uses U+00A0 (non-breaking space) as thousands separator
// and before the euro sign, per fr-FR convention specified in LEGAL.md.
const NBSP = " "; // non-breaking space U+00A0

Deno.test("formatEurosFromCents: 100 cents = 1,00 NBSP euro", () => {
  assertEquals(formatEurosFromCents(100), `1,00${NBSP}€`);
});

Deno.test("formatEurosFromCents: 123456 cents = 1 NBSP 234,56 NBSP euro", () => {
  assertEquals(formatEurosFromCents(123456), `1${NBSP}234,56${NBSP}€`);
});

Deno.test("formatEurosFromCents: 120000 cents = 1 NBSP 200,00 NBSP euro", () => {
  assertEquals(formatEurosFromCents(120000), `1${NBSP}200,00${NBSP}€`);
});

Deno.test("formatEurosFromCents: 0 cents = 0,00 NBSP euro", () => {
  assertEquals(formatEurosFromCents(0), `0,00${NBSP}€`);
});

Deno.test("formatEurosFromCents: large amount 1234567 cents", () => {
  assertEquals(formatEurosFromCents(1234567), `12${NBSP}345,67${NBSP}€`);
});

Deno.test("formatEurosFromCents: 50 cents = 0,50 NBSP euro", () => {
  assertEquals(formatEurosFromCents(50), `0,50${NBSP}€`);
});

// ---------------------------------------------------------------------------
// formatDateFr
// ---------------------------------------------------------------------------

Deno.test("formatDateFr: ISO string 2026-05-31 -> 31/05/2026", () => {
  assertEquals(formatDateFr("2026-05-31"), "31/05/2026");
});

Deno.test("formatDateFr: ISO string 2026-01-01 -> 01/01/2026", () => {
  assertEquals(formatDateFr("2026-01-01"), "01/01/2026");
});

Deno.test("formatDateFr: Date object", () => {
  const d = new Date("2026-12-25T00:00:00Z");
  assertEquals(formatDateFr(d), "25/12/2026");
});

// ---------------------------------------------------------------------------
// formatMonthYearFr
// ---------------------------------------------------------------------------

Deno.test("formatMonthYearFr: 2026-05-01 -> mai 2026", () => {
  assertEquals(formatMonthYearFr("2026-05-01"), "mai 2026");
});

Deno.test("formatMonthYearFr: 2026-01-15 -> janvier 2026", () => {
  assertEquals(formatMonthYearFr("2026-01-15"), "janvier 2026");
});

Deno.test("formatMonthYearFr: 2026-12-01 -> decembre 2026", () => {
  assertEquals(formatMonthYearFr("2026-12-01"), "decembre 2026");
});

Deno.test("formatMonthYearFr: 2025-02-28 -> fevrier 2025", () => {
  assertEquals(formatMonthYearFr("2025-02-28"), "fevrier 2025");
});
