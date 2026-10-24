-- ============================================================
-- VIP WHOLESALE & POS MANAGEMENT SYSTEM
-- FRESH DATABASE BASELINE - SCHEMA VERSION 00034
-- ============================================================
-- This is the single authoritative schema for a NEW Supabase project.
-- It merges the curated base schema (migrations 00001-00015) with every
-- migration through 00034, in order.
--
-- DO NOT run this on a database that already contains the VIP schema.
-- For an existing database use the incremental migrations instead.
--
-- After running this file, run: seeds/001_admin.sql
-- To start over on the same project, run: operations/reset_database.sql
-- Then run this file and the seed again.
--
-- Old, superseded scripts live in archive/ for historical reference only.
-- ============================================================


-- ============================================================================
-- CONSOLIDATED BASE - migrations 00001-00015
-- Source: archive/migrations/000_fresh_schema.sql
-- ============================================================================
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
    order_id    UUID           REFERENCES orders(id) ON DELETE SET NULL,
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


-- ============================================================================
-- 00016 - customer app grants and schema fixes
-- Source: archive/migrations/00016_customer_app_grants_and_schema_fix.sql
-- ============================================================================
-- ============================================================
-- 00016_customer_app_grants_and_schema_fix.sql
-- FIX: PostgREST schema cache misses for the customer app
--
-- Root cause: view_customer_products was created in 00014 but
-- never GRANTed to anon/authenticated. PostgREST only exposes
-- objects that the calling role has SELECT privilege on, so the
-- view was invisible to every client query and the schema cache
-- returned: "could not find the table public.view_customer_products".
--
-- Also covers: product_prices and product_barcodes GRANT (needed
-- for the flat-query fallback in product_repository_impl.dart),
-- and explicit GRANT on rpc_submit_customer_order.
-- ============================================================


-- 1. GRANT SELECT on view_customer_products to both anon and authenticated
--    The view already has security_invoker = true, so RLS on the
--    underlying tables (products, stock_ledger, order_items) still applies.
GRANT SELECT ON view_customer_products TO anon, authenticated;


-- 2. GRANT SELECT on product_prices to anon and authenticated
--    RLS policy "Public read product prices" (USING TRUE) already exists
--    from migration 00005, but PostgREST also requires a schema-level GRANT.
GRANT SELECT ON product_prices TO anon, authenticated;


-- 3. GRANT SELECT on product_barcodes to anon and authenticated
--    RLS policy "Public read product barcodes" (USING TRUE) already exists
--    from migration 00005.
GRANT SELECT ON product_barcodes TO anon, authenticated;


-- 4. GRANT SELECT on products to authenticated (customer portal read)
--    RLS policy "Customers view active products" (active = TRUE) already
--    filters out inactive items for customer role.
GRANT SELECT ON products TO anon, authenticated;


-- 5. GRANT EXECUTE on rpc_submit_customer_order to anon and authenticated
--    The function was created in 00014 with SECURITY DEFINER but never
--    granted EXECUTE to the public roles.
GRANT EXECUTE ON FUNCTION rpc_submit_customer_order(UUID, UUID, JSONB, JSONB)
  TO anon, authenticated;


-- 6. GRANT SELECT on orders and order_items to authenticated
--    Needed for customerOrdersProvider to read the customer's own orders.
--    RLS "Customer view own orders" policy restricts rows to their account.
GRANT SELECT ON orders TO authenticated;
GRANT SELECT ON order_items TO authenticated;


-- 7. GRANT SELECT on view_customer_balance to authenticated
--    Used by moderator KPI tiles and the credit-limit check in checkout.
GRANT SELECT ON view_customer_balance TO authenticated;


-- 8. Notify PostgREST to reload its schema cache immediately.
--    This takes effect the moment the migration is applied — no manual
--    restart of the PostgREST process is needed.
NOTIFY pgrst, 'reload schema';


-- ============================================================================
-- 00017 - staff app grants
-- Source: archive/migrations/00017_staff_app_grants.sql
-- ============================================================================
-- ============================================================
-- 00017_staff_app_grants.sql
-- Complete GRANT pass for staff app views, tables and RPCs.
--
-- Root cause: "permission denied for view view_product_stock" (42501)
-- PostgREST only exposes objects with an explicit GRANT to the
-- calling role, regardless of RLS policies.
--
-- What is already granted by prior migrations:
--   00014: view_product_stock → authenticated
--   00015: users (column-level), customers → anon, authenticated
--          rpc_verify_user_pin, rpc_change_user_pin,
--          rpc_reset_user_pin_by_admin, rpc_create_staff_member → anon, authenticated
--   00016: view_customer_products, product_prices, product_barcodes,
--          products, orders, order_items, view_customer_balance → anon/authenticated
--          rpc_submit_customer_order → anon, authenticated
--
-- This migration adds everything still missing.
-- Safe to run multiple times — GRANT is idempotent.
-- ============================================================

-- ============================================================
-- 1. TABLES not yet granted
-- ============================================================
GRANT SELECT ON suppliers           TO authenticated;
GRANT SELECT ON payments            TO authenticated;
GRANT SELECT ON purchases           TO authenticated;
GRANT SELECT ON purchase_items      TO authenticated;
GRANT SELECT ON stock_ledger        TO authenticated;
GRANT SELECT ON customer_ledger     TO authenticated;
GRANT SELECT ON supplier_ledger     TO authenticated;
GRANT SELECT ON wallet_entries      TO authenticated;
GRANT SELECT ON settlements         TO authenticated;

-- Audit & driver tables (added in later migrations)
GRANT SELECT ON audit_log           TO authenticated;
GRANT SELECT ON driver_locations    TO authenticated;
GRANT INSERT, UPDATE ON driver_locations TO authenticated;

-- ============================================================
-- 2. VIEWS not yet granted
-- ============================================================
-- view_product_stock is already granted in 00014, but repeat is harmless
GRANT SELECT ON view_product_stock          TO authenticated;
GRANT SELECT ON view_driver_wallet_balance  TO authenticated;
GRANT SELECT ON view_supplier_balance       TO authenticated;

-- ============================================================
-- 3. RPC FUNCTIONS — only those not already granted in 00015/00016
--    Exact signatures match the CREATE OR REPLACE FUNCTION headers.
-- ============================================================

-- Purchase (00004): rpc_post_purchase(p_purchase_id UUID, p_user_id UUID)
GRANT EXECUTE ON FUNCTION rpc_post_purchase(UUID, UUID)
  TO authenticated;

-- Store sale (00014): rpc_post_store_sale(customer_id, items, paid_cash, on_account, cashier_id)
GRANT EXECUTE ON FUNCTION rpc_post_store_sale(UUID, JSONB, BIGINT, BIGINT, UUID, UUID)
  TO authenticated;

-- Order confirm (00014): rpc_confirm_online_order(order_id, cashier_id, driver_id)
GRANT EXECUTE ON FUNCTION rpc_confirm_online_order(UUID, UUID, UUID)
  TO authenticated;

-- Order delivery (00014): rpc_record_order_delivery(driver_id, order_id, collected_cash, client_id)
GRANT EXECUTE ON FUNCTION rpc_record_order_delivery(UUID, UUID, BIGINT, UUID)
  TO authenticated;

-- Driver settlement (00004): rpc_settle_driver_wallet(cashier_id, driver_id, counted_cash, notes)
GRANT EXECUTE ON FUNCTION rpc_settle_driver_wallet(UUID, UUID, BIGINT, TEXT)
  TO authenticated;

-- Debt collection (00008): rpc_collect_customer_debt(cashier_id, customer_id, amount, method, notes, client_id)
GRANT EXECUTE ON FUNCTION rpc_collect_customer_debt(UUID, UUID, BIGINT, payment_method, TEXT, UUID)
  TO authenticated;

-- Product creation (00014): rpc_create_product(product, barcodes, prices, opening_stock, user_id)
GRANT EXECUTE ON FUNCTION rpc_create_product(JSONB, JSONB, JSONB, INT, UUID)
  TO authenticated;

-- Stock adjustment (00004): rpc_adjust_stock(user_id, product_id, qty_change, reason)
GRANT EXECUTE ON FUNCTION rpc_adjust_stock(UUID, UUID, INT, TEXT)
  TO authenticated;

-- ============================================================
-- 4. FORCE PostgREST SCHEMA CACHE RELOAD
-- ============================================================
NOTIFY pgrst, 'reload schema';


-- ============================================================================
-- 00018 - widen users.pin_code to TEXT
-- Source: archive/migrations/00018_widen_pin_code_to_text.sql
-- ============================================================================
-- ============================================================
-- 00018_widen_pin_code_to_text.sql
-- pin_code was added in 00009 as VARCHAR(10) — too short for
-- bcrypt hashes (60 chars). Widen to TEXT.
-- Idempotent: ALTER TYPE on a TEXT column is a no-op in PG.
-- ============================================================

ALTER TABLE users ALTER COLUMN pin_code TYPE TEXT;


-- ============================================================================
-- 00019 - users SELECT grant for staff login
-- Source: archive/migrations/00019_fix_users_select_for_staff_login.sql
-- ============================================================================
-- ============================================================
-- 00019_fix_users_select_for_staff_login.sql
--
-- Problem: The staff login screen calls getStaffMembers() as the
-- anon role (no Supabase Auth session yet). Migration 00015 did:
--
--   REVOKE ALL ON users FROM anon, authenticated;
--   GRANT SELECT (id, phone, name, role, active, language, ...) ON users TO anon, authenticated;
--
-- Column-level GRANTs in PostgreSQL are additive to table-level
-- grants, but when the table-level SELECT is revoked entirely,
-- PostgREST's schema introspection may report the table as
-- unreadable, causing the query to return empty silently.
--
-- Fix: restore a full table-level SELECT grant and rely on the
-- RLS policy "Allow anon read users for profile and lookup"
-- (USING TRUE) to control row access. pin_code is never
-- returned — the query selects only safe columns explicitly.
-- ============================================================

-- Restore full table-level SELECT (column-level grants remain in addition)
GRANT SELECT ON users TO anon, authenticated;

-- Confirm the RLS policy exists; recreate it to be safe
DROP POLICY IF EXISTS "Allow anon read users for profile and lookup" ON users;
CREATE POLICY "Allow anon read users for profile and lookup"
    ON users FOR SELECT
    USING (TRUE);

-- Force PostgREST schema cache reload
NOTIFY pgrst, 'reload schema';


-- ============================================================================
-- 00020a - missing RLS policies and write grants
-- Source: archive/migrations/00020_missing_rls_policies_and_write_grants.sql
-- ============================================================================
-- ============================================================
-- 00020_missing_rls_policies_and_write_grants.sql
--
-- 000_fresh_schema.sql enables RLS on all tables but only creates
-- policies for a subset of them. Missing = everything blocked.
--
-- IMPORTANT: Staff in this app authenticate via PIN only — no
-- Supabase Auth signIn call is made, so the Supabase client
-- retains the 'anon' role. All policies must include TO anon
-- (or omit the TO clause to cover both anon + authenticated).
--
-- Safe to run multiple times — DROP POLICY IF EXISTS + GRANT are idempotent.
-- ============================================================

-- ── suppliers ─────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Allow all operations on suppliers"  ON suppliers;
DROP POLICY IF EXISTS "Suppliers policy"                   ON suppliers;
DROP POLICY IF EXISTS "suppliers_all_authenticated"        ON suppliers;
DROP POLICY IF EXISTS "suppliers_open"                     ON suppliers;

CREATE POLICY "suppliers_open"
ON suppliers FOR ALL
USING (TRUE) WITH CHECK (TRUE);

GRANT SELECT, INSERT, UPDATE, DELETE ON suppliers TO anon, authenticated;

-- ── purchases ─────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Allow all operations on purchases"  ON purchases;
DROP POLICY IF EXISTS "purchases_all_authenticated"        ON purchases;
DROP POLICY IF EXISTS "purchases_open"                     ON purchases;

CREATE POLICY "purchases_open"
ON purchases FOR ALL
USING (TRUE) WITH CHECK (TRUE);

GRANT SELECT, INSERT, UPDATE, DELETE ON purchases TO anon, authenticated;

-- ── purchase_items ────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Allow all operations on purchase_items" ON purchase_items;
DROP POLICY IF EXISTS "purchase_items_all_authenticated"       ON purchase_items;
DROP POLICY IF EXISTS "purchase_items_open"                    ON purchase_items;

CREATE POLICY "purchase_items_open"
ON purchase_items FOR ALL
USING (TRUE) WITH CHECK (TRUE);

GRANT SELECT, INSERT, UPDATE, DELETE ON purchase_items TO anon, authenticated;

-- ── addresses ─────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Allow all operations on addresses"  ON addresses;
DROP POLICY IF EXISTS "addresses_all_authenticated"        ON addresses;
DROP POLICY IF EXISTS "addresses_open"                     ON addresses;

CREATE POLICY "addresses_open"
ON addresses FOR ALL
USING (TRUE) WITH CHECK (TRUE);

GRANT SELECT, INSERT, UPDATE, DELETE ON addresses TO anon, authenticated;

-- ── stock_ledger ──────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Allow all operations on stock_ledger" ON stock_ledger;
DROP POLICY IF EXISTS "stock_ledger_all_authenticated"       ON stock_ledger;
DROP POLICY IF EXISTS "stock_ledger_open"                    ON stock_ledger;

CREATE POLICY "stock_ledger_open"
ON stock_ledger FOR ALL
USING (TRUE) WITH CHECK (TRUE);

GRANT SELECT, INSERT ON stock_ledger TO anon, authenticated;

-- ── supplier_ledger ───────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Allow all operations on supplier_ledger" ON supplier_ledger;
DROP POLICY IF EXISTS "supplier_ledger_all_authenticated"       ON supplier_ledger;
DROP POLICY IF EXISTS "supplier_ledger_open"                    ON supplier_ledger;

CREATE POLICY "supplier_ledger_open"
ON supplier_ledger FOR ALL
USING (TRUE) WITH CHECK (TRUE);

GRANT SELECT, INSERT ON supplier_ledger TO anon, authenticated;

-- ── payments ──────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Allow all operations on payments"  ON payments;
DROP POLICY IF EXISTS "payments_all_authenticated"        ON payments;
DROP POLICY IF EXISTS "payments_open"                     ON payments;

CREATE POLICY "payments_open"
ON payments FOR ALL
USING (TRUE) WITH CHECK (TRUE);

GRANT SELECT, INSERT, UPDATE ON payments TO anon, authenticated;

-- ── settlements ───────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Allow all operations on settlements" ON settlements;
DROP POLICY IF EXISTS "settlements_all_authenticated"       ON settlements;
DROP POLICY IF EXISTS "settlements_open"                    ON settlements;

CREATE POLICY "settlements_open"
ON settlements FOR ALL
USING (TRUE) WITH CHECK (TRUE);

GRANT SELECT, INSERT ON settlements TO anon, authenticated;

-- ── order_items ───────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Allow all operations on order_items" ON order_items;
DROP POLICY IF EXISTS "order_items_all_authenticated"       ON order_items;
DROP POLICY IF EXISTS "order_items_open"                    ON order_items;

CREATE POLICY "order_items_open"
ON order_items FOR ALL
USING (TRUE) WITH CHECK (TRUE);

GRANT SELECT, INSERT, UPDATE ON order_items TO anon, authenticated;

-- ── product_barcodes / product_prices: allow staff writes ─────────────────
DROP POLICY IF EXISTS "Staff write product barcodes" ON product_barcodes;
DROP POLICY IF EXISTS "Staff write product prices"   ON product_prices;
DROP POLICY IF EXISTS "product_barcodes_open"        ON product_barcodes;
DROP POLICY IF EXISTS "product_prices_open"          ON product_prices;

CREATE POLICY "product_barcodes_open"
ON product_barcodes FOR ALL
USING (TRUE) WITH CHECK (TRUE);

CREATE POLICY "product_prices_open"
ON product_prices FOR ALL
USING (TRUE) WITH CHECK (TRUE);

GRANT SELECT, INSERT, UPDATE, DELETE ON product_barcodes TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON product_prices   TO anon, authenticated;

-- ── products: allow staff writes ──────────────────────────────────────────
GRANT SELECT, INSERT, UPDATE, DELETE ON products TO anon, authenticated;

-- ── customers: allow staff writes ─────────────────────────────────────────
GRANT SELECT, INSERT, UPDATE ON customers TO anon, authenticated;

-- ── orders / wallet_entries: ensure anon can write ────────────────────────
GRANT SELECT, INSERT, UPDATE ON orders         TO anon, authenticated;
GRANT SELECT, INSERT         ON wallet_entries TO anon, authenticated;
GRANT SELECT, INSERT         ON customer_ledger TO anon, authenticated;

-- ── audit_log: triggers write to it ───────────────────────────────────────
GRANT SELECT, INSERT ON audit_log TO anon, authenticated;

-- ── Force PostgREST schema cache reload ───────────────────────────────────
NOTIFY pgrst, 'reload schema';


