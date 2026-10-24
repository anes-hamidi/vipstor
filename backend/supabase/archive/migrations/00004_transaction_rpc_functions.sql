-- ============================================================
-- 00004_transaction_rpc_functions.sql
-- ATOMIC BUSINESS LOGIC & LEDGER POSTING TRANSACTIONS
-- ============================================================

-- 1. POST PURCHASE (Manager received supplier shipment)
CREATE OR REPLACE FUNCTION rpc_post_purchase(p_purchase_id UUID, p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_purchase purchases%ROWTYPE;
    v_item RECORD;
    v_total_amount BIGINT := 0;
BEGIN
    SELECT * INTO v_purchase FROM purchases WHERE id = p_purchase_id FOR UPDATE;
    IF NOT FOUND THEN 
        RAISE EXCEPTION 'Purchase % not found', p_purchase_id; 
    END IF;
    
    IF v_purchase.status <> 'draft' THEN 
        RAISE EXCEPTION 'Purchase is not in draft status (current: %)', v_purchase.status; 
    END IF;

    FOR v_item IN (SELECT * FROM purchase_items WHERE purchase_id = p_purchase_id) LOOP
        v_total_amount := v_total_amount + (v_item.quantity * v_item.unit_cost);

        INSERT INTO stock_ledger (product_id, qty_change, reason, ref_type, ref_id, user_id, notes)
        VALUES (v_item.product_id, v_item.quantity, 'purchase', 'purchase', p_purchase_id, p_user_id, 'Purchase received: Invoice ' || v_purchase.invoice_no);

        UPDATE products 
        SET last_unit_cost = v_item.unit_cost,
            active = TRUE,
            updated_at = NOW()
        WHERE id = v_item.product_id;
    END LOOP;

    INSERT INTO supplier_ledger (supplier_id, amount_change, ref_type, ref_id, notes)
    VALUES (v_purchase.supplier_id, v_total_amount, 'purchase', p_purchase_id, 'Invoice ' || v_purchase.invoice_no);

    UPDATE purchases 
    SET status = 'posted', 
        total_amount = v_total_amount, 
        posted_at = NOW() 
    WHERE id = p_purchase_id;

    RETURN jsonb_build_object(
        'status', 'success', 
        'purchase_id', p_purchase_id, 
        'total_amount', v_total_amount
    );
END;
$$;

-- 2. POST IN-STORE SALE (Cashier counter sale)
CREATE OR REPLACE FUNCTION rpc_post_store_sale(
    p_cashier_id UUID,
    p_customer_id UUID,          -- NULL if walk-in anonymous buyer
    p_items JSONB,               -- Array of {product_id: UUID, quantity: INT, unit_price: BIGINT, unit_cost: BIGINT}
    p_paid_cash BIGINT,          -- In centimes
    p_on_account BIGINT          -- In centimes
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_order_id UUID := gen_random_uuid();
    v_item JSONB;
    v_total_amount BIGINT := 0;
    v_total_cost BIGINT := 0;
    v_current_stock INT;
    v_product_id UUID;
    v_qty INT;
    v_price BIGINT;
    v_cost BIGINT;
    v_customer_limit BIGINT;
    v_current_debt BIGINT;
BEGIN
    IF p_on_account > 0 THEN
        IF p_customer_id IS NULL THEN
            RAISE EXCEPTION 'Cannot put amount on balance without a registered customer account.';
        END IF;

        SELECT credit_limit, COALESCE(current_balance, 0)
        INTO v_customer_limit, v_current_debt
        FROM view_customer_balance 
        WHERE customer_id = p_customer_id;

        IF (v_current_debt + p_on_account) > v_customer_limit THEN
            RAISE EXCEPTION 'Sale exceeds customer credit limit! Limit: %, Current Debt: %, Requested: %', 
                v_customer_limit, v_current_debt, p_on_account;
        END IF;
    END IF;

    INSERT INTO orders (id, channel, customer_id, status, cashier_id, total_amount, paid_amount)
    VALUES (v_order_id, 'store', p_customer_id, 'delivered', p_cashier_id, 0, p_paid_cash);

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        v_product_id := (v_item->>'product_id')::UUID;
        v_qty := (v_item->>'quantity')::INT;
        v_price := (v_item->>'unit_price')::BIGINT;
        v_cost := COALESCE((v_item->>'unit_cost')::BIGINT, 0);

        SELECT available_qty INTO v_current_stock 
        FROM view_product_stock 
        WHERE product_id = v_product_id;

        IF v_current_stock < v_qty THEN
            RAISE EXCEPTION 'Insufficient stock for product %: requested %, available %', 
                v_product_id, v_qty, v_current_stock;
        END IF;

        v_total_amount := v_total_amount + (v_qty * v_price);
        v_total_cost := v_total_cost + (v_qty * v_cost);

        INSERT INTO order_items (order_id, product_id, quantity, unit_price, unit_cost)
        VALUES (v_order_id, v_product_id, v_qty, v_price, v_cost);

        INSERT INTO stock_ledger (product_id, qty_change, reason, ref_type, ref_id, user_id, notes)
        VALUES (v_product_id, -v_qty, 'sale', 'order', v_order_id, p_cashier_id, 'Counter Sale');
    END LOOP;

    UPDATE orders 
    SET total_amount = v_total_amount, 
        total_cost = v_total_cost, 
        delivered_at = NOW()
    WHERE id = v_order_id;

    IF p_on_account > 0 THEN
        INSERT INTO customer_ledger (customer_id, amount_change, ref_type, ref_id, notes)
        VALUES (p_customer_id, p_on_account, 'order_credit', v_order_id, 'Counter sale credit');
    END IF;

    IF p_paid_cash > 0 THEN
        INSERT INTO payments (order_id, customer_id, amount, method, received_by, status)
        VALUES (v_order_id, p_customer_id, p_paid_cash, 'cash', p_cashier_id, 'settled');
    END IF;

    RETURN jsonb_build_object(
        'status', 'success', 
        'order_id', v_order_id, 
        'total_amount', v_total_amount, 
        'paid_cash', p_paid_cash, 
        'on_account', p_on_account
    );
END;
$$;

-- 3. CONFIRM ONLINE ORDER (Reserves inventory)
CREATE OR REPLACE FUNCTION rpc_confirm_online_order(
    p_order_id UUID,
    p_cashier_id UUID,
    p_driver_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_order orders%ROWTYPE;
    v_item RECORD;
    v_avail INT;
BEGIN
    SELECT * INTO v_order FROM orders WHERE id = p_order_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Order % not found', p_order_id; END IF;
    IF v_order.status <> 'submitted' THEN RAISE EXCEPTION 'Order is not in submitted status'; END IF;

    FOR v_item IN (SELECT * FROM order_items WHERE order_id = p_order_id) LOOP
        SELECT available_qty INTO v_avail FROM view_product_stock WHERE product_id = v_item.product_id;
        IF v_avail < v_item.quantity THEN
            RAISE EXCEPTION 'Cannot confirm order: Insufficient stock for product % (Requested: %, Available: %)',
                v_item.product_id, v_item.quantity, v_avail;
        END IF;
    END LOOP;

    UPDATE orders 
    SET status = CASE WHEN p_driver_id IS NOT NULL THEN 'assigned'::order_status ELSE 'confirmed'::order_status END,
        cashier_id = p_cashier_id,
        driver_id = COALESCE(p_driver_id, driver_id),
        confirmed_at = NOW()
    WHERE id = p_order_id;

    RETURN jsonb_build_object('status', 'success', 'order_id', p_order_id, 'assigned_driver', p_driver_id);
END;
$$;

-- 4. RECORD ORDER DELIVERY (Driver collected payment, idempotent)
CREATE OR REPLACE FUNCTION rpc_record_order_delivery(
    p_driver_id UUID,
    p_order_id UUID,
    p_collected_cash BIGINT,
    p_client_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_order orders%ROWTYPE;
    v_unpaid_amount BIGINT;
    v_payment_id UUID;
BEGIN
    SELECT * INTO v_order FROM orders WHERE id = p_order_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Order % not found', p_order_id; END IF;

    IF v_order.status IN ('delivered', 'settled') THEN
        RETURN jsonb_build_object('status', 'already_delivered', 'order_id', p_order_id);
    END IF;

    v_unpaid_amount := v_order.total_amount - p_collected_cash;

    IF p_collected_cash > 0 THEN
        INSERT INTO payments (id, order_id, customer_id, amount, method, received_by, status, client_id)
        VALUES (gen_random_uuid(), p_order_id, v_order.customer_id, p_collected_cash, 'cash', p_driver_id, 'collected', p_client_id)
        ON CONFLICT (client_id) DO UPDATE SET amount = EXCLUDED.amount
        RETURNING id INTO v_payment_id;

        INSERT INTO wallet_entries (driver_id, type, amount, payment_id, client_id)
        VALUES (p_driver_id, 'collection', p_collected_cash, v_payment_id, p_client_id)
        ON CONFLICT (client_id) DO NOTHING;
    END IF;

    IF v_unpaid_amount > 0 AND v_order.customer_id IS NOT NULL THEN
        INSERT INTO customer_ledger (customer_id, amount_change, ref_type, ref_id, notes)
        VALUES (v_order.customer_id, v_unpaid_amount, 'order_credit', p_order_id, 'Delivery remaining unpaid balance');
    END IF;

    INSERT INTO stock_ledger (product_id, qty_change, reason, ref_type, ref_id, user_id, notes)
    SELECT oi.product_id, -oi.quantity, 'sale', 'order', p_order_id, p_driver_id, 'Delivery Completed'
    FROM order_items oi
    WHERE oi.order_id = p_order_id;

    UPDATE orders 
    SET status = 'delivered', 
        paid_amount = p_collected_cash, 
        delivered_at = NOW()
    WHERE id = p_order_id;

    RETURN jsonb_build_object('status', 'success', 'order_id', p_order_id, 'collected', p_collected_cash);
END;
$$;

-- 5. END-OF-DAY DRIVER WALLET SETTLEMENT
CREATE OR REPLACE FUNCTION rpc_settle_driver_wallet(
    p_cashier_id UUID,
    p_driver_id UUID,
    p_counted_cash BIGINT,
    p_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_expected_cash BIGINT := 0;
    v_difference BIGINT := 0;
    v_settlement_id UUID := gen_random_uuid();
    v_status settlement_status := 'settled';
BEGIN
    SELECT current_wallet_balance INTO v_expected_cash
    FROM view_driver_wallet_balance
    WHERE driver_id = p_driver_id;

    v_expected_cash := COALESCE(v_expected_cash, 0);

    IF v_expected_cash <= 0 AND p_counted_cash = 0 THEN
        RAISE EXCEPTION 'No pending collections to settle for driver %', p_driver_id;
    END IF;

    v_difference := p_counted_cash - v_expected_cash;
    IF v_difference <> 0 THEN
        v_status := 'discrepancy_flagged';
    END IF;

    INSERT INTO settlements (id, driver_id, cashier_id, expected_amount, counted_amount, status, notes)
    VALUES (v_settlement_id, p_driver_id, p_cashier_id, v_expected_cash, p_counted_cash, v_status, p_notes);

    INSERT INTO wallet_entries (driver_id, type, amount, settlement_id)
    VALUES (p_driver_id, 'handover', v_expected_cash, v_settlement_id);

    UPDATE orders 
    SET status = 'settled', 
        settled_at = NOW()
    WHERE driver_id = p_driver_id AND status = 'delivered';

    UPDATE payments 
    SET status = 'settled'
    WHERE received_by = p_driver_id AND status = 'collected';

    RETURN jsonb_build_object(
        'status', 'success',
        'settlement_id', v_settlement_id,
        'expected', v_expected_cash,
        'counted', p_counted_cash,
        'difference', v_difference,
        'settlement_status', v_status
    );
END;
$$;

-- 6. STOCK ADJUSTMENT
CREATE OR REPLACE FUNCTION rpc_adjust_stock(
    p_user_id UUID,
    p_product_id UUID,
    p_qty_change INT,
    p_reason TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_adjustment_id UUID := gen_random_uuid();
BEGIN
    IF p_qty_change = 0 THEN
        RAISE EXCEPTION 'Quantity change cannot be zero';
    END IF;

    INSERT INTO stock_ledger (id, product_id, qty_change, reason, ref_type, ref_id, user_id, notes)
    VALUES (v_adjustment_id, p_product_id, p_qty_change, 'adjustment', 'manual_adjustment', v_adjustment_id, p_user_id, p_reason);

    RETURN jsonb_build_object('status', 'success', 'adjustment_id', v_adjustment_id, 'qty_change', p_qty_change);
END;
$$;
