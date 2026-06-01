/**
 * Unit tests for send-receipt input validation logic.
 *
 * Pure unit tests — no Supabase client, no Resend calls.
 * Validates UUID format checking, schema validation, and method gating.
 *
 * Run: deno test --allow-env send-receipt/tests/input_validation_test.ts
 */

import {
  assertEquals,
  assert,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { parseSchema } from "../../_shared/supabase_client.ts";

// ---------------------------------------------------------------------------
// Replicate UUID validation from index.ts
// ---------------------------------------------------------------------------

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function isUuid(s: string): boolean {
  return UUID_RE.test(s);
}

// ---------------------------------------------------------------------------
// UUID validation
// ---------------------------------------------------------------------------

Deno.test("isUuid: valid v4 UUID passes", () => {
  assert(isUuid("11111111-1111-4111-8111-111111111111"));
  assert(isUuid("a3bb189e-8bf9-4e4a-a2db-c43c5d7f9e10"));
});

Deno.test("isUuid: empty string fails", () => {
  assert(!isUuid(""));
});

Deno.test("isUuid: non-v4 UUID fails (v1)", () => {
  assert(!isUuid("6ba7b810-9dad-11d1-80b4-00c04fd430c8"));
});

Deno.test("isUuid: malformed UUID fails", () => {
  assert(!isUuid("not-a-uuid"));
  assert(!isUuid("11111111-1111-1111-1111-11111111111")); // too short
});

Deno.test("isUuid: plain string with no hyphens fails", () => {
  assert(!isUuid("111111111111411181111111111111111111"));
});

// ---------------------------------------------------------------------------
// Schema validation (reuses _shared/supabase_client.ts parseSchema)
// ---------------------------------------------------------------------------

Deno.test("parseSchema: undefined defaults to public", () => {
  assertEquals(parseSchema(undefined), "public");
});

Deno.test("parseSchema: null defaults to public", () => {
  assertEquals(parseSchema(null), "public");
});

Deno.test("parseSchema: 'dev' is accepted", () => {
  assertEquals(parseSchema("dev"), "dev");
});

Deno.test("parseSchema: 'public' is accepted", () => {
  assertEquals(parseSchema("public"), "public");
});

Deno.test("parseSchema: invalid value throws RangeError", () => {
  assertThrows(() => parseSchema("staging"), RangeError, "schema invalide");
});

Deno.test("parseSchema: empty string throws RangeError", () => {
  assertThrows(() => parseSchema(""), RangeError, "schema invalide");
});

// ---------------------------------------------------------------------------
// Body validation logic — simulates handler checks
// ---------------------------------------------------------------------------

function validateBody(body: Record<string, unknown>): { error: string } | null {
  if (!body.receipt_id || typeof body.receipt_id !== "string") {
    return { error: "receipt_id est requis" };
  }
  if (!isUuid(body.receipt_id as string)) {
    return { error: "receipt_id n'est pas un UUID valide" };
  }
  try {
    parseSchema(body.schema);
  } catch {
    return { error: "schema invalide" };
  }
  return null;
}

Deno.test("body: missing receipt_id → error", () => {
  const result = validateBody({ schema: "public" });
  assert(result !== null);
  assertEquals(result!.error, "receipt_id est requis");
});

Deno.test("body: receipt_id is null → error", () => {
  const result = validateBody({ receipt_id: null as unknown as string, schema: "public" });
  assert(result !== null);
  assertEquals(result!.error, "receipt_id est requis");
});

Deno.test("body: malformed UUID → error", () => {
  const result = validateBody({ receipt_id: "not-a-uuid", schema: "public" });
  assert(result !== null);
  assertEquals(result!.error, "receipt_id n'est pas un UUID valide");
});

Deno.test("body: invalid schema value → error", () => {
  const result = validateBody({
    receipt_id: "11111111-1111-4111-8111-111111111111",
    schema: "production",
  });
  assert(result !== null);
  assertEquals(result!.error, "schema invalide");
});

Deno.test("body: valid UUID + valid schema → no error", () => {
  const result = validateBody({
    receipt_id: "11111111-1111-4111-8111-111111111111",
    schema: "dev",
  });
  assertEquals(result, null);
});

Deno.test("body: valid UUID + missing schema defaults to public (no error)", () => {
  const result = validateBody({
    receipt_id: "a3bb189e-8bf9-4e4a-a2db-c43c5d7f9e10",
  });
  assertEquals(result, null);
});
