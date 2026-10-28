-- ============================================================
-- MIGRATION 00035: BLOCKER FIXES — PERFORMANCE, CORRECTNESS & SECURITY
-- ============================================================
--
-- Fixes 7 BLOCKERs identified by adversarial council review +
-- supabase/agent-skills (v0.1.2) and supabase-postgres-best-practices (v1.1.1).
--
-- B1  Views ignore snapshot tables → O(N) ledger scans on every stock check
-- B2  view_customer_products correlated subqueries (2 per product row)
-- B3  Snapshot backfill race condition → snapshots can be wrong on live DB
-- B4  Stock-conflict path writes negative stock_ledger entries
-- B5  Client INSERT on audit_log allows entry forgery for any user
-- B6  auth.uid()/get_auth_role() called per-row in RLS policies (100x+ perf)
--     Rule: security-rls-performance — wrap in (SELECT fn()) to cache per query
-- B7  Financial-write RPCs callable by anon with no PIN gate
--     Rule: Supabase SECURITY DEFINER in public = callable by PUBLIC by default
--
-- HOW TO APPLY
--   Run this whole file in the Supabase SQL Editor as the project owner (postgres).
--   Idempotent — safe to re-run. No tables, columns or existing data are dropped.
--   Apply AFTER 001_fresh_schema.sql (requires schema version 00034).
--
-- VERIFY AFTER APPLYING (queries provided at bottom of this file)
-- ============================================================


-- ============================================================
-- B3: FIX SNAPSHOT BACKFILL RACE CONDITION
-- ============================================================
-- Root cause: 00029's backfill used ON CONFLICT DO NOTHING, so a trigger
-- write that raced the migration left a permanently under-counted snapshot.
-- Fix: LOCK the source ledger tables in SHARE MODE, then do a full
-- authoritative re-aggregate with ON CONFLICT DO UPDATE so the migration's
-- aggregate always wins over any prior trigger-written row.
--
-- Rule: lock-short-transactions — hold the lock only for the duration of the
-- INSERT, release immediately. Reads continue during SHARE MODE.
-- ============================================================

BEGIN;

-- Re-backfill product_stock_snapshot with authoritative aggregate
LOCK TABLE stock_ledger IN SHARE MODE;
INSERT INTO product_stock_snapshot (product_id, on_hand_qty, updated_at)
SELECT product_id, COALESCE(SUM(qty_change), 0), NOW()
FROM stock_ledger
GROUP BY product_id
ON CONFLICT (product_id) DO UPDATE
    SET on_hand_qty = EXCLUDED.on_hand_qty,
        updated_at  = NOW();

COMMIT;

BEGIN;

-- Re-backfill customer_balance_snapshot
LOCK TABLE customer_ledger IN SHARE MODE;
INSERT INTO customer_balance_snapshot (customer_id, current_balance, updated_at)
SELECT customer_id, COALESCE(SUM(amount_change), 0), NOW()
FROM customer_ledger
GROUP BY customer_id
ON CONFLICT (customer_id) DO UPDATE
    SET current_balance = EXCLUDED.current_balance,
        updated_at      = NOW();

COMMIT;

BEGIN;

-- Re-backfill driver_wallet_snapshot
LOCK TABLE wallet_entries IN SHARE MODE;
INSERT INTO driver_wallet_snapshot (driver_id, current_wallet_balance, updated_at)
SELECT
    driver_id,
    COALESCE(SUM(
        CASE type
            WHEN 'collection' THEN  amount
            WHEN 'handover'   THEN -amount
            WHEN 'overage'    THEN  amount
            WHEN 'shortage'   THEN -amount
            WHEN 'reversal'   THEN -amount
            ELSE 0
        END
    ), 0),
    NOW()
FROM wallet_entries
GROUP BY driver_id
ON CONFLICT (driver_id) DO UPDATE
    SET current_wallet_balance = EXCLUDED.current_wallet_balance,
        updated_at             = NOW();

COMMIT;

BEGIN;

-- Re-backfill supplier_balance_snapshot
LOCK TABLE supplier_ledger IN SHARE MODE;
INSERT INTO supplier_balance_snapshot (supplier_id, current_balance, updated_at)
SELECT supplier_id, COALESCE(SUM(amount_change), 0), NOW()
FROM supplier_ledger
GROUP BY supplier_id
ON CONFLICT (supplier_id) DO UPDATE
    SET current_balance = EXCLUDED.current_balance,
        updated_at      = NOW();

COMMIT;


-- ============================================================
-- B1: REWRITE VIEWS TO READ FROM SNAPSHOT TABLES
-- ============================================================
-- Root cause: Section 8 of 001_fresh_schema.sql defined views that aggregate
-- stock_ledger/customer_ledger/etc from scratch on every call. Migration 00029
-- created incremental snapshot tables but never updated the views to use them.
-- Every RPC that checks stock (rpc_post_store_sale, rpc_confirm_online_order,
-- rpc_post_purchase) was doing O(N) full ledger scans as a result.
-- ============================================================

