-- ============================================================
-- customer_app_catchup.sql
-- SAFE CATCH-UP SCRIPT FOR CUSTOMER APP
--
-- Run this once in the Supabase SQL Editor.
-- Every statement uses IF NOT EXISTS / CREATE OR REPLACE /
-- ON CONFLICT DO NOTHING so it is safe to re-run.
--
-- Applies everything from migrations 00010 through 00016
-- that the customer app requires, without touching data.
-- ============================================================


-- ── SECTION 1: ENUM EXTENSIONS ────────────────────────────────────────────────
-- From 00010: Add 'preparing' and 'ready' to order_status if missing

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_type t
        JOIN pg_enum e ON t.oid = e.enumtypid
        WHERE t.typname = 'order_status' AND e.enumlabel = 'preparing'
    ) THEN
        ALTER TYPE order_status ADD VALUE 'preparing' AFTER 'confirmed';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_type t
        JOIN pg_enum e ON t.oid = e.enumtypid
        WHERE t.typname = 'order_status' AND e.enumlabel = 'ready'
    ) THEN
        ALTER TYPE order_status ADD VALUE 'ready' AFTER 'preparing';
    END IF;
END $$;


-- ── SECTION 2: DRIVER LOCATIONS TABLE ────────────────────────────────────────
-- From 00011: Real-time driver location tracking

CREATE TABLE IF NOT EXISTS driver_locations (
    driver_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    heading DOUBLE PRECISION,
    speed DOUBLE PRECISION,
    battery_level INTEGER,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE driver_locations ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'driver_locations' AND policyname = 'Drivers can upsert their own location'
    ) THEN
        CREATE POLICY "Drivers can upsert their own location"
        ON driver_locations FOR ALL
        USING (
            driver_id = auth.uid()
            OR get_auth_role() IN ('moderator', 'manager', 'cashier')
        )
        WITH CHECK (
            driver_id = auth.uid()
            OR get_auth_role() IN ('moderator', 'manager', 'cashier')
        );
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'driver_locations' AND policyname = 'Customers can track active delivery driver'
    ) THEN
        CREATE POLICY "Customers can track active delivery driver"
        ON driver_locations FOR SELECT
        USING (
            EXISTS (
                SELECT 1 FROM orders o
                JOIN customers c ON o.customer_id = c.id
                WHERE c.user_id = auth.uid()
                  AND o.driver_id = driver_locations.driver_id
                  AND o.status IN ('assigned', 'accepted', 'out_for_delivery')
            )
        );
    END IF;
END $$;


-- ── SECTION 3: AUDIT_LOG TABLE ────────────────────────────────────────────────
-- From 00012: Needed by security RPCs in 00015

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

ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow view audit logs" ON audit_log;
CREATE POLICY "Allow view audit logs"
ON audit_log FOR SELECT
USING (TRUE);

