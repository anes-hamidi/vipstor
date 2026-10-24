-- ============================================================
-- 00010_add_preparing_ready_order_statuses.sql
-- EXTEND ORDER_STATUS ENUM WITH PREPARING AND READY STATES
-- ============================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_type t
        JOIN pg_enum e ON t.oid = e.enumtypid
        WHERE t.typname = 'order_status' AND e.enumlabel = 'preparing'
    ) THEN
        ALTER TYPE order_status ADD VALUE 'preparing' AFTER 'confirmed';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_type t
        JOIN pg_enum e ON t.oid = e.enumtypid
        WHERE t.typname = 'order_status' AND e.enumlabel = 'ready'
    ) THEN
        ALTER TYPE order_status ADD VALUE 'ready' AFTER 'preparing';
    END IF;
END $$;