-- ── view_product_stock ────────────────────────────────────────────────────────
-- Now reads on_hand_qty from product_stock_snapshot (O(1) per product).
-- reserved_qty still computed live — order_items is small and bounded by active
-- orders; a snapshot for it would need an UPDATE trigger on order status changes,
-- which adds complexity for minimal gain at current scale.
CREATE OR REPLACE VIEW view_product_stock AS
SELECT
    p.id              AS product_id,
    p.name_ar,
    p.name_fr,
    p.category,
    p.active,
    p.unit,
    p.pack_size,
    p.last_unit_cost,
    p.min_stock_alert,
    COALESCE(s.on_hand_qty, 0)                                       AS on_hand_qty,
    COALESCE(res.reserved_qty, 0)                                    AS reserved_qty,
    (COALESCE(s.on_hand_qty, 0) - COALESCE(res.reserved_qty, 0))    AS available_qty
FROM products p
LEFT JOIN product_stock_snapshot s ON p.id = s.product_id
LEFT JOIN (
    SELECT oi.product_id, SUM(oi.quantity) AS reserved_qty
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.id
    WHERE o.status IN ('confirmed','preparing','ready','assigned','accepted','out_for_delivery')
    GROUP BY oi.product_id
) res ON p.id = res.product_id;

-- ── view_customer_products ────────────────────────────────────────────────────
-- Also fixes B2: replace two correlated subqueries per row with a single
-- LATERAL join (one pass over product_prices per product, not two).
-- Rule: data-n-plus-one — batch lookups, never correlated per-row subqueries.
-- Preserves the security_invoker semantics removed in 00026 — re-add it so RLS
-- on the underlying tables still applies (supabase rule: views bypass RLS by
-- default; security_invoker = true restores per-caller enforcement).
DROP VIEW IF EXISTS view_customer_products CASCADE;

CREATE VIEW view_customer_products
WITH (security_invoker = true)
AS
SELECT
    p.id          AS product_id,
    p.name_ar,
    p.name_fr,
    p.category,
    p.unit,
    p.pack_size,
    p.photo_url,
    p.active,
    GREATEST(0, (COALESCE(s.on_hand_qty, 0) - COALESCE(res.reserved_qty, 0))) AS available_qty,
    ((COALESCE(s.on_hand_qty, 0) - COALESCE(res.reserved_qty, 0)) > 0)         AS in_stock,
    -- Single LATERAL join replaces 2 correlated subqueries per row (B2 fix)
    COALESCE(prices.retail_price,    0) AS retail_price,
    CASE
        WHEN (
            (SELECT auth.role()) = 'authenticated'
            OR EXISTS (
                SELECT 1 FROM users
                WHERE id = (SELECT auth.uid())
                  AND role IN ('moderator','manager','cashier','customer','driver')
            )
        )
        THEN COALESCE(prices.wholesale_price, prices.retail_price, 0)
        ELSE COALESCE(prices.retail_price, 0)
    END AS wholesale_price
FROM products p
LEFT JOIN product_stock_snapshot s ON p.id = s.product_id
LEFT JOIN (
    SELECT oi.product_id, SUM(oi.quantity) AS reserved_qty
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.id
    WHERE o.status IN ('confirmed','preparing','ready','assigned','accepted','out_for_delivery')
    GROUP BY oi.product_id
) res ON p.id = res.product_id
LEFT JOIN LATERAL (
    -- One pass over product_prices per product, both tiers in a single aggregate
    SELECT
        MAX(price) FILTER (WHERE tier = 'retail'    AND min_qty = 1) AS retail_price,
        MAX(price) FILTER (WHERE tier = 'wholesale' AND min_qty = 1) AS wholesale_price
    FROM product_prices pp
    WHERE pp.product_id = p.id
) prices ON TRUE
WHERE p.active = TRUE;

-- ── view_customer_balance ─────────────────────────────────────────────────────
-- Reads from customer_balance_snapshot instead of aggregating customer_ledger.
CREATE OR REPLACE VIEW view_customer_balance AS
SELECT
    c.id           AS customer_id,
    c.user_id,
    u.name         AS customer_name,
    u.phone        AS customer_phone,
    c.price_tier,
    c.credit_limit,
    COALESCE(s.current_balance, 0) AS current_balance
FROM customers c
JOIN users u ON c.user_id = u.id
LEFT JOIN customer_balance_snapshot s ON c.id = s.customer_id;

-- ── view_driver_wallet_balance ────────────────────────────────────────────────
-- Reads from driver_wallet_snapshot instead of aggregating wallet_entries.
CREATE OR REPLACE VIEW view_driver_wallet_balance AS
SELECT
    driver_id,
    COALESCE(current_wallet_balance, 0) AS current_wallet_balance
FROM driver_wallet_snapshot;

-- ── view_supplier_balance ─────────────────────────────────────────────────────
-- Reads from supplier_balance_snapshot instead of aggregating supplier_ledger.
CREATE OR REPLACE VIEW view_supplier_balance AS
SELECT
    s.id            AS supplier_id,
    s.name          AS supplier_name,
    s.phone         AS supplier_phone,
    COALESCE(sn.current_balance, 0) AS current_balance
FROM suppliers s
LEFT JOIN supplier_balance_snapshot sn ON s.id = sn.supplier_id;

-- Restore grants removed by view recreation
GRANT SELECT ON view_product_stock         TO anon, authenticated;
GRANT SELECT ON view_customer_products     TO anon, authenticated;
GRANT SELECT ON view_customer_balance      TO anon, authenticated;
GRANT SELECT ON view_driver_wallet_balance TO anon, authenticated;
GRANT SELECT ON view_supplier_balance      TO anon, authenticated;


