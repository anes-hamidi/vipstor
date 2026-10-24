-- ============================================================
-- 00012_comprehensive_audit_trail_and_views.sql
-- COMPREHENSIVE AUDIT TRAIL LOGGING & INTELLIGENT MODERATOR VIEW
-- ============================================================

-- 1. Ensure audit_log table has helper indexes and fields
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

-- 2. Enhanced Trigger Function with User Resolution
CREATE OR REPLACE FUNCTION trigger_audit_log_func()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID := NULL;
    v_before JSONB := NULL;
    v_after JSONB := NULL;
    v_target_id UUID := NULL;
BEGIN
    -- 1. Try to resolve user_id from auth.uid()
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

    -- 3. If v_user_id is NULL, intelligently deduce operator from context record fields
    IF v_user_id IS NULL THEN
        IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
            -- Check common user reference columns
            IF v_after ? 'received_by' AND (v_after->>'received_by') IS NOT NULL THEN
                v_user_id := (v_after->>'received_by')::UUID;
            ELSIF v_after ? 'cashier_id' AND (v_after->>'cashier_id') IS NOT NULL THEN
                v_user_id := (v_after->>'cashier_id')::UUID;
            ELSIF v_after ? 'created_by' AND (v_after->>'created_by') IS NOT NULL THEN
                v_user_id := (v_after->>'created_by')::UUID;
            ELSIF v_after ? 'user_id' AND (v_after->>'user_id') IS NOT NULL THEN
                v_user_id := (v_after->>'user_id')::UUID;
            ELSIF v_after ? 'driver_id' AND (v_after->>'driver_id') IS NOT NULL THEN
                v_user_id := (v_after->>'driver_id')::UUID;
            ELSIF TG_TABLE_NAME = 'orders' AND v_after ? 'customer_id' AND (v_after->>'customer_id') IS NOT NULL THEN
                -- Find user_id belonging to customer
                SELECT c.user_id INTO v_user_id 
                FROM customers c 
                WHERE c.id = (v_after->>'customer_id')::UUID;
            END IF;
        ELSE
            -- In DELETE operations, check OLD state
            IF v_before ? 'received_by' AND (v_before->>'received_by') IS NOT NULL THEN
                v_user_id := (v_before->>'received_by')::UUID;
            ELSIF v_before ? 'cashier_id' AND (v_before->>'cashier_id') IS NOT NULL THEN
                v_user_id := (v_before->>'cashier_id')::UUID;
            ELSIF v_before ? 'created_by' AND (v_before->>'created_by') IS NOT NULL THEN
                v_user_id := (v_before->>'created_by')::UUID;
            ELSIF v_before ? 'user_id' AND (v_before->>'user_id') IS NOT NULL THEN
                v_user_id := (v_before->>'user_id')::UUID;
            ELSIF v_before ? 'driver_id' AND (v_before->>'driver_id') IS NOT NULL THEN
                v_user_id := (v_before->>'driver_id')::UUID;
            END IF;
        END IF;
    END IF;

    -- 4. Insert into audit_log
    INSERT INTO audit_log (user_id, action, target_table, target_id, before_state, after_state)
    VALUES (v_user_id, TG_OP, TG_TABLE_NAME, v_target_id, v_before, v_after);

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$;

-- 3. Attach audit triggers to all key operational tables
-- Orders
DROP TRIGGER IF EXISTS trg_audit_orders ON orders;
CREATE TRIGGER trg_audit_orders AFTER INSERT OR UPDATE OR DELETE ON orders
FOR EACH ROW EXECUTE FUNCTION trigger_audit_log_func();

-- Order items
DROP TRIGGER IF EXISTS trg_audit_order_items ON order_items;
CREATE TRIGGER trg_audit_order_items AFTER INSERT OR UPDATE OR DELETE ON order_items
FOR EACH ROW EXECUTE FUNCTION trigger_audit_log_func();

-- Payments (Cash collection & debt repayment)
DROP TRIGGER IF EXISTS trg_audit_payments ON payments;
CREATE TRIGGER trg_audit_payments AFTER INSERT OR UPDATE OR DELETE ON payments
FOR EACH ROW EXECUTE FUNCTION trigger_audit_log_func();

-- Stock Movements (Sales, purchases, manual adjustments)
DROP TRIGGER IF EXISTS trg_audit_stock_ledger ON stock_ledger;
CREATE TRIGGER trg_audit_stock_ledger AFTER INSERT OR UPDATE OR DELETE ON stock_ledger
FOR EACH ROW EXECUTE FUNCTION trigger_audit_log_func();

-- Customer Debt Ledger
DROP TRIGGER IF EXISTS trg_audit_customer_ledger ON customer_ledger;
CREATE TRIGGER trg_audit_customer_ledger AFTER INSERT OR UPDATE OR DELETE ON customer_ledger
FOR EACH ROW EXECUTE FUNCTION trigger_audit_log_func();

-- Supplier Debt Ledger
DROP TRIGGER IF EXISTS trg_audit_supplier_ledger ON supplier_ledger;
CREATE TRIGGER trg_audit_supplier_ledger AFTER INSERT OR UPDATE OR DELETE ON supplier_ledger
FOR EACH ROW EXECUTE FUNCTION trigger_audit_log_func();

-- Purchases (Supplier invoices)
DROP TRIGGER IF EXISTS trg_audit_purchases ON purchases;
CREATE TRIGGER trg_audit_purchases AFTER INSERT OR UPDATE OR DELETE ON purchases
FOR EACH ROW EXECUTE FUNCTION trigger_audit_log_func();

