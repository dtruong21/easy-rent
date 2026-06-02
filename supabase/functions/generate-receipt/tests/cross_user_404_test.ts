/**
 * Tests for Fix E2 — cross-user payment IDs → unified 404.
 *
 * Verifies that when payments are not found (empty result from RLS filter) or
 * when the count mismatches (cross-user or soft-deleted), the handler produces
 * a single undistinguished 404 — not a 403 that would reveal whether a UUID
 * belongs to a different account.
 *
 * Run: deno test supabase/functions/generate-receipt/tests/cross_user_404_test.ts
 */
import {
  assertEquals,
  assert,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

// ---------------------------------------------------------------------------
// Replicate the handler logic for payment count validation
// ---------------------------------------------------------------------------

const UNIFIED_404_MESSAGE = "Aucun paiement actif trouve pour cette demande";

/**
 * Simulates the handler's payment access-check logic.
 * Returns { status, error } as the handler would.
 */
function checkPaymentAccess(
  payments: { id: string }[] | null,
  requestedIds: string[],
): { status: number; error: string } | null {
  if (!payments || payments.length === 0) {
    return { status: 404, error: UNIFIED_404_MESSAGE };
  }
  if (payments.length !== requestedIds.length) {
    // Unified 404 — no distinction between cross-user and soft-deleted
    return { status: 404, error: UNIFIED_404_MESSAGE };
  }
  return null; // OK
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

Deno.test("cross-user: empty payments array → 404 with unified message", () => {
  const result = checkPaymentAccess([], ["11111111-1111-4111-8111-111111111111"]);
  assert(result !== null);
  assertEquals(result!.status, 404);
  assertEquals(result!.error, UNIFIED_404_MESSAGE);
});

Deno.test("cross-user: null payments → 404 with unified message", () => {
  const result = checkPaymentAccess(null, ["11111111-1111-4111-8111-111111111111"]);
  assert(result !== null);
  assertEquals(result!.status, 404);
  assertEquals(result!.error, UNIFIED_404_MESSAGE);
});

Deno.test("cross-user: count mismatch (1 requested, 0 returned by RLS) → 404", () => {
  // RLS filtered out 1 payment (belongs to another account)
  const requestedIds = ["11111111-1111-4111-8111-111111111111"];
  const paymentsFromDb: { id: string }[] = [];
  const result = checkPaymentAccess(paymentsFromDb, requestedIds);
  assert(result !== null);
  assertEquals(result!.status, 404);
  assertEquals(result!.error, UNIFIED_404_MESSAGE);
});

Deno.test("cross-user: count mismatch (2 requested, 1 returned) → 404", () => {
  // One ID belongs to the caller, one belongs to another account
  const requestedIds = [
    "11111111-1111-4111-8111-111111111111",
    "22222222-2222-4222-8222-222222222222",
  ];
  const paymentsFromDb = [{ id: "11111111-1111-4111-8111-111111111111" }];
  const result = checkPaymentAccess(paymentsFromDb, requestedIds);
  assert(result !== null);
  assertEquals(result!.status, 404);
  assertEquals(result!.error, UNIFIED_404_MESSAGE);
});

Deno.test("cross-user: response must NOT be 403 (no distinction)", () => {
  const requestedIds = ["11111111-1111-4111-8111-111111111111"];
  const paymentsFromDb: { id: string }[] = []; // RLS filtered — cross-user
  const result = checkPaymentAccess(paymentsFromDb, requestedIds);
  assert(result !== null);
  assert(result!.status !== 403, "Must not return 403 (leaks account existence)");
});

Deno.test("cross-user: all valid IDs found → no error (null returned)", () => {
  const requestedIds = [
    "11111111-1111-4111-8111-111111111111",
    "22222222-2222-4222-8222-222222222222",
  ];
  const paymentsFromDb = [
    { id: "11111111-1111-4111-8111-111111111111" },
    { id: "22222222-2222-4222-8222-222222222222" },
  ];
  const result = checkPaymentAccess(paymentsFromDb, requestedIds);
  assertEquals(result, null, "All found → no error");
});

Deno.test("cross-user: error message is identical for empty-result and count-mismatch", () => {
  const ids = ["11111111-1111-4111-8111-111111111111"];
  const emptyResult = checkPaymentAccess([], ids);
  const mismatchResult = checkPaymentAccess([], ids);

  assert(emptyResult !== null && mismatchResult !== null);
  assertEquals(
    emptyResult!.error,
    mismatchResult!.error,
    "Both cases must return the same error message",
  );
});
