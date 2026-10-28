-- ============================================================
-- VIP WHOLESALE & POS MANAGEMENT SYSTEM
-- SEED 001 - INITIAL MODERATOR (ADMIN ONLY)
-- ============================================================
-- Run this ONCE after schema/006_auth_management.sql.
--
-- This seed creates the public.users moderator row only. It does NOT create a
-- Supabase Auth user (passwords must never be seeded in SQL).
--
-- 1. Apply 005_phase0_security.sql and 006_auth_management.sql.
-- 2. Run this seed.
-- 3. In Supabase Dashboard > Authentication > Users, create an email user:
--      Email:    bootstrap-moderator@vip.algomend.app
--                (temporary; replaced by SQL in the next step)
--      Password: a strong password chosen by the owner
--      Auto-confirm user: enabled
--      User metadata / app metadata: leave both empty for now.
--    The temporary email deliberately does not look like a phone number:
--    a synthetic phone-shaped email would make the insert trigger derive the
--    seeded phone and collide with this moderator row.
-- 4. Run this SQL to set the real synthetic email and attach the trusted role
--    and phone. The update trigger then adopts the seeded moderator row. The
--    CTE also refreshes the email identity data so Auth stays consistent:
--      WITH updated AS (
--          UPDATE auth.users
--          SET email = '213673336972@vip.algomend.app',
--              email_confirmed_at = COALESCE(email_confirmed_at, NOW()),
--              raw_app_meta_data =
--                  COALESCE(raw_app_meta_data, '{}'::jsonb)
--                  || '{"role":"moderator"}'::jsonb,
--              raw_user_meta_data =
--                  COALESCE(raw_user_meta_data, '{}'::jsonb)
--                  || '{"phone":"0673336972","name":"المدير العام"}'::jsonb,
--              updated_at = NOW()
--          WHERE email = 'bootstrap-moderator@vip.algomend.app'
--          RETURNING id, email
--      )
--      UPDATE auth.identities i
--      SET identity_data =
--              COALESCE(i.identity_data, '{}'::jsonb)
--              || jsonb_build_object('email', u.email, 'email_verified', TRUE),
--          updated_at = NOW()
--      FROM updated u
--      WHERE i.user_id = u.id AND i.provider = 'email';
--    Existing public.users role always wins over app_metadata after the link.
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