-- ============================================================================
-- 00020b - supplier write grants
-- Source: archive/migrations/00020_supplier_write_grants.sql
-- ============================================================================
-- ============================================================
-- 00020_supplier_write_grants.sql
--
-- Root cause 1: "permission denied for table suppliers" (42501)
-- Root cause 2: "new row violates row-level security policy" on suppliers INSERT
--
-- Migration 00017 only granted SELECT on suppliers.
-- The open RLS policy from 00006 may not be present on all DB instances.
-- This migration explicitly grants write verbs AND recreates the open policy.
--
-- Safe to run multiple times — GRANT and DROP POLICY IF EXISTS are idempotent.
-- ============================================================

-- ── Suppliers: recreate open RLS policy + write grants ───────────────────
DROP POLICY IF EXISTS "Allow all operations on suppliers" ON suppliers;
DROP POLICY IF EXISTS "Suppliers policy"                  ON suppliers;
DROP POLICY IF EXISTS "Staff manage suppliers"            ON suppliers;
DROP POLICY IF EXISTS "suppliers_all_authenticated"       ON suppliers;

CREATE POLICY "suppliers_all_authenticated"
ON suppliers FOR ALL
TO authenticated
USING (TRUE)
WITH CHECK (TRUE);

GRANT INSERT, UPDATE, DELETE ON suppliers TO authenticated;

-- ── Purchases / purchase_items: direct write for draft creation ───────────
GRANT INSERT, UPDATE, DELETE ON purchases       TO authenticated;
GRANT INSERT, UPDATE, DELETE ON purchase_items  TO authenticated;

-- ── Customers: cashier creates walk-in customers directly ─────────────────
GRANT INSERT, UPDATE ON customers TO authenticated;
GRANT INSERT, UPDATE ON addresses TO authenticated;

-- ── Products: manager edits product fields directly ───────────────────────
GRANT UPDATE ON products TO authenticated;

-- ── Force PostgREST schema cache reload ───────────────────────────────────
NOTIFY pgrst, 'reload schema';


-- ============================================================================
-- 00021 - staff profile update grants
-- Source: archive/migrations/00021_allow_staff_profile_updates.sql
-- ============================================================================
-- ============================================================
-- 00021_allow_staff_profile_updates.sql
--
-- Fix: PostgREST permission denied on table `users` (code 42501).
--
-- Root Cause:
-- Staff authentication uses PIN code verification locally without a
-- Supabase Auth JWT session, running all client queries under the `anon`
-- role. When updating a staff profile (name, phone, role, active, etc.)
-- from the Moderator Dashboard or Profile Sheet, PostgreSQL blocked the
-- operation because:
-- 1. `users` table had UPDATE grant revoked or restricted.
-- 2. The RLS policy for UPDATE was restricted strictly to `role = 'customer'`.
--
-- This script grants UPDATE permissions on the safe staff profile columns
-- and updates the RLS policies to allow updating user profiles.
-- ============================================================

-- 1. Grant table-level UPDATE and safe column updates to anon and authenticated
GRANT UPDATE (name, phone, role, active, language, updated_at) ON users TO anon, authenticated;
GRANT SELECT ON users TO anon, authenticated;

-- 2. Reconfigure RLS policies on `users` table
DROP POLICY IF EXISTS "Allow staff and user profile update" ON users;
DROP POLICY IF EXISTS "Allow customer self-update" ON users;
DROP POLICY IF EXISTS "Allow all operations on users for app functionality" ON users;

-- Policy to allow profile updates (for staff management and customer self-updates)
CREATE POLICY "Allow staff and user profile update"
ON users FOR UPDATE
TO anon, authenticated
USING (TRUE)
WITH CHECK (TRUE);

-- 3. Force PostgREST schema cache reload
NOTIFY pgrst, 'reload schema';


-- ============================================================================
-- 00022 - universal audit trail and intelligence
-- Source: archive/migrations/00022_universal_audit_trail_and_intelligence.sql
-- ============================================================================
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


-- ============================================================================
-- 00023 - OTA app versions and storage
-- Source: archive/migrations/00023_app_versions_and_storage.sql
-- ============================================================================
-- ==============================================================================
-- 00023_app_versions_and_storage.sql
-- Private Over-The-Air (OTA) Application Update System
-- Manages in-house releases across Android, iOS, and Windows
-- ==============================================================================

-- 1. App Versions Table
create table if not exists public.app_versions (
    id uuid primary key default gen_random_uuid(),
    app_type text not null check (app_type in ('staff_app', 'customer_app')),
    platform text not null check (platform in ('android', 'ios', 'windows', 'macos', 'linux', 'web')),
    version_name text not null,                   -- e.g. '1.1.0'
    build_number integer not null,                -- e.g. 15
    min_supported_build integer not null default 1, -- Forces update if current_build < min_supported_build
    download_url text not null,                   -- Direct download link (APK, MSIX, EXE, ZIP)
    manifest_url text,                            -- iOS itms-services manifest.plist URL
    release_notes text,                           -- Markdown / Arabic release notes
    is_mandatory boolean not null default false,  -- If true, blocks usage until updated
    file_size_bytes bigint,                       -- File size in bytes for download progress estimation
    published_by uuid references auth.users(id),
    published_at timestamptz not null default now(),
    created_at timestamptz not null default now()
);

-- Index for instant lookup of latest version per app & platform
create index if not exists idx_app_versions_lookup 
    on public.app_versions (app_type, platform, build_number desc);

-- 2. Row Level Security (RLS)
alter table public.app_versions enable row level security;

-- Everyone (anon and authenticated) can query app versions to check for updates
drop policy if exists "Allow public read access to app_versions" on public.app_versions;
create policy "Allow public read access to app_versions"
    on public.app_versions for select
    using (true);

-- Only moderators or service_role can insert/update app_versions
drop policy if exists "Allow moderators to manage app_versions" on public.app_versions;
create policy "Allow moderators to manage app_versions"
    on public.app_versions for all
    using (
        exists (
            select 1 from public.users u
            where u.id = auth.uid()
            and u.role = 'moderator'
        )
    )
    with check (
        exists (
            select 1 from public.users u
            where u.id = auth.uid()
            and u.role = 'moderator'
        )
    );

-- 3. Storage Bucket for App Releases
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
    'app-releases',
    'app-releases',
    true,
    524288000, -- 500 MB max per installer
    array[
        'application/vnd.android.package-archive',
        'application/octet-stream',
        'application/x-msdos-program',
        'application/x-msi',
        'application/zip',
        'text/xml',
        'application/xml',
        'text/plain'
    ]
)
on conflict (id) do update set
    public = true,
    file_size_limit = 524288000;

-- Storage Policies for 'app-releases'
drop policy if exists "Public Access for App Releases" on storage.objects;
create policy "Public Access for App Releases"
    on storage.objects for select
    using (bucket_id = 'app-releases');

drop policy if exists "Moderator and Service Upload for App Releases" on storage.objects;
create policy "Moderator and Service Upload for App Releases"
    on storage.objects for insert
    with check (
        bucket_id = 'app-releases' and (
            auth.role() = 'service_role' or
            exists (
                select 1 from public.users u
                where u.id = auth.uid()
                and u.role = 'moderator'
            )
        )
    );

-- 4. RPC Function to get latest version cleanly
create or replace function public.rpc_get_latest_app_version(
    p_app_type text,
    p_platform text
)
returns table (
    id uuid,
    app_type text,
    platform text,
    version_name text,
    build_number integer,
    min_supported_build integer,
    download_url text,
    manifest_url text,
    release_notes text,
    is_mandatory boolean,
    file_size_bytes bigint,
    published_at timestamptz
)
language sql
security definer
stable
set search_path = public
as $$
    select 
        id,
        app_type,
        platform,
        version_name,
        build_number,
        min_supported_build,
        download_url,
        manifest_url,
        release_notes,
        is_mandatory,
        file_size_bytes,
        published_at
    from public.app_versions
    where app_type = p_app_type
      and platform = p_platform
    order by build_number desc
    limit 1;
$$;

grant execute on function public.rpc_get_latest_app_version(text, text) to anon, authenticated, service_role;

-- 5. app_versions starts empty. Releases are registered by
--    scripts/publish_release.ps1 after the artifact is uploaded to Storage.
--    Seeding placeholder rows here would advertise downloads that do not exist.


-- ============================================================================
-- 00024 - purge master PIN and revoke anon writes
-- Source: archive/migrations/00024_purge_master_pin_and_revoke_anon_writes.sql
-- ============================================================================
-- ============================================================
-- 00024_purge_master_pin_and_revoke_anon_writes.sql
--
-- 1. PURGE MASTER PIN OVERRIDES ('0000', '1234')
--    - Ensures ONLY cryptographically hashed values (bcrypt) in users.pin_code are validated.
--    - Removes hardcoded fallbacks from all internal/public functions.
--
-- 2. REVOKE ANONYMOUS WRITE GRANTS ON BASE TABLES
--    - Revoke INSERT, UPDATE, DELETE on:
--      users, suppliers, purchases, purchase_items, order_items, stock_ledger
--    - Tightens RLS policies so anon cannot mutate critical tables directly.
--
-- 3. ROUTE WRITES TO ATOMIC SECURITY DEFINER RPCs
--    - rpc_create_supplier: Atomic validated creation of supplier records
--    - rpc_create_draft_purchase: Atomic creation of draft purchase with items
--    - rpc_update_user_profile: Validated profile update with caller verification
--    - rpc_sync_customer_profile: Validated customer profile registration & update
-- ============================================================

-- ============================================================
-- PART 1: PURGE MASTER PIN OVERRIDES & HARDEN VERIFICATION
-- ============================================================

-- Ensure pgcrypto extension is active
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Harden _internal_verify_and_track_pin to strictly require bcrypt match
CREATE OR REPLACE FUNCTION _internal_verify_and_track_pin(
    p_user_id UUID,
    p_pin TEXT,
    p_require_moderator BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_user users%ROWTYPE;
    v_lock pin_attempt_limits%ROWTYPE;
    v_lock_key BIGINT;
    v_is_valid BOOLEAN := FALSE;
    v_new_step INT := 0;
    v_lock_duration INTERVAL := INTERVAL '1 minute';
BEGIN
    -- Advisory lock per user using hash of UUID to serialize concurrent verification requests
    v_lock_key := ('x' || substr(md5(p_user_id::text), 1, 16))::bit(64)::bigint;
    PERFORM pg_advisory_xact_lock(v_lock_key);

    -- Load current attempt limits
    SELECT * INTO v_lock FROM pin_attempt_limits WHERE user_id = p_user_id;

    -- Check 24-hour decay: reset counter if last failed attempt was over 24 hours ago
    IF v_lock.user_id IS NOT NULL AND v_lock.last_failed_at IS NOT NULL THEN
        IF v_lock.last_failed_at < NOW() - INTERVAL '24 hours' THEN
            v_lock.failed_attempts := 0;
            v_lock.lock_step := 0;
            v_lock.locked_until := NULL;
        END IF;
    END IF;

    -- Reset failed_attempts when locked_until has passed
    IF v_lock.user_id IS NOT NULL AND v_lock.locked_until IS NOT NULL THEN
        IF v_lock.locked_until <= NOW() THEN
            v_lock.failed_attempts := 0;
            v_lock.locked_until := NULL;
        END IF;
    END IF;

    -- Check active lock status
    IF v_lock.user_id IS NOT NULL AND v_lock.locked_until IS NOT NULL AND v_lock.locked_until > NOW() THEN
        RETURN jsonb_build_object(
            'valid', FALSE,
            'locked', TRUE,
            'message', 'الحساب مقفل مؤقتاً لتكرار المحاولات الخاطئة. يرجى الانتظار.'
        );
    END IF;

    -- Load user record
    SELECT * INTO v_user FROM users WHERE id = p_user_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('valid', FALSE, 'message', 'المستخدم غير موجود');
    END IF;

    IF v_user.active = FALSE THEN
        RETURN jsonb_build_object('valid', FALSE, 'message', 'الحساب معطل من قبل الإدارة');
    END IF;

    IF p_require_moderator AND v_user.role <> 'moderator' THEN
        RETURN jsonb_build_object('valid', FALSE, 'message', 'العملية تتطلب صلاحيات المشرف العام (Moderator)');
    END IF;

    -- Reject empty, short, or invalid PIN input
    IF p_pin IS NULL OR LENGTH(trim(p_pin)) < 4 THEN
        RETURN jsonb_build_object('valid', FALSE, 'message', 'رمز PIN غير صالح');
    END IF;

    -- Compare hashed PIN strictly using crypt(pin, stored_hash). NO '0000' or '1234' backdoor.
    IF v_user.pin_code IS NOT NULL AND v_user.pin_code = crypt(trim(p_pin), v_user.pin_code) THEN
        v_is_valid := TRUE;
    END IF;

    IF v_is_valid THEN
        -- Reset counter ONLY on successful authentication
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
        -- Failed attempt: compute escalating lock duration
        IF v_lock.user_id IS NULL THEN
            INSERT INTO pin_attempt_limits (user_id, failed_attempts, lock_step, locked_until, last_failed_at)
            VALUES (p_user_id, 1, 0, NULL, NOW());
        ELSE
            v_lock.failed_attempts := v_lock.failed_attempts + 1;
            IF v_lock.failed_attempts >= 15 THEN
                v_new_step := 3;
                v_lock_duration := INTERVAL '15 minutes';
            ELSIF v_lock.failed_attempts >= 10 THEN
                v_new_step := 2;
                v_lock_duration := INTERVAL '5 minutes';
            ELSIF v_lock.failed_attempts >= 5 THEN
                v_new_step := 1;
                v_lock_duration := INTERVAL '1 minute';
            ELSE
                v_new_step := 0;
            END IF;

            UPDATE pin_attempt_limits 
            SET failed_attempts = v_lock.failed_attempts,
                lock_step = v_new_step,
                last_failed_at = NOW(),
                locked_until = CASE 
                    WHEN v_new_step > 0 THEN NOW() + v_lock_duration 
                    ELSE NULL 
                END
            WHERE user_id = p_user_id;
        END IF;

        RETURN jsonb_build_object('valid', FALSE, 'message', 'رمز PIN غير صحيح');
    END IF;
END;
$$;

-- Ensure execute on internal function remains strictly revoked
REVOKE ALL ON FUNCTION _internal_verify_and_track_pin(UUID, TEXT, BOOLEAN) FROM PUBLIC, anon, authenticated;

-- Public wrapper for PIN verification
CREATE OR REPLACE FUNCTION rpc_verify_user_pin(
    p_user_id UUID,
    p_pin TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
BEGIN
    RETURN _internal_verify_and_track_pin(p_user_id, p_pin, FALSE);
END;
$$;
GRANT EXECUTE ON FUNCTION rpc_verify_user_pin(UUID, TEXT) TO anon, authenticated;

-- Public wrapper for changing own PIN (strictly validates old PIN via bcrypt)
CREATE OR REPLACE FUNCTION rpc_change_user_pin(
    p_user_id UUID,
    p_old_pin TEXT,
    p_new_pin TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_check JSONB;
BEGIN
    v_check := _internal_verify_and_track_pin(p_user_id, p_old_pin, FALSE);
    IF (v_check->>'valid')::BOOLEAN <> TRUE THEN
        RETURN jsonb_build_object('status', 'error', 'message', COALESCE(v_check->>'message', 'رمز PIN الحالي غير صحيح'));
    END IF;

    IF LENGTH(trim(p_new_pin)) < 4 THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'يجب أن يتكون رمز PIN الجديد من 4 أرقام على الأقل');
    END IF;

    UPDATE users
    SET pin_code = crypt(trim(p_new_pin), gen_salt('bf')),
        updated_at = NOW()
    WHERE id = p_user_id;

    INSERT INTO audit_log (user_id, action, target_table, target_id, after_state)
    VALUES (p_user_id, 'USER_PIN_CHANGED', 'users', p_user_id, jsonb_build_object('changed_at', NOW()));

    RETURN jsonb_build_object('status', 'success', 'message', 'تم تحديث رمز PIN بنجاح');
END;
$$;
GRANT EXECUTE ON FUNCTION rpc_change_user_pin(UUID, TEXT, TEXT) TO anon, authenticated;

-- Admin/Moderator reset of staff PIN (strictly validates admin credentials via bcrypt)
CREATE OR REPLACE FUNCTION rpc_reset_user_pin_by_admin(
    p_admin_id UUID,
    p_admin_pin TEXT,
    p_target_user_id UUID,
    p_new_pin TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_admin_check JSONB;
    v_target RECORD;
BEGIN
    -- Verify admin identity and pin strictly
    v_admin_check := _internal_verify_and_track_pin(p_admin_id, p_admin_pin, TRUE);
    IF (v_admin_check->>'valid')::BOOLEAN <> TRUE THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'فشل التحقق من هوية المشرف أو رمز PIN للمشرف');
    END IF;

    SELECT id, name, phone, role INTO v_target FROM users WHERE id = p_target_user_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'الموظف غير موجود');
    END IF;

    IF LENGTH(trim(p_new_pin)) < 4 THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'يجب أن يتكون رمز PIN من 4 أرقام على الأقل');
    END IF;

    UPDATE users
    SET pin_code = crypt(trim(p_new_pin), gen_salt('bf')),
        updated_at = NOW()
    WHERE id = p_target_user_id;

    INSERT INTO audit_log (user_id, action, target_table, target_id, after_state)
    VALUES (p_admin_id, 'MODERATOR_RESET_USER_PIN', 'users', p_target_user_id, jsonb_build_object(
        'target_name', v_target.name,
        'target_phone', v_target.phone,
        'target_role', v_target.role,
        'reset_at', NOW()
    ));

    RETURN jsonb_build_object('status', 'success', 'message', 'تم إعادة تعيين رمز PIN بنجاح');
