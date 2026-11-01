-- ============================================================================
-- 010_driver_delivery_ops.sql
-- Driver delivery proof-of-delivery and failed-attempt workflow.
--
-- Adds:
--   * durable proof metadata on orders (signature, photo, GPS, recipient,
--     delivery notes);
--   * rpc_record_order_delivery_v2 — cash collection + proof in one transaction;
--   * rpc_record_delivery_failure — routes an unsuccessful attempt to the
--     manager review queue without touching cash or marking it delivered.
--
-- Run after 009_staff_pin_auth.sql, then redeploy the staff app.
-- ============================================================================

BEGIN;

-- ── 1. Proof / attempt metadata ─────────────────────────────────────────────
ALTER TABLE public.orders
    ADD COLUMN IF NOT EXISTS delivery_signature       TEXT,
    ADD COLUMN IF NOT EXISTS delivery_photo           TEXT,
    ADD COLUMN IF NOT EXISTS delivery_lat             DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS delivery_lng             DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS delivery_recipient_name  TEXT,
    ADD COLUMN IF NOT EXISTS delivery_notes           TEXT,
    ADD COLUMN IF NOT EXISTS delivery_failure_reason  TEXT,
    ADD COLUMN IF NOT EXISTS delivery_attempted_at    TIMESTAMPTZ;

COMMENT ON COLUMN public.orders.delivery_signature IS
    'Base64-encoded PNG signature captured by the driver app.';
COMMENT ON COLUMN public.orders.delivery_photo IS
    'Base64-encoded compressed delivery photo captured by the driver app.';
COMMENT ON COLUMN public.orders.delivery_failure_reason IS
    'Stable failure code when a delivery attempt ends without hand-off.';
COMMENT ON COLUMN public.orders.delivery_attempted_at IS
    'Timestamp of the last delivery attempt / hand-off.';

CREATE INDEX IF NOT EXISTS idx_orders_delivery_failure
    ON public.orders (delivery_attempted_at DESC)
    WHERE delivery_failure_reason IS NOT NULL;

