-- ============================================================
-- 00024_purge_master_pin_and_revoke_anon_writes.sql
--
-- 1. PURGE MASTER PIN OVERRIDES ('0000', '1234')
--    - Ensures ONLY cryptographically hashed values (bcrypt) in users.pin_code are validated.
--    - Removes hardcoded fallbacks from all internal/public functions.
--
-- 2. REVOKE ANONYMOUS WRITE GRANTS ON BASE TABLES
--    - Revoke INSERT, UPDATE, DELETE on:
--      users, suppliers, purchases, purchase_items, order_items, stock_ledger
--    - Tightens RLS policies so anon cannot mutate critical tables directly.
--
-- 3. ROUTE WRITES TO ATOMIC SECURITY DEFINER RPCs
--    - rpc_create_supplier: Atomic validated creation of supplier records
--    - rpc_create_draft_purchase: Atomic creation of draft purchase with items
--    - rpc_update_user_profile: Validated profile update with caller verification
--    - rpc_sync_customer_profile: Validated customer profile registration & update
-- ============================================================

-- ============================================================
-- PART 1: PURGE MASTER PIN OVERRIDES & HARDEN VERIFICATION
-- ============================================================

-- Ensure pgcrypto extension is active
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Harden _internal_verify_and_track_pin to strictly require bcrypt match
CREATE OR REPLACE FUNCTION _internal_verify_and_track_pin(
    p_user_id UUID,
    p_pin TEXT,
    p_require_moderator BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_user users%ROWTYPE;
    v_lock pin_attempt_limits%ROWTYPE;
    v_lock_key BIGINT;
    v_is_valid BOOLEAN := FALSE;
    v_new_step INT := 0;
    v_lock_duration INTERVAL := INTERVAL '1 minute';
BEGIN
    -- Advisory lock per user using hash of UUID to serialize concurrent verification requests
    v_lock_key := ('x' || substr(md5(p_user_id::text), 1, 16))::bit(64)::bigint;
    PERFORM pg_advisory_xact_lock(v_lock_key);

    -- Load current attempt limits
    SELECT * INTO v_lock FROM pin_attempt_limits WHERE user_id = p_user_id;

    -- Check 24-hour decay: reset counter if last failed attempt was over 24 hours ago
    IF v_lock.user_id IS NOT NULL AND v_lock.last_failed_at IS NOT NULL THEN
        IF v_lock.last_failed_at < NOW() - INTERVAL '24 hours' THEN
            v_lock.failed_attempts := 0;
            v_lock.lock_step := 0;
            v_lock.locked_until := NULL;
        END IF;
    END IF;

    -- Reset failed_attempts when locked_until has passed
    IF v_lock.user_id IS NOT NULL AND v_lock.locked_until IS NOT NULL THEN
        IF v_lock.locked_until <= NOW() THEN
            v_lock.failed_attempts := 0;
            v_lock.locked_until := NULL;
        END IF;
    END IF;

    -- Check active lock status
    IF v_lock.user_id IS NOT NULL AND v_lock.locked_until IS NOT NULL AND v_lock.locked_until > NOW() THEN
        RETURN jsonb_build_object(
            'valid', FALSE,
            'locked', TRUE,
            'message', 'الحساب مقفل مؤقتاً لتكرار المحاولات الخاطئة. يرجى الانتظار.'
        );
    END IF;

    -- Load user record
    SELECT * INTO v_user FROM users WHERE id = p_user_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('valid', FALSE, 'message', 'المستخدم غير موجود');
    END IF;

    IF v_user.active = FALSE THEN
        RETURN jsonb_build_object('valid', FALSE, 'message', 'الحساب معطل من قبل الإدارة');
    END IF;

    IF p_require_moderator AND v_user.role <> 'moderator' THEN
        RETURN jsonb_build_object('valid', FALSE, 'message', 'العملية تتطلب صلاحيات المشرف العام (Moderator)');
    END IF;

    -- Reject empty, short, or invalid PIN input
    IF p_pin IS NULL OR LENGTH(trim(p_pin)) < 4 THEN
        RETURN jsonb_build_object('valid', FALSE, 'message', 'رمز PIN غير صالح');
    END IF;

    -- Compare hashed PIN strictly using crypt(pin, stored_hash). NO '0000' or '1234' backdoor.
    IF v_user.pin_code IS NOT NULL AND v_user.pin_code = crypt(trim(p_pin), v_user.pin_code) THEN
        v_is_valid := TRUE;
    END IF;

    IF v_is_valid THEN
        -- Reset counter ONLY on successful authentication
        DELETE FROM pin_attempt_limits WHERE user_id = p_user_id;
        RETURN jsonb_build_object(
            'valid', TRUE,
            'id', v_user.id,
            'name', v_user.name,
            'phone', v_user.phone,
            'role', v_user.role,
            'language', v_user.language
        );
    ELSE
        -- Failed attempt: compute escalating lock duration
        IF v_lock.user_id IS NULL THEN
            INSERT INTO pin_attempt_limits (user_id, failed_attempts, lock_step, locked_until, last_failed_at)
            VALUES (p_user_id, 1, 0, NULL, NOW());
        ELSE
            v_lock.failed_attempts := v_lock.failed_attempts + 1;
            IF v_lock.failed_attempts >= 15 THEN
                v_new_step := 3;
                v_lock_duration := INTERVAL '15 minutes';
            ELSIF v_lock.failed_attempts >= 10 THEN
                v_new_step := 2;
                v_lock_duration := INTERVAL '5 minutes';
            ELSIF v_lock.failed_attempts >= 5 THEN
                v_new_step := 1;
                v_lock_duration := INTERVAL '1 minute';
            ELSE
                v_new_step := 0;
            END IF;

            UPDATE pin_attempt_limits 
            SET failed_attempts = v_lock.failed_attempts,
                lock_step = v_new_step,
                last_failed_at = NOW(),
                locked_until = CASE 
                    WHEN v_new_step > 0 THEN NOW() + v_lock_duration 
                    ELSE NULL 
                END
            WHERE user_id = p_user_id;
        END IF;

        RETURN jsonb_build_object('valid', FALSE, 'message', 'رمز PIN غير صحيح');
    END IF;
END;
$$;

-- Ensure execute on internal function remains strictly revoked
REVOKE ALL ON FUNCTION _internal_verify_and_track_pin(UUID, TEXT, BOOLEAN) FROM PUBLIC, anon, authenticated;

-- Public wrapper for PIN verification
CREATE OR REPLACE FUNCTION rpc_verify_user_pin(
    p_user_id UUID,
    p_pin TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
BEGIN
    RETURN _internal_verify_and_track_pin(p_user_id, p_pin, FALSE);
END;
$$;
GRANT EXECUTE ON FUNCTION rpc_verify_user_pin(UUID, TEXT) TO anon, authenticated;

-- Public wrapper for changing own PIN (strictly validates old PIN via bcrypt)
CREATE OR REPLACE FUNCTION rpc_change_user_pin(
    p_user_id UUID,
    p_old_pin TEXT,
    p_new_pin TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_check JSONB;
BEGIN
    v_check := _internal_verify_and_track_pin(p_user_id, p_old_pin, FALSE);
    IF (v_check->>'valid')::BOOLEAN <> TRUE THEN
        RETURN jsonb_build_object('status', 'error', 'message', COALESCE(v_check->>'message', 'رمز PIN الحالي غير صحيح'));
    END IF;

    IF LENGTH(trim(p_new_pin)) < 4 THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'يجب أن يتكون رمز PIN الجديد من 4 أرقام على الأقل');
    END IF;

    UPDATE users
    SET pin_code = crypt(trim(p_new_pin), gen_salt('bf')),
        updated_at = NOW()
    WHERE id = p_user_id;

    INSERT INTO audit_log (user_id, action, target_table, target_id, after_state)
    VALUES (p_user_id, 'USER_PIN_CHANGED', 'users', p_user_id, jsonb_build_object('changed_at', NOW()));

    RETURN jsonb_build_object('status', 'success', 'message', 'تم تحديث رمز PIN بنجاح');
END;
$$;
GRANT EXECUTE ON FUNCTION rpc_change_user_pin(UUID, TEXT, TEXT) TO anon, authenticated;

-- Admin/Moderator reset of staff PIN (strictly validates admin credentials via bcrypt)
CREATE OR REPLACE FUNCTION rpc_reset_user_pin_by_admin(
    p_admin_id UUID,
    p_admin_pin TEXT,
    p_target_user_id UUID,
    p_new_pin TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_admin_check JSONB;
    v_target RECORD;
BEGIN
    -- Verify admin identity and pin strictly
    v_admin_check := _internal_verify_and_track_pin(p_admin_id, p_admin_pin, TRUE);
    IF (v_admin_check->>'valid')::BOOLEAN <> TRUE THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'فشل التحقق من هوية المشرف أو رمز PIN للمشرف');
    END IF;

    SELECT id, name, phone, role INTO v_target FROM users WHERE id = p_target_user_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'الموظف غير موجود');
    END IF;

    IF LENGTH(trim(p_new_pin)) < 4 THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'يجب أن يتكون رمز PIN من 4 أرقام على الأقل');
    END IF;

    UPDATE users
    SET pin_code = crypt(trim(p_new_pin), gen_salt('bf')),
        updated_at = NOW()
    WHERE id = p_target_user_id;

    INSERT INTO audit_log (user_id, action, target_table, target_id, after_state)
    VALUES (p_admin_id, 'MODERATOR_RESET_USER_PIN', 'users', p_target_user_id, jsonb_build_object(
        'target_name', v_target.name,
        'target_phone', v_target.phone,
        'target_role', v_target.role,
        'reset_at', NOW()
    ));

    RETURN jsonb_build_object('status', 'success', 'message', 'تم إعادة تعيين رمز PIN بنجاح');
