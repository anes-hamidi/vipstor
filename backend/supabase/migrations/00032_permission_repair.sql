-- ============================================================
-- 00032_permission_repair.sql
--
-- PURPOSE
--   Repair the 42501 "permission denied for table users" failures
--   introduced by migration 00024, repair the broken audit trigger
--   introduced by migration 00027, and reconcile client grants/RLS
--   across the schema.
--
-- WHAT THIS MIGRATION DOES
--   1. Fixes trigger_audit_log_func():
--      - replaces the invalid composite-row `NEW ? 'column'` checks
--        with to_jsonb(NEW) lookups (fixes 42883 on every order,
--        wallet_entries, and settlements write);
--      - removes pin_code / device_token from audit payloads;
--      - redacts those keys from historical audit rows.
--   2. Adds rpc_save_user_profile(...) for staff self-service and
--      moderator profile editing. The caller proves identity with
--      their own PIN; the target's old PIN is never required.
--   3. Adds rpc_create_customer_by_staff(...) so cashiers can create
--      customers without direct INSERT rights on users/customers.
--   4. Adds rpc_record_supplier_payment(...) for idempotent supplier
--      payments, replacing direct ledger writes.
--   5. Reconciles grants:
--      - users/customers are read-only to clients, with column-level
--        SELECT that excludes pin_code / device_token;
--      - sensitive tables are writable only through SECURITY DEFINER
--        RPCs;
--      - orders keeps a narrow UPDATE(status, driver_id, notes) for
--        the existing status-sync path;
--      - append-only telemetry tables keep INSERT but lose UPDATE/
--        DELETE and gain RLS.
--   6. Re-grants SELECT on all reporting views and reloads PostgREST.
--
-- HOW TO APPLY
--   Run this whole file in the Supabase SQL editor as the project
--   owner (postgres). It is written to be idempotent.
--
-- VERIFY AFTER APPLYING
--   SELECT has_column_privilege('anon','public.users','pin_code','SELECT');        -- must be false
--   SELECT has_column_privilege('anon','public.customers','device_token','SELECT');-- must be false
--   SELECT has_table_privilege('anon','public.users','UPDATE');                     -- must be false
--   SELECT has_table_privilege('anon','public.customers','UPDATE');                 -- must be false
--   SELECT has_table_privilege('anon','public.orders','INSERT');                    -- must be false
--   SELECT has_column_privilege('anon','public.orders','status','UPDATE');          -- must be true
--   SELECT has_column_privilege('anon','public.orders','total_amount','UPDATE');    -- must be false
--   SELECT p.oid::regprocedure, has_function_privilege('anon', p.oid, 'EXECUTE')
--   FROM pg_proc p
--   WHERE p.pronamespace = 'public'::regnamespace
--     AND p.proname IN ('rpc_save_user_profile','rpc_create_customer_by_staff',
--                       'rpc_record_supplier_payment','rpc_submit_customer_order',
--                       'rpc_post_store_sale','rpc_update_user_profile',
--                       'rpc_sync_customer_profile')
--   ORDER BY p.proname;
--   -- Expected: the first five are true; the last two are false.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- PART 1: FIX THE AUDIT TRIGGER (42883)
-- ============================================================

CREATE OR REPLACE FUNCTION trigger_audit_log_func()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_user_id   UUID := NULL;
    v_before    JSONB := NULL;
    v_after     JSONB := NULL;
    v_new_json  JSONB := NULL;
    v_old_json  JSONB := NULL;
    v_target_id UUID := NULL;
BEGIN
    -- Resolve actor from auth.uid() when a JWT exists.
    BEGIN
        v_user_id := auth.uid();
    EXCEPTION WHEN OTHERS THEN
        v_user_id := NULL;
    END;

    -- Convert composite rows to JSONB once. Composite records do not
    -- support the jsonb `?` operator; to_jsonb(NEW) does.
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        v_new_json := to_jsonb(NEW) - 'pin_code' - 'device_token';
    END IF;
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        v_old_json := to_jsonb(OLD) - 'pin_code' - 'device_token';
    END IF;

    -- Extract target id.
    BEGIN
        v_target_id := COALESCE(v_new_json->>'id', v_old_json->>'id')::UUID;
    EXCEPTION WHEN OTHERS THEN
        v_target_id := NULL;
    END;

    -- Deduce actor from record fields for anon clients.
    IF v_user_id IS NULL AND v_new_json IS NOT NULL THEN
        BEGIN
            IF TG_TABLE_NAME = 'orders' THEN
                v_user_id := NULLIF(v_new_json->>'cashier_id', '')::UUID;
            ELSIF TG_TABLE_NAME = 'wallet_entries' THEN
                v_user_id := NULLIF(v_new_json->>'driver_id', '')::UUID;
            ELSIF TG_TABLE_NAME = 'settlements' THEN
                v_user_id := NULLIF(v_new_json->>'cashier_id', '')::UUID;
            ELSIF TG_TABLE_NAME = 'users' THEN
                v_user_id := v_target_id;
            END IF;
        EXCEPTION WHEN OTHERS THEN
            v_user_id := NULL;
        END;
    END IF;

    -- Keep full before/after only for critical tables.
    IF TG_TABLE_NAME IN (
        'orders', 'settlements', 'wallet_entries', 'users',
        'customers', 'suppliers', 'purchases'
    ) THEN
        IF TG_OP = 'INSERT' THEN
            v_after := v_new_json;
        ELSIF TG_OP = 'UPDATE' THEN
            v_before := v_old_json;
            v_after := v_new_json;
        ELSIF TG_OP = 'DELETE' THEN
            v_before := v_old_json;
        END IF;
    END IF;

    INSERT INTO audit_log (
        user_id, action, target_table, target_id, before_state, after_state
    ) VALUES (
        v_user_id, TG_OP, TG_TABLE_NAME, v_target_id, v_before, v_after
    );

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

