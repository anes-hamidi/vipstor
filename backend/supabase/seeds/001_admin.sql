-- ============================================================
-- VIP WHOLESALE & POS MANAGEMENT SYSTEM
-- SEED 001 - INITIAL MODERATOR (ADMIN ONLY)
-- ============================================================
-- Run this ONCE after schema/001_fresh_schema.sql.
--
-- Creates the single master moderator account:
--   Phone : 0673336972
--   PIN   : 1234
--
-- There are no demo staff, customers, suppliers, products, prices,
-- or opening stock in this seed. Create them from the apps.
--
-- SECURITY: Change the PIN immediately after the first login.
-- ============================================================

SET search_path = public, extensions, pg_temp;

INSERT INTO users (id, phone, name, role, active, language, pin_code)
VALUES (
    '11111111-1111-1111-1111-111111111111',
    '0673336972',
    'المدير العام',
    'moderator',
    TRUE,
    'ar',
    crypt('1234', gen_salt('bf'))
)
ON CONFLICT DO NOTHING;

NOTIFY pgrst, 'reload schema';
