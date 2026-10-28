-- ============================================================
-- VIP WHOLESALE & POS MANAGEMENT SYSTEM
-- SEED 001 - INITIAL MODERATOR (ADMIN ONLY)
-- ============================================================
-- Run this ONCE after schema/005_phase0_security.sql.
--
-- This seed creates the public.users moderator row only. It does NOT create a
-- Supabase Auth user (passwords must never be seeded in SQL).
--
-- 1. Apply 005_phase0_security.sql.
-- 2. Run this seed.
-- 3. In Supabase Dashboard > Authentication > Users, create a phone user:
--      Phone:    +213673336972 (E.164; public.users keeps local 0673336972)
--      Password: a strong password chosen by the owner
--      app_metadata: {"role":"moderator"}
--      user_metadata: {"name":"المدير العام"}
--    The auth trigger links it to this row by phone. Existing public.users role
--    always wins over app_metadata.
--
-- The PIN below is a temporary step-up secret. `must_change_pin = TRUE` means
-- the apps must force a PIN change immediately after the first authenticated
-- login. Do not keep 1234 in production.
--
-- There are no demo staff, customers, suppliers, products, prices,
-- or opening stock in this seed. Create them from the apps.
-- ============================================================

SET search_path = public, extensions, pg_temp;

INSERT INTO users (id, phone, name, role, active, language, pin_code, must_change_pin)
VALUES (
    '11111111-1111-1111-1111-111111111111',
    '0673336972',
    'المدير العام',
    'moderator',
    TRUE,
    'ar',
    crypt('1234', gen_salt('bf')),
    TRUE
)
ON CONFLICT (id) DO UPDATE SET
    must_change_pin = TRUE,
    updated_at = NOW();

-- Backfill the customer profile for any customer users linked by the auth
-- trigger or by schema/005. Safe to re-run.
INSERT INTO customers (user_id, price_tier)
SELECT u.id, 'wholesale'::price_tier
FROM users u
WHERE u.role = 'customer'::user_role
ON CONFLICT (user_id) DO NOTHING;

NOTIFY pgrst, 'reload schema';
