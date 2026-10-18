-- ============================================================
-- VIP WHOLESALE & POS MANAGEMENT SYSTEM
-- AUTHORITATIVE SEED DATA
-- ============================================================
-- Run this script AFTER init_fresh_database.sql.
-- Seeds the default Master Moderator, staff members, sample suppliers,
-- products with multi-tier pricing, barcodes, and opening inventory.
-- All staff PIN codes are pre-hashed with bcrypt (PIN: 1234).
-- ============================================================

SET search_path = public, extensions, pg_temp;

-- ── 1. Master Moderator & Staff Members ────────────────────────────────────────
-- Default initial PIN for all seed accounts is: 1234
-- (Must be changed upon production onboarding via app settings)

INSERT INTO users (id, phone, name, role, active, language, pin_code) VALUES
    (
        '11111111-1111-1111-1111-111111111111',
        '0673336972',
        'المدير العام',
        'moderator',
        TRUE,
        'ar',
        crypt('1234', gen_salt('bf'))
    ),
    (
        '22222222-2222-2222-2222-222222222222',
        '0550000002',
        'مسؤول المخزن أحمد',
        'manager',
        TRUE,
        'ar',
        crypt('1234', gen_salt('bf'))
    ),
    (
        '33333333-3333-3333-3333-333333333333',
        '0550000003',
        'كاشير الكاونتر يوسف',
        'cashier',
        TRUE,
        'ar',
        crypt('1234', gen_salt('bf'))
    ),
    (
        '44444444-4444-4444-4444-444444444444',
        '0550000004',
        'سائق التوصيل علي',
        'driver',
        TRUE,
        'ar',
        crypt('1234', gen_salt('bf'))
    ),
    (
        '55555555-5555-5555-5555-555555555555',
        '0550000005',
        'ميني ماركت الأمل (زبون)',
        'customer',
        TRUE,
        'ar',
        NULL -- Customers authenticate via phone OTP
    )
ON CONFLICT (phone) DO UPDATE SET
    name       = EXCLUDED.name,
    role       = EXCLUDED.role,
    active     = TRUE,
    pin_code   = COALESCE(EXCLUDED.pin_code, users.pin_code),
    updated_at = NOW();


-- ── 2. Customer Profile & Delivery Address ────────────────────────────────────
INSERT INTO customers (id, user_id, price_tier, credit_limit) VALUES
    (
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        '55555555-5555-5555-5555-555555555555',
        'wholesale',
        5000000 -- 50,000 DA credit limit in centimes
    )
ON CONFLICT (user_id) DO UPDATE SET
    price_tier   = EXCLUDED.price_tier,
    credit_limit = EXCLUDED.credit_limit,
    updated_at   = NOW();

INSERT INTO addresses (id, customer_id, label, address_text, wilaya, commune, latitude, longitude, is_default) VALUES
    (
        'a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        'المحل الرئيسي',
        'حي 14 شارع الشهداء، باب الزوار',
        'الجزائر',
        'باب الزوار',
        36.7188,
        3.1812,
        TRUE
    )
ON CONFLICT (id) DO NOTHING;


-- ── 3. Suppliers ─────────────────────────────────────────────────────────────
INSERT INTO suppliers (id, name, phone, company_register, notes) VALUES
    (
        'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        'شركة الأغذية العامة الوسطى',
        '023000001',
        'RC-16-009871',
        'مورد معتمد للزيوت والمواد الأولية'
    ),
    (
        'cccccccc-cccc-cccc-cccc-cccccccccccc',
        'مؤسسة مشروبات الشمال',
        '021000002',
        'RC-16-004523',
        'مورد رسمي للمشروبات والقهوة'
    )
ON CONFLICT (id) DO NOTHING;


