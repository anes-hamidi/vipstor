-- ============================================================
-- 00003_audit_triggers.sql
-- IMMUTABLE AUDIT LOG & AUTOMATIC TRIGGER TRACKING
-- ============================================================

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

CREATE INDEX IF NOT EXISTS idx_audit_log_target ON audit_log(target_table, target_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_user ON audit_log(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_created ON audit_log(created_at);

-- Generic Audit Trigger Function
CREATE OR REPLACE FUNCTION trigger_audit_log_func()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID;
    v_before JSONB := NULL;
    v_after JSONB := NULL;
    v_target_id UUID := NULL;
BEGIN
    BEGIN
        v_user_id := auth.uid();
    EXCEPTION WHEN OTHERS THEN
        v_user_id := NULL;
    END;

    IF TG_OP = 'INSERT' THEN
        v_after := to_jsonb(NEW);
        BEGIN
            v_target_id := (NEW.id)::UUID;
        EXCEPTION WHEN OTHERS THEN
            v_target_id := NULL;
        END;
    ELSIF TG_OP = 'UPDATE' THEN
        v_before := to_jsonb(OLD);
        v_after := to_jsonb(NEW);
        BEGIN
            v_target_id := (NEW.id)::UUID;
        EXCEPTION WHEN OTHERS THEN
            v_target_id := NULL;
        END;
    ELSIF TG_OP = 'DELETE' THEN
        v_before := to_jsonb(OLD);
        BEGIN
            v_target_id := (OLD.id)::UUID;
        EXCEPTION WHEN OTHERS THEN
            v_target_id := NULL;
        END;
    END IF;

    INSERT INTO audit_log (user_id, action, target_table, target_id, before_state, after_state)
    VALUES (v_user_id, TG_OP, TG_TABLE_NAME, v_target_id, v_before, v_after);

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$;

DROP TRIGGER IF EXISTS trg_audit_users ON users;
CREATE TRIGGER trg_audit_users AFTER INSERT OR UPDATE OR DELETE ON users
FOR EACH ROW EXECUTE FUNCTION trigger_audit_log_func();

DROP TRIGGER IF EXISTS trg_audit_customers ON customers;
CREATE TRIGGER trg_audit_customers AFTER INSERT OR UPDATE OR DELETE ON customers
FOR EACH ROW EXECUTE FUNCTION trigger_audit_log_func();

DROP TRIGGER IF EXISTS trg_audit_product_prices ON product_prices;
CREATE TRIGGER trg_audit_product_prices AFTER INSERT OR UPDATE OR DELETE ON product_prices
FOR EACH ROW EXECUTE FUNCTION trigger_audit_log_func();

DROP TRIGGER IF EXISTS trg_audit_settlements ON settlements;
CREATE TRIGGER trg_audit_settlements AFTER INSERT OR UPDATE OR DELETE ON settlements
FOR EACH ROW EXECUTE FUNCTION trigger_audit_log_func();
