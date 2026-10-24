-- ============================================================
-- VIP WHOLESALE & POS MANAGEMENT SYSTEM
-- STORAGE LIFECYCLE & RETENTION MANAGEMENT (00034+)
-- ============================================================
-- Optimizes storage for permanent operation under the Supabase Free
-- Tier (500 MB limit).
--
-- Capabilities:
-- 1. Updates foreign key on payments(order_id) to ON DELETE SET NULL
--    so archived orders can be safely pruned without breaking payment
--    or customer ledger history.
-- 2. Adds maintenance mode bypass to trigger_audit_log_func so bulk
--    archival doesn't flood audit_log with DELETE triggers.
-- 3. Provides rpc_purge_historical_data() to prune:
--    - Closed orders & items > p_order_retention_days (default 60 days)
--    - Audit logs > p_audit_retention_days (default 30 days)
--    - Driver location events > p_telemetry_retention_days (default 7 days)
--    - Transient failed offline operations > 14 days
--
-- PRESERVED DATA (NEVER DELETED):
--   - Products, prices, barcodes, product_stock_snapshot
--   - Customers, addresses, customer_ledger, customer_balance_snapshot
--   - Suppliers, purchases, supplier_ledger, supplier_balance_snapshot
--   - Users, permissions, role_permissions
--   - Payments, settlements, wallet_entries, driver_wallet_snapshot
--   - In-flight/active orders ('submitted', 'confirmed', 'preparing',
--     'ready', 'assigned', 'accepted', 'out_for_delivery')
-- ============================================================

-- ------------------------------------------------------------------
-- 1. Foreign Key Adjustment: payments.order_id ON DELETE SET NULL
-- ------------------------------------------------------------------
DO $$
BEGIN
    -- Drop existing constraint if named payments_order_id_fkey
    IF EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'payments_order_id_fkey'
          AND table_name = 'payments'
    ) THEN
        ALTER TABLE payments DROP CONSTRAINT payments_order_id_fkey;
    END IF;

    -- Re-add with ON DELETE SET NULL
    ALTER TABLE payments
        ADD CONSTRAINT payments_order_id_fkey
        FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE SET NULL;
END $$;


-- ------------------------------------------------------------------
-- 2. Performance Index on driver_location_events(recorded_at)
-- ------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_driver_location_events_recorded_at
    ON driver_location_events(recorded_at);

CREATE INDEX IF NOT EXISTS idx_orders_status_created_at
    ON orders(status, created_at)
    WHERE status IN ('delivered', 'settled', 'cancelled');


-- ------------------------------------------------------------------
-- 3. Update Audit Trigger Function to Support Maintenance Bypass
-- ------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trigger_audit_log_func()
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

    -- Resolve actor from auth.uid() when a JWT exists.
    BEGIN
        v_user_id := auth.uid();
    EXCEPTION WHEN OTHERS THEN
        v_user_id := NULL;
    END;

    -- Convert composite rows to JSONB once.
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
    ELSE
        -- For other retained tables, store only keys/changes
        IF TG_OP = 'INSERT' THEN
            v_after := jsonb_build_object('id', v_target_id);
        ELSIF TG_OP = 'UPDATE' THEN
            v_before := jsonb_build_object('id', v_target_id);
            v_after := jsonb_build_object('id', v_target_id);
        ELSIF TG_OP = 'DELETE' THEN
            v_before := jsonb_build_object('id', v_target_id);
        END IF;
    END IF;

    INSERT INTO audit_log (
        table_name,
        action,
        user_id,
        before_state,
        after_state,
        target_id
    ) VALUES (
        TG_TABLE_NAME,
        TG_OP,
        v_user_id,
        v_before,
        v_after,
        v_target_id
    );

    RETURN COALESCE(NEW, OLD);
EXCEPTION WHEN OTHERS THEN
    -- Audit must never break user transactions
    RETURN COALESCE(NEW, OLD);
END;
$$;


