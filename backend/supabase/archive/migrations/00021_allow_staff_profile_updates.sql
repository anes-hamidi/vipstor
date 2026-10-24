-- ============================================================
-- 00021_allow_staff_profile_updates.sql
--
-- Fix: PostgREST permission denied on table `users` (code 42501).
--
-- Root Cause:
-- Staff authentication uses PIN code verification locally without a
-- Supabase Auth JWT session, running all client queries under the `anon`
-- role. When updating a staff profile (name, phone, role, active, etc.)
-- from the Moderator Dashboard or Profile Sheet, PostgreSQL blocked the
-- operation because:
-- 1. `users` table had UPDATE grant revoked or restricted.
-- 2. The RLS policy for UPDATE was restricted strictly to `role = 'customer'`.
--
-- This script grants UPDATE permissions on the safe staff profile columns
-- and updates the RLS policies to allow updating user profiles.
-- ============================================================

-- 1. Grant table-level UPDATE and safe column updates to anon and authenticated
GRANT UPDATE (name, phone, role, active, language, updated_at) ON users TO anon, authenticated;
GRANT SELECT ON users TO anon, authenticated;

-- 2. Reconfigure RLS policies on `users` table
DROP POLICY IF EXISTS "Allow staff and user profile update" ON users;
DROP POLICY IF EXISTS "Allow customer self-update" ON users;
DROP POLICY IF EXISTS "Allow all operations on users for app functionality" ON users;

-- Policy to allow profile updates (for staff management and customer self-updates)
CREATE POLICY "Allow staff and user profile update"
ON users FOR UPDATE
TO anon, authenticated
USING (TRUE)
WITH CHECK (TRUE);

-- 3. Force PostgREST schema cache reload
NOTIFY pgrst, 'reload schema';