-- Redact credentials from historical audit rows. The trigger above
-- prevents new rows from storing them.
UPDATE audit_log
SET before_state = before_state - 'pin_code' - 'device_token',
    after_state  = after_state  - 'pin_code' - 'device_token'
WHERE target_table IN ('users', 'customers')
  AND (
      (before_state IS NOT NULL AND (before_state ? 'pin_code' OR before_state ? 'device_token'))
      OR
      (after_state IS NOT NULL AND (after_state ? 'pin_code' OR after_state ? 'device_token'))
  );

-- ============================================================
-- PART 2: PROFILE SAVE RPC
-- ============================================================

CREATE OR REPLACE FUNCTION rpc_save_user_profile(
    p_caller_id UUID,
    p_caller_pin TEXT,
    p_target_user_id UUID,
    p_name VARCHAR,
    p_phone VARCHAR,
    p_language VARCHAR DEFAULT 'ar',
    p_role TEXT DEFAULT NULL,
    p_active BOOLEAN DEFAULT NULL,
    p_new_pin TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_auth_check JSONB;
    v_caller users%ROWTYPE;
    v_target users%ROWTYPE;
    v_is_moderator BOOLEAN := FALSE;
    v_clean_name VARCHAR;
    v_clean_phone VARCHAR;
    v_new_language VARCHAR;
    v_new_role user_role;
    v_new_active BOOLEAN;
    v_new_pin TEXT;
    v_other_moderators INT := 0;
BEGIN
    -- 1. Verify the caller with their own PIN.
    v_auth_check := _internal_verify_and_track_pin(p_caller_id, p_caller_pin, FALSE);
    IF COALESCE((v_auth_check->>'valid')::BOOLEAN, FALSE) IS NOT TRUE THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', COALESCE(v_auth_check->>'message', 'فشل التحقق من هوية المستخدم أو رمز PIN')
        );
    END IF;

    SELECT * INTO v_caller FROM users WHERE id = p_caller_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'المستخدم غير موجود');
    END IF;
    v_is_moderator := (v_caller.role = 'moderator');

    -- 2. Non-moderators may only edit themselves.
    IF NOT v_is_moderator AND p_caller_id <> p_target_user_id THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'لا تملك صلاحية تعديل بيانات مستخدم آخر'
        );
    END IF;

    SELECT * INTO v_target FROM users WHERE id = p_target_user_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'الموظف غير موجود');
    END IF;

    -- 3. Validate profile fields.
    v_clean_name := trim(COALESCE(p_name, ''));
    IF LENGTH(v_clean_name) < 2 OR LENGTH(v_clean_name) > 100 THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'الاسم يجب أن يتكون من 2 إلى 100 حرف');
    END IF;

    v_clean_phone := trim(COALESCE(p_phone, ''));
    IF v_clean_phone !~ '^0[0-9]{8,14}$' THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'رقم الهاتف غير صالح (يجب أن يبدأ بـ 0 ويتكون من 9 إلى 15 رقماً)'
        );
    END IF;

    IF EXISTS (
        SELECT 1 FROM users
        WHERE phone = v_clean_phone AND id <> p_target_user_id
    ) THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'رقم الهاتف مستخدم بالفعل من قبل حساب آخر');
    END IF;

    v_new_language := COALESCE(NULLIF(trim(p_language), ''), v_target.language);
    IF v_new_language NOT IN ('ar', 'fr') THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'اللغة غير مدعومة');
    END IF;

    -- 4. Role/active changes are moderator-only.
    IF (p_role IS NOT NULL AND trim(p_role) <> '') OR p_active IS NOT NULL THEN
        IF NOT v_is_moderator THEN
            RETURN jsonb_build_object(
                'status', 'error',
                'message', 'لا تملك صلاحية تغيير الدور أو حالة الحساب'
            );
        END IF;
    END IF;

    v_new_role := v_target.role;
    IF p_role IS NOT NULL AND trim(p_role) <> '' THEN
        IF trim(p_role) NOT IN ('moderator', 'manager', 'cashier', 'driver') THEN
            RETURN jsonb_build_object('status', 'error', 'message', 'الدور الوظيفي غير صالح');
        END IF;
        v_new_role := trim(p_role)::user_role;
    END IF;
    v_new_active := COALESCE(p_active, v_target.active);

    -- 5. Never allow the last active moderator to be demoted or disabled.
    IF v_target.role = 'moderator'
       AND v_target.active = TRUE
       AND (v_new_role <> 'moderator' OR v_new_active = FALSE)
    THEN
        SELECT COUNT(*) INTO v_other_moderators
        FROM users
        WHERE role = 'moderator'
          AND active = TRUE
          AND id <> p_target_user_id;

        IF v_other_moderators = 0 THEN
            RETURN jsonb_build_object(
                'status', 'error',
                'message', 'لا يمكن تعطيل أو تغيير دور آخر مشرف عام نشط'
            );
        END IF;
    END IF;

    -- 6. Optional new PIN for the target. The caller's PIN above is the
    --    authorization proof, so a moderator resetting another staff
    --    member's PIN does not need that staff member's old PIN.
    v_new_pin := NULLIF(trim(p_new_pin), '');
    IF v_new_pin IS NOT NULL AND v_new_pin !~ '^[0-9]{4,8}$' THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'رمز PIN الجديد يجب أن يتكون من 4 إلى 8 أرقام'
        );
    END IF;

    -- 7. Apply the update.
    UPDATE users
    SET name       = v_clean_name,
        phone      = v_clean_phone,
        language   = v_new_language,
        role       = v_new_role,
        active     = v_new_active,
        pin_code   = CASE
                         WHEN v_new_pin IS NOT NULL
                         THEN crypt(v_new_pin, gen_salt('bf'))
                         ELSE pin_code
                     END,
        updated_at = NOW()
    WHERE id = p_target_user_id;

    -- 8. Explicit audit entry (never includes the PIN hash).
    INSERT INTO audit_log (
        user_id, action, target_table, target_id, before_state, after_state
    ) VALUES (
        p_caller_id,
        'USER_PROFILE_UPDATED',
        'users',
        p_target_user_id,
        jsonb_build_object(
            'name', v_target.name,
            'phone', v_target.phone,
            'role', v_target.role,
            'active', v_target.active,
            'language', v_target.language
        ),
        jsonb_build_object(
            'name', v_clean_name,
            'phone', v_clean_phone,
            'role', v_new_role,
            'active', v_new_active,
            'language', v_new_language,
            'pin_changed', (v_new_pin IS NOT NULL)
        )
    );

    RETURN jsonb_build_object(
        'status', 'success',
        'message', 'تم تحديث البيانات بنجاح',
        'user_id', p_target_user_id,
        'name', v_clean_name,
        'phone', v_clean_phone,
        'role', v_new_role,
        'active', v_new_active,
        'language', v_new_language
    );
