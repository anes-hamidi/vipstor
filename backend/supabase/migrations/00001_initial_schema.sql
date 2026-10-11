-- ============================================================
-- 00001_initial_schema.sql
-- WHOLESALE SHOP MANAGEMENT SYSTEM: CORE SCHEMAS & TABLES
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- User Roles
CREATE TYPE user_role AS ENUM (
  'moderator', 
  'manager', 
  'cashier', 
  'driver', 
  'customer'
);

-- Price Tiers
CREATE TYPE price_tier AS ENUM (
  'retail', 
  'wholesale', 
  'bulk'
);

-- Purchase Invoices
CREATE TYPE purchase_status AS ENUM (
  'draft', 
  'posted', 
  'cancelled'
);

-- Sales & Order Channels
CREATE TYPE order_channel AS ENUM (
  'store', 
  'online'
);

-- Order Lifecycle Statuses
CREATE TYPE order_status AS ENUM (
  'submitted',        -- Online order submitted by customer
  'confirmed',        -- Cashier confirmed (reserves inventory)
  'preparing',        -- Warehouse packing & assembly
  'ready',            -- Prepared and ready for driver dispatch
  'assigned',         -- Assigned to driver
  'accepted',         -- Driver accepted
  'refused',          -- Driver refused (re-queued for cashier)
  'out_for_delivery', -- Out with driver
  'delivered',        -- Delivered & cash collected / balance updated
  'settled',          -- Cash closed at end-of-day settlement
  'cancelled'         -- Voided / returned
);

-- Payment Methods
CREATE TYPE payment_method AS ENUM (
  'cash', 
  'customer_balance', 
  'mixed'
);

-- Payment Statuses
CREATE TYPE payment_status AS ENUM (
  'collected', 
  'settled', 
  'reversed'
);

-- Driver Wallet Entry Types
CREATE TYPE wallet_entry_type AS ENUM (
  'collection', 
  'handover', 
  'shortage', 
  'overage', 
  'reversal'
);

-- End of Day Settlement Statuses
CREATE TYPE settlement_status AS ENUM (
  'pending', 
  'settled', 
  'discrepancy_flagged', 
  'approved'
);

-- Stock Reason
CREATE TYPE stock_ref_type AS ENUM (
  'purchase', 
  'sale', 
  'return', 
  'adjustment'
);

-- ============================================================
-- USERS & PROFILES
-- ============================================================
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone VARCHAR(20) NOT NULL UNIQUE,
    name VARCHAR(100) NOT NULL,
    role user_role NOT NULL DEFAULT 'customer',
    active BOOLEAN NOT NULL DEFAULT TRUE,
    language VARCHAR(5) NOT NULL DEFAULT 'ar' CHECK (language IN ('ar', 'fr')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS customers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    price_tier price_tier NOT NULL DEFAULT 'wholesale',
    credit_limit BIGINT NOT NULL DEFAULT 0, -- In centimes (100 centimes = 1 DZD)
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS addresses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    label VARCHAR(50) NOT NULL, -- e.g. 'Magasin Principal', 'Dépôt'
    address_text TEXT NOT NULL,
    wilaya VARCHAR(50) NOT NULL,
    commune VARCHAR(50) NOT NULL,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    is_default BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS suppliers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(150) NOT NULL,
    phone VARCHAR(20) NOT NULL,
    company_register VARCHAR(50),
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- PRODUCTS, BARCODES & MULTI-TIER PRICING
-- ============================================================
CREATE TABLE IF NOT EXISTS products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name_ar VARCHAR(200) NOT NULL,
    name_fr VARCHAR(200) NOT NULL,
    category VARCHAR(100) NOT NULL,
    unit VARCHAR(20) NOT NULL DEFAULT 'piece', -- 'piece', 'carton', 'kg', 'box'
    pack_size INT NOT NULL DEFAULT 1,          -- Number of items per pack
    photo_url TEXT,
    last_unit_cost BIGINT NOT NULL DEFAULT 0,  -- In centimes
    min_stock_alert INT NOT NULL DEFAULT 5,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS product_barcodes (
    barcode VARCHAR(64) PRIMARY KEY,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    units_per_scan INT NOT NULL DEFAULT 1,      -- 1 for unit, 12/24 for carton
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS product_prices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    tier price_tier NOT NULL,
    min_qty INT NOT NULL DEFAULT 1,
    price BIGINT NOT NULL CHECK (price >= 0),   -- In centimes
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_product_tier_min_qty UNIQUE(product_id, tier, min_qty)
);

-- ============================================================
-- PURCHASES (SUPPLIER INVOICE HEADERS & ITEMS)
-- ============================================================
CREATE TABLE IF NOT EXISTS purchases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    supplier_id UUID NOT NULL REFERENCES suppliers(id),
    invoice_no VARCHAR(100) NOT NULL,
    invoice_date DATE NOT NULL DEFAULT CURRENT_DATE,
    status purchase_status NOT NULL DEFAULT 'draft',
    total_amount BIGINT NOT NULL DEFAULT 0,    -- In centimes
    created_by UUID NOT NULL REFERENCES users(id),
    posted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_supplier_invoice UNIQUE(supplier_id, invoice_no)
);

CREATE TABLE IF NOT EXISTS purchase_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    purchase_id UUID NOT NULL REFERENCES purchases(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id),
    quantity INT NOT NULL CHECK (quantity > 0),
    unit_cost BIGINT NOT NULL CHECK (unit_cost >= 0),
    selling_price BIGINT NOT NULL CHECK (selling_price >= unit_cost),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- ORDERS (COUNTER & ONLINE)
-- ============================================================
CREATE TABLE IF NOT EXISTS orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_number BIGSERIAL UNIQUE,
    channel order_channel NOT NULL,
    customer_id UUID REFERENCES customers(id), -- NULL for anonymous counter sale
    status order_status NOT NULL DEFAULT 'submitted',
    driver_id UUID REFERENCES users(id),       -- Assigned delivery driver
    cashier_id UUID REFERENCES users(id),      -- Counter cashier or confirming cashier
    delivery_address JSONB,                    -- Snapshot of address at order time
    total_amount BIGINT NOT NULL DEFAULT 0,    -- Total price in centimes
    total_cost BIGINT NOT NULL DEFAULT 0,      -- Snapshot of purchase costs (for gross margin)
    paid_amount BIGINT NOT NULL DEFAULT 0,     -- Amount received in centimes
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    confirmed_at TIMESTAMPTZ,
    delivered_at TIMESTAMPTZ,
    settled_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS order_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id),
    quantity INT NOT NULL CHECK (quantity > 0),
    unit_price BIGINT NOT NULL CHECK (unit_price >= 0),
    unit_cost BIGINT NOT NULL DEFAULT 0,       -- Snapshot for margin tracking
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