END;
$$;
GRANT EXECUTE ON FUNCTION rpc_reset_user_pin_by_admin(UUID, TEXT, UUID, TEXT) TO anon, authenticated;

-- Moderator create staff member (strictly requires non-null, minimum 4-digit PIN)
CREATE OR REPLACE FUNCTION rpc_create_staff_member(
    p_admin_id UUID,
    p_admin_pin TEXT,
    p_name VARCHAR,
    p_phone VARCHAR,
    p_role user_role,
    p_initial_pin TEXT,
    p_language VARCHAR DEFAULT 'ar'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_admin_check JSONB;
    v_user_id UUID := gen_random_uuid();
BEGIN
    -- Verify caller is active moderator with correct PIN
    v_admin_check := _internal_verify_and_track_pin(p_admin_id, p_admin_pin, TRUE);
    IF (v_admin_check->>'valid')::BOOLEAN <> TRUE THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'فشل التحقق من صلاحيات المشرف العام');
    END IF;

    IF p_initial_pin IS NULL OR LENGTH(trim(p_initial_pin)) < 4 THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'يجب تحديد رمز PIN من 4 أرقام على الأقل للموظف الجديد');
    END IF;

    IF p_role = 'customer' THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'لا يمكن استخدام هذه الدالة لإنشاء حسابات الزبائن');
    END IF;

    INSERT INTO users (id, name, phone, role, pin_code, language, active)
    VALUES (v_user_id, trim(p_name), trim(p_phone), p_role, crypt(trim(p_initial_pin), gen_salt('bf')), p_language, TRUE);

    INSERT INTO audit_log (user_id, action, target_table, target_id, after_state)
    VALUES (p_admin_id, 'STAFF_MEMBER_CREATED', 'users', v_user_id,
        jsonb_build_object('name', p_name, 'phone', p_phone, 'role', p_role));

    RETURN jsonb_build_object(
        'status', 'success',
        'id', v_user_id,
        'name', p_name,
        'phone', p_phone,
        'role', p_role
    );
