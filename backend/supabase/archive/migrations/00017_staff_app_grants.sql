-- ============================================================
-- 00017_staff_app_grants.sql
-- Complete GRANT pass for staff app views, tables and RPCs.
--
-- Root cause: "permission denied for view view_product_stock" (42501)
-- PostgREST only exposes objects with an explicit GRANT to the
-- calling role, regardless of RLS policies.
--
-- What is already granted by prior migrations:
--   00014: view_product_stock → authenticated
--   00015: users (column-level), customers → anon, authenticated
--          rpc_verify_user_pin, rpc_change_user_pin,
--          rpc_reset_user_pin_by_admin, rpc_create_staff_member → anon, authenticated
--   00016: view_customer_products, product_prices, product_barcodes,
--          products, orders, order_items, view_customer_balance → anon/authenticated
--          rpc_submit_customer_order → anon, authenticated
--
-- This migration adds everything still missing.
-- Safe to run multiple times — GRANT is idempotent.
-- ============================================================

-- ============================================================
-- 1. TABLES not yet granted
-- ============================================================
GRANT SELECT ON suppliers           TO authenticated;
GRANT SELECT ON payments            TO authenticated;
GRANT SELECT ON purchases           TO authenticated;
GRANT SELECT ON purchase_items      TO authenticated;
GRANT SELECT ON stock_ledger        TO authenticated;
GRANT SELECT ON customer_ledger     TO authenticated;
GRANT SELECT ON supplier_ledger     TO authenticated;
GRANT SELECT ON wallet_entries      TO authenticated;
GRANT SELECT ON settlements         TO authenticated;

-- Audit & driver tables (added in later migrations)
GRANT SELECT ON audit_log           TO authenticated;
GRANT SELECT ON driver_locations    TO authenticated;
GRANT INSERT, UPDATE ON driver_locations TO authenticated;

-- ============================================================
-- 2. VIEWS not yet granted
-- ============================================================
-- view_product_stock is already granted in 00014, but repeat is harmless
GRANT SELECT ON view_product_stock          TO authenticated;
GRANT SELECT ON view_driver_wallet_balance  TO authenticated;
GRANT SELECT ON view_supplier_balance       TO authenticated;

-- ============================================================
-- 3. RPC FUNCTIONS — only those not already granted in 00015/00016
--    Exact signatures match the CREATE OR REPLACE FUNCTION headers.
-- ============================================================

-- Purchase (00004): rpc_post_purchase(p_purchase_id UUID, p_user_id UUID)
GRANT EXECUTE ON FUNCTION rpc_post_purchase(UUID, UUID)
  TO authenticated;

-- Store sale (00014): rpc_post_store_sale(customer_id, items, paid_cash, on_account, cashier_id)
GRANT EXECUTE ON FUNCTION rpc_post_store_sale(UUID, JSONB, BIGINT, BIGINT, UUID)
  TO authenticated;

-- Order confirm (00014): rpc_confirm_online_order(order_id, cashier_id, driver_id)
GRANT EXECUTE ON FUNCTION rpc_confirm_online_order(UUID, UUID, UUID)
  TO authenticated;

-- Order delivery (00014): rpc_record_order_delivery(driver_id, order_id, collected_cash, client_id)
GRANT EXECUTE ON FUNCTION rpc_record_order_delivery(UUID, UUID, BIGINT, UUID)
  TO authenticated;

-- Driver settlement (00004): rpc_settle_driver_wallet(cashier_id, driver_id, counted_cash, notes)
GRANT EXECUTE ON FUNCTION rpc_settle_driver_wallet(UUID, UUID, BIGINT, TEXT)
  TO authenticated;

-- Debt collection (00008): rpc_collect_customer_debt(cashier_id, customer_id, amount, method, notes, client_id)
GRANT EXECUTE ON FUNCTION rpc_collect_customer_debt(UUID, UUID, BIGINT, payment_method, TEXT, UUID)
  TO authenticated;

-- Product creation (00014): rpc_create_product(product, barcodes, prices, opening_stock, user_id)
GRANT EXECUTE ON FUNCTION rpc_create_product(JSONB, JSONB, JSONB, INT, UUID)
  TO authenticated;

-- Stock adjustment (00004): rpc_adjust_stock(user_id, product_id, qty_change, reason)
GRANT EXECUTE ON FUNCTION rpc_adjust_stock(UUID, UUID, INT, TEXT)
  TO authenticated;

-- ============================================================
-- 4. FORCE PostgREST SCHEMA CACHE RELOAD
-- ============================================================
NOTIFY pgrst, 'reload schema';
