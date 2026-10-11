-- ============================================================
-- clean_start.sql
-- RESET DATABASE TO CLEAN PRODUCTION STATE (IDEMPOTENT)
-- (Deletes all test/seed data, fixes RLS and preserves only the Admin Moderator)
-- ============================================================

-- 1. Truncate all transactional, ledger, and entity tables
TRUNCATE TABLE 
  payments,
  wallet_entries,
  settlements,
  order_items,
  orders,
  purchase_items,
  purchases,
  stock_ledger,
  customer_ledger,
  supplier_ledger,
  product_barcodes,
  product_prices,
  products,
  addresses,
  customers,
  suppliers,
  audit_log,
  users
CASCADE;

-- 2. Insert ONLY the initial Master Admin Moderator account
INSERT INTO users (id, phone, name, role, active, language)
VALUES (
  '11111111-1111-1111-1111-111111111111',
  '+213550000001',
  'Admin Moderator',
  'moderator',
  TRUE,
  'ar'
)
ON CONFLICT (phone) DO UPDATE 
SET role = 'moderator', name = 'Admin Moderator', active = TRUE;

-- 3. Atomic RPC function to create staff members with SECURITY DEFINER
CREATE OR REPLACE FUNCTION rpc_create_staff_member(
    p_name VARCHAR,
    p_phone VARCHAR,
    p_role user_role,
    p_language VARCHAR DEFAULT 'ar'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID := gen_random_uuid();
BEGIN
    INSERT INTO users (id, name, phone, role, language, active)
    VALUES (v_user_id, p_name, p_phone, p_role, p_language, TRUE);

    RETURN jsonb_build_object(
        'status', 'success',
        'id', v_user_id,
        'name', p_name,
        'phone', p_phone,
        'role', p_role
    );
END;
$$;

-- 4. Set Permissive RLS Policies for App Functionality with Anon Key
DROP POLICY IF EXISTS "Users can view their own profile" ON users;
DROP POLICY IF EXISTS "Moderator full control over users" ON users;
DROP POLICY IF EXISTS "Allow anon read active users for phone login" ON users;
DROP POLICY IF EXISTS "Allow staff insert" ON users;
DROP POLICY IF EXISTS "Allow all operations on users for app functionality" ON users;
CREATE POLICY "Allow all operations on users for app functionality"
ON users FOR ALL USING (TRUE) WITH CHECK (TRUE);

DROP POLICY IF EXISTS "Suppliers policy" ON suppliers;
DROP POLICY IF EXISTS "Allow all operations on suppliers" ON suppliers;
CREATE POLICY "Allow all operations on suppliers"
ON suppliers FOR ALL USING (TRUE) WITH CHECK (TRUE);

DROP POLICY IF EXISTS "Customers policy" ON customers;
DROP POLICY IF EXISTS "Allow all operations on customers" ON customers;
CREATE POLICY "Allow all operations on customers"
ON customers FOR ALL USING (TRUE) WITH CHECK (TRUE);

DROP POLICY IF EXISTS "Addresses policy" ON addresses;
DROP POLICY IF EXISTS "Allow all operations on addresses" ON addresses;
CREATE POLICY "Allow all operations on addresses"
ON addresses FOR ALL USING (TRUE) WITH CHECK (TRUE);

DROP POLICY IF EXISTS "Customer view own orders" ON orders;
DROP POLICY IF EXISTS "Customer create orders" ON orders;
DROP POLICY IF EXISTS "Staff update orders" ON orders;
DROP POLICY IF EXISTS "Allow all operations on orders" ON orders;
CREATE POLICY "Allow all operations on orders"
ON orders FOR ALL USING (TRUE) WITH CHECK (TRUE);

DROP POLICY IF EXISTS "Order items visible to order owner and staff" ON order_items;
DROP POLICY IF EXISTS "Allow all operations on order_items" ON order_items;
CREATE POLICY "Allow all operations on order_items"
ON order_items FOR ALL USING (TRUE) WITH CHECK (TRUE);

DROP POLICY IF EXISTS "Customers view active products" ON products;
DROP POLICY IF EXISTS "Staff manage products" ON products;
DROP POLICY IF EXISTS "Allow all operations on products" ON products;
CREATE POLICY "Allow all operations on products"
ON products FOR ALL USING (TRUE) WITH CHECK (TRUE);

DROP POLICY IF EXISTS "Public read product barcodes" ON product_barcodes;
DROP POLICY IF EXISTS "Allow all operations on product_barcodes" ON product_barcodes;
CREATE POLICY "Allow all operations on product_barcodes"
ON product_barcodes FOR ALL USING (TRUE) WITH CHECK (TRUE);

DROP POLICY IF EXISTS "Public read product prices" ON product_prices;
DROP POLICY IF EXISTS "Allow all operations on product_prices" ON product_prices;
CREATE POLICY "Allow all operations on product_prices"
ON product_prices FOR ALL USING (TRUE) WITH CHECK (TRUE);

DROP POLICY IF EXISTS "Allow all operations on stock_ledger" ON stock_ledger;
CREATE POLICY "Allow all operations on stock_ledger"
ON stock_ledger FOR ALL USING (TRUE) WITH CHECK (TRUE);

DROP POLICY IF EXISTS "Allow all operations on purchases" ON purchases;
CREATE POLICY "Allow all operations on purchases"
ON purchases FOR ALL USING (TRUE) WITH CHECK (TRUE);

DROP POLICY IF EXISTS "Allow all operations on purchase_items" ON purchase_items;
CREATE POLICY "Allow all operations on purchase_items"
ON purchase_items FOR ALL USING (TRUE) WITH CHECK (TRUE);

DROP POLICY IF EXISTS "Allow all operations on supplier_ledger" ON supplier_ledger;
CREATE POLICY "Allow all operations on supplier_ledger"
ON supplier_ledger FOR ALL USING (TRUE) WITH CHECK (TRUE);

DROP POLICY IF EXISTS "Customers view own ledger balance" ON customer_ledger;
DROP POLICY IF EXISTS "Allow all operations on customer_ledger" ON customer_ledger;
CREATE POLICY "Allow all operations on customer_ledger"
ON customer_ledger FOR ALL USING (TRUE) WITH CHECK (TRUE);

DROP POLICY IF EXISTS "Allow all operations on payments" ON payments;
CREATE POLICY "Allow all operations on payments"
ON payments FOR ALL USING (TRUE) WITH CHECK (TRUE);

DROP POLICY IF EXISTS "Allow all operations on settlements" ON settlements;
CREATE POLICY "Allow all operations on settlements"
ON settlements FOR ALL USING (TRUE) WITH CHECK (TRUE);

DROP POLICY IF EXISTS "Drivers view own wallet entries" ON wallet_entries;
DROP POLICY IF EXISTS "Allow all operations on wallet_entries" ON wallet_entries;
CREATE POLICY "Allow all operations on wallet_entries"
ON wallet_entries FOR ALL USING (TRUE) WITH CHECK (TRUE);

DROP POLICY IF EXISTS "Only moderator views audit log" ON audit_log;
DROP POLICY IF EXISTS "Allow view audit logs" ON audit_log;
CREATE POLICY "Allow view audit logs"
ON audit_log FOR SELECT USING (TRUE);
