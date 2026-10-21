-- ============================================================
-- MIGRATION 00026: RESILIENCE & SCALABILITY OPTIMIZATIONS
-- 1. Structured POS Shifts Table & Settlement RPCs
-- 2. Deterministic Offline Stock Conflict Policy (requires_manager_review)
-- 3. Isolated Pricing Tier Visibility (Retail baseline for anon, Wholesale for authenticated)
-- ============================================================

-- ------------------------------------------------------------
-- 1. ADD 'requires_manager_review' TO order_status ENUM
-- ------------------------------------------------------------
DO $$
BEGIN
    ALTER TYPE order_status ADD VALUE IF NOT EXISTS 'requires_manager_review';
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

-- ------------------------------------------------------------
-- 2. STRUCTURED POS SHIFTS SETTLEMENT SCHEMA
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pos_shifts (
    id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id              UUID UNIQUE, -- Offline idempotency key
    cashier_id             UUID NOT NULL REFERENCES users(id),
    cashier_name           TEXT NOT NULL,
    z_report_sequence      INT NOT NULL,
    opening_float          BIGINT NOT NULL DEFAULT 0, -- Centimes
    cash_sales             BIGINT NOT NULL DEFAULT 0, -- Centimes
    credit_sales           BIGINT NOT NULL DEFAULT 0, -- Centimes
    debt_collected         BIGINT NOT NULL DEFAULT 0, -- Centimes
    supplier_payments      BIGINT NOT NULL DEFAULT 0, -- Centimes
    driver_settlements     BIGINT NOT NULL DEFAULT 0, -- Centimes
    returns_amount         BIGINT NOT NULL DEFAULT 0, -- Centimes
    expected_cash          BIGINT NOT NULL DEFAULT 0, -- Centimes
    actual_cash            BIGINT,                    -- Centimes (populated upon close)
    variance               BIGINT,                    -- Centimes (actual - expected)
    denominations          JSONB DEFAULT '{}'::jsonb, -- Note/coin breakdown
    status                 TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'closed')),
    opened_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    closed_at              TIMESTAMPTZ,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Targeted indexes for cashier settlement querying and reporting
CREATE INDEX IF NOT EXISTS idx_pos_shifts_cashier_id ON pos_shifts(cashier_id);
CREATE INDEX IF NOT EXISTS idx_pos_shifts_opened_at ON pos_shifts(opened_at DESC);
CREATE INDEX IF NOT EXISTS idx_pos_shifts_closed_at ON pos_shifts(closed_at DESC);
CREATE INDEX IF NOT EXISTS idx_pos_shifts_z_sequence ON pos_shifts(z_report_sequence);
CREATE INDEX IF NOT EXISTS idx_pos_shifts_status ON pos_shifts(status);

-- Enable RLS and establish security boundary
ALTER TABLE pos_shifts ENABLE ROW LEVEL SECURITY;
REVOKE INSERT, UPDATE, DELETE ON pos_shifts FROM anon, authenticated;
GRANT SELECT ON pos_shifts TO anon, authenticated;

DROP POLICY IF EXISTS "pos_shifts_read" ON pos_shifts;
CREATE POLICY "pos_shifts_read" ON pos_shifts FOR SELECT USING (TRUE);

-- ------------------------------------------------------------
-- DROP EXISTING OVERLOADS OF SHIFT & SALE RPCS TO AVOID AMBIGUITY (ERROR 42725)
-- ------------------------------------------------------------
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (
        SELECT oid::regprocedure AS func_sig
        FROM pg_proc
        WHERE proname IN ('rpc_post_store_sale', 'rpc_open_pos_shift', 'rpc_close_pos_shift')
          AND pronamespace = 'public'::regnamespace
    ) LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.func_sig || ' CASCADE';
    END LOOP;
END $$;