END;
$$;
GRANT EXECUTE ON FUNCTION rpc_reset_user_pin_by_admin(UUID, TEXT, UUID, TEXT) TO anon, authenticated;

-- Moderator create staff member (strictly requires non-null, minimum 4-digit PIN)
CREATE OR REPLACE FUNCTION rpc_create_staff_member(
    p_admin_id UUID,
    p_admin_pin TEXT,
    p_name VARCHAR,
    p_phone VARCHAR,
    p_role user_role,
    p_initial_pin TEXT,
    p_language VARCHAR DEFAULT 'ar'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_admin_check JSONB;
    v_user_id UUID := gen_random_uuid();
BEGIN
    -- Verify caller is active moderator with correct PIN
    v_admin_check := _internal_verify_and_track_pin(p_admin_id, p_admin_pin, TRUE);
    IF (v_admin_check->>'valid')::BOOLEAN <> TRUE THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'فشل التحقق من صلاحيات المشرف العام');
    END IF;

    IF p_initial_pin IS NULL OR LENGTH(trim(p_initial_pin)) < 4 THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'يجب تحديد رمز PIN من 4 أرقام على الأقل للموظف الجديد');
    END IF;

    IF p_role = 'customer' THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'لا يمكن استخدام هذه الدالة لإنشاء حسابات الزبائن');
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
GRANT EXECUTE ON FUNCTION rpc_create_staff_member(UUID, TEXT, VARCHAR, VARCHAR, user_role, TEXT, VARCHAR) TO anon, authenticated;


-- ============================================================
-- PART 2: REVOKE ANONYMOUS WRITE GRANTS ON BASE TABLES
-- ============================================================

-- 1. USERS: Revoke all direct writes from anon
REVOKE INSERT, UPDATE, DELETE ON users FROM anon;
REVOKE UPDATE (name, phone, role, active, language, updated_at) ON users FROM anon;
-- Allow anon read-only SELECT for profile and staff list
GRANT SELECT ON users TO anon, authenticated;

DROP POLICY IF EXISTS "Allow staff and user profile update" ON users;
DROP POLICY IF EXISTS "Allow customer self-registration" ON users;
DROP POLICY IF EXISTS "Allow customer self-update" ON users;

CREATE POLICY "Allow authenticated staff update users"
ON users FOR UPDATE TO authenticated
USING (get_auth_role() IN ('moderator', 'manager'))
WITH CHECK (get_auth_role() IN ('moderator', 'manager'));

-- 2. SUPPLIERS: Revoke write from anon
REVOKE INSERT, UPDATE, DELETE ON suppliers FROM anon;
GRANT SELECT ON suppliers TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON suppliers TO authenticated;

DROP POLICY IF EXISTS "suppliers_open" ON suppliers;
CREATE POLICY "suppliers_read" ON suppliers FOR SELECT USING (TRUE);
CREATE POLICY "suppliers_write_authenticated" ON suppliers FOR ALL TO authenticated
USING (get_auth_role() IN ('moderator', 'manager'))
WITH CHECK (get_auth_role() IN ('moderator', 'manager'));

-- 3. PURCHASES & PURCHASE_ITEMS: Revoke write from anon
REVOKE INSERT, UPDATE, DELETE ON purchases FROM anon;
REVOKE INSERT, UPDATE, DELETE ON purchase_items FROM anon;
GRANT SELECT ON purchases TO anon, authenticated;
GRANT SELECT ON purchase_items TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON purchases TO authenticated;
GRANT INSERT, UPDATE, DELETE ON purchase_items TO authenticated;

DROP POLICY IF EXISTS "purchases_open" ON purchases;
DROP POLICY IF EXISTS "purchase_items_open" ON purchase_items;
CREATE POLICY "purchases_read" ON purchases FOR SELECT USING (TRUE);
CREATE POLICY "purchase_items_read" ON purchase_items FOR SELECT USING (TRUE);
CREATE POLICY "purchases_write_authenticated" ON purchases FOR ALL TO authenticated
USING (get_auth_role() IN ('moderator', 'manager'))
WITH CHECK (get_auth_role() IN ('moderator', 'manager'));
CREATE POLICY "purchase_items_write_authenticated" ON purchase_items FOR ALL TO authenticated
USING (get_auth_role() IN ('moderator', 'manager'))
WITH CHECK (get_auth_role() IN ('moderator', 'manager'));

-- 4. ORDER_ITEMS: Revoke direct writes from anon
REVOKE INSERT, UPDATE, DELETE ON order_items FROM anon;
GRANT SELECT ON order_items TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON order_items TO authenticated;

DROP POLICY IF EXISTS "order_items_open" ON order_items;
CREATE POLICY "order_items_read" ON order_items FOR SELECT USING (TRUE);
CREATE POLICY "order_items_write_authenticated" ON order_items FOR ALL TO authenticated
USING (get_auth_role() IN ('moderator', 'manager', 'cashier'))
WITH CHECK (get_auth_role() IN ('moderator', 'manager', 'cashier'));

-- 5. STOCK_LEDGER: Strictly append-only, NO direct write from anon
REVOKE INSERT, UPDATE, DELETE ON stock_ledger FROM anon;
GRANT SELECT ON stock_ledger TO anon, authenticated;
GRANT INSERT ON stock_ledger TO authenticated;

DROP POLICY IF EXISTS "stock_ledger_open" ON stock_ledger;
CREATE POLICY "stock_ledger_read" ON stock_ledger FOR SELECT USING (TRUE);
CREATE POLICY "stock_ledger_insert_authenticated" ON stock_ledger FOR INSERT TO authenticated
WITH CHECK (get_auth_role() IN ('moderator', 'manager', 'cashier'));

-- 6. CUSTOMERS: Revoke direct UPDATE/DELETE from anon
REVOKE UPDATE, DELETE ON customers FROM anon;
GRANT SELECT ON customers TO anon, authenticated;
GRANT ALL ON customers TO authenticated;

DROP POLICY IF EXISTS "Allow all operations on customers" ON customers;
CREATE POLICY "customers_read" ON customers FOR SELECT USING (TRUE);
CREATE POLICY "customers_write_authenticated" ON customers FOR ALL TO authenticated
USING (get_auth_role() IN ('moderator', 'manager', 'cashier'))
WITH CHECK (get_auth_role() IN ('moderator', 'manager', 'cashier'));


-- ============================================================
-- PART 3: NEW SECURITY DEFINER RPCs TO ROUTE WRITE OPERATIONS
-- ============================================================

