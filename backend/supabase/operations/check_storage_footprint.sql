-- ============================================================
-- VIP WHOLESALE & POS MANAGEMENT SYSTEM
-- OPERATIONS - STORAGE FOOTPRINT & QUOTA AUDIT
-- ============================================================
-- Read-only diagnostic query to inspect table sizes, index overhead,
-- row counts, and archivable candidates under the Supabase 500 MB Free Tier.
-- ============================================================

-- ------------------------------------------------------------------
-- 1. Table & Index Disk Footprint (Top Tables by Size)
-- ------------------------------------------------------------------
WITH table_sizes AS (
    SELECT
        c.relname AS table_name,
        c.reltuples::BIGINT AS estimated_rows,
        pg_total_relation_size(c.oid) AS total_bytes,
        pg_relation_size(c.oid) AS table_bytes,
        pg_indexes_size(c.oid) AS index_bytes
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind = 'r'
)
SELECT
    table_name,
    estimated_rows,
    pg_size_pretty(table_bytes) AS table_size,
    pg_size_pretty(index_bytes) AS index_size,
    pg_size_pretty(total_bytes) AS total_size,
    round(100.0 * total_bytes / NULLIF((SELECT sum(total_bytes) FROM table_sizes), 0), 1) AS pct_of_db,
    round(100.0 * total_bytes / 524288000.0, 2) AS pct_of_500mb_free_quota
FROM table_sizes
ORDER BY total_bytes DESC;


-- ------------------------------------------------------------------
-- 2. Total Database Footprint vs. 500 MB Free Tier Limit
-- ------------------------------------------------------------------
SELECT
    pg_size_pretty(pg_database_size(current_database())) AS total_db_size,
    pg_size_pretty(524288000 - pg_database_size(current_database())) AS remaining_free_space,
    round(100.0 * pg_database_size(current_database()) / 524288000.0, 2) AS pct_quota_used,
    CASE 
        WHEN pg_database_size(current_database()) < 262144000 THEN 'HEALTHY (Below 50% Quota)'
        WHEN pg_database_size(current_database()) < 419430400 THEN 'WARNING (Above 50% Quota - Run Cleanup)'
        ELSE 'CRITICAL (Approaching 500 MB Free Limit)'
    END AS quota_status;


-- ------------------------------------------------------------------
-- 3. Core Preserved Assets (Must NEVER be zero in active store)
-- ------------------------------------------------------------------
SELECT
    (SELECT count(*) FROM products)                  AS total_products,
    (SELECT count(*) FROM customers)                 AS total_customers,
    (SELECT count(*) FROM suppliers)                 AS total_suppliers,
    (SELECT count(*) FROM users)                     AS total_users,
    (SELECT count(*) FROM stock_ledger)              AS stock_ledger_entries,
    (SELECT count(*) FROM customer_ledger)           AS customer_ledger_entries,
    (SELECT count(*) FROM supplier_ledger)           AS supplier_ledger_entries,
    (SELECT count(*) FROM wallet_entries)            AS wallet_entries;


-- ------------------------------------------------------------------
-- 4. Archivable Candidates (Data older than retention thresholds)
-- ------------------------------------------------------------------
SELECT
    (
        SELECT count(*) FROM orders
        WHERE status IN ('delivered', 'settled', 'cancelled')
          AND created_at < NOW() - INTERVAL '60 days'
    ) AS archivable_orders_60d,
    (
        SELECT count(*) FROM order_items
        WHERE order_id IN (
            SELECT id FROM orders
            WHERE status IN ('delivered', 'settled', 'cancelled')
              AND created_at < NOW() - INTERVAL '60 days'
        )
    ) AS archivable_order_items_60d,
    (
        SELECT count(*) FROM audit_log
        WHERE created_at < NOW() - INTERVAL '30 days'
    ) AS archivable_audit_log_30d,
    (
        SELECT count(*) FROM driver_location_events
        WHERE recorded_at < NOW() - INTERVAL '7 days'
    ) AS archivable_telemetry_events_7d;
