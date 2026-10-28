-- ============================================================
-- VIP WHOLESALE & POS MANAGEMENT SYSTEM
-- OPERATIONS - INSTALLATION VERIFICATION
-- ============================================================
-- Read-only. Run this after schema/001_fresh_schema.sql through
-- schema/006_auth_management.sql and seeds/001_admin.sql to confirm the
-- database is ready.
--
-- A healthy fresh install shows:
--   * latest_version = 00037
--   * no missing tables
--   * no missing RPCs
--   * rls_enabled = public_tables
--   * one active moderator row
--   * products/customers/suppliers/orders/app_versions = 0
--     (admin-only seed; releases are registered by the publisher)
-- ============================================================


-- 1. Baseline version -------------------------------------------------------
SELECT
    count(*)    AS applied_migrations,
    max(version) AS latest_version
FROM schema_migrations;


-- 2. Missing critical tables ------------------------------------------------
WITH expected(name) AS (
    VALUES
        ('users'), ('customers'), ('addresses'), ('suppliers'),
        ('products'), ('product_barcodes'), ('product_prices'),
        ('orders'), ('order_items'), ('payments'),
        ('purchases'), ('purchase_items'),
        ('stock_ledger'), ('customer_ledger'), ('supplier_ledger'),
        ('wallet_entries'), ('settlements'), ('driver_locations'),
        ('audit_log'), ('permissions'), ('role_permissions'),
        ('app_versions'), ('pos_shifts'),
        ('product_stock_snapshot'), ('customer_balance_snapshot'),
        ('driver_wallet_snapshot'), ('driver_location_events'),
        ('failed_operations'), ('schema_migrations'),
        ('customer_recovery'), ('auth_rate_limits')
)
SELECT e.name AS missing_table
FROM expected e
WHERE to_regclass('public.' || e.name) IS NULL
ORDER BY 1;


-- 3. Missing critical RPCs --------------------------------------------------
WITH expected(name) AS (
    VALUES
        ('rpc_verify_user_pin'), ('rpc_change_user_pin'),
        ('rpc_reset_user_pin_by_admin'), ('rpc_create_staff_member'),
        ('rpc_post_store_sale'), ('rpc_collect_customer_debt'),
        ('rpc_confirm_online_order'), ('rpc_record_order_delivery'),
        ('rpc_settle_driver_wallet'), ('rpc_post_purchase'),
        ('rpc_adjust_stock'), ('rpc_create_product'),
        ('rpc_submit_customer_order'), ('rpc_register_or_bind_customer_device'),
        ('rpc_save_user_profile'), ('rpc_create_customer_by_staff'),
        ('rpc_get_customer_order_live'), ('rpc_open_pos_shift'),
        ('rpc_close_pos_shift'), ('rpc_get_latest_app_version'),
        ('rpc_purge_historical_data'), ('rpc_bootstrap_my_account'),
        ('rpc_auth_rate_limit'), ('rpc_auth_verify_moderator_pin'),
        ('rpc_auth_customer_register_finalize'),
        ('rpc_auth_customer_recovery_verify'),
        ('rpc_auth_customer_recovery_rotate'),
        ('rpc_auth_staff_create_finalize'),
        ('rpc_auth_staff_delete_prepare')
)
SELECT e.name AS missing_rpc
FROM expected e
WHERE NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = e.name
)
ORDER BY 1;


-- 4. RLS coverage -----------------------------------------------------------
SELECT
    count(*)                                   AS public_tables,
    count(*) FILTER (WHERE c.relrowsecurity)   AS rls_enabled,
    count(*) FILTER (WHERE NOT c.relrowsecurity) AS rls_missing
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'r';


-- 5. Admin account ----------------------------------------------------------
SELECT id, phone, name, role, active, language,
       (pin_code IS NOT NULL) AS pin_set
FROM users
WHERE role = 'moderator'
ORDER BY created_at;


-- 6. RBAC reference data ----------------------------------------------------
SELECT
    (SELECT count(*) FROM permissions)       AS permissions,
    (SELECT count(*) FROM role_permissions)  AS role_permissions;


-- 7. Storage buckets --------------------------------------------------------
SELECT id, public, file_size_limit
FROM storage.buckets
WHERE id IN ('product-images', 'app-releases')
ORDER BY id;


-- 8. Demo data check (expected 0 for an admin-only seed) --------------------
SELECT
    (SELECT count(*) FROM products)     AS products,
    (SELECT count(*) FROM customers)    AS customers,
    (SELECT count(*) FROM suppliers)    AS suppliers,
    (SELECT count(*) FROM orders)       AS orders,
    (SELECT count(*) FROM app_versions) AS app_versions;


-- 9. RLS policy count -------------------------------------------------------
SELECT count(*) AS public_policies
FROM pg_policies
WHERE schemaname = 'public';

NOTIFY pgrst, 'reload schema';
