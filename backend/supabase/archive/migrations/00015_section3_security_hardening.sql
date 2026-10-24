-- ============================================================
-- 00015_section3_security_hardening.sql
-- REVISED SECTION 3 SECURITY HARDENING
-- ============================================================

-- 1. DROP OLD OVERLOADS
DROP FUNCTION IF EXISTS rpc_create_staff_member(VARCHAR, VARCHAR, user_role, VARCHAR);

-- 2. SECURE PIN ATTEMPT LIMITING TABLE
CREATE TABLE IF NOT EXISTS pin_attempt_limits (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    failed_attempts INT NOT NULL DEFAULT 0,
    locked_until TIMESTAMPTZ,
    lock_step INT NOT NULL DEFAULT 0,
    last_failed_at TIMESTAMPTZ
);

ALTER TABLE pin_attempt_limits ADD COLUMN IF NOT EXISTS last_failed_at TIMESTAMPTZ;
ALTER TABLE pin_attempt_limits ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON pin_attempt_limits FROM PUBLIC, anon, authenticated;

-- 3. INTERIM POLICIES & COLUMN GRANTS ON USERS TABLE
-- Allow reading public, safe profile columns only
REVOKE ALL ON users FROM anon, authenticated;
GRANT SELECT (id, phone, name, role, active, language, created_at, updated_at)
  ON users TO anon, authenticated;

-- Restrict direct writes on sensitive columns; allow interim customer profile writes
GRANT INSERT (name, phone, role, language, active) ON users TO anon, authenticated;
GRANT UPDATE (name, phone, language, active) ON users TO anon, authenticated;

-- Ensure RLS on users prevents tampering with privileged accounts/roles
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow all operations on users for app functionality" ON users;
DROP POLICY IF EXISTS "Allow anon read users for profile and lookup" ON users;
DROP POLICY IF EXISTS "Allow customer self-registration" ON users;
DROP POLICY IF EXISTS "Allow customer self-update" ON users;

CREATE POLICY "Allow anon read users for profile and lookup"
ON users FOR SELECT
USING (TRUE);

-- Customer self-registration: no pin_code clause in policy
CREATE POLICY "Allow customer self-registration"
ON users FOR INSERT
WITH CHECK (
    role = 'customer'::user_role
);

CREATE POLICY "Allow customer self-update"
ON users FOR UPDATE
USING (
    role = 'customer'::user_role
)
WITH CHECK (
    role = 'customer'::user_role
);

-- 4. RESTRICT CUSTOMERS TABLE
REVOKE ALL ON customers FROM anon, authenticated;
GRANT SELECT ON customers TO anon, authenticated;
GRANT INSERT (user_id) ON customers TO anon, authenticated;

ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow all operations on customers" ON customers;
DROP POLICY IF EXISTS "Customers policy" ON customers;
DROP POLICY IF EXISTS "Allow read customers" ON customers;
DROP POLICY IF EXISTS "Allow insert customer user_id" ON customers;

CREATE POLICY "Allow read customers"
ON customers FOR SELECT
USING (TRUE);

CREATE POLICY "Allow insert customer user_id"
ON customers FOR INSERT
WITH CHECK (TRUE);

-- 5. BCRYPT HASHING FOR EXISTING USERS & DROP DEFAULT DEMO PIN
ALTER TABLE users ALTER COLUMN pin_code DROP DEFAULT;

SET search_path = public, extensions, pg_temp;

UPDATE users 
SET pin_code = crypt(COALESCE(pin_code, '1234'), gen_salt('bf'))
WHERE pin_code IS NOT NULL AND pin_code !~ '^\$2[aby]\$';

RESET search_path;

-- 6. SINGLE INTERNAL ADVISORY-LOCKED ATTEMPT CHECK FUNCTION
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

    -- Compare hashed PIN strictly
    IF v_user.pin_code IS NOT NULL AND v_user.pin_code = crypt(p_pin, v_user.pin_code) THEN
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
        -- Step 1: 5 failures -> 1 min
        -- Step 2: 10 failures -> 5 min
        -- Step 3: 15+ failures -> 15 min
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

