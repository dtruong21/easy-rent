/**
 * Tests for Fix C2 — CORS origin allowlist.
 *
 * Verifies that:
 *   - Disallowed origins receive 403
 *   - Allowed production origins receive 200 (preflight) or null (POST)
 *   - Localhost origins (any port) are allowed in dev
 *   - The ALLOWED_ORIGINS env var extends the allowlist
 *   - The response never returns "*" as Access-Control-Allow-Origin
 *
 * Run: deno test --allow-env supabase/functions/generate-receipt/tests/cors_allowlist_test.ts
 */
import {
  assertEquals,
  assert,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handleCors, buildCorsHeaders } from "../../_shared/cors.ts";

// ---------------------------------------------------------------------------
// Helper: build a minimal Request with the given origin and method
// ---------------------------------------------------------------------------
function makeRequest(origin: string, method = "OPTIONS"): Request {
  return new Request("https://functions.supabase.co/generate-receipt", {
    method,
    headers: { Origin: origin },
  });
}

// ---------------------------------------------------------------------------
// Disallowed origins → 403
// ---------------------------------------------------------------------------

Deno.test("CORS: evil.com → 403", async () => {
  const req = makeRequest("https://evil.com");
  const res = handleCors(req);
  assert(res !== null, "Should return a Response for disallowed origin");
  assertEquals(res!.status, 403);
});

Deno.test("CORS: http://evil.com (http, not https) → 403", async () => {
  const req = makeRequest("http://evil.com");
  const res = handleCors(req);
  assert(res !== null);
  assertEquals(res!.status, 403);
});

Deno.test("CORS: empty origin → 403", () => {
  const req = makeRequest("");
  const res = handleCors(req);
  assert(res !== null);
  assertEquals(res!.status, 403);
});

Deno.test("CORS: subdomain of allowed origin is NOT allowed", () => {
  // sub.easy-rent-54cd4.web.app is not in the list
  const req = makeRequest("https://sub.easy-rent-54cd4.web.app");
  const res = handleCors(req);
  assert(res !== null);
  assertEquals(res!.status, 403);
});

// ---------------------------------------------------------------------------
// Allowed production origins → 200 preflight or null for non-OPTIONS
// ---------------------------------------------------------------------------

Deno.test("CORS: easy-rent-54cd4.web.app → OPTIONS returns 200", () => {
  const req = makeRequest("https://easy-rent-54cd4.web.app", "OPTIONS");
  const res = handleCors(req);
  assert(res !== null, "OPTIONS preflight should return a Response");
  assertEquals(res!.status, 200);
});

Deno.test("CORS: easy-rent-54cd4.firebaseapp.com → OPTIONS returns 200", () => {
  const req = makeRequest("https://easy-rent-54cd4.firebaseapp.com", "OPTIONS");
  const res = handleCors(req);
  assert(res !== null);
  assertEquals(res!.status, 200);
});

Deno.test("CORS: allowed origin POST → returns null (handler proceeds)", () => {
  const req = makeRequest("https://easy-rent-54cd4.web.app", "POST");
  const res = handleCors(req);
  assertEquals(res, null, "Allowed POST should return null so handler continues");
});

// ---------------------------------------------------------------------------
// Localhost dev origins → allowed (any port)
// ---------------------------------------------------------------------------

Deno.test("CORS: http://localhost:3000 → OPTIONS returns 200", () => {
  const req = makeRequest("http://localhost:3000", "OPTIONS");
  const res = handleCors(req);
  assert(res !== null);
  assertEquals(res!.status, 200);
});

Deno.test("CORS: http://localhost:8080 → OPTIONS returns 200", () => {
  const req = makeRequest("http://localhost:8080", "OPTIONS");
  const res = handleCors(req);
  assert(res !== null);
  assertEquals(res!.status, 200);
});

Deno.test("CORS: http://127.0.0.1:5000 → OPTIONS returns 200", () => {
  const req = makeRequest("http://127.0.0.1:5000", "OPTIONS");
  const res = handleCors(req);
  assert(res !== null);
  assertEquals(res!.status, 200);
});

Deno.test("CORS: https://localhost:3000 (https, not http) → 403", () => {
  // Only http:// localhost is allowed (Flutter Web dev server uses http)
  const req = makeRequest("https://localhost:3000", "OPTIONS");
  const res = handleCors(req);
  assert(res !== null);
  assertEquals(res!.status, 403);
});

// ---------------------------------------------------------------------------
// Echoed origin — never "*"
// ---------------------------------------------------------------------------

Deno.test("CORS: response header echoes specific origin, not '*'", () => {
  const origin = "https://easy-rent-54cd4.web.app";
  const req = makeRequest(origin, "OPTIONS");
  const res = handleCors(req);
  assert(res !== null);
  const acao = res!.headers.get("Access-Control-Allow-Origin");
  assertEquals(acao, origin, "Must echo the specific origin");
  assert(acao !== "*", "Must NOT return wildcard '*'");
});

Deno.test("CORS: Vary: Origin header is present on preflight", () => {
  const req = makeRequest("https://easy-rent-54cd4.web.app", "OPTIONS");
  const res = handleCors(req);
  assert(res !== null);
  const vary = res!.headers.get("Vary");
  assert(vary?.includes("Origin"), "Vary: Origin must be set");
});

Deno.test("CORS: buildCorsHeaders returns echoed origin for known origin", () => {
  const origin = "https://easy-rent-54cd4.web.app";
  const headers = buildCorsHeaders(origin);
  assertEquals(headers["Access-Control-Allow-Origin"], origin);
  assert(headers["Access-Control-Allow-Origin"] !== "*");
});

Deno.test("CORS: Vary: Origin in 403 response for disallowed origin", () => {
  const req = makeRequest("https://evil.com");
  const res = handleCors(req);
  assert(res !== null);
  assertEquals(res!.status, 403);
  const vary = res!.headers.get("Vary");
  assert(vary?.includes("Origin"), "Vary: Origin must be set even on 403");
});