CREATE INDEX IF NOT EXISTS idx_audit_log_target  ON audit_log(target_table, target_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_user    ON audit_log(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_created ON audit_log(created_at DESC);


-- ── SECTION 4: STORAGE BUCKET ─────────────────────────────────────────────────
-- From 00013: Product images bucket

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'product-images',
    'product-images',
    TRUE,
    5242880,
    ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE SET
    public = TRUE,
    file_size_limit = 5242880,
    allowed_mime_types = ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp'];


-- ── SECTION 5: CLIENT_ID COLUMN ON ORDERS ─────────────────────────────────────
-- From 00014: Idempotency key for offline order sync

ALTER TABLE orders ADD COLUMN IF NOT EXISTS client_id UUID UNIQUE;


-- ── SECTION 6: VIEW_CUSTOMER_PRODUCTS (THE MAIN FIX) ─────────────────────────
-- From 00014: Slim customer-facing product catalogue view.
-- security_invoker = true means the caller's RLS is applied,
-- so customers only see active products they are allowed to read.

CREATE OR REPLACE VIEW view_customer_products
WITH (security_invoker = true)
AS
SELECT
    p.id                AS product_id,
    p.name_ar,
    p.name_fr,
    p.category,
    p.unit,
    p.pack_size,
    p.photo_url,
    p.active,
    (
        COALESCE(sl_agg.total_on_hand, 0)
        - COALESCE(res.reserved_qty, 0)
    )                   AS available_qty,
    (
        (COALESCE(sl_agg.total_on_hand, 0) - COALESCE(res.reserved_qty, 0)) > 0
    )                   AS in_stock
FROM products p
LEFT JOIN (
    SELECT product_id, SUM(qty_change) AS total_on_hand
    FROM stock_ledger
    GROUP BY product_id
) sl_agg ON p.id = sl_agg.product_id
LEFT JOIN (
    SELECT oi.product_id, SUM(oi.quantity) AS reserved_qty
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.id
    WHERE o.status IN ('confirmed', 'assigned', 'accepted', 'out_for_delivery')
    GROUP BY oi.product_id
) res ON p.id = res.product_id
WHERE p.active = TRUE;


-- ── SECTION 7: RPC_SUBMIT_CUSTOMER_ORDER ──────────────────────────────────────
-- From 00014: Server-side price resolution for customer orders.

CREATE OR REPLACE FUNCTION rpc_submit_customer_order(
    p_client_id         UUID,
    p_customer_id       UUID,
    p_delivery_address  JSONB,
    p_items             JSONB   -- [{product_id: UUID, quantity: INT}]
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_order_id              UUID;
    v_user_tier             price_tier := 'wholesale';
    v_item                  JSONB;
    v_product_id            UUID;
    v_qty                   INT;
    v_unit_price            BIGINT;
    v_unit_cost             BIGINT;
    v_total_amount          BIGINT := 0;
    v_total_cost            BIGINT := 0;
    v_resolved_customer_id  UUID := p_customer_id;
BEGIN
    -- Idempotency: return existing order if client_id already used
    IF p_client_id IS NOT NULL THEN
        SELECT id INTO v_order_id FROM orders WHERE client_id = p_client_id;
        IF v_order_id IS NOT NULL THEN
            RETURN v_order_id;
        END IF;
    END IF;

    -- Resolve customer tier
    IF v_resolved_customer_id IS NOT NULL THEN
        SELECT price_tier INTO v_user_tier
        FROM customers WHERE id = v_resolved_customer_id;
        IF NOT FOUND THEN
            SELECT id, price_tier
            INTO v_resolved_customer_id, v_user_tier
            FROM customers WHERE user_id = auth.uid();
        END IF;
    ELSE
        SELECT id, price_tier
        INTO v_resolved_customer_id, v_user_tier
        FROM customers WHERE user_id = auth.uid();
    END IF;

    IF v_user_tier IS NULL THEN v_user_tier := 'wholesale'; END IF;

    v_order_id := gen_random_uuid();

    INSERT INTO orders (
        id, client_id, channel, customer_id, status,
        delivery_address, total_amount, total_cost, paid_amount
    )
    VALUES (
        v_order_id, p_client_id, 'online', v_resolved_customer_id,
        'submitted', p_delivery_address, 0, 0, 0
    )
    ON CONFLICT (client_id) DO NOTHING;

    IF NOT FOUND THEN
        SELECT id INTO v_order_id FROM orders WHERE client_id = p_client_id;
        RETURN v_order_id;
    END IF;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        v_product_id := (v_item->>'product_id')::UUID;
        v_qty        := (v_item->>'quantity')::INT;

        IF v_qty <= 0 THEN
            RAISE EXCEPTION 'Quantity must be > 0 for product %', v_product_id;
        END IF;

        -- Server-side price by tier + min_qty
        SELECT price INTO v_unit_price
        FROM product_prices
        WHERE product_id = v_product_id
          AND tier = v_user_tier
          AND min_qty <= v_qty
        ORDER BY min_qty DESC
        LIMIT 1;

        IF v_unit_price IS NULL THEN
            SELECT price INTO v_unit_price
            FROM product_prices
            WHERE product_id = v_product_id
            ORDER BY min_qty ASC
            LIMIT 1;
        END IF;

        IF v_unit_price IS NULL THEN
            RAISE EXCEPTION 'No price configured for product %', v_product_id;
        END IF;

        SELECT COALESCE(last_unit_cost, 0) INTO v_unit_cost
        FROM products WHERE id = v_product_id;

        v_total_amount := v_total_amount + (v_qty * v_unit_price);
        v_total_cost   := v_total_cost   + (v_qty * COALESCE(v_unit_cost, 0));

        INSERT INTO order_items (order_id, product_id, quantity, unit_price, unit_cost)
        VALUES (v_order_id, v_product_id, v_qty, v_unit_price, COALESCE(v_unit_cost, 0));
    END LOOP;

    UPDATE orders
    SET total_amount = v_total_amount,
        total_cost   = v_total_cost
    WHERE id = v_order_id;

    RETURN v_order_id;
END;
$$;


-- ── SECTION 8: PIN SECURITY TABLE ─────────────────────────────────────────────
-- From 00015: Brute-force protection

CREATE TABLE IF NOT EXISTS pin_attempt_limits (
    user_id        UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    failed_attempts INT NOT NULL DEFAULT 0,
    locked_until   TIMESTAMPTZ,
    lock_step      INT NOT NULL DEFAULT 0,
    last_failed_at TIMESTAMPTZ
);

ALTER TABLE pin_attempt_limits ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON pin_attempt_limits FROM PUBLIC, anon, authenticated;


-- ── SECTION 9: PIN_CODE COLUMN ────────────────────────────────────────────────
-- From 00009: Ensure pin_code column exists

ALTER TABLE users ADD COLUMN IF NOT EXISTS pin_code VARCHAR(10) DEFAULT '1234';


-- ── SECTION 10: GRANTS — THE ACTUAL FIX FOR THE SCHEMA CACHE ERROR ───────────
-- PostgREST only exposes objects that the calling role has SELECT/EXECUTE on.
-- Without these GRANTs the view is invisible to the client even if it exists.

GRANT SELECT ON view_customer_products                     TO anon, authenticated;
GRANT SELECT ON products                                   TO anon, authenticated;
GRANT SELECT ON product_prices                             TO anon, authenticated;
GRANT SELECT ON product_barcodes                           TO anon, authenticated;
GRANT SELECT ON orders                                     TO authenticated;
GRANT SELECT ON order_items                                TO authenticated;
GRANT SELECT ON view_customer_balance                      TO authenticated;
GRANT SELECT ON view_product_stock                         TO authenticated;
GRANT SELECT ON driver_locations                           TO authenticated;

GRANT EXECUTE ON FUNCTION rpc_submit_customer_order(UUID, UUID, JSONB, JSONB)
    TO anon, authenticated;
GRANT EXECUTE ON FUNCTION rpc_verify_user_pin(UUID, TEXT)
    TO anon, authenticated;
GRANT EXECUTE ON FUNCTION rpc_change_user_pin(UUID, TEXT, TEXT)
    TO anon, authenticated;


-- ── SECTION 11: FORCE POSTGREST SCHEMA CACHE RELOAD ──────────────────────────
-- This tells PostgREST to re-scan the schema immediately.
-- You should also go to Supabase Dashboard → API → "Reload Schema" as a backup.

NOTIFY pgrst, 'reload schema';
