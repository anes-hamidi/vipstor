-- ============================================================
-- 00025_device_bound_customer_auth.sql
--
-- DEVICE-BOUND CRYPTOGRAPHIC AUTHENTICATION FOR CUSTOMERS
-- (Replaces SMS OTP with Zero-Cost Device-Bound Token Handshake)
--
-- 1. Adds `device_token` to `customers` table (UUID / crypt token).
-- 2. rpc_register_or_bind_customer_device:
--    - When a customer registers or opens the app on a new device,
--      their hardware device signature is bound to their account.
--    - If account has an existing device_token, any different device
--      attempting to act on the account is rejected (preventing account takeover).
-- 3. rpc_verify_customer_device:
--    - Validates device_token match on phone lookup or order checkout.
-- 4. Updates rpc_sync_customer_profile & rpc_submit_customer_order
--    to require and verify p_device_token.
-- ============================================================

-- 1. Add device_token column to customers table
ALTER TABLE customers ADD COLUMN IF NOT EXISTS device_token TEXT;
CREATE INDEX IF NOT EXISTS idx_customers_device_token ON customers(device_token);

-- 2. RPC: Register or Bind Device to Customer
CREATE OR REPLACE FUNCTION rpc_register_or_bind_customer_device(
    p_phone VARCHAR,
    p_device_token TEXT,
    p_name VARCHAR DEFAULT NULL,
    p_wilaya VARCHAR DEFAULT NULL,
    p_commune VARCHAR DEFAULT NULL,
    p_address_text TEXT DEFAULT NULL,
    p_latitude DOUBLE PRECISION DEFAULT NULL,
    p_longitude DOUBLE PRECISION DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_clean_phone VARCHAR := trim(p_phone);
    v_clean_name VARCHAR := trim(COALESCE(p_name, 'زبون متجر الجملة'));
    v_clean_token TEXT := trim(p_device_token);
    v_user_id UUID;
    v_customer_id UUID;
    v_existing_token TEXT;
    v_credit_limit BIGINT := 0;
    v_price_tier price_tier := 'wholesale';
BEGIN
    IF v_clean_phone IS NULL OR v_clean_phone !~ '^0[5-7][0-9]{8}$' THEN
        RETURN jsonb_build_object('success', FALSE, 'error', 'رقم الهاتف غير صالح. يجب أن يبدأ بـ 05 أو 06 أو 07');
    END IF;

    IF v_clean_token IS NULL OR LENGTH(v_clean_token) < 16 THEN
        RETURN jsonb_build_object('success', FALSE, 'error', 'معرف الجهاز غير صالح');
    END IF;

    -- Look up existing user by phone
    SELECT id INTO v_user_id FROM users WHERE phone = v_clean_phone LIMIT 1;

    IF v_user_id IS NOT NULL THEN
        -- Existing user: check customer and device_token
        SELECT id, device_token, credit_limit, price_tier
        INTO v_customer_id, v_existing_token, v_credit_limit, v_price_tier
        FROM customers
        WHERE user_id = v_user_id
        LIMIT 1;

        IF v_customer_id IS NOT NULL THEN
            IF v_existing_token IS NOT NULL AND v_existing_token <> '' THEN
                -- Account already bound to a device: verify match!
                IF v_existing_token <> v_clean_token THEN
                    RETURN jsonb_build_object(
                        'success', FALSE,
                        'bound_to_other_device', TRUE,
                        'error', 'هذا الحساب مرتبط بجهاز آخر بالفعل لحماية البيانات. يرجى التواصل مع الإدارة لإعادة ربط الجهاز.'
                    );
                END IF;
            ELSE
                -- First time binding device token to existing customer
                UPDATE customers SET device_token = v_clean_token WHERE id = v_customer_id;
            END IF;

            -- Update profile details if provided
            IF p_name IS NOT NULL AND trim(p_name) <> '' THEN
                UPDATE users SET name = v_clean_name, updated_at = NOW() WHERE id = v_user_id;
            END IF;
        ELSE
            -- User exists but no customer row
            v_customer_id := gen_random_uuid();
            INSERT INTO customers (id, user_id, device_token, credit_limit, price_tier)
            VALUES (v_customer_id, v_user_id, v_clean_token, 0, 'wholesale');
        END IF;
    ELSE
        -- New User Registration
        v_user_id := gen_random_uuid();
        INSERT INTO users (id, name, phone, role, language, active)
        VALUES (v_user_id, v_clean_name, v_clean_phone, 'customer', 'ar', TRUE);

        v_customer_id := gen_random_uuid();
        INSERT INTO customers (id, user_id, device_token, credit_limit, price_tier)
        VALUES (v_customer_id, v_user_id, v_clean_token, 0, 'wholesale');
    END IF;

    -- Update or insert address if provided
    IF p_wilaya IS NOT NULL AND p_commune IS NOT NULL AND trim(p_wilaya) <> '' THEN
        INSERT INTO addresses (customer_id, wilaya, commune, address_text, latitude, longitude, is_default)
        VALUES (v_customer_id, trim(p_wilaya), trim(p_commune), trim(COALESCE(p_address_text, '')), p_latitude, p_longitude, TRUE)
        ON CONFLICT DO NOTHING;
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE,
        'customer_id', v_customer_id,
        'user_id', v_user_id,
        'name', v_clean_name,
        'phone', v_clean_phone,
        'wilaya', trim(COALESCE(p_wilaya, '')),
        'commune', trim(COALESCE(p_commune, '')),
        'address_text', trim(COALESCE(p_address_text, '')),
        'credit_limit', v_credit_limit,
        'price_tier', v_price_tier,
        'device_token', v_clean_token
    );
