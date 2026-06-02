/**
 * CORS helpers for EasyRent Edge Functions.
 *
 * Allowed origins allowlist (Fix C2 — security-auditor):
 *   - https://easy-rent-54cd4.web.app       (Firebase Hosting prod)
 *   - https://easy-rent-54cd4.firebaseapp.com (Firebase Hosting alternate domain)
 *   - http://localhost:*                     (local Flutter Web dev server)
 *   - http://127.0.0.1:*                    (local Flutter Web alternate)
 *
 * Additional origins can be configured at deploy time by setting the
 * ALLOWED_ORIGINS secret (comma-separated list) via:
 *   supabase secrets set ALLOWED_ORIGINS="https://custom.example.com"
 *
 * Security properties:
 *   - Access-Control-Allow-Origin echoes the specific matching origin (never "*")
 *   - Vary: Origin is set so CDN/proxy caches respect per-origin variation
 *   - Requests from non-listed origins are rejected with 403 before body processing
 */

/** Hardcoded base origins derived from firebase.json / .firebaserc (project: easy-rent-54cd4). */
const HARDCODED_ORIGINS: string[] = [
  "https://easy-rent-54cd4.web.app",
  "https://easy-rent-54cd4.firebaseapp.com",
];

/**
 * Returns true if the origin is explicitly in the allowlist or is a localhost origin.
 * Localhost check covers any port (e.g. http://localhost:3000, http://127.0.0.1:8080).
 */
function isAllowedOrigin(origin: string, allowedOrigins: string[]): boolean {
  if (allowedOrigins.includes(origin)) return true;
  // Allow any localhost / 127.0.0.1 port for local dev
  if (
    origin.startsWith("http://localhost:") ||
    origin.startsWith("http://127.0.0.1:")
  ) {
    return true;
  }
  return false;
}

/**
 * Builds the full allowed-origins list at runtime:
 *   hardcoded list + optional ALLOWED_ORIGINS env var (comma-separated).
 */
function buildAllowedOrigins(): string[] {
  const extra = Deno.env.get("ALLOWED_ORIGINS");
  if (!extra) return HARDCODED_ORIGINS;
  const extraList = extra
    .split(",")
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
  return [...HARDCODED_ORIGINS, ...extraList];
}

/** Common non-origin CORS headers shared by all responses. */
const CORS_COMMON_HEADERS = {
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
};

/**
 * Returns CORS response headers for a given (allowed) origin.
 * Always echoes the specific origin, never "*".
 */
export function buildCorsHeaders(origin: string): Record<string, string> {
  return {
    ...CORS_COMMON_HEADERS,
    "Access-Control-Allow-Origin": origin,
  };
}

/**
 * Handles CORS for a request.
 *
 * - If the Origin is not in the allowlist → returns a 403 response immediately.
 * - If the request is an OPTIONS preflight → returns a 200 OK with CORS headers.
 * - Otherwise → returns null (caller should proceed with the actual handler).
 *
 * Callers MUST use buildCorsHeaders(origin) when building their own responses
 * so that the echoed origin is consistent. Use the exported `corsHeaders` only
 * when you already have the origin validated.
 */
export function handleCors(req: Request): Response | null {
  const origin = req.headers.get("Origin") ?? "";
  const allowedOrigins = buildAllowedOrigins();

  if (!isAllowedOrigin(origin, allowedOrigins)) {
    return new Response(JSON.stringify({ error: "Forbidden" }), {
      status: 403,
      headers: {
        "Content-Type": "application/json",
        "Vary": "Origin",
      },
    });
  }

  const corsHeaders = buildCorsHeaders(origin);

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Store validated origin on the request for downstream use
  // (returned via buildCorsHeaders — callers should re-call buildCorsHeaders(origin))
  return null;
}

/**
 * Returns validated CORS headers for a request whose origin has already been
 * checked by handleCors. Call this to build response headers in the main handler.
 *
 * If called without a valid origin (e.g. in tests), falls back to an empty
 * Access-Control-Allow-Origin which browsers will reject — this is intentional.
 */
export function getCorsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("Origin") ?? "";
  return buildCorsHeaders(origin);
}

/**
 * Legacy export kept for callers that spread `corsHeaders` into a response.
 * In the main handler, prefer getCorsHeaders(req) to get the per-request origin.
 *
 * @deprecated Use getCorsHeaders(req) instead.
 */
export const corsHeaders = CORS_COMMON_HEADERS;
