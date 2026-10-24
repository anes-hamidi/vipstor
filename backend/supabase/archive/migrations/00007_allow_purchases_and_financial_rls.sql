-- ============================================================
-- 00007_allow_purchases_and_financial_rls.sql
-- PERMISSIVE RLS POLICIES FOR PURCHASES AND FINANCIAL LEDGERS
-- ============================================================

-- 1. Purchases
DROP POLICY IF EXISTS "Allow all operations on purchases" ON purchases;
CREATE POLICY "Allow all operations on purchases"
ON purchases FOR ALL
USING (TRUE)
WITH CHECK (TRUE);

-- 2. Purchase Items
DROP POLICY IF EXISTS "Allow all operations on purchase_items" ON purchase_items;
CREATE POLICY "Allow all operations on purchase_items"
ON purchase_items FOR ALL
USING (TRUE)
WITH CHECK (TRUE);

-- 3. Supplier Ledger
DROP POLICY IF EXISTS "Allow all operations on supplier_ledger" ON supplier_ledger;
CREATE POLICY "Allow all operations on supplier_ledger"
ON supplier_ledger FOR ALL
USING (TRUE)
WITH CHECK (TRUE);

-- 4. Customer Ledger
DROP POLICY IF EXISTS "Customers view own ledger balance" ON customer_ledger;
DROP POLICY IF EXISTS "Allow all operations on customer_ledger" ON customer_ledger;
CREATE POLICY "Allow all operations on customer_ledger"
ON customer_ledger FOR ALL
USING (TRUE)
WITH CHECK (TRUE);

-- 5. Payments
DROP POLICY IF EXISTS "Allow all operations on payments" ON payments;
CREATE POLICY "Allow all operations on payments"
ON payments FOR ALL
USING (TRUE)
WITH CHECK (TRUE);

-- 6. Settlements
DROP POLICY IF EXISTS "Allow all operations on settlements" ON settlements;
CREATE POLICY "Allow all operations on settlements"
ON settlements FOR ALL
USING (TRUE)
WITH CHECK (TRUE);

-- 7. Wallet Entries
DROP POLICY IF EXISTS "Drivers view own wallet entries" ON wallet_entries;
DROP POLICY IF EXISTS "Allow all operations on wallet_entries" ON wallet_entries;
CREATE POLICY "Allow all operations on wallet_entries"
ON wallet_entries FOR ALL
USING (TRUE)
WITH CHECK (TRUE);
