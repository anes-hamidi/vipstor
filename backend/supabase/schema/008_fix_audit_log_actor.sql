-- ============================================================
-- VIP WHOLESALE & POS MANAGEMENT SYSTEM
-- AUDIT LOG ACTOR MAPPING FIX (00039)
-- ============================================================
-- Problem
-- -------
-- trigger_audit_log_func() wrote auth.uid() straight into
-- audit_log.user_id. auth.uid() is the Supabase Auth identity
-- (auth.users.id), but audit_log.user_id has a foreign key to
-- public.users(id). Staff accounts have two different ids, so the first
-- audited write from a signed-in staff session failed with:
--
--   insert or update on table "audit_log" violates foreign key constraint
--   "audit_log_user_id_fkey"
--   DETAIL: Key (user_id)=(...) is not present in table "users".
--
-- This is what blocked changing a temporary moderator PIN: the users
-- UPDATE fires the audit trigger, the trigger fails, and the whole
-- transaction (including the PIN change) rolls back.
--
-- Fix
-- ---
--   * Resolve the actor through public.users.auth_user_id (= auth.uid()).
--   * Keep the record-field fallbacks used by anon/service-role sessions
--     where auth.uid() is NULL.
--   * Never write an actor id that is absent from public.users. If the
--     actor cannot be resolved (for example a hard-deleted row), write
--     NULL instead of aborting the business transaction.
--   * Preserve the maintenance-mode bypass and PIN/device-token redaction.
--
-- Apply order: after 007_storage_policy_hardening.sql.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.trigger_audit_log_func()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_user_id   UUID := NULL;
    v_before    JSONB := NULL;
    v_after     JSONB := NULL;
    v_new_json  JSONB := NULL;
    v_old_json  JSONB := NULL;
    v_target_id UUID := NULL;
BEGIN
    -- Fast exit during batch maintenance / archival cleanup
    IF current_setting('app.maintenance_mode', true) = 'true' THEN
        RETURN COALESCE(NEW, OLD);
    END IF;

    -- auth.uid() identifies auth.users, while audit_log.user_id references
    -- public.users. Translate the JWT identity to the application user id.
    BEGIN
        IF auth.uid() IS NOT NULL THEN
            SELECT u.id INTO v_user_id
            FROM public.users u
            WHERE u.auth_user_id = auth.uid()
            LIMIT 1;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        v_user_id := NULL;
    END;

    -- Convert composite rows to JSONB once. Composite records do not
    -- support the jsonb `?` operator; to_jsonb(NEW) does.
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        v_new_json := to_jsonb(NEW) - 'pin_code' - 'device_token';
    END IF;
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        v_old_json := to_jsonb(OLD) - 'pin_code' - 'device_token';
    END IF;

    -- Extract target id.
    BEGIN
        v_target_id := COALESCE(v_new_json->>'id', v_old_json->>'id')::UUID;
    EXCEPTION WHEN OTHERS THEN
        v_target_id := NULL;
    END;

    -- Deduce actor from record fields for anon clients.
    IF v_user_id IS NULL AND v_new_json IS NOT NULL THEN
        BEGIN
            IF TG_TABLE_NAME = 'orders' THEN
                v_user_id := NULLIF(v_new_json->>'cashier_id', '')::UUID;
            ELSIF TG_TABLE_NAME = 'wallet_entries' THEN
                v_user_id := NULLIF(v_new_json->>'driver_id', '')::UUID;
            ELSIF TG_TABLE_NAME = 'settlements' THEN
                v_user_id := NULLIF(v_new_json->>'cashier_id', '')::UUID;
            ELSIF TG_TABLE_NAME = 'users' THEN
                v_user_id := v_target_id;
            END IF;
        EXCEPTION WHEN OTHERS THEN
            v_user_id := NULL;
        END;
    END IF;

    -- The FK must never abort the business write just because the actor
    -- could not be resolved. Log the row with a NULL actor instead.
    IF v_user_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = v_user_id)
    THEN
        v_user_id := NULL;
    END IF;

    -- Keep full before/after only for critical tables.
    IF TG_TABLE_NAME IN (
        'orders', 'settlements', 'wallet_entries', 'users',
        'customers', 'suppliers', 'purchases'
    ) THEN
        IF TG_OP = 'INSERT' THEN
            v_after := v_new_json;
        ELSIF TG_OP = 'UPDATE' THEN
            v_before := v_old_json;
            v_after := v_new_json;
        ELSIF TG_OP = 'DELETE' THEN
            v_before := v_old_json;
        END IF;
    END IF;

    INSERT INTO public.audit_log (
        user_id, action, target_table, target_id, before_state, after_state
    ) VALUES (
        v_user_id, TG_OP, TG_TABLE_NAME, v_target_id, v_before, v_after
    );

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

INSERT INTO public.schema_migrations (version, description)
VALUES ('00039', '00039 - map auth identities to public.users for audit_log.user_id')
ON CONFLICT (version) DO NOTHING;

COMMIT;

-- ------------------------------------------------------------------
-- Verification (read-only; uncomment to run)
-- ------------------------------------------------------------------
-- Expected: 0 rows. No audit entry may reference a missing user.
--
-- SELECT count(*) AS orphan_audit_actors
-- FROM public.audit_log a
-- LEFT JOIN public.users u ON u.id = a.user_id
-- WHERE a.user_id IS NOT NULL AND u.id IS NULL;
--
-- Expected: the definition contains "auth_user_id = auth.uid()".
--
-- SELECT pg_get_functiondef('public.trigger_audit_log_func()'::regprocedure);