END;
$$;

REVOKE ALL ON FUNCTION rpc_save_user_profile(
    UUID, TEXT, UUID, VARCHAR, VARCHAR, VARCHAR, TEXT, BOOLEAN, TEXT
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_save_user_profile(
    UUID, TEXT, UUID, VARCHAR, VARCHAR, VARCHAR, TEXT, BOOLEAN, TEXT
) TO anon, authenticated;

-- ============================================================
-- PART 3: STAFF-CREATED CUSTOMER RPC
-- ============================================================

CREATE OR REPLACE FUNCTION rpc_create_customer_by_staff(
    p_caller_id UUID,
    p_caller_pin TEXT,
    p_name VARCHAR,
    p_phone VARCHAR,
    p_credit_limit BIGINT DEFAULT 0,
    p_price_tier TEXT DEFAULT 'wholesale'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_auth_check JSONB;
    v_caller users%ROWTYPE;
    v_clean_name VARCHAR;
    v_clean_phone VARCHAR;
    v_tier price_tier := 'wholesale';
    v_user_id UUID;
    v_customer_id UUID;
BEGIN
    v_auth_check := _internal_verify_and_track_pin(p_caller_id, p_caller_pin, FALSE);
    IF COALESCE((v_auth_check->>'valid')::BOOLEAN, FALSE) IS NOT TRUE THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', COALESCE(v_auth_check->>'message', 'فشل التحقق من هوية المستخدم أو رمز PIN')
        );
    END IF;

    SELECT * INTO v_caller FROM users WHERE id = p_caller_id;
    IF NOT FOUND OR v_caller.role NOT IN ('moderator', 'manager', 'cashier') THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'هذه العملية متاحة للمشرف أو مدير المخزون أو أمين الصندوق فقط'
        );
    END IF;

    v_clean_name := trim(COALESCE(p_name, ''));
    IF LENGTH(v_clean_name) < 2 OR LENGTH(v_clean_name) > 100 THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'اسم الزبون يجب أن يتكون من 2 إلى 100 حرف');
    END IF;

    v_clean_phone := trim(COALESCE(p_phone, ''));
    IF v_clean_phone !~ '^0[5-7][0-9]{8}$' THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'رقم هاتف الزبون غير صالح (يجب أن يبدأ بـ 05 أو 06 أو 07)'
        );
    END IF;

    IF COALESCE(p_credit_limit, 0) < 0 THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'سقف الائتمان لا يمكن أن يكون سالباً');
    END IF;

    IF p_price_tier IS NOT NULL AND trim(p_price_tier) <> '' THEN
        IF trim(p_price_tier) NOT IN ('retail', 'wholesale', 'bulk') THEN
            RETURN jsonb_build_object('status', 'error', 'message', 'فئة السعر غير صالحة');
        END IF;
        v_tier := trim(p_price_tier)::price_tier;
    END IF;

    IF EXISTS (SELECT 1 FROM users WHERE phone = v_clean_phone) THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'رقم الهاتف مسجل بالفعل. ابحث عن الزبون في القائمة بدلاً من إنشاء حساب جديد.'
        );
    END IF;

    INSERT INTO users (name, phone, role, language, active)
    VALUES (v_clean_name, v_clean_phone, 'customer', 'ar', TRUE)
    RETURNING id INTO v_user_id;

    INSERT INTO customers (user_id, credit_limit, price_tier)
    VALUES (v_user_id, COALESCE(p_credit_limit, 0), v_tier)
    RETURNING id INTO v_customer_id;

    INSERT INTO audit_log (
        user_id, action, target_table, target_id, after_state
    ) VALUES (
        p_caller_id,
        'CUSTOMER_CREATED_BY_STAFF',
        'customers',
        v_customer_id,
        jsonb_build_object(
            'customer_id', v_customer_id,
            'user_id', v_user_id,
            'name', v_clean_name,
            'phone', v_clean_phone,
            'credit_limit', COALESCE(p_credit_limit, 0),
            'price_tier', v_tier
        )
    );

    RETURN jsonb_build_object(
        'status', 'success',
        'message', 'تم تسجيل الزبون بنجاح',
        'customer_id', v_customer_id,
        'user_id', v_user_id,
        'name', v_clean_name,
        'phone', v_clean_phone,
        'credit_limit', COALESCE(p_credit_limit, 0),
        'price_tier', v_tier
    );