-- ── 4. Products Catalog ──────────────────────────────────────────────────────
INSERT INTO products (id, name_ar, name_fr, category, unit, pack_size, last_unit_cost, min_stock_alert, active) VALUES
    (
        'dddddddd-dddd-dddd-dddd-dddddddddddd',
        'زيت المائدة 5 لتر',
        'Huile de Table 5L',
        'زيوت ودهون',
        'carton',
        4,
        60000, -- 600.00 DA cost per unit in centimes
        10,
        TRUE
    ),
    (
        'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
        'سكر أبيض بلوري 1 كغ',
        'Sucre Blanc 1kg',
        'مواد غذائية عامة',
        'carton',
        10,
        8500, -- 85.00 DA cost
        20,
        TRUE
    ),
    (
        'ffffffff-ffff-ffff-ffff-ffffffffffff',
        'قهوة مطحونة رفيعة 250 غ',
        'Café Moulu 250g',
        'مشروبات وقهوة',
        'box',
        24,
        22000, -- 220.00 DA cost
        15,
        TRUE
    )
ON CONFLICT (id) DO UPDATE SET
    name_ar        = EXCLUDED.name_ar,
    name_fr        = EXCLUDED.name_fr,
    category       = EXCLUDED.category,
    last_unit_cost = EXCLUDED.last_unit_cost,
    active         = TRUE;


-- ── 5. Product Barcodes (Single Units & Master Cartons) ──────────────────────
INSERT INTO product_barcodes (barcode, product_id, units_per_scan) VALUES
    ('6131234567890', 'dddddddd-dddd-dddd-dddd-dddddddddddd', 1),
    ('6131234567891', 'dddddddd-dddd-dddd-dddd-dddddddddddd', 4),
    ('6139876543210', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 1),
    ('6139876543211', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 10),
    ('6135554443332', 'ffffffff-ffff-ffff-ffff-ffffffffffff', 1),
    ('6135554443333', 'ffffffff-ffff-ffff-ffff-ffffffffffff', 24)
ON CONFLICT (barcode) DO NOTHING;


-- ── 6. Multi-Tier Product Pricing (Retail, Wholesale, Bulk) ──────────────────
INSERT INTO product_prices (product_id, tier, min_qty, price) VALUES
    -- Huile 5L
    ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'retail',    1,  68000), -- 680 DA
    ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'wholesale', 4,  64000), -- 640 DA
    ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'bulk',      20, 62000), -- 620 DA

    -- Sucre 1kg
    ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'retail',    1,  10000), -- 100 DA
    ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'wholesale', 10, 9200),  -- 92 DA
    ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'bulk',      50, 8900),  -- 89 DA

    -- Café 250g
    ('ffffffff-ffff-ffff-ffff-ffffffffffff', 'retail',    1,   26000), -- 260 DA
    ('ffffffff-ffff-ffff-ffff-ffffffffffff', 'wholesale', 24,  24000), -- 240 DA
    ('ffffffff-ffff-ffff-ffff-ffffffffffff', 'bulk',      120, 23000)  -- 230 DA
ON CONFLICT (product_id, tier, min_qty) DO UPDATE SET
    price = EXCLUDED.price;


-- ── 7. Opening Inventory in Append-Only Stock Ledger ─────────────────────────
INSERT INTO stock_ledger (id, product_id, qty_change, reason, ref_type, ref_id, user_id, notes) VALUES
    (
        '10101010-1010-1010-1010-101010101010',
        'dddddddd-dddd-dddd-dddd-dddddddddddd',
        200, -- 200 units on hand
        'adjustment',
        'opening_stock',
        'dddddddd-dddd-dddd-dddd-dddddddddddd',
        '11111111-1111-1111-1111-111111111111',
        'الرصيد الافتتاحي للمخزون - زيت 5 لتر'
    ),
    (
        '20202020-2020-2020-2020-202020202020',
        'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
        1000, -- 1000 units on hand
        'adjustment',
        'opening_stock',
        'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
        '11111111-1111-1111-1111-111111111111',
        'الرصيد الافتتاحي للمخزون - سكر 1 كغ'
    ),
    (
        '30303030-3030-3030-3030-303030303030',
        'ffffffff-ffff-ffff-ffff-ffffffffffff',
        480, -- 480 units on hand
        'adjustment',
        'opening_stock',
        'ffffffff-ffff-ffff-ffff-ffffffffffff',
        '11111111-1111-1111-1111-111111111111',
        'الرصيد الافتتاحي للمخزون - قهوة 250 غ'
    )
ON CONFLICT (ref_id) WHERE ref_type = 'opening_stock' DO NOTHING;

NOTIFY pgrst, 'reload schema';
