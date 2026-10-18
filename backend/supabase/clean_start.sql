-- ============================================================
-- VIP WHOLESALE & POS MANAGEMENT SYSTEM
-- CLEAN PRODUCTION RESET (IDEMPOTENT DATA RESET)
-- ============================================================
-- Truncates all transactional tables and ledgers while preserving
-- the authoritative schema, strict RLS policies, triggers, and
-- reinstates the Master Admin Moderator.
-- ============================================================

-- 1. Truncate all transactional and ledger tables
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
    driver_locations,
    pin_attempt_limits,
    users
CASCADE;

-- 2. Insert the Master Admin Moderator account with bcrypt hashed PIN (1234)
INSERT INTO users (id, phone, name, role, active, language, pin_code)
VALUES (
    '11111111-1111-1111-1111-111111111111',
    '0673336972',
    'المدير العام',
    'moderator',
    TRUE,
    'ar',
    crypt('1234', gen_salt('bf'))
)
ON CONFLICT (phone) DO UPDATE SET
    role       = 'moderator',
    name       = 'المدير العام',
    active     = TRUE,
    pin_code   = crypt('1234', gen_salt('bf')),
    updated_at = NOW();

-- 3. Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';
