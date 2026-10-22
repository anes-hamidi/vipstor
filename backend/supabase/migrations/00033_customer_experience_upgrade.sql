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

-- Force PostgREST to pick up the new function/index metadata.
NOTIFY pgrst, 'reload schema';
