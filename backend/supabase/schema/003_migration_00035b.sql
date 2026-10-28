-- ============================================================
-- MIGRATION 00035b: rpc_resolve_stock_conflict
-- Manager review flow for orders flagged 'requires_manager_review'
-- ============================================================
--
-- When rpc_post_store_sale detects a stock conflict (B4 fix in 00035),
-- it creates the order with status = 'requires_manager_review' but
-- deliberately SKIPS writing stock_ledger entries.
--
-- A manager must then call this RPC to:
--   APPROVE  → write stock_ledger for items that actually shipped
--              and mark the order 'delivered'
--   CANCEL   → void the order, credit any payment back to the customer,
--              and mark it 'cancelled'
--
-- This preserves ledger integrity: stock never goes negative, and
-- every ledger entry has a human authorization behind it.
-- ============================================================

CREATE OR REPLACE FUNCTION rpc_resolve_stock_conflict(
    p_manager_id    UUID,
    p_manager_pin   TEXT,
    p_order_id      UUID,
    p_action        TEXT,     -- 'approve' or 'cancel'
    p_adjustments   JSONB DEFAULT NULL,
    -- For approve: optional array of {product_id, quantity} to override
    -- what was actually shipped vs what was ordered. NULL = ship all items
    -- at their original quantities (manager has verified stock manually).
    p_notes         TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_auth_check  JSONB;
    v_caller      users%ROWTYPE;
    v_order       orders%ROWTYPE;
    v_item        RECORD;
    v_adj_map     JSONB := '{}'::JSONB;
    v_adj_qty     INT;
    v_shipped     INT := 0;
    v_refund      BIGINT := 0;
BEGIN
    -- ── 1. Verify manager PIN ─────────────────────────────────────────────
    v_auth_check := _internal_verify_and_track_pin(p_manager_id, p_manager_pin, FALSE);
    IF COALESCE((v_auth_check->>'valid')::BOOLEAN, FALSE) IS NOT TRUE THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', COALESCE(v_auth_check->>'message', 'فشل التحقق من هوية المدير')
        );
    END IF;

    SELECT * INTO v_caller FROM users WHERE id = p_manager_id;
    IF NOT FOUND OR v_caller.role NOT IN ('moderator', 'manager') THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'هذه العملية متاحة للمدير أو المشرف العام فقط'
        );
    END IF;

    -- ── 2. Load and validate the order ───────────────────────────────────
    SELECT * INTO v_order FROM orders WHERE id = p_order_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'الطلب غير موجود');
    END IF;

    IF v_order.status <> 'requires_manager_review' THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', format('الطلب ليس في وضع المراجعة (الحالة الحالية: %s)', v_order.status)
        );
    END IF;

    -- ── 3. Validate action ────────────────────────────────────────────────
    IF p_action NOT IN ('approve', 'cancel') THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'الإجراء غير صالح — يجب أن يكون approve أو cancel'
        );
    END IF;

    -- ── 4. Build adjustment quantity map if provided ──────────────────────
    -- Allows manager to ship partial quantities (e.g., only 3 of 5 ordered)
    IF p_adjustments IS NOT NULL THEN
        SELECT jsonb_object_agg(item->>'product_id', (item->>'quantity')::INT)
        INTO v_adj_map
        FROM jsonb_array_elements(p_adjustments) AS item;
    END IF;

    -- ── 5a. APPROVE: write stock_ledger for shipped items ─────────────────
    IF p_action = 'approve' THEN
        FOR v_item IN
            SELECT oi.product_id, oi.quantity, oi.unit_price
            FROM order_items oi
            WHERE oi.order_id = p_order_id
        LOOP
            -- Use adjusted qty if provided, otherwise original order qty
            IF p_adjustments IS NOT NULL AND v_adj_map ? v_item.product_id::text THEN
                v_adj_qty := (v_adj_map->>v_item.product_id::text)::INT;
            ELSE
                v_adj_qty := v_item.quantity;
            END IF;

            -- Skip items with zero adjusted qty (manager chose not to ship)
            CONTINUE WHEN v_adj_qty <= 0;

            -- Write stock deduction — this is the deferred write from rpc_post_store_sale
            INSERT INTO stock_ledger (
                product_id, qty_change, reason, ref_type, ref_id, user_id, notes
            ) VALUES (
                v_item.product_id,
                -v_adj_qty,
                'sale',
                'order',
                p_order_id,
                p_manager_id,
                format('Manager-approved conflict resolution (order %s)', p_order_id)
            );

            v_shipped := v_shipped + 1;
        END LOOP;

        -- Update order items if quantities were adjusted
        IF p_adjustments IS NOT NULL THEN
            FOR v_item IN
                SELECT oi.id, oi.product_id
                FROM order_items oi
                WHERE oi.order_id = p_order_id
            LOOP
                IF v_adj_map ? v_item.product_id::text THEN
                    UPDATE order_items
                    SET quantity = (v_adj_map->>v_item.product_id::text)::INT
                    WHERE id = v_item.id;
                END IF;
            END LOOP;
        END IF;

        UPDATE orders
        SET status       = 'delivered',
            delivered_at = NOW(),
            notes        = COALESCE(
                p_notes,
                format('Manager-resolved stock conflict. %s items shipped.', v_shipped)
            )
        WHERE id = p_order_id;

        INSERT INTO audit_log (user_id, action, target_table, target_id, after_state)
        VALUES (p_manager_id, 'STOCK_CONFLICT_APPROVED', 'orders', p_order_id,
            jsonb_build_object(
                'order_id', p_order_id,
                'items_shipped', v_shipped,
                'adjustments_applied', p_adjustments IS NOT NULL,
                'resolved_by', p_manager_id,
                'notes', p_notes
            )
        );

        RETURN jsonb_build_object(
            'status', 'success',
            'action', 'approved',
            'order_id', p_order_id,
            'items_shipped', v_shipped
        );
    END IF;

    -- ── 5b. CANCEL: void the order, refund any collected cash ─────────────
    IF p_action = 'cancel' THEN
        -- Refund any cash payment already recorded for this order
        SELECT COALESCE(SUM(amount), 0) INTO v_refund
        FROM payments
        WHERE order_id = p_order_id AND status = 'collected';

        IF v_refund > 0 THEN
            -- Reverse the payment
            UPDATE payments
            SET status = 'reversed'
            WHERE order_id = p_order_id AND status = 'collected';

            -- Credit back to customer balance if it was a known customer
            IF v_order.customer_id IS NOT NULL THEN
                INSERT INTO customer_ledger (
                    customer_id, amount_change, ref_type, ref_id, notes
                ) VALUES (
                    v_order.customer_id,
                    -v_refund,   -- negative = reduces their debt
                    'order_reversal',
                    p_order_id,
                    format('Refund: cancelled conflict-order %s', p_order_id)
                );
            END IF;
        END IF;

        UPDATE orders
        SET status = 'cancelled',
            notes  = COALESCE(
                p_notes,
                format('Cancelled by manager %s — stock conflict unresolvable', p_manager_id)
            )
        WHERE id = p_order_id;

        INSERT INTO audit_log (user_id, action, target_table, target_id, after_state)
        VALUES (p_manager_id, 'STOCK_CONFLICT_CANCELLED', 'orders', p_order_id,
            jsonb_build_object(
                'order_id', p_order_id,
                'refund_centimes', v_refund,
                'resolved_by', p_manager_id,
                'notes', p_notes
            )
        );

        RETURN jsonb_build_object(
            'status', 'success',
            'action', 'cancelled',
            'order_id', p_order_id,
            'refunded_centimes', v_refund
        );
    END IF;

    -- Unreachable, but Postgres requires a final RETURN
    RETURN jsonb_build_object('status', 'error', 'message', 'unexpected path');
