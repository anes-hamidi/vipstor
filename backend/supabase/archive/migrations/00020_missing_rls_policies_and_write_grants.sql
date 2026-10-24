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