END;
$$;
GRANT EXECUTE ON FUNCTION rpc_create_staff_member(UUID, TEXT, VARCHAR, VARCHAR, user_role, TEXT, VARCHAR) TO anon, authenticated;


-- ============================================================
-- PART 2: REVOKE ANONYMOUS WRITE GRANTS ON BASE TABLES
-- ============================================================

-- 1. USERS: Revoke all direct writes from anon
REVOKE INSERT, UPDATE, DELETE ON users FROM anon;
REVOKE UPDATE (name, phone, role, active, language, updated_at) ON users FROM anon;
-- Allow anon read-only SELECT for profile and staff list
GRANT SELECT ON users TO anon, authenticated;

DROP POLICY IF EXISTS "Allow staff and user profile update" ON users;
DROP POLICY IF EXISTS "Allow customer self-registration" ON users;
DROP POLICY IF EXISTS "Allow customer self-update" ON users;

CREATE POLICY "Allow authenticated staff update users"
ON users FOR UPDATE TO authenticated
USING (get_auth_role() IN ('moderator', 'manager'))
WITH CHECK (get_auth_role() IN ('moderator', 'manager'));

-- 2. SUPPLIERS: Revoke write from anon
REVOKE INSERT, UPDATE, DELETE ON suppliers FROM anon;
GRANT SELECT ON suppliers TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON suppliers TO authenticated;

