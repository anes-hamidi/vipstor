-- ============================================================
-- 00022_universal_audit_trail_and_intelligence.sql
--
-- UNIVERSAL REAL-TIME AUDIT LOGGING FOR ALL DATABASE OPERATIONS
--
-- 1. Covers every operational table with automatic trigger logging:
--    - orders, order_items
--    - payments, settlements, wallet_entries
--    - stock_ledger, purchases, purchase_items
--    - products, product_barcodes, product_prices
--    - suppliers, supplier_ledger
--    - users, customers, addresses
--    - driver_locations
--    - stock_adjustments, stock_adjustment_items (if created)
--
-- 2. Enhanced Operator (Actor) Resolution:
--    Deduces the exact actor UUID even when executing as 'anon' role
--    from context fields: payer_user_id, received_by, cashier_id,
--    created_by, driver_id, user_id, approved_by, adjusted_by_user_id.
--
-- 3. Creates unified views:
--    - view_audit_log_enriched (matches Staff App moderator dashboard)
--    - view_audit_trail_intelligence (backward-compatible)
--
-- 4. Ensures RLS and permissions for anon + authenticated roles.
-- ============================================================

-- ── 1. Ensure audit_log table and indexes ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS audit_log (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID REFERENCES users(id),
    action VARCHAR(50) NOT NULL,
    target_table VARCHAR(50) NOT NULL,
    target_id UUID,
    before_state JSONB,
    after_state JSONB,
    ip_address INET,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_log_target ON audit_log(target_table, target_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_user ON audit_log(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_created ON audit_log(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_action ON audit_log(action);

-- ── 2. Universal Trigger Function with Comprehensive Actor Resolution ─────────
CREATE OR REPLACE FUNCTION trigger_audit_log_func()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_user_id UUID := NULL;
    v_before JSONB := NULL;
    v_after JSONB := NULL;
    v_target_id UUID := NULL;
BEGIN
    -- 1. Try to resolve user_id from auth.uid() if JWT session exists
    BEGIN
        v_user_id := auth.uid();
    EXCEPTION WHEN OTHERS THEN
        v_user_id := NULL;
    END;

    -- 2. Extract before/after state and target_id
    IF TG_OP = 'INSERT' THEN
        v_after := to_jsonb(NEW);
        BEGIN
            v_target_id := (NEW.id)::UUID;
        EXCEPTION WHEN OTHERS THEN
            v_target_id := NULL;
        END;
    ELSIF TG_OP = 'UPDATE' THEN
        v_before := to_jsonb(OLD);
        v_after := to_jsonb(NEW);
        BEGIN
            v_target_id := (NEW.id)::UUID;
        EXCEPTION WHEN OTHERS THEN
            v_target_id := NULL;
        END;
    ELSIF TG_OP = 'DELETE' THEN
        v_before := to_jsonb(OLD);
        BEGIN
            v_target_id := (OLD.id)::UUID;
        EXCEPTION WHEN OTHERS THEN
            v_target_id := NULL;
        END;
    END IF;

    -- 3. If v_user_id is NULL (e.g. anon role login with PIN), deduce from record fields
    IF v_user_id IS NULL THEN
        IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
            IF v_after ? 'adjusted_by_user_id' AND (v_after->>'adjusted_by_user_id') IS NOT NULL THEN
                v_user_id := (v_after->>'adjusted_by_user_id')::UUID;
            ELSIF v_after ? 'received_by' AND (v_after->>'received_by') IS NOT NULL THEN
                v_user_id := (v_after->>'received_by')::UUID;
            ELSIF v_after ? 'cashier_id' AND (v_after->>'cashier_id') IS NOT NULL THEN
                v_user_id := (v_after->>'cashier_id')::UUID;
            ELSIF v_after ? 'created_by' AND (v_after->>'created_by') IS NOT NULL THEN
                v_user_id := (v_after->>'created_by')::UUID;
            ELSIF v_after ? 'approved_by' AND (v_after->>'approved_by') IS NOT NULL THEN
                v_user_id := (v_after->>'approved_by')::UUID;
            ELSIF v_after ? 'driver_id' AND (v_after->>'driver_id') IS NOT NULL THEN
                v_user_id := (v_after->>'driver_id')::UUID;
            ELSIF v_after ? 'user_id' AND (v_after->>'user_id') IS NOT NULL THEN
                v_user_id := (v_after->>'user_id')::UUID;
            ELSIF TG_TABLE_NAME = 'orders' AND v_after ? 'customer_id' AND (v_after->>'customer_id') IS NOT NULL THEN
                SELECT c.user_id INTO v_user_id FROM customers c WHERE c.id = (v_after->>'customer_id')::UUID;
            ELSIF TG_TABLE_NAME = 'customer_ledger' AND v_after ? 'customer_id' AND (v_after->>'customer_id') IS NOT NULL THEN
                SELECT c.user_id INTO v_user_id FROM customers c WHERE c.id = (v_after->>'customer_id')::UUID;
            ELSIF TG_TABLE_NAME = 'addresses' AND v_after ? 'customer_id' AND (v_after->>'customer_id') IS NOT NULL THEN
                SELECT c.user_id INTO v_user_id FROM customers c WHERE c.id = (v_after->>'customer_id')::UUID;
            ELSIF TG_TABLE_NAME = 'users' THEN
                v_user_id := v_target_id;
            END IF;
        ELSE
            -- In DELETE operations, check OLD state
            IF v_before ? 'adjusted_by_user_id' AND (v_before->>'adjusted_by_user_id') IS NOT NULL THEN
                v_user_id := (v_before->>'adjusted_by_user_id')::UUID;
            ELSIF v_before ? 'received_by' AND (v_before->>'received_by') IS NOT NULL THEN
                v_user_id := (v_before->>'received_by')::UUID;
            ELSIF v_before ? 'cashier_id' AND (v_before->>'cashier_id') IS NOT NULL THEN
                v_user_id := (v_before->>'cashier_id')::UUID;
            ELSIF v_before ? 'created_by' AND (v_before->>'created_by') IS NOT NULL THEN
                v_user_id := (v_before->>'created_by')::UUID;
            ELSIF v_before ? 'approved_by' AND (v_before->>'approved_by') IS NOT NULL THEN
                v_user_id := (v_before->>'approved_by')::UUID;
            ELSIF v_before ? 'driver_id' AND (v_before->>'driver_id') IS NOT NULL THEN
                v_user_id := (v_before->>'driver_id')::UUID;
            ELSIF v_before ? 'user_id' AND (v_before->>'user_id') IS NOT NULL THEN
                v_user_id := (v_before->>'user_id')::UUID;
            ELSIF TG_TABLE_NAME = 'orders' AND v_before ? 'customer_id' AND (v_before->>'customer_id') IS NOT NULL THEN
                SELECT c.user_id INTO v_user_id FROM customers c WHERE c.id = (v_before->>'customer_id')::UUID;
            ELSIF TG_TABLE_NAME = 'users' THEN
                v_user_id := v_target_id;
            END IF;
        END IF;
    END IF;

    -- 4. Insert into immutable audit_log
    INSERT INTO audit_log (user_id, action, target_table, target_id, before_state, after_state)
    VALUES (v_user_id, TG_OP, TG_TABLE_NAME, v_target_id, v_before, v_after);

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$;

-- ── 3. Attach Universal Triggers to ALL Operational Tables ───────────────────

-- Sales & Orders
DROP TRIGGER IF EXISTS trg_audit_orders ON orders;
CREATE TRIGGER trg_audit_orders AFTER INSERT OR UPDATE OR DELETE ON orders
FOR EACH ROW EXECUTE FUNCTION trigger_audit_log_func();

DROP TRIGGER IF EXISTS trg_audit_order_items ON order_items;
CREATE TRIGGER trg_audit_order_items AFTER INSERT OR UPDATE OR DELETE ON order_items
FOR EACH ROW EXECUTE FUNCTION trigger_audit_log_func();

-- Payments & Cash Flow
DROP TRIGGER IF EXISTS trg_audit_payments ON payments;
CREATE TRIGGER trg_audit_payments AFTER INSERT OR UPDATE OR DELETE ON payments
FOR EACH ROW EXECUTE FUNCTION trigger_audit_log_func();

DROP TRIGGER IF EXISTS trg_audit_settlements ON settlements;
CREATE TRIGGER trg_audit_settlements AFTER INSERT OR UPDATE OR DELETE ON settlements
FOR EACH ROW EXECUTE FUNCTION trigger_audit_log_func();

DROP TRIGGER IF EXISTS trg_audit_wallet_entries ON wallet_entries;
CREATE TRIGGER trg_audit_wallet_entries AFTER INSERT OR UPDATE OR DELETE ON wallet_entries
FOR EACH ROW EXECUTE FUNCTION trigger_audit_log_func();

-- Inventory & Stock Movements
DROP TRIGGER IF EXISTS trg_audit_stock_ledger ON stock_ledger;
CREATE TRIGGER trg_audit_stock_ledger AFTER INSERT OR UPDATE OR DELETE ON stock_ledger
FOR EACH ROW EXECUTE FUNCTION trigger_audit_log_func();

DROP TRIGGER IF EXISTS trg_audit_purchases ON purchases;
CREATE TRIGGER trg_audit_purchases AFTER INSERT OR UPDATE OR DELETE ON purchases
FOR EACH ROW EXECUTE FUNCTION trigger_audit_log_func();

DROP TRIGGER IF EXISTS trg_audit_purchase_items ON purchase_items;
CREATE TRIGGER trg_audit_purchase_items AFTER INSERT OR UPDATE OR DELETE ON purchase_items
FOR EACH ROW EXECUTE FUNCTION trigger_audit_log_func();

-- Products, Prices & Barcodes
DROP TRIGGER IF EXISTS trg_audit_products ON products;
CREATE TRIGGER trg_audit_products AFTER INSERT OR UPDATE OR DELETE ON products
FOR EACH ROW EXECUTE FUNCTION trigger_audit_log_func();

DROP TRIGGER IF EXISTS trg_audit_product_prices ON product_prices;
CREATE TRIGGER trg_audit_product_prices AFTER INSERT OR UPDATE OR DELETE ON product_prices
FOR EACH ROW EXECUTE FUNCTION trigger_audit_log_func();

DROP TRIGGER IF EXISTS trg_audit_product_barcodes ON product_barcodes;
CREATE TRIGGER trg_audit_product_barcodes AFTER INSERT OR UPDATE OR DELETE ON product_barcodes
FOR EACH ROW EXECUTE FUNCTION trigger_audit_log_func();

-- Debt & Balances Ledgers
DROP TRIGGER IF EXISTS trg_audit_customer_ledger ON customer_ledger;
CREATE TRIGGER trg_audit_customer_ledger AFTER INSERT OR UPDATE OR DELETE ON customer_ledger
FOR EACH ROW EXECUTE FUNCTION trigger_audit_log_func();

DROP TRIGGER IF EXISTS trg_audit_supplier_ledger ON supplier_ledger;
CREATE TRIGGER trg_audit_supplier_ledger AFTER INSERT OR UPDATE OR DELETE ON supplier_ledger
FOR EACH ROW EXECUTE FUNCTION trigger_audit_log_func();

-- Stakeholders (Users, Customers, Suppliers, Addresses)
DROP TRIGGER IF EXISTS trg_audit_users ON users;
CREATE TRIGGER trg_audit_users AFTER INSERT OR UPDATE OR DELETE ON users
FOR EACH ROW EXECUTE FUNCTION trigger_audit_log_func();

DROP TRIGGER IF EXISTS trg_audit_customers ON customers;
CREATE TRIGGER trg_audit_customers AFTER INSERT OR UPDATE OR DELETE ON customers
FOR EACH ROW EXECUTE FUNCTION trigger_audit_log_func();

DROP TRIGGER IF EXISTS trg_audit_suppliers ON suppliers;
CREATE TRIGGER trg_audit_suppliers AFTER INSERT OR UPDATE OR DELETE ON suppliers
FOR EACH ROW EXECUTE FUNCTION trigger_audit_log_func();

DROP TRIGGER IF EXISTS trg_audit_addresses ON addresses;
CREATE TRIGGER trg_audit_addresses AFTER INSERT OR UPDATE OR DELETE ON addresses
FOR EACH ROW EXECUTE FUNCTION trigger_audit_log_func();

-- Real-time tracking
DROP TRIGGER IF EXISTS trg_audit_driver_locations ON driver_locations;
CREATE TRIGGER trg_audit_driver_locations AFTER INSERT OR UPDATE OR DELETE ON driver_locations
FOR EACH ROW EXECUTE FUNCTION trigger_audit_log_func();

-- ── 4. Unified Enriched View for the Moderator Dashboard ───────────────────────
DROP VIEW IF EXISTS view_audit_trail_intelligence CASCADE;
DROP VIEW IF EXISTS view_audit_log_enriched CASCADE;

CREATE OR REPLACE VIEW view_audit_log_enriched AS
SELECT 
    a.id,
    a.created_at,
    a.action,
    a.target_table,
    a.target_id,
    a.user_id,
    u.name AS actor_name,
    u.role AS actor_role,
    u.phone AS actor_phone,
    -- Intelligent Title in Arabic
    CASE 
        -- Orders
        WHEN a.target_table = 'orders' AND a.action = 'INSERT' THEN 
            'طلب جديد تم تسجيله (' || COALESCE(a.after_state->>'channel', 'store') || ')'
        WHEN a.target_table = 'orders' AND a.action = 'UPDATE' THEN 
            'تحديث حالة الطلب إلى: ' || COALESCE(a.after_state->>'status', '')
        WHEN a.target_table = 'orders' AND a.action = 'DELETE' THEN 'حذف أو إلغاء طلب'
        
        -- Payments & Cash
        WHEN a.target_table = 'payments' AND a.action = 'INSERT' THEN 
            'تحصيل مالي: ' || COALESCE(((a.after_state->>'amount')::numeric / 100)::text, '0') || ' دج'
        WHEN a.target_table = 'payments' AND a.action = 'UPDATE' THEN 'تعديل دفعة مالية'
        WHEN a.target_table = 'settlements' THEN 'إغلاق تسوية سائق (End-of-day)'
        WHEN a.target_table = 'wallet_entries' AND a.action = 'INSERT' THEN 
            'حركة بمحفظة السائق: ' || COALESCE(a.after_state->>'type', '') || ' (' || COALESCE(((a.after_state->>'amount')::numeric / 100)::text, '0') || ' دج)'
        
        -- Stock & Purchasing
        WHEN a.target_table = 'stock_ledger' AND a.action = 'INSERT' THEN 
            'حركة مخزون (' || COALESCE(a.after_state->>'reason', '') || '): ' || COALESCE(a.after_state->>'qty_change', '0') || ' وحدة'
        WHEN a.target_table = 'purchases' AND a.action = 'INSERT' THEN 
            'فاتورة شراء جديدة: ' || COALESCE(a.after_state->>'invoice_no', '')
        WHEN a.target_table = 'purchases' AND a.action = 'UPDATE' THEN 
            'تحديث حالة فاتورة شراء إلى: ' || COALESCE(a.after_state->>'status', '')
        WHEN a.target_table = 'purchase_items' THEN 'إضافة / تعديل بنود فاتورة شراء'

        -- Products & Pricing
        WHEN a.target_table = 'products' AND a.action = 'INSERT' THEN 
            'إضافة منتج جديد: ' || COALESCE(a.after_state->>'name_ar', '')
        WHEN a.target_table = 'products' AND a.action = 'UPDATE' THEN 
            'تعديل منتج: ' || COALESCE(a.after_state->>'name_ar', '')
        WHEN a.target_table = 'products' AND a.action = 'DELETE' THEN 
            'حذف منتج من الكتالوج'
        WHEN a.target_table = 'product_prices' THEN 
            'تحديث تسعيرة منتج (' || COALESCE(a.after_state->>'tier', '') || '): ' || COALESCE(((a.after_state->>'price')::numeric / 100)::text, '0') || ' دج'
        WHEN a.target_table = 'product_barcodes' THEN 'إضافة أو تعديل باركود لمنتج'

        -- Customer & Supplier Ledgers
        WHEN a.target_table = 'customer_ledger' AND a.action = 'INSERT' THEN 
            'قيد دين زبون: ' || COALESCE(((a.after_state->>'amount_change')::numeric / 100)::text, '0') || ' دج'
        WHEN a.target_table = 'supplier_ledger' AND a.action = 'INSERT' THEN 
            'قيد حساب مورد: ' || COALESCE(((a.after_state->>'amount_change')::numeric / 100)::text, '0') || ' دج'

        -- Security & Accounts
        WHEN a.target_table = 'users' AND a.action = 'INSERT' THEN 
            'إنشاء حساب جديد: ' || COALESCE(a.after_state->>'name', '') || ' (' || COALESCE(a.after_state->>'role', '') || ')'
        WHEN a.target_table = 'users' AND a.action = 'UPDATE' THEN 
            'تحديث بيانات مستخدم: ' || COALESCE(a.after_state->>'name', '')
        WHEN a.target_table = 'customers' THEN 'تحديث بيانات زبون / حد الائتمان'
        WHEN a.target_table = 'suppliers' THEN 'إضافة أو تعديل مورد'
        WHEN a.target_table = 'addresses' THEN 'إضافة أو تعديل عنوان توصيل'
        WHEN a.target_table = 'driver_locations' THEN 'تحديث موقع سائق التوصيل'

        -- Explicit Access & Session Action Types
        WHEN a.action = 'STAFF_LOGIN' THEN 
            'تسجيل دخول موظف: ' || COALESCE(a.after_state->>'name', u.name, '') || ' (' || COALESCE(a.after_state->>'role', u.role::text, '') || ')'
        WHEN a.action = 'STAFF_LOGOUT' THEN 
            'تسجيل خروج موظف: ' || COALESCE(a.after_state->>'name', u.name, '')
        WHEN a.action = 'CASHIER_SWITCH' THEN 
            'تبديل كاشير: ' || COALESCE(a.after_state->>'new_cashier_name', '') || ' (السابق: ' || COALESCE(a.before_state->>'previous_cashier_name', '') || ')'
        WHEN a.action = 'SHIFT_OPENED' THEN 
            'فتح وردية كاشير جديدة (Z-#' || COALESCE(a.after_state->>'z_report_number', '') || ') برصيد: ' || COALESCE(((a.after_state->>'opening_float_centimes')::numeric / 100)::text, '0') || ' دج'
        WHEN a.action = 'SHIFT_CLOSED' THEN 
            'إغلاق وردية كاشير (Z-#' || COALESCE(a.after_state->>'z_report_number', '') || ') بفارق: ' || COALESCE(((a.after_state->>'variance_centimes')::numeric / 100)::text, '0') || ' دج'
        WHEN a.action = 'SUPPLIER_PAYMENT' THEN 
            'سداد نقدي للمورد: ' || COALESCE(a.after_state->>'supplier_name', '') || ' بمبلغ ' || COALESCE(((a.after_state->>'amount_centimes')::numeric / 100)::text, '0') || ' دج'
        WHEN a.action = 'MODERATOR_RESET_USER_PIN' THEN 'إعادة تعيين رمز PIN لموظف بواسطة المشرف'
        WHEN a.action = 'USER_PIN_CHANGED' THEN 'تغيير رمز PIN الحساب'
        WHEN a.action = 'STAFF_MEMBER_CREATED' THEN 'إنشاء حساب موظف جديد'
        ELSE a.action || ' على ' || a.target_table
    END AS intelligent_title,

    -- Intelligent Category (مبيعات / مالية / مخزون / أمان / عام)
    CASE 
        WHEN a.action IN ('SHIFT_OPENED', 'SHIFT_CLOSED', 'SUPPLIER_PAYMENT') THEN 'finance'
        WHEN a.target_table IN ('payments', 'settlements', 'customer_ledger', 'supplier_ledger', 'wallet_entries') THEN 'finance'
        WHEN a.target_table IN ('orders', 'order_items') THEN 'sales'
        WHEN a.target_table IN ('stock_ledger', 'purchases', 'purchase_items', 'products', 'product_prices', 'product_barcodes') THEN 'inventory'
        WHEN a.target_table IN ('users', 'customers') OR a.action IN ('STAFF_LOGIN', 'STAFF_LOGOUT', 'CASHIER_SWITCH', 'MODERATOR_RESET_USER_PIN', 'USER_PIN_CHANGED', 'STAFF_MEMBER_CREATED') THEN 'security'
        ELSE 'general'
    END AS category,

    -- Actor Type (staff, customer, system)
    CASE 
        WHEN u.role = 'customer' THEN 'customer'
        WHEN u.role IN ('cashier', 'driver', 'manager', 'moderator') THEN 'staff'
        WHEN a.action IN ('STAFF_LOGIN', 'STAFF_LOGOUT', 'CASHIER_SWITCH', 'SHIFT_OPENED', 'SHIFT_CLOSED') THEN 'staff'
        ELSE 'system'
    END AS actor_type,

    a.ip_address,
    a.before_state,
    a.after_state
FROM audit_log a
LEFT JOIN users u ON a.user_id = u.id
ORDER BY a.created_at DESC;

-- Backward-compatible alias view
CREATE OR REPLACE VIEW view_audit_trail_intelligence AS
SELECT * FROM view_audit_log_enriched;

-- ── 5. Security & Access Grants ────────────────────────────────────────────────
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow select audit_log" ON audit_log;
CREATE POLICY "Allow select audit_log"
ON audit_log FOR SELECT
TO anon, authenticated
USING (TRUE);

DROP POLICY IF EXISTS "Allow insert audit_log" ON audit_log;
CREATE POLICY "Allow insert audit_log"
ON audit_log FOR INSERT
TO anon, authenticated
WITH CHECK (TRUE);

GRANT SELECT, INSERT ON audit_log TO anon, authenticated;
GRANT SELECT ON view_audit_log_enriched TO anon, authenticated;
GRANT SELECT ON view_audit_trail_intelligence TO anon, authenticated;

-- Force PostgREST schema reload
NOTIFY pgrst, 'reload schema';
