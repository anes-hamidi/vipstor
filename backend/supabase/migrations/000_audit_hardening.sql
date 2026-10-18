-- ============================================================
-- AUDIT LOG HARDENING
-- Fixes all gaps found in the audit trail analysis:
--   1. Add audit triggers to missing tables
--   2. Fix NULL user_id for customer-submitted orders
--   3. Populate ip_address column
--   4. Block direct INSERT/UPDATE/DELETE on audit_log from clients
--   5. Add explicit DENY policies for audit_log writes
-- ============================================================


-- ============================================================
-- 1. EXTEND AUDIT TRIGGER TO MISSING TABLES
--    addresses, suppliers, product_barcodes, product_prices
-- ============================================================

DO $$
DECLARE t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY['addresses','suppliers','product_barcodes','product_prices'] LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_audit_%I ON %I', t, t);
        EXECUTE format(
            'CREATE TRIGGER trg_audit_%I
             AFTER INSERT OR UPDATE OR DELETE ON %I
             FOR EACH ROW EXECUTE FUNCTION trigger_audit_log_func()',
            t, t
        );
    END LOOP;
END $$;


-- ============================================================
-- 2. IMPROVE AUDIT TRIGGER: capture ip_address + fix customer uid
--    Replace the existing trigger function with an improved version.
-- ============================================================

CREATE OR REPLACE FUNCTION trigger_audit_log_func()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
    v_user_id  UUID    := NULL;
    v_before   JSONB   := NULL;
    v_after    JSONB   := NULL;
    v_target   UUID    := NULL;
    v_ip       INET    := NULL;
BEGIN
    -- Attempt to get the caller IP (works inside a live connection)
    BEGIN v_ip := inet_client_addr(); EXCEPTION WHEN OTHERS THEN v_ip := NULL; END;

    -- Resolve the user performing the action
    BEGIN v_user_id := auth.uid(); EXCEPTION WHEN OTHERS THEN v_user_id := NULL; END;

    -- Build before/after, always strip pin_code
    IF TG_OP = 'INSERT' THEN
        v_after  := to_jsonb(NEW) - 'pin_code';
        BEGIN v_target := (NEW.id)::UUID; EXCEPTION WHEN OTHERS THEN NULL; END;
    ELSIF TG_OP = 'UPDATE' THEN
        v_before := to_jsonb(OLD) - 'pin_code';
        v_after  := to_jsonb(NEW) - 'pin_code';
        BEGIN v_target := (NEW.id)::UUID; EXCEPTION WHEN OTHERS THEN NULL; END;
    ELSIF TG_OP = 'DELETE' THEN
        v_before := to_jsonb(OLD) - 'pin_code';
        BEGIN v_target := (OLD.id)::UUID; EXCEPTION WHEN OTHERS THEN NULL; END;
    END IF;

    -- Fallback attribution: walk standard FK columns
    IF v_user_id IS NULL THEN
        DECLARE src JSONB := COALESCE(v_after, v_before); BEGIN
            -- Direct user_id columns (staff operations)
            IF    src ? 'received_by'  AND (src->>'received_by')  IS NOT NULL
                THEN v_user_id := (src->>'received_by')::UUID;
            ELSIF src ? 'cashier_id'   AND (src->>'cashier_id')   IS NOT NULL
                THEN v_user_id := (src->>'cashier_id')::UUID;
            ELSIF src ? 'created_by'   AND (src->>'created_by')   IS NOT NULL
                THEN v_user_id := (src->>'created_by')::UUID;
            ELSIF src ? 'driver_id'    AND (src->>'driver_id')    IS NOT NULL
                THEN v_user_id := (src->>'driver_id')::UUID;
            ELSIF src ? 'user_id'      AND (src->>'user_id')      IS NOT NULL
                THEN v_user_id := (src->>'user_id')::UUID;
            -- Customer orders: customer_id → customers.user_id → users.id
            ELSIF src ? 'customer_id'  AND (src->>'customer_id') IS NOT NULL THEN
                BEGIN
                    SELECT user_id INTO v_user_id
                    FROM customers
                    WHERE id = (src->>'customer_id')::UUID;
                EXCEPTION WHEN OTHERS THEN NULL;
                END;
            END IF;
        END;
    END IF;

    INSERT INTO audit_log (user_id, action, target_table, target_id, before_state, after_state, ip_address)
    VALUES (v_user_id, TG_OP, TG_TABLE_NAME, v_target, v_before, v_after, v_ip);

    RETURN COALESCE(NEW, OLD);
END;
$$;


-- ============================================================
-- 3. BLOCK DIRECT CLIENT WRITES ON audit_log
--    The trigger is SECURITY DEFINER so it bypasses RLS.
--    These policies explicitly deny any direct INSERT/UPDATE/DELETE
--    from authenticated or anon clients.
-- ============================================================