END;
$$;

REVOKE ALL ON FUNCTION rpc_create_customer_by_staff(
    UUID, TEXT, VARCHAR, VARCHAR, BIGINT, TEXT
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_create_customer_by_staff(
    UUID, TEXT, VARCHAR, VARCHAR, BIGINT, TEXT
) TO anon, authenticated;

-- ============================================================
-- PART 4: IDEMPOTENT SUPPLIER PAYMENT RPC
-- ============================================================

ALTER TABLE supplier_ledger
    ADD COLUMN IF NOT EXISTS client_id UUID;

CREATE UNIQUE INDEX IF NOT EXISTS idx_supplier_ledger_client_id
    ON supplier_ledger(client_id)
    WHERE client_id IS NOT NULL;

-- Drop the earlier draft signature if it was ever applied manually.
DROP FUNCTION IF EXISTS rpc_record_supplier_payment(
    UUID, UUID, BIGINT, UUID, UUID, TEXT
);

CREATE OR REPLACE FUNCTION rpc_record_supplier_payment(
    p_client_id UUID,
    p_supplier_id UUID,
    p_amount BIGINT,
    p_payer_user_id UUID,
    p_purchase_id UUID DEFAULT NULL,
    p_notes TEXT DEFAULT NULL,
    p_caller_pin TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_auth_check JSONB;
    v_caller users%ROWTYPE;
    v_existing supplier_ledger%ROWTYPE;
    v_supplier suppliers%ROWTYPE;
BEGIN
    IF p_client_id IS NULL THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'معرف العملية مطلوب');
    END IF;

    -- The payer is the caller. Require the payer's own PIN, because the
    -- anon key alone must never authorize a financial write.
    v_auth_check := _internal_verify_and_track_pin(
        p_payer_user_id, p_caller_pin, FALSE
    );
    IF COALESCE((v_auth_check->>'valid')::BOOLEAN, FALSE) IS NOT TRUE THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', COALESCE(v_auth_check->>'message', 'فشل التحقق من هوية المستخدم أو رمز PIN')
        );
    END IF;

    SELECT * INTO v_caller FROM users WHERE id = p_payer_user_id;
    IF NOT FOUND OR v_caller.role NOT IN ('moderator', 'manager', 'cashier') THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'هذه العملية متاحة للمشرف أو مدير المخزون أو أمين الصندوق فقط'
        );
    END IF;

    SELECT * INTO v_existing FROM supplier_ledger WHERE client_id = p_client_id;
    IF FOUND THEN
        RETURN jsonb_build_object(
            'status', 'already_processed',
            'ledger_id', v_existing.id,
            'client_id', p_client_id
        );
    END IF;

    IF p_amount IS NULL OR p_amount <= 0 THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'المبلغ غير صالح');
    END IF;

    SELECT * INTO v_supplier FROM suppliers WHERE id = p_supplier_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'المورد غير موجود');
    END IF;

    INSERT INTO supplier_ledger (
        supplier_id, amount_change, ref_type, ref_id, notes, client_id
    ) VALUES (
        p_supplier_id,
        -p_amount,
        'supplier_payment',
        COALESCE(p_purchase_id, p_client_id),
        COALESCE(NULLIF(trim(p_notes), ''), 'سداد نقدي لمستحقات المورد'),
        p_client_id
    )
    RETURNING * INTO v_existing;

    INSERT INTO audit_log (
        user_id, action, target_table, target_id, after_state
    ) VALUES (
        p_payer_user_id,
        'SUPPLIER_PAYMENT',
        'supplier_ledger',
        v_existing.id,
        jsonb_build_object(
            'ledger_id', v_existing.id,
            'supplier_id', p_supplier_id,
            'supplier_name', v_supplier.name,
            'amount', p_amount,
            'purchase_id', p_purchase_id,
            'client_id', p_client_id,
            'notes', p_notes
        )
    );

    RETURN jsonb_build_object(
        'status', 'success',
        'ledger_id', v_existing.id,
        'supplier_id', p_supplier_id,
        'amount', p_amount,
        'client_id', p_client_id
    );
END;
$$;

