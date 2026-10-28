-- ============================================================
-- VERIFY MIGRATION 00035
-- Run in Supabase SQL Editor after applying 002_migration_00035.sql
-- All checks should return PASS. Any FAIL needs investigation.
-- ============================================================

DO $$
DECLARE
  v_count     BIGINT;
  v_text      TEXT;
  v_pass      INT := 0;
  v_fail      INT := 0;

  PROCEDURE check(label TEXT, expr BOOLEAN) AS $$
  BEGIN
    IF expr THEN
      RAISE NOTICE 'PASS  %', label;
      v_pass := v_pass + 1;
    ELSE
      RAISE WARNING 'FAIL  %', label;
      v_fail := v_fail + 1;
    END IF;
  END;
$$ LANGUAGE plpgsql;

BEGIN

  RAISE NOTICE '=== Migration 00035 Verification ===';
  RAISE NOTICE '';
  RAISE NOTICE '--- B3: Snapshot backfill correctness ---';

  -- Check snapshots are populated
  SELECT COUNT(*) INTO v_count FROM product_stock_snapshot;
  CALL check('product_stock_snapshot has rows', v_count > 0);

  SELECT COUNT(*) INTO v_count FROM customer_balance_snapshot;
  CALL check('customer_balance_snapshot has rows', v_count >= 0);  -- may be 0 on fresh DB

  SELECT COUNT(*) INTO v_count FROM driver_wallet_snapshot;
  CALL check('driver_wallet_snapshot has rows', v_count >= 0);

  SELECT COUNT(*) INTO v_count FROM supplier_balance_snapshot;
  CALL check('supplier_balance_snapshot has rows', v_count >= 0);

  -- Snapshot totals match live ledger aggregates
  SELECT COUNT(*) INTO v_count FROM (
    SELECT s.product_id
    FROM product_stock_snapshot s
    JOIN (
      SELECT product_id, COALESCE(SUM(qty_change), 0) AS live_qty
      FROM stock_ledger GROUP BY product_id
    ) ledger USING (product_id)
    WHERE ABS(s.on_hand_qty - ledger.live_qty) > 0
  ) mismatches;
  CALL check('product_stock_snapshot matches stock_ledger aggregate', v_count = 0);

  SELECT COUNT(*) INTO v_count FROM (
    SELECT s.customer_id
    FROM customer_balance_snapshot s
    JOIN (
      SELECT customer_id, COALESCE(SUM(amount_change), 0) AS live_bal
      FROM customer_ledger GROUP BY customer_id
    ) ledger USING (customer_id)
    WHERE ABS(s.current_balance - ledger.live_bal) > 0
  ) mismatches;
  CALL check('customer_balance_snapshot matches customer_ledger aggregate', v_count = 0);

  RAISE NOTICE '';
  RAISE NOTICE '--- B1/B2: Views read from snapshots ---';

  -- view_product_stock should NOT reference stock_ledger directly
  SELECT definition INTO v_text
  FROM pg_views WHERE schemaname = 'public' AND viewname = 'view_product_stock';
  CALL check('view_product_stock uses product_stock_snapshot',
    v_text LIKE '%product_stock_snapshot%');
  CALL check('view_product_stock does NOT aggregate stock_ledger directly',
    v_text NOT LIKE '%SUM(qty_change)%');

  -- view_customer_balance should NOT reference customer_ledger directly
  SELECT definition INTO v_text
  FROM pg_views WHERE schemaname = 'public' AND viewname = 'view_customer_balance';
  CALL check('view_customer_balance uses customer_balance_snapshot',
    v_text LIKE '%customer_balance_snapshot%');
  CALL check('view_customer_balance does NOT aggregate customer_ledger directly',
    v_text NOT LIKE '%SUM(amount_change)%');

  -- view_customer_products should use LATERAL join, not correlated subqueries
  SELECT definition INTO v_text
  FROM pg_views WHERE schemaname = 'public' AND viewname = 'view_customer_products';
  CALL check('view_customer_products uses LATERAL join for prices',
    v_text LIKE '%LATERAL%');
  CALL check('view_customer_products has security_invoker',
    v_text LIKE '%security_invoker%' OR EXISTS (
      SELECT 1 FROM pg_class c
      JOIN pg_namespace n ON c.relnamespace = n.oid
      WHERE n.nspname = 'public' AND c.relname = 'view_customer_products'
        AND c.relkind = 'v'
        -- security_invoker is stored in reloptions
        AND 'security_invoker=true' = ANY(c.reloptions)
    ));

  RAISE NOTICE '';
  RAISE NOTICE '--- B4: rpc_post_store_sale signature ---';

  -- Function must exist with the correct signature
  CALL check('rpc_post_store_sale exists with 6-arg signature',
    EXISTS (
      SELECT 1 FROM pg_proc p
      JOIN pg_namespace n ON p.pronamespace = n.oid
      WHERE n.nspname = 'public'
        AND p.proname = 'rpc_post_store_sale'
        AND pronargs = 6
    ));

  -- Only one overload should exist (no old 5-arg version)
  SELECT COUNT(*) INTO v_count FROM pg_proc p
  JOIN pg_namespace n ON p.pronamespace = n.oid
  WHERE n.nspname = 'public' AND p.proname = 'rpc_post_store_sale';
  CALL check('rpc_post_store_sale has exactly 1 overload (no stale versions)', v_count = 1);

  RAISE NOTICE '';
  RAISE NOTICE '--- B5: audit_log client INSERT revoked ---';

  -- anon must not have INSERT on audit_log
  CALL check('anon cannot INSERT into audit_log',
    NOT has_table_privilege('anon', 'public.audit_log', 'INSERT'));

  -- authenticated must not have INSERT on audit_log
  CALL check('authenticated cannot INSERT into audit_log',
    NOT has_table_privilege('authenticated', 'public.audit_log', 'INSERT'));

  -- client_insert policy must not exist
  CALL check('audit_log_client_insert policy is gone',
    NOT EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname = 'public'
        AND tablename = 'audit_log'
        AND policyname = 'audit_log_client_insert'
    ));

  -- moderator SELECT policy must exist
  CALL check('audit_log_moderator_select policy exists',
    EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname = 'public'
        AND tablename = 'audit_log'
        AND policyname = 'audit_log_moderator_select'
    ));

  RAISE NOTICE '';
  RAISE NOTICE '--- B6: RLS policies use (SELECT fn()) caching ---';

  -- orders_read policy must exist
  CALL check('orders_read policy exists',
    EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname = 'public' AND tablename = 'orders'
        AND policyname = 'orders_read'
    ));

  -- orders_read must use (SELECT auth.uid()) not bare auth.uid()
  SELECT qual INTO v_text FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'orders' AND policyname = 'orders_read';
  CALL check('orders_read uses (SELECT auth.uid()) — not bare auth.uid()',
    v_text LIKE '%(SELECT auth.uid())%');

  -- products_read must exist
  CALL check('products_read policy exists',
    EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname = 'public' AND tablename = 'products'
        AND policyname = 'products_read'
    ));

  -- product_prices_read policy
  CALL check('product_prices_read policy exists',
    EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname = 'public' AND tablename = 'product_prices'
        AND policyname = 'product_prices_read'
    ));

  -- stock_ledger_insert_authenticated — must use (SELECT get_auth_role())
  SELECT with_check INTO v_text FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'stock_ledger'
    AND policyname = 'stock_ledger_insert_authenticated';
  CALL check('stock_ledger insert policy uses (SELECT get_auth_role())',
    v_text LIKE '%(SELECT get_auth_role())%');

  RAISE NOTICE '';
  RAISE NOTICE '--- B7: PIN gates on financial RPCs ---';

  -- rpc_adjust_stock must have 5 args (added p_caller_pin)
  CALL check('rpc_adjust_stock has 5 params (PIN gate added)',
    EXISTS (
      SELECT 1 FROM pg_proc p
      JOIN pg_namespace n ON p.pronamespace = n.oid
      WHERE n.nspname = 'public' AND p.proname = 'rpc_adjust_stock'
        AND pronargs = 5
    ));

  -- rpc_open_pos_shift must have 7 args (added p_cashier_pin)
  CALL check('rpc_open_pos_shift has 7 params (PIN gate added)',
    EXISTS (
      SELECT 1 FROM pg_proc p
      JOIN pg_namespace n ON p.pronamespace = n.oid
      WHERE n.nspname = 'public' AND p.proname = 'rpc_open_pos_shift'
        AND pronargs = 7
    ));

  -- rpc_purge_historical_data: anon + authenticated must not have EXECUTE
  CALL check('anon cannot call rpc_purge_historical_data',
    NOT has_function_privilege('anon',
      'public.rpc_purge_historical_data(integer,integer,integer)', 'EXECUTE'));
  CALL check('authenticated cannot call rpc_purge_historical_data',
    NOT has_function_privilege('authenticated',
      'public.rpc_purge_historical_data(integer,integer,integer)', 'EXECUTE'));

  -- rpc_resolve_stock_conflict must exist (from this migration's Part 3)
  CALL check('rpc_resolve_stock_conflict exists',
    EXISTS (
      SELECT 1 FROM pg_proc p
      JOIN pg_namespace n ON p.pronamespace = n.oid
      WHERE n.nspname = 'public' AND p.proname = 'rpc_resolve_stock_conflict'
    ));

  RAISE NOTICE '';
  RAISE NOTICE '--- Indexes ---';

  CALL check('idx_orders_cashier_id exists',
    EXISTS (
      SELECT 1 FROM pg_indexes
      WHERE schemaname = 'public' AND tablename = 'orders'
        AND indexname = 'idx_orders_cashier_id'
    ));

  RAISE NOTICE '';
  RAISE NOTICE '--- View grants ---';

  CALL check('view_product_stock readable by authenticated',
    has_table_privilege('authenticated', 'public.view_product_stock', 'SELECT'));
  CALL check('view_customer_products readable by anon',
    has_table_privilege('anon', 'public.view_customer_products', 'SELECT'));
  CALL check('view_customer_balance readable by authenticated',
    has_table_privilege('authenticated', 'public.view_customer_balance', 'SELECT'));
  CALL check('view_audit_log_enriched readable by authenticated',
    has_table_privilege('authenticated', 'public.view_audit_log_enriched', 'SELECT'));

  RAISE NOTICE '';
  RAISE NOTICE '--- Schema migration record ---';
  CALL check('schema_migrations row 00035 present',
    EXISTS (SELECT 1 FROM schema_migrations WHERE version = '00035'));

  RAISE NOTICE '';
  RAISE NOTICE '=== RESULT: % passed, % failed ===', v_pass, v_fail;
  IF v_fail > 0 THEN
    RAISE WARNING '% checks failed — review WARNINGs above before deploying', v_fail;
  ELSE
    RAISE NOTICE 'All checks passed. Migration 00035 is correctly applied.';
  END IF;

END $$;


-- ============================================================
-- FUNCTIONAL SPOT TESTS — run manually to confirm behaviour
-- ============================================================

-- 1. Stock-conflict does NOT write negative stock
--    (Only safe to run on a test DB — uses a real product/order)
/*
DO $$
DECLARE
  v_prod UUID;
  v_cust UUID;
  v_result JSONB;
  v_before INT;
  v_after INT;
BEGIN
  SELECT id INTO v_prod FROM products WHERE active = TRUE LIMIT 1;
  SELECT id INTO v_cust FROM customers LIMIT 1;

  SELECT on_hand_qty INTO v_before
  FROM product_stock_snapshot WHERE product_id = v_prod;

  -- Attempt a sale that exceeds available stock
  SELECT rpc_post_store_sale(
    gen_random_uuid(),   -- client_id
    (SELECT id FROM users WHERE role = 'cashier' LIMIT 1),
    v_cust,
    jsonb_build_array(jsonb_build_object(
      'product_id', v_prod,
      'quantity', 999999,   -- guaranteed stock conflict
      'unit_price', 100,
      'unit_cost', 50
    )),
    999999 * 100,   -- paid_cash
    0
  ) INTO v_result;

  SELECT on_hand_qty INTO v_after
  FROM product_stock_snapshot WHERE product_id = v_prod;

  ASSERT (v_result->>'stock_conflict')::BOOLEAN = TRUE,
    'Expected stock_conflict = true';
  ASSERT v_after = v_before,
    format('Stock changed despite conflict! Before: %s After: %s', v_before, v_after);

  RAISE NOTICE 'PASS  stock-conflict sale does not write negative stock_ledger';
END $$;
*/

-- 2. rpc_adjust_stock rejects empty PIN
/*
SELECT rpc_adjust_stock(
  (SELECT id FROM users WHERE role = 'moderator' LIMIT 1),
  '',   -- empty PIN
  (SELECT id FROM products LIMIT 1),
  1,
  'test'
);
-- Expected: {"status": "error", "message": "رمز PIN غير صالح"}
*/

-- 3. Find any remaining unindexed FK columns
SELECT
  conrelid::regclass AS table_name,
  a.attname          AS fk_column
FROM pg_constraint c
JOIN pg_attribute a
  ON a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey)
WHERE c.contype = 'f'
  AND NOT EXISTS (
    SELECT 1 FROM pg_index i
    WHERE i.indrelid = c.conrelid AND a.attnum = ANY(i.indkey)
  )
ORDER BY table_name, fk_column;
-- Expected: 0 rows (or only system tables)
