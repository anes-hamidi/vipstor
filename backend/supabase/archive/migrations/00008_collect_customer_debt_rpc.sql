-- ============================================================
-- 00008_collect_customer_debt_rpc.sql
-- ATOMIC CUSTOMER DEBT COLLECTION & PAYMENT POSTING
-- ============================================================

CREATE OR REPLACE FUNCTION rpc_collect_customer_debt(
    p_cashier_id UUID,
    p_customer_id UUID,
    p_amount BIGINT,              -- In centimes (> 0)
    p_method payment_method DEFAULT 'cash',
    p_notes TEXT DEFAULT NULL,
    p_client_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_customer customers%ROWTYPE;
    v_payment_id UUID := gen_random_uuid();
    v_previous_balance BIGINT := 0;
    v_new_balance BIGINT := 0;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'Debt collection amount must be greater than zero.';
    END IF;

    SELECT * INTO v_customer FROM customers WHERE id = p_customer_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Customer % not found.', p_customer_id;
    END IF;

    -- Fetch current debt balance
    SELECT COALESCE(current_balance, 0) INTO v_previous_balance
    FROM view_customer_balance
    WHERE customer_id = p_customer_id;

    -- 1. Insert Payment Record
    INSERT INTO payments (
        id,
        order_id,
        customer_id,
        amount,
        method,
        received_by,
        status,
        client_id
    )
    VALUES (
        v_payment_id,
        NULL,
        p_customer_id,
        p_amount,
        p_method,
        p_cashier_id,
        'settled',
        p_client_id
    );

    -- 2. Insert Negative Amount into Customer Ledger (- reduces debt)
    INSERT INTO customer_ledger (
        id,
        customer_id,
        amount_change,
        ref_type,
        ref_id,
        notes
    )
    VALUES (
        gen_random_uuid(),
        p_customer_id,
        -p_amount,
        'payment',
        v_payment_id,
        COALESCE(p_notes, 'Debt repayment collected at cashier counter')
    );

    -- Calculate new balance
    v_new_balance := v_previous_balance - p_amount;

    RETURN jsonb_build_object(
        'status', 'success',
        'payment_id', v_payment_id,
        'customer_id', p_customer_id,
        'paid_amount', p_amount,
        'previous_balance', v_previous_balance,
        'new_balance', v_new_balance,
        'method', p_method,
        'timestamp', NOW()
    );
END;
$$;