-- ------------------------------------------------------------
-- RPC: rpc_open_pos_shift
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_open_pos_shift(
    p_client_id UUID,
    p_cashier_id UUID,
    p_cashier_name TEXT,
    p_opening_float BIGINT,
    p_z_report_sequence INT,
    p_opened_at TIMESTAMPTZ DEFAULT NOW()
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_shift_id UUID;
    v_existing pos_shifts%ROWTYPE;
BEGIN
    -- Idempotency check via client_id
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

    -- Validate cashier existence
    IF NOT EXISTS (SELECT 1 FROM users WHERE id = p_cashier_id) THEN
        RAISE EXCEPTION 'Cashier % not found', p_cashier_id;
    END IF;

    INSERT INTO pos_shifts (
        client_id,
        cashier_id,
        cashier_name,
        opening_float,
        z_report_sequence,
        expected_cash,
        status,
        opened_at
    ) VALUES (
        p_client_id,
        p_cashier_id,
        p_cashier_name,
        p_opening_float,
        p_z_report_sequence,
        p_opening_float,
        'open',
        COALESCE(p_opened_at, NOW())
    )
    RETURNING id INTO v_shift_id;

    -- Structured audit trail entry
    INSERT INTO audit_log (user_id, action, target_table, target_id, after_state)
    VALUES (
        p_cashier_id,
        'SHIFT_OPENED',
        'pos_shifts',
        v_shift_id,
        jsonb_build_object(
            'shift_id', v_shift_id,
            'client_id', p_client_id,
            'cashier_id', p_cashier_id,
            'cashier_name', p_cashier_name,
            'opening_float_centimes', p_opening_float,
            'z_report_number', p_z_report_sequence,
            'opened_at', COALESCE(p_opened_at, NOW())
        )
    );

    RETURN jsonb_build_object(
        'status', 'success',
        'shift_id', v_shift_id,
        'z_report_sequence', p_z_report_sequence
    );
END;
$$;

-- ------------------------------------------------------------
-- RPC: rpc_close_pos_shift
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_close_pos_shift(
    p_client_id UUID,
    p_shift_id UUID DEFAULT NULL,
    p_cashier_id UUID DEFAULT NULL,
    p_z_report_sequence INT DEFAULT NULL,
    p_expected_cash BIGINT DEFAULT 0,
    p_actual_cash BIGINT DEFAULT 0,
    p_variance BIGINT DEFAULT 0,
    p_cash_sales BIGINT DEFAULT 0,
    p_credit_sales BIGINT DEFAULT 0,
    p_debt_collected BIGINT DEFAULT 0,
    p_supplier_payments BIGINT DEFAULT 0,
    p_driver_settlements BIGINT DEFAULT 0,
    p_returns_amount BIGINT DEFAULT 0,
    p_denominations JSONB DEFAULT '{}'::jsonb,
    p_closed_at TIMESTAMPTZ DEFAULT NOW()
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_shift_id UUID := p_shift_id;
    v_existing pos_shifts%ROWTYPE;
BEGIN
    -- Idempotency check via client_id if closing record already created
    IF p_client_id IS NOT NULL THEN
        SELECT * INTO v_existing FROM pos_shifts WHERE client_id = p_client_id AND status = 'closed';
        IF FOUND THEN
            RETURN jsonb_build_object(
                'status', 'already_processed',
                'shift_id', v_existing.id
            );
        END IF;
    END IF;

    -- Lookup existing shift
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
            actual_cash = p_actual_cash,
            expected_cash = p_expected_cash,
            variance = p_variance,
            cash_sales = p_cash_sales,
            credit_sales = p_credit_sales,
            debt_collected = p_debt_collected,
            supplier_payments = p_supplier_payments,
            driver_settlements = p_driver_settlements,
            returns_amount = p_returns_amount,
            denominations = p_denominations,
            status = 'closed',
            closed_at = COALESCE(p_closed_at, NOW()),
            updated_at = NOW()
        WHERE id = v_existing.id
        RETURNING id INTO v_shift_id;
    ELSE
        -- Insert fallback when opened offline prior to sync
        INSERT INTO pos_shifts (
            client_id,
            cashier_id,
            cashier_name,
            z_report_sequence,
            opening_float,
            cash_sales,
            credit_sales,
            debt_collected,
            supplier_payments,
            driver_settlements,
            returns_amount,
            expected_cash,
            actual_cash,
            variance,
            denominations,
            status,
            opened_at,
            closed_at
        ) VALUES (
            p_client_id,
            COALESCE(p_cashier_id, gen_random_uuid()),
            COALESCE((SELECT name FROM users WHERE id = p_cashier_id), 'أمين الصندوق'),
            COALESCE(p_z_report_sequence, 0),
            0,
            p_cash_sales,
            p_credit_sales,
            p_debt_collected,
            p_supplier_payments,
            p_driver_settlements,
            p_returns_amount,
            p_expected_cash,
            p_actual_cash,
            p_variance,
            p_denominations,
            'closed',
            COALESCE(p_closed_at, NOW()) - INTERVAL '8 hours',
            COALESCE(p_closed_at, NOW())
        )
        RETURNING id INTO v_shift_id;
    END IF;

    -- Structured audit trail entry
    INSERT INTO audit_log (user_id, action, target_table, target_id, after_state)
    VALUES (
        p_cashier_id,
        'SHIFT_CLOSED',
        'pos_shifts',
        v_shift_id,
        jsonb_build_object(
            'shift_id', v_shift_id,
            'client_id', p_client_id,
            'cashier_id', p_cashier_id,
            'z_number', p_z_report_sequence,
            'expected_cash_centimes', p_expected_cash,
            'counted_cash_centimes', p_actual_cash,
            'variance_centimes', p_variance,
            'cash_sales_centimes', p_cash_sales,
            'credit_sales_centimes', p_credit_sales,
            'debt_collected_centimes', p_debt_collected,
            'supplier_payments_centimes', p_supplier_payments,
            'driver_settlement_centimes', p_driver_settlements,
            'closed_at', COALESCE(p_closed_at, NOW())
        )
    );

    RETURN jsonb_build_object(
        'status', 'success',
        'shift_id', v_shift_id,
        'variance', p_variance
    );
END;
$$;

GRANT EXECUTE ON FUNCTION rpc_open_pos_shift(UUID, UUID, TEXT, BIGINT, INT, TIMESTAMPTZ) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION rpc_close_pos_shift(UUID, UUID, UUID, INT, BIGINT, BIGINT, BIGINT, BIGINT, BIGINT, BIGINT, BIGINT, BIGINT, BIGINT, JSONB, TIMESTAMPTZ) TO anon, authenticated;

-- ------------------------------------------------------------
-- 3. DETERMINISTIC OFFLINE SALE SYNC: rpc_post_store_sale
-- Handles offline stock shortage by flagging 'requires_manager_review'
-- instead of throwing unhandled exceptions.
-- ------------------------------------------------------------
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
BEGIN
    -- 1. Idempotency check via client_id
    IF p_client_id IS NOT NULL THEN
        SELECT * INTO v_existing_order FROM orders WHERE client_id = p_client_id;
        IF FOUND THEN
            RETURN jsonb_build_object(
                'status', CASE WHEN v_existing_order.status = 'requires_manager_review' THEN 'requires_manager_review' ELSE 'already_processed' END,
                'order_id', v_existing_order.id,
                'total_amount', v_existing_order.total_amount,
                'paid_cash', v_existing_order.paid_amount,
                'client_id', p_client_id
            );
        END IF;
    END IF;

    -- 2. Validate cashier
    IF v_cashier IS NOT NULL AND NOT EXISTS (SELECT 1 FROM users WHERE id = v_cashier) THEN
        v_cashier := NULL;
    END IF;

    -- 3. Validate customer credit limit if on account
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

    -- Lock affected products
    PERFORM id FROM products
    WHERE id IN (SELECT (item->>'product_id')::UUID FROM jsonb_array_elements(p_items) AS item)
    ORDER BY id FOR UPDATE;

    -- 4. Check stock and compute totals
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        v_product_id := (v_item->>'product_id')::UUID;
        v_qty        := (v_item->>'quantity')::INT;
        v_price      := (v_item->>'unit_price')::BIGINT;
        v_item_cost  := COALESCE((v_item->>'unit_cost')::BIGINT, 0);

        SELECT COALESCE(available_qty, 0) INTO v_stock FROM view_product_stock WHERE product_id = v_product_id;
        IF v_stock < v_qty THEN
            v_has_stock_conflict := TRUE;
            v_conflict_details := v_conflict_details || format('[Product %s: requested %s, available %s] ', v_product_id, v_qty, v_stock);
        END IF;

        v_total := v_total + (v_qty * v_price);
        v_cost  := v_cost  + (v_qty * v_item_cost);
    END LOOP;

    -- 5. Payment check
    IF (p_paid_cash + p_on_account) <> v_total THEN
        RAISE EXCEPTION 'Payment mismatch: paid(%) + on_account(%) <> total(%)', p_paid_cash, p_on_account, v_total;
    END IF;

    -- Status classification based on stock availability
    IF v_has_stock_conflict THEN
        v_order_status := 'requires_manager_review';
    ELSE
        v_order_status := 'delivered';
    END IF;

    -- 6. Insert Order Header
    INSERT INTO orders (
        id, client_id, channel, customer_id, status, cashier_id,
        total_amount, total_cost, paid_amount, notes, delivered_at
    )
    VALUES (
        v_order_id, p_client_id, 'store', p_customer_id, v_order_status, v_cashier,
        v_total, v_cost, p_paid_cash,
        CASE WHEN v_has_stock_conflict THEN 'OFFLINE_STOCK_CONFLICT: ' || v_conflict_details ELSE NULL END,
        NOW()
    );

    -- 7. Insert Items & Stock Ledger
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        v_product_id := (v_item->>'product_id')::UUID;
        v_qty        := (v_item->>'quantity')::INT;
        v_price      := (v_item->>'unit_price')::BIGINT;
        v_item_cost  := COALESCE((v_item->>'unit_cost')::BIGINT, 0);

        INSERT INTO order_items (order_id, product_id, quantity, unit_price, unit_cost)
        VALUES (v_order_id, v_product_id, v_qty, v_price, v_item_cost);

        INSERT INTO stock_ledger (product_id, qty_change, reason, ref_type, ref_id, user_id, notes)
        VALUES (
            v_product_id,
            -v_qty,
            'sale',
            'order',
            v_order_id,
            COALESCE(v_cashier, gen_random_uuid()),
            CASE WHEN v_has_stock_conflict THEN 'Counter Sale (Stock Conflict Flagged)' ELSE 'Counter Sale' END
        );
    END LOOP;

    -- 8. Customer Ledger (if on account)
    IF p_on_account > 0 AND p_customer_id IS NOT NULL THEN
        INSERT INTO customer_ledger (customer_id, amount_change, ref_type, ref_id, notes)
        VALUES (p_customer_id, p_on_account, 'order_credit', v_order_id, 'Counter sale credit');
    END IF;

    -- 9. Payment Record (if paid cash)
    IF p_paid_cash > 0 THEN
        INSERT INTO payments (order_id, customer_id, amount, method, received_by, status, client_id)
        VALUES (v_order_id, p_customer_id, p_paid_cash, 'cash', COALESCE(v_cashier, gen_random_uuid()), 'settled', p_client_id);
    END IF;

    -- 10. Audit alert on stock conflict
    IF v_has_stock_conflict THEN
        INSERT INTO audit_log (user_id, action, target_table, target_id, after_state)
        VALUES (
            v_cashier,
            'OFFLINE_STOCK_CONFLICT_FLAGGED',
            'orders',
            v_order_id,
            jsonb_build_object(
                'order_id', v_order_id,
                'client_id', p_client_id,
                'conflict_details', v_conflict_details,
                'status', 'requires_manager_review',
                'total_amount', v_total
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

GRANT EXECUTE ON FUNCTION rpc_post_store_sale(UUID, UUID, UUID, JSONB, BIGINT, BIGINT) TO anon, authenticated;

-- ------------------------------------------------------------
-- 4. ISOLATE PRICING TIER VISIBILITY
-- Baseline retail pricing exposed for unauthenticated catalog browsing.
-- Tiered wholesale pricing unlocked only for authenticated/validated customers & staff.
-- ------------------------------------------------------------

-- A. Restrict product_prices SELECT policy
DROP POLICY IF EXISTS "Product prices open" ON product_prices;
DROP POLICY IF EXISTS "product_prices_select_policy" ON product_prices;
CREATE POLICY "product_prices_select_policy" ON product_prices
FOR SELECT USING (
    tier = 'retail'
    OR auth.role() = 'authenticated'
    OR (current_setting('request.jwt.claims', true)::jsonb->>'role') = 'authenticated'
    OR EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role IN ('moderator','manager','cashier','customer'))
);

-- B. Safely drop and recreate view_customer_products with baseline retail and conditional wholesale
DROP VIEW IF EXISTS view_customer_products CASCADE;

CREATE VIEW view_customer_products
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
    GREATEST(0, (COALESCE(sl.total_on_hand, 0) - COALESCE(res.reserved_qty, 0))) AS available_qty,
    ((COALESCE(sl.total_on_hand, 0) - COALESCE(res.reserved_qty, 0)) > 0)          AS in_stock,
    -- Baseline retail price (Always visible to all, including unauthenticated anon visitors)
    COALESCE(
        (SELECT price FROM product_prices WHERE product_id = p.id AND tier = 'retail' ORDER BY min_qty ASC LIMIT 1),
        0
    ) AS retail_price,
    -- Tiered wholesale price: Masked to retail_price for unauthenticated anon visitors;
    -- Real wholesale price visible only for authenticated customers and staff
    CASE
        WHEN (
            auth.role() = 'authenticated'
            OR (current_setting('request.jwt.claims', true)::jsonb->>'role') = 'authenticated'
            OR EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role IN ('moderator','manager','cashier','customer'))
        ) THEN
            COALESCE(
                (SELECT price FROM product_prices WHERE product_id = p.id AND tier = 'wholesale' ORDER BY min_qty ASC LIMIT 1),
                (SELECT price FROM product_prices WHERE product_id = p.id AND tier = 'retail' ORDER BY min_qty ASC LIMIT 1),
                0
            )
        ELSE
            COALESCE(
                (SELECT price FROM product_prices WHERE product_id = p.id AND tier = 'retail' ORDER BY min_qty ASC LIMIT 1),
                0
            )
    END AS wholesale_price
FROM products p
LEFT JOIN (
    SELECT product_id, SUM(qty_change) AS total_on_hand
    FROM stock_ledger GROUP BY product_id
) sl ON p.id = sl.product_id
LEFT JOIN (
    SELECT oi.product_id, SUM(oi.quantity) AS reserved_qty
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.id
    WHERE o.status IN ('confirmed','preparing','ready','assigned','accepted','out_for_delivery')
    GROUP BY oi.product_id
) res ON p.id = res.product_id
WHERE p.active = TRUE;

GRANT SELECT ON view_customer_products TO anon, authenticated;
