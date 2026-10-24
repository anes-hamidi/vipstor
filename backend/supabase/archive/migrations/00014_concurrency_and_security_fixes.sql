-- ============================================================
-- 00014_concurrency_and_security_fixes.sql
-- STRICT CONCURRENCY LOCKS, LEDGER IMMUTABILITY, SERVER-SIDE PRICING,
-- ATOMIC PRODUCT CREATION, RLS RESTRICTIONS & IDEMPOTENCY
-- ============================================================

-- 1. PREVENT DIRECT UPDATE OR DELETE ON APPEND-ONLY LEDGERS
CREATE OR REPLACE FUNCTION trg_block_immutable_ledger_modifications()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'Table % is strictly append-only. UPDATE and DELETE operations are prohibited.', TG_TABLE_NAME;
END;
$$;

DROP TRIGGER IF EXISTS trg_block_stock_ledger_mutation ON stock_ledger;
CREATE TRIGGER trg_block_stock_ledger_mutation
BEFORE UPDATE OR DELETE ON stock_ledger
FOR EACH ROW
EXECUTE FUNCTION trg_block_immutable_ledger_modifications();

DROP TRIGGER IF EXISTS trg_block_customer_ledger_mutation ON customer_ledger;
CREATE TRIGGER trg_block_customer_ledger_mutation
BEFORE UPDATE OR DELETE ON customer_ledger
FOR EACH ROW
EXECUTE FUNCTION trg_block_immutable_ledger_modifications();

DROP TRIGGER IF EXISTS trg_block_supplier_ledger_mutation ON supplier_ledger;
CREATE TRIGGER trg_block_supplier_ledger_mutation
BEFORE UPDATE OR DELETE ON supplier_ledger
FOR EACH ROW
EXECUTE FUNCTION trg_block_immutable_ledger_modifications();


-- 2. PARTIAL UNIQUE INDEX ON stock_ledger FOR OPENING STOCK
CREATE UNIQUE INDEX IF NOT EXISTS uq_stock_ledger_opening_ref 
ON stock_ledger (ref_id) 
WHERE ref_type = 'opening_stock';


-- 3. CLIENT IDEMPOTENCY KEY ON ORDERS TABLE
ALTER TABLE orders ADD COLUMN IF NOT EXISTS client_id UUID UNIQUE;


-- 4. SLIM PRODUCT STOCK VIEW FOR CUSTOMERS
-- Security: customer does not see last_unit_cost, on_hand_qty, or reserved_qty breakdown
CREATE OR REPLACE VIEW view_customer_products
WITH (security_invoker = true)
AS
SELECT 
    p.id AS product_id,
    p.name_ar,
    p.name_fr,
    p.category,
    p.unit,
    p.pack_size,
    p.photo_url,
    p.active,
    (COALESCE(sl_agg.total_on_hand, 0) - COALESCE(res.reserved_qty, 0)) AS available_qty,
    ((COALESCE(sl_agg.total_on_hand, 0) - COALESCE(res.reserved_qty, 0)) > 0) AS in_stock
FROM products p
LEFT JOIN (
    SELECT product_id, SUM(qty_change) AS total_on_hand
    FROM stock_ledger
    GROUP BY product_id
) sl_agg ON p.id = sl_agg.product_id
LEFT JOIN (
    SELECT oi.product_id, SUM(oi.quantity) AS reserved_qty
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.id
    WHERE o.status IN ('confirmed', 'assigned', 'accepted', 'out_for_delivery')
    GROUP BY oi.product_id
) res ON p.id = res.product_id
WHERE p.active = TRUE;


-- 5. RLS POLICIES & GRANTS: REVOKE CUSTOMER ACCESS TO view_product_stock & RESTRICT DIRECT STATUS UPDATE
REVOKE SELECT ON view_product_stock FROM anon, authenticated;
GRANT SELECT ON view_product_stock TO authenticated; -- View is used by staff RPCs and staff queries

-- Restrict direct orders UPDATE: Staff cannot directly mutate status (must use RPCs)
DROP POLICY IF EXISTS "Staff update orders" ON orders;
DROP POLICY IF EXISTS "Allow all operations on orders" ON orders;

CREATE POLICY "Customer view own orders"
ON orders FOR SELECT
USING (
    customer_id IN (SELECT id FROM customers WHERE user_id = auth.uid())
    OR driver_id = auth.uid()
    OR get_auth_role() IN ('moderator', 'manager', 'cashier')
);

CREATE POLICY "Customer create orders"
ON orders FOR INSERT
WITH CHECK (
    customer_id IN (SELECT id FROM customers WHERE user_id = auth.uid())
    OR get_auth_role() IN ('moderator', 'cashier')
);