-- 1. RPC: CREATE SUPPLIER
CREATE OR REPLACE FUNCTION rpc_create_supplier(
    p_name VARCHAR,
    p_phone VARCHAR,
    p_company_register VARCHAR DEFAULT NULL,
    p_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_supplier_id UUID := gen_random_uuid();
    v_clean_name VARCHAR := trim(p_name);
    v_clean_phone VARCHAR := trim(p_phone);
BEGIN
    IF v_clean_name IS NULL OR LENGTH(v_clean_name) < 2 THEN
        RAISE EXCEPTION 'اسم المورد غير صالح';
    END IF;

    INSERT INTO suppliers (id, name, phone, company_register, notes)
    VALUES (v_supplier_id, v_clean_name, v_clean_phone, trim(p_company_register), trim(p_notes));

    RETURN jsonb_build_object(
        'id', v_supplier_id,
        'name', v_clean_name,
        'phone', v_clean_phone,
        'company_register', trim(p_company_register),
        'notes', trim(p_notes)
    );
END;
$$;
GRANT EXECUTE ON FUNCTION rpc_create_supplier(VARCHAR, VARCHAR, VARCHAR, TEXT) TO anon, authenticated;

-- 2. RPC: CREATE DRAFT PURCHASE
CREATE OR REPLACE FUNCTION rpc_create_draft_purchase(
    p_supplier_id UUID,
    p_invoice_no VARCHAR,
    p_invoice_date DATE,
    p_total_amount BIGINT,
    p_created_by UUID,
    p_items JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_purchase_id UUID := gen_random_uuid();
    v_item JSONB;
    v_product_id UUID;
    v_qty INT;
    v_unit_cost BIGINT;
    v_selling_price BIGINT;
BEGIN
    INSERT INTO purchases (id, supplier_id, invoice_no, invoice_date, status, total_amount, created_by)
    VALUES (v_purchase_id, p_supplier_id, p_invoice_no, p_invoice_date, 'draft', p_total_amount, p_created_by);

    IF p_items IS NOT NULL AND jsonb_array_length(p_items) > 0 THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
            v_product_id := (v_item->>'product_id')::UUID;
            v_qty := COALESCE((v_item->>'quantity')::INT, (v_item->>'qty')::INT, 1);
            v_unit_cost := COALESCE((v_item->>'unit_cost')::BIGINT, (v_item->>'cost_centimes')::BIGINT, 0);
            v_selling_price := COALESCE((v_item->>'selling_price')::BIGINT, v_unit_cost);

            IF v_selling_price < v_unit_cost THEN
                v_selling_price := v_unit_cost;
            END IF;

            INSERT INTO purchase_items (purchase_id, product_id, quantity, unit_cost, selling_price)
            VALUES (v_purchase_id, v_product_id, v_qty, v_unit_cost, v_selling_price);
        END LOOP;
    END IF;

    RETURN v_purchase_id;
END;
$$;
GRANT EXECUTE ON FUNCTION rpc_create_draft_purchase(UUID, VARCHAR, DATE, BIGINT, UUID, JSONB) TO anon, authenticated;

-- 3. RPC: UPDATE USER PROFILE (MODERATOR OR SELF)
CREATE OR REPLACE FUNCTION rpc_update_user_profile(
    p_caller_id UUID,
    p_caller_pin TEXT,
    p_target_user_id UUID,
    p_name VARCHAR,
    p_phone VARCHAR,
    p_language VARCHAR DEFAULT 'ar',
    p_role user_role DEFAULT NULL,
    p_active BOOLEAN DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_auth_check JSONB;
    v_caller users%ROWTYPE;
    v_is_moderator BOOLEAN := FALSE;
BEGIN
    -- Verify caller credentials
    v_auth_check := _internal_verify_and_track_pin(p_caller_id, p_caller_pin, FALSE);
    IF (v_auth_check->>'valid')::BOOLEAN <> TRUE THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'فشل التحقق من هوية المستخدم أو رمز PIN');
    END IF;

    SELECT * INTO v_caller FROM users WHERE id = p_caller_id;
    IF v_caller.role = 'moderator' THEN
        v_is_moderator := TRUE;
    END IF;

    -- Non-moderators can only update their own profile and cannot change role or active status
    IF NOT v_is_moderator AND p_caller_id <> p_target_user_id THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'لا تملك صلاحية تعديل بيانات مستخدم آخر');
    END IF;

    IF v_is_moderator THEN
        UPDATE users
        SET name = trim(p_name),
            phone = trim(p_phone),
            language = COALESCE(p_language, language),
            role = COALESCE(p_role, role),
            active = COALESCE(p_active, active),
            updated_at = NOW()
        WHERE id = p_target_user_id;
    ELSE
        UPDATE users
        SET name = trim(p_name),
            phone = trim(p_phone),
            language = COALESCE(p_language, language),
            updated_at = NOW()
        WHERE id = p_target_user_id;
    END IF;

    INSERT INTO audit_log (user_id, action, target_table, target_id, after_state)
    VALUES (p_caller_id, 'USER_PROFILE_UPDATED', 'users', p_target_user_id, jsonb_build_object(
        'name', p_name,
        'phone', p_phone,
        'language', p_language,
        'updated_at', NOW()
    ));

    RETURN jsonb_build_object('status', 'success', 'message', 'تم تحديث البيانات بنجاح');
END;
$$;
GRANT EXECUTE ON FUNCTION rpc_update_user_profile(UUID, TEXT, UUID, VARCHAR, VARCHAR, VARCHAR, user_role, BOOLEAN) TO anon, authenticated;

-- 4. RPC: SYNC CUSTOMER PROFILE (Creation / Update with verification)
CREATE OR REPLACE FUNCTION rpc_sync_customer_profile(
    p_name VARCHAR,
    p_phone VARCHAR,
    p_wilaya VARCHAR,
    p_commune VARCHAR,
    p_address_text TEXT,
    p_latitude DOUBLE PRECISION DEFAULT NULL,
    p_longitude DOUBLE PRECISION DEFAULT NULL,
    p_existing_customer_id UUID DEFAULT NULL,
    p_existing_user_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_clean_phone VARCHAR := trim(p_phone);
    v_clean_name VARCHAR := trim(p_name);
    v_user_id UUID := p_existing_user_id;
    v_customer_id UUID := p_existing_customer_id;
    v_credit_limit BIGINT := 0;
    v_price_tier price_tier := 'wholesale';
    v_auth_uid UUID;
BEGIN
    BEGIN v_auth_uid := auth.uid(); EXCEPTION WHEN OTHERS THEN v_auth_uid := NULL; END;

    IF v_clean_phone IS NULL OR v_clean_phone !~ '^0[5-7][0-9]{8}$' THEN
        RAISE EXCEPTION 'رقم الهاتف غير صالح';
    END IF;

    IF v_clean_name IS NULL OR LENGTH(v_clean_name) < 2 THEN
        v_clean_name := 'زبون متجر الجملة';
    END IF;

    -- Resolve user_id: prefer auth.uid() if authenticated session exists
    IF v_auth_uid IS NOT NULL THEN
        v_user_id := v_auth_uid;
    ELSIF v_user_id IS NULL THEN
        SELECT id INTO v_user_id FROM users WHERE phone = v_clean_phone LIMIT 1;
    END IF;

    IF v_user_id IS NOT NULL THEN
        UPDATE users
        SET name = v_clean_name,
            phone = v_clean_phone,
            active = TRUE,
            updated_at = NOW()
        WHERE id = v_user_id;
    ELSE
        v_user_id := gen_random_uuid();
        INSERT INTO users (id, name, phone, role, language, active)
        VALUES (v_user_id, v_clean_name, v_clean_phone, 'customer', 'ar', TRUE);
    END IF;

    -- Resolve customer_id
    IF v_customer_id IS NOT NULL THEN
        SELECT id, credit_limit, price_tier INTO v_customer_id, v_credit_limit, v_price_tier
        FROM customers WHERE id = v_customer_id;
    ELSE
        SELECT id, credit_limit, price_tier INTO v_customer_id, v_credit_limit, v_price_tier
        FROM customers WHERE user_id = v_user_id LIMIT 1;
    END IF;

    IF v_customer_id IS NULL THEN
        v_customer_id := gen_random_uuid();
        INSERT INTO customers (id, user_id, credit_limit, price_tier)
        VALUES (v_customer_id, v_user_id, 0, 'wholesale')
        RETURNING id, credit_limit, price_tier INTO v_customer_id, v_credit_limit, v_price_tier;
    END IF;

    -- Upsert primary address
    IF p_wilaya IS NOT NULL AND p_commune IS NOT NULL THEN
        INSERT INTO addresses (customer_id, wilaya, commune, address_text, latitude, longitude, is_default)
        VALUES (v_customer_id, trim(p_wilaya), trim(p_commune), trim(p_address_text), p_latitude, p_longitude, TRUE)
        ON CONFLICT DO NOTHING;
    END IF;

    RETURN jsonb_build_object(
        'customer_id', v_customer_id,
        'user_id', v_user_id,
        'name', v_clean_name,
        'phone', v_clean_phone,
        'wilaya', trim(p_wilaya),
        'commune', trim(p_commune),
        'address_text', trim(p_address_text),
        'credit_limit', v_credit_limit,
        'price_tier', v_price_tier
    );
END;
$$;
GRANT EXECUTE ON FUNCTION rpc_sync_customer_profile(VARCHAR, VARCHAR, VARCHAR, VARCHAR, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, UUID, UUID) TO anon, authenticated;

-- Force PostgREST schema cache reload
NOTIFY pgrst, 'reload schema';


-- ============================================================================
-- 00025 - device-bound customer authentication
-- Source: archive/migrations/00025_device_bound_customer_auth.sql
-- ============================================================================
-- ============================================================
-- 00025_device_bound_customer_auth.sql
--
-- DEVICE-BOUND CRYPTOGRAPHIC AUTHENTICATION FOR CUSTOMERS
-- (Replaces SMS OTP with Zero-Cost Device-Bound Token Handshake)
--
-- 1. Adds `device_token` to `customers` table (UUID / crypt token).
-- 2. rpc_register_or_bind_customer_device:
--    - When a customer registers or opens the app on a new device,
--      their hardware device signature is bound to their account.
--    - If account has an existing device_token, any different device
--      attempting to act on the account is rejected (preventing account takeover).
-- 3. rpc_verify_customer_device:
--    - Validates device_token match on phone lookup or order checkout.
-- 4. Updates rpc_sync_customer_profile & rpc_submit_customer_order
--    to require and verify p_device_token.
-- ============================================================

-- 1. Add device_token column to customers table
ALTER TABLE customers ADD COLUMN IF NOT EXISTS device_token TEXT;
CREATE INDEX IF NOT EXISTS idx_customers_device_token ON customers(device_token);

-- 2. RPC: Register or Bind Device to Customer
CREATE OR REPLACE FUNCTION rpc_register_or_bind_customer_device(
    p_phone VARCHAR,
    p_device_token TEXT,
    p_name VARCHAR DEFAULT NULL,
    p_wilaya VARCHAR DEFAULT NULL,
    p_commune VARCHAR DEFAULT NULL,
    p_address_text TEXT DEFAULT NULL,
    p_latitude DOUBLE PRECISION DEFAULT NULL,
    p_longitude DOUBLE PRECISION DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_clean_phone VARCHAR := trim(p_phone);
    v_clean_name VARCHAR := trim(COALESCE(p_name, 'زبون متجر الجملة'));
    v_clean_token TEXT := trim(p_device_token);
    v_user_id UUID;
    v_customer_id UUID;
    v_existing_token TEXT;
    v_credit_limit BIGINT := 0;
    v_price_tier price_tier := 'wholesale';
BEGIN
    IF v_clean_phone IS NULL OR v_clean_phone !~ '^0[5-7][0-9]{8}$' THEN
        RETURN jsonb_build_object('success', FALSE, 'error', 'رقم الهاتف غير صالح. يجب أن يبدأ بـ 05 أو 06 أو 07');
    END IF;

    IF v_clean_token IS NULL OR LENGTH(v_clean_token) < 16 THEN
        RETURN jsonb_build_object('success', FALSE, 'error', 'معرف الجهاز غير صالح');
    END IF;

    -- Look up existing user by phone
    SELECT id INTO v_user_id FROM users WHERE phone = v_clean_phone LIMIT 1;

    IF v_user_id IS NOT NULL THEN
        -- Existing user: check customer and device_token
        SELECT id, device_token, credit_limit, price_tier
        INTO v_customer_id, v_existing_token, v_credit_limit, v_price_tier
        FROM customers
        WHERE user_id = v_user_id
        LIMIT 1;

        IF v_customer_id IS NOT NULL THEN
            IF v_existing_token IS NOT NULL AND v_existing_token <> '' THEN
                -- Account already bound to a device: verify match!
                IF v_existing_token <> v_clean_token THEN
                    RETURN jsonb_build_object(
                        'success', FALSE,
                        'bound_to_other_device', TRUE,
                        'error', 'هذا الحساب مرتبط بجهاز آخر بالفعل لحماية البيانات. يرجى التواصل مع الإدارة لإعادة ربط الجهاز.'
                    );
                END IF;
            ELSE
                -- First time binding device token to existing customer
                UPDATE customers SET device_token = v_clean_token WHERE id = v_customer_id;
            END IF;

            -- Update profile details if provided
            IF p_name IS NOT NULL AND trim(p_name) <> '' THEN
                UPDATE users SET name = v_clean_name, updated_at = NOW() WHERE id = v_user_id;
            END IF;
        ELSE
            -- User exists but no customer row
            v_customer_id := gen_random_uuid();
            INSERT INTO customers (id, user_id, device_token, credit_limit, price_tier)
            VALUES (v_customer_id, v_user_id, v_clean_token, 0, 'wholesale');
        END IF;
    ELSE
        -- New User Registration
        v_user_id := gen_random_uuid();
        INSERT INTO users (id, name, phone, role, language, active)
        VALUES (v_user_id, v_clean_name, v_clean_phone, 'customer', 'ar', TRUE);

        v_customer_id := gen_random_uuid();
        INSERT INTO customers (id, user_id, device_token, credit_limit, price_tier)
        VALUES (v_customer_id, v_user_id, v_clean_token, 0, 'wholesale');
    END IF;

    -- Update or insert address if provided
    IF p_wilaya IS NOT NULL AND p_commune IS NOT NULL AND trim(p_wilaya) <> '' THEN
        INSERT INTO addresses (customer_id, wilaya, commune, address_text, latitude, longitude, is_default)
        VALUES (v_customer_id, trim(p_wilaya), trim(p_commune), trim(COALESCE(p_address_text, '')), p_latitude, p_longitude, TRUE)
        ON CONFLICT DO NOTHING;
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE,
        'customer_id', v_customer_id,
        'user_id', v_user_id,
        'name', v_clean_name,
        'phone', v_clean_phone,
        'wilaya', trim(COALESCE(p_wilaya, '')),
        'commune', trim(COALESCE(p_commune, '')),
        'address_text', trim(COALESCE(p_address_text, '')),
        'credit_limit', v_credit_limit,
        'price_tier', v_price_tier,
        'device_token', v_clean_token
    );
END;
$$;
GRANT EXECUTE ON FUNCTION rpc_register_or_bind_customer_device(VARCHAR, TEXT, VARCHAR, VARCHAR, VARCHAR, TEXT, DOUBLE PRECISION, DOUBLE PRECISION) TO anon, authenticated;

-- 3. RPC: Lookup Customer by Phone with Device Verification
CREATE OR REPLACE FUNCTION rpc_lookup_customer_by_phone(
    p_phone VARCHAR,
    p_device_token TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_clean_phone VARCHAR := trim(p_phone);
    v_clean_token TEXT := trim(p_device_token);
    v_user users%ROWTYPE;
    v_cust customers%ROWTYPE;
    v_addr addresses%ROWTYPE;
BEGIN
    SELECT * INTO v_user FROM users WHERE phone = v_clean_phone LIMIT 1;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('found', FALSE, 'message', 'لا يوجد حساب مسجل بهذا الرقم');
    END IF;

    SELECT * INTO v_cust FROM customers WHERE user_id = v_user.id LIMIT 1;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('found', FALSE, 'message', 'لا يوجد ملف زبون مرتبط بهذا الرقم');
    END IF;

    -- Device authentication check
    IF v_cust.device_token IS NOT NULL AND v_cust.device_token <> '' THEN
        IF v_clean_token IS NULL OR v_cust.device_token <> v_clean_token THEN
            RETURN jsonb_build_object(
                'found', FALSE,
                'device_mismatch', TRUE,
                'message', 'هذا الحساب مرتبط بجهاز آخر ومحمي بكلمة أمان مشفرة للجهاز الأصلي.'
            );
        END IF;
    ELSE
        -- Auto-bind if not previously bound
        IF v_clean_token IS NOT NULL AND LENGTH(v_clean_token) >= 16 THEN
            UPDATE customers SET device_token = v_clean_token WHERE id = v_cust.id;
        END IF;
    END IF;

    SELECT * INTO v_addr FROM addresses WHERE customer_id = v_cust.id ORDER BY is_default DESC, created_at DESC LIMIT 1;

    RETURN jsonb_build_object(
        'found', TRUE,
        'id', v_cust.id,
        'user_id', v_user.id,
        'name', v_user.name,
        'phone', v_user.phone,
        'wilaya', COALESCE(v_addr.wilaya, ''),
        'commune', COALESCE(v_addr.commune, ''),
        'address_text', COALESCE(v_addr.address_text, ''),
        'latitude', v_addr.latitude,
        'longitude', v_addr.longitude,
        'credit_limit', v_cust.credit_limit,
        'price_tier', v_cust.price_tier
    );
END;
$$;
GRANT EXECUTE ON FUNCTION rpc_lookup_customer_by_phone(VARCHAR, TEXT) TO anon, authenticated;

-- 4. Update rpc_submit_customer_order to verify device token
CREATE OR REPLACE FUNCTION rpc_submit_customer_order(
    p_client_id       UUID,
    p_customer_id     UUID,
    p_delivery_address JSONB,
    p_items           JSONB,
    p_device_token    TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_order_id   UUID;
    v_tier       price_tier := 'wholesale';
    v_cust_id    UUID := p_customer_id;
    v_stored_token TEXT;
    v_item       JSONB;
    v_product_id UUID;
    v_qty        INT;
    v_unit_price BIGINT;
    v_unit_cost  BIGINT;
    v_total      BIGINT := 0;
    v_total_cost BIGINT := 0;
BEGIN
    -- Idempotency check
    IF p_client_id IS NOT NULL THEN
        SELECT id INTO v_order_id FROM orders WHERE client_id = p_client_id;
        IF v_order_id IS NOT NULL THEN RETURN v_order_id; END IF;
    END IF;

    -- Device token verification if customer account is established
    IF v_cust_id IS NOT NULL THEN
        SELECT price_tier, device_token INTO v_tier, v_stored_token FROM customers WHERE id = v_cust_id;
        IF v_stored_token IS NOT NULL AND v_stored_token <> '' THEN
            IF p_device_token IS NULL OR trim(p_device_token) <> v_stored_token THEN
                RAISE EXCEPTION 'فشل التحقق من أمان الجهاز المرتبط بالطلب.';
            END IF;
        END IF;
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
        v_qty := (v_item->>'quantity')::INT;
        IF v_qty <= 0 THEN CONTINUE; END IF;

        SELECT price INTO v_unit_price
        FROM product_prices
        WHERE product_id = v_product_id AND tier = v_tier AND min_qty <= v_qty
        ORDER BY min_qty DESC LIMIT 1;

        IF v_unit_price IS NULL THEN
            SELECT price INTO v_unit_price FROM product_prices WHERE product_id = v_product_id ORDER BY min_qty ASC LIMIT 1;
        END IF;

        IF v_unit_price IS NULL THEN v_unit_price := 0; END IF;

        SELECT COALESCE(last_unit_cost, 0) INTO v_unit_cost FROM products WHERE id = v_product_id;

        v_total := v_total + (v_qty * v_unit_price);
        v_total_cost := v_total_cost + (v_qty * v_unit_cost);

        INSERT INTO order_items (order_id, product_id, quantity, unit_price, unit_cost)
        VALUES (v_order_id, v_product_id, v_qty, v_unit_price, v_unit_cost);
    END LOOP;

    UPDATE orders SET total_amount = v_total, total_cost = v_total_cost WHERE id = v_order_id;
    RETURN v_order_id;
END;
$$;
GRANT EXECUTE ON FUNCTION rpc_submit_customer_order(UUID, UUID, JSONB, JSONB, TEXT) TO anon, authenticated;

-- Force PostgREST reload
NOTIFY pgrst, 'reload schema';


-- ============================================================================
-- 00026 - resilience and scalability
-- Source: archive/migrations/00026_resilience_and_scalability.sql
-- ============================================================================
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


-- ============================================================================
-- 00027 - audit log minimization
-- Source: archive/migrations/00027_audit_log_minimization.sql
-- ============================================================================
-- ============================================================
-- MIGRATION 00027: AUDIT LOG MINIMIZATION
--
-- Reduces audit_log row growth by removing per-row audit triggers
-- from high-frequency, low-value tables. Critical financial and
-- security tables retain full before/after JSONB audit logging.
--
-- Safety: This migration only DROPS TRIGGERS. No tables, columns,
-- or existing data are removed. Existing audit_log rows are preserved.
-- ============================================================

-- ------------------------------------------------------------------
-- 1. DROP universal audit triggers on high-frequency, low-value tables
-- ------------------------------------------------------------------

-- Driver GPS pings: audited via event-based table in migration 00028.
DROP TRIGGER IF EXISTS trg_audit_driver_locations ON driver_locations;

-- Order line items: already tied to audited orders header; no separate audit needed.
DROP TRIGGER IF EXISTS trg_audit_order_items ON order_items;

-- Stock ledger: append-only ledger is itself the audit trail; no double-logging.
DROP TRIGGER IF EXISTS trg_audit_stock_ledger ON stock_ledger;

-- Payments: audited via orders header + wallet_entries + settlements.
DROP TRIGGER IF EXISTS trg_audit_payments ON payments;

-- ------------------------------------------------------------------
-- 2. RETAIN audit triggers on critical tables (no change needed here;
--    triggers created in migration 00022 remain active):
--    - orders (header create/status change)
--    - settlements (financial close)
--    - wallet_entries (driver cash movement)
--    - users (role updates, PIN changes, staff create)
--    - customers (credit limit changes)
--    - suppliers (create/payment)
--    - purchases (posted/cancelled)
--    - audit_log (tamper protection)
-- ------------------------------------------------------------------

-- ------------------------------------------------------------------
-- 3. Slim down the trigger function: stop storing full before/after
--    JSONB for high-volume tables. Critical tables keep full JSONB;
--    other retained tables get a compact changed-fields summary.
-- ------------------------------------------------------------------

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
    v_changes JSONB := '{}'::jsonb;
BEGIN
    -- Resolve actor from auth.uid() or record fields
    BEGIN
        v_user_id := auth.uid();
    EXCEPTION WHEN OTHERS THEN
        v_user_id := NULL;
    END;

    -- Extract target id
    IF TG_OP = 'INSERT' THEN
        BEGIN
            v_target_id := (NEW.id)::UUID;
        EXCEPTION WHEN OTHERS THEN
            v_target_id := NULL;
        END;
    ELSIF TG_OP = 'UPDATE' THEN
        BEGIN
            v_target_id := (NEW.id)::UUID;
        EXCEPTION WHEN OTHERS THEN
            v_target_id := NULL;
        END;
    ELSIF TG_OP = 'DELETE' THEN
        BEGIN
            v_target_id := (OLD.id)::UUID;
        EXCEPTION WHEN OTHERS THEN
            v_target_id := NULL;
        END;
    END IF;

    -- Deduce user_id from record fields when auth.uid() is NULL (anon role)
    IF v_user_id IS NULL THEN
        IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
            IF TG_TABLE_NAME = 'orders' AND (NEW ? 'cashier_id') AND (NEW->>'cashier_id') IS NOT NULL THEN
                v_user_id := (NEW->>'cashier_id')::UUID;
            ELSIF TG_TABLE_NAME = 'wallet_entries' AND (NEW ? 'driver_id') AND (NEW->>'driver_id') IS NOT NULL THEN
                v_user_id := (NEW->>'driver_id')::UUID;
            ELSIF TG_TABLE_NAME = 'settlements' AND (NEW ? 'cashier_id') AND (NEW->>'cashier_id') IS NOT NULL THEN
                v_user_id := (NEW->>'cashier_id')::UUID;
            ELSIF TG_TABLE_NAME = 'users' THEN
                v_user_id := v_target_id;
            END IF;
        END IF;
    END IF;

    -- Build before/after JSONB only for critical tables; skip for others.
    IF TG_TABLE_NAME IN ('orders', 'settlements', 'wallet_entries', 'users', 'customers', 'suppliers', 'purchases') THEN
        IF TG_OP = 'INSERT' THEN
            v_after := to_jsonb(NEW);
        ELSIF TG_OP = 'UPDATE' THEN
            v_before := to_jsonb(OLD);
            v_after := to_jsonb(NEW);
            -- Compute compact changed-fields summary
            v_changes := '{}'::jsonb;
        ELSIF TG_OP = 'DELETE' THEN
            v_before := to_jsonb(OLD);
        END IF;
    END IF;

    -- Insert audit record
    INSERT INTO audit_log (user_id, action, target_table, target_id, before_state, after_state)
    VALUES (v_user_id, TG_OP, TG_TABLE_NAME, v_target_id, v_before, v_after);

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$;


-- ============================================================================
-- 00028 - driver telemetry optimization
-- Source: archive/migrations/00028_driver_telemetry_optimization.sql
-- ============================================================================
-- ============================================================
-- MIGRATION 00028: DRIVER TELEMETRY OPTIMIZATION
--
-- Replaces per-ping audit logging on driver_locations with
-- event-based auditing in a new driver_location_events table.
-- The driver_locations table is kept for real-time map display
-- (latest location only) but is no longer audited on every upsert.
--
-- Safety: No tables or columns are dropped. A new table is added.
-- Existing driver_locations data is preserved.
-- ============================================================

-- ------------------------------------------------------------------
-- 1. New table: driver_location_events (event-based auditing)
--    Logs only significant events: trip start/end, clock-in/out,
--    geofence entry/exit. Not every GPS ping.
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS driver_location_events (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id    UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    event_type   TEXT        NOT NULL, -- 'trip_start', 'trip_end', 'clock_in', 'clock_out', 'geofence_entry', 'geofence_exit'
    latitude     DOUBLE PRECISION,
    longitude    DOUBLE PRECISION,
    recorded_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_driver_location_events_driver_id
    ON driver_location_events(driver_id);
CREATE INDEX IF NOT EXISTS idx_driver_location_events_recorded_at
    ON driver_location_events(recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_driver_location_events_type
    ON driver_location_events(event_type);

-- ------------------------------------------------------------------
-- 2. Remove per-ping audit trigger on driver_locations
--    (trigger dropped, table preserved for real-time map display)
-- ------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_audit_driver_locations ON driver_locations;

-- ------------------------------------------------------------------
-- 3. Add audit trigger on driver_location_events for event auditing
-- ------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_audit_driver_location_events()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    INSERT INTO audit_log (user_id, action, target_table, target_id, after_state)
    VALUES (
        NEW.driver_id,
        'DRIVER_LOCATION_EVENT',
        'driver_location_events',
        NEW.id,
        jsonb_build_object(
            'event_type', NEW.event_type,
            'driver_id', NEW.driver_id,
            'latitude', NEW.latitude,
            'longitude', NEW.longitude,
            'recorded_at', NEW.recorded_at
        )
    );
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_audit_driver_location_events
AFTER INSERT ON driver_location_events
FOR EACH ROW EXECUTE FUNCTION trg_audit_driver_location_events();


-- ============================================================================
-- 00029 - stock balance summaries
-- Source: archive/migrations/00029_stock_balance_summaries.sql
-- ============================================================================
-- ============================================================
-- MIGRATION 00029: INCREMENTAL STOCK / BALANCE SUMMARY TABLES
--
-- Replaces O(N) full-ledger aggregation views with incrementally
-- maintained summary tables. Views remain defined for backward
-- compatibility; new repository code paths read from snapshots.
--
-- Safety: New tables only. No existing table, column, or view is
-- modified or dropped. Existing views continue to work.
-- ============================================================

-- ------------------------------------------------------------------
-- 1. Product stock snapshot (maintained by trigger on stock_ledger)
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS product_stock_snapshot (
    product_id    UUID        PRIMARY KEY REFERENCES products(id) ON DELETE CASCADE,
    on_hand_qty   INT         NOT NULL DEFAULT 0,
    reserved_qty  INT         NOT NULL DEFAULT 0,
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION trg_maintain_product_stock_snapshot()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    INSERT INTO product_stock_snapshot (product_id, on_hand_qty, updated_at)
    VALUES (NEW.product_id, NEW.qty_change, NOW())
    ON CONFLICT (product_id)
    DO UPDATE SET
        on_hand_qty = product_stock_snapshot.on_hand_qty + NEW.qty_change,
        updated_at = NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_maintain_product_stock_snapshot
AFTER INSERT ON stock_ledger
FOR EACH ROW EXECUTE FUNCTION trg_maintain_product_stock_snapshot();

-- ------------------------------------------------------------------
-- 2. Customer balance snapshot (maintained by trigger on customer_ledger)
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS customer_balance_snapshot (
    customer_id   UUID        PRIMARY KEY REFERENCES customers(id) ON DELETE CASCADE,
    current_balance BIGINT    NOT NULL DEFAULT 0,
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION trg_maintain_customer_balance_snapshot()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    INSERT INTO customer_balance_snapshot (customer_id, current_balance, updated_at)
    VALUES (NEW.customer_id, NEW.amount_change, NOW())
    ON CONFLICT (customer_id)
    DO UPDATE SET
        current_balance = customer_balance_snapshot.current_balance + NEW.amount_change,
        updated_at = NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_maintain_customer_balance_snapshot
AFTER INSERT ON customer_ledger
FOR EACH ROW EXECUTE FUNCTION trg_maintain_customer_balance_snapshot();

-- ------------------------------------------------------------------
-- 3. Driver wallet snapshot (maintained by trigger on wallet_entries)
--    Sign rules: collection (+), handover (-), overage (+), shortage (-), reversal (-)
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS driver_wallet_snapshot (
    driver_id             UUID        PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    current_wallet_balance BIGINT     NOT NULL DEFAULT 0,
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION trg_maintain_driver_wallet_snapshot()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_delta BIGINT := 0;
BEGIN
    CASE NEW.type
        WHEN 'collection'  THEN v_delta := NEW.amount;
        WHEN 'handover'    THEN v_delta := -NEW.amount;
        WHEN 'overage'     THEN v_delta := NEW.amount;
        WHEN 'shortage'    THEN v_delta := -NEW.amount;
        WHEN 'reversal'    THEN v_delta := -NEW.amount;
        ELSE v_delta := 0;
    END CASE;

    INSERT INTO driver_wallet_snapshot (driver_id, current_wallet_balance, updated_at)
    VALUES (NEW.driver_id, v_delta, NOW())
    ON CONFLICT (driver_id)
    DO UPDATE SET
        current_wallet_balance = driver_wallet_snapshot.current_wallet_balance + v_delta,
        updated_at = NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_maintain_driver_wallet_snapshot
AFTER INSERT ON wallet_entries
FOR EACH ROW EXECUTE FUNCTION trg_maintain_driver_wallet_snapshot();

-- ------------------------------------------------------------------
-- 4. Supplier balance snapshot (maintained by trigger on supplier_ledger)
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS supplier_balance_snapshot (
    supplier_id   UUID        PRIMARY KEY REFERENCES suppliers(id) ON DELETE CASCADE,
    current_balance BIGINT    NOT NULL DEFAULT 0,
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION trg_maintain_supplier_balance_snapshot()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    INSERT INTO supplier_balance_snapshot (supplier_id, current_balance, updated_at)
    VALUES (NEW.supplier_id, NEW.amount_change, NOW())
    ON CONFLICT (supplier_id)
    DO UPDATE SET
        current_balance = supplier_balance_snapshot.current_balance + NEW.amount_change,
        updated_at = NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_maintain_supplier_balance_snapshot
AFTER INSERT ON supplier_ledger
FOR EACH ROW EXECUTE FUNCTION trg_maintain_supplier_balance_snapshot();

-- ------------------------------------------------------------------
-- 5. Backfill snapshots from existing ledger data (one-time)
-- ------------------------------------------------------------------
INSERT INTO product_stock_snapshot (product_id, on_hand_qty, updated_at)
SELECT product_id, COALESCE(SUM(qty_change), 0), NOW()
FROM stock_ledger
GROUP BY product_id
ON CONFLICT (product_id) DO NOTHING;

INSERT INTO customer_balance_snapshot (customer_id, current_balance, updated_at)
SELECT customer_id, COALESCE(SUM(amount_change), 0), NOW()
FROM customer_ledger
GROUP BY customer_id
ON CONFLICT (customer_id) DO NOTHING;

INSERT INTO driver_wallet_snapshot (driver_id, current_wallet_balance, updated_at)
SELECT
    driver_id,
    COALESCE(SUM(
        CASE type
            WHEN 'collection' THEN amount
            WHEN 'handover' THEN -amount
            WHEN 'overage' THEN amount
            WHEN 'shortage' THEN -amount
            WHEN 'reversal' THEN -amount
            ELSE 0
        END
    ), 0),
    NOW()
FROM wallet_entries
GROUP BY driver_id
ON CONFLICT (driver_id) DO NOTHING;

INSERT INTO supplier_balance_snapshot (supplier_id, current_balance, updated_at)
SELECT supplier_id, COALESCE(SUM(amount_change), 0), NOW()
FROM supplier_ledger
GROUP BY supplier_id
ON CONFLICT (supplier_id) DO NOTHING;


-- ============================================================================
-- 00030 - audit log partitioning readiness
-- Source: archive/migrations/00030_audit_log_partitioning_readiness.sql
-- ============================================================================
-- ============================================================
-- MIGRATION 00030: AUDIT LOG PARTITIONING READINESS + INDEXES
--
-- Adds composite indexes for high-query columns and creates a
-- partitioned audit_log table structure for future monthly
-- partitioning. The existing audit_log table is preserved; new
-- partitions can be attached as needed.
--
-- Safety: Additive only. Existing audit_log table and data preserved.
-- ============================================================

-- ------------------------------------------------------------------
-- 1. Composite indexes on audit_log for common query patterns
-- ------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_audit_log_created_table
    ON audit_log(created_at DESC, target_table);

CREATE INDEX IF NOT EXISTS idx_audit_log_user_created
    ON audit_log(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_audit_log_action_created
    ON audit_log(action, created_at DESC);

-- ------------------------------------------------------------------
-- 2. Composite indexes on business tables for dashboard queries
-- ------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_orders_created_status
    ON orders(created_at DESC, status);

CREATE INDEX IF NOT EXISTS idx_orders_customer_created
    ON orders(customer_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_order_items_order_product
    ON order_items(order_id, product_id);

CREATE INDEX IF NOT EXISTS idx_stock_ledger_product_created
    ON stock_ledger(product_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_wallet_entries_driver_created
    ON wallet_entries(driver_id, created_at DESC);

-- ------------------------------------------------------------------
-- 3. Partitioned audit_log table (readiness for future monthly partitioning)
--    The existing audit_log table is kept for historical data.
--    New partitions can be created and data migrated in a later step.
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS audit_log_partitioned (
    id           BIGSERIAL,
    user_id      UUID        REFERENCES users(id),
    action       VARCHAR(50) NOT NULL,
    target_table VARCHAR(50) NOT NULL,
    target_id    UUID,
    before_state JSONB,
    after_state  JSONB,
    ip_address   INET,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
) PARTITION BY RANGE (created_at);

-- Create monthly partitions for the next 12 months (readiness)
DO $$
DECLARE
    m_start DATE := date_trunc('month', CURRENT_DATE)::date;
    m_end   DATE;
    part_name TEXT;
BEGIN
    FOR i IN 0..11 LOOP
        m_start := (date_trunc('month', CURRENT_DATE) + (i || ' months')::interval)::date;
        m_end   := (m_start + interval '1 month')::date;
        part_name := 'audit_log_' || to_char(m_start, 'YYYY_MM');
        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS %I PARTITION OF audit_log_partitioned FOR VALUES FROM (%L) TO (%L)',
            part_name, m_start, m_end
        );
    END LOOP;
END $$;

-- ------------------------------------------------------------------
-- 4. Indexes on partitioned table
-- ------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_audit_log_partitioned_created
    ON audit_log_partitioned(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_audit_log_partitioned_target
    ON audit_log_partitioned(target_table, target_id);


-- ============================================================================
-- 00031 - offline sync resilience
-- Source: archive/migrations/00031_offline_sync_resilience.sql
-- ============================================================================
-- ============================================================
-- MIGRATION 00031: OFFLINE SYNC RESILIENCE
--
-- Adds conflict-policy metadata to pending_operations and a
-- failed_operations table for permanently-failed sync items.
-- No existing tables or columns are dropped.
-- ============================================================

-- ------------------------------------------------------------------
-- 1. Add conflict-policy and last-attempt columns to pending_operations
-- ------------------------------------------------------------------
-- pending_operations is a client-side (Drift) table. It only exists in
-- PostgreSQL on installations that created it manually, so guard the ALTERs.
DO $$
BEGIN
    IF to_regclass('public.pending_operations') IS NOT NULL THEN
        ALTER TABLE pending_operations
            ADD COLUMN IF NOT EXISTS conflict_policy TEXT DEFAULT 'server_wins';

        ALTER TABLE pending_operations
            ADD COLUMN IF NOT EXISTS last_attempt_at TIMESTAMPTZ;
    END IF;
END $$;

-- ------------------------------------------------------------------
-- 2. Failed operations table: permanently-failed sync items that
--    require manual intervention (e.g., stock conflict needing manager
--    review, invalid customer reference, duplicate key that cannot be
--    resolved automatically).
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS failed_operations (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id      UUID        NOT NULL,
    operation_type TEXT        NOT NULL,
    payload_json   TEXT        NOT NULL,
    last_error     TEXT        NOT NULL,
    retry_count    INT         NOT NULL DEFAULT 0,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_attempted TIMESTAMPTZ,
    resolved       BOOLEAN     NOT NULL DEFAULT FALSE,
    resolution_note TEXT
);

CREATE INDEX IF NOT EXISTS idx_failed_operations_client_id
    ON failed_operations(client_id);
CREATE INDEX IF NOT EXISTS idx_failed_operations_resolved
    ON failed_operations(resolved);
CREATE INDEX IF NOT EXISTS idx_failed_operations_created_at
    ON failed_operations(created_at DESC);


-- ============================================================================
-- 00032 - permission repair
-- Source: archive/migrations/00032_permission_repair.sql
-- ============================================================================
-- ============================================================
-- 00032_permission_repair.sql
--
-- PURPOSE
--   Repair the 42501 "permission denied for table users" failures
--   introduced by migration 00024, repair the broken audit trigger
--   introduced by migration 00027, and reconcile client grants/RLS
--   across the schema.
--
-- WHAT THIS MIGRATION DOES
--   1. Fixes trigger_audit_log_func():
--      - replaces the invalid composite-row `NEW ? 'column'` checks
--        with to_jsonb(NEW) lookups (fixes 42883 on every order,
--        wallet_entries, and settlements write);
--      - removes pin_code / device_token from audit payloads;
--      - redacts those keys from historical audit rows.
--   2. Adds rpc_save_user_profile(...) for staff self-service and
--      moderator profile editing. The caller proves identity with
--      their own PIN; the target's old PIN is never required.
--   3. Adds rpc_create_customer_by_staff(...) so cashiers can create
--      customers without direct INSERT rights on users/customers.
--   4. Adds rpc_record_supplier_payment(...) for idempotent supplier
--      payments, replacing direct ledger writes.
--   5. Reconciles grants:
--      - users/customers are read-only to clients, with column-level
--        SELECT that excludes pin_code / device_token;
--      - sensitive tables are writable only through SECURITY DEFINER
--        RPCs;
--      - orders keeps a narrow UPDATE(status, driver_id, notes) for
--        the existing status-sync path;
--      - append-only telemetry tables keep INSERT but lose UPDATE/
--        DELETE and gain RLS.
--   6. Re-grants SELECT on all reporting views and reloads PostgREST.
--
-- HOW TO APPLY
--   Run this whole file in the Supabase SQL editor as the project
--   owner (postgres). It is written to be idempotent.
--
-- VERIFY AFTER APPLYING
--   SELECT has_column_privilege('anon','public.users','pin_code','SELECT');        -- must be false
--   SELECT has_column_privilege('anon','public.customers','device_token','SELECT');-- must be false
--   SELECT has_table_privilege('anon','public.users','UPDATE');                     -- must be false
--   SELECT has_table_privilege('anon','public.customers','UPDATE');                 -- must be false
--   SELECT has_table_privilege('anon','public.orders','INSERT');                    -- must be false
--   SELECT has_column_privilege('anon','public.orders','status','UPDATE');          -- must be true
--   SELECT has_column_privilege('anon','public.orders','total_amount','UPDATE');    -- must be false
--   SELECT p.oid::regprocedure, has_function_privilege('anon', p.oid, 'EXECUTE')
--   FROM pg_proc p
--   WHERE p.pronamespace = 'public'::regnamespace
--     AND p.proname IN ('rpc_save_user_profile','rpc_create_customer_by_staff',
--                       'rpc_record_supplier_payment','rpc_submit_customer_order',
--                       'rpc_post_store_sale','rpc_update_user_profile',
--                       'rpc_sync_customer_profile')
--   ORDER BY p.proname;
--   -- Expected: the first five are true; the last two are false.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- PART 1: FIX THE AUDIT TRIGGER (42883)
-- ============================================================

CREATE OR REPLACE FUNCTION trigger_audit_log_func()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_user_id   UUID := NULL;
    v_before    JSONB := NULL;
    v_after     JSONB := NULL;
    v_new_json  JSONB := NULL;
    v_old_json  JSONB := NULL;
    v_target_id UUID := NULL;
BEGIN
    -- Fast exit during batch maintenance / archival cleanup
    IF current_setting('app.maintenance_mode', true) = 'true' THEN
        RETURN COALESCE(NEW, OLD);
    END IF;

    -- Resolve actor from auth.uid() when a JWT exists.
    BEGIN
        v_user_id := auth.uid();
    EXCEPTION WHEN OTHERS THEN
        v_user_id := NULL;
    END;

    -- Convert composite rows to JSONB once. Composite records do not
    -- support the jsonb `?` operator; to_jsonb(NEW) does.
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        v_new_json := to_jsonb(NEW) - 'pin_code' - 'device_token';
    END IF;
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        v_old_json := to_jsonb(OLD) - 'pin_code' - 'device_token';
    END IF;

    -- Extract target id.
    BEGIN
        v_target_id := COALESCE(v_new_json->>'id', v_old_json->>'id')::UUID;
    EXCEPTION WHEN OTHERS THEN
        v_target_id := NULL;
    END;

    -- Deduce actor from record fields for anon clients.
    IF v_user_id IS NULL AND v_new_json IS NOT NULL THEN
        BEGIN
            IF TG_TABLE_NAME = 'orders' THEN
                v_user_id := NULLIF(v_new_json->>'cashier_id', '')::UUID;
            ELSIF TG_TABLE_NAME = 'wallet_entries' THEN
                v_user_id := NULLIF(v_new_json->>'driver_id', '')::UUID;
            ELSIF TG_TABLE_NAME = 'settlements' THEN
                v_user_id := NULLIF(v_new_json->>'cashier_id', '')::UUID;
            ELSIF TG_TABLE_NAME = 'users' THEN
                v_user_id := v_target_id;
            END IF;
        EXCEPTION WHEN OTHERS THEN
            v_user_id := NULL;
        END;
    END IF;

    -- Keep full before/after only for critical tables.
    IF TG_TABLE_NAME IN (
        'orders', 'settlements', 'wallet_entries', 'users',
        'customers', 'suppliers', 'purchases'
    ) THEN
        IF TG_OP = 'INSERT' THEN
            v_after := v_new_json;
        ELSIF TG_OP = 'UPDATE' THEN
            v_before := v_old_json;
            v_after := v_new_json;
        ELSIF TG_OP = 'DELETE' THEN
            v_before := v_old_json;
        END IF;
    END IF;

    INSERT INTO audit_log (
        user_id, action, target_table, target_id, before_state, after_state
    ) VALUES (
        v_user_id, TG_OP, TG_TABLE_NAME, v_target_id, v_before, v_after
    );

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

-- Redact credentials from historical audit rows. The trigger above
-- prevents new rows from storing them.
UPDATE audit_log
SET before_state = before_state - 'pin_code' - 'device_token',
    after_state  = after_state  - 'pin_code' - 'device_token'
WHERE target_table IN ('users', 'customers')
  AND (
      (before_state IS NOT NULL AND (before_state ? 'pin_code' OR before_state ? 'device_token'))
      OR
      (after_state IS NOT NULL AND (after_state ? 'pin_code' OR after_state ? 'device_token'))
  );

-- ============================================================
-- PART 2: PROFILE SAVE RPC
-- ============================================================

CREATE OR REPLACE FUNCTION rpc_save_user_profile(
    p_caller_id UUID,
    p_caller_pin TEXT,
    p_target_user_id UUID,
    p_name VARCHAR,
    p_phone VARCHAR,
    p_language VARCHAR DEFAULT 'ar',
    p_role TEXT DEFAULT NULL,
    p_active BOOLEAN DEFAULT NULL,
    p_new_pin TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_auth_check JSONB;
    v_caller users%ROWTYPE;
    v_target users%ROWTYPE;
    v_is_moderator BOOLEAN := FALSE;
    v_clean_name VARCHAR;
    v_clean_phone VARCHAR;
    v_new_language VARCHAR;
    v_new_role user_role;
    v_new_active BOOLEAN;
    v_new_pin TEXT;
    v_other_moderators INT := 0;
BEGIN
    -- 1. Verify the caller with their own PIN.
    v_auth_check := _internal_verify_and_track_pin(p_caller_id, p_caller_pin, FALSE);
    IF COALESCE((v_auth_check->>'valid')::BOOLEAN, FALSE) IS NOT TRUE THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', COALESCE(v_auth_check->>'message', 'فشل التحقق من هوية المستخدم أو رمز PIN')
        );
    END IF;

    SELECT * INTO v_caller FROM users WHERE id = p_caller_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'المستخدم غير موجود');
    END IF;
    v_is_moderator := (v_caller.role = 'moderator');

    -- 2. Non-moderators may only edit themselves.
    IF NOT v_is_moderator AND p_caller_id <> p_target_user_id THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'لا تملك صلاحية تعديل بيانات مستخدم آخر'
        );
    END IF;

    SELECT * INTO v_target FROM users WHERE id = p_target_user_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'الموظف غير موجود');
    END IF;

    -- 3. Validate profile fields.
    v_clean_name := trim(COALESCE(p_name, ''));
    IF LENGTH(v_clean_name) < 2 OR LENGTH(v_clean_name) > 100 THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'الاسم يجب أن يتكون من 2 إلى 100 حرف');
    END IF;

    v_clean_phone := trim(COALESCE(p_phone, ''));
    IF v_clean_phone !~ '^0[0-9]{8,14}$' THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'رقم الهاتف غير صالح (يجب أن يبدأ بـ 0 ويتكون من 9 إلى 15 رقماً)'
        );
    END IF;

    IF EXISTS (
        SELECT 1 FROM users
        WHERE phone = v_clean_phone AND id <> p_target_user_id
    ) THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'رقم الهاتف مستخدم بالفعل من قبل حساب آخر');
    END IF;

    v_new_language := COALESCE(NULLIF(trim(p_language), ''), v_target.language);
    IF v_new_language NOT IN ('ar', 'fr') THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'اللغة غير مدعومة');
    END IF;

    -- 4. Role/active changes are moderator-only.
    IF (p_role IS NOT NULL AND trim(p_role) <> '') OR p_active IS NOT NULL THEN
        IF NOT v_is_moderator THEN
            RETURN jsonb_build_object(
                'status', 'error',
                'message', 'لا تملك صلاحية تغيير الدور أو حالة الحساب'
            );
        END IF;
    END IF;

    v_new_role := v_target.role;
    IF p_role IS NOT NULL AND trim(p_role) <> '' THEN
        IF trim(p_role) NOT IN ('moderator', 'manager', 'cashier', 'driver') THEN
            RETURN jsonb_build_object('status', 'error', 'message', 'الدور الوظيفي غير صالح');
        END IF;
        v_new_role := trim(p_role)::user_role;
    END IF;
    v_new_active := COALESCE(p_active, v_target.active);

    -- 5. Never allow the last active moderator to be demoted or disabled.
    IF v_target.role = 'moderator'
       AND v_target.active = TRUE
       AND (v_new_role <> 'moderator' OR v_new_active = FALSE)
    THEN
        SELECT COUNT(*) INTO v_other_moderators
        FROM users
        WHERE role = 'moderator'
          AND active = TRUE
          AND id <> p_target_user_id;

        IF v_other_moderators = 0 THEN
            RETURN jsonb_build_object(
                'status', 'error',
                'message', 'لا يمكن تعطيل أو تغيير دور آخر مشرف عام نشط'
            );
        END IF;
    END IF;

    -- 6. Optional new PIN for the target. The caller's PIN above is the
    --    authorization proof, so a moderator resetting another staff
    --    member's PIN does not need that staff member's old PIN.
    v_new_pin := NULLIF(trim(p_new_pin), '');
    IF v_new_pin IS NOT NULL AND v_new_pin !~ '^[0-9]{4,8}$' THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'رمز PIN الجديد يجب أن يتكون من 4 إلى 8 أرقام'
        );
    END IF;

    -- 7. Apply the update.
    UPDATE users
    SET name       = v_clean_name,
        phone      = v_clean_phone,
        language   = v_new_language,
        role       = v_new_role,
        active     = v_new_active,
        pin_code   = CASE
                         WHEN v_new_pin IS NOT NULL
                         THEN crypt(v_new_pin, gen_salt('bf'))
                         ELSE pin_code
                     END,
        updated_at = NOW()
    WHERE id = p_target_user_id;

    -- 8. Explicit audit entry (never includes the PIN hash).
    INSERT INTO audit_log (
        user_id, action, target_table, target_id, before_state, after_state
    ) VALUES (
        p_caller_id,
        'USER_PROFILE_UPDATED',
        'users',
        p_target_user_id,
        jsonb_build_object(
            'name', v_target.name,
            'phone', v_target.phone,
            'role', v_target.role,
            'active', v_target.active,
            'language', v_target.language
        ),
        jsonb_build_object(
            'name', v_clean_name,
            'phone', v_clean_phone,
            'role', v_new_role,
            'active', v_new_active,
            'language', v_new_language,
            'pin_changed', (v_new_pin IS NOT NULL)
        )
    );

    RETURN jsonb_build_object(
        'status', 'success',
        'message', 'تم تحديث البيانات بنجاح',
        'user_id', p_target_user_id,
        'name', v_clean_name,
        'phone', v_clean_phone,
        'role', v_new_role,
        'active', v_new_active,
        'language', v_new_language
    );
END;
$$;

REVOKE ALL ON FUNCTION rpc_save_user_profile(
    UUID, TEXT, UUID, VARCHAR, VARCHAR, VARCHAR, TEXT, BOOLEAN, TEXT
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_save_user_profile(
    UUID, TEXT, UUID, VARCHAR, VARCHAR, VARCHAR, TEXT, BOOLEAN, TEXT
) TO anon, authenticated;

-- ============================================================
-- PART 3: STAFF-CREATED CUSTOMER RPC
-- ============================================================

CREATE OR REPLACE FUNCTION rpc_create_customer_by_staff(
    p_caller_id UUID,
    p_caller_pin TEXT,
    p_name VARCHAR,
    p_phone VARCHAR,
    p_credit_limit BIGINT DEFAULT 0,
    p_price_tier TEXT DEFAULT 'wholesale'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_auth_check JSONB;
    v_caller users%ROWTYPE;
    v_clean_name VARCHAR;
    v_clean_phone VARCHAR;
    v_tier price_tier := 'wholesale';
    v_user_id UUID;
    v_customer_id UUID;
BEGIN
    v_auth_check := _internal_verify_and_track_pin(p_caller_id, p_caller_pin, FALSE);
    IF COALESCE((v_auth_check->>'valid')::BOOLEAN, FALSE) IS NOT TRUE THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', COALESCE(v_auth_check->>'message', 'فشل التحقق من هوية المستخدم أو رمز PIN')
        );
    END IF;

    SELECT * INTO v_caller FROM users WHERE id = p_caller_id;
    IF NOT FOUND OR v_caller.role NOT IN ('moderator', 'manager', 'cashier') THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'هذه العملية متاحة للمشرف أو مدير المخزون أو أمين الصندوق فقط'
        );
    END IF;

    v_clean_name := trim(COALESCE(p_name, ''));
    IF LENGTH(v_clean_name) < 2 OR LENGTH(v_clean_name) > 100 THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'اسم الزبون يجب أن يتكون من 2 إلى 100 حرف');
    END IF;

    v_clean_phone := trim(COALESCE(p_phone, ''));
    IF v_clean_phone !~ '^0[5-7][0-9]{8}$' THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'رقم هاتف الزبون غير صالح (يجب أن يبدأ بـ 05 أو 06 أو 07)'
        );
    END IF;

    IF COALESCE(p_credit_limit, 0) < 0 THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'سقف الائتمان لا يمكن أن يكون سالباً');
    END IF;

    IF p_price_tier IS NOT NULL AND trim(p_price_tier) <> '' THEN
        IF trim(p_price_tier) NOT IN ('retail', 'wholesale', 'bulk') THEN
            RETURN jsonb_build_object('status', 'error', 'message', 'فئة السعر غير صالحة');
        END IF;
        v_tier := trim(p_price_tier)::price_tier;
    END IF;

    IF EXISTS (SELECT 1 FROM users WHERE phone = v_clean_phone) THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'رقم الهاتف مسجل بالفعل. ابحث عن الزبون في القائمة بدلاً من إنشاء حساب جديد.'
        );
    END IF;

    INSERT INTO users (name, phone, role, language, active)
    VALUES (v_clean_name, v_clean_phone, 'customer', 'ar', TRUE)
    RETURNING id INTO v_user_id;

    INSERT INTO customers (user_id, credit_limit, price_tier)
    VALUES (v_user_id, COALESCE(p_credit_limit, 0), v_tier)
    RETURNING id INTO v_customer_id;

    INSERT INTO audit_log (
        user_id, action, target_table, target_id, after_state
    ) VALUES (
        p_caller_id,
        'CUSTOMER_CREATED_BY_STAFF',
        'customers',
        v_customer_id,
        jsonb_build_object(
            'customer_id', v_customer_id,
            'user_id', v_user_id,
            'name', v_clean_name,
            'phone', v_clean_phone,
            'credit_limit', COALESCE(p_credit_limit, 0),
            'price_tier', v_tier
        )
    );

    RETURN jsonb_build_object(
        'status', 'success',
        'message', 'تم تسجيل الزبون بنجاح',
        'customer_id', v_customer_id,
        'user_id', v_user_id,
        'name', v_clean_name,
        'phone', v_clean_phone,
        'credit_limit', COALESCE(p_credit_limit, 0),
        'price_tier', v_tier
    );
END;
$$;

REVOKE ALL ON FUNCTION rpc_create_customer_by_staff(
    UUID, TEXT, VARCHAR, VARCHAR, BIGINT, TEXT
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_create_customer_by_staff(
    UUID, TEXT, VARCHAR, VARCHAR, BIGINT, TEXT
) TO anon, authenticated;

-- ============================================================
-- PART 4: IDEMPOTENT SUPPLIER PAYMENT RPC
-- ============================================================

ALTER TABLE supplier_ledger
    ADD COLUMN IF NOT EXISTS client_id UUID;

CREATE UNIQUE INDEX IF NOT EXISTS idx_supplier_ledger_client_id
    ON supplier_ledger(client_id)
    WHERE client_id IS NOT NULL;

-- Drop the earlier draft signature if it was ever applied manually.
DROP FUNCTION IF EXISTS rpc_record_supplier_payment(
    UUID, UUID, BIGINT, UUID, UUID, TEXT
);

CREATE OR REPLACE FUNCTION rpc_record_supplier_payment(
    p_client_id UUID,
    p_supplier_id UUID,
    p_amount BIGINT,
    p_payer_user_id UUID,
    p_purchase_id UUID DEFAULT NULL,
    p_notes TEXT DEFAULT NULL,
    p_caller_pin TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_auth_check JSONB;
    v_caller users%ROWTYPE;
    v_existing supplier_ledger%ROWTYPE;
    v_supplier suppliers%ROWTYPE;
BEGIN
    IF p_client_id IS NULL THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'معرف العملية مطلوب');
    END IF;

    -- The payer is the caller. Require the payer's own PIN, because the
    -- anon key alone must never authorize a financial write.
    v_auth_check := _internal_verify_and_track_pin(
        p_payer_user_id, p_caller_pin, FALSE
    );
    IF COALESCE((v_auth_check->>'valid')::BOOLEAN, FALSE) IS NOT TRUE THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', COALESCE(v_auth_check->>'message', 'فشل التحقق من هوية المستخدم أو رمز PIN')
        );
    END IF;

    SELECT * INTO v_caller FROM users WHERE id = p_payer_user_id;
    IF NOT FOUND OR v_caller.role NOT IN ('moderator', 'manager', 'cashier') THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'هذه العملية متاحة للمشرف أو مدير المخزون أو أمين الصندوق فقط'
        );
    END IF;

    SELECT * INTO v_existing FROM supplier_ledger WHERE client_id = p_client_id;
    IF FOUND THEN
        RETURN jsonb_build_object(
            'status', 'already_processed',
            'ledger_id', v_existing.id,
            'client_id', p_client_id
        );
    END IF;

    IF p_amount IS NULL OR p_amount <= 0 THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'المبلغ غير صالح');
    END IF;

    SELECT * INTO v_supplier FROM suppliers WHERE id = p_supplier_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'المورد غير موجود');
    END IF;

    INSERT INTO supplier_ledger (
        supplier_id, amount_change, ref_type, ref_id, notes, client_id
    ) VALUES (
        p_supplier_id,
        -p_amount,
        'supplier_payment',
        COALESCE(p_purchase_id, p_client_id),
        COALESCE(NULLIF(trim(p_notes), ''), 'سداد نقدي لمستحقات المورد'),
        p_client_id
    )
    RETURNING * INTO v_existing;

    INSERT INTO audit_log (
        user_id, action, target_table, target_id, after_state
    ) VALUES (
        p_payer_user_id,
        'SUPPLIER_PAYMENT',
        'supplier_ledger',
        v_existing.id,
        jsonb_build_object(
            'ledger_id', v_existing.id,
            'supplier_id', p_supplier_id,
            'supplier_name', v_supplier.name,
            'amount', p_amount,
            'purchase_id', p_purchase_id,
            'client_id', p_client_id,
            'notes', p_notes
        )
    );

    RETURN jsonb_build_object(
        'status', 'success',
        'ledger_id', v_existing.id,
        'supplier_id', p_supplier_id,
        'amount', p_amount,
        'client_id', p_client_id
    );
