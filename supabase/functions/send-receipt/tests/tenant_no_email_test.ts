/**
 * Tests for tenant email validation — D1 decision (block if no email).
 *
 * Verifies that the handler returns 422 "tenant_no_email" when:
 *   - tenant.email is null
 *   - tenant.email is empty string
 *   - tenant.email is whitespace only
 *
 * Pure unit tests — simulates the handler's tenant email check.
 *
 * Run: deno test --allow-env send-receipt/tests/tenant_no_email_test.ts
 */

import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";

// ---------------------------------------------------------------------------
// Replicate the tenant email validation from index.ts
// ---------------------------------------------------------------------------

interface TenantRow {
  first_name: string;
  last_name: string;
  email: string | null;
}

function validateTenantEmail(
  tenantData: TenantRow | null | undefined,
): { status: number; error: string } | null {
  if (!tenantData || !tenantData.email || tenantData.email.trim() === "") {
    return { status: 422, error: "tenant_no_email" };
  }
  return null;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

Deno.test("tenant email: null email → 422 tenant_no_email", () => {
  const tenant: TenantRow = {
    first_name: "Jean",
    last_name: "Dupont",
    email: null,
  };
  const result = validateTenantEmail(tenant);
  assert(result !== null);
  assertEquals(result!.status, 422);
  assertEquals(result!.error, "tenant_no_email");
});

Deno.test("tenant email: empty string → 422 tenant_no_email", () => {
  const tenant: TenantRow = {
    first_name: "Jean",
    last_name: "Dupont",
    email: "",
  };
  const result = validateTenantEmail(tenant);
  assert(result !== null);
  assertEquals(result!.status, 422);
  assertEquals(result!.error, "tenant_no_email");
});

Deno.test("tenant email: whitespace only → 422 tenant_no_email", () => {
  const tenant: TenantRow = {
    first_name: "Jean",
    last_name: "Dupont",
    email: "   ",
  };
  const result = validateTenantEmail(tenant);
  assert(result !== null);
  assertEquals(result!.status, 422);
  assertEquals(result!.error, "tenant_no_email");
});

Deno.test("tenant email: null tenantData → 422 tenant_no_email", () => {
  const result = validateTenantEmail(null);
  assert(result !== null);
  assertEquals(result!.status, 422);
  assertEquals(result!.error, "tenant_no_email");
});

Deno.test("tenant email: valid email → no error", () => {
  const tenant: TenantRow = {
    first_name: "Jean",
    last_name: "Dupont",
    email: "jean.dupont@example.com",
  };
  const result = validateTenantEmail(tenant);
  assertEquals(result, null);
});

Deno.test("tenant email: email with surrounding whitespace is trimmed and valid", () => {
  // Whitespace around a real email address — still valid after trim
  const tenant: TenantRow = {
    first_name: "Marie",
    last_name: "Martin",
    email: "  marie@example.com  ",
  };
  // The handler trims before sending, but trim() != "" → passes validation
  const result = validateTenantEmail(tenant);
  assertEquals(result, null);
});
