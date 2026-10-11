-- ============================================================
-- seed.sql
-- INITIAL SAMPLE SEED DATA
-- ============================================================

INSERT INTO users (id, phone, name, role, language) VALUES
('11111111-1111-1111-1111-111111111111', '+213550000001', 'Admin Moderator', 'moderator', 'ar'),
('22222222-2222-2222-2222-222222222222', '+213550000002', 'Inventory Manager', 'manager', 'fr'),
('33333333-3333-3333-3333-333333333333', '+213550000003', 'Counter Cashier', 'cashier', 'ar'),
('44444444-4444-4444-4444-444444444444', '+213550000004', 'Delivery Driver Ali', 'driver', 'ar'),
('55555555-5555-5555-5555-555555555555', '+213550000005', 'Epicerie El Amel (Customer)', 'customer', 'ar')
ON CONFLICT (id) DO NOTHING;

INSERT INTO customers (id, user_id, price_tier, credit_limit) VALUES
('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '55555555-5555-5555-5555-555555555555', 'wholesale', 5000000)
ON CONFLICT (id) DO NOTHING;

INSERT INTO addresses (customer_id, label, address_text, wilaya, commune, is_default) VALUES
('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Magasin Bab Ezzouar', '14 Rue des Martyrs', 'Alger', 'Bab Ezzouar', TRUE);

INSERT INTO suppliers (id, name, phone, company_register) VALUES
('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'SPA Agro-Alimentaire Centrale', '+21323000000', 'RC-16-009871'),
('cccccccc-cccc-cccc-cccc-cccccccccccc', 'SARL Boissons du Nord', '+21321000000', 'RC-16-004523')
ON CONFLICT (id) DO NOTHING;

INSERT INTO products (id, name_ar, name_fr, category, unit, pack_size, last_unit_cost, active) VALUES
('dddddddd-dddd-dddd-dddd-dddddddddddd', 'زيت المائدة 5 لتر', 'Huile de Table 5L', 'Huiles', 'carton', 4, 60000, TRUE),
('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'سكر أبيض 1 كغ', 'Sucre Blanc 1kg', 'Epicerie', 'carton', 10, 8500, TRUE),
('ffffffff-ffff-ffff-ffff-ffffffffffff', 'قهوة مطحونة 250 غ', 'Café Moulu 250g', 'Boissons', 'box', 24, 22000, TRUE)
ON CONFLICT (id) DO NOTHING;

INSERT INTO product_barcodes (barcode, product_id, units_per_scan) VALUES
('6131234567890', 'dddddddd-dddd-dddd-dddd-dddddddddddd', 1),
('6131234567891', 'dddddddd-dddd-dddd-dddd-dddddddddddd', 4),
('6139876543210', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 1),
('6139876543211', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 10),
('6135554443332', 'ffffffff-ffff-ffff-ffff-ffffffffffff', 1)
ON CONFLICT (barcode) DO NOTHING;

INSERT INTO product_prices (product_id, tier, min_qty, price) VALUES
('dddddddd-dddd-dddd-dddd-dddddddddddd', 'retail', 1, 68000),
('dddddddd-dddd-dddd-dddd-dddddddddddd', 'wholesale', 4, 64000),
('dddddddd-dddd-dddd-dddd-dddddddddddd', 'bulk', 20, 62000),

('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'retail', 1, 10000),
('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'wholesale', 10, 9200),
('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'bulk', 50, 8900),

('ffffffff-ffff-ffff-ffff-ffffffffffff', 'retail', 1, 26000),
('ffffffff-ffff-ffff-ffff-ffffffffffff', 'wholesale', 24, 24000),
('ffffffff-ffff-ffff-ffff-ffffffffffff', 'bulk', 120, 23000)
ON CONFLICT DO NOTHING;

INSERT INTO stock_ledger (product_id, qty_change, reason, ref_type, ref_id, user_id, notes) VALUES
('dddddddd-dddd-dddd-dddd-dddddddddddd', 100, 'adjustment', 'initial_opening_stock', '11111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 'Stock initial huile'),
('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 500, 'adjustment', 'initial_opening_stock', '11111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 'Stock initial sucre'),
('ffffffff-ffff-ffff-ffff-ffffffffffff', 240, 'adjustment', 'initial_opening_stock', '11111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 'Stock initial café');