END;
$$;

REVOKE ALL ON FUNCTION rpc_record_supplier_payment(
    UUID, UUID, BIGINT, UUID, UUID, TEXT, TEXT
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_record_supplier_payment(
    UUID, UUID, BIGINT, UUID, UUID, TEXT, TEXT
) TO anon, authenticated;

-- ============================================================
-- PART 5: GRANT / RLS RECONCILIATION
-- ============================================================

-- PostgreSQL keeps table-level and column-level grants separate:
-- `REVOKE ALL ON TABLE` does NOT remove old grants such as
-- `GRANT UPDATE (name, phone, role, active, language, updated_at)`.
-- Clear every column privilege on the tables we are making read-only
-- (or narrow-update), then re-grant exactly what is needed below.
DO $$
DECLARE
    v_table TEXT;
    v_column TEXT;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'users', 'customers', 'addresses', 'orders',
        'products', 'product_prices', 'product_barcodes',
        'suppliers', 'purchases', 'purchase_items', 'order_items',
        'stock_ledger', 'customer_ledger', 'supplier_ledger', 'payments',
        'settlements', 'wallet_entries', 'pos_shifts', 'permissions',
        'role_permissions', 'app_versions', 'audit_log',
        'audit_log_partitioned', 'pin_attempt_limits'
    ] LOOP
        FOR v_column IN
            SELECT column_name
            FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = v_table
        LOOP
            EXECUTE format(
                'REVOKE ALL (%I) ON TABLE public.%I FROM anon, authenticated',
                v_column, v_table
            );
        END LOOP;
    END LOOP;
