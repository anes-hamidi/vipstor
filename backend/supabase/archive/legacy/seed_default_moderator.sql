-- ============================================================
-- seed_default_moderator.sql
-- Creates the default moderator (admin) account.
-- Run ONCE on a fresh database after 000_fresh_schema.sql,
-- OR on an existing database (widens pin_code to TEXT first).
--
-- Default credentials:
--   Phone : 0673336972
--   PIN   : 1234
--
-- CHANGE THE PIN immediately after first login using the
-- "Change PIN" option in the app (Settings → Change PIN).
-- ============================================================

SET search_path = public, extensions, pg_temp;

-- Widen pin_code to TEXT if it is still the old VARCHAR(10)
-- (migration 00009 added it as VARCHAR(10); bcrypt hashes are 60 chars)
ALTER TABLE users ALTER COLUMN pin_code TYPE TEXT;

INSERT INTO users (
    id,
    phone,
    name,
    role,
    active,
    language,
    pin_code,
    created_at,
    updated_at
)
VALUES (
    gen_random_uuid(),
    '0673336972',
    'المدير العام',
    'moderator',
    TRUE,
    'ar',
    -- PIN '1234' hashed with bcrypt (pgcrypto)
    crypt('1234', gen_salt('bf')),
    NOW(),
    NOW()
)
ON CONFLICT (phone) DO UPDATE
    SET
        name      = EXCLUDED.name,
        role      = 'moderator',
        active    = TRUE,
        pin_code  = EXCLUDED.pin_code,
        updated_at = NOW();

-- Confirm the row was created
SELECT id, phone, name, role, active, created_at
FROM users
WHERE phone = '0673336972';
