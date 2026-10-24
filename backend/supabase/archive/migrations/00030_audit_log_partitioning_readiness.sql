-- ============================================================
-- MIGRATION 00030: AUDIT LOG PARTITIONING READINESS + INDEXES
--
-- Adds composite indexes for high-query columns and creates a
-- partitioned audit_log table structure for future monthly
-- partitioning. The existing audit_log table is preserved; new
-- partitions can be attached as needed.
--
-- Safety: Additive only. Existing audit_log table and data preserved.
-- ============================================================

-- ------------------------------------------------------------------
-- 1. Composite indexes on audit_log for common query patterns
-- ------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_audit_log_created_table
    ON audit_log(created_at DESC, target_table);

CREATE INDEX IF NOT EXISTS idx_audit_log_user_created
    ON audit_log(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_audit_log_action_created
    ON audit_log(action, created_at DESC);

-- ------------------------------------------------------------------
-- 2. Composite indexes on business tables for dashboard queries
-- ------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_orders_created_status
    ON orders(created_at DESC, status);

CREATE INDEX IF NOT EXISTS idx_orders_customer_created
    ON orders(customer_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_order_items_order_product
    ON order_items(order_id, product_id);

CREATE INDEX IF NOT EXISTS idx_stock_ledger_product_created
    ON stock_ledger(product_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_wallet_entries_driver_created
    ON wallet_entries(driver_id, created_at DESC);

-- ------------------------------------------------------------------
-- 3. Partitioned audit_log table (readiness for future monthly partitioning)
--    The existing audit_log table is kept for historical data.
--    New partitions can be created and data migrated in a later step.
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS audit_log_partitioned (
    id           BIGSERIAL,
    user_id      UUID        REFERENCES users(id),
    action       VARCHAR(50) NOT NULL,
    target_table VARCHAR(50) NOT NULL,
    target_id    UUID,
    before_state JSONB,
    after_state  JSONB,
    ip_address   INET,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
) PARTITION BY RANGE (created_at);

-- Create monthly partitions for the next 12 months (readiness)
DO $$
DECLARE
    m_start DATE := date_trunc('month', CURRENT_DATE)::date;
    m_end   DATE;
    part_name TEXT;
BEGIN
    FOR i IN 0..11 LOOP
        m_start := (date_trunc('month', CURRENT_DATE) + (i || ' months')::interval)::date;
        m_end   := (m_start + interval '1 month')::date;
        part_name := 'audit_log_' || to_char(m_start, 'YYYY_MM');
        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS %I PARTITION OF audit_log_partitioned FOR VALUES FROM (%L) TO (%L)',
            part_name, m_start, m_end
        );
    END LOOP;
END $$;

-- ------------------------------------------------------------------
-- 4. Indexes on partitioned table
-- ------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_audit_log_partitioned_created
    ON audit_log_partitioned(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_audit_log_partitioned_target
    ON audit_log_partitioned(target_table, target_id);