REVOKE ALL ON FUNCTION rpc_record_supplier_payment(
    UUID, UUID, BIGINT, UUID, UUID, TEXT, TEXT
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_record_supplier_payment(
    UUID, UUID, BIGINT, UUID, UUID, TEXT, TEXT
) TO anon, authenticated;

-- ============================================================
-- PART 5: GRANT / RLS RECONCILIATION
-- ============================================================

-- PostgreSQL keeps table-level and column-level grants separate:
-- `REVOKE ALL ON TABLE` does NOT remove old grants such as
-- `GRANT UPDATE (name, phone, role, active, language, updated_at)`.
-- Clear every column privilege on the tables we are making read-only
-- (or narrow-update), then re-grant exactly what is needed below.
DO $$
DECLARE
    v_table TEXT;
    v_column TEXT;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'users', 'customers', 'addresses', 'orders',
        'products', 'product_prices', 'product_barcodes',
        'suppliers', 'purchases', 'purchase_items', 'order_items',
        'stock_ledger', 'customer_ledger', 'supplier_ledger', 'payments',
        'settlements', 'wallet_entries', 'pos_shifts', 'permissions',
        'role_permissions', 'app_versions', 'audit_log',
        'audit_log_partitioned', 'pin_attempt_limits'
    ] LOOP
        FOR v_column IN
            SELECT column_name
            FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = v_table
        LOOP
            EXECUTE format(
                'REVOKE ALL (%I) ON TABLE public.%I FROM anon, authenticated',
                v_column, v_table
            );
        END LOOP;
    END LOOP;
END $$;

-- ------------------------------------------------------------
-- 5.1 users: read-only, PIN hash excluded
-- ------------------------------------------------------------
REVOKE ALL ON TABLE users FROM anon, authenticated;
GRANT SELECT (
    id, phone, name, role, active, language, created_at, updated_at
) ON TABLE users TO anon, authenticated;

ALTER TABLE users ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public read users profile lookup" ON users;
DROP POLICY IF EXISTS "Allow anon read users for profile and lookup" ON users;
DROP POLICY IF EXISTS "Allow customer self-registration" ON users;
DROP POLICY IF EXISTS "Allow customer self-update" ON users;
DROP POLICY IF EXISTS "Allow user profile updates" ON users;
DROP POLICY IF EXISTS "Allow staff and user profile update" ON users;
DROP POLICY IF EXISTS "Allow authenticated staff update users" ON users;
DROP POLICY IF EXISTS "Allow all operations on users for app functionality" ON users;
DROP POLICY IF EXISTS "Users can view their own profile" ON users;
DROP POLICY IF EXISTS "Moderator full control over users" ON users;
DROP POLICY IF EXISTS "users_read" ON users;

CREATE POLICY "users_read" ON users
    FOR SELECT
    USING (TRUE);

-- ------------------------------------------------------------
-- 5.2 customers: read-only, device token excluded
-- ------------------------------------------------------------
REVOKE ALL ON TABLE customers FROM anon, authenticated;
GRANT SELECT (
    id, user_id, price_tier, credit_limit, created_at, updated_at
) ON TABLE customers TO anon, authenticated;

ALTER TABLE customers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Customers readable by all" ON customers;
DROP POLICY IF EXISTS "Allow read customers" ON customers;
DROP POLICY IF EXISTS "Customers insertable" ON customers;
DROP POLICY IF EXISTS "Customers updatable by staff and owner" ON customers;
DROP POLICY IF EXISTS "Allow insert customer user_id" ON customers;
DROP POLICY IF EXISTS "Allow all operations on customers" ON customers;
DROP POLICY IF EXISTS "customers_write_authenticated" ON customers;
DROP POLICY IF EXISTS "customers_read" ON customers;

CREATE POLICY "customers_read" ON customers
    FOR SELECT
    USING (TRUE);

-- ------------------------------------------------------------
-- 5.3 addresses: read-only to clients; writes go through RPCs
-- ------------------------------------------------------------
REVOKE INSERT, UPDATE, DELETE ON addresses FROM anon, authenticated;
GRANT SELECT ON addresses TO anon, authenticated;

ALTER TABLE addresses ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Addresses operations" ON addresses;
DROP POLICY IF EXISTS "addresses_open" ON addresses;
DROP POLICY IF EXISTS "Allow all operations on addresses" ON addresses;
DROP POLICY IF EXISTS "Allow all operations on addresses for app functionality" ON addresses;
DROP POLICY IF EXISTS "addresses_read" ON addresses;

CREATE POLICY "addresses_read" ON addresses
    FOR SELECT
    USING (TRUE);

-- ------------------------------------------------------------
-- 5.4 orders: RPC-only inserts; narrow direct status update
-- ------------------------------------------------------------
REVOKE INSERT, UPDATE, DELETE ON orders FROM anon, authenticated;
GRANT SELECT ON orders TO anon, authenticated;
GRANT UPDATE (status, driver_id, notes) ON orders TO anon, authenticated;

ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Orders view policy" ON orders;
DROP POLICY IF EXISTS "Orders insert policy" ON orders;
DROP POLICY IF EXISTS "Orders update policy" ON orders;
DROP POLICY IF EXISTS "Customer view own orders" ON orders;
DROP POLICY IF EXISTS "Customer create orders" ON orders;
DROP POLICY IF EXISTS "Staff update orders" ON orders;
DROP POLICY IF EXISTS "Allow all operations on orders" ON orders;
DROP POLICY IF EXISTS "orders_read" ON orders;
DROP POLICY IF EXISTS "orders_client_update" ON orders;

CREATE POLICY "orders_read" ON orders
    FOR SELECT
    USING (TRUE);

CREATE POLICY "orders_client_update" ON orders
    FOR UPDATE
    TO anon, authenticated
    USING (TRUE)
    WITH CHECK (TRUE);

-- ------------------------------------------------------------
-- 5.5 catalogue: RPC-only writes
-- ------------------------------------------------------------
REVOKE INSERT, UPDATE, DELETE ON products FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON product_prices FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON product_barcodes FROM anon, authenticated;

