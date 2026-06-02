/**
 * Tests for Resend error mapping — quota exceeded (429), 5xx, 401.
 *
 * Mocks the global fetch to simulate Resend API responses without
 * any real network call or valid API key.
 *
 * Run: deno test --allow-env send-receipt/tests/resend_quota_429_test.ts
 */

import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { ResendError, sendEmailViaResend } from "../resend_client.ts";

const VALID_PARAMS = {
  to: "tenant@example.com",
  subject: "Votre quittance de loyer — mai 2026",
  html: "<p>Test</p>",
  attachments: [{ filename: "quittance_2026_05.pdf", content: "base64content" }],
};

// ---------------------------------------------------------------------------
// Helper: mock fetch globally with automatic restore in try/finally
// ---------------------------------------------------------------------------

const originalFetch = globalThis.fetch;

function mockFetch(status: number, body: unknown): void {
  (globalThis as Record<string, unknown>).fetch = async (
    _url: string | URL | Request,
    _init?: RequestInit,
  ): Promise<Response> => {
    return new Response(JSON.stringify(body), { status });
  };
}

function mockFetchThrow(errorMessage: string): void {
  (globalThis as Record<string, unknown>).fetch = async (): Promise<Response> => {
    throw new Error(errorMessage);
  };
}

function restoreFetch(): void {
  (globalThis as Record<string, unknown>).fetch = originalFetch;
}

// ---------------------------------------------------------------------------
// Set required env vars for the duration of each test
// ---------------------------------------------------------------------------

function setEnv(): void {
  Deno.env.set("RESEND_API_KEY", "re_test_key_123");
  Deno.env.set("RESEND_FROM_EMAIL", "EasyRent <noreply@easyrent.app>");
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

Deno.test("resend 429 → ResendError with code quota_exceeded", async () => {
  setEnv();
  mockFetch(429, { name: "rate_limit_exceeded", message: "Too Many Requests" });

  let threw = false;
  try {
    await sendEmailViaResend(VALID_PARAMS);
  } catch (err) {
    threw = true;
    assert(err instanceof ResendError, "Must throw ResendError");
    assertEquals((err as ResendError).code, "quota_exceeded");
    assertEquals((err as ResendError).httpStatus, 429);
  } finally {
    restoreFetch();
  }
  assert(threw, "Expected an error to be thrown for 429");
});

Deno.test("resend 500 → ResendError with code email_send_failed", async () => {
  setEnv();
  mockFetch(500, { message: "Internal Server Error" });

  let threw = false;
  try {
    await sendEmailViaResend(VALID_PARAMS);
  } catch (err) {
    threw = true;
    assert(err instanceof ResendError, "Must throw ResendError");
    assertEquals((err as ResendError).code, "email_send_failed");
    assertEquals((err as ResendError).httpStatus, 500);
  } finally {
    restoreFetch();
  }
  assert(threw, "Expected an error to be thrown for 500");
});

Deno.test("resend 401 (revoked key) → ResendError with code email_send_failed", async () => {
  setEnv();
  mockFetch(401, { name: "missing_api_key", message: "API key is missing or invalid" });

  let threw = false;
  try {
    await sendEmailViaResend(VALID_PARAMS);
  } catch (err) {
    threw = true;
    assert(err instanceof ResendError, "Must throw ResendError");
    assertEquals((err as ResendError).code, "email_send_failed");
    assertEquals((err as ResendError).httpStatus, 401);
  } finally {
    restoreFetch();
  }
  assert(threw, "Expected an error to be thrown for 401");
});

Deno.test("resend 403 (domain not verified) → ResendError with code email_send_failed", async () => {
  setEnv();
  mockFetch(403, { name: "validation_error", message: "Domain not verified" });

  let threw = false;
  try {
    await sendEmailViaResend(VALID_PARAMS);
  } catch (err) {
    threw = true;
    assert(err instanceof ResendError, "Must throw ResendError");
    assertEquals((err as ResendError).code, "email_send_failed");
  } finally {
    restoreFetch();
  }
  assert(threw, "Expected an error to be thrown for 403");
});

Deno.test("resend 422 (invalid address) → ResendError with code tenant_no_email", async () => {
  setEnv();
  mockFetch(422, { name: "validation_error", message: "Invalid email address" });

  let threw = false;
  try {
    await sendEmailViaResend(VALID_PARAMS);
  } catch (err) {
    threw = true;
    assert(err instanceof ResendError, "Must throw ResendError");
    assertEquals((err as ResendError).code, "tenant_no_email");
    assertEquals((err as ResendError).httpStatus, 422);
  } finally {
    restoreFetch();
  }
  assert(threw, "Expected an error to be thrown for 422");
});

Deno.test("resend network error (fetch throws) → ResendError with code email_send_failed", async () => {
  setEnv();
  mockFetchThrow("Network connection refused");

  let threw = false;
  try {
    await sendEmailViaResend(VALID_PARAMS);
  } catch (err) {
    threw = true;
    assert(err instanceof ResendError, "Must throw ResendError");
    assertEquals((err as ResendError).code, "email_send_failed");
    assert(
      (err as ResendError).message.includes("Network error"),
      "Message should mention network error",
    );
  } finally {
    restoreFetch();
  }
  assert(threw, "Expected an error to be thrown on network failure");
});

Deno.test("resend 200 success → returns { id }", async () => {
  setEnv();
  mockFetch(200, { id: "resend-msg-id-abc123" });

  try {
    const result = await sendEmailViaResend(VALID_PARAMS);
    assertEquals(result.id, "resend-msg-id-abc123");
  } finally {
    restoreFetch();
  }
});

Deno.test("resend missing RESEND_API_KEY → ResendError email_config_missing", async () => {
  Deno.env.delete("RESEND_API_KEY");
  Deno.env.set("RESEND_FROM_EMAIL", "EasyRent <noreply@easyrent.app>");

  let threw = false;
  try {
    await sendEmailViaResend(VALID_PARAMS);
  } catch (err) {
    threw = true;
    assert(err instanceof ResendError, "Must throw ResendError");
    assertEquals((err as ResendError).code, "email_config_missing");
  } finally {
    // Restore env
    Deno.env.set("RESEND_API_KEY", "re_test_key_123");
  }
  assert(threw, "Expected an error when RESEND_API_KEY is absent");
});
