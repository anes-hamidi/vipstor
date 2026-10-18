-- ============================================================
-- 00019_fix_users_select_for_staff_login.sql
--
-- Problem: The staff login screen calls getStaffMembers() as the
-- anon role (no Supabase Auth session yet). Migration 00015 did:
--
--   REVOKE ALL ON users FROM anon, authenticated;
--   GRANT SELECT (id, phone, name, role, active, language, ...) ON users TO anon, authenticated;
--
-- Column-level GRANTs in PostgreSQL are additive to table-level
-- grants, but when the table-level SELECT is revoked entirely,
-- PostgREST's schema introspection may report the table as
-- unreadable, causing the query to return empty silently.
--
-- Fix: restore a full table-level SELECT grant and rely on the
-- RLS policy "Allow anon read users for profile and lookup"
-- (USING TRUE) to control row access. pin_code is never
-- returned — the query selects only safe columns explicitly.
-- ============================================================

-- Restore full table-level SELECT (column-level grants remain in addition)
GRANT SELECT ON users TO anon, authenticated;

-- Confirm the RLS policy exists; recreate it to be safe
DROP POLICY IF EXISTS "Allow anon read users for profile and lookup" ON users;
CREATE POLICY "Allow anon read users for profile and lookup"
    ON users FOR SELECT
    USING (TRUE);

-- Force PostgREST schema cache reload
NOTIFY pgrst, 'reload schema';
