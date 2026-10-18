-- ============================================================
-- rollback_00015.sql
-- ROLLBACK SCRIPT FOR 00015 SECURITY HARDENING
-- ============================================================
-- WARNING: 
-- 1. PIN codes that have been hashed using crypt(..., gen_salt('bf')) 
--    CANNOT be decrypted back to plaintext. Users will need to use their 
--    known PINs or have them reset.
-- 2. This script restores the previous open policies and grants.
-- ============================================================

-- 1. RESTORE POLICIES & PERMISSIONS ON USERS
DROP POLICY IF EXISTS "Allow anon read users for profile and lookup" ON users;
DROP POLICY IF EXISTS "Allow customer self-registration" ON users;
DROP POLICY IF EXISTS "Allow customer self-update" ON users;
DROP POLICY IF EXISTS "Allow all operations on users for app functionality" ON users;

CREATE POLICY "Allow all operations on users for app functionality"
ON users FOR ALL
USING (TRUE)
WITH CHECK (TRUE);

GRANT ALL ON users TO anon, authenticated;

-- 2. RESTORE POLICIES & PERMISSIONS ON CUSTOMERS
DROP POLICY IF EXISTS "Allow read customers" ON customers;
DROP POLICY IF EXISTS "Allow insert customer user_id" ON customers;
DROP POLICY IF EXISTS "Allow all operations on customers" ON customers;

CREATE POLICY "Allow all operations on customers"
ON customers FOR ALL
USING (TRUE)
WITH CHECK (TRUE);

GRANT ALL ON customers TO anon, authenticated;

-- 3. DROP PIN ATTEMPT LIMITS TABLE
DROP TABLE IF EXISTS pin_attempt_limits CASCADE;

-- 4. DROP INTERNAL VERIFICATION FUNCTION
DROP FUNCTION IF EXISTS _internal_verify_and_track_pin(UUID, TEXT, BOOLEAN);

-- 5. REVERT RPC SIGNATURES IF DESIRED
DROP FUNCTION IF EXISTS rpc_reset_user_pin_by_admin(UUID, TEXT, UUID, TEXT);
DROP FUNCTION IF EXISTS rpc_create_staff_member(UUID, TEXT, VARCHAR, VARCHAR, user_role, TEXT, VARCHAR);