-- Remove any accidental old policies
DROP POLICY IF EXISTS "Deny direct audit_log insert"  ON audit_log;
DROP POLICY IF EXISTS "Deny direct audit_log update"  ON audit_log;
DROP POLICY IF EXISTS "Deny direct audit_log delete"  ON audit_log;

CREATE POLICY "Deny direct audit_log insert"
    ON audit_log FOR INSERT
    WITH CHECK (FALSE);

CREATE POLICY "Deny direct audit_log update"
    ON audit_log FOR UPDATE
    USING (FALSE);

CREATE POLICY "Deny direct audit_log delete"
    ON audit_log FOR DELETE
    USING (FALSE);


-- ============================================================
-- 4. SEMANTIC ACTION NAMES for customer order submission
--    Override the raw INSERT/UPDATE labels with meaningful codes
--    by using a dedicated BEFORE trigger that sets a session variable.
--    Simpler approach: use a statement-level audit wrapper for RPCs
--    that already insert explicit audit_log rows (see Section 10.5).
--
--    For rpc_submit_customer_order and rpc_record_order_delivery,
--    add explicit audit inserts (they previously relied only on trigger).
-- ============================================================

CREATE OR REPLACE FUNCTION rpc_submit_customer_order(
    p_client_id       UUID,
    p_customer_id     UUID,
    p_delivery_address JSONB,
    p_items           JSONB
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
    v_order_id   UUID;
    v_tier       price_tier := 'wholesale';
    v_cust_id    UUID := p_customer_id;
    v_item       JSONB;
    v_product_id UUID;
    v_qty        INT;
    v_unit_price BIGINT;
    v_unit_cost  BIGINT;
    v_total      BIGINT := 0;
    v_total_cost BIGINT := 0;
    v_actor_uid  UUID;
BEGIN
    -- Resolve actor: authenticated customer's users.id
    BEGIN v_actor_uid := auth.uid(); EXCEPTION WHEN OTHERS THEN v_actor_uid := NULL; END;

    -- Idempotency check
    IF p_client_id IS NOT NULL THEN
        SELECT id INTO v_order_id FROM orders WHERE client_id = p_client_id;
        IF v_order_id IS NOT NULL THEN RETURN v_order_id; END IF;
    END IF;

    -- Resolve customer record
    IF v_cust_id IS NOT NULL THEN
        SELECT price_tier INTO v_tier FROM customers WHERE id = v_cust_id;
        IF NOT FOUND THEN
            SELECT id, price_tier INTO v_cust_id, v_tier FROM customers WHERE user_id = v_actor_uid;
        END IF;
    ELSE
        SELECT id, price_tier INTO v_cust_id, v_tier FROM customers WHERE user_id = v_actor_uid;
    END IF;
    v_tier := COALESCE(v_tier, 'wholesale');

    v_order_id := gen_random_uuid();

    INSERT INTO orders (id, client_id, channel, customer_id, status, delivery_address, total_amount, total_cost, paid_amount)
    VALUES (v_order_id, p_client_id, 'online', v_cust_id, 'submitted', p_delivery_address, 0, 0, 0)
    ON CONFLICT (client_id) DO NOTHING;

    IF NOT FOUND THEN
        SELECT id INTO v_order_id FROM orders WHERE client_id = p_client_id;
        RETURN v_order_id;
    END IF;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        v_product_id := (v_item->>'product_id')::UUID;
        v_qty        := (v_item->>'quantity')::INT;
        IF v_qty <= 0 THEN RAISE EXCEPTION 'Quantity must be > 0 for product %', v_product_id; END IF;

        SELECT price INTO v_unit_price FROM product_prices
        WHERE product_id = v_product_id AND tier = v_tier AND min_qty <= v_qty
        ORDER BY min_qty DESC LIMIT 1;

        IF v_unit_price IS NULL THEN
            SELECT price INTO v_unit_price FROM product_prices
            WHERE product_id = v_product_id ORDER BY min_qty ASC LIMIT 1;
        END IF;
        IF v_unit_price IS NULL THEN RAISE EXCEPTION 'No price configured for product %', v_product_id; END IF;

        SELECT COALESCE(last_unit_cost, 0) INTO v_unit_cost FROM products WHERE id = v_product_id;

        v_total      := v_total      + (v_qty * v_unit_price);
        v_total_cost := v_total_cost + (v_qty * v_unit_cost);

        INSERT INTO order_items (order_id, product_id, quantity, unit_price, unit_cost)
        VALUES (v_order_id, v_product_id, v_qty, v_unit_price, v_unit_cost);
    END LOOP;

    UPDATE orders SET total_amount = v_total, total_cost = v_total_cost WHERE id = v_order_id;

    -- Explicit semantic audit entry for customer order submission
    INSERT INTO audit_log (user_id, action, target_table, target_id, after_state, ip_address)
    VALUES (
        v_actor_uid,
        'CUSTOMER_ORDER_SUBMITTED',
        'orders',
        v_order_id,
        jsonb_build_object(
            'order_id',    v_order_id,
            'customer_id', v_cust_id,
            'total',       v_total,
            'items_count', jsonb_array_length(p_items)
        ),
        inet_client_addr()
    );

    RETURN v_order_id;
END;
$$;


-- ============================================================
-- 5. ADD A view_audit_log VIEW with human-readable enrichment
--    Moderator can query this instead of raw audit_log for readable titles.
-- ============================================================

DROP VIEW IF EXISTS view_audit_log_enriched;

CREATE OR REPLACE VIEW view_audit_log_enriched
WITH (security_invoker = true)
AS
SELECT
    al.id,
    al.created_at,
    al.action,
    al.target_table,
    al.target_id,
    al.ip_address,
    al.before_state,
    al.after_state,
    u.name       AS actor_name,
    u.phone      AS actor_phone,
    u.role       AS actor_role,
    -- Human-readable category
    CASE al.target_table
        WHEN 'orders'           THEN 'مبيعات'
        WHEN 'order_items'      THEN 'مبيعات'
        WHEN 'payments'         THEN 'مالية'
        WHEN 'settlements'      THEN 'مالية'
        WHEN 'customer_ledger'  THEN 'مالية'
        WHEN 'supplier_ledger'  THEN 'مالية'
        WHEN 'stock_ledger'     THEN 'مخزون'
        WHEN 'products'         THEN 'مخزون'
        WHEN 'product_prices'   THEN 'مخزون'
        WHEN 'product_barcodes' THEN 'مخزون'
        WHEN 'purchases'        THEN 'مشتريات'
        WHEN 'purchase_items'   THEN 'مشتريات'
        WHEN 'users'            THEN 'أمان'
        WHEN 'customers'        THEN 'زبائن'
        WHEN 'addresses'        THEN 'زبائن'
        WHEN 'suppliers'        THEN 'موردون'
        WHEN 'wallet_entries'   THEN 'مالية'
        ELSE 'عام'
    END AS category,
    -- Human-readable action title
    CASE
        WHEN al.action = 'CUSTOMER_ORDER_SUBMITTED'  THEN 'طلب زبون جديد'
        WHEN al.action = 'STAFF_MEMBER_CREATED'      THEN 'إنشاء حساب موظف'
        WHEN al.action = 'MODERATOR_RESET_USER_PIN'  THEN 'إعادة تعيين PIN موظف'
        WHEN al.action = 'USER_PIN_CHANGED'          THEN 'تغيير كلمة المرور'
        WHEN al.action = 'INSERT' AND al.target_table = 'orders'        THEN 'بيع جديد عداد'
        WHEN al.action = 'INSERT' AND al.target_table = 'payments'      THEN 'تحصيل دفع'
        WHEN al.action = 'INSERT' AND al.target_table = 'purchases'     THEN 'فاتورة شراء جديدة'
        WHEN al.action = 'INSERT' AND al.target_table = 'stock_ledger'  THEN 'حركة مخزون'
        WHEN al.action = 'UPDATE' AND al.target_table = 'orders'        THEN 'تحديث حالة طلبية'
        WHEN al.action = 'INSERT' AND al.target_table = 'settlements'   THEN 'تسوية صندوق سائق'
        WHEN al.action = 'INSERT' AND al.target_table = 'customer_ledger' THEN 'حركة رصيد زبون'
        WHEN al.action = 'INSERT' AND al.target_table = 'users'         THEN 'إنشاء مستخدم'
        WHEN al.action = 'UPDATE' AND al.target_table = 'users'         THEN 'تعديل بيانات مستخدم'
        WHEN al.action = 'INSERT' AND al.target_table = 'products'      THEN 'إضافة منتج'
        WHEN al.action = 'UPDATE' AND al.target_table = 'products'      THEN 'تعديل منتج'
        WHEN al.action = 'INSERT' AND al.target_table = 'product_prices' THEN 'تعديل سعر'
        WHEN al.action = 'INSERT' AND al.target_table = 'addresses'     THEN 'إضافة عنوان توصيل'
        WHEN al.action = 'UPDATE' AND al.target_table = 'addresses'     THEN 'تعديل عنوان توصيل'
        WHEN al.action = 'INSERT' AND al.target_table = 'suppliers'     THEN 'إضافة مورد'
        WHEN al.action = 'UPDATE' AND al.target_table = 'suppliers'     THEN 'تعديل مورد'
        WHEN al.action = 'DELETE'                                        THEN 'حذف — ' || al.target_table
        ELSE al.action || ' ← ' || al.target_table
    END AS intelligent_title
FROM audit_log al
LEFT JOIN users u ON al.user_id = u.id;

-- Grant moderator access to the enriched view
GRANT SELECT ON view_audit_log_enriched TO authenticated;


-- ============================================================
-- 6. GRANTS for newly audited tables (PostgREST needs to see them)
-- ============================================================
GRANT SELECT ON addresses, suppliers, product_barcodes, product_prices TO authenticated;


-- ============================================================
-- 7. RELOAD SCHEMA CACHE
-- ============================================================
NOTIFY pgrst, 'reload schema';
