-- ============================================================
-- 00005_row_level_security.sql
-- ROLE-BASED ACCESS CONTROL (RLS) POLICIES
-- ============================================================

ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE addresses ENABLE ROW LEVEL SECURITY;
ALTER TABLE suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_barcodes ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_prices ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchases ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE supplier_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE settlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE wallet_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION get_auth_role()
RETURNS user_role
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
    SELECT role FROM users WHERE id = auth.uid();
$$;

-- 1. USERS POLICIES
CREATE POLICY "Users can view their own profile"
ON users FOR SELECT
USING (id = auth.uid() OR get_auth_role() IN ('moderator', 'manager', 'cashier'));

CREATE POLICY "Moderator full control over users"
ON users FOR ALL
USING (get_auth_role() = 'moderator');

-- 2. PRODUCTS & PRICING POLICIES
CREATE POLICY "Customers view active products"
ON products FOR SELECT
USING (active = TRUE OR get_auth_role() IN ('moderator', 'manager', 'cashier', 'driver'));

CREATE POLICY "Staff manage products"
ON products FOR ALL
USING (get_auth_role() IN ('moderator', 'manager'));

CREATE POLICY "Public read product barcodes"
ON product_barcodes FOR SELECT
USING (TRUE);

CREATE POLICY "Public read product prices"
ON product_prices FOR SELECT
USING (TRUE);

-- 3. ORDERS & ORDER ITEMS POLICIES
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

CREATE POLICY "Staff update orders"
ON orders FOR UPDATE
USING (
    get_auth_role() IN ('moderator', 'cashier')
    OR (get_auth_role() = 'driver' AND driver_id = auth.uid())
);

CREATE POLICY "Order items visible to order owner and staff"
ON order_items FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM orders o 
        WHERE o.id = order_items.order_id 
        AND (
            o.customer_id IN (SELECT id FROM customers WHERE user_id = auth.uid())
            OR o.driver_id = auth.uid()
            OR get_auth_role() IN ('moderator', 'manager', 'cashier')
        )
    )
);

-- 4. DRIVER WALLET ENTRIES POLICIES
CREATE POLICY "Drivers view own wallet entries"
ON wallet_entries FOR SELECT
USING (
    driver_id = auth.uid() 
    OR get_auth_role() IN ('moderator', 'cashier')
);

-- 5. CUSTOMER LEDGER POLICIES
CREATE POLICY "Customers view own ledger balance"
ON customer_ledger FOR SELECT
USING (
    customer_id IN (SELECT id FROM customers WHERE user_id = auth.uid())
    OR get_auth_role() IN ('moderator', 'cashier')
);

-- 6. AUDIT LOG POLICIES
CREATE POLICY "Only moderator views audit log"
ON audit_log FOR SELECT
USING (get_auth_role() = 'moderator');
