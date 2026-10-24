-- ============================================================
-- VIP WHOLESALE & POS MANAGEMENT SYSTEM
-- OPERATIONS - DESTRUCTIVE DATABASE RESET
-- ============================================================
-- WARNING: THIS DELETES EVERYTHING IN THE PUBLIC SCHEMA.
-- All VIP tables, views, functions, types, triggers, policies and
-- data will be removed.
--
-- It does NOT touch:
--   * Supabase Auth users (auth schema)
--   * uploaded files in Supabase Storage
--
-- Use this only when you want to rebuild the database from scratch.
-- After running it, run these two files IN ORDER:
--   1. schema/001_fresh_schema.sql
--   2. seeds/001_admin.sql
-- ============================================================

BEGIN;

DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public;

ALTER SCHEMA public OWNER TO postgres;

-- Restore the standard Supabase schema privileges.
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT ALL   ON SCHEMA public TO postgres, service_role;

-- service_role keeps full access to future objects.
-- anon/authenticated only get sequence access by default; the baseline
-- grants their table and function privileges explicitly.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT ALL ON TABLES TO postgres, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT ALL ON SEQUENCES TO postgres, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT ALL ON FUNCTIONS TO postgres, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT USAGE, SELECT ON SEQUENCES TO anon, authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