-- ------------------------------------------------------------------
-- 4. Storage Purge & Archival Procedure: rpc_purge_historical_data
-- ------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_purge_historical_data(
    p_order_retention_days INT DEFAULT 60,
    p_audit_retention_days INT DEFAULT 30,
    p_telemetry_retention_days INT DEFAULT 7
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_purged_orders BIGINT := 0;
    v_purged_order_items BIGINT := 0;
    v_purged_audit BIGINT := 0;
    v_purged_telemetry BIGINT := 0;
    v_purged_failed_ops BIGINT := 0;
    v_cutoff_orders TIMESTAMPTZ;
    v_cutoff_audit TIMESTAMPTZ;
    v_cutoff_telemetry TIMESTAMPTZ;
BEGIN
    -- Guardrails on minimum safe retention periods
    IF p_order_retention_days < 14 THEN
        RAISE EXCEPTION 'Order retention cannot be less than 14 days.';
    END IF;
    IF p_audit_retention_days < 7 THEN
        RAISE EXCEPTION 'Audit retention cannot be less than 7 days.';
    END IF;
    IF p_telemetry_retention_days < 1 THEN
        RAISE EXCEPTION 'Telemetry retention cannot be less than 1 day.';
    END IF;

    v_cutoff_orders := NOW() - (p_order_retention_days || ' days')::INTERVAL;
    v_cutoff_audit := NOW() - (p_audit_retention_days || ' days')::INTERVAL;
    v_cutoff_telemetry := NOW() - (p_telemetry_retention_days || ' days')::INTERVAL;

    -- Suppress audit triggers during batch cleanup
    PERFORM set_config('app.maintenance_mode', 'true', true);

    -- 1. Purge driver location events older than threshold
    DELETE FROM driver_location_events
    WHERE recorded_at < v_cutoff_telemetry;
    GET DIAGNOSTICS v_purged_telemetry = ROW_COUNT;

    -- 2. Purge transient offline sync failure logs older than 14 days
    DELETE FROM failed_operations
    WHERE created_at < (NOW() - INTERVAL '14 days');
    GET DIAGNOSTICS v_purged_failed_ops = ROW_COUNT;

    -- 3. Purge audit log records older than threshold
    DELETE FROM audit_log
    WHERE created_at < v_cutoff_audit;
    GET DIAGNOSTICS v_purged_audit = ROW_COUNT;

    -- Also purge audit_log_partitioned if active
    IF to_regclass('public.audit_log_partitioned') IS NOT NULL THEN
        BEGIN
            DELETE FROM audit_log_partitioned WHERE created_at < v_cutoff_audit;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END IF;

    -- 4. Purge closed/delivered/cancelled orders older than threshold
    --    ACTIVE / IN-FLIGHT orders are NEVER touched!
    -- Detach payments from orders being deleted so payment records remain intact
    UPDATE payments
    SET order_id = NULL
    WHERE order_id IN (
        SELECT id FROM orders
        WHERE status IN ('delivered', 'settled', 'cancelled')
          AND created_at < v_cutoff_orders
    );

    -- Delete order_items
    WITH old_orders AS (
        SELECT id FROM orders
        WHERE status IN ('delivered', 'settled', 'cancelled')
          AND created_at < v_cutoff_orders
    ),
    deleted_items AS (
        DELETE FROM order_items
        WHERE order_id IN (SELECT id FROM old_orders)
        RETURNING id
    )
    SELECT count(*) INTO v_purged_order_items FROM deleted_items;

    -- Delete orders
    WITH deleted_orders AS (
        DELETE FROM orders
        WHERE status IN ('delivered', 'settled', 'cancelled')
          AND created_at < v_cutoff_orders
        RETURNING id
    )
    SELECT count(*) INTO v_purged_orders FROM deleted_orders;

    RETURN jsonb_build_object(
        'status', 'success',
        'purged_orders', v_purged_orders,
        'purged_order_items', v_purged_order_items,
        'purged_audit_entries', v_purged_audit,
        'purged_telemetry_events', v_purged_telemetry,
        'purged_failed_operations', v_purged_failed_ops,
        'order_retention_days', p_order_retention_days,
        'audit_retention_days', p_audit_retention_days,
        'telemetry_retention_days', p_telemetry_retention_days,
        'executed_at', NOW()
    );
END;
$$;

-- Revoke public access; only authenticated and service_role can call this
REVOKE EXECUTE ON FUNCTION rpc_purge_historical_data(INT, INT, INT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_purge_historical_data(INT, INT, INT) TO service_role, authenticated;