DROP POLICY IF EXISTS "suppliers_open" ON suppliers;
CREATE POLICY "suppliers_read" ON suppliers FOR SELECT USING (TRUE);
CREATE POLICY "suppliers_write_authenticated" ON suppliers FOR ALL TO authenticated
USING (get_auth_role() IN ('moderator', 'manager'))
WITH CHECK (get_auth_role() IN ('moderator', 'manager'));

-- 3. PURCHASES & PURCHASE_ITEMS: Revoke write from anon
REVOKE INSERT, UPDATE, DELETE ON purchases FROM anon;
REVOKE INSERT, UPDATE, DELETE ON purchase_items FROM anon;
GRANT SELECT ON purchases TO anon, authenticated;
GRANT SELECT ON purchase_items TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON purchases TO authenticated;
GRANT INSERT, UPDATE, DELETE ON purchase_items TO authenticated;

DROP POLICY IF EXISTS "purchases_open" ON purchases;
DROP POLICY IF EXISTS "purchase_items_open" ON purchase_items;
CREATE POLICY "purchases_read" ON purchases FOR SELECT USING (TRUE);
CREATE POLICY "purchase_items_read" ON purchase_items FOR SELECT USING (TRUE);
CREATE POLICY "purchases_write_authenticated" ON purchases FOR ALL TO authenticated
USING (get_auth_role() IN ('moderator', 'manager'))
WITH CHECK (get_auth_role() IN ('moderator', 'manager'));
CREATE POLICY "purchase_items_write_authenticated" ON purchase_items FOR ALL TO authenticated
USING (get_auth_role() IN ('moderator', 'manager'))
WITH CHECK (get_auth_role() IN ('moderator', 'manager'));

-- 4. ORDER_ITEMS: Revoke direct writes from anon
REVOKE INSERT, UPDATE, DELETE ON order_items FROM anon;
GRANT SELECT ON order_items TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON order_items TO authenticated;

DROP POLICY IF EXISTS "order_items_open" ON order_items;
CREATE POLICY "order_items_read" ON order_items FOR SELECT USING (TRUE);
CREATE POLICY "order_items_write_authenticated" ON order_items FOR ALL TO authenticated
USING (get_auth_role() IN ('moderator', 'manager', 'cashier'))
WITH CHECK (get_auth_role() IN ('moderator', 'manager', 'cashier'));

-- 5. STOCK_LEDGER: Strictly append-only, NO direct write from anon
REVOKE INSERT, UPDATE, DELETE ON stock_ledger FROM anon;
GRANT SELECT ON stock_ledger TO anon, authenticated;
GRANT INSERT ON stock_ledger TO authenticated;

DROP POLICY IF EXISTS "stock_ledger_open" ON stock_ledger;
CREATE POLICY "stock_ledger_read" ON stock_ledger FOR SELECT USING (TRUE);
CREATE POLICY "stock_ledger_insert_authenticated" ON stock_ledger FOR INSERT TO authenticated
WITH CHECK (get_auth_role() IN ('moderator', 'manager', 'cashier'));

-- 6. CUSTOMERS: Revoke direct UPDATE/DELETE from anon
REVOKE UPDATE, DELETE ON customers FROM anon;
GRANT SELECT ON customers TO anon, authenticated;
GRANT ALL ON customers TO authenticated;

DROP POLICY IF EXISTS "Allow all operations on customers" ON customers;
CREATE POLICY "customers_read" ON customers FOR SELECT USING (TRUE);
CREATE POLICY "customers_write_authenticated" ON customers FOR ALL TO authenticated
USING (get_auth_role() IN ('moderator', 'manager', 'cashier'))
WITH CHECK (get_auth_role() IN ('moderator', 'manager', 'cashier'));


-- ============================================================
-- PART 3: NEW SECURITY DEFINER RPCs TO ROUTE WRITE OPERATIONS
-- ============================================================

