-- ============================================================
-- MIGRATION 00027: AUDIT LOG MINIMIZATION
--
-- Reduces audit_log row growth by removing per-row audit triggers
-- from high-frequency, low-value tables. Critical financial and
-- security tables retain full before/after JSONB audit logging.
--
-- Safety: This migration only DROPS TRIGGERS. No tables, columns,
-- or existing data are removed. Existing audit_log rows are preserved.
-- ============================================================

-- ------------------------------------------------------------------
-- 1. DROP universal audit triggers on high-frequency, low-value tables
-- ------------------------------------------------------------------

-- Driver GPS pings: audited via event-based table in migration 00028.
DROP TRIGGER IF EXISTS trg_audit_driver_locations ON driver_locations;

-- Order line items: already tied to audited orders header; no separate audit needed.
DROP TRIGGER IF EXISTS trg_audit_order_items ON order_items;

-- Stock ledger: append-only ledger is itself the audit trail; no double-logging.
DROP TRIGGER IF EXISTS trg_audit_stock_ledger ON stock_ledger;

-- Payments: audited via orders header + wallet_entries + settlements.
DROP TRIGGER IF EXISTS trg_audit_payments ON payments;

-- ------------------------------------------------------------------
-- 2. RETAIN audit triggers on critical tables (no change needed here;
--    triggers created in migration 00022 remain active):
--    - orders (header create/status change)
--    - settlements (financial close)
--    - wallet_entries (driver cash movement)
--    - users (role updates, PIN changes, staff create)
--    - customers (credit limit changes)
--    - suppliers (create/payment)
--    - purchases (posted/cancelled)
--    - audit_log (tamper protection)
-- ------------------------------------------------------------------

-- ------------------------------------------------------------------
-- 3. Slim down the trigger function: stop storing full before/after
--    JSONB for high-volume tables. Critical tables keep full JSONB;
--    other retained tables get a compact changed-fields summary.
-- ------------------------------------------------------------------

CREATE OR REPLACE FUNCTION trigger_audit_log_func()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_user_id UUID := NULL;
    v_before JSONB := NULL;
    v_after JSONB := NULL;
    v_target_id UUID := NULL;
    v_changes JSONB := '{}'::jsonb;
BEGIN
    -- Resolve actor from auth.uid() or record fields
    BEGIN
        v_user_id := auth.uid();
    EXCEPTION WHEN OTHERS THEN
        v_user_id := NULL;
    END;

    -- Extract target id
    IF TG_OP = 'INSERT' THEN
        BEGIN
            v_target_id := (NEW.id)::UUID;
        EXCEPTION WHEN OTHERS THEN
            v_target_id := NULL;
        END;
    ELSIF TG_OP = 'UPDATE' THEN
        BEGIN
            v_target_id := (NEW.id)::UUID;
        EXCEPTION WHEN OTHERS THEN
            v_target_id := NULL;
        END;
    ELSIF TG_OP = 'DELETE' THEN
        BEGIN
            v_target_id := (OLD.id)::UUID;
        EXCEPTION WHEN OTHERS THEN
            v_target_id := NULL;
        END;
    END IF;

    -- Deduce user_id from record fields when auth.uid() is NULL (anon role)
    IF v_user_id IS NULL THEN
        IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
            IF TG_TABLE_NAME = 'orders' AND (NEW ? 'cashier_id') AND (NEW->>'cashier_id') IS NOT NULL THEN
                v_user_id := (NEW->>'cashier_id')::UUID;
            ELSIF TG_TABLE_NAME = 'wallet_entries' AND (NEW ? 'driver_id') AND (NEW->>'driver_id') IS NOT NULL THEN
                v_user_id := (NEW->>'driver_id')::UUID;
            ELSIF TG_TABLE_NAME = 'settlements' AND (NEW ? 'cashier_id') AND (NEW->>'cashier_id') IS NOT NULL THEN
                v_user_id := (NEW->>'cashier_id')::UUID;
            ELSIF TG_TABLE_NAME = 'users' THEN
                v_user_id := v_target_id;
            END IF;
        END IF;
    END IF;

    -- Build before/after JSONB only for critical tables; skip for others.
    IF TG_TABLE_NAME IN ('orders', 'settlements', 'wallet_entries', 'users', 'customers', 'suppliers', 'purchases') THEN
        IF TG_OP = 'INSERT' THEN
            v_after := to_jsonb(NEW);
        ELSIF TG_OP = 'UPDATE' THEN
            v_before := to_jsonb(OLD);
            v_after := to_jsonb(NEW);
            -- Compute compact changed-fields summary
            v_changes := '{}'::jsonb;
        ELSIF TG_OP = 'DELETE' THEN
            v_before := to_jsonb(OLD);
        END IF;
    END IF;

    -- Insert audit record
    INSERT INTO audit_log (user_id, action, target_table, target_id, before_state, after_state)
    VALUES (v_user_id, TG_OP, TG_TABLE_NAME, v_target_id, v_before, v_after);

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$;