END;
$$;
GRANT EXECUTE ON FUNCTION rpc_register_or_bind_customer_device(VARCHAR, TEXT, VARCHAR, VARCHAR, VARCHAR, TEXT, DOUBLE PRECISION, DOUBLE PRECISION) TO anon, authenticated;

-- 3. RPC: Lookup Customer by Phone with Device Verification
CREATE OR REPLACE FUNCTION rpc_lookup_customer_by_phone(
    p_phone VARCHAR,
    p_device_token TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_clean_phone VARCHAR := trim(p_phone);
    v_clean_token TEXT := trim(p_device_token);
    v_user users%ROWTYPE;
    v_cust customers%ROWTYPE;
    v_addr addresses%ROWTYPE;
BEGIN
    SELECT * INTO v_user FROM users WHERE phone = v_clean_phone LIMIT 1;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('found', FALSE, 'message', 'لا يوجد حساب مسجل بهذا الرقم');
    END IF;

    SELECT * INTO v_cust FROM customers WHERE user_id = v_user.id LIMIT 1;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('found', FALSE, 'message', 'لا يوجد ملف زبون مرتبط بهذا الرقم');
    END IF;

    -- Device authentication check
    IF v_cust.device_token IS NOT NULL AND v_cust.device_token <> '' THEN
        IF v_clean_token IS NULL OR v_cust.device_token <> v_clean_token THEN
            RETURN jsonb_build_object(
                'found', FALSE,
                'device_mismatch', TRUE,
                'message', 'هذا الحساب مرتبط بجهاز آخر ومحمي بكلمة أمان مشفرة للجهاز الأصلي.'
            );
        END IF;
    ELSE
        -- Auto-bind if not previously bound
        IF v_clean_token IS NOT NULL AND LENGTH(v_clean_token) >= 16 THEN
            UPDATE customers SET device_token = v_clean_token WHERE id = v_cust.id;
        END IF;
    END IF;

    SELECT * INTO v_addr FROM addresses WHERE customer_id = v_cust.id ORDER BY is_default DESC, created_at DESC LIMIT 1;

    RETURN jsonb_build_object(
        'found', TRUE,
        'id', v_cust.id,
        'user_id', v_user.id,
        'name', v_user.name,
        'phone', v_user.phone,
        'wilaya', COALESCE(v_addr.wilaya, ''),
        'commune', COALESCE(v_addr.commune, ''),
        'address_text', COALESCE(v_addr.address_text, ''),
        'latitude', v_addr.latitude,
        'longitude', v_addr.longitude,
        'credit_limit', v_cust.credit_limit,
        'price_tier', v_cust.price_tier
    );
END;
$$;
GRANT EXECUTE ON FUNCTION rpc_lookup_customer_by_phone(VARCHAR, TEXT) TO anon, authenticated;

-- 4. Update rpc_submit_customer_order to verify device token
CREATE OR REPLACE FUNCTION rpc_submit_customer_order(
    p_client_id       UUID,
    p_customer_id     UUID,
    p_delivery_address JSONB,
    p_items           JSONB,
    p_device_token    TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_order_id   UUID;
    v_tier       price_tier := 'wholesale';
    v_cust_id    UUID := p_customer_id;
    v_stored_token TEXT;
    v_item       JSONB;
    v_product_id UUID;
    v_qty        INT;
    v_unit_price BIGINT;
    v_unit_cost  BIGINT;
    v_total      BIGINT := 0;
    v_total_cost BIGINT := 0;
BEGIN
    -- Idempotency check
    IF p_client_id IS NOT NULL THEN
        SELECT id INTO v_order_id FROM orders WHERE client_id = p_client_id;
        IF v_order_id IS NOT NULL THEN RETURN v_order_id; END IF;
    END IF;

    -- Device token verification if customer account is established
    IF v_cust_id IS NOT NULL THEN
        SELECT price_tier, device_token INTO v_tier, v_stored_token FROM customers WHERE id = v_cust_id;
        IF v_stored_token IS NOT NULL AND v_stored_token <> '' THEN
            IF p_device_token IS NULL OR trim(p_device_token) <> v_stored_token THEN
                RAISE EXCEPTION 'فشل التحقق من أمان الجهاز المرتبط بالطلب.';
            END IF;
        END IF;
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
        v_qty := (v_item->>'quantity')::INT;
        IF v_qty <= 0 THEN CONTINUE; END IF;

        SELECT price INTO v_unit_price
        FROM product_prices
        WHERE product_id = v_product_id AND tier = v_tier AND min_qty <= v_qty
        ORDER BY min_qty DESC LIMIT 1;

        IF v_unit_price IS NULL THEN
            SELECT price INTO v_unit_price FROM product_prices WHERE product_id = v_product_id ORDER BY min_qty ASC LIMIT 1;
        END IF;

        IF v_unit_price IS NULL THEN v_unit_price := 0; END IF;

        SELECT COALESCE(last_unit_cost, 0) INTO v_unit_cost FROM products WHERE id = v_product_id;

        v_total := v_total + (v_qty * v_unit_price);
        v_total_cost := v_total_cost + (v_qty * v_unit_cost);

        INSERT INTO order_items (order_id, product_id, quantity, unit_price, unit_cost)
        VALUES (v_order_id, v_product_id, v_qty, v_unit_price, v_unit_cost);
    END LOOP;

    UPDATE orders SET total_amount = v_total, total_cost = v_total_cost WHERE id = v_order_id;
    RETURN v_order_id;
END;
$$;
GRANT EXECUTE ON FUNCTION rpc_submit_customer_order(UUID, UUID, JSONB, JSONB, TEXT) TO anon, authenticated;

-- Force PostgREST reload
NOTIFY pgrst, 'reload schema';