GRANT SELECT ON products TO anon, authenticated;
GRANT SELECT ON product_prices TO anon, authenticated;
GRANT SELECT ON product_barcodes TO anon, authenticated;

-- ------------------------------------------------------------
-- 5.6 purchasing and stock: RPC-only writes
-- ------------------------------------------------------------
REVOKE INSERT, UPDATE, DELETE ON suppliers FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON purchases FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON purchase_items FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON order_items FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON stock_ledger FROM anon, authenticated;

GRANT SELECT ON suppliers TO anon, authenticated;
GRANT SELECT ON purchases TO anon, authenticated;
GRANT SELECT ON purchase_items TO anon, authenticated;
GRANT SELECT ON order_items TO anon, authenticated;
GRANT SELECT ON stock_ledger TO anon, authenticated;

-- ------------------------------------------------------------
-- 5.7 financial ledgers: RPC-only writes
-- ------------------------------------------------------------
REVOKE INSERT, UPDATE, DELETE ON customer_ledger FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON supplier_ledger FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON payments FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON settlements FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON wallet_entries FROM anon, authenticated;

GRANT SELECT ON customer_ledger TO anon, authenticated;
GRANT SELECT ON supplier_ledger TO anon, authenticated;
GRANT SELECT ON payments TO anon, authenticated;
GRANT SELECT ON settlements TO anon, authenticated;
GRANT SELECT ON wallet_entries TO anon, authenticated;

-- ------------------------------------------------------------
-- 5.8 POS shifts, PIN attempt limits, permissions: read-only
-- ------------------------------------------------------------
REVOKE INSERT, UPDATE, DELETE ON pos_shifts FROM anon, authenticated;
GRANT SELECT ON pos_shifts TO anon, authenticated;

REVOKE ALL ON pin_attempt_limits FROM anon, authenticated;

REVOKE INSERT, UPDATE, DELETE ON permissions FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON role_permissions FROM anon, authenticated;
GRANT SELECT ON permissions TO anon, authenticated;
GRANT SELECT ON role_permissions TO anon, authenticated;

-- ------------------------------------------------------------
-- 5.9 app versions: public read, moderator-managed (service role)
-- ------------------------------------------------------------
REVOKE INSERT, UPDATE, DELETE ON app_versions FROM anon, authenticated;
GRANT SELECT ON app_versions TO anon, authenticated;

-- ------------------------------------------------------------
-- 5.10 audit log: append-only to clients, not directly readable
--      Moderators read the sanitised view instead.
-- ------------------------------------------------------------
REVOKE SELECT, UPDATE, DELETE ON audit_log FROM anon, authenticated;
GRANT INSERT ON audit_log TO anon, authenticated;

DO $$
DECLARE
    v_partition REGCLASS;
BEGIN
    IF to_regclass('public.audit_log_partitioned') IS NOT NULL THEN
        EXECUTE 'REVOKE ALL ON audit_log_partitioned FROM anon, authenticated';
        EXECUTE 'ALTER TABLE audit_log_partitioned ENABLE ROW LEVEL SECURITY';

        FOR v_partition IN
            SELECT inhrelid::regclass
            FROM pg_inherits
            WHERE inhparent = 'public.audit_log_partitioned'::regclass
        LOOP
            EXECUTE format(
                'REVOKE ALL ON %s FROM anon, authenticated',
                v_partition
            );
            EXECUTE format(
                'ALTER TABLE %s ENABLE ROW LEVEL SECURITY',
                v_partition
            );
        END LOOP;
    END IF;
END $$;

ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow select audit_log" ON audit_log;
DROP POLICY IF EXISTS "Allow insert audit_log" ON audit_log;
DROP POLICY IF EXISTS "Staff and moderator view audit log" ON audit_log;
DROP POLICY IF EXISTS "Allow view audit logs" ON audit_log;
DROP POLICY IF EXISTS "Only moderator views audit log" ON audit_log;
DROP POLICY IF EXISTS "Deny direct audit_log insert" ON audit_log;
DROP POLICY IF EXISTS "Deny direct audit_log update" ON audit_log;
DROP POLICY IF EXISTS "Deny direct audit_log delete" ON audit_log;
DROP POLICY IF EXISTS "audit_log_client_insert" ON audit_log;

CREATE POLICY "audit_log_client_insert" ON audit_log
    FOR INSERT
    TO anon, authenticated
    WITH CHECK (
        audit_log.user_id IS NOT NULL
        AND EXISTS (SELECT 1 FROM users u WHERE u.id = audit_log.user_id)
    );

-- The moderator dashboard reads this view. Recreate it as an owner-run
-- view with a deliberately small, non-sensitive column list. Raw
-- before_state / after_state / ip_address payloads stay unreadable to
-- clients even though they can still execute INSERT for their own
-- append-only audit events.
DROP VIEW IF EXISTS view_audit_trail_intelligence CASCADE;
DROP VIEW IF EXISTS view_audit_log_enriched CASCADE;

