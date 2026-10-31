-- ============================================================================
-- 009_staff_pin_auth.sql
-- PIN-only staff sign-in support.
--
-- Design:
--   * Cashiers, managers and drivers authenticate with a PIN only.
--   * The `auth-admin` Edge Function verifies the PIN server-side, rotates the
--     hidden Supabase Auth password and returns a short-lived session so the
--     existing RLS/data/RPC layer keeps working.
--   * Moderators keep phone + password and are rejected by the PIN endpoint.
--
-- The internal PIN verification function must be executable by the service
-- role only. It must never be exposed to anon or authenticated clients: it
-- accepts an arbitrary target user id, unlike the self-only `rpc_verify_user_pin`
-- step-up wrapper.
--
-- Apply after 008_fix_audit_log_actor.sql.
-- ============================================================================

BEGIN;

SET LOCAL search_path = public, extensions, pg_temp;

REVOKE ALL ON FUNCTION public.internal_verify_user_pin(UUID, TEXT)
    FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.internal_verify_user_pin(UUID, TEXT)
    TO service_role;

INSERT INTO public.schema_migrations (version, description)
VALUES ('00040', '00040 - PIN-only staff sign-in session bridge')
ON CONFLICT (version) DO NOTHING;

NOTIFY pgrst, 'reload schema';

COMMIT;
