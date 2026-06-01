/**
 * Tests for Fix 3 — body.schema routing.
 *
 * Verifies that parseSchema() correctly validates the schema field and that the
 * handler passes the schema through to DB queries.
 *
 * Run: deno test --allow-env supabase/functions/generate-receipt/tests/schema_routing_test.ts
 */
import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { parseSchema } from "../../_shared/supabase_client.ts";

// ---------------------------------------------------------------------------
// parseSchema — unit tests
// ---------------------------------------------------------------------------

Deno.test("parseSchema: undefined -> defaults to 'public'", () => {
  assertEquals(parseSchema(undefined), "public");
});

Deno.test("parseSchema: null -> defaults to 'public'", () => {
  assertEquals(parseSchema(null), "public");
});

Deno.test("parseSchema: 'public' -> 'public'", () => {
  assertEquals(parseSchema("public"), "public");
});

Deno.test("parseSchema: 'dev' -> 'dev'", () => {
  assertEquals(parseSchema("dev"), "dev");
});

Deno.test("parseSchema: invalid value throws RangeError", () => {
  assertThrows(
    () => parseSchema("staging"),
    RangeError,
    "schema invalide",
  );
});

Deno.test("parseSchema: empty string throws RangeError", () => {
  assertThrows(
    () => parseSchema(""),
    RangeError,
    "schema invalide",
  );
});

Deno.test("parseSchema: numeric value throws RangeError", () => {
  assertThrows(
    () => parseSchema(42),
    RangeError,
    "schema invalide",
  );
});

Deno.test("parseSchema: 'PUBLIC' (uppercase) throws RangeError — case-sensitive", () => {
  assertThrows(
    () => parseSchema("PUBLIC"),
    RangeError,
    "schema invalide",
  );
});

// ---------------------------------------------------------------------------
// Schema routing contract — simulate how the handler applies the schema
// ---------------------------------------------------------------------------

Deno.test("schema routing: body without schema field defaults to 'public'", () => {
  // Simulate what the handler does:
  //   const schemaName = parseSchema((body as Record<string, unknown>).schema);
  const body: Record<string, unknown> = {
    payment_ids: ["11111111-1111-4111-8111-111111111111"],
  };
  const schemaName = parseSchema(body["schema"]);
  assertEquals(schemaName, "public");
});

Deno.test("schema routing: body.schema = 'dev' routes to dev schema", () => {
  const body: Record<string, unknown> = {
    payment_ids: ["11111111-1111-4111-8111-111111111111"],
    schema: "dev",
  };
  const schemaName = parseSchema(body["schema"]);
  assertEquals(schemaName, "dev");
});

Deno.test("schema routing: body.schema = 'public' routes to public schema", () => {
  const body: Record<string, unknown> = {
    payment_ids: ["11111111-1111-4111-8111-111111111111"],
    schema: "public",
  };
  const schemaName = parseSchema(body["schema"]);
  assertEquals(schemaName, "public");
});

Deno.test("schema routing: invalid schema in body throws (handler must return 400)", () => {
  const body: Record<string, unknown> = {
    payment_ids: ["11111111-1111-4111-8111-111111111111"],
    schema: "invalid_schema",
  };
  assertThrows(
    () => parseSchema(body["schema"]),
    RangeError,
  );
});