CREATE VIEW view_audit_log_enriched
AS
SELECT
    a.id,
    a.created_at,
    a.action,
    a.target_table,
    a.target_id,
    a.user_id,
    u.name  AS actor_name,
    u.role  AS actor_role,
    u.phone AS actor_phone,
    CASE
        WHEN a.target_table = 'orders' AND a.action = 'INSERT'
            THEN 'طلب جديد تم تسجيله (' || COALESCE(a.after_state->>'channel', 'store') || ')'
        WHEN a.target_table = 'orders' AND a.action = 'UPDATE'
            THEN 'تحديث حالة الطلب إلى: ' || COALESCE(a.after_state->>'status', '')
        WHEN a.target_table = 'orders' AND a.action = 'DELETE'
            THEN 'حذف أو إلغاء طلب'
        WHEN a.target_table = 'payments' AND a.action = 'INSERT'
            THEN 'تحصيل مالي: ' || COALESCE(((a.after_state->>'amount')::numeric / 100)::text, '0') || ' دج'
        WHEN a.target_table = 'settlements'
            THEN 'إغلاق تسوية سائق (End-of-day)'
        WHEN a.target_table = 'wallet_entries' AND a.action = 'INSERT'
            THEN 'حركة بمحفظة السائق: ' || COALESCE(a.after_state->>'type', '')
        WHEN a.target_table = 'stock_ledger' AND a.action = 'INSERT'
            THEN 'حركة مخزون (' || COALESCE(a.after_state->>'reason', '') || ')'
        WHEN a.target_table = 'purchases' AND a.action = 'INSERT'
            THEN 'فاتورة شراء جديدة: ' || COALESCE(a.after_state->>'invoice_no', '')
        WHEN a.target_table = 'purchases' AND a.action = 'UPDATE'
            THEN 'تحديث حالة فاتورة شراء إلى: ' || COALESCE(a.after_state->>'status', '')
        WHEN a.target_table = 'products' AND a.action = 'INSERT'
            THEN 'إضافة منتج جديد: ' || COALESCE(a.after_state->>'name_ar', '')
        WHEN a.target_table = 'products' AND a.action = 'UPDATE'
            THEN 'تعديل منتج: ' || COALESCE(a.after_state->>'name_ar', '')
        WHEN a.target_table = 'customers'
            THEN 'تحديث بيانات زبون / حد الائتمان'
        WHEN a.target_table = 'suppliers'
            THEN 'إضافة أو تعديل مورد'
        WHEN a.target_table = 'addresses'
            THEN 'إضافة أو تعديل عنوان توصيل'
        WHEN a.action = 'STAFF_LOGIN'
            THEN 'تسجيل دخول موظف: ' || COALESCE(a.after_state->>'name', u.name, '')
        WHEN a.action = 'STAFF_LOGOUT'
            THEN 'تسجيل خروج موظف: ' || COALESCE(a.after_state->>'name', u.name, '')
        WHEN a.action = 'CASHIER_SWITCH'
            THEN 'تبديل كاشير: ' || COALESCE(a.after_state->>'new_cashier_name', '')
        WHEN a.action = 'SUPPLIER_PAYMENT'
            THEN 'سداد نقدي للمورد: ' || COALESCE(a.after_state->>'supplier_name', '')
        WHEN a.action = 'USER_PROFILE_UPDATED'
            THEN 'تحديث بيانات مستخدم: ' || COALESCE(a.after_state->>'name', '')
        WHEN a.action = 'CUSTOMER_CREATED_BY_STAFF'
            THEN 'تسجيل زبون جديد: ' || COALESCE(a.after_state->>'name', '')
        WHEN a.action = 'MODERATOR_RESET_USER_PIN'
            THEN 'إعادة تعيين رمز PIN لموظف بواسطة المشرف'
        WHEN a.action = 'USER_PIN_CHANGED'
            THEN 'تغيير رمز PIN الحساب'
        WHEN a.action = 'STAFF_MEMBER_CREATED'
            THEN 'إنشاء حساب موظف جديد'
        ELSE a.action || ' على ' || a.target_table
    END AS intelligent_title,
    CASE
        WHEN a.action IN ('SHIFT_OPENED', 'SHIFT_CLOSED', 'SUPPLIER_PAYMENT')
            THEN 'finance'
        WHEN a.target_table IN (
            'payments', 'settlements', 'customer_ledger',
            'supplier_ledger', 'wallet_entries'
        ) THEN 'finance'
        WHEN a.target_table IN ('orders', 'order_items')
            THEN 'sales'
        WHEN a.target_table IN (
            'stock_ledger', 'purchases', 'purchase_items',
            'products', 'product_prices', 'product_barcodes'
        ) THEN 'inventory'
        WHEN a.target_table IN ('users', 'customers')
             OR a.action IN (
                 'STAFF_LOGIN', 'STAFF_LOGOUT', 'CASHIER_SWITCH',
                 'MODERATOR_RESET_USER_PIN', 'USER_PIN_CHANGED',
                 'STAFF_MEMBER_CREATED', 'USER_PROFILE_UPDATED',
                 'CUSTOMER_CREATED_BY_STAFF'
             ) THEN 'security'
        ELSE 'general'
    END AS category,
    CASE
        WHEN u.role = 'customer' THEN 'customer'
        WHEN u.role IN ('cashier', 'driver', 'manager', 'moderator') THEN 'staff'
        WHEN a.action IN (
            'STAFF_LOGIN', 'STAFF_LOGOUT', 'CASHIER_SWITCH',
            'SHIFT_OPENED', 'SHIFT_CLOSED'
        ) THEN 'staff'
        ELSE 'system'
    END AS actor_type
FROM audit_log a
LEFT JOIN users u ON a.user_id = u.id;

CREATE VIEW view_audit_trail_intelligence AS
SELECT * FROM view_audit_log_enriched;

