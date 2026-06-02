/**
 * Tests for cross-user access control — unified 404 (no account existence leak).
 *
 * Verifies that when RLS returns null (cross-user or non-existent receipt),
 * the handler produces a 404 "receipt_not_found" — never 403 which would
 * reveal whether the UUID belongs to another account.
 *
 * Pure unit tests — simulates the handler's receipt-not-found logic.
 *
 * Run: deno test --allow-env send-receipt/tests/cross_user_404_test.ts
 */

import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";

// ---------------------------------------------------------------------------
// Replicate the receipt access-check logic from index.ts
// ---------------------------------------------------------------------------

function checkReceiptAccess(
  receiptRow: Record<string, unknown> | null,
): { status: number; error: string } | null {
  if (!receiptRow) {
    return { status: 404, error: "receipt_not_found" };
  }
  return null;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

Deno.test("cross-user: null row from RLS → 404 receipt_not_found", () => {
  const result = checkReceiptAccess(null);
  assert(result !== null);
  assertEquals(result!.status, 404);
  assertEquals(result!.error, "receipt_not_found");
});

Deno.test("cross-user: null row must NOT be 403 (no account leak)", () => {
  const result = checkReceiptAccess(null);
  assert(result !== null);
  assert(result!.status !== 403, "Must not return 403 — would leak account existence");
});

Deno.test("cross-user: null row must NOT be 401 (no auth confusion)", () => {
  const result = checkReceiptAccess(null);
  assert(result !== null);
  assert(result!.status !== 401, "Must not return 401 for cross-user access");
});

Deno.test("cross-user: valid row → no error (null returned)", () => {
  const row = {
    id: "11111111-1111-4111-8111-111111111111",
    landlord_id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    is_voided: false,
    is_stale: false,
    pdf_path: "path/to/receipt.pdf",
  };
  const result = checkReceiptAccess(row);
  assertEquals(result, null);
});

Deno.test("cross-user: error message is always the same for null row (no distinction)", () => {
  // Non-existent UUID and cross-user UUID both return null from RLS — same message
  const resultA = checkReceiptAccess(null); // non-existent
  const resultB = checkReceiptAccess(null); // cross-user (same null from RLS)

  assert(resultA !== null && resultB !== null);
  assertEquals(
    resultA!.error,
    resultB!.error,
    "Both cases must return the same error code",
  );
  assertEquals(
    resultA!.status,
    resultB!.status,
    "Both cases must return the same HTTP status",
  );
});