-- STRICTLY REVOKE EXECUTE ON INTERNAL FUNCTION
REVOKE ALL ON FUNCTION _internal_verify_and_track_pin(UUID, TEXT, BOOLEAN) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION _internal_verify_and_track_pin(UUID, TEXT, BOOLEAN) FROM anon, authenticated, PUBLIC;

-- 7. RPC: rpc_verify_user_pin
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

-- 8. RPC: rpc_change_user_pin
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

    IF LENGTH(p_new_pin) < 4 THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'يجب أن يتكون رمز PIN من 4 أرقام على الأقل');
    END IF;

    UPDATE users
    SET pin_code = crypt(p_new_pin, gen_salt('bf')),
        updated_at = NOW()
    WHERE id = p_user_id;

    INSERT INTO audit_log (user_id, action, target_table, target_id, before_state, after_state)
    VALUES (p_user_id, 'USER_PIN_CHANGED', 'users', p_user_id, NULL, jsonb_build_object('changed_at', NOW()));

    DELETE FROM pin_attempt_limits WHERE user_id = p_user_id;

    RETURN jsonb_build_object('status', 'success', 'message', 'تم تحديث رمز PIN بنجاح');
END;
$$;

GRANT EXECUTE ON FUNCTION rpc_change_user_pin(UUID, TEXT, TEXT) TO anon, authenticated;

-- 9. RPC: rpc_reset_user_pin_by_admin (WITH ADMIN PROOF & PIN VERIFICATION)
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

    IF LENGTH(p_new_pin) < 4 THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'يجب أن يتكون رمز PIN من 4 أرقام على الأقل');
    END IF;

    UPDATE users
    SET pin_code = crypt(p_new_pin, gen_salt('bf')),
        updated_at = NOW()
    WHERE id = p_target_user_id;

    DELETE FROM pin_attempt_limits WHERE user_id = p_target_user_id;

    INSERT INTO audit_log (user_id, action, target_table, target_id, before_state, after_state)
    VALUES (
        p_admin_id,
        'MODERATOR_RESET_USER_PIN',
        'users',
        p_target_user_id,
        NULL,
        jsonb_build_object(
            'target_name', v_target.name,
            'target_phone', v_target.phone,
            'target_role', v_target.role,
            'reset_at', NOW()
        )
    );

    RETURN jsonb_build_object(
        'status', 'success',
        'message', 'تم تعيين وتشفير رمز PIN الجديد للموظف بنجاح',
        'target_user_id', p_target_user_id
    );
END;
$$;

GRANT EXECUTE ON FUNCTION rpc_reset_user_pin_by_admin(UUID, TEXT, UUID, TEXT) TO anon, authenticated;

-- 10. RPC: rpc_create_staff_member (WITH ADMIN PROOF & REQUIRED INITIAL PIN)
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
    v_hashed_pin TEXT;
BEGIN
    -- Verify caller is active moderator with correct PIN
    v_admin_check := _internal_verify_and_track_pin(p_admin_id, p_admin_pin, TRUE);
    IF (v_admin_check->>'valid')::BOOLEAN <> TRUE THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'فشل التحقق من صلاحيات المشرف العام');
    END IF;

    IF p_initial_pin IS NULL OR LENGTH(trim(p_initial_pin)) < 4 THEN
        RAISE EXCEPTION 'A valid initial PIN of at least 4 digits is required';
    END IF;

    v_hashed_pin := crypt(p_initial_pin, gen_salt('bf'));

    INSERT INTO users (id, name, phone, role, pin_code, language, active)
    VALUES (v_user_id, p_name, p_phone, p_role, v_hashed_pin, p_language, TRUE);

    INSERT INTO audit_log (user_id, action, target_table, target_id, before_state, after_state)
    VALUES (
        p_admin_id,
        'STAFF_MEMBER_CREATED',
        'users',
        v_user_id,
        NULL,
        jsonb_build_object('name', p_name, 'phone', p_phone, 'role', p_role)
    );

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