GRANT SELECT ON view_audit_log_enriched TO anon, authenticated;
GRANT SELECT ON view_audit_trail_intelligence TO anon, authenticated;

-- ------------------------------------------------------------
-- 5.11 driver telemetry: append-only, RLS enabled
-- ------------------------------------------------------------
REVOKE DELETE ON driver_locations FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON driver_locations TO anon, authenticated;

DO $$
BEGIN
    IF to_regclass('public.driver_location_events') IS NOT NULL THEN
        EXECUTE 'ALTER TABLE driver_location_events ENABLE ROW LEVEL SECURITY';
        EXECUTE 'REVOKE UPDATE, DELETE ON driver_location_events FROM anon, authenticated';
        EXECUTE 'GRANT SELECT, INSERT ON driver_location_events TO anon, authenticated';
        EXECUTE 'DROP POLICY IF EXISTS driver_location_events_read ON driver_location_events';
        EXECUTE 'DROP POLICY IF EXISTS driver_location_events_insert ON driver_location_events';
        EXECUTE 'CREATE POLICY driver_location_events_read ON driver_location_events FOR SELECT USING (TRUE)';
        EXECUTE 'CREATE POLICY driver_location_events_insert ON driver_location_events FOR INSERT WITH CHECK (driver_id IS NOT NULL)';
    END IF;
END $$;

-- ------------------------------------------------------------
-- 5.12 failed sync operations: append-only, RLS enabled
-- ------------------------------------------------------------
DO $$
BEGIN
    IF to_regclass('public.failed_operations') IS NOT NULL THEN
        EXECUTE 'ALTER TABLE failed_operations ENABLE ROW LEVEL SECURITY';
        EXECUTE 'REVOKE UPDATE, DELETE ON failed_operations FROM anon, authenticated';
        EXECUTE 'GRANT SELECT, INSERT ON failed_operations TO anon, authenticated';
        EXECUTE 'DROP POLICY IF EXISTS failed_operations_read ON failed_operations';
        EXECUTE 'DROP POLICY IF EXISTS failed_operations_insert ON failed_operations';
        EXECUTE 'CREATE POLICY failed_operations_read ON failed_operations FOR SELECT USING (TRUE)';
        EXECUTE 'CREATE POLICY failed_operations_insert ON failed_operations FOR INSERT WITH CHECK (client_id IS NOT NULL)';
    END IF;
END $$;

-- ------------------------------------------------------------
-- 5.13 aggregate snapshots: read-only to clients, maintained by
--      SECURITY DEFINER triggers.
-- ------------------------------------------------------------
DO $$
DECLARE
    v_table TEXT;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'product_stock_snapshot',
        'customer_balance_snapshot',
        'driver_wallet_snapshot',
        'supplier_balance_snapshot'
    ] LOOP
        IF to_regclass('public.' || v_table) IS NOT NULL THEN
            EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', v_table);
            EXECUTE format('REVOKE ALL ON %I FROM anon, authenticated', v_table);
            EXECUTE format('GRANT SELECT ON %I TO anon, authenticated', v_table);
            EXECUTE format('DROP POLICY IF EXISTS %I ON %I', v_table || '_read', v_table);
            EXECUTE format(
                'CREATE POLICY %I ON %I FOR SELECT USING (TRUE)',
                v_table || '_read', v_table
            );
        END IF;
    END LOOP;
END $$;

-- ------------------------------------------------------------
-- 5.14 reporting views: restore SELECT after table grants change
-- ------------------------------------------------------------
DO $$
DECLARE
    v_view TEXT;
BEGIN
    FOREACH v_view IN ARRAY ARRAY[
        'view_product_stock',
        'view_driver_wallet_balance',
        'view_customer_balance',
        'view_supplier_balance',
        'view_customer_products',
        'view_audit_log_enriched',
        'view_audit_trail_intelligence'
    ] LOOP
        IF to_regclass('public.' || v_view) IS NOT NULL THEN
            EXECUTE format('GRANT SELECT ON %I TO anon, authenticated', v_view);
        END IF;
    END LOOP;
END $$;

-- ------------------------------------------------------------
-- 5.15 Disable superseded RPCs. The device-bound customer RPC and
--      rpc_save_user_profile are the supported paths.
-- ------------------------------------------------------------
DO $$
BEGIN
    IF to_regprocedure(
        'public.rpc_sync_customer_profile(varchar,varchar,varchar,varchar,text,double precision,double precision,uuid,uuid)'
    ) IS NOT NULL THEN
        EXECUTE 'REVOKE EXECUTE ON FUNCTION rpc_sync_customer_profile(
            VARCHAR, VARCHAR, VARCHAR, VARCHAR, TEXT,
            DOUBLE PRECISION, DOUBLE PRECISION, UUID, UUID
        ) FROM PUBLIC, anon, authenticated';
    END IF;

    IF to_regprocedure(
        'public.rpc_update_user_profile(uuid,text,uuid,varchar,varchar,varchar,public.user_role,boolean)'
    ) IS NOT NULL THEN
        EXECUTE 'REVOKE EXECUTE ON FUNCTION rpc_update_user_profile(
            UUID, TEXT, UUID, VARCHAR, VARCHAR, VARCHAR, user_role, BOOLEAN
        ) FROM PUBLIC, anon, authenticated';
    END IF;
END $$;

-- ============================================================
-- PART 6: RELOAD POSTGREST SCHEMA CACHE
-- ============================================================
NOTIFY pgrst, 'reload schema';