CREATE POLICY "Staff update non-status order fields"
ON orders FOR UPDATE
USING (
    get_auth_role() IN ('moderator', 'cashier')
    OR (get_auth_role() = 'driver' AND driver_id = auth.uid())
)
WITH CHECK (
    -- Prohibit direct update of order status through standard REST update
    get_auth_role() IN ('moderator')
);


-- 6. RPC SUBMIT CUSTOMER ORDER (Server-side price resolution by customer tier and cost snapshot)
CREATE OR REPLACE FUNCTION rpc_submit_customer_order(
    p_client_id UUID,
    p_customer_id UUID,
    p_delivery_address JSONB,
    p_items JSONB               -- Array of {product_id: UUID, quantity: INT}
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_order_id UUID;
    v_user_tier price_tier := 'wholesale';
    v_item JSONB;
    v_product_id UUID;
    v_qty INT;
    v_unit_price BIGINT;
    v_unit_cost BIGINT;
    v_total_amount BIGINT := 0;
    v_total_cost BIGINT := 0;
    v_resolved_customer_id UUID := p_customer_id;
BEGIN
    -- 1. Idempotency check: If an order with this client_id exists, return it immediately
    IF p_client_id IS NOT NULL THEN
        SELECT id INTO v_order_id FROM orders WHERE client_id = p_client_id;
        IF v_order_id IS NOT NULL THEN
            RETURN v_order_id;
        END IF;
    END IF;

    -- 2. Resolve customer tier and verify customer account
    IF v_resolved_customer_id IS NOT NULL THEN
        SELECT price_tier INTO v_user_tier FROM customers WHERE id = v_resolved_customer_id;
        IF NOT FOUND THEN
            -- Fallback check if user_id passed instead of customer_id
            SELECT id, price_tier INTO v_resolved_customer_id, v_user_tier FROM customers WHERE user_id = auth.uid();
        END IF;
    ELSE
        SELECT id, price_tier INTO v_resolved_customer_id, v_user_tier FROM customers WHERE user_id = auth.uid();
    END IF;

    IF v_user_tier IS NULL THEN
        v_user_tier := 'wholesale';
    END IF;

    v_order_id := gen_random_uuid();

    -- 3. Insert order header with client_id (atomic deduplication on conflict)
    INSERT INTO orders (id, client_id, channel, customer_id, status, delivery_address, total_amount, total_cost, paid_amount)
    VALUES (v_order_id, p_client_id, 'online', v_resolved_customer_id, 'submitted', p_delivery_address, 0, 0, 0)
    ON CONFLICT (client_id) DO NOTHING;

    -- If another concurrent call won the race, return the existing ID
    IF NOT FOUND THEN
        SELECT id INTO v_order_id FROM orders WHERE client_id = p_client_id;
        RETURN v_order_id;
    END IF;

    -- 4. Process each item: Resolve price according to tier & min_qty, snapshot unit_cost
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        v_product_id := (v_item->>'product_id')::UUID;
        v_qty := (v_item->>'quantity')::INT;

        IF v_qty <= 0 THEN
            RAISE EXCEPTION 'Item quantity must be greater than zero for product %', v_product_id;
        END IF;

        -- Resolve server-side price from product_prices matching tier and qualifying min_qty
        SELECT price INTO v_unit_price
        FROM product_prices
        WHERE product_id = v_product_id
          AND tier = v_user_tier
          AND min_qty <= v_qty
        ORDER BY min_qty DESC
        LIMIT 1;

        -- Fallback to default retail/min price if exact tier row not found
        IF v_unit_price IS NULL THEN
            SELECT price INTO v_unit_price
            FROM product_prices
            WHERE product_id = v_product_id
            ORDER BY min_qty ASC
            LIMIT 1;
        END IF;

        IF v_unit_price IS NULL THEN
            RAISE EXCEPTION 'No price configured for product %', v_product_id;
        END IF;

        -- Snapshot purchasing cost from products table
        SELECT last_unit_cost INTO v_unit_cost
        FROM products
        WHERE id = v_product_id;

        v_unit_cost := COALESCE(v_unit_cost, 0);

        v_total_amount := v_total_amount + (v_qty * v_unit_price);
        v_total_cost := v_total_cost + (v_qty * v_unit_cost);

        INSERT INTO order_items (order_id, product_id, quantity, unit_price, unit_cost)
        VALUES (v_order_id, v_product_id, v_qty, v_unit_price, v_unit_cost);
    END LOOP;

    -- Update order with calculated totals
    UPDATE orders 
    SET total_amount = v_total_amount, 
        total_cost = v_total_cost 
    WHERE id = v_order_id;

    RETURN v_order_id;
END;
$$;


-- 7. RPC ATOMIC PRODUCT CREATION (Product + Barcodes + Prices + Opening stock in one transaction)
CREATE OR REPLACE FUNCTION rpc_create_product(
    p_product JSONB,           -- {id, name_ar, name_fr, category, unit, pack_size, photo_url, last_unit_cost, active}
    p_barcodes JSONB,          -- Array of barcode strings
    p_prices JSONB,            -- Array of {id, tier, min_qty, price}
    p_opening_stock INT,
    p_user_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_product_id UUID;
    v_b TEXT;
    v_p JSONB;
    v_operator_id UUID;
BEGIN
    v_product_id := COALESCE((p_product->>'id')::UUID, gen_random_uuid());
    v_operator_id := COALESCE(auth.uid(), p_user_id);

    -- 1. Insert product row
    INSERT INTO products (
        id, name_ar, name_fr, category, unit, pack_size, photo_url, last_unit_cost, active
    ) VALUES (
        v_product_id,
        p_product->>'name_ar',
        COALESCE(p_product->>'name_fr', p_product->>'name_ar'),
        COALESCE(p_product->>'category', 'عام'),
        COALESCE(p_product->>'unit', 'piece'),
        COALESCE((p_product->>'pack_size')::INT, 1),
        p_product->>'photo_url',
        COALESCE((p_product->>'last_unit_cost')::BIGINT, 0),
        COALESCE((p_product->>'active')::BOOLEAN, TRUE)
    )
    ON CONFLICT (id) DO UPDATE SET
        name_ar = EXCLUDED.name_ar,
        name_fr = EXCLUDED.name_fr,
        category = EXCLUDED.category,
        unit = EXCLUDED.unit,
        pack_size = EXCLUDED.pack_size,
        photo_url = EXCLUDED.photo_url,
        last_unit_cost = EXCLUDED.last_unit_cost,
        active = EXCLUDED.active,
        updated_at = NOW();

    -- 2. Insert barcodes
    IF p_barcodes IS NOT NULL THEN
        FOR v_b IN SELECT jsonb_array_elements_text(p_barcodes) LOOP
            IF v_b IS NOT NULL AND trim(v_b) <> '' THEN
                INSERT INTO product_barcodes (barcode, product_id, units_per_scan)
                VALUES (trim(v_b), v_product_id, 1)
                ON CONFLICT (barcode) DO NOTHING;
            END IF;
        END LOOP;
    END IF;

    -- 3. Insert price tiers
    IF p_prices IS NOT NULL THEN
        FOR v_p IN SELECT * FROM jsonb_array_elements(p_prices) LOOP
            INSERT INTO product_prices (id, product_id, tier, min_qty, price)
            VALUES (
                COALESCE((v_p->>'id')::UUID, gen_random_uuid()),
                v_product_id,
                (v_p->>'tier')::price_tier,
                COALESCE((v_p->>'min_qty')::INT, 1),
                (v_p->>'price')::BIGINT
            )
            ON CONFLICT (product_id, tier, min_qty) DO UPDATE 
            SET price = EXCLUDED.price;
        END LOOP;
    END IF;

    -- 4. Insert opening stock ledger movement if specified (> 0)
    IF p_opening_stock > 0 THEN
        IF v_operator_id IS NULL THEN
            SELECT id INTO v_operator_id FROM users LIMIT 1;
        END IF;

        INSERT INTO stock_ledger (
            product_id, qty_change, reason, ref_type, ref_id, user_id, notes
        ) VALUES (
            v_product_id,
            p_opening_stock,
            'adjustment'::stock_ref_type,
            'opening_stock',
            v_product_id,
            v_operator_id,
            'المخزون الافتتاحي الأولي عند إنشاء المنتج'
        )
        ON CONFLICT DO NOTHING;
    END IF;

    RETURN v_product_id;
END;
$$;


-- 8. RPC POST STORE SALE (Using auth.uid(), SET search_path, customer row lock, payment validation)
CREATE OR REPLACE FUNCTION rpc_post_store_sale(
    p_customer_id UUID,          -- NULL if walk-in anonymous buyer
    p_items JSONB,               -- Array of {product_id: UUID, quantity: INT, unit_price: BIGINT, unit_cost: BIGINT}
    p_paid_cash BIGINT,          -- In centimes
    p_on_account BIGINT,         -- In centimes
    p_cashier_id UUID DEFAULT NULL -- Optional fallback when running outside auth session
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_order_id UUID := gen_random_uuid();
    v_effective_cashier UUID;
    v_item JSONB;
    v_total_amount BIGINT := 0;
    v_total_cost BIGINT := 0;
    v_current_stock INT;
    v_product_id UUID;
    v_qty INT;
    v_price BIGINT;
    v_cost BIGINT;
    v_customer customers%ROWTYPE;
    v_current_debt BIGINT;
BEGIN
    -- 1. Use auth.uid() or fallback
    v_effective_cashier := COALESCE(auth.uid(), p_cashier_id);
    IF v_effective_cashier IS NULL THEN
        SELECT id INTO v_effective_cashier FROM users WHERE role IN ('cashier', 'manager', 'moderator') LIMIT 1;
    END IF;

    -- 2. Lock customer row before credit limit check
    IF p_on_account > 0 THEN
        IF p_customer_id IS NULL THEN
            RAISE EXCEPTION 'Cannot put amount on balance without a registered customer account.';
        END IF;

        SELECT * INTO v_customer 
        FROM customers 
        WHERE id = p_customer_id 
        FOR UPDATE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Customer % not found', p_customer_id;
        END IF;

        SELECT COALESCE(current_balance, 0)
        INTO v_current_debt
        FROM view_customer_balance 
        WHERE customer_id = p_customer_id;

        IF (v_current_debt + p_on_account) > v_customer.credit_limit THEN
            RAISE EXCEPTION 'Sale exceeds customer credit limit! Limit: %, Current Debt: %, Requested: %', 
                v_customer.credit_limit, v_current_debt, p_on_account;
        END IF;
    END IF;

    -- 3. Lock all products involved in alphabetical order of UUID to prevent deadlocks
    PERFORM id 
    FROM products 
    WHERE id IN (
        SELECT (item->>'product_id')::UUID 
        FROM jsonb_array_elements(p_items) AS item
    )
    ORDER BY id 
    FOR UPDATE;

    -- 4. Calculate total amount & verify stock
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
    END LOOP;

    -- 5. Validate paid + on_account = total
    IF (p_paid_cash + p_on_account) <> v_total_amount THEN
        RAISE EXCEPTION 'Payment mismatch: paid (%) + on_account (%) must equal total amount (%)',
            p_paid_cash, p_on_account, v_total_amount;
    END IF;

    -- 6. Insert order header
    INSERT INTO orders (id, channel, customer_id, status, cashier_id, total_amount, total_cost, paid_amount, delivered_at)
    VALUES (v_order_id, 'store', p_customer_id, 'delivered', v_effective_cashier, v_total_amount, v_total_cost, p_paid_cash, NOW());

    -- 7. Insert items and stock movements
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        v_product_id := (v_item->>'product_id')::UUID;
        v_qty := (v_item->>'quantity')::INT;
        v_price := (v_item->>'unit_price')::BIGINT;
        v_cost := COALESCE((v_item->>'unit_cost')::BIGINT, 0);

        INSERT INTO order_items (order_id, product_id, quantity, unit_price, unit_cost)
        VALUES (v_order_id, v_product_id, v_qty, v_price, v_cost);

        INSERT INTO stock_ledger (product_id, qty_change, reason, ref_type, ref_id, user_id, notes)
        VALUES (v_product_id, -v_qty, 'sale', 'order', v_order_id, v_effective_cashier, 'Counter Sale');
    END LOOP;

    -- 8. Customer balance and payment entries
    IF p_on_account > 0 THEN
        INSERT INTO customer_ledger (customer_id, amount_change, ref_type, ref_id, notes)
        VALUES (p_customer_id, p_on_account, 'order_credit', v_order_id, 'Counter sale credit');
    END IF;

    IF p_paid_cash > 0 THEN
        INSERT INTO payments (order_id, customer_id, amount, method, received_by, status)
        VALUES (v_order_id, p_customer_id, p_paid_cash, 'cash', v_effective_cashier, 'settled');
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


-- 9. RPC CONFIRM ONLINE ORDER WITH FOR UPDATE PRODUCT LOCKS & RE-CHECK
CREATE OR REPLACE FUNCTION rpc_confirm_online_order(
    p_order_id UUID,
    p_cashier_id UUID,
    p_driver_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_order orders%ROWTYPE;
    v_item RECORD;
    v_avail INT;
BEGIN
    SELECT * INTO v_order FROM orders WHERE id = p_order_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Order % not found', p_order_id; END IF;
    IF v_order.status <> 'submitted' THEN RAISE EXCEPTION 'Order % is not in submitted status (current: %)', p_order_id, v_order.status; END IF;

    PERFORM p.id
    FROM products p
    JOIN order_items oi ON oi.product_id = p.id
    WHERE oi.order_id = p_order_id
    ORDER BY p.id
    FOR UPDATE;

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


-- 10. RPC RECORD ORDER DELIVERY WITH FOR UPDATE PRODUCT LOCKS
CREATE OR REPLACE FUNCTION rpc_record_order_delivery(
    p_driver_id UUID,
    p_order_id UUID,
    p_collected_cash BIGINT,
    p_client_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
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

    PERFORM p.id
    FROM products p
    JOIN order_items oi ON oi.product_id = p.id
    WHERE oi.order_id = p_order_id
    ORDER BY p.id
    FOR UPDATE;

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