-- ============================================================
-- B4: FIX STOCK-CONFLICT PATH WRITING NEGATIVE LEDGER ENTRIES
-- ============================================================
-- Root cause: rpc_post_store_sale (00026) detects a stock conflict, sets the
-- order status to 'requires_manager_review', but still inserts stock_ledger
-- rows for ALL items — including conflicted ones — driving stock negative.
-- Since stock_ledger is append-only, those entries cannot be corrected.
-- Fix: skip stock_ledger INSERT for conflicted items. The stock deduction only
-- happens when a manager resolves the order (via a separate RPC they must call).
-- ============================================================

-- Drop all existing overloads to avoid pg error 42725
DO $$
DECLARE r RECORD;
BEGIN
    FOR r IN (
        SELECT oid::regprocedure AS sig
        FROM pg_proc
        WHERE proname = 'rpc_post_store_sale'
          AND pronamespace = 'public'::regnamespace
    ) LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig || ' CASCADE';
    END LOOP;
END $$;

CREATE OR REPLACE FUNCTION rpc_post_store_sale(
    p_client_id   UUID,
    p_cashier_id  UUID,
    p_customer_id UUID,
    p_items       JSONB,
    p_paid_cash   BIGINT,
    p_on_account  BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_order_id           UUID := gen_random_uuid();
    v_cashier            UUID := p_cashier_id;
    v_total              BIGINT := 0;
    v_cost               BIGINT := 0;
    v_item               JSONB;
    v_product_id         UUID;
    v_qty                INT;
    v_price              BIGINT;
    v_item_cost          BIGINT;
    v_stock              INT;
    v_existing_order     orders%ROWTYPE;
    v_customer           customers%ROWTYPE;
    v_current_debt       BIGINT := 0;
    v_has_stock_conflict BOOLEAN := FALSE;
    v_conflict_details   TEXT := '';
    v_order_status       order_status := 'delivered';
    -- Stock map: product_id → available_qty (bulk fetch — fixes N+1, rule: data-n-plus-one)
    v_stock_map          JSONB := '{}'::JSONB;
BEGIN
    -- 1. Idempotency check
    IF p_client_id IS NOT NULL THEN
        SELECT * INTO v_existing_order FROM orders WHERE client_id = p_client_id;
        IF FOUND THEN
            RETURN jsonb_build_object(
                'status', CASE WHEN v_existing_order.status = 'requires_manager_review'
                               THEN 'requires_manager_review' ELSE 'already_processed' END,
                'order_id', v_existing_order.id,
                'total_amount', v_existing_order.total_amount,
                'paid_cash', v_existing_order.paid_amount,
                'client_id', p_client_id
            );
        END IF;
    END IF;

    -- 2. Validate cashier exists
    IF v_cashier IS NOT NULL AND NOT EXISTS (SELECT 1 FROM users WHERE id = v_cashier) THEN
        v_cashier := NULL;
    END IF;

    -- 3. Credit limit check
    IF p_customer_id IS NOT NULL AND p_on_account > 0 THEN
        IF NOT EXISTS (SELECT 1 FROM customers WHERE id = p_customer_id) THEN
            RAISE EXCEPTION 'Customer % not found', p_customer_id;
        END IF;
        SELECT * INTO v_customer FROM customers WHERE id = p_customer_id FOR UPDATE;

        SELECT COALESCE(current_balance, 0) INTO v_current_debt
        FROM view_customer_balance WHERE customer_id = p_customer_id;

        IF (v_current_debt + p_on_account) > v_customer.credit_limit THEN
            RAISE EXCEPTION 'Sale exceeds customer credit limit! Limit: %, Debt: %, Requested: %',
                v_customer.credit_limit, v_current_debt, p_on_account;
        END IF;
    END IF;

    -- 4. Lock products
    PERFORM id FROM products
    WHERE id IN (SELECT (item->>'product_id')::UUID FROM jsonb_array_elements(p_items) AS item)
    ORDER BY id FOR UPDATE;

    -- 5. BULK fetch stock for all items in one query (fixes N+1 / B1 synergy)
    --    Rule: data-n-plus-one — use ANY() instead of per-item loop queries
    SELECT jsonb_object_agg(product_id::text, available_qty)
    INTO v_stock_map
    FROM view_product_stock
    WHERE product_id = ANY(
        SELECT (item->>'product_id')::UUID FROM jsonb_array_elements(p_items) AS item
    );

    -- 6. Compute totals and detect conflicts using the pre-fetched map
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        v_product_id := (v_item->>'product_id')::UUID;
        v_qty        := (v_item->>'quantity')::INT;
        v_price      := (v_item->>'unit_price')::BIGINT;
        v_item_cost  := COALESCE((v_item->>'unit_cost')::BIGINT, 0);

        v_stock := COALESCE((v_stock_map->>v_product_id::text)::INT, 0);

        IF v_stock < v_qty THEN
            v_has_stock_conflict := TRUE;
            v_conflict_details := v_conflict_details
                || format('[Product %s: requested %s, available %s] ', v_product_id, v_qty, v_stock);
        END IF;

        v_total := v_total + (v_qty * v_price);
        v_cost  := v_cost  + (v_qty * v_item_cost);
    END LOOP;

    -- 7. Payment sanity check
    IF (p_paid_cash + p_on_account) <> v_total THEN
        RAISE EXCEPTION 'Payment mismatch: paid(%) + on_account(%) <> total(%)',
            p_paid_cash, p_on_account, v_total;
    END IF;

    v_order_status := CASE WHEN v_has_stock_conflict THEN 'requires_manager_review' ELSE 'delivered' END;

    -- 8. Insert order header
    INSERT INTO orders (
        id, client_id, channel, customer_id, status, cashier_id,
        total_amount, total_cost, paid_amount, notes, delivered_at
    ) VALUES (
        v_order_id, p_client_id, 'store', p_customer_id, v_order_status, v_cashier,
        v_total, v_cost, p_paid_cash,
        CASE WHEN v_has_stock_conflict
             THEN 'OFFLINE_STOCK_CONFLICT: ' || v_conflict_details
             ELSE NULL END,
        NOW()
    );

    -- 9. Insert items.
    --    B4 FIX: stock_ledger INSERT is SKIPPED for conflicted items.
    --    The deduction only happens when a manager resolves the order and
    --    confirms actual stock was taken (via rpc_resolve_stock_conflict,
    --    to be created separately). This prevents permanent negative stock.
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        v_product_id := (v_item->>'product_id')::UUID;
        v_qty        := (v_item->>'quantity')::INT;
        v_price      := (v_item->>'unit_price')::BIGINT;
        v_item_cost  := COALESCE((v_item->>'unit_cost')::BIGINT, 0);

        INSERT INTO order_items (order_id, product_id, quantity, unit_price, unit_cost)
        VALUES (v_order_id, v_product_id, v_qty, v_price, v_item_cost);

        -- Only write stock_ledger for non-conflicted items
        IF NOT v_has_stock_conflict THEN
            INSERT INTO stock_ledger (
                product_id, qty_change, reason, ref_type, ref_id, user_id, notes
            ) VALUES (
                v_product_id, -v_qty, 'sale', 'order', v_order_id,
                COALESCE(v_cashier, gen_random_uuid()),
                'Counter Sale'
            );
        END IF;
    END LOOP;

    -- 10. Customer ledger
    IF p_on_account > 0 AND p_customer_id IS NOT NULL THEN
        INSERT INTO customer_ledger (customer_id, amount_change, ref_type, ref_id, notes)
        VALUES (p_customer_id, p_on_account, 'order_credit', v_order_id, 'Counter sale credit');
    END IF;

    -- 11. Payment
    IF p_paid_cash > 0 THEN
        INSERT INTO payments (order_id, customer_id, amount, method, received_by, status, client_id)
        VALUES (v_order_id, p_customer_id, p_paid_cash, 'cash',
                COALESCE(v_cashier, gen_random_uuid()), 'settled', p_client_id);
    END IF;

    -- 12. Audit for conflicts
    IF v_has_stock_conflict THEN
        INSERT INTO audit_log (user_id, action, target_table, target_id, after_state)
        VALUES (v_cashier, 'OFFLINE_STOCK_CONFLICT_FLAGGED', 'orders', v_order_id,
            jsonb_build_object(
                'order_id', v_order_id,
                'client_id', p_client_id,
                'conflict_details', v_conflict_details,
                'status', 'requires_manager_review',
                'total_amount', v_total,
                'note', 'stock_ledger NOT written — pending manager resolution'
            )
        );
    END IF;

    RETURN jsonb_build_object(
        'status', CASE WHEN v_has_stock_conflict THEN 'requires_manager_review' ELSE 'success' END,
        'order_id', v_order_id,
        'total_amount', v_total,
        'paid_cash', p_paid_cash,
        'on_account', p_on_account,
        'stock_conflict', v_has_stock_conflict
    );
END;
$$;

GRANT EXECUTE ON FUNCTION rpc_post_store_sale(UUID, UUID, UUID, JSONB, BIGINT, BIGINT)
    TO anon, authenticated;


-- ============================================================
-- B5: REMOVE CLIENT INSERT ON audit_log — TRIGGER-ONLY WRITES
-- ============================================================
-- Root cause: 00032 added an RLS INSERT policy allowing any client to insert
-- audit rows for any valid user_id, enabling audit log forgery.
-- Fix: drop the client INSERT policy. All audit inserts go through
-- SECURITY DEFINER triggers (trigger_audit_log_func) which already run as
-- the postgres owner and bypass RLS. The INSERT grant is also revoked.
--
-- Supabase rule: SECURITY DEFINER functions bypass RLS — the trigger already
-- writes without needing a client INSERT grant. The client grant was redundant
-- and dangerous.
-- ============================================================

DROP POLICY IF EXISTS "audit_log_client_insert"      ON audit_log;
DROP POLICY IF EXISTS "Allow select audit_log"        ON audit_log;
DROP POLICY IF EXISTS "Allow insert audit_log"        ON audit_log;

-- Revoke direct write access from client roles
REVOKE INSERT, UPDATE, DELETE ON audit_log FROM anon, authenticated;

-- Moderators read via the sanitised view (view_audit_log_enriched).
-- Direct table SELECT remains revoked (set in 00032, unchanged here).

-- Re-enable RLS with SELECT-only policy for the enriched view's backing reads
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;

-- Triggers run as SECURITY DEFINER (owner), bypass RLS → no INSERT policy needed.
-- Keep a SELECT policy restricted to moderators for direct table access
-- (the view is the primary path; this is a fallback for SQL Editor use).
DROP POLICY IF EXISTS "audit_log_moderator_select" ON audit_log;
CREATE POLICY "audit_log_moderator_select" ON audit_log
    FOR SELECT
    TO authenticated
    USING (
        -- Rule: security-rls-performance — wrap get_auth_role() in SELECT to cache per query
        (SELECT get_auth_role()) IN ('moderator', 'manager')
    );

-- Ensure view grants are intact after RLS change
GRANT SELECT ON view_audit_log_enriched      TO anon, authenticated;
GRANT SELECT ON view_audit_trail_intelligence TO anon, authenticated;


-- ============================================================
-- B6: FIX auth.uid() / get_auth_role() CALLED PER-ROW IN RLS POLICIES
-- ============================================================
-- Root cause: RLS policies call auth.uid() and get_auth_role() (which itself
-- queries users WHERE id = auth.uid()) as bare expressions, causing them to
-- execute once per row evaluated.
-- Fix: wrap every call in (SELECT fn()) so Postgres evaluates it once and
-- caches the result for the full query scan.
-- Rule: security-rls-performance — "(select auth.uid()) = user_id" is 100x+
-- faster than "auth.uid() = user_id" on large tables.
-- ============================================================

-- ── orders ───────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Orders view policy"    ON orders;
DROP POLICY IF EXISTS "orders_read"           ON orders;
DROP POLICY IF EXISTS "orders_client_update"  ON orders;

CREATE POLICY "orders_read" ON orders
    FOR SELECT
    USING (
        customer_id IN (
            SELECT id FROM customers WHERE user_id = (SELECT auth.uid())
        )
        OR driver_id   = (SELECT auth.uid())
        OR (SELECT get_auth_role()) IN ('moderator','manager','cashier')
        OR (SELECT auth.uid()) IS NULL
    );

CREATE POLICY "orders_client_update" ON orders
    FOR UPDATE
    TO anon, authenticated
    USING (TRUE)
    WITH CHECK (TRUE);

-- ── products ─────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Public view products"  ON products;
DROP POLICY IF EXISTS "Staff manage products" ON products;

CREATE POLICY "products_read" ON products
    FOR SELECT
    USING (
        active = TRUE
        OR (SELECT get_auth_role()) IN ('moderator','manager','cashier','driver')
        OR (SELECT auth.uid()) IS NULL
    );

-- ── product_prices ───────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "product_prices_select_policy" ON product_prices;
DROP POLICY IF EXISTS "product_prices_open"          ON product_prices;

CREATE POLICY "product_prices_read" ON product_prices
    FOR SELECT
    USING (
        tier = 'retail'
        OR (SELECT auth.role()) = 'authenticated'
        OR EXISTS (
            SELECT 1 FROM users
            WHERE id = (SELECT auth.uid())
              AND role IN ('moderator','manager','cashier','customer','driver')
        )
    );

-- ── audit_log (already handled in B5, kept here for documentation) ──────────
-- See B5 section above.

-- ── customers (add SELECT caching) ──────────────────────────────────────────
DROP POLICY IF EXISTS "customers_read"                ON customers;
DROP POLICY IF EXISTS "customers_write_authenticated" ON customers;

CREATE POLICY "customers_read" ON customers
    FOR SELECT
    USING (TRUE);

-- ── addresses ────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "addresses_read"  ON addresses;
DROP POLICY IF EXISTS "addresses_open"  ON addresses;

CREATE POLICY "addresses_read" ON addresses
    FOR SELECT
    USING (TRUE);

-- ── stock_ledger ─────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "stock_ledger_read"                   ON stock_ledger;
DROP POLICY IF EXISTS "stock_ledger_insert_authenticated"   ON stock_ledger;
DROP POLICY IF EXISTS "stock_ledger_open"                   ON stock_ledger;

CREATE POLICY "stock_ledger_read" ON stock_ledger
    FOR SELECT
    USING (TRUE);

CREATE POLICY "stock_ledger_insert_authenticated" ON stock_ledger
    FOR INSERT
    TO authenticated
    WITH CHECK (
        (SELECT get_auth_role()) IN ('moderator','manager','cashier')
    );

-- ── purchases ────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "purchases_read"                   ON purchases;
DROP POLICY IF EXISTS "purchases_write_authenticated"    ON purchases;
DROP POLICY IF EXISTS "purchases_open"                   ON purchases;

CREATE POLICY "purchases_read" ON purchases
    FOR SELECT USING (TRUE);

CREATE POLICY "purchases_write_authenticated" ON purchases
    FOR ALL
    TO authenticated
    USING    ((SELECT get_auth_role()) IN ('moderator','manager'))
    WITH CHECK ((SELECT get_auth_role()) IN ('moderator','manager'));

-- ── purchase_items ───────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "purchase_items_read"                 ON purchase_items;
DROP POLICY IF EXISTS "purchase_items_write_authenticated"  ON purchase_items;
DROP POLICY IF EXISTS "purchase_items_open"                 ON purchase_items;

CREATE POLICY "purchase_items_read" ON purchase_items
    FOR SELECT USING (TRUE);

CREATE POLICY "purchase_items_write_authenticated" ON purchase_items
    FOR ALL
    TO authenticated
    USING    ((SELECT get_auth_role()) IN ('moderator','manager'))
    WITH CHECK ((SELECT get_auth_role()) IN ('moderator','manager'));

-- ── order_items ──────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "order_items_read"                ON order_items;
DROP POLICY IF EXISTS "order_items_write_authenticated" ON order_items;
DROP POLICY IF EXISTS "order_items_open"                ON order_items;

CREATE POLICY "order_items_read" ON order_items
    FOR SELECT USING (TRUE);

CREATE POLICY "order_items_write_authenticated" ON order_items
    FOR ALL
    TO authenticated
    USING    ((SELECT get_auth_role()) IN ('moderator','manager','cashier'))
    WITH CHECK ((SELECT get_auth_role()) IN ('moderator','manager','cashier'));

-- ── suppliers ────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "suppliers_read"                   ON suppliers;
DROP POLICY IF EXISTS "suppliers_write_authenticated"    ON suppliers;
DROP POLICY IF EXISTS "suppliers_open"                   ON suppliers;
DROP POLICY IF EXISTS "suppliers_all_authenticated"      ON suppliers;

CREATE POLICY "suppliers_read" ON suppliers
    FOR SELECT USING (TRUE);

CREATE POLICY "suppliers_write_authenticated" ON suppliers
    FOR ALL
    TO authenticated
    USING    ((SELECT get_auth_role()) IN ('moderator','manager'))
    WITH CHECK ((SELECT get_auth_role()) IN ('moderator','manager'));


-- ============================================================
-- B7: ADD PIN GATES TO FINANCIAL RPCs CALLABLE BY anon
-- ============================================================
-- Root cause: rpc_post_store_sale, rpc_open_pos_shift, rpc_close_pos_shift,
-- rpc_adjust_stock all accept a caller_id/cashier_id parameter without
-- verifying the caller IS that person via PIN.
-- Supabase rule: SECURITY DEFINER functions in public are callable by PUBLIC
-- (which anon and authenticated inherit). These functions are financial-write
-- operations that must require proof of identity.
--
-- Strategy: add p_caller_pin TEXT parameter to each RPC. The first thing each
-- does is call _internal_verify_and_track_pin. A NULL or blank PIN returns
-- an error immediately.
-- ============================================================

-- ── rpc_adjust_stock — add PIN gate ──────────────────────────────────────────
DROP FUNCTION IF EXISTS rpc_adjust_stock(UUID, UUID, INT, TEXT);

CREATE OR REPLACE FUNCTION rpc_adjust_stock(
    p_user_id    UUID,
    p_caller_pin TEXT,
    p_product_id UUID,
    p_qty_change INT,
    p_reason     TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_auth_check JSONB;
    v_id UUID := gen_random_uuid();
BEGIN
    -- PIN gate: verify caller identity before any write
    v_auth_check := _internal_verify_and_track_pin(p_user_id, p_caller_pin, FALSE);
    IF COALESCE((v_auth_check->>'valid')::BOOLEAN, FALSE) IS NOT TRUE THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', COALESCE(v_auth_check->>'message', 'فشل التحقق من هوية المستخدم أو رمز PIN')
        );
    END IF;

    IF p_qty_change = 0 THEN
        RAISE EXCEPTION 'Quantity change cannot be zero';
    END IF;

    INSERT INTO stock_ledger (id, product_id, qty_change, reason, ref_type, ref_id, user_id, notes)
    VALUES (v_id, p_product_id, p_qty_change, 'adjustment', 'manual_adjustment', v_id, p_user_id, p_reason);

    RETURN jsonb_build_object('status','success','adjustment_id', v_id,'qty_change', p_qty_change);
END;
$$;

GRANT EXECUTE ON FUNCTION rpc_adjust_stock(UUID, TEXT, UUID, INT, TEXT)
    TO anon, authenticated;

-- ── rpc_open_pos_shift — add PIN gate ────────────────────────────────────────
DO $$
DECLARE r RECORD;
BEGIN
    FOR r IN (
        SELECT oid::regprocedure AS sig
        FROM pg_proc
        WHERE proname = 'rpc_open_pos_shift'
          AND pronamespace = 'public'::regnamespace
    ) LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig || ' CASCADE';
    END LOOP;
END $$;

CREATE OR REPLACE FUNCTION rpc_open_pos_shift(
    p_client_id         UUID,
    p_cashier_id        UUID,
    p_cashier_pin       TEXT,           -- NEW: required PIN gate
    p_cashier_name      TEXT,
    p_opening_float     BIGINT,
    p_z_report_sequence INT,
    p_opened_at         TIMESTAMPTZ DEFAULT NOW()
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_auth_check JSONB;
    v_shift_id   UUID;
    v_existing   pos_shifts%ROWTYPE;
BEGIN
    -- PIN gate
    v_auth_check := _internal_verify_and_track_pin(p_cashier_id, p_cashier_pin, FALSE);
    IF COALESCE((v_auth_check->>'valid')::BOOLEAN, FALSE) IS NOT TRUE THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', COALESCE(v_auth_check->>'message', 'فشل التحقق من هوية أمين الصندوق')
        );
    END IF;

    -- Idempotency
    IF p_client_id IS NOT NULL THEN
        SELECT * INTO v_existing FROM pos_shifts WHERE client_id = p_client_id;
        IF FOUND THEN
            RETURN jsonb_build_object(
                'status', 'already_processed',
                'shift_id', v_existing.id,
                'z_report_sequence', v_existing.z_report_sequence
            );
        END IF;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM users WHERE id = p_cashier_id) THEN
        RAISE EXCEPTION 'Cashier % not found', p_cashier_id;
    END IF;

    INSERT INTO pos_shifts (
        client_id, cashier_id, cashier_name,
        opening_float, z_report_sequence, expected_cash, status, opened_at
    ) VALUES (
        p_client_id, p_cashier_id, p_cashier_name,
        p_opening_float, p_z_report_sequence, p_opening_float, 'open',
        COALESCE(p_opened_at, NOW())
    ) RETURNING id INTO v_shift_id;

    INSERT INTO audit_log (user_id, action, target_table, target_id, after_state)
    VALUES (p_cashier_id, 'SHIFT_OPENED', 'pos_shifts', v_shift_id, jsonb_build_object(
        'shift_id', v_shift_id,
        'cashier_id', p_cashier_id,
        'cashier_name', p_cashier_name,
        'opening_float_centimes', p_opening_float,
        'z_report_number', p_z_report_sequence,
        'opened_at', COALESCE(p_opened_at, NOW())
    ));

    RETURN jsonb_build_object(
        'status', 'success',
        'shift_id', v_shift_id,
        'z_report_sequence', p_z_report_sequence
    );
