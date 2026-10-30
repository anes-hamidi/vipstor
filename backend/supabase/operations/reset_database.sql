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
-- After running it, run these files IN ORDER:
--   1. schema/001_fresh_schema.sql
--   2. schema/002_migration_00035.sql
--   3. schema/003_migration_00035b.sql
--   4. schema/004_migration_00036.sql
--   5. schema/005_phase0_security.sql
--   6. schema/006_auth_management.sql
--   7. schema/007_storage_policy_hardening.sql
--   8. seeds/001_admin.sql
--
-- Skipping 002-007 leaves the database without the Phase 0 security fixes
-- (JWT identity mapping, RPC/RLS lockdown) and re-opens the product-images
-- upload policy to the anon key.
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