END $$;

-- ------------------------------------------------------------
-- 5.1 users: read-only, PIN hash excluded
-- ------------------------------------------------------------
REVOKE ALL ON TABLE users FROM anon, authenticated;
GRANT SELECT (
    id, phone, name, role, active, language, created_at, updated_at
) ON TABLE users TO anon, authenticated;

ALTER TABLE users ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public read users profile lookup" ON users;
DROP POLICY IF EXISTS "Allow anon read users for profile and lookup" ON users;
DROP POLICY IF EXISTS "Allow customer self-registration" ON users;
DROP POLICY IF EXISTS "Allow customer self-update" ON users;
DROP POLICY IF EXISTS "Allow user profile updates" ON users;
DROP POLICY IF EXISTS "Allow staff and user profile update" ON users;
DROP POLICY IF EXISTS "Allow authenticated staff update users" ON users;
DROP POLICY IF EXISTS "Allow all operations on users for app functionality" ON users;
DROP POLICY IF EXISTS "Users can view their own profile" ON users;
DROP POLICY IF EXISTS "Moderator full control over users" ON users;
DROP POLICY IF EXISTS "users_read" ON users;

CREATE POLICY "users_read" ON users
    FOR SELECT
    USING (TRUE);

-- ------------------------------------------------------------
-- 5.2 customers: read-only, device token excluded
-- ------------------------------------------------------------
REVOKE ALL ON TABLE customers FROM anon, authenticated;
GRANT SELECT (
    id, user_id, price_tier, credit_limit, created_at, updated_at
) ON TABLE customers TO anon, authenticated;