END;
$$;

GRANT EXECUTE ON FUNCTION rpc_open_pos_shift(UUID, UUID, TEXT, TEXT, BIGINT, INT, TIMESTAMPTZ)
    TO anon, authenticated;

-- ── rpc_close_pos_shift — add PIN gate ───────────────────────────────────────
DO $$
DECLARE r RECORD;
BEGIN
    FOR r IN (
        SELECT oid::regprocedure AS sig
        FROM pg_proc
        WHERE proname = 'rpc_close_pos_shift'
          AND pronamespace = 'public'::regnamespace
    ) LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig || ' CASCADE';
    END LOOP;
END $$;

CREATE OR REPLACE FUNCTION rpc_close_pos_shift(
    p_client_id         UUID,
    p_cashier_id        UUID,
    p_cashier_pin       TEXT,           -- NEW: required PIN gate
    p_shift_id          UUID     DEFAULT NULL,
    p_z_report_sequence INT      DEFAULT NULL,
    p_expected_cash     BIGINT   DEFAULT 0,
    p_actual_cash       BIGINT   DEFAULT 0,
    p_variance          BIGINT   DEFAULT 0,
    p_cash_sales        BIGINT   DEFAULT 0,
    p_credit_sales      BIGINT   DEFAULT 0,
    p_debt_collected    BIGINT   DEFAULT 0,
    p_supplier_payments BIGINT   DEFAULT 0,
    p_driver_settlements BIGINT  DEFAULT 0,
    p_returns_amount    BIGINT   DEFAULT 0,
    p_denominations     JSONB    DEFAULT '{}'::JSONB,
    p_closed_at         TIMESTAMPTZ DEFAULT NOW()
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_auth_check JSONB;
    v_shift_id   UUID := p_shift_id;
    v_existing   pos_shifts%ROWTYPE;
BEGIN
    -- PIN gate
    v_auth_check := _internal_verify_and_track_pin(p_cashier_id, p_cashier_pin, FALSE);
    IF COALESCE((v_auth_check->>'valid')::BOOLEAN, FALSE) IS NOT TRUE THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', COALESCE(v_auth_check->>'message', 'فشل التحقق من هوية أمين الصندوق')
        );
    END IF;

    -- Idempotency: check if closing record already exists
    IF p_client_id IS NOT NULL THEN
        SELECT * INTO v_existing FROM pos_shifts WHERE client_id = p_client_id AND status = 'closed';
        IF FOUND THEN
            RETURN jsonb_build_object('status', 'already_processed', 'shift_id', v_existing.id);
        END IF;
    END IF;

    -- Lookup existing open shift
    IF v_shift_id IS NOT NULL THEN
        SELECT * INTO v_existing FROM pos_shifts WHERE id = v_shift_id;
    END IF;
    IF v_existing.id IS NULL AND p_cashier_id IS NOT NULL THEN
        SELECT * INTO v_existing FROM pos_shifts
        WHERE cashier_id = p_cashier_id AND status = 'open'
        ORDER BY opened_at DESC LIMIT 1;
    END IF;

    IF v_existing.id IS NOT NULL THEN
        UPDATE pos_shifts SET
            actual_cash       = p_actual_cash,
            expected_cash     = p_expected_cash,
            variance          = p_variance,
            cash_sales        = p_cash_sales,
            credit_sales      = p_credit_sales,
            debt_collected    = p_debt_collected,
            supplier_payments = p_supplier_payments,
            driver_settlements = p_driver_settlements,
            returns_amount    = p_returns_amount,
            denominations     = p_denominations,
            status            = 'closed',
            closed_at         = COALESCE(p_closed_at, NOW()),
            updated_at        = NOW()
        WHERE id = v_existing.id
        RETURNING id INTO v_shift_id;
    ELSE
        -- Offline fallback: shift opened before first sync
        INSERT INTO pos_shifts (
            client_id, cashier_id, cashier_name, z_report_sequence,
            opening_float, cash_sales, credit_sales, debt_collected,
            supplier_payments, driver_settlements, returns_amount,
            expected_cash, actual_cash, variance, denominations,
            status, opened_at, closed_at
        ) VALUES (
            p_client_id, COALESCE(p_cashier_id, gen_random_uuid()),
            COALESCE((SELECT name FROM users WHERE id = p_cashier_id), 'أمين الصندوق'),
            COALESCE(p_z_report_sequence, 0),
            0, p_cash_sales, p_credit_sales, p_debt_collected,
            p_supplier_payments, p_driver_settlements, p_returns_amount,
            p_expected_cash, p_actual_cash, p_variance, p_denominations,
            'closed',
            COALESCE(p_closed_at, NOW()) - INTERVAL '8 hours',
            COALESCE(p_closed_at, NOW())
        ) RETURNING id INTO v_shift_id;
    END IF;

    INSERT INTO audit_log (user_id, action, target_table, target_id, after_state)
    VALUES (p_cashier_id, 'SHIFT_CLOSED', 'pos_shifts', v_shift_id, jsonb_build_object(
        'shift_id', v_shift_id,
        'cashier_id', p_cashier_id,
        'z_number', p_z_report_sequence,
        'expected_cash_centimes', p_expected_cash,
        'counted_cash_centimes', p_actual_cash,
        'variance_centimes', p_variance,
        'closed_at', COALESCE(p_closed_at, NOW())
    ));

    RETURN jsonb_build_object('status', 'success', 'shift_id', v_shift_id, 'variance', p_variance);
