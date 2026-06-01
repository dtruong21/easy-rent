/**
 * Tests for receipt state validation.
 *
 * Verifies that the handler returns the correct error codes for:
 *   - voided receipt         → 422 receipt_invalid
 *   - stale receipt          → 422 receipt_invalid
 *   - pdf_path null or empty → 422 pdf_unavailable
 *
 * Pure unit tests — simulates the handler's receipt state checks.
 *
 * Run: deno test --allow-env send-receipt/tests/receipt_invalid_test.ts
 */

import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";

// ---------------------------------------------------------------------------
// Replicate receipt state validation from index.ts
// ---------------------------------------------------------------------------

interface ReceiptState {
  is_voided: boolean;
  is_stale: boolean;
  pdf_path: string | null;
}

function validateReceiptState(
  receipt: ReceiptState,
): { status: number; error: string; message: string } | null {
  if (receipt.is_voided) {
    return {
      status: 422,
      error: "receipt_invalid",
      message: "La quittance est annulée — impossible à envoyer",
    };
  }
  if (receipt.is_stale) {
    return {
      status: 422,
      error: "receipt_invalid",
      message: "La quittance est périmée — impossible à envoyer",
    };
  }
  if (!receipt.pdf_path || receipt.pdf_path.trim() === "") {
    return {
      status: 422,
      error: "pdf_unavailable",
      message: "PDF indisponible pour cette quittance. Régénérez-la.",
    };
  }
  return null;
}

// ---------------------------------------------------------------------------
// Tests — voided
// ---------------------------------------------------------------------------

Deno.test("receipt: is_voided = true → 422 receipt_invalid", () => {
  const receipt: ReceiptState = {
    is_voided: true,
    is_stale: false,
    pdf_path: "landlord-id/receipt-id.pdf",
  };
  const result = validateReceiptState(receipt);
  assert(result !== null);
  assertEquals(result!.status, 422);
  assertEquals(result!.error, "receipt_invalid");
});

Deno.test("receipt: voided error code is not pdf_unavailable", () => {
  const receipt: ReceiptState = {
    is_voided: true,
    is_stale: false,
    pdf_path: "landlord-id/receipt-id.pdf",
  };
  const result = validateReceiptState(receipt);
  assert(result !== null);
  assert(result!.error !== "pdf_unavailable", "voided must not return pdf_unavailable");
});

// ---------------------------------------------------------------------------
// Tests — stale
// ---------------------------------------------------------------------------

Deno.test("receipt: is_stale = true → 422 receipt_invalid", () => {
  const receipt: ReceiptState = {
    is_voided: false,
    is_stale: true,
    pdf_path: "landlord-id/receipt-id.pdf",
  };
  const result = validateReceiptState(receipt);
  assert(result !== null);
  assertEquals(result!.status, 422);
  assertEquals(result!.error, "receipt_invalid");
});

Deno.test("receipt: stale message is different from voided message", () => {
  const voided = validateReceiptState({ is_voided: true, is_stale: false, pdf_path: "x.pdf" });
  const stale = validateReceiptState({ is_voided: false, is_stale: true, pdf_path: "x.pdf" });
  assert(voided !== null && stale !== null);
  assert(voided!.message !== stale!.message, "voided and stale messages should differ");
});

// ---------------------------------------------------------------------------
// Tests — pdf_unavailable
// ---------------------------------------------------------------------------

Deno.test("receipt: pdf_path null → 422 pdf_unavailable", () => {
  const receipt: ReceiptState = {
    is_voided: false,
    is_stale: false,
    pdf_path: null,
  };
  const result = validateReceiptState(receipt);
  assert(result !== null);
  assertEquals(result!.status, 422);
  assertEquals(result!.error, "pdf_unavailable");
});

Deno.test("receipt: pdf_path empty string → 422 pdf_unavailable", () => {
  const receipt: ReceiptState = {
    is_voided: false,
    is_stale: false,
    pdf_path: "",
  };
  const result = validateReceiptState(receipt);
  assert(result !== null);
  assertEquals(result!.status, 422);
  assertEquals(result!.error, "pdf_unavailable");
});

Deno.test("receipt: pdf_path whitespace → 422 pdf_unavailable", () => {
  const receipt: ReceiptState = {
    is_voided: false,
    is_stale: false,
    pdf_path: "   ",
  };
  const result = validateReceiptState(receipt);
  assert(result !== null);
  assertEquals(result!.status, 422);
  assertEquals(result!.error, "pdf_unavailable");
});

// ---------------------------------------------------------------------------
// Tests — valid receipt passes all checks
// ---------------------------------------------------------------------------

Deno.test("receipt: valid state → no error", () => {
  const receipt: ReceiptState = {
    is_voided: false,
    is_stale: false,
    pdf_path: "00000000-0000-4000-8000-000000000001/00000000-0000-4000-8000-000000000002.pdf",
  };
  const result = validateReceiptState(receipt);
  assertEquals(result, null);
});

Deno.test("receipt: voided takes precedence over stale (checked first)", () => {
  // Both flags set — voided should be reported (handler checks voided first)
  const receipt: ReceiptState = {
    is_voided: true,
    is_stale: true,
    pdf_path: "x.pdf",
  };
  const result = validateReceiptState(receipt);
  assert(result !== null);
  assertEquals(result!.error, "receipt_invalid");
  assert(
    result!.message.includes("annulée"),
    "voided message should mention annulée",
  );
});
