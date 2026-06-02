import { createClient, SupabaseClient } from "@supabase/supabase-js";

/** Allowed schema values. Any other value must be rejected with HTTP 400. */
export type AllowedSchema = "public" | "dev";

/**
 * Validates and parses the schema field from the request body.
 * Returns the schema name if valid, or throws an object with a 400 response
 * payload if invalid.
 *
 * Callers must check the return type:
 *   const schema = parseSchema(body.schema);
 *   // if invalid, parseSchema has already returned the error payload — handle it.
 */
export function parseSchema(raw: unknown): AllowedSchema {
  if (raw === undefined || raw === null) return "public";
  if (raw === "public" || raw === "dev") return raw as AllowedSchema;
  throw new RangeError(
    `schema invalide : "${raw}" — valeurs acceptees : "public", "dev"`,
  );
}

/**
 * Creates a Supabase client that propagates the caller's JWT so that
 * Row Level Security policies apply automatically.
 * Never use the service role key here — auth is enforced via RLS.
 */
export function createClientWithJwt(req: Request): SupabaseClient {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");

  if (!supabaseUrl || !supabaseAnonKey) {
    throw new Error("Missing SUPABASE_URL or SUPABASE_ANON_KEY env vars");
  }

  const authHeader = req.headers.get("Authorization") ?? "";

  return createClient(supabaseUrl, supabaseAnonKey, {
    global: {
      headers: { Authorization: authHeader },
    },
    auth: {
      persistSession: false,
    },
  });
}