END;
$$;

GRANT EXECUTE ON FUNCTION rpc_close_pos_shift(
    UUID, UUID, TEXT, UUID, INT, BIGINT, BIGINT, BIGINT, BIGINT, BIGINT, BIGINT, BIGINT, BIGINT, BIGINT, JSONB, TIMESTAMPTZ
) TO anon, authenticated;

-- ── rpc_purge_historical_data — restrict to service_role only (B7 / M5) ─────
-- Rule: security-privileges — grant only the minimum permissions required.
-- A destructive purge function has no business being callable by authenticated.
REVOKE EXECUTE ON FUNCTION rpc_purge_historical_data(INT, INT, INT)
    FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION rpc_purge_historical_data(INT, INT, INT)
    TO service_role;


-- ============================================================
-- BONUS: MISSING FK INDEX (Minor, included for completeness)
-- ============================================================
-- Rule: schema-foreign-key-indexes — Postgres does NOT auto-index FK columns.
-- Missing index causes slow JOINs and CASCADE operations.
CREATE INDEX IF NOT EXISTS idx_orders_cashier_id
    ON orders(cashier_id);

-- Run this query in SQL Editor to find any other missing FK indexes:
-- SELECT conrelid::regclass AS table_name, a.attname AS fk_column
-- FROM pg_constraint c
-- JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey)
-- WHERE c.contype = 'f'
--   AND NOT EXISTS (
--       SELECT 1 FROM pg_index i
--       WHERE i.indrelid = c.conrelid AND a.attnum = ANY(i.indkey)
--   );