ALTER TABLE customers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Customers readable by all" ON customers;
DROP POLICY IF EXISTS "Allow read customers" ON customers;
DROP POLICY IF EXISTS "Customers insertable" ON customers;
DROP POLICY IF EXISTS "Customers updatable by staff and owner" ON customers;
DROP POLICY IF EXISTS "Allow insert customer user_id" ON customers;
DROP POLICY IF EXISTS "Allow all operations on customers" ON customers;
DROP POLICY IF EXISTS "customers_write_authenticated" ON customers;
DROP POLICY IF EXISTS "customers_read" ON customers;

CREATE POLICY "customers_read" ON customers
    FOR SELECT
    USING (TRUE);

-- ------------------------------------------------------------
-- 5.3 addresses: read-only to clients; writes go through RPCs
-- ------------------------------------------------------------
REVOKE INSERT, UPDATE, DELETE ON addresses FROM anon, authenticated;
GRANT SELECT ON addresses TO anon, authenticated;

ALTER TABLE addresses ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Addresses operations" ON addresses;
DROP POLICY IF EXISTS "addresses_open" ON addresses;
DROP POLICY IF EXISTS "Allow all operations on addresses" ON addresses;
DROP POLICY IF EXISTS "Allow all operations on addresses for app functionality" ON addresses;
DROP POLICY IF EXISTS "addresses_read" ON addresses;

CREATE POLICY "addresses_read" ON addresses
    FOR SELECT
    USING (TRUE);

-- ------------------------------------------------------------
-- 5.4 orders: RPC-only inserts; narrow direct status update
-- ------------------------------------------------------------
REVOKE INSERT, UPDATE, DELETE ON orders FROM anon, authenticated;
GRANT SELECT ON orders TO anon, authenticated;
GRANT UPDATE (status, driver_id, notes) ON orders TO anon, authenticated;

ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Orders view policy" ON orders;
DROP POLICY IF EXISTS "Orders insert policy" ON orders;
DROP POLICY IF EXISTS "Orders update policy" ON orders;
DROP POLICY IF EXISTS "Customer view own orders" ON orders;
DROP POLICY IF EXISTS "Customer create orders" ON orders;
DROP POLICY IF EXISTS "Staff update orders" ON orders;
DROP POLICY IF EXISTS "Allow all operations on orders" ON orders;
DROP POLICY IF EXISTS "orders_read" ON orders;
DROP POLICY IF EXISTS "orders_client_update" ON orders;

CREATE POLICY "orders_read" ON orders
    FOR SELECT
    USING (TRUE);

CREATE POLICY "orders_client_update" ON orders
    FOR UPDATE
    TO anon, authenticated
    USING (TRUE)
    WITH CHECK (TRUE);

-- ------------------------------------------------------------
-- 5.5 catalogue: RPC-only writes
-- ------------------------------------------------------------
REVOKE INSERT, UPDATE, DELETE ON products FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON product_prices FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON product_barcodes FROM anon, authenticated;

GRANT SELECT ON products TO anon, authenticated;
GRANT SELECT ON product_prices TO anon, authenticated;
GRANT SELECT ON product_barcodes TO anon, authenticated;

-- ------------------------------------------------------------
-- 5.6 purchasing and stock: RPC-only writes
-- ------------------------------------------------------------
REVOKE INSERT, UPDATE, DELETE ON suppliers FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON purchases FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON purchase_items FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON order_items FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON stock_ledger FROM anon, authenticated;

GRANT SELECT ON suppliers TO anon, authenticated;
GRANT SELECT ON purchases TO anon, authenticated;
GRANT SELECT ON purchase_items TO anon, authenticated;
GRANT SELECT ON order_items TO anon, authenticated;
GRANT SELECT ON stock_ledger TO anon, authenticated;

-- ------------------------------------------------------------
-- 5.7 financial ledgers: RPC-only writes
-- ------------------------------------------------------------
REVOKE INSERT, UPDATE, DELETE ON customer_ledger FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON supplier_ledger FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON payments FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON settlements FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON wallet_entries FROM anon, authenticated;

GRANT SELECT ON customer_ledger TO anon, authenticated;
GRANT SELECT ON supplier_ledger TO anon, authenticated;
GRANT SELECT ON payments TO anon, authenticated;
GRANT SELECT ON settlements TO anon, authenticated;
GRANT SELECT ON wallet_entries TO anon, authenticated;

-- ------------------------------------------------------------
-- 5.8 POS shifts, PIN attempt limits, permissions: read-only
-- ------------------------------------------------------------
REVOKE INSERT, UPDATE, DELETE ON pos_shifts FROM anon, authenticated;
GRANT SELECT ON pos_shifts TO anon, authenticated;

REVOKE ALL ON pin_attempt_limits FROM anon, authenticated;

REVOKE INSERT, UPDATE, DELETE ON permissions FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON role_permissions FROM anon, authenticated;
GRANT SELECT ON permissions TO anon, authenticated;
GRANT SELECT ON role_permissions TO anon, authenticated;

-- ------------------------------------------------------------
-- 5.9 app versions: public read, moderator-managed (service role)
-- ------------------------------------------------------------
REVOKE INSERT, UPDATE, DELETE ON app_versions FROM anon, authenticated;
GRANT SELECT ON app_versions TO anon, authenticated;

-- ------------------------------------------------------------
-- 5.10 audit log: append-only to clients, not directly readable
--      Moderators read the sanitised view instead.
-- ------------------------------------------------------------
REVOKE SELECT, UPDATE, DELETE ON audit_log FROM anon, authenticated;
GRANT INSERT ON audit_log TO anon, authenticated;

DO $$
DECLARE
    v_partition REGCLASS;
BEGIN
    IF to_regclass('public.audit_log_partitioned') IS NOT NULL THEN
        EXECUTE 'REVOKE ALL ON audit_log_partitioned FROM anon, authenticated';
        EXECUTE 'ALTER TABLE audit_log_partitioned ENABLE ROW LEVEL SECURITY';

        FOR v_partition IN
            SELECT inhrelid::regclass
            FROM pg_inherits
            WHERE inhparent = 'public.audit_log_partitioned'::regclass
        LOOP
            EXECUTE format(
                'REVOKE ALL ON %s FROM anon, authenticated',
                v_partition
            );
            EXECUTE format(
                'ALTER TABLE %s ENABLE ROW LEVEL SECURITY',
                v_partition
            );
        END LOOP;
    END IF;
END $$;

ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow select audit_log" ON audit_log;
DROP POLICY IF EXISTS "Allow insert audit_log" ON audit_log;
DROP POLICY IF EXISTS "Staff and moderator view audit log" ON audit_log;
DROP POLICY IF EXISTS "Allow view audit logs" ON audit_log;
DROP POLICY IF EXISTS "Only moderator views audit log" ON audit_log;
DROP POLICY IF EXISTS "Deny direct audit_log insert" ON audit_log;
DROP POLICY IF EXISTS "Deny direct audit_log update" ON audit_log;
DROP POLICY IF EXISTS "Deny direct audit_log delete" ON audit_log;
DROP POLICY IF EXISTS "audit_log_client_insert" ON audit_log;

CREATE POLICY "audit_log_client_insert" ON audit_log
    FOR INSERT
    TO anon, authenticated
    WITH CHECK (
        audit_log.user_id IS NOT NULL
        AND EXISTS (SELECT 1 FROM users u WHERE u.id = audit_log.user_id)
    );

-- The moderator dashboard reads this view. Recreate it as an owner-run
-- view with a deliberately small, non-sensitive column list. Raw
-- before_state / after_state / ip_address payloads stay unreadable to
-- clients even though they can still execute INSERT for their own
-- append-only audit events.
DROP VIEW IF EXISTS view_audit_trail_intelligence CASCADE;
DROP VIEW IF EXISTS view_audit_log_enriched CASCADE;

CREATE VIEW view_audit_log_enriched
AS
SELECT
    a.id,
    a.created_at,
    a.action,
    a.target_table,
    a.target_id,
    a.user_id,
    u.name  AS actor_name,
    u.role  AS actor_role,
    u.phone AS actor_phone,
    CASE
        WHEN a.target_table = 'orders' AND a.action = 'INSERT'
            THEN 'طلب جديد تم تسجيله (' || COALESCE(a.after_state->>'channel', 'store') || ')'
        WHEN a.target_table = 'orders' AND a.action = 'UPDATE'
            THEN 'تحديث حالة الطلب إلى: ' || COALESCE(a.after_state->>'status', '')
        WHEN a.target_table = 'orders' AND a.action = 'DELETE'
            THEN 'حذف أو إلغاء طلب'
        WHEN a.target_table = 'payments' AND a.action = 'INSERT'
            THEN 'تحصيل مالي: ' || COALESCE(((a.after_state->>'amount')::numeric / 100)::text, '0') || ' دج'
        WHEN a.target_table = 'settlements'
            THEN 'إغلاق تسوية سائق (End-of-day)'
        WHEN a.target_table = 'wallet_entries' AND a.action = 'INSERT'
            THEN 'حركة بمحفظة السائق: ' || COALESCE(a.after_state->>'type', '')
        WHEN a.target_table = 'stock_ledger' AND a.action = 'INSERT'
            THEN 'حركة مخزون (' || COALESCE(a.after_state->>'reason', '') || ')'
        WHEN a.target_table = 'purchases' AND a.action = 'INSERT'
            THEN 'فاتورة شراء جديدة: ' || COALESCE(a.after_state->>'invoice_no', '')
        WHEN a.target_table = 'purchases' AND a.action = 'UPDATE'
            THEN 'تحديث حالة فاتورة شراء إلى: ' || COALESCE(a.after_state->>'status', '')
        WHEN a.target_table = 'products' AND a.action = 'INSERT'
            THEN 'إضافة منتج جديد: ' || COALESCE(a.after_state->>'name_ar', '')
        WHEN a.target_table = 'products' AND a.action = 'UPDATE'
            THEN 'تعديل منتج: ' || COALESCE(a.after_state->>'name_ar', '')
        WHEN a.target_table = 'customers'
            THEN 'تحديث بيانات زبون / حد الائتمان'
        WHEN a.target_table = 'suppliers'
            THEN 'إضافة أو تعديل مورد'
        WHEN a.target_table = 'addresses'
            THEN 'إضافة أو تعديل عنوان توصيل'
        WHEN a.action = 'STAFF_LOGIN'
            THEN 'تسجيل دخول موظف: ' || COALESCE(a.after_state->>'name', u.name, '')
        WHEN a.action = 'STAFF_LOGOUT'
            THEN 'تسجيل خروج موظف: ' || COALESCE(a.after_state->>'name', u.name, '')
        WHEN a.action = 'CASHIER_SWITCH'
            THEN 'تبديل كاشير: ' || COALESCE(a.after_state->>'new_cashier_name', '')
        WHEN a.action = 'SUPPLIER_PAYMENT'
            THEN 'سداد نقدي للمورد: ' || COALESCE(a.after_state->>'supplier_name', '')
        WHEN a.action = 'USER_PROFILE_UPDATED'
            THEN 'تحديث بيانات مستخدم: ' || COALESCE(a.after_state->>'name', '')
        WHEN a.action = 'CUSTOMER_CREATED_BY_STAFF'
            THEN 'تسجيل زبون جديد: ' || COALESCE(a.after_state->>'name', '')
        WHEN a.action = 'MODERATOR_RESET_USER_PIN'
            THEN 'إعادة تعيين رمز PIN لموظف بواسطة المشرف'
        WHEN a.action = 'USER_PIN_CHANGED'
            THEN 'تغيير رمز PIN الحساب'
        WHEN a.action = 'STAFF_MEMBER_CREATED'
            THEN 'إنشاء حساب موظف جديد'
        ELSE a.action || ' على ' || a.target_table
    END AS intelligent_title,
    CASE
        WHEN a.action IN ('SHIFT_OPENED', 'SHIFT_CLOSED', 'SUPPLIER_PAYMENT')
            THEN 'finance'
        WHEN a.target_table IN (
            'payments', 'settlements', 'customer_ledger',
            'supplier_ledger', 'wallet_entries'
        ) THEN 'finance'
        WHEN a.target_table IN ('orders', 'order_items')
            THEN 'sales'
        WHEN a.target_table IN (
            'stock_ledger', 'purchases', 'purchase_items',
            'products', 'product_prices', 'product_barcodes'
        ) THEN 'inventory'
        WHEN a.target_table IN ('users', 'customers')
             OR a.action IN (
                 'STAFF_LOGIN', 'STAFF_LOGOUT', 'CASHIER_SWITCH',
                 'MODERATOR_RESET_USER_PIN', 'USER_PIN_CHANGED',
                 'STAFF_MEMBER_CREATED', 'USER_PROFILE_UPDATED',
                 'CUSTOMER_CREATED_BY_STAFF'
             ) THEN 'security'
        ELSE 'general'
    END AS category,
    CASE
        WHEN u.role = 'customer' THEN 'customer'
        WHEN u.role IN ('cashier', 'driver', 'manager', 'moderator') THEN 'staff'
        WHEN a.action IN (
            'STAFF_LOGIN', 'STAFF_LOGOUT', 'CASHIER_SWITCH',
            'SHIFT_OPENED', 'SHIFT_CLOSED'
        ) THEN 'staff'
        ELSE 'system'
    END AS actor_type
FROM audit_log a
LEFT JOIN users u ON a.user_id = u.id;

CREATE VIEW view_audit_trail_intelligence AS
SELECT * FROM view_audit_log_enriched;

GRANT SELECT ON view_audit_log_enriched TO anon, authenticated;
GRANT SELECT ON view_audit_trail_intelligence TO anon, authenticated;

-- ------------------------------------------------------------
-- 5.11 driver telemetry: append-only, RLS enabled
-- ------------------------------------------------------------
REVOKE DELETE ON driver_locations FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON driver_locations TO anon, authenticated;

DO $$
BEGIN
    IF to_regclass('public.driver_location_events') IS NOT NULL THEN
        EXECUTE 'ALTER TABLE driver_location_events ENABLE ROW LEVEL SECURITY';
        EXECUTE 'REVOKE UPDATE, DELETE ON driver_location_events FROM anon, authenticated';
        EXECUTE 'GRANT SELECT, INSERT ON driver_location_events TO anon, authenticated';
        EXECUTE 'DROP POLICY IF EXISTS driver_location_events_read ON driver_location_events';
        EXECUTE 'DROP POLICY IF EXISTS driver_location_events_insert ON driver_location_events';
        EXECUTE 'CREATE POLICY driver_location_events_read ON driver_location_events FOR SELECT USING (TRUE)';
        EXECUTE 'CREATE POLICY driver_location_events_insert ON driver_location_events FOR INSERT WITH CHECK (driver_id IS NOT NULL)';
    END IF;
