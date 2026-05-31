import { createClient, SupabaseClient } from "@supabase/supabase-js";

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