-- 11. AUDIT LOG CLEANUP & STRIP PIN_CODE TRIGGER
UPDATE audit_log 
SET before_state = before_state - 'pin_code',
    after_state  = after_state  - 'pin_code'
WHERE target_table = 'users' 
  AND ((before_state ? 'pin_code') OR (after_state ? 'pin_code'));

CREATE OR REPLACE FUNCTION trigger_audit_log_func()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user_id UUID := NULL;
    v_before JSONB := NULL;
    v_after JSONB := NULL;
    v_target_id UUID := NULL;
BEGIN
    BEGIN v_user_id := auth.uid(); EXCEPTION WHEN OTHERS THEN v_user_id := NULL; END;

    IF TG_OP = 'INSERT' THEN
        v_after := to_jsonb(NEW) - 'pin_code';
        BEGIN v_target_id := (NEW.id)::UUID; EXCEPTION WHEN OTHERS THEN v_target_id := NULL; END;
    ELSIF TG_OP = 'UPDATE' THEN
        v_before := to_jsonb(OLD) - 'pin_code';
        v_after := to_jsonb(NEW) - 'pin_code';
        BEGIN v_target_id := (NEW.id)::UUID; EXCEPTION WHEN OTHERS THEN v_target_id := NULL; END;
    ELSIF TG_OP = 'DELETE' THEN
        v_before := to_jsonb(OLD) - 'pin_code';
        BEGIN v_target_id := (OLD.id)::UUID; EXCEPTION WHEN OTHERS THEN v_target_id := NULL; END;
    END IF;

    IF v_user_id IS NULL THEN
        IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
            IF v_after ? 'received_by' AND (v_after->>'received_by') IS NOT NULL THEN
                v_user_id := (v_after->>'received_by')::UUID;
            ELSIF v_after ? 'cashier_id' AND (v_after->>'cashier_id') IS NOT NULL THEN
                v_user_id := (v_after->>'cashier_id')::UUID;
            ELSIF v_after ? 'created_by' AND (v_after->>'created_by') IS NOT NULL THEN
                v_user_id := (v_after->>'created_by')::UUID;
            ELSIF v_after ? 'user_id' AND (v_after->>'user_id') IS NOT NULL THEN
                v_user_id := (v_after->>'user_id')::UUID;
            ELSIF v_after ? 'driver_id' AND (v_after->>'driver_id') IS NOT NULL THEN
                v_user_id := (v_after->>'driver_id')::UUID;
            ELSIF TG_TABLE_NAME = 'orders' AND v_after ? 'customer_id' AND (v_after->>'customer_id') IS NOT NULL THEN
                SELECT c.user_id INTO v_user_id FROM customers c WHERE c.id = (v_after->>'customer_id')::UUID;
            END IF;
        ELSE
            IF v_before ? 'received_by' AND (v_before->>'received_by') IS NOT NULL THEN
                v_user_id := (v_before->>'received_by')::UUID;
            ELSIF v_before ? 'cashier_id' AND (v_before->>'cashier_id') IS NOT NULL THEN
                v_user_id := (v_before->>'cashier_id')::UUID;
            ELSIF v_before ? 'created_by' AND (v_before->>'created_by') IS NOT NULL THEN
                v_user_id := (v_before->>'created_by')::UUID;
            ELSIF v_before ? 'user_id' AND (v_before->>'user_id') IS NOT NULL THEN
                v_user_id := (v_before->>'user_id')::UUID;
            ELSIF v_before ? 'driver_id' AND (v_before->>'driver_id') IS NOT NULL THEN
                v_user_id := (v_before->>'driver_id')::UUID;
            END IF;
        END IF;
    END IF;

    INSERT INTO audit_log (user_id, action, target_table, target_id, before_state, after_state)
    VALUES (v_user_id, TG_OP, TG_TABLE_NAME, v_target_id, v_before, v_after);

    IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$$;
