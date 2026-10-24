-- ============================================================
-- 00016_customer_app_grants_and_schema_fix.sql
-- FIX: PostgREST schema cache misses for the customer app
--
-- Root cause: view_customer_products was created in 00014 but
-- never GRANTed to anon/authenticated. PostgREST only exposes
-- objects that the calling role has SELECT privilege on, so the
-- view was invisible to every client query and the schema cache
-- returned: "could not find the table public.view_customer_products".
--
-- Also covers: product_prices and product_barcodes GRANT (needed
-- for the flat-query fallback in product_repository_impl.dart),
-- and explicit GRANT on rpc_submit_customer_order.
-- ============================================================


-- 1. GRANT SELECT on view_customer_products to both anon and authenticated
--    The view already has security_invoker = true, so RLS on the
--    underlying tables (products, stock_ledger, order_items) still applies.
GRANT SELECT ON view_customer_products TO anon, authenticated;


-- 2. GRANT SELECT on product_prices to anon and authenticated
--    RLS policy "Public read product prices" (USING TRUE) already exists
--    from migration 00005, but PostgREST also requires a schema-level GRANT.
GRANT SELECT ON product_prices TO anon, authenticated;


-- 3. GRANT SELECT on product_barcodes to anon and authenticated
--    RLS policy "Public read product barcodes" (USING TRUE) already exists
--    from migration 00005.
GRANT SELECT ON product_barcodes TO anon, authenticated;


-- 4. GRANT SELECT on products to authenticated (customer portal read)
--    RLS policy "Customers view active products" (active = TRUE) already
--    filters out inactive items for customer role.
GRANT SELECT ON products TO anon, authenticated;


-- 5. GRANT EXECUTE on rpc_submit_customer_order to anon and authenticated
--    The function was created in 00014 with SECURITY DEFINER but never
--    granted EXECUTE to the public roles.
GRANT EXECUTE ON FUNCTION rpc_submit_customer_order(UUID, UUID, JSONB, JSONB)
  TO anon, authenticated;


-- 6. GRANT SELECT on orders and order_items to authenticated
--    Needed for customerOrdersProvider to read the customer's own orders.
--    RLS "Customer view own orders" policy restricts rows to their account.
GRANT SELECT ON orders TO authenticated;
GRANT SELECT ON order_items TO authenticated;


-- 7. GRANT SELECT on view_customer_balance to authenticated
--    Used by moderator KPI tiles and the credit-limit check in checkout.
GRANT SELECT ON view_customer_balance TO authenticated;


-- 8. Notify PostgREST to reload its schema cache immediately.
--    This takes effect the moment the migration is applied — no manual
--    restart of the PostgREST process is needed.
NOTIFY pgrst, 'reload schema';