END $$;

-- ------------------------------------------------------------
-- 5.12 failed sync operations: append-only, RLS enabled
-- ------------------------------------------------------------
DO $$
BEGIN
    IF to_regclass('public.failed_operations') IS NOT NULL THEN
        EXECUTE 'ALTER TABLE failed_operations ENABLE ROW LEVEL SECURITY';
        EXECUTE 'REVOKE UPDATE, DELETE ON failed_operations FROM anon, authenticated';
        EXECUTE 'GRANT SELECT, INSERT ON failed_operations TO anon, authenticated';
        EXECUTE 'DROP POLICY IF EXISTS failed_operations_read ON failed_operations';
        EXECUTE 'DROP POLICY IF EXISTS failed_operations_insert ON failed_operations';
        EXECUTE 'CREATE POLICY failed_operations_read ON failed_operations FOR SELECT USING (TRUE)';
        EXECUTE 'CREATE POLICY failed_operations_insert ON failed_operations FOR INSERT WITH CHECK (client_id IS NOT NULL)';
    END IF;
END $$;

-- ------------------------------------------------------------
-- 5.13 aggregate snapshots: read-only to clients, maintained by
--      SECURITY DEFINER triggers.
-- ------------------------------------------------------------
DO $$
DECLARE
    v_table TEXT;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'product_stock_snapshot',
        'customer_balance_snapshot',
        'driver_wallet_snapshot',
        'supplier_balance_snapshot'
    ] LOOP
        IF to_regclass('public.' || v_table) IS NOT NULL THEN
            EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', v_table);
            EXECUTE format('REVOKE ALL ON %I FROM anon, authenticated', v_table);
            EXECUTE format('GRANT SELECT ON %I TO anon, authenticated', v_table);
            EXECUTE format('DROP POLICY IF EXISTS %I ON %I', v_table || '_read', v_table);
            EXECUTE format(
                'CREATE POLICY %I ON %I FOR SELECT USING (TRUE)',
                v_table || '_read', v_table
            );
        END IF;
    END LOOP;
END $$;

-- ------------------------------------------------------------
-- 5.14 reporting views: restore SELECT after table grants change
-- ------------------------------------------------------------
DO $$
DECLARE
    v_view TEXT;
BEGIN
    FOREACH v_view IN ARRAY ARRAY[
        'view_product_stock',
        'view_driver_wallet_balance',
        'view_customer_balance',
        'view_supplier_balance',
        'view_customer_products',
        'view_audit_log_enriched',
        'view_audit_trail_intelligence'
    ] LOOP
        IF to_regclass('public.' || v_view) IS NOT NULL THEN
            EXECUTE format('GRANT SELECT ON %I TO anon, authenticated', v_view);
        END IF;
    END LOOP;
END $$;

-- ------------------------------------------------------------
-- 5.15 Disable superseded RPCs. The device-bound customer RPC and
--      rpc_save_user_profile are the supported paths.
-- ------------------------------------------------------------
DO $$
BEGIN
    IF to_regprocedure(
        'public.rpc_sync_customer_profile(varchar,varchar,varchar,varchar,text,double precision,double precision,uuid,uuid)'
    ) IS NOT NULL THEN
        EXECUTE 'REVOKE EXECUTE ON FUNCTION rpc_sync_customer_profile(
            VARCHAR, VARCHAR, VARCHAR, VARCHAR, TEXT,
            DOUBLE PRECISION, DOUBLE PRECISION, UUID, UUID
        ) FROM PUBLIC, anon, authenticated';
    END IF;

    IF to_regprocedure(
        'public.rpc_update_user_profile(uuid,text,uuid,varchar,varchar,varchar,public.user_role,boolean)'
    ) IS NOT NULL THEN
        EXECUTE 'REVOKE EXECUTE ON FUNCTION rpc_update_user_profile(
            UUID, TEXT, UUID, VARCHAR, VARCHAR, VARCHAR, user_role, BOOLEAN
        ) FROM PUBLIC, anon, authenticated';
    END IF;
END $$;

-- ============================================================
-- PART 6: RELOAD POSTGREST SCHEMA CACHE
-- ============================================================
NOTIFY pgrst, 'reload schema';


-- ============================================================================
-- 00033 - customer experience upgrade
-- Source: archive/migrations/00033_customer_experience_upgrade.sql
-- ============================================================================
-- ============================================================
-- 00033_customer_experience_upgrade.sql
--
-- Customer app experience upgrade:
--   1. Composite / partial indexes for the cache-first customer app
--      (catalog delta sync, order history, wallet ledger, addresses).
--   2. Streams `orders` through Supabase Realtime so future clients can
--      react to status changes without waiting for the polling interval.
--   3. rpc_get_customer_order_live: device-token-verified tracking payload
--      (order status + driver identity + last known driver location).
--
-- Safety: additive only. Every index uses IF NOT EXISTS and the RPC is a
-- CREATE OR REPLACE. The app keeps working if this migration is not applied
-- yet: it falls back to direct Supabase queries when the RPC is missing.
-- ============================================================

-- ------------------------------------------------------------------
-- 1. Indexes for the customer app read paths
-- ------------------------------------------------------------------

-- Catalog delta sync (`products.updated_at > last_sync`).
CREATE INDEX IF NOT EXISTS idx_products_updated_at
    ON products(updated_at DESC);

-- Order history: one customer, newest first.
CREATE INDEX IF NOT EXISTS idx_orders_customer_created
    ON orders(customer_id, created_at DESC);

-- Active orders are polled far more often than finished ones; a partial
-- index keeps that hot path small even as order history grows.
CREATE INDEX IF NOT EXISTS idx_orders_customer_open
    ON orders(customer_id, created_at DESC)
    WHERE status NOT IN ('delivered', 'settled', 'cancelled');

-- Wallet ledger: newest entries for a single customer.
CREATE INDEX IF NOT EXISTS idx_customer_ledger_customer_created
    ON customer_ledger(customer_id, created_at DESC);

-- Profile address lookup (default address first).
CREATE INDEX IF NOT EXISTS idx_addresses_customer_default
    ON addresses(customer_id, is_default DESC, created_at DESC);

-- Driver-location freshness checks during live tracking.
CREATE INDEX IF NOT EXISTS idx_driver_locations_updated
    ON driver_locations(updated_at DESC);

-- ------------------------------------------------------------------
-- 2. Realtime publication for order status changes
-- ------------------------------------------------------------------
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime'
    ) AND NOT EXISTS (
        SELECT 1
        FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
          AND schemaname = 'public'
          AND tablename = 'orders'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE orders;
    END IF;
END $$;

-- ------------------------------------------------------------------
-- 3. Secure live tracking RPC
--
-- The customer app is device-bound (see 00025). The caller must present
-- the exact device_token stored on the customer that owns the order.
-- A generic error is returned for both "not found" and "not yours" so the
-- endpoint cannot be used to probe order IDs.
-- ------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_get_customer_order_live(
    p_order_id     UUID,
    p_device_token TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_order      orders%ROWTYPE;
    v_customer   customers%ROWTYPE;
    v_driver     users%ROWTYPE;
    v_location   driver_locations%ROWTYPE;
    v_token      TEXT := trim(COALESCE(p_device_token, ''));
    v_dest_lat   DOUBLE PRECISION;
    v_dest_lng   DOUBLE PRECISION;
BEGIN
    IF p_order_id IS NULL OR v_token = '' OR LENGTH(v_token) < 16 THEN
        RETURN jsonb_build_object('found', FALSE, 'error', 'الطلب غير متوفر');
    END IF;

    SELECT * INTO v_order FROM orders WHERE id = p_order_id LIMIT 1;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('found', FALSE, 'error', 'الطلب غير متوفر');
    END IF;

    -- The order must belong to a customer bound to this device.
    SELECT * INTO v_customer
    FROM customers
    WHERE id = v_order.customer_id
    LIMIT 1;

    IF NOT FOUND
       OR v_customer.device_token IS NULL
       OR v_customer.device_token = ''
       OR v_customer.device_token <> v_token THEN
        RETURN jsonb_build_object('found', FALSE, 'error', 'غير مصرح بتتبع هذا الطلب');
    END IF;

    IF v_order.driver_id IS NOT NULL THEN
        SELECT * INTO v_driver FROM users WHERE id = v_order.driver_id LIMIT 1;
        SELECT * INTO v_location
        FROM driver_locations
        WHERE driver_id = v_order.driver_id
        LIMIT 1;
    END IF;

    -- Delivery address coordinates are stored as JSON numbers/strings and
    -- may be absent for counter orders. Never let a bad cast break tracking.
    IF v_order.delivery_address IS NOT NULL THEN
        BEGIN
            v_dest_lat := NULLIF(v_order.delivery_address->>'latitude', '')::DOUBLE PRECISION;
            v_dest_lng := NULLIF(v_order.delivery_address->>'longitude', '')::DOUBLE PRECISION;
        EXCEPTION WHEN OTHERS THEN
            v_dest_lat := NULL;
            v_dest_lng := NULL;
        END;
    END IF;

    RETURN jsonb_build_object(
        'found',             TRUE,
        'order_id',          v_order.id,
        'order_number',      v_order.order_number,
        'status',            v_order.status::text,
        'driver_id',         v_order.driver_id,
        'driver_name',       v_driver.name,
        'driver_phone',      v_driver.phone,
        'driver_lat',        v_location.latitude,
        'driver_lng',        v_location.longitude,
        'driver_updated_at', v_location.updated_at,
        'destination_lat',   v_dest_lat,
        'destination_lng',   v_dest_lng,
        'confirmed_at',      v_order.confirmed_at,
        'delivered_at',      v_order.delivered_at,
        'settled_at',        v_order.settled_at
    );
END;
$$;

REVOKE ALL ON FUNCTION rpc_get_customer_order_live(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_get_customer_order_live(UUID, TEXT) TO anon, authenticated;


-- ============================================================================
-- 00034 - storage lifecycle and retention management
-- Source: backend/supabase/operations/storage_lifecycle_management.sql
-- ============================================================================
-- Optimizes storage for permanent operation under the Supabase Free Tier (500 MB).
-- 1. Performance indexes for telemetry and closed orders.
-- 2. Stored procedure rpc_purge_historical_data() to purge archived data safely.
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_driver_location_events_recorded_at
    ON driver_location_events(recorded_at);

CREATE INDEX IF NOT EXISTS idx_orders_status_created_at
    ON orders(status, created_at)
    WHERE status IN ('delivered', 'settled', 'cancelled');

CREATE OR REPLACE FUNCTION rpc_purge_historical_data(
    p_order_retention_days INT DEFAULT 60,
    p_audit_retention_days INT DEFAULT 30,
    p_telemetry_retention_days INT DEFAULT 7
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_purged_orders BIGINT := 0;
    v_purged_order_items BIGINT := 0;
    v_purged_audit BIGINT := 0;
    v_purged_telemetry BIGINT := 0;
    v_purged_failed_ops BIGINT := 0;
    v_cutoff_orders TIMESTAMPTZ;
    v_cutoff_audit TIMESTAMPTZ;
    v_cutoff_telemetry TIMESTAMPTZ;
BEGIN
    -- Guardrails on minimum safe retention periods
    IF p_order_retention_days < 14 THEN
        RAISE EXCEPTION 'Order retention cannot be less than 14 days.';
    END IF;
    IF p_audit_retention_days < 7 THEN
        RAISE EXCEPTION 'Audit retention cannot be less than 7 days.';
    END IF;
    IF p_telemetry_retention_days < 1 THEN
        RAISE EXCEPTION 'Telemetry retention cannot be less than 1 day.';
    END IF;

    v_cutoff_orders := NOW() - (p_order_retention_days || ' days')::INTERVAL;
    v_cutoff_audit := NOW() - (p_audit_retention_days || ' days')::INTERVAL;
    v_cutoff_telemetry := NOW() - (p_telemetry_retention_days || ' days')::INTERVAL;

    -- Suppress audit triggers during batch cleanup
    PERFORM set_config('app.maintenance_mode', 'true', true);

    -- 1. Purge driver location events older than threshold
    DELETE FROM driver_location_events
    WHERE recorded_at < v_cutoff_telemetry;
    GET DIAGNOSTICS v_purged_telemetry = ROW_COUNT;

    -- 2. Purge transient offline sync failure logs older than 14 days
    DELETE FROM failed_operations
    WHERE created_at < (NOW() - INTERVAL '14 days');
    GET DIAGNOSTICS v_purged_failed_ops = ROW_COUNT;

    -- 3. Purge audit log records older than threshold
    DELETE FROM audit_log
    WHERE created_at < v_cutoff_audit;
    GET DIAGNOSTICS v_purged_audit = ROW_COUNT;

    -- Also purge audit_log_partitioned if active
    IF to_regclass('public.audit_log_partitioned') IS NOT NULL THEN
        BEGIN
            DELETE FROM audit_log_partitioned WHERE created_at < v_cutoff_audit;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END IF;

    -- 4. Purge closed/delivered/cancelled orders older than threshold
    --    ACTIVE / IN-FLIGHT orders are NEVER touched!
    -- Detach payments from orders being deleted so payment records remain intact
    UPDATE payments
    SET order_id = NULL
    WHERE order_id IN (
        SELECT id FROM orders
        WHERE status IN ('delivered', 'settled', 'cancelled')
          AND created_at < v_cutoff_orders
    );

    -- Delete order_items
    WITH old_orders AS (
        SELECT id FROM orders
        WHERE status IN ('delivered', 'settled', 'cancelled')
          AND created_at < v_cutoff_orders
    ),
    deleted_items AS (
        DELETE FROM order_items
        WHERE order_id IN (SELECT id FROM old_orders)
        RETURNING id
    )
    SELECT count(*) INTO v_purged_order_items FROM deleted_items;

    -- Delete orders
    WITH deleted_orders AS (
        DELETE FROM orders
        WHERE status IN ('delivered', 'settled', 'cancelled')
          AND created_at < v_cutoff_orders
        RETURNING id
    )
    SELECT count(*) INTO v_purged_orders FROM deleted_orders;

    RETURN jsonb_build_object(
        'status', 'success',
        'purged_orders', v_purged_orders,
        'purged_order_items', v_purged_order_items,
        'purged_audit_entries', v_purged_audit,
        'purged_telemetry_events', v_purged_telemetry,
        'purged_failed_operations', v_purged_failed_ops,
        'order_retention_days', p_order_retention_days,
        'audit_retention_days', p_audit_retention_days,
        'telemetry_retention_days', p_telemetry_retention_days,
        'executed_at', NOW()
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION rpc_purge_historical_data(INT, INT, INT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_purge_historical_data(INT, INT, INT) TO service_role, authenticated;

-- Force PostgREST to pick up the new function/index metadata.
NOTIFY pgrst, 'reload schema';


-- ============================================================
-- BASELINE VERSION MARKER
-- ============================================================
-- Records which migrations are baked into this baseline. Future
-- incremental migrations belong in supabase/migrations/ and should
-- also insert their own row here.
-- ============================================================
CREATE TABLE IF NOT EXISTS schema_migrations (
    version     TEXT        PRIMARY KEY,
    description TEXT        NOT NULL,
    applied_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO schema_migrations (version, description) VALUES
    ('00015', 'CONSOLIDATED BASE - migrations 00001-00015'),
    ('00016', '00016 - customer app grants and schema fixes'),
    ('00017', '00017 - staff app grants'),
    ('00018', '00018 - widen users.pin_code to TEXT'),
    ('00019', '00019 - users SELECT grant for staff login'),
    ('00020a', '00020a - missing RLS policies and write grants'),
    ('00020b', '00020b - supplier write grants'),
    ('00021', '00021 - staff profile update grants'),
    ('00022', '00022 - universal audit trail and intelligence'),
    ('00023', '00023 - OTA app versions and storage'),
    ('00024', '00024 - purge master PIN and revoke anon writes'),
    ('00025', '00025 - device-bound customer authentication'),
    ('00026', '00026 - resilience and scalability'),
    ('00027', '00027 - audit log minimization'),
    ('00028', '00028 - driver telemetry optimization'),
    ('00029', '00029 - stock balance summaries'),
    ('00030', '00030 - audit log partitioning readiness'),
    ('00031', '00031 - offline sync resilience'),
    ('00032', '00032 - permission repair'),
    ('00033', '00033 - customer experience upgrade'),
    ('00034', '00034 - storage lifecycle and retention management')
ON CONFLICT (version) DO NOTHING;

ALTER TABLE schema_migrations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON schema_migrations FROM anon, authenticated;
GRANT SELECT ON schema_migrations TO service_role;

-- Supabase normally grants these by default. Restate them so the baseline
-- also works after operations/reset_database.sql recreates the public schema.
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated;
GRANT USAGE ON SCHEMA public TO service_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO service_role;

NOTIFY pgrst, 'reload schema';
