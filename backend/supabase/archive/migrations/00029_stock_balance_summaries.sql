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
