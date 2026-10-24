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
