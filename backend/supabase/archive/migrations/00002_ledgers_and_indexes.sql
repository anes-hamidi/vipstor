-- ============================================================
-- 00002_ledgers_and_indexes.sql
-- APPEND-ONLY LEDGERS, WALLETS, SETTLEMENTS, VIEWS & INDEXES
-- ============================================================

-- ============================================================
-- 1. APPEND-ONLY LEDGERS (SOURCE OF TRUTH)
-- ============================================================

-- Stock Movement Ledger
CREATE TABLE IF NOT EXISTS stock_ledger (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES products(id),
    qty_change INT NOT NULL,                  -- Positive (+ In) or Negative (- Out)
    reason stock_ref_type NOT NULL,
    ref_type VARCHAR(50) NOT NULL,            -- 'purchase', 'order', 'adjustment'
    ref_id UUID NOT NULL,
    user_id UUID NOT NULL REFERENCES users(id),
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Customer Debt Ledger
CREATE TABLE IF NOT EXISTS customer_ledger (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID NOT NULL REFERENCES customers(id),
    amount_change BIGINT NOT NULL,            -- Positive (+ debt owed to shop), Negative (- payment / return)
    ref_type VARCHAR(50) NOT NULL,            -- 'order_credit', 'payment', 'return_refund'
    ref_id UUID NOT NULL,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Supplier Debt Ledger
CREATE TABLE IF NOT EXISTS supplier_ledger (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    supplier_id UUID NOT NULL REFERENCES suppliers(id),
    amount_change BIGINT NOT NULL,            -- Positive (+ shop owes supplier), Negative (- payment to supplier)
    ref_type VARCHAR(50) NOT NULL,            -- 'purchase', 'supplier_payment'
    ref_id UUID NOT NULL,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Payments
CREATE TABLE IF NOT EXISTS payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID REFERENCES orders(id),
    customer_id UUID REFERENCES customers(id),
    amount BIGINT NOT NULL CHECK (amount > 0), -- In centimes
    method payment_method NOT NULL DEFAULT 'cash',
    received_by UUID NOT NULL REFERENCES users(id),
    status payment_status NOT NULL DEFAULT 'collected',
    client_id UUID UNIQUE,                    -- Offline sync idempotency UUID
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- End of Day Settlements
CREATE TABLE IF NOT EXISTS settlements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id UUID NOT NULL REFERENCES users(id),
    cashier_id UUID NOT NULL REFERENCES users(id),
    expected_amount BIGINT NOT NULL,          -- In centimes
    counted_amount BIGINT NOT NULL,           -- In centimes
    difference BIGINT GENERATED ALWAYS AS (counted_amount - expected_amount) STORED,
    status settlement_status NOT NULL DEFAULT 'settled',
    approved_by UUID REFERENCES users(id),
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Driver Delivery Wallet Ledger
CREATE TABLE IF NOT EXISTS wallet_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id UUID NOT NULL REFERENCES users(id),
    type wallet_entry_type NOT NULL,
    amount BIGINT NOT NULL CHECK (amount > 0), -- In centimes (Magnitude)
    payment_id UUID REFERENCES payments(id),
    settlement_id UUID REFERENCES settlements(id),
    client_id UUID UNIQUE,                     -- Offline sync idempotency UUID
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 2. DYNAMIC REAL-TIME BALANCE VIEWS
-- ============================================================

-- Live Product Stock (Accounting for confirmed reservations)
CREATE OR REPLACE VIEW view_product_stock AS
SELECT 
    p.id AS product_id,
    p.name_ar,
    p.name_fr,
    p.active,
    p.unit,
    p.pack_size,
    p.last_unit_cost,
    p.min_stock_alert,
    COALESCE(sl_agg.total_on_hand, 0) AS on_hand_qty,
    COALESCE(res.reserved_qty, 0) AS reserved_qty,
    (COALESCE(sl_agg.total_on_hand, 0) - COALESCE(res.reserved_qty, 0)) AS available_qty
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
) res ON p.id = res.product_id;

-- Live Driver Wallet Balance
CREATE OR REPLACE VIEW view_driver_wallet_balance AS
SELECT 
    driver_id,
    COALESCE(SUM(
        CASE 
            WHEN type = 'collection' THEN amount
            WHEN type = 'handover' THEN -amount
            WHEN type = 'overage' THEN amount
            WHEN type = 'shortage' THEN -amount
            ELSE 0
        END
    ), 0) AS current_wallet_balance
FROM wallet_entries
GROUP BY driver_id;

-- Live Customer Debt Statement
CREATE OR REPLACE VIEW view_customer_balance AS
SELECT 
    c.id AS customer_id,
    c.user_id,
    u.name AS customer_name,
    u.phone AS customer_phone,
    c.credit_limit,
    COALESCE(SUM(cl.amount_change), 0) AS current_balance
FROM customers c
JOIN users u ON c.user_id = u.id
LEFT JOIN customer_ledger cl ON c.id = cl.customer_id
GROUP BY c.id, c.user_id, u.name, u.phone, c.credit_limit;

-- Live Supplier Balance (Total Shop Debt to Supplier)
CREATE OR REPLACE VIEW view_supplier_balance AS
SELECT 
    s.id AS supplier_id,
    s.name AS supplier_name,
    s.phone AS supplier_phone,
    COALESCE(SUM(sl.amount_change), 0) AS current_balance
FROM suppliers s
LEFT JOIN supplier_ledger sl ON s.id = sl.supplier_id
GROUP BY s.id;

-- ============================================================
-- 3. PERFORMANCE INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_stock_ledger_product ON stock_ledger(product_id);
CREATE INDEX IF NOT EXISTS idx_stock_ledger_created ON stock_ledger(created_at);
CREATE INDEX IF NOT EXISTS idx_customer_ledger_customer ON customer_ledger(customer_id);
CREATE INDEX IF NOT EXISTS idx_supplier_ledger_supplier ON supplier_ledger(supplier_id);
CREATE INDEX IF NOT EXISTS idx_wallet_entries_driver ON wallet_entries(driver_id);
CREATE INDEX IF NOT EXISTS idx_orders_customer ON orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_orders_driver ON orders(driver_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
CREATE INDEX IF NOT EXISTS idx_product_barcodes_barcode ON product_barcodes(barcode);
CREATE INDEX IF NOT EXISTS idx_product_prices_lookup ON product_prices(product_id, tier, min_qty);