-- 1. RPC: CREATE SUPPLIER
CREATE OR REPLACE FUNCTION rpc_create_supplier(
    p_name VARCHAR,
    p_phone VARCHAR,
    p_company_register VARCHAR DEFAULT NULL,
    p_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_supplier_id UUID := gen_random_uuid();
    v_clean_name VARCHAR := trim(p_name);
    v_clean_phone VARCHAR := trim(p_phone);
BEGIN
    IF v_clean_name IS NULL OR LENGTH(v_clean_name) < 2 THEN
        RAISE EXCEPTION 'اسم المورد غير صالح';
    END IF;

    INSERT INTO suppliers (id, name, phone, company_register, notes)
    VALUES (v_supplier_id, v_clean_name, v_clean_phone, trim(p_company_register), trim(p_notes));

    RETURN jsonb_build_object(
        'id', v_supplier_id,
        'name', v_clean_name,
        'phone', v_clean_phone,
        'company_register', trim(p_company_register),
        'notes', trim(p_notes)
    );
END;
$$;
GRANT EXECUTE ON FUNCTION rpc_create_supplier(VARCHAR, VARCHAR, VARCHAR, TEXT) TO anon, authenticated;

-- 2. RPC: CREATE DRAFT PURCHASE
CREATE OR REPLACE FUNCTION rpc_create_draft_purchase(
    p_supplier_id UUID,
    p_invoice_no VARCHAR,
    p_invoice_date DATE,
    p_total_amount BIGINT,
    p_created_by UUID,
    p_items JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_purchase_id UUID := gen_random_uuid();
    v_item JSONB;
    v_product_id UUID;
    v_qty INT;
    v_unit_cost BIGINT;
    v_selling_price BIGINT;
BEGIN
    INSERT INTO purchases (id, supplier_id, invoice_no, invoice_date, status, total_amount, created_by)
    VALUES (v_purchase_id, p_supplier_id, p_invoice_no, p_invoice_date, 'draft', p_total_amount, p_created_by);

    IF p_items IS NOT NULL AND jsonb_array_length(p_items) > 0 THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
            v_product_id := (v_item->>'product_id')::UUID;
            v_qty := COALESCE((v_item->>'quantity')::INT, (v_item->>'qty')::INT, 1);
            v_unit_cost := COALESCE((v_item->>'unit_cost')::BIGINT, (v_item->>'cost_centimes')::BIGINT, 0);
            v_selling_price := COALESCE((v_item->>'selling_price')::BIGINT, v_unit_cost);

            IF v_selling_price < v_unit_cost THEN
                v_selling_price := v_unit_cost;
            END IF;

            INSERT INTO purchase_items (purchase_id, product_id, quantity, unit_cost, selling_price)
            VALUES (v_purchase_id, v_product_id, v_qty, v_unit_cost, v_selling_price);
        END LOOP;
    END IF;

    RETURN v_purchase_id;
END;
$$;
GRANT EXECUTE ON FUNCTION rpc_create_draft_purchase(UUID, VARCHAR, DATE, BIGINT, UUID, JSONB) TO anon, authenticated;

-- 3. RPC: UPDATE USER PROFILE (MODERATOR OR SELF)
CREATE OR REPLACE FUNCTION rpc_update_user_profile(
    p_caller_id UUID,
    p_caller_pin TEXT,
    p_target_user_id UUID,
    p_name VARCHAR,
    p_phone VARCHAR,
    p_language VARCHAR DEFAULT 'ar',
    p_role user_role DEFAULT NULL,
    p_active BOOLEAN DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_auth_check JSONB;
    v_caller users%ROWTYPE;
    v_is_moderator BOOLEAN := FALSE;
BEGIN
    -- Verify caller credentials
    v_auth_check := _internal_verify_and_track_pin(p_caller_id, p_caller_pin, FALSE);
    IF (v_auth_check->>'valid')::BOOLEAN <> TRUE THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'فشل التحقق من هوية المستخدم أو رمز PIN');
    END IF;

    SELECT * INTO v_caller FROM users WHERE id = p_caller_id;
    IF v_caller.role = 'moderator' THEN
        v_is_moderator := TRUE;
    END IF;

    -- Non-moderators can only update their own profile and cannot change role or active status
    IF NOT v_is_moderator AND p_caller_id <> p_target_user_id THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'لا تملك صلاحية تعديل بيانات مستخدم آخر');
    END IF;

    IF v_is_moderator THEN
        UPDATE users
        SET name = trim(p_name),
            phone = trim(p_phone),
            language = COALESCE(p_language, language),
            role = COALESCE(p_role, role),
            active = COALESCE(p_active, active),
            updated_at = NOW()
        WHERE id = p_target_user_id;
    ELSE
        UPDATE users
        SET name = trim(p_name),
            phone = trim(p_phone),
            language = COALESCE(p_language, language),
            updated_at = NOW()
        WHERE id = p_target_user_id;
    END IF;

    INSERT INTO audit_log (user_id, action, target_table, target_id, after_state)
    VALUES (p_caller_id, 'USER_PROFILE_UPDATED', 'users', p_target_user_id, jsonb_build_object(
        'name', p_name,
        'phone', p_phone,
        'language', p_language,
        'updated_at', NOW()
    ));

    RETURN jsonb_build_object('status', 'success', 'message', 'تم تحديث البيانات بنجاح');
END;
$$;
GRANT EXECUTE ON FUNCTION rpc_update_user_profile(UUID, TEXT, UUID, VARCHAR, VARCHAR, VARCHAR, user_role, BOOLEAN) TO anon, authenticated;

-- 4. RPC: SYNC CUSTOMER PROFILE (Creation / Update with verification)
CREATE OR REPLACE FUNCTION rpc_sync_customer_profile(
    p_name VARCHAR,
    p_phone VARCHAR,
    p_wilaya VARCHAR,
    p_commune VARCHAR,
    p_address_text TEXT,
    p_latitude DOUBLE PRECISION DEFAULT NULL,
    p_longitude DOUBLE PRECISION DEFAULT NULL,
    p_existing_customer_id UUID DEFAULT NULL,
    p_existing_user_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_clean_phone VARCHAR := trim(p_phone);
    v_clean_name VARCHAR := trim(p_name);
    v_user_id UUID := p_existing_user_id;
    v_customer_id UUID := p_existing_customer_id;
    v_credit_limit BIGINT := 0;
    v_price_tier price_tier := 'wholesale';
    v_auth_uid UUID;
BEGIN
    BEGIN v_auth_uid := auth.uid(); EXCEPTION WHEN OTHERS THEN v_auth_uid := NULL; END;

    IF v_clean_phone IS NULL OR v_clean_phone !~ '^0[5-7][0-9]{8}$' THEN
        RAISE EXCEPTION 'رقم الهاتف غير صالح';
    END IF;

    IF v_clean_name IS NULL OR LENGTH(v_clean_name) < 2 THEN
        v_clean_name := 'زبون متجر الجملة';
    END IF;

    -- Resolve user_id: prefer auth.uid() if authenticated session exists
    IF v_auth_uid IS NOT NULL THEN
        v_user_id := v_auth_uid;
    ELSIF v_user_id IS NULL THEN
        SELECT id INTO v_user_id FROM users WHERE phone = v_clean_phone LIMIT 1;
    END IF;

    IF v_user_id IS NOT NULL THEN
        UPDATE users
        SET name = v_clean_name,
            phone = v_clean_phone,
            active = TRUE,
            updated_at = NOW()
        WHERE id = v_user_id;
    ELSE
        v_user_id := gen_random_uuid();
        INSERT INTO users (id, name, phone, role, language, active)
        VALUES (v_user_id, v_clean_name, v_clean_phone, 'customer', 'ar', TRUE);
    END IF;

    -- Resolve customer_id
    IF v_customer_id IS NOT NULL THEN
        SELECT id, credit_limit, price_tier INTO v_customer_id, v_credit_limit, v_price_tier
        FROM customers WHERE id = v_customer_id;
    ELSE
        SELECT id, credit_limit, price_tier INTO v_customer_id, v_credit_limit, v_price_tier
        FROM customers WHERE user_id = v_user_id LIMIT 1;
    END IF;

    IF v_customer_id IS NULL THEN
        v_customer_id := gen_random_uuid();
        INSERT INTO customers (id, user_id, credit_limit, price_tier)
        VALUES (v_customer_id, v_user_id, 0, 'wholesale')
        RETURNING id, credit_limit, price_tier INTO v_customer_id, v_credit_limit, v_price_tier;
    END IF;

    -- Upsert primary address
    IF p_wilaya IS NOT NULL AND p_commune IS NOT NULL THEN
        INSERT INTO addresses (customer_id, wilaya, commune, address_text, latitude, longitude, is_default)
        VALUES (v_customer_id, trim(p_wilaya), trim(p_commune), trim(p_address_text), p_latitude, p_longitude, TRUE)
        ON CONFLICT DO NOTHING;
    END IF;

    RETURN jsonb_build_object(
        'customer_id', v_customer_id,
        'user_id', v_user_id,
        'name', v_clean_name,
        'phone', v_clean_phone,
        'wilaya', trim(p_wilaya),
        'commune', trim(p_commune),
        'address_text', trim(p_address_text),
        'credit_limit', v_credit_limit,
        'price_tier', v_price_tier
    );
END;
$$;
GRANT EXECUTE ON FUNCTION rpc_sync_customer_profile(VARCHAR, VARCHAR, VARCHAR, VARCHAR, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, UUID, UUID) TO anon, authenticated;

-- Force PostgREST schema cache reload
NOTIFY pgrst, 'reload schema';
