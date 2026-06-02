/**
 * Unit tests for computeDocumentType helper.
 * Validates quittance vs recu classification per loi 6 juillet 1989, art. 21.
 *
 * Run: deno test --allow-net supabase/functions/generate-receipt/tests/compute_document_type_test.ts
 */
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { computeDocumentType } from "../pdf_layout.ts";

Deno.test("quittance: exact payment (rent + charges)", () => {
  assertEquals(computeDocumentType(120000, 100000, 20000), "quittance");
});

Deno.test("quittance: overpayment (more than due)", () => {
  assertEquals(computeDocumentType(130000, 100000, 20000), "quittance");
});

Deno.test("recu: partial payment (less than due)", () => {
  assertEquals(computeDocumentType(110000, 100000, 20000), "recu");
});

Deno.test("recu: zero charges — payment equals rent only — partial if lease has charges", () => {
  // lease has charges but payment covers only rent
  assertEquals(computeDocumentType(100000, 100000, 20000), "recu");
});

Deno.test("quittance: no charges on lease, payment equals rent", () => {
  assertEquals(computeDocumentType(100000, 100000, 0), "quittance");
});

Deno.test("recu: small partial payment", () => {
  assertEquals(computeDocumentType(1, 100000, 20000), "recu");
});

Deno.test("quittance: multi-payment summing to full amount", () => {
  // e.g., two payments of 60000 each = 120000 = rent(100000) + charges(20000)
  const totalCents = 60000 + 60000;
  assertEquals(computeDocumentType(totalCents, 100000, 20000), "quittance");
});

Deno.test("recu: multi-payment summing below due amount", () => {
  const totalCents = 50000 + 40000; // 90000 < 120000
  assertEquals(computeDocumentType(totalCents, 100000, 20000), "recu");
});

Deno.test("quittance: boundary — exactly at due amount", () => {
  assertEquals(computeDocumentType(100000, 100000, 0), "quittance");
});