-- Products (Item modifications)
DROP TRIGGER IF EXISTS trg_audit_products ON products;
CREATE TRIGGER trg_audit_products AFTER INSERT OR UPDATE OR DELETE ON products
FOR EACH ROW EXECUTE FUNCTION trigger_audit_log_func();

-- Users (Staff & customer accounts)
DROP TRIGGER IF EXISTS trg_audit_users ON users;
CREATE TRIGGER trg_audit_users AFTER INSERT OR UPDATE OR DELETE ON users
FOR EACH ROW EXECUTE FUNCTION trigger_audit_log_func();

-- Customers (Limits & tiers)
DROP TRIGGER IF EXISTS trg_audit_customers ON customers;
CREATE TRIGGER trg_audit_customers AFTER INSERT OR UPDATE OR DELETE ON customers
FOR EACH ROW EXECUTE FUNCTION trigger_audit_log_func();

-- Product Prices
DROP TRIGGER IF EXISTS trg_audit_product_prices ON product_prices;
CREATE TRIGGER trg_audit_product_prices AFTER INSERT OR UPDATE OR DELETE ON product_prices
FOR EACH ROW EXECUTE FUNCTION trigger_audit_log_func();

-- Settlements (End-of-day driver cash close)
DROP TRIGGER IF EXISTS trg_audit_settlements ON settlements;
CREATE TRIGGER trg_audit_settlements AFTER INSERT OR UPDATE OR DELETE ON settlements
FOR EACH ROW EXECUTE FUNCTION trigger_audit_log_func();

-- Wallet entries (Driver collections & handovers)
DROP TRIGGER IF EXISTS trg_audit_wallet_entries ON wallet_entries;
CREATE TRIGGER trg_audit_wallet_entries AFTER INSERT OR UPDATE OR DELETE ON wallet_entries
FOR EACH ROW EXECUTE FUNCTION trigger_audit_log_func();

-- 4. Create an intelligent human-readable view for moderator inspection
CREATE OR REPLACE VIEW view_audit_trail_intelligence AS
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
    -- Intelligent Title
    CASE 
        WHEN a.target_table = 'orders' AND a.action = 'INSERT' THEN 'طلب جديد تم إنشاؤه'
        WHEN a.target_table = 'orders' AND a.action = 'UPDATE' THEN 
            'تحديث حالة الطلب: ' || COALESCE(a.after_state->>'status', '')
        WHEN a.target_table = 'orders' AND a.action = 'DELETE' THEN 'حذف / إلغاء طلب'
        WHEN a.target_table = 'payments' AND a.action = 'INSERT' THEN 
            'تحصيل مالي: ' || COALESCE(((a.after_state->>'amount')::numeric / 100)::text, '0') || ' دج'
        WHEN a.target_table = 'stock_ledger' AND a.action = 'INSERT' THEN 
            'حركة مخزون (' || COALESCE(a.after_state->>'reason', '') || '): ' || COALESCE(a.after_state->>'qty_change', '0') || ' وحدة'
        WHEN a.target_table = 'customer_ledger' AND a.action = 'INSERT' THEN 
            'تسجيل على حساب الزبون: ' || COALESCE(((a.after_state->>'amount_change')::numeric / 100)::text, '0') || ' دج'
        WHEN a.target_table = 'supplier_ledger' AND a.action = 'INSERT' THEN 
            'تسجيل حساب مورد: ' || COALESCE(((a.after_state->>'amount_change')::numeric / 100)::text, '0') || ' دج'
        WHEN a.target_table = 'settlements' THEN 'إغلاق تسوية سائق (End-of-day)'
        WHEN a.target_table = 'purchases' AND a.action = 'INSERT' THEN 'فاتورة شراء جديدة'
        WHEN a.target_table = 'purchases' AND a.action = 'UPDATE' THEN 'تحديث فاتورة شراء'
        WHEN a.target_table = 'users' AND a.action = 'INSERT' THEN 'تسجيل مستخدم / موظف جديد'
        WHEN a.target_table = 'users' AND a.action = 'UPDATE' THEN 'تعديل بيانات مستخدم'
        WHEN a.target_table = 'products' THEN 'تعديل في قائمة المنتجات'
        WHEN a.target_table = 'product_prices' THEN 'تحديث أسعار الأصناف'
        ELSE a.action || ' على ' || a.target_table
    END AS intelligent_title,
    -- Intelligent Category
    CASE 
        WHEN a.target_table IN ('payments', 'settlements', 'customer_ledger', 'supplier_ledger', 'wallet_entries') THEN 'finance'
        WHEN a.target_table IN ('orders', 'order_items') THEN 'sales'
        WHEN a.target_table IN ('stock_ledger', 'purchases', 'products', 'product_prices') THEN 'inventory'
        WHEN a.target_table IN ('users', 'customers') THEN 'security'
        ELSE 'general'
    END AS category,
    -- Intelligent Actor Type
    CASE 
        WHEN u.role = 'customer' THEN 'customer'
        WHEN u.role IN ('cashier', 'driver', 'manager', 'moderator') THEN 'staff'
        ELSE 'system'
    END AS actor_type,
    a.before_state,
    a.after_state
FROM audit_log a
LEFT JOIN users u ON a.user_id = u.id
ORDER BY a.created_at DESC;

-- Enable RLS and permissions on view/table
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow view audit logs" ON audit_log;
CREATE POLICY "Allow view audit logs"
ON audit_log FOR SELECT
USING (TRUE);