END;
$$;

REVOKE ALL ON FUNCTION rpc_resolve_stock_conflict(UUID, TEXT, UUID, TEXT, JSONB, TEXT)
    FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_resolve_stock_conflict(UUID, TEXT, UUID, TEXT, JSONB, TEXT)
    TO authenticated;
-- Note: anon cannot call this — only authenticated sessions (manager/moderator).


-- ── View for the manager review queue ────────────────────────────────────────
-- Shows all orders pending conflict resolution, enriched with item details.
CREATE OR REPLACE VIEW view_stock_conflict_queue AS
SELECT
    o.id              AS order_id,
    o.order_number,
    o.created_at,
    o.total_amount,
    o.paid_amount,
    o.notes           AS conflict_details,
    u.name            AS cashier_name,
    c.id              AS customer_id,
    cu.name           AS customer_name,
    cu.phone          AS customer_phone,
    jsonb_agg(jsonb_build_object(
        'product_id',   oi.product_id,
        'product_name', p.name_ar,
        'ordered_qty',  oi.quantity,
        'unit_price',   oi.unit_price,
        'available_qty', COALESCE(ss.on_hand_qty, 0)
    ) ORDER BY p.name_ar) AS items
FROM orders o
LEFT JOIN users u  ON u.id  = o.cashier_id
LEFT JOIN customers c  ON c.id  = o.customer_id
LEFT JOIN users cu ON cu.id = c.user_id
JOIN order_items oi ON oi.order_id = o.id
JOIN products p     ON p.id = oi.product_id
LEFT JOIN product_stock_snapshot ss ON ss.product_id = p.id
WHERE o.status = 'requires_manager_review'
GROUP BY o.id, o.order_number, o.created_at, o.total_amount,
         o.paid_amount, o.notes, u.name, c.id, cu.name, cu.phone
ORDER BY o.created_at ASC;

GRANT SELECT ON view_stock_conflict_queue TO authenticated;


-- ── Schema migration record ───────────────────────────────────────────────────
INSERT INTO schema_migrations (version, description) VALUES
    ('00035b', '00035b - rpc_resolve_stock_conflict + view_stock_conflict_queue')
ON CONFLICT (version) DO NOTHING;

NOTIFY pgrst, 'reload schema';


-- ============================================================
-- USAGE EXAMPLES
-- ============================================================
/*

-- Approve conflict: ship what was originally ordered
SELECT rpc_resolve_stock_conflict(
    '<manager-uuid>',
    '1234',                 -- manager's PIN
    '<order-uuid>',
    'approve',
    NULL,                   -- ship all items at original qty
    'مراجعة مخزون مباشرة — الكميات صحيحة'
);

-- Approve conflict with partial quantities (3 of 5 bottles in stock)
SELECT rpc_resolve_stock_conflict(
    '<manager-uuid>',
    '1234',
    '<order-uuid>',
    'approve',
    '[{"product_id": "<prod-uuid>", "quantity": 3}]'::jsonb,
    'شحن جزئي — 3 زجاجات متاحة من أصل 5'
);

-- Cancel the conflict order entirely
SELECT rpc_resolve_stock_conflict(
    '<manager-uuid>',
    '1234',
    '<order-uuid>',
    'cancel',
    NULL,
    'إلغاء الطلب — المخزون غير متاح'
);

-- View the conflict queue (for the manager UI)
SELECT * FROM view_stock_conflict_queue;

*/
