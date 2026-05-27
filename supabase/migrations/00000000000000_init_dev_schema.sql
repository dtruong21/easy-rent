-- ============================================================================
-- Init dev schema for multi-environment on Supabase free tier
-- ============================================================================
-- Strategy: same database hosts both `public` (PROD) and `dev` (DEV) schemas.
-- All future migrations must apply changes to BOTH schemas.
-- See docs/ENVIRONMENTS.md for the full strategy.
-- ============================================================================

-- Create the dev schema
CREATE SCHEMA IF NOT EXISTS dev;

-- Grant usage to the same roles as public, so RLS can run
GRANT USAGE ON SCHEMA dev TO authenticated, anon, service_role;

-- Default privileges so future tables in dev are accessible to authenticated users
-- (RLS still gates actual row access)
ALTER DEFAULT PRIVILEGES IN SCHEMA dev
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES
  TO authenticated;

ALTER DEFAULT PRIVILEGES IN SCHEMA dev
  GRANT USAGE, SELECT ON SEQUENCES
  TO authenticated;

ALTER DEFAULT PRIVILEGES IN SCHEMA dev
  GRANT EXECUTE ON FUNCTIONS
  TO authenticated;

-- Comment for posterity
COMMENT ON SCHEMA dev IS 'Development/staging mirror of public schema. Mapped to Git branch `develop`. See docs/ENVIRONMENTS.md.';

-- ============================================================================
-- Helper: function to check schema parity (debug tool)
-- ============================================================================
-- Returns rows where `public` and `dev` have differing tables.
-- Run periodically: SELECT * FROM dev.check_schema_parity();

CREATE OR REPLACE FUNCTION dev.check_schema_parity()
RETURNS TABLE (
  public_table text,
  dev_table text,
  status text
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    pub.tablename::text,
    d.tablename::text,
    CASE
      WHEN pub.tablename IS NULL THEN 'MISSING IN PUBLIC'
      WHEN d.tablename IS NULL THEN 'MISSING IN DEV'
      ELSE 'OK'
    END::text AS status
  FROM (SELECT tablename FROM pg_tables WHERE schemaname = 'public') pub
  FULL OUTER JOIN (SELECT tablename FROM pg_tables WHERE schemaname = 'dev') d
    ON pub.tablename = d.tablename
  WHERE pub.tablename IS NULL OR d.tablename IS NULL OR pub.tablename != d.tablename;
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================================================
-- Helper: assert RLS is enabled on both schemas for a given table
-- ============================================================================
CREATE OR REPLACE FUNCTION dev.assert_rls_both_schemas(table_name text)
RETURNS void AS $$
DECLARE
  public_rls boolean;
  dev_rls boolean;
BEGIN
  SELECT relrowsecurity INTO public_rls FROM pg_class
    WHERE relname = table_name AND relnamespace = 'public'::regnamespace;
  SELECT relrowsecurity INTO dev_rls FROM pg_class
    WHERE relname = table_name AND relnamespace = 'dev'::regnamespace;

  IF NOT public_rls THEN
    RAISE EXCEPTION 'RLS not enabled on public.% — security violation', table_name;
  END IF;
  IF NOT dev_rls THEN
    RAISE EXCEPTION 'RLS not enabled on dev.% — security violation', table_name;
  END IF;
END;
$$ LANGUAGE plpgsql;
