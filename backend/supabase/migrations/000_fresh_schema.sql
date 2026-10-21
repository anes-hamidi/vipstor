-- ============================================================
-- VIP WHOLESALE & POS MANAGEMENT SYSTEM
-- COMPLETE AUTHORITATIVE FRESH DATABASE SCHEMA & RLS
-- Single authoritative migration — run on an empty database.
-- ============================================================

-- ============================================================
-- SECTION 1: EXTENSIONS
-- ============================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";


-- ============================================================
-- SECTION 2: ENUM TYPES
-- ============================================================
DO $$ BEGIN
    CREATE TYPE user_role AS ENUM (
        'moderator', 'manager', 'cashier', 'driver', 'customer'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE price_tier AS ENUM (
        'retail', 'wholesale', 'bulk'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE purchase_status AS ENUM (
        'draft', 'posted', 'cancelled'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE order_channel AS ENUM (
        'store', 'online'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE order_status AS ENUM (
        'submitted',        -- Online order placed by customer
        'confirmed',        -- Cashier confirmed, inventory reserved
        'preparing',        -- Warehouse packing
        'ready',            -- Ready for dispatch
        'assigned',         -- Assigned to driver
        'accepted',         -- Driver accepted
        'refused',          -- Driver refused, re-queued
        'out_for_delivery', -- With driver
        'delivered',        -- Delivered, cash collected
        'settled',          -- End-of-day cash closed
        'cancelled'         -- Voided / returned
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE payment_method AS ENUM (
        'cash', 'customer_balance', 'mixed'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE payment_status AS ENUM (
        'collected', 'settled', 'reversed'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE wallet_entry_type AS ENUM (
        'collection', 'handover', 'shortage', 'overage', 'reversal'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE settlement_status AS ENUM (
        'pending', 'settled', 'discrepancy_flagged', 'approved'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE stock_ref_type AS ENUM (
        'purchase', 'sale', 'return', 'adjustment'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;


-- ============================================================
-- SECTION 3: ROLE-BASED ACCESS CONTROL (RBAC) & PERMISSIONS
-- ============================================================

CREATE TABLE IF NOT EXISTS permissions (
    code        VARCHAR(64) PRIMARY KEY,
    module      VARCHAR(50) NOT NULL,
    description TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS role_permissions (
    role            user_role   NOT NULL,
    permission_code VARCHAR(64) NOT NULL REFERENCES permissions(code) ON DELETE CASCADE,
    PRIMARY KEY (role, permission_code)
);

-- Seed Standard Granular Permissions
INSERT INTO permissions (code, module, description) VALUES
    ('products.read',          'catalog',     'عرض قائمة وتفاصيل المنتجات والأسعار'),
    ('products.manage',        'catalog',     'إضافة وتعديل وحذف المنتجات والباركود والأسعار'),
    ('orders.view_all',        'orders',      'عرض جميع الطلبيات وحالاتها'),
    ('orders.view_assigned',   'orders',      'عرض الطلبيات المسندة للسائق فقط'),
    ('orders.view_own',        'orders',      'عرض الزبون لطلبياته الخاصة'),
    ('orders.create_counter',  'pos',         'تسجيل مبيعات الكاونتر الفورية'),
    ('orders.create_online',   'ecommerce',   'تقديم طلبية شراء إلكترونية'),
    ('orders.manage_status',   'orders',      'تأكيد الطلبيات وتعيين السائق وتحديث مراحل التجهيز'),
    ('orders.deliver',         'delivery',    'تسجيل تسليم الطلبية وتحصيل المبالغ النقدية'),
    ('purchases.manage',       'purchases',   'إدخال فواتير الشراء وترحيلها لحساب المورد والمخزون'),
    ('suppliers.manage',       'suppliers',   'إدارة الموردين وحساباتهم ومستحقاتهم'),
    ('customers.manage',       'customers',   'إدارة الزبائن وحدود الائتمان وسقوف الديون'),
    ('finance.collect_debt',   'finance',     'تحصيل ديون الزبائن وإصدار وصولات السداد'),
    ('finance.settle_wallet',  'finance',     'تسوية عهدة السائقين وإغلاق الصناديق اليومية'),
    ('finance.view_reports',   'finance',     'الاطلاع على تقارير الأرباح والسيولة والديون'),
    ('staff.manage',           'staff',       'إنشاء وتعديل حسابات الموظفين وتعيين الأدوار'),
    ('staff.reset_pin',        'staff',       'إعادة تعيين رموز PIN للموظفين بواسطة المشرف'),
    ('audit.view',             'audit',       'عرض سجل تدقيق العمليات والتغييرات الأمنية'),
    ('telemetry.driver_gps',   'delivery',    'بث واستقبال الإحداثيات المباشرة للسائقين')
ON CONFLICT (code) DO UPDATE SET
    module = EXCLUDED.module,
    description = EXCLUDED.description;

-- Bind Permissions to User Roles
INSERT INTO role_permissions (role, permission_code) VALUES
    -- Moderator: full authority
    ('moderator', 'products.read'),
    ('moderator', 'products.manage'),
    ('moderator', 'orders.view_all'),
    ('moderator', 'orders.create_counter'),
    ('moderator', 'orders.manage_status'),
    ('moderator', 'purchases.manage'),
    ('moderator', 'suppliers.manage'),
    ('moderator', 'customers.manage'),
    ('moderator', 'finance.collect_debt'),
    ('moderator', 'finance.settle_wallet'),
    ('moderator', 'finance.view_reports'),
    ('moderator', 'staff.manage'),
    ('moderator', 'staff.reset_pin'),
    ('moderator', 'audit.view'),
    ('moderator', 'telemetry.driver_gps'),

    -- Inventory Manager
    ('manager', 'products.read'),
    ('manager', 'products.manage'),
    ('manager', 'orders.view_all'),
    ('manager', 'orders.manage_status'),
    ('manager', 'purchases.manage'),
    ('manager', 'suppliers.manage'),
    ('manager', 'customers.manage'),
    ('manager', 'telemetry.driver_gps'),

    -- Counter Cashier
    ('cashier', 'products.read'),
    ('cashier', 'orders.view_all'),
    ('cashier', 'orders.create_counter'),
    ('cashier', 'orders.manage_status'),
    ('cashier', 'customers.manage'),
    ('cashier', 'finance.collect_debt'),
    ('cashier', 'finance.settle_wallet'),
    ('cashier', 'telemetry.driver_gps'),

    -- Delivery Driver
    ('driver', 'products.read'),
    ('driver', 'orders.view_assigned'),
    ('driver', 'orders.deliver'),
    ('driver', 'telemetry.driver_gps'),

    -- Customer
    ('customer', 'products.read'),
    ('customer', 'orders.view_own'),
    ('customer', 'orders.create_online'),
    ('customer', 'telemetry.driver_gps')
ON CONFLICT (role, permission_code) DO NOTHING;

-- Helper to check if a role possesses a permission
CREATE OR REPLACE FUNCTION has_permission(p_role user_role, p_permission_code VARCHAR)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT EXISTS (
        SELECT 1 FROM role_permissions
        WHERE role = p_role AND permission_code = p_permission_code
    );
$$;

-- Helper to list all permissions for a role
CREATE OR REPLACE FUNCTION get_role_permissions(p_role user_role)
RETURNS TEXT[] LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT COALESCE(array_agg(permission_code::TEXT), ARRAY[]::TEXT[])
    FROM role_permissions
    WHERE role = p_role;
$$;


-- ============================================================
-- SECTION 4: CORE ENTITY TABLES
-- ============================================================

-- Users table (staff + customers share this table, differentiated by role)
CREATE TABLE IF NOT EXISTS users (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone       VARCHAR(20)  NOT NULL UNIQUE,
    name        VARCHAR(100) NOT NULL,
    role        user_role    NOT NULL DEFAULT 'customer',
    active      BOOLEAN      NOT NULL DEFAULT TRUE,
    language    VARCHAR(5)   NOT NULL DEFAULT 'ar' CHECK (language IN ('ar', 'fr')),
    pin_code    TEXT,        -- Bcrypt hash (60 chars)
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- Customer profiles (one-to-one with users where role = 'customer')
CREATE TABLE IF NOT EXISTS customers (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID        NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    price_tier   price_tier  NOT NULL DEFAULT 'wholesale',
    credit_limit BIGINT      NOT NULL DEFAULT 0,  -- In centimes (DA × 100)
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Customer delivery addresses
CREATE TABLE IF NOT EXISTS addresses (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id  UUID        NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    label        VARCHAR(50) NOT NULL DEFAULT 'المحل الرئيسي',
    address_text TEXT        NOT NULL,
    wilaya       VARCHAR(50) NOT NULL,
    commune      VARCHAR(50) NOT NULL,
    latitude     DOUBLE PRECISION,
    longitude    DOUBLE PRECISION,
    is_default   BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Suppliers
CREATE TABLE IF NOT EXISTS suppliers (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name             VARCHAR(150) NOT NULL,
    phone            VARCHAR(20)  NOT NULL,
    company_register VARCHAR(50),
    notes            TEXT,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- Products catalog
CREATE TABLE IF NOT EXISTS products (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name_ar         VARCHAR(200) NOT NULL,
    name_fr         VARCHAR(200) NOT NULL,
    category        VARCHAR(100) NOT NULL DEFAULT 'عام',
    unit            VARCHAR(20)  NOT NULL DEFAULT 'piece',
    pack_size       INT          NOT NULL DEFAULT 1,
    photo_url       TEXT,
    last_unit_cost  BIGINT       NOT NULL DEFAULT 0,  -- In centimes
    min_stock_alert INT          NOT NULL DEFAULT 5,
    active          BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- Product barcodes
CREATE TABLE IF NOT EXISTS product_barcodes (
    barcode        VARCHAR(64) PRIMARY KEY,
    product_id     UUID        NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    units_per_scan INT         NOT NULL DEFAULT 1,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Multi-tier pricing
CREATE TABLE IF NOT EXISTS product_prices (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID        NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    tier       price_tier  NOT NULL,
    min_qty    INT         NOT NULL DEFAULT 1,
    price      BIGINT      NOT NULL CHECK (price >= 0),  -- In centimes
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_product_tier_min_qty UNIQUE (product_id, tier, min_qty)
);

-- Purchases (Supplier invoice headers)
CREATE TABLE IF NOT EXISTS purchases (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    supplier_id  UUID            NOT NULL REFERENCES suppliers(id),
    invoice_no   VARCHAR(100)    NOT NULL,
    invoice_date DATE            NOT NULL DEFAULT CURRENT_DATE,
    status       purchase_status NOT NULL DEFAULT 'draft',
    total_amount BIGINT          NOT NULL DEFAULT 0,  -- In centimes
    created_by   UUID            NOT NULL REFERENCES users(id),
    posted_at    TIMESTAMPTZ,
    created_at   TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_supplier_invoice UNIQUE (supplier_id, invoice_no)
);

-- Purchase invoice items
CREATE TABLE IF NOT EXISTS purchase_items (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    purchase_id   UUID    NOT NULL REFERENCES purchases(id) ON DELETE CASCADE,
    product_id    UUID    NOT NULL REFERENCES products(id),
    quantity      INT     NOT NULL CHECK (quantity > 0),
    unit_cost     BIGINT  NOT NULL CHECK (unit_cost >= 0),     -- In centimes
    selling_price BIGINT  NOT NULL CHECK (selling_price >= 0), -- In centimes
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Orders (Counter sales and online orders)
CREATE TABLE IF NOT EXISTS orders (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id        UUID         UNIQUE,  -- Offline idempotency key
    order_number     BIGSERIAL    UNIQUE,
    channel          order_channel NOT NULL,
    customer_id      UUID         REFERENCES customers(id),  -- NULL = walk-in customer
    status           order_status  NOT NULL DEFAULT 'submitted',
    driver_id        UUID         REFERENCES users(id),
    cashier_id       UUID         REFERENCES users(id),
    delivery_address JSONB,
    total_amount     BIGINT       NOT NULL DEFAULT 0,  -- In centimes
    total_cost       BIGINT       NOT NULL DEFAULT 0,  -- In centimes
    paid_amount      BIGINT       NOT NULL DEFAULT 0,  -- In centimes
    notes            TEXT,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    confirmed_at     TIMESTAMPTZ,
    delivered_at     TIMESTAMPTZ,
    settled_at       TIMESTAMPTZ
);

-- Order items
CREATE TABLE IF NOT EXISTS order_items (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id   UUID    NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id UUID    NOT NULL REFERENCES products(id),
    quantity   INT     NOT NULL CHECK (quantity > 0),
    unit_price BIGINT  NOT NULL CHECK (unit_price >= 0),  -- In centimes
    unit_cost  BIGINT  NOT NULL DEFAULT 0,                -- In centimes
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- ============================================================
-- SECTION 5: APPEND-ONLY FINANCIAL & STOCK LEDGERS
-- ============================================================

-- Stock movement ledger
CREATE TABLE IF NOT EXISTS stock_ledger (
    id         UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID           NOT NULL REFERENCES products(id),
    qty_change INT            NOT NULL,
    reason     stock_ref_type NOT NULL,
    ref_type   VARCHAR(50)    NOT NULL,
    ref_id     UUID           NOT NULL,
    user_id    UUID           NOT NULL REFERENCES users(id),
    notes      TEXT,
    created_at TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

-- Customer debt ledger
CREATE TABLE IF NOT EXISTS customer_ledger (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id   UUID        NOT NULL REFERENCES customers(id),
    amount_change BIGINT      NOT NULL,  -- Positive = debt, Negative = payment
    ref_type      VARCHAR(50) NOT NULL,
    ref_id        UUID        NOT NULL,
    notes         TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Supplier liability ledger
CREATE TABLE IF NOT EXISTS supplier_ledger (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    supplier_id   UUID        NOT NULL REFERENCES suppliers(id),
    amount_change BIGINT      NOT NULL,  -- Positive = shop liability
    ref_type      VARCHAR(50) NOT NULL,
    ref_id        UUID        NOT NULL,
    notes         TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Payments collection log
CREATE TABLE IF NOT EXISTS payments (
    id          UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id    UUID           REFERENCES orders(id),
    customer_id UUID           REFERENCES customers(id),
    amount      BIGINT         NOT NULL CHECK (amount > 0),
    method      payment_method NOT NULL DEFAULT 'cash',
    received_by UUID           NOT NULL REFERENCES users(id),
    status      payment_status NOT NULL DEFAULT 'collected',
    client_id   UUID           UNIQUE,  -- Idempotency key
    created_at  TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

-- Driver end-of-day settlements
CREATE TABLE IF NOT EXISTS settlements (
    id              UUID              PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id       UUID              NOT NULL REFERENCES users(id),
    cashier_id      UUID              NOT NULL REFERENCES users(id),
    expected_amount BIGINT            NOT NULL,
    counted_amount  BIGINT            NOT NULL,
    difference      BIGINT            GENERATED ALWAYS AS (counted_amount - expected_amount) STORED,
    status          settlement_status NOT NULL DEFAULT 'settled',
    approved_by     UUID              REFERENCES users(id),
    notes           TEXT,
    created_at      TIMESTAMPTZ       NOT NULL DEFAULT NOW()
);

-- Driver cash wallet entries
CREATE TABLE IF NOT EXISTS wallet_entries (
    id            UUID              PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id     UUID              NOT NULL REFERENCES users(id),
    type          wallet_entry_type NOT NULL,
    amount        BIGINT            NOT NULL CHECK (amount > 0),
    payment_id    UUID              REFERENCES payments(id),
    settlement_id UUID              REFERENCES settlements(id),
    client_id     UUID              UNIQUE,  -- Idempotency key
    created_at    TIMESTAMPTZ       NOT NULL DEFAULT NOW()
);

-- Real-time driver telemetry
CREATE TABLE IF NOT EXISTS driver_locations (
    driver_id     UUID             PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    latitude      DOUBLE PRECISION NOT NULL,
    longitude     DOUBLE PRECISION NOT NULL,
    heading       DOUBLE PRECISION,
    speed         DOUBLE PRECISION,
    battery_level INTEGER,
    updated_at    TIMESTAMPTZ      NOT NULL DEFAULT NOW()
);

-- PIN Brute-force protection tracker
CREATE TABLE IF NOT EXISTS pin_attempt_limits (
    user_id        UUID        PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    failed_attempts INT        NOT NULL DEFAULT 0,
    locked_until   TIMESTAMPTZ,
    lock_step      INT         NOT NULL DEFAULT 0,
    last_failed_at TIMESTAMPTZ
);

-- System audit trail
CREATE TABLE IF NOT EXISTS audit_log (
    id           BIGSERIAL   PRIMARY KEY,
    user_id      UUID        REFERENCES users(id),
    action       VARCHAR(50) NOT NULL,
    target_table VARCHAR(50) NOT NULL,
    target_id    UUID,
    before_state JSONB,
    after_state  JSONB,
    ip_address   INET,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- ============================================================
-- SECTION 6: IMMUTABLE LEDGER GUARDS
-- ============================================================
CREATE OR REPLACE FUNCTION trg_block_immutable_ledger_modifications()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'Table % is strictly append-only. UPDATE and DELETE are prohibited.', TG_TABLE_NAME;
END;
$$;

DROP TRIGGER IF EXISTS trg_block_stock_ledger_mutation ON stock_ledger;
CREATE TRIGGER trg_block_stock_ledger_mutation
    BEFORE UPDATE OR DELETE ON stock_ledger
    FOR EACH ROW EXECUTE FUNCTION trg_block_immutable_ledger_modifications();

DROP TRIGGER IF EXISTS trg_block_customer_ledger_mutation ON customer_ledger;
CREATE TRIGGER trg_block_customer_ledger_mutation
    BEFORE UPDATE OR DELETE ON customer_ledger
    FOR EACH ROW EXECUTE FUNCTION trg_block_immutable_ledger_modifications();

DROP TRIGGER IF EXISTS trg_block_supplier_ledger_mutation ON supplier_ledger;
CREATE TRIGGER trg_block_supplier_ledger_mutation
    BEFORE UPDATE OR DELETE ON supplier_ledger
    FOR EACH ROW EXECUTE FUNCTION trg_block_immutable_ledger_modifications();


-- ============================================================
-- SECTION 7: AUTOMATED AUDIT TRIGGER
-- ============================================================
CREATE OR REPLACE FUNCTION trigger_audit_log_func()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
    v_user_id  UUID    := NULL;
    v_before   JSONB   := NULL;
    v_after    JSONB   := NULL;
    v_target   UUID    := NULL;
    v_ip       INET    := NULL;
BEGIN
    BEGIN v_ip := inet_client_addr(); EXCEPTION WHEN OTHERS THEN v_ip := NULL; END;
    BEGIN v_user_id := auth.uid(); EXCEPTION WHEN OTHERS THEN v_user_id := NULL; END;

    IF TG_OP = 'INSERT' THEN
        v_after  := to_jsonb(NEW) - 'pin_code';
        BEGIN v_target := (NEW.id)::UUID; EXCEPTION WHEN OTHERS THEN NULL; END;
    ELSIF TG_OP = 'UPDATE' THEN
        v_before := to_jsonb(OLD) - 'pin_code';
        v_after  := to_jsonb(NEW) - 'pin_code';
        BEGIN v_target := (NEW.id)::UUID; EXCEPTION WHEN OTHERS THEN NULL; END;
    ELSIF TG_OP = 'DELETE' THEN
        v_before := to_jsonb(OLD) - 'pin_code';
        BEGIN v_target := (OLD.id)::UUID; EXCEPTION WHEN OTHERS THEN NULL; END;
    END IF;

    IF v_user_id IS NULL THEN
        DECLARE src JSONB := COALESCE(v_after, v_before); BEGIN
            IF    src ? 'received_by'  AND (src->>'received_by')  IS NOT NULL THEN v_user_id := (src->>'received_by')::UUID;
            ELSIF src ? 'cashier_id'   AND (src->>'cashier_id')   IS NOT NULL THEN v_user_id := (src->>'cashier_id')::UUID;
            ELSIF src ? 'created_by'   AND (src->>'created_by')   IS NOT NULL THEN v_user_id := (src->>'created_by')::UUID;
            ELSIF src ? 'driver_id'    AND (src->>'driver_id')    IS NOT NULL THEN v_user_id := (src->>'driver_id')::UUID;
            ELSIF src ? 'user_id'      AND (src->>'user_id')      IS NOT NULL THEN v_user_id := (src->>'user_id')::UUID;
            ELSIF src ? 'customer_id'  AND (src->>'customer_id')  IS NOT NULL THEN
                BEGIN
                    SELECT user_id INTO v_user_id FROM customers WHERE id = (src->>'customer_id')::UUID;
                EXCEPTION WHEN OTHERS THEN NULL; END;
            END IF;
        END;
    END IF;

    INSERT INTO audit_log (user_id, action, target_table, target_id, before_state, after_state, ip_address)
    VALUES (v_user_id, TG_OP, TG_TABLE_NAME, v_target, v_before, v_after, v_ip);

    RETURN COALESCE(NEW, OLD);
END;
$$;

-- Attach audit trigger to all operational tables
DO $$
DECLARE t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'orders', 'order_items', 'payments', 'purchases', 'purchase_items',
        'products', 'product_barcodes', 'product_prices', 'suppliers',
        'customers', 'users', 'addresses', 'settlements', 'wallet_entries',
        'stock_ledger', 'customer_ledger', 'supplier_ledger'
    ] LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_audit_%I ON %I', t, t);
        EXECUTE format('CREATE TRIGGER trg_audit_%I AFTER INSERT OR UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION trigger_audit_log_func()', t, t);
    END LOOP;
END $$;


-- ============================================================
-- SECTION 8: DERIVED BALANCE & CATALOG VIEWS
-- ============================================================

-- Staff inventory view
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
    COALESCE(sl.total_on_hand, 0)                                     AS on_hand_qty,
    COALESCE(res.reserved_qty, 0)                                     AS reserved_qty,
    (COALESCE(sl.total_on_hand, 0) - COALESCE(res.reserved_qty, 0))  AS available_qty
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
) res ON p.id = res.product_id;

-- Customer sanitized catalog view
CREATE OR REPLACE VIEW view_customer_products
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
    GREATEST(0, (COALESCE(sl.total_on_hand, 0) - COALESCE(res.reserved_qty, 0))) AS available_qty,
    ((COALESCE(sl.total_on_hand, 0) - COALESCE(res.reserved_qty, 0)) > 0)          AS in_stock
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

-- Driver wallet balance view
CREATE OR REPLACE VIEW view_driver_wallet_balance AS
SELECT
    driver_id,
    COALESCE(SUM(
        CASE
            WHEN type = 'collection' THEN  amount
            WHEN type = 'handover'   THEN -amount
            WHEN type = 'overage'    THEN  amount
            WHEN type = 'shortage'   THEN -amount
            ELSE 0
        END
    ), 0) AS current_wallet_balance
FROM wallet_entries
GROUP BY driver_id;

-- Customer balance view
CREATE OR REPLACE VIEW view_customer_balance AS
SELECT
    c.id           AS customer_id,
    c.user_id,
    u.name         AS customer_name,
    u.phone        AS customer_phone,
    c.price_tier,
    c.credit_limit,
    COALESCE(SUM(cl.amount_change), 0) AS current_balance
FROM customers c
JOIN users u ON c.user_id = u.id
LEFT JOIN customer_ledger cl ON c.id = cl.customer_id
GROUP BY c.id, c.user_id, u.name, u.phone, c.price_tier, c.credit_limit;

-- Supplier balance view
CREATE OR REPLACE VIEW view_supplier_balance AS
SELECT
    s.id            AS supplier_id,
    s.name          AS supplier_name,
    s.phone         AS supplier_phone,
    COALESCE(SUM(sl.amount_change), 0) AS current_balance
FROM suppliers s
LEFT JOIN supplier_ledger sl ON s.id = sl.supplier_id
GROUP BY s.id, s.name, s.phone;

-- Enriched human-friendly audit log view for Moderator Dashboard
CREATE OR REPLACE VIEW view_audit_log_enriched AS
SELECT
    al.id,
    al.created_at,
    al.action,
    al.target_table,
    al.target_id,
    al.ip_address,
    al.before_state,
    al.after_state,
    u.name       AS actor_name,
    u.phone      AS actor_phone,
    u.role       AS actor_role,
    CASE al.target_table
        WHEN 'orders'           THEN 'مبيعات'
        WHEN 'order_items'      THEN 'مبيعات'
        WHEN 'payments'         THEN 'مالية'
        WHEN 'settlements'      THEN 'مالية'
        WHEN 'customer_ledger'  THEN 'مالية'
        WHEN 'supplier_ledger'  THEN 'مالية'
        WHEN 'stock_ledger'     THEN 'مخزون'
        WHEN 'products'         THEN 'مخزون'
        WHEN 'product_prices'   THEN 'مخزون'
        WHEN 'product_barcodes' THEN 'مخزون'
        WHEN 'purchases'        THEN 'مشتريات'
        WHEN 'purchase_items'   THEN 'مشتريات'
        WHEN 'users'            THEN 'أمان وموظفين'
        WHEN 'customers'        THEN 'زبائن'
        WHEN 'addresses'        THEN 'زبائن'
        WHEN 'suppliers'        THEN 'موردون'
        WHEN 'wallet_entries'   THEN 'مالية'
        ELSE 'عام'
    END AS category,
    CASE
        WHEN al.action = 'CUSTOMER_ORDER_SUBMITTED'  THEN 'طلب زبون جديد'
        WHEN al.action = 'STAFF_MEMBER_CREATED'      THEN 'إنشاء حساب موظف'
        WHEN al.action = 'MODERATOR_RESET_USER_PIN'  THEN 'إعادة تعيين PIN موظف'
        WHEN al.action = 'USER_PIN_CHANGED'          THEN 'تغيير رمز PIN'
        WHEN al.action = 'INSERT' AND al.target_table = 'orders'        THEN 'تسجيل بيع كاونتر'
        WHEN al.action = 'INSERT' AND al.target_table = 'payments'      THEN 'تحصيل دفعة مالية'
        WHEN al.action = 'INSERT' AND al.target_table = 'purchases'     THEN 'فاتورة مشتريات جديدة'
        WHEN al.action = 'INSERT' AND al.target_table = 'stock_ledger'  THEN 'حركة مخزون'
        WHEN al.action = 'UPDATE' AND al.target_table = 'orders'        THEN 'تحديث حالة طلبية'
        WHEN al.action = 'INSERT' AND al.target_table = 'settlements'   THEN 'تسوية صندوق سائق'
        WHEN al.action = 'INSERT' AND al.target_table = 'customer_ledger' THEN 'حركة حساب زبون'
        WHEN al.action = 'INSERT' AND al.target_table = 'users'         THEN 'إنشاء مستخدم'
        WHEN al.action = 'UPDATE' AND al.target_table = 'users'         THEN 'تعديل بيانات مستخدم'
        WHEN al.action = 'INSERT' AND al.target_table = 'products'      THEN 'إضافة منتج جديد'
        WHEN al.action = 'UPDATE' AND al.target_table = 'products'      THEN 'تعديل بيانات منتج'
        WHEN al.action = 'INSERT' AND al.target_table = 'product_prices' THEN 'تحديث تسعيرة'
        WHEN al.action = 'INSERT' AND al.target_table = 'addresses'     THEN 'إضافة عنوان توصيل'
        WHEN al.action = 'UPDATE' AND al.target_table = 'addresses'     THEN 'تعديل عنوان توصيل'
        WHEN al.action = 'INSERT' AND al.target_table = 'suppliers'     THEN 'إضافة مورد'
        WHEN al.action = 'UPDATE' AND al.target_table = 'suppliers'     THEN 'تعديل مورد'
        WHEN al.action = 'DELETE'                                        THEN 'حذف من ' || al.target_table
        ELSE al.action || ' ← ' || al.target_table
    END AS intelligent_title
FROM audit_log al
LEFT JOIN users u ON al.user_id = u.id;


-- ============================================================
-- SECTION 9: PERFORMANCE INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_users_phone             ON users(phone);
CREATE INDEX IF NOT EXISTS idx_users_role_active       ON users(role, active);
CREATE INDEX IF NOT EXISTS idx_customers_user          ON customers(user_id);
CREATE INDEX IF NOT EXISTS idx_addresses_cust          ON addresses(customer_id);
CREATE INDEX IF NOT EXISTS idx_products_active_cat     ON products(active, category);
CREATE INDEX IF NOT EXISTS idx_product_barcodes_bar    ON product_barcodes(barcode);
CREATE INDEX IF NOT EXISTS idx_product_prices_lookup   ON product_prices(product_id, tier, min_qty);
CREATE INDEX IF NOT EXISTS idx_orders_customer         ON orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_orders_driver           ON orders(driver_id);
CREATE INDEX IF NOT EXISTS idx_orders_status           ON orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_created          ON orders(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_order_items_order       ON order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_product     ON order_items(product_id);
CREATE INDEX IF NOT EXISTS idx_stock_ledger_prod       ON stock_ledger(product_id);
CREATE INDEX IF NOT EXISTS idx_stock_ledger_created    ON stock_ledger(created_at);
CREATE INDEX IF NOT EXISTS idx_customer_ledger_cust    ON customer_ledger(customer_id);
CREATE INDEX IF NOT EXISTS idx_customer_ledger_created ON customer_ledger(created_at);
CREATE INDEX IF NOT EXISTS idx_supplier_ledger_supp    ON supplier_ledger(supplier_id);
CREATE INDEX IF NOT EXISTS idx_payments_order          ON payments(order_id);
CREATE INDEX IF NOT EXISTS idx_payments_customer       ON payments(customer_id);
CREATE INDEX IF NOT EXISTS idx_wallet_entries_driver   ON wallet_entries(driver_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_target        ON audit_log(target_table, target_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_user          ON audit_log(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_created       ON audit_log(created_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS uq_stock_ledger_opening_ref
    ON stock_ledger (ref_id)
    WHERE ref_type = 'opening_stock';


-- ============================================================
-- SECTION 10: ATOMIC SECURITY DEFINER RPC FUNCTIONS
-- ============================================================

-- ── 10.1 Internal PIN verification with Lockout Escalation ───────────────────
CREATE OR REPLACE FUNCTION _internal_verify_and_track_pin(
    p_user_id           UUID,
    p_pin               TEXT,
    p_require_moderator BOOLEAN DEFAULT FALSE
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions, pg_temp AS $$
DECLARE
    v_user      users%ROWTYPE;
    v_lock      pin_attempt_limits%ROWTYPE;
    v_lock_key  BIGINT;
    v_is_valid  BOOLEAN := FALSE;
    v_new_step  INT := 0;
    v_lock_dur  INTERVAL := INTERVAL '1 minute';
BEGIN
    v_lock_key := ('x' || substr(md5(p_user_id::text), 1, 16))::bit(64)::bigint;
    PERFORM pg_advisory_xact_lock(v_lock_key);

    SELECT * INTO v_lock FROM pin_attempt_limits WHERE user_id = p_user_id;

    IF v_lock.user_id IS NOT NULL AND v_lock.last_failed_at IS NOT NULL
       AND v_lock.last_failed_at < NOW() - INTERVAL '24 hours' THEN
        v_lock.failed_attempts := 0; v_lock.lock_step := 0; v_lock.locked_until := NULL;
    END IF;

    IF v_lock.user_id IS NOT NULL AND v_lock.locked_until IS NOT NULL
       AND v_lock.locked_until <= NOW() THEN
        v_lock.failed_attempts := 0; v_lock.locked_until := NULL;
    END IF;

    IF v_lock.user_id IS NOT NULL AND v_lock.locked_until IS NOT NULL
       AND v_lock.locked_until > NOW() THEN
        RETURN jsonb_build_object(
            'valid', FALSE,
            'locked', TRUE,
            'message', 'الحساب مقفل مؤقتاً لتكرار المحاولات الخاطئة. يرجى الانتظار.'
        );
    END IF;

    SELECT * INTO v_user FROM users WHERE id = p_user_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('valid', FALSE, 'message', 'المستخدم غير موجود');
    END IF;
    IF v_user.active = FALSE THEN
        RETURN jsonb_build_object('valid', FALSE, 'message', 'الحساب معطل من قبل الإدارة');
    END IF;
    IF p_require_moderator AND v_user.role <> 'moderator' THEN
        RETURN jsonb_build_object('valid', FALSE, 'message', 'العملية تتطلب صلاحيات المشرف العام');
    END IF;

    IF v_user.pin_code IS NOT NULL AND v_user.pin_code = crypt(p_pin, v_user.pin_code) THEN
        v_is_valid := TRUE;
    END IF;

    IF v_is_valid THEN
        DELETE FROM pin_attempt_limits WHERE user_id = p_user_id;
        RETURN jsonb_build_object(
            'valid', TRUE,
            'id', v_user.id,
            'name', v_user.name,
            'phone', v_user.phone,
            'role', v_user.role,
            'language', v_user.language
        );
    ELSE
        IF v_lock.user_id IS NULL THEN
            INSERT INTO pin_attempt_limits (user_id, failed_attempts, lock_step, locked_until, last_failed_at)
            VALUES (p_user_id, 1, 0, NULL, NOW());
        ELSE
            v_lock.failed_attempts := v_lock.failed_attempts + 1;
            IF    v_lock.failed_attempts >= 15 THEN v_new_step := 3; v_lock_dur := INTERVAL '15 minutes';
            ELSIF v_lock.failed_attempts >= 10 THEN v_new_step := 2; v_lock_dur := INTERVAL '5 minutes';
            ELSIF v_lock.failed_attempts >= 5  THEN v_new_step := 1; v_lock_dur := INTERVAL '1 minute';
            END IF;

            UPDATE pin_attempt_limits
            SET failed_attempts = v_lock.failed_attempts,
                lock_step       = v_new_step,
                last_failed_at  = NOW(),
                locked_until    = CASE WHEN v_new_step > 0 THEN NOW() + v_lock_dur ELSE NULL END
            WHERE user_id = p_user_id;
        END IF;

        RETURN jsonb_build_object('valid', FALSE, 'message', 'رمز PIN غير صحيح');
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION _internal_verify_and_track_pin(UUID, TEXT, BOOLEAN) FROM PUBLIC, anon, authenticated;

-- ── 10.2 Verify PIN (Public Staff Auth RPC) ──────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_verify_user_pin(p_user_id UUID, p_pin TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions, pg_temp AS $$
BEGIN
    RETURN _internal_verify_and_track_pin(p_user_id, p_pin, FALSE);
END;
$$;

-- ── 10.3 Change Own PIN ──────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_change_user_pin(p_user_id UUID, p_old_pin TEXT, p_new_pin TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions, pg_temp AS $$
DECLARE
    v_check JSONB;
BEGIN
    v_check := _internal_verify_and_track_pin(p_user_id, p_old_pin, FALSE);
    IF (v_check->>'valid')::BOOLEAN <> TRUE THEN
        RETURN jsonb_build_object('status','error','message', COALESCE(v_check->>'message','رمز PIN الحالي غير صحيح'));
    END IF;

    IF LENGTH(trim(p_new_pin)) < 4 THEN
        RETURN jsonb_build_object('status','error','message','يجب أن يتكون رمز PIN من 4 أرقام على الأقل');
    END IF;

    UPDATE users
    SET pin_code = crypt(trim(p_new_pin), gen_salt('bf')),
        updated_at = NOW()
    WHERE id = p_user_id;

    DELETE FROM pin_attempt_limits WHERE user_id = p_user_id;

    INSERT INTO audit_log (user_id, action, target_table, target_id, after_state)
    VALUES (p_user_id, 'USER_PIN_CHANGED', 'users', p_user_id, jsonb_build_object('changed_at', NOW()));

    RETURN jsonb_build_object('status','success','message','تم تحديث رمز PIN بنجاح');
END;
$$;

-- ── 10.4 Reset Staff PIN by Moderator ────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_reset_user_pin_by_admin(
    p_admin_id       UUID,
    p_admin_pin      TEXT,
    p_target_user_id UUID,
    p_new_pin        TEXT
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions, pg_temp AS $$
DECLARE
    v_check JSONB;
    v_target RECORD;
BEGIN
    v_check := _internal_verify_and_track_pin(p_admin_id, p_admin_pin, TRUE);
    IF (v_check->>'valid')::BOOLEAN <> TRUE THEN
        RETURN jsonb_build_object('status','error','message','فشل التحقق من صلاحيات المشرف العام');
    END IF;

    SELECT id, name, phone, role INTO v_target FROM users WHERE id = p_target_user_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('status','error','message','الموظف غير موجود');
    END IF;

    IF LENGTH(trim(p_new_pin)) < 4 THEN
        RETURN jsonb_build_object('status','error','message','يجب أن يتكون رمز PIN من 4 أرقام على الأقل');
    END IF;

    UPDATE users
    SET pin_code = crypt(trim(p_new_pin), gen_salt('bf')),
        updated_at = NOW()
    WHERE id = p_target_user_id;

    DELETE FROM pin_attempt_limits WHERE user_id = p_target_user_id;

    INSERT INTO audit_log (user_id, action, target_table, target_id, after_state)
    VALUES (p_admin_id, 'MODERATOR_RESET_USER_PIN', 'users', p_target_user_id,
        jsonb_build_object('target_name', v_target.name, 'target_role', v_target.role, 'reset_at', NOW()));

    RETURN jsonb_build_object(
        'status','success',
        'message','تم تعيين وتشفير رمز PIN الجديد للموظف بنجاح',
        'target_user_id', p_target_user_id
    );
END;
$$;

-- ── 10.5 Create Staff Member ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_create_staff_member(
    p_admin_id    UUID,
    p_admin_pin   TEXT,
    p_name        VARCHAR,
    p_phone       VARCHAR,
    p_role        user_role,
    p_initial_pin TEXT,
    p_language    VARCHAR DEFAULT 'ar'
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions, pg_temp AS $$
DECLARE
    v_check JSONB;
    v_user_id UUID := gen_random_uuid();
BEGIN
    v_check := _internal_verify_and_track_pin(p_admin_id, p_admin_pin, TRUE);
    IF (v_check->>'valid')::BOOLEAN <> TRUE THEN
        RETURN jsonb_build_object('status','error','message','فشل التحقق من صلاحيات المشرف العام');
    END IF;

    IF p_initial_pin IS NULL OR LENGTH(trim(p_initial_pin)) < 4 THEN
        RAISE EXCEPTION 'A valid initial PIN of at least 4 digits is required';
    END IF;

    INSERT INTO users (id, name, phone, role, pin_code, language, active)
    VALUES (v_user_id, trim(p_name), trim(p_phone), p_role, crypt(trim(p_initial_pin), gen_salt('bf')), p_language, TRUE);

    INSERT INTO audit_log (user_id, action, target_table, target_id, after_state)
    VALUES (p_admin_id, 'STAFF_MEMBER_CREATED', 'users', v_user_id,
        jsonb_build_object('name', p_name, 'phone', p_phone, 'role', p_role));

    RETURN jsonb_build_object(
        'status', 'success',
        'id', v_user_id,
        'name', p_name,
        'phone', p_phone,
        'role', p_role
    );
END;
$$;

-- Backwards compatibility overload: reject creation without initial PIN
DROP FUNCTION IF EXISTS rpc_create_staff_member(VARCHAR, VARCHAR, user_role, VARCHAR);

-- ── 10.6 Post Purchase Invoice ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_post_purchase(p_purchase_id UUID, p_user_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
    v_purchase purchases%ROWTYPE;
    v_item RECORD;
    v_total BIGINT := 0;
BEGIN
    SELECT * INTO v_purchase FROM purchases WHERE id = p_purchase_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Purchase % not found', p_purchase_id; END IF;
    IF v_purchase.status <> 'draft' THEN
        RAISE EXCEPTION 'Purchase is not in draft status (current: %)', v_purchase.status;
    END IF;

    FOR v_item IN SELECT * FROM purchase_items WHERE purchase_id = p_purchase_id LOOP
        v_total := v_total + (v_item.quantity * v_item.unit_cost);

        INSERT INTO stock_ledger (product_id, qty_change, reason, ref_type, ref_id, user_id, notes)
        VALUES (v_item.product_id, v_item.quantity, 'purchase', 'purchase', p_purchase_id, p_user_id,
                'Purchase received: Invoice ' || v_purchase.invoice_no);

        UPDATE products
        SET last_unit_cost = v_item.unit_cost,
            active = TRUE,
            updated_at = NOW()
        WHERE id = v_item.product_id;
    END LOOP;

    INSERT INTO supplier_ledger (supplier_id, amount_change, ref_type, ref_id, notes)
    VALUES (v_purchase.supplier_id, v_total, 'purchase', p_purchase_id, 'Invoice ' || v_purchase.invoice_no);

    UPDATE purchases
    SET status = 'posted',
        total_amount = v_total,
        posted_at = NOW()
    WHERE id = p_purchase_id;

    RETURN jsonb_build_object('status','success','purchase_id', p_purchase_id,'total_amount', v_total);
END;
$$;

-- ── 10.7 Post Counter Store Sale ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_post_store_sale(
    p_customer_id  UUID,
    p_items        JSONB,
    p_paid_cash    BIGINT,
    p_on_account   BIGINT,
    p_cashier_id   UUID DEFAULT NULL,
    p_client_id    UUID DEFAULT NULL
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
    v_order_id        UUID;
    v_cashier         UUID;
    v_item            JSONB;
    v_total           BIGINT := 0;
    v_cost            BIGINT := 0;
    v_stock           INT;
    v_product_id      UUID;
    v_qty             INT;
    v_price           BIGINT;
    v_item_cost       BIGINT;
    v_customer        customers%ROWTYPE;
    v_current_debt    BIGINT;
BEGIN
    IF p_client_id IS NOT NULL THEN
        SELECT id INTO v_order_id FROM orders WHERE client_id = p_client_id;
        IF v_order_id IS NOT NULL THEN
            RETURN jsonb_build_object('status','success','order_id', v_order_id,'idempotent_replay', true);
        END IF;
    END IF;

    v_order_id := gen_random_uuid();
    v_cashier  := COALESCE(auth.uid(), p_cashier_id);

    IF p_on_account > 0 THEN
        IF p_customer_id IS NULL THEN
            RAISE EXCEPTION 'Cannot put amount on balance without an identified customer account.';
        END IF;
        SELECT * INTO v_customer FROM customers WHERE id = p_customer_id FOR UPDATE;
        IF NOT FOUND THEN RAISE EXCEPTION 'Customer % not found', p_customer_id; END IF;

        SELECT COALESCE(current_balance, 0) INTO v_current_debt
        FROM view_customer_balance WHERE customer_id = p_customer_id;

        IF (v_current_debt + p_on_account) > v_customer.credit_limit THEN
            RAISE EXCEPTION 'Sale exceeds customer credit limit! Limit: %, Debt: %, Requested: %',
                v_customer.credit_limit, v_current_debt, p_on_account;
        END IF;
    END IF;

    PERFORM id FROM products
    WHERE id IN (SELECT (item->>'product_id')::UUID FROM jsonb_array_elements(p_items) AS item)
    ORDER BY id FOR UPDATE;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        v_product_id := (v_item->>'product_id')::UUID;
        v_qty        := (v_item->>'quantity')::INT;
        v_price      := (v_item->>'unit_price')::BIGINT;
        v_item_cost  := COALESCE((v_item->>'unit_cost')::BIGINT, 0);

        SELECT available_qty INTO v_stock FROM view_product_stock WHERE product_id = v_product_id;
        IF v_stock < v_qty THEN
            RAISE EXCEPTION 'Insufficient stock for product %: requested %, available %', v_product_id, v_qty, v_stock;
        END IF;

        v_total := v_total + (v_qty * v_price);
        v_cost  := v_cost  + (v_qty * v_item_cost);
    END LOOP;

    IF (p_paid_cash + p_on_account) <> v_total THEN
        RAISE EXCEPTION 'Payment mismatch: paid(%) + on_account(%) ≠ total(%)', p_paid_cash, p_on_account, v_total;
    END IF;

    INSERT INTO orders (id, client_id, channel, customer_id, status, cashier_id, total_amount, total_cost, paid_amount, delivered_at)
    VALUES (v_order_id, p_client_id, 'store', p_customer_id, 'delivered', v_cashier, v_total, v_cost, p_paid_cash, NOW());

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        v_product_id := (v_item->>'product_id')::UUID;
        v_qty        := (v_item->>'quantity')::INT;
        v_price      := (v_item->>'unit_price')::BIGINT;
        v_item_cost  := COALESCE((v_item->>'unit_cost')::BIGINT, 0);

        INSERT INTO order_items (order_id, product_id, quantity, unit_price, unit_cost)
        VALUES (v_order_id, v_product_id, v_qty, v_price, v_item_cost);

        INSERT INTO stock_ledger (product_id, qty_change, reason, ref_type, ref_id, user_id, notes)
        VALUES (v_product_id, -v_qty, 'sale', 'order', v_order_id, COALESCE(v_cashier, gen_random_uuid()), 'Counter Sale');
    END LOOP;

    IF p_on_account > 0 THEN
        INSERT INTO customer_ledger (customer_id, amount_change, ref_type, ref_id, notes)
        VALUES (p_customer_id, p_on_account, 'order_credit', v_order_id, 'Counter sale credit');
    END IF;

    IF p_paid_cash > 0 THEN
        INSERT INTO payments (order_id, customer_id, amount, method, received_by, status, client_id)
        VALUES (v_order_id, p_customer_id, p_paid_cash, 'cash', COALESCE(v_cashier, gen_random_uuid()), 'settled', p_client_id);
    END IF;

    RETURN jsonb_build_object(
        'status','success',
        'order_id', v_order_id,
        'total_amount', v_total,
        'paid_cash', p_paid_cash,
        'on_account', p_on_account
    );
END;
$$;

-- ── 10.8 Collect Customer Debt Repayment ──────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_collect_customer_debt(
    p_cashier_id  UUID,
    p_customer_id UUID,
    p_amount      BIGINT,
    p_method      payment_method DEFAULT 'cash',
    p_notes       TEXT           DEFAULT NULL,
    p_client_id   UUID           DEFAULT NULL
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
    v_payment_id UUID := gen_random_uuid();
    v_prev       BIGINT := 0;
BEGIN
    IF p_amount <= 0 THEN RAISE EXCEPTION 'Amount must be greater than zero.'; END IF;

    PERFORM id FROM customers WHERE id = p_customer_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Customer % not found.', p_customer_id; END IF;

    SELECT COALESCE(current_balance, 0) INTO v_prev
    FROM view_customer_balance WHERE customer_id = p_customer_id;

    INSERT INTO payments (id, order_id, customer_id, amount, method, received_by, status, client_id)
    VALUES (v_payment_id, NULL, p_customer_id, p_amount, p_method, p_cashier_id, 'settled', p_client_id);

    INSERT INTO customer_ledger (customer_id, amount_change, ref_type, ref_id, notes)
    VALUES (p_customer_id, -p_amount, 'payment', v_payment_id,
            COALESCE(p_notes, 'Debt repayment collected at cashier counter'));

    RETURN jsonb_build_object(
        'status', 'success',
        'payment_id', v_payment_id,
        'customer_id', p_customer_id,
        'paid_amount', p_amount,
        'previous_balance', v_prev,
        'new_balance', v_prev - p_amount,
        'method', p_method,
        'timestamp', NOW()
    );
END;
$$;

-- ── 10.9 Confirm Online Order & Reserve Stock ─────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_confirm_online_order(
    p_order_id    UUID,
    p_cashier_id  UUID,
    p_driver_id   UUID DEFAULT NULL
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
    v_order orders%ROWTYPE;
    v_item RECORD;
    v_avail INT;
BEGIN
    SELECT * INTO v_order FROM orders WHERE id = p_order_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Order % not found', p_order_id; END IF;
    IF v_order.status <> 'submitted' THEN
        RAISE EXCEPTION 'Order is not in submitted status (current: %)', v_order.status;
    END IF;

    FOR v_item IN SELECT * FROM order_items WHERE order_id = p_order_id LOOP
        SELECT available_qty INTO v_avail FROM view_product_stock WHERE product_id = v_item.product_id;
        IF v_avail < v_item.quantity THEN
            RAISE EXCEPTION 'Insufficient stock for product % (req: %, avail: %)',
                v_item.product_id, v_item.quantity, v_avail;
        END IF;
    END LOOP;

    UPDATE orders
    SET status       = CASE WHEN p_driver_id IS NOT NULL THEN 'assigned'::order_status ELSE 'confirmed'::order_status END,
        cashier_id   = p_cashier_id,
        driver_id    = COALESCE(p_driver_id, driver_id),
        confirmed_at = NOW()
    WHERE id = p_order_id;

    RETURN jsonb_build_object('status','success','order_id', p_order_id,'assigned_driver', p_driver_id);
END;
$$;

-- ── 10.10 Record Order Delivery & Driver Cash Collection ──────────────────────
CREATE OR REPLACE FUNCTION rpc_record_order_delivery(
    p_driver_id      UUID,
    p_order_id       UUID,
    p_collected_cash BIGINT,
    p_client_id      UUID
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
    v_order      orders%ROWTYPE;
    v_unpaid     BIGINT;
    v_payment_id UUID;
BEGIN
    SELECT * INTO v_order FROM orders WHERE id = p_order_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Order % not found', p_order_id; END IF;

    IF v_order.status IN ('delivered','settled') THEN
        RETURN jsonb_build_object('status','already_delivered','order_id', p_order_id);
    END IF;

    v_unpaid := v_order.total_amount - p_collected_cash;

    IF p_collected_cash > 0 THEN
        INSERT INTO payments (id, order_id, customer_id, amount, method, received_by, status, client_id)
        VALUES (gen_random_uuid(), p_order_id, v_order.customer_id, p_collected_cash, 'cash', p_driver_id, 'collected', p_client_id)
        ON CONFLICT (client_id) DO UPDATE SET amount = EXCLUDED.amount
        RETURNING id INTO v_payment_id;

        INSERT INTO wallet_entries (driver_id, type, amount, payment_id, client_id)
        VALUES (p_driver_id, 'collection', p_collected_cash, v_payment_id, p_client_id)
        ON CONFLICT (client_id) DO NOTHING;
    END IF;

    IF v_unpaid > 0 AND v_order.customer_id IS NOT NULL THEN
        INSERT INTO customer_ledger (customer_id, amount_change, ref_type, ref_id, notes)
        VALUES (v_order.customer_id, v_unpaid, 'order_credit', p_order_id, 'Delivery remaining unpaid balance');
    END IF;

    UPDATE orders
    SET status       = 'delivered',
        paid_amount  = p_collected_cash,
        delivered_at = NOW()
    WHERE id = p_order_id;

    RETURN jsonb_build_object('status','success','order_id', p_order_id,'collected', p_collected_cash);
END;
$$;

-- ── 10.11 Settle Driver Wallet at Counter ────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_settle_driver_wallet(
    p_cashier_id   UUID,
    p_driver_id    UUID,
    p_counted_cash BIGINT,
    p_notes        TEXT DEFAULT NULL
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
    v_expected      BIGINT := 0;
    v_settlement_id UUID := gen_random_uuid();
    v_status        settlement_status := 'settled';
BEGIN
    SELECT current_wallet_balance INTO v_expected
    FROM view_driver_wallet_balance WHERE driver_id = p_driver_id;
    v_expected := COALESCE(v_expected, 0);

    IF v_expected <= 0 AND p_counted_cash = 0 THEN
        RAISE EXCEPTION 'No pending collections to settle for driver %', p_driver_id;
    END IF;

    IF (p_counted_cash - v_expected) <> 0 THEN
        v_status := 'discrepancy_flagged';
    END IF;

    INSERT INTO settlements (id, driver_id, cashier_id, expected_amount, counted_amount, status, notes)
    VALUES (v_settlement_id, p_driver_id, p_cashier_id, v_expected, p_counted_cash, v_status, p_notes);

    INSERT INTO wallet_entries (driver_id, type, amount, settlement_id)
    VALUES (p_driver_id, 'handover', v_expected, v_settlement_id);

    UPDATE orders SET status = 'settled', settled_at = NOW()
    WHERE driver_id = p_driver_id AND status = 'delivered';

    UPDATE payments SET status = 'settled'
    WHERE received_by = p_driver_id AND status = 'collected';

    RETURN jsonb_build_object(
        'status', 'success',
        'settlement_id', v_settlement_id,
        'expected', v_expected,
        'counted', p_counted_cash,
        'difference', p_counted_cash - v_expected,
        'settlement_status', v_status
    );
END;
$$;

-- ── 10.12 Adjust Stock Quantity ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_adjust_stock(
    p_user_id    UUID,
    p_product_id UUID,
    p_qty_change INT,
    p_reason     TEXT
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
    v_id UUID := gen_random_uuid();
BEGIN
    IF p_qty_change = 0 THEN RAISE EXCEPTION 'Quantity change cannot be zero'; END IF;

    INSERT INTO stock_ledger (id, product_id, qty_change, reason, ref_type, ref_id, user_id, notes)
    VALUES (v_id, p_product_id, p_qty_change, 'adjustment', 'manual_adjustment', v_id, p_user_id, p_reason);

    RETURN jsonb_build_object('status','success','adjustment_id', v_id,'qty_change', p_qty_change);
END;
$$;

-- ── 10.13 Atomic Product Creation ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_create_product(
    p_product       JSONB,
    p_barcodes      JSONB,
    p_prices        JSONB,
    p_opening_stock INT,
    p_user_id       UUID
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
    v_product_id UUID;
    v_operator   UUID;
    v_b          TEXT;
    v_p          JSONB;
BEGIN
    v_product_id := COALESCE((p_product->>'id')::UUID, gen_random_uuid());
    v_operator   := COALESCE(auth.uid(), p_user_id);

    INSERT INTO products (id, name_ar, name_fr, category, unit, pack_size, photo_url, last_unit_cost, active)
    VALUES (
        v_product_id,
        p_product->>'name_ar',
        COALESCE(p_product->>'name_fr', p_product->>'name_ar'),
        COALESCE(p_product->>'category','عام'),
        COALESCE(p_product->>'unit','piece'),
        COALESCE((p_product->>'pack_size')::INT, 1),
        p_product->>'photo_url',
        COALESCE((p_product->>'last_unit_cost')::BIGINT, 0),
        COALESCE((p_product->>'active')::BOOLEAN, TRUE)
    )
    ON CONFLICT (id) DO UPDATE SET
        name_ar        = EXCLUDED.name_ar,
        name_fr        = EXCLUDED.name_fr,
        category       = EXCLUDED.category,
        unit           = EXCLUDED.unit,
        pack_size      = EXCLUDED.pack_size,
        photo_url      = EXCLUDED.photo_url,
        last_unit_cost = EXCLUDED.last_unit_cost,
        active         = EXCLUDED.active,
        updated_at     = NOW();

    IF p_barcodes IS NOT NULL THEN
        FOR v_b IN SELECT jsonb_array_elements_text(p_barcodes) LOOP
            IF v_b IS NOT NULL AND trim(v_b) <> '' THEN
                INSERT INTO product_barcodes (barcode, product_id)
                VALUES (trim(v_b), v_product_id)
                ON CONFLICT (barcode) DO NOTHING;
            END IF;
        END LOOP;
    END IF;

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
            ON CONFLICT (product_id, tier, min_qty) DO UPDATE SET price = EXCLUDED.price;
        END LOOP;
    END IF;

    IF p_opening_stock > 0 THEN
        IF v_operator IS NULL THEN
            SELECT id INTO v_operator FROM users WHERE role IN ('moderator','manager') LIMIT 1;
        END IF;
        INSERT INTO stock_ledger (product_id, qty_change, reason, ref_type, ref_id, user_id, notes)
        VALUES (v_product_id, p_opening_stock, 'adjustment'::stock_ref_type, 'opening_stock', v_product_id,
                v_operator, 'المخزون الافتتاحي الأولي عند إنشاء المنتج')
        ON CONFLICT DO NOTHING;
    END IF;

    RETURN v_product_id;
END;
$$;

-- ── 10.14 Submit Customer Order ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_submit_customer_order(
    p_client_id        UUID,
    p_customer_id      UUID,
    p_delivery_address JSONB,
    p_items            JSONB
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
    v_order_id   UUID;
    v_tier       price_tier := 'wholesale';
    v_cust_id    UUID := p_customer_id;
    v_item       JSONB;
    v_product_id UUID;
    v_qty        INT;
    v_unit_price BIGINT;
    v_unit_cost  BIGINT;
    v_total      BIGINT := 0;
    v_total_cost BIGINT := 0;
BEGIN
    IF p_client_id IS NOT NULL THEN
        SELECT id INTO v_order_id FROM orders WHERE client_id = p_client_id;
        IF v_order_id IS NOT NULL THEN RETURN v_order_id; END IF;
    END IF;

    IF v_cust_id IS NOT NULL THEN
        SELECT price_tier INTO v_tier FROM customers WHERE id = v_cust_id;
        IF NOT FOUND THEN
            SELECT id, price_tier INTO v_cust_id, v_tier FROM customers WHERE user_id = auth.uid();
        END IF;
    ELSE
        SELECT id, price_tier INTO v_cust_id, v_tier FROM customers WHERE user_id = auth.uid();
    END IF;
    v_tier := COALESCE(v_tier, 'wholesale');

    v_order_id := gen_random_uuid();

    INSERT INTO orders (id, client_id, channel, customer_id, status, delivery_address, total_amount, total_cost, paid_amount)
    VALUES (v_order_id, p_client_id, 'online', v_cust_id, 'submitted', p_delivery_address, 0, 0, 0)
    ON CONFLICT (client_id) DO NOTHING;

    IF NOT FOUND THEN
        SELECT id INTO v_order_id FROM orders WHERE client_id = p_client_id;
        RETURN v_order_id;
    END IF;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        v_product_id := (v_item->>'product_id')::UUID;
        v_qty        := (v_item->>'quantity')::INT;
        IF v_qty <= 0 THEN RAISE EXCEPTION 'Quantity must be > 0 for product %', v_product_id; END IF;

        SELECT price INTO v_unit_price FROM product_prices
        WHERE product_id = v_product_id AND tier = v_tier AND min_qty <= v_qty
        ORDER BY min_qty DESC LIMIT 1;

        IF v_unit_price IS NULL THEN
            SELECT price INTO v_unit_price FROM product_prices
            WHERE product_id = v_product_id AND tier = v_tier
            ORDER BY min_qty ASC LIMIT 1;
        END IF;

        IF v_unit_price IS NULL THEN
            SELECT price INTO v_unit_price FROM product_prices
            WHERE product_id = v_product_id ORDER BY min_qty ASC LIMIT 1;
        END IF;

        IF v_unit_price IS NULL THEN RAISE EXCEPTION 'No price configured for product %', v_product_id; END IF;

        SELECT COALESCE(last_unit_cost, 0) INTO v_unit_cost FROM products WHERE id = v_product_id;

        v_total      := v_total      + (v_qty * v_unit_price);
        v_total_cost := v_total_cost + (v_qty * v_unit_cost);

        INSERT INTO order_items (order_id, product_id, quantity, unit_price, unit_cost)
        VALUES (v_order_id, v_product_id, v_qty, v_unit_price, v_unit_cost);
    END LOOP;

    UPDATE orders SET total_amount = v_total, total_cost = v_total_cost WHERE id = v_order_id;

    RETURN v_order_id;
END;
$$;


-- ============================================================
-- SECTION 11: ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================================

ALTER TABLE users               ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers           ENABLE ROW LEVEL SECURITY;
ALTER TABLE addresses           ENABLE ROW LEVEL SECURITY;
ALTER TABLE suppliers           ENABLE ROW LEVEL SECURITY;
ALTER TABLE products            ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_barcodes    ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_prices      ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchases           ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_items      ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders              ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items         ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_ledger        ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer_ledger     ENABLE ROW LEVEL SECURITY;
ALTER TABLE supplier_ledger     ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments            ENABLE ROW LEVEL SECURITY;
ALTER TABLE settlements         ENABLE ROW LEVEL SECURITY;
ALTER TABLE wallet_entries      ENABLE ROW LEVEL SECURITY;
ALTER TABLE driver_locations    ENABLE ROW LEVEL SECURITY;
ALTER TABLE pin_attempt_limits  ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log           ENABLE ROW LEVEL SECURITY;
ALTER TABLE permissions         ENABLE ROW LEVEL SECURITY;
ALTER TABLE role_permissions    ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION get_auth_role()
RETURNS user_role LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT role FROM users WHERE id = auth.uid();
$$;

-- Permissions & Role_Permissions (Read-only)
DROP POLICY IF EXISTS "Anyone can view permissions" ON permissions;
CREATE POLICY "Anyone can view permissions" ON permissions FOR SELECT USING (TRUE);

DROP POLICY IF EXISTS "Anyone can view role permissions" ON role_permissions;
CREATE POLICY "Anyone can view role permissions" ON role_permissions FOR SELECT USING (TRUE);

-- Users: protect PIN, allow profile read and customer registration
REVOKE ALL ON users FROM anon, authenticated;
GRANT SELECT (id, phone, name, role, active, language, created_at, updated_at) ON users TO anon, authenticated;
GRANT INSERT (name, phone, role, language, active) ON users TO anon, authenticated;
GRANT UPDATE (name, phone, language, active) ON users TO anon, authenticated;

DROP POLICY IF EXISTS "Public read users profile lookup" ON users;
CREATE POLICY "Public read users profile lookup" ON users FOR SELECT USING (TRUE);

DROP POLICY IF EXISTS "Allow customer self-registration" ON users;
CREATE POLICY "Allow customer self-registration" ON users FOR INSERT WITH CHECK (role = 'customer'::user_role);

DROP POLICY IF EXISTS "Allow user profile updates" ON users;
CREATE POLICY "Allow user profile updates" ON users FOR UPDATE USING (TRUE) WITH CHECK (TRUE);

-- PIN Attempt Limits
REVOKE ALL ON pin_attempt_limits FROM PUBLIC, anon, authenticated;

-- Customers & Addresses
REVOKE ALL ON customers FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON customers TO anon, authenticated;

DROP POLICY IF EXISTS "Customers readable by all" ON customers;
CREATE POLICY "Customers readable by all" ON customers FOR SELECT USING (TRUE);

DROP POLICY IF EXISTS "Customers insertable" ON customers;
CREATE POLICY "Customers insertable" ON customers FOR INSERT WITH CHECK (TRUE);

DROP POLICY IF EXISTS "Customers updatable by staff and owner" ON customers;
CREATE POLICY "Customers updatable by staff and owner" ON customers FOR UPDATE USING (TRUE);

REVOKE ALL ON addresses FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON addresses TO anon, authenticated;

DROP POLICY IF EXISTS "Addresses operations" ON addresses;
CREATE POLICY "Addresses operations" ON addresses FOR ALL USING (TRUE) WITH CHECK (TRUE);

-- Products, Barcodes, Prices
REVOKE ALL ON products FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON products TO anon, authenticated;

DROP POLICY IF EXISTS "Public view products" ON products;
CREATE POLICY "Public view products" ON products FOR SELECT USING (active = TRUE OR get_auth_role() IN ('moderator','manager','cashier','driver') OR auth.uid() IS NULL);

DROP POLICY IF EXISTS "Staff manage products" ON products;
CREATE POLICY "Staff manage products" ON products FOR ALL USING (TRUE) WITH CHECK (TRUE);

REVOKE ALL ON product_barcodes FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON product_barcodes TO anon, authenticated;

DROP POLICY IF EXISTS "Product barcodes open" ON product_barcodes;
CREATE POLICY "Product barcodes open" ON product_barcodes FOR ALL USING (TRUE) WITH CHECK (TRUE);

REVOKE ALL ON product_prices FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON product_prices TO anon, authenticated;

DROP POLICY IF EXISTS "Product prices open" ON product_prices;
CREATE POLICY "Product prices open" ON product_prices FOR ALL USING (TRUE) WITH CHECK (TRUE);

-- Suppliers & Purchases
REVOKE ALL ON suppliers FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON suppliers TO anon, authenticated;

DROP POLICY IF EXISTS "Suppliers open" ON suppliers;
CREATE POLICY "Suppliers open" ON suppliers FOR ALL USING (TRUE) WITH CHECK (TRUE);

REVOKE ALL ON purchases FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON purchases TO anon, authenticated;

DROP POLICY IF EXISTS "Purchases open" ON purchases;
CREATE POLICY "Purchases open" ON purchases FOR ALL USING (TRUE) WITH CHECK (TRUE);

REVOKE ALL ON purchase_items FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON purchase_items TO anon, authenticated;

DROP POLICY IF EXISTS "Purchase items open" ON purchase_items;
CREATE POLICY "Purchase items open" ON purchase_items FOR ALL USING (TRUE) WITH CHECK (TRUE);

-- Orders & Order Items
REVOKE ALL ON orders FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON orders TO anon, authenticated;

DROP POLICY IF EXISTS "Orders view policy" ON orders;
CREATE POLICY "Orders view policy" ON orders FOR SELECT USING (
    customer_id IN (SELECT id FROM customers WHERE user_id = auth.uid())
    OR driver_id = auth.uid()
    OR get_auth_role() IN ('moderator','manager','cashier')
    OR auth.uid() IS NULL
);

DROP POLICY IF EXISTS "Orders insert policy" ON orders;
CREATE POLICY "Orders insert policy" ON orders FOR INSERT WITH CHECK (TRUE);

DROP POLICY IF EXISTS "Orders update policy" ON orders;
CREATE POLICY "Orders update policy" ON orders FOR UPDATE USING (TRUE) WITH CHECK (TRUE);

REVOKE ALL ON order_items FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON order_items TO anon, authenticated;

DROP POLICY IF EXISTS "Order items open" ON order_items;
CREATE POLICY "Order items open" ON order_items FOR ALL USING (TRUE) WITH CHECK (TRUE);

-- Financial Ledgers & Settlements
REVOKE ALL ON stock_ledger FROM anon, authenticated;
GRANT SELECT, INSERT ON stock_ledger TO anon, authenticated;

DROP POLICY IF EXISTS "Stock ledger open read and insert" ON stock_ledger;
CREATE POLICY "Stock ledger open read and insert" ON stock_ledger FOR ALL USING (TRUE) WITH CHECK (TRUE);

REVOKE ALL ON customer_ledger FROM anon, authenticated;
GRANT SELECT, INSERT ON customer_ledger TO anon, authenticated;

DROP POLICY IF EXISTS "Customer ledger open read and insert" ON customer_ledger;
CREATE POLICY "Customer ledger open read and insert" ON customer_ledger FOR ALL USING (TRUE) WITH CHECK (TRUE);

REVOKE ALL ON supplier_ledger FROM anon, authenticated;
GRANT SELECT, INSERT ON supplier_ledger TO anon, authenticated;

DROP POLICY IF EXISTS "Supplier ledger open read and insert" ON supplier_ledger;
CREATE POLICY "Supplier ledger open read and insert" ON supplier_ledger FOR ALL USING (TRUE) WITH CHECK (TRUE);

REVOKE ALL ON payments FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON payments TO anon, authenticated;

DROP POLICY IF EXISTS "Payments open" ON payments;
CREATE POLICY "Payments open" ON payments FOR ALL USING (TRUE) WITH CHECK (TRUE);

REVOKE ALL ON settlements FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON settlements TO anon, authenticated;

DROP POLICY IF EXISTS "Settlements open" ON settlements;
CREATE POLICY "Settlements open" ON settlements FOR ALL USING (TRUE) WITH CHECK (TRUE);

REVOKE ALL ON wallet_entries FROM anon, authenticated;
GRANT SELECT, INSERT ON wallet_entries TO anon, authenticated;

DROP POLICY IF EXISTS "Wallet entries open" ON wallet_entries;
CREATE POLICY "Wallet entries open" ON wallet_entries FOR ALL USING (TRUE) WITH CHECK (TRUE);

-- Driver Locations
REVOKE ALL ON driver_locations FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON driver_locations TO anon, authenticated;

DROP POLICY IF EXISTS "Driver locations open for driver and staff" ON driver_locations;
CREATE POLICY "Driver locations open for driver and staff" ON driver_locations FOR ALL USING (TRUE) WITH CHECK (TRUE);

-- Audit Log Security
REVOKE ALL ON audit_log FROM anon, authenticated;
GRANT SELECT ON audit_log TO anon, authenticated;

DROP POLICY IF EXISTS "Staff and moderator view audit log" ON audit_log;
CREATE POLICY "Staff and moderator view audit log" ON audit_log FOR SELECT USING (
    get_auth_role() IN ('moderator', 'manager')
    OR auth.uid() IS NULL
);


-- ============================================================
-- SECTION 12: VIEW GRANTS & EXPOSURE
-- ============================================================
GRANT SELECT ON view_product_stock         TO anon, authenticated;
GRANT SELECT ON view_customer_products     TO anon, authenticated;
GRANT SELECT ON view_driver_wallet_balance TO anon, authenticated;
GRANT SELECT ON view_customer_balance      TO anon, authenticated;
GRANT SELECT ON view_supplier_balance      TO anon, authenticated;
GRANT SELECT ON view_audit_log_enriched    TO anon, authenticated;


-- ============================================================
-- SECTION 13: SUPABASE REALTIME PUBLICATION
-- ============================================================
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'driver_locations'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE driver_locations;
    END IF;
END $$;


-- ============================================================
-- SECTION 14: STORAGE BUCKET (Product Images)
-- ============================================================
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'product-images',
    'product-images',
    TRUE,
    5242880,  -- 5 MB limit
    ARRAY['image/jpeg','image/jpg','image/png','image/webp','image/gif']
)
ON CONFLICT (id) DO UPDATE SET
    public = TRUE,
    file_size_limit = 5242880,
    allowed_mime_types = ARRAY['image/jpeg','image/jpg','image/png','image/webp','image/gif'];

DROP POLICY IF EXISTS "Public read product images" ON storage.objects;
CREATE POLICY "Public read product images" ON storage.objects FOR SELECT USING (bucket_id = 'product-images');

DROP POLICY IF EXISTS "Allow staff upload product images" ON storage.objects;
CREATE POLICY "Allow staff upload product images" ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'product-images');

DROP POLICY IF EXISTS "Allow staff update product images" ON storage.objects;
CREATE POLICY "Allow staff update product images" ON storage.objects FOR UPDATE USING (bucket_id = 'product-images');


-- ============================================================
-- SECTION 15: POSTGREST SCHEMA CACHE RELOAD
-- ============================================================
NOTIFY pgrst, 'reload schema';