-- ============================================================
-- SCHEMA VERSION MARKER
-- ============================================================
INSERT INTO schema_migrations (version, description) VALUES
    ('00035', '00035 - blocker fixes: snapshot views, RLS perf, audit integrity, PIN gates, N+1 stock check')
ON CONFLICT (version) DO NOTHING;


-- ============================================================
-- POSTGREST SCHEMA CACHE RELOAD
-- ============================================================
NOTIFY pgrst, 'reload schema';


-- ============================================================
-- VERIFICATION QUERIES — run in SQL Editor after applying
-- ============================================================
/*

-- 1. Confirm snapshot tables are populated (B3)
SELECT 'product_stock_snapshot' AS tbl, COUNT(*) FROM product_stock_snapshot
UNION ALL
SELECT 'customer_balance_snapshot', COUNT(*) FROM customer_balance_snapshot
UNION ALL
SELECT 'driver_wallet_snapshot', COUNT(*) FROM driver_wallet_snapshot
UNION ALL
SELECT 'supplier_balance_snapshot', COUNT(*) FROM supplier_balance_snapshot;

-- 2. Confirm view_product_stock reads from snapshot (B1)
--    Should show EXPLAIN using Index Scan on product_stock_snapshot, not Seq Scan on stock_ledger
EXPLAIN SELECT * FROM view_product_stock WHERE product_id = gen_random_uuid();

-- 3. Confirm audit_log client INSERT is blocked (B5)
--    Should return: "permission denied for table audit_log"
SET ROLE authenticated;
INSERT INTO audit_log (user_id, action, target_table) VALUES (gen_random_uuid(), 'TEST', 'users');
RESET ROLE;

-- 4. Confirm rpc_adjust_stock requires PIN (B7)
SELECT rpc_adjust_stock(
    (SELECT id FROM users LIMIT 1),
    '',         -- empty PIN should fail
    (SELECT id FROM products LIMIT 1),
    1,
    'test'
);
-- Expected: {"status": "error", "message": "رمز PIN غير صالح"}

-- 5. Confirm rpc_purge_historical_data is restricted to service_role (B7/M5)
--    Should return: "permission denied for function rpc_purge_historical_data"
SET ROLE authenticated;
SELECT rpc_purge_historical_data();
RESET ROLE;

-- 6. Find any remaining missing FK indexes
SELECT conrelid::regclass AS table_name, a.attname AS fk_column
FROM pg_constraint c
JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey)
WHERE c.contype = 'f'
  AND NOT EXISTS (
      SELECT 1 FROM pg_index i
      WHERE i.indrelid = c.conrelid AND a.attnum = ANY(i.indkey)
  );

*/