-- ── 2. Delivery with proof ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_record_order_delivery_v2(
    p_driver_id       UUID,
    p_order_id        UUID,
    p_collected_cash  BIGINT,
    p_client_id       UUID,
    p_signature_base64 TEXT DEFAULT NULL,
    p_photo_base64     TEXT DEFAULT NULL,
    p_delivery_lat     DOUBLE PRECISION DEFAULT NULL,
    p_delivery_lng     DOUBLE PRECISION DEFAULT NULL,
    p_recipient_name   TEXT DEFAULT NULL,
    p_notes            TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor        UUID := public.current_app_user_id();
    v_role         public.user_role := public.current_app_role();
    v_driver       UUID;
    v_prior_failure TEXT;
    v_result       JSONB;
BEGIN
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'not authenticated' USING ERRCODE = '42501';
    END IF;
    IF p_collected_cash IS NULL OR p_collected_cash < 0 THEN
        RAISE EXCEPTION 'collected cash cannot be negative' USING ERRCODE = '22023';
    END IF;
    IF length(COALESCE(p_signature_base64, '')) > 2_000_000
       OR length(COALESCE(p_photo_base64, '')) > 8_000_000 THEN
        RAISE EXCEPTION 'delivery proof payload is too large' USING ERRCODE = '22023';
    END IF;

    IF v_role = 'driver'::public.user_role THEN
        v_driver := v_actor;
    ELSIF public.is_cashier_or_above() THEN
        v_driver := p_driver_id;
        IF v_driver IS NULL THEN
            SELECT driver_id INTO v_driver
            FROM public.orders
            WHERE id = p_order_id;
        END IF;
    ELSE
        RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
    END IF;

    IF v_driver IS NULL
       OR NOT EXISTS (
           SELECT 1 FROM public.orders
           WHERE id = p_order_id AND driver_id = v_driver
       )
       OR NOT EXISTS (
           SELECT 1 FROM public.users
           WHERE id = v_driver
             AND role = 'driver'::public.user_role
             AND active
       ) THEN
        RAISE EXCEPTION 'forbidden: order is not assigned to this driver'
            USING ERRCODE = '42501';
    END IF;

    -- Remember whether this order previously failed. A successful redelivery
    -- must replace failed-attempt metadata instead of inheriting it.
    SELECT delivery_failure_reason INTO v_prior_failure
    FROM public.orders
    WHERE id = p_order_id;

    -- The internal function performs the atomic cash/ledger/delivery write.
    v_result := public.internal_record_order_delivery(
        v_driver, p_order_id, p_collected_cash, p_client_id);

    -- Attach proof even when the internal call is an idempotent repeat.
    UPDATE public.orders
    SET delivery_signature      = COALESCE(p_signature_base64, delivery_signature),
        delivery_photo          = COALESCE(p_photo_base64, delivery_photo),
        delivery_lat            = CASE
            WHEN v_prior_failure IS NOT NULL THEN p_delivery_lat
            ELSE COALESCE(p_delivery_lat, delivery_lat)
        END,
        delivery_lng            = CASE
            WHEN v_prior_failure IS NOT NULL THEN p_delivery_lng
            ELSE COALESCE(p_delivery_lng, delivery_lng)
        END,
        delivery_recipient_name = COALESCE(
            NULLIF(btrim(p_recipient_name), ''), delivery_recipient_name),
        delivery_notes          = CASE
            WHEN v_prior_failure IS NOT NULL THEN NULLIF(btrim(p_notes), '')
            ELSE COALESCE(NULLIF(btrim(p_notes), ''), delivery_notes)
        END,
        delivery_failure_reason = NULL,
        delivery_attempted_at   = NOW(),
        updated_at              = NOW()
    WHERE id = p_order_id;

    RETURN v_result;
END;
$$;

-- ── 3. Unsuccessful delivery attempt ────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_record_delivery_failure(
    p_order_id    UUID,
    p_reason      TEXT,
    p_client_id   UUID,
    p_notes       TEXT DEFAULT NULL,
    p_delivery_lat DOUBLE PRECISION DEFAULT NULL,
    p_delivery_lng DOUBLE PRECISION DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID := public.current_app_user_id();
    v_role  public.user_role := public.current_app_role();
    v_order public.orders%ROWTYPE;
BEGIN
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'not authenticated' USING ERRCODE = '42501';
    END IF;
    IF p_reason NOT IN (
        'customer_unavailable',
        'wrong_address',
        'customer_refused',
        'payment_issue',
        'damaged_order',
        'other'
    ) THEN
        RAISE EXCEPTION 'invalid delivery failure reason' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_order
    FROM public.orders
    WHERE id = p_order_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'order not found' USING ERRCODE = 'P0002';
    END IF;

    IF v_role = 'driver'::public.user_role THEN
        IF v_order.driver_id IS DISTINCT FROM v_actor THEN
            RAISE EXCEPTION 'forbidden: order is not assigned to this driver'
                USING ERRCODE = '42501';
        END IF;
    ELSIF NOT public.is_cashier_or_above() THEN
        RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
    END IF;

    IF v_order.status IN (
        'delivered'::public.order_status,
        'settled'::public.order_status,
        'cancelled'::public.order_status,
        'refused'::public.order_status
    ) THEN
        RAISE EXCEPTION 'terminal orders cannot record a failed attempt'
            USING ERRCODE = '42501';
    END IF;

    UPDATE public.orders
    SET status                    = 'requires_manager_review'::public.order_status,
        delivery_failure_reason   = p_reason,
        delivery_attempted_at     = NOW(),
        delivery_lat              = COALESCE(p_delivery_lat, delivery_lat),
        delivery_lng              = COALESCE(p_delivery_lng, delivery_lng),
        delivery_notes            = COALESCE(
            NULLIF(btrim(p_notes), ''), delivery_notes),
        updated_at                = NOW()
    WHERE id = p_order_id;

    RETURN jsonb_build_object(
        'status', 'requires_manager_review',
        'order_id', p_order_id,
        'reason', p_reason,
        'client_id', p_client_id
    );
END;
$$;

-- ── 3b. Manager resolution / reassignment ───────────────────────────────────
-- Reassigning a failed order clears the failed-attempt metadata so it returns
-- to the new driver's active queue. Terminal orders stay immutable.
CREATE OR REPLACE FUNCTION public.rpc_assign_order_driver(
    p_order_id UUID, p_driver_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT public.is_cashier_or_above() THEN
        RAISE EXCEPTION 'forbidden: cashier or above only' USING ERRCODE = '42501';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.users
        WHERE id = p_driver_id
          AND role = 'driver'::public.user_role
          AND active
    ) THEN
        RAISE EXCEPTION 'invalid driver' USING ERRCODE = '22023';
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.orders
        WHERE id = p_order_id
          AND status IN ('delivered'::public.order_status,
                         'settled'::public.order_status,
                         'cancelled'::public.order_status,
                         'refused'::public.order_status)
    ) THEN
        RAISE EXCEPTION 'terminal orders cannot be reassigned' USING ERRCODE = '42501';
    END IF;

    UPDATE public.orders
    SET driver_id                 = p_driver_id,
        status                    = 'assigned'::public.order_status,
        delivery_failure_reason   = NULL,
        delivery_attempted_at     = NULL,
        delivery_lat              = NULL,
        delivery_lng              = NULL,
        delivery_notes            = NULL,
        delivery_recipient_name   = NULL,
        delivery_signature        = NULL,
        delivery_photo            = NULL,
        updated_at                = NOW()
    WHERE id = p_order_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'order not found' USING ERRCODE = 'P0002';
    END IF;
    RETURN jsonb_build_object('status', 'success', 'order_id', p_order_id);
END;
$$;

-- ── 4. Permissions ──────────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION public.rpc_record_order_delivery_v2(
    UUID, UUID, BIGINT, UUID, TEXT, TEXT, DOUBLE PRECISION,
    DOUBLE PRECISION, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rpc_record_delivery_failure(
    UUID, TEXT, UUID, TEXT, DOUBLE PRECISION, DOUBLE PRECISION) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.rpc_record_order_delivery_v2(
    UUID, UUID, BIGINT, UUID, TEXT, TEXT, DOUBLE PRECISION,
    DOUBLE PRECISION, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_record_delivery_failure(
    UUID, TEXT, UUID, TEXT, DOUBLE PRECISION, DOUBLE PRECISION)
    TO authenticated;

-- ── 5. Version tracking ─────────────────────────────────────────────────────
INSERT INTO public.schema_migrations (version, description)
VALUES ('00041', '00041 - Driver proof-of-delivery and failed-attempt workflow')
ON CONFLICT (version) DO NOTHING;

NOTIFY pgrst, 'reload schema';

COMMIT;
