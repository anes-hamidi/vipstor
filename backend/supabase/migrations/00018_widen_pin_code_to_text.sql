-- ============================================================
-- 00018_widen_pin_code_to_text.sql
-- pin_code was added in 00009 as VARCHAR(10) — too short for
-- bcrypt hashes (60 chars). Widen to TEXT.
-- Idempotent: ALTER TYPE on a TEXT column is a no-op in PG.
-- ============================================================

ALTER TABLE users ALTER COLUMN pin_code TYPE TEXT;
