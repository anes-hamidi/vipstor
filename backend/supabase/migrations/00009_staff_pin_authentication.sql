-- ============================================================
-- 00009_staff_pin_authentication.sql
-- STAFF PIN AUTHENTICATION & PIN MANAGEMENT RPCs
-- ============================================================

-- 1. Add pin_code column to users table with default demo PIN '1234'
ALTER TABLE users ADD COLUMN IF NOT EXISTS pin_code VARCHAR(10) DEFAULT '1234';

-- 2. Function to atomically verify user PIN
CREATE OR REPLACE FUNCTION rpc_verify_user_pin(
    p_user_id UUID,
    p_pin TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user RECORD;
    v_stored_pin TEXT;
BEGIN
    SELECT id, name, phone, role, active, language, COALESCE(pin_code, '1234') as pin_code
    INTO v_user
    FROM users
    WHERE id = p_user_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('valid', FALSE, 'message', 'المستخدم غير موجود');
    END IF;

    IF v_user.active = FALSE THEN
        RETURN jsonb_build_object('valid', FALSE, 'message', 'الحساب معطل من قبل الإدارة');
    END IF;

    -- Exact pin match strictly (No backdoor overrides)
    IF p_pin = v_user.pin_code THEN
        RETURN jsonb_build_object(
            'valid', TRUE,
            'id', v_user.id,
            'name', v_user.name,
            'phone', v_user.phone,
            'role', v_user.role,
            'language', v_user.language
        );
    ELSE
        RETURN jsonb_build_object('valid', FALSE, 'message', 'رمز PIN غير صحيح');
    END IF;
END;
$$;

-- 3. Function to change user PIN
CREATE OR REPLACE FUNCTION rpc_change_user_pin(
    p_user_id UUID,
    p_old_pin TEXT,
    p_new_pin TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_pin TEXT;
BEGIN
    SELECT COALESCE(pin_code, '1234') INTO v_current_pin
    FROM users
    WHERE id = p_user_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'المستخدم غير موجود');
    END IF;

    IF p_old_pin != v_current_pin THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'رمز PIN الحالي غير صحيح');
    END IF;

    IF LENGTH(p_new_pin) < 4 THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'يجب أن يتكون رمز PIN من 4 أرقام على الأقل');
    END IF;

    UPDATE users
    SET pin_code = p_new_pin,
        updated_at = NOW()
    WHERE id = p_user_id;

    -- Audit log entry
    INSERT INTO audit_log (user_id, action_type, entity_type, entity_id, payload)
    VALUES (p_user_id, 'USER_PIN_CHANGED', 'users', p_user_id, jsonb_build_object('changed_at', NOW()));

    RETURN jsonb_build_object('status', 'success', 'message', 'تم تحديث رمز PIN بنجاح');
END;
$$;

-- 4. Function for moderator/admin to directly reset/generate PIN for any staff member
CREATE OR REPLACE FUNCTION rpc_reset_user_pin_by_admin(
    p_admin_id UUID,
    p_target_user_id UUID,
    p_new_pin TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_admin RECORD;
    v_target RECORD;
BEGIN
    SELECT id, name, phone, role INTO v_target FROM users WHERE id = p_target_user_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'الموظف غير موجود');
    END IF;

    IF LENGTH(p_new_pin) < 4 THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'يجب أن يتكون رمز PIN من 4 أرقام على الأقل');
    END IF;

    UPDATE users
    SET pin_code = p_new_pin,
        updated_at = NOW()
    WHERE id = p_target_user_id;

    -- Audit log entry
    INSERT INTO audit_log (user_id, action_type, entity_type, entity_id, payload)
    VALUES (p_admin_id, 'MODERATOR_RESET_USER_PIN', 'users', p_target_user_id, jsonb_build_object(
        'target_name', v_target.name,
        'target_phone', v_target.phone,
        'target_role', v_target.role,
        'reset_at', NOW()
    ));

    RETURN jsonb_build_object(
        'status', 'success',
        'message', 'تم توليد وتعيين رمز PIN الجديد للموظف بنجاح',
        'target_user_id', p_target_user_id,
        'new_pin', p_new_pin
    );
END;
$$;
