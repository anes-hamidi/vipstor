-- ============================================================================
-- 006_auth_management.sql
-- Password-only account lifecycle for customers and staff.
--
-- Apply ONCE after 005_phase0_security.sql, as the project owner (postgres).
--
-- Design:
--   * Supabase Auth uses email + password. A phone number is mapped to a
--     deterministic synthetic email: <international digits>@vip.algomend.app.
--     No email is ever sent and no SMS provider or OTP is required.
--   * Customer self-registration and password recovery are mediated by the
--     `auth-admin` Edge Function, which uses the service role and stores only
--     a bcrypt hash of a one-time-displayed recovery code.
--   * Staff accounts are created, edited and soft-deleted by a moderator
--     through the same Edge Function. Deleting an account removes the
--     Supabase Auth identity and keeps the public.users row for historical
--     foreign keys.
--
-- Operational prerequisites (not SQL):
--   1. Deploy backend/supabase/functions/auth-admin (see functions/README.md).
--   2. Deploy it with JWT verification disabled; the function validates staff
--      JWTs itself and only enables the public customer actions it needs.
--   3. Keep email confirmation enabled if desired: admin-created auth users
--      are created with `email_confirm = true`, so no confirmation mail is
--      sent or needed.
-- ============================================================================

BEGIN;

SET LOCAL search_path = public, extensions, pg_temp;

-- ----------------------------------------------------------------------------
-- 1. USER ROW LIFECYCLE
-- ----------------------------------------------------------------------------

ALTER TABLE public.users ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS deleted_by UUID;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'users_deleted_by_fkey'
          AND conrelid = 'public.users'::regclass
    ) THEN
        ALTER TABLE public.users
            ADD CONSTRAINT users_deleted_by_fkey
            FOREIGN KEY (deleted_by) REFERENCES public.users(id)
            ON DELETE SET NULL;
    END IF;
END $$;

-- The original schema used a full unique constraint on phone. Soft-deleted
-- accounts must not block reuse of the same phone number, so replace it with
-- a partial unique index over live rows only.
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT c.conname
        FROM pg_constraint c
        WHERE c.conrelid = 'public.users'::regclass
          AND c.contype = 'u'
          AND pg_get_constraintdef(c.oid) LIKE 'UNIQUE (phone)%'
    LOOP
        EXECUTE format('ALTER TABLE public.users DROP CONSTRAINT %I', r.conname);
    END LOOP;
END $$;

DROP INDEX IF EXISTS public.users_phone_key;
CREATE UNIQUE INDEX IF NOT EXISTS uq_users_phone_live
    ON public.users (phone)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_users_deleted_at
    ON public.users (deleted_at);

CREATE INDEX IF NOT EXISTS idx_users_auth_user_id
    ON public.users (auth_user_id)
    WHERE auth_user_id IS NOT NULL;

-- Staff lists filter on this column; 005 revoked the table-level grant and
-- re-granted an explicit column list, so extend that list additively.
GRANT SELECT (deleted_at) ON public.users TO authenticated;

-- auth-admin reads users with the service role and may soft-delete a
-- provisioned row when finalize fails. Keep this explicit so the function does
-- not depend on project-level default grants.
GRANT SELECT, UPDATE ON public.users TO service_role;

-- Deleted rows must never authorize, even if a still-valid JWT outlives the
-- Auth identity or a row is soft-deleted without clearing active.
CREATE OR REPLACE FUNCTION public.current_app_user_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT id
    FROM public.users
    WHERE auth_user_id = auth.uid()
      AND active = TRUE
      AND deleted_at IS NULL
    LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.current_app_role()
RETURNS public.user_role
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT role
    FROM public.users
    WHERE auth_user_id = auth.uid()
      AND active = TRUE
      AND deleted_at IS NULL
    LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.current_customer_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT c.id
    FROM public.customers c
    JOIN public.users u ON u.id = c.user_id
    WHERE u.auth_user_id = auth.uid()
      AND u.active = TRUE
      AND u.deleted_at IS NULL
    LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.current_customer_tier()
RETURNS public.price_tier
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT c.price_tier
    FROM public.customers c
    JOIN public.users u ON u.id = c.user_id
    WHERE u.auth_user_id = auth.uid()
      AND u.active = TRUE
      AND u.deleted_at IS NULL
    LIMIT 1;
$$;

-- ----------------------------------------------------------------------------
-- 2. SYNTHETIC EMAIL HELPERS
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.auth_email_for_phone(p_phone TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
    SELECT regexp_replace(public.normalize_phone(p_phone), '[^0-9]', '', 'g')
           || '@vip.algomend.app';
$$;

CREATE OR REPLACE FUNCTION public.normalize_recovery_code(p_code TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
    SELECT upper(regexp_replace(COALESCE(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
$$;

-- ----------------------------------------------------------------------------
-- 3. AUTH USER -> PUBLIC USER PROVISIONING/LINKING
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.handle_auth_user_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_phone TEXT;
    v_local_phone TEXT;
    v_name TEXT;
    v_role public.user_role := 'customer'::public.user_role;
    v_user public.users%ROWTYPE;
BEGIN
    -- New accounts use a synthetic email. Legacy phone-auth users remain
    -- supported through NEW.phone. User metadata is client-editable, so it is
    -- never used to decide which public phone a JWT may claim.
    v_phone := public.normalize_phone(NEW.phone);

    IF v_phone IS NULL
       AND lower(NEW.email) ~ '^[0-9]{9,15}@vip[.]algomend[.]app$'
    THEN
        v_phone := public.normalize_phone(split_part(NEW.email, '@', 1));
    END IF;

    IF v_phone IS NULL THEN
        RETURN NEW;
    END IF;
    v_local_phone := regexp_replace(v_phone, '^\+213', '0');

    BEGIN
        v_role := COALESCE((NEW.raw_app_meta_data->>'role')::public.user_role,
                           'customer'::public.user_role);
    EXCEPTION WHEN invalid_text_representation THEN
        v_role := 'customer'::public.user_role;
    END;

    v_name := COALESCE(
        NULLIF(trim(NEW.raw_user_meta_data->>'name'), ''),
        NULLIF(trim(NEW.raw_user_meta_data->>'full_name'), ''),
        'زبون'
    );

    SELECT * INTO v_user
    FROM public.users
    WHERE auth_user_id = NEW.id
    LIMIT 1;

    IF FOUND THEN
        IF v_user.deleted_at IS NOT NULL THEN
            RAISE EXCEPTION 'account has been deleted'
                USING ERRCODE = '42501';
        END IF;
        UPDATE public.users
        SET phone = v_local_phone,
            must_change_pin = must_change_pin
                OR (role <> 'customer'::public.user_role AND pin_code IS NULL),
            updated_at = NOW()
        WHERE id = v_user.id;
        -- Existing database role wins; app_metadata is only used for new rows.
        v_role := v_user.role;
    ELSE
        -- Customer rows are never auto-linked: a new Auth identity must not
        -- claim an existing phone merely by knowing it. A trusted server-set
        -- app_metadata role may link an existing *staff* row, which is how the
        -- seeded moderator and legacy staff rows are adopted.
        IF v_role <> 'customer'::public.user_role THEN
            SELECT * INTO v_user
            FROM public.users
            WHERE deleted_at IS NULL
              AND active IS TRUE
              AND auth_user_id IS NULL
              AND role = v_role
              AND phone IN (v_phone, v_local_phone)
            LIMIT 1;
            IF FOUND THEN
                UPDATE public.users
                SET auth_user_id = NEW.id,
                    phone = v_local_phone,
                    must_change_pin = must_change_pin OR (pin_code IS NULL),
                    updated_at = NOW()
                WHERE id = v_user.id;
            END IF;
        END IF;

        IF v_user.id IS NULL THEN
            IF EXISTS (
                SELECT 1 FROM public.users
                WHERE deleted_at IS NULL
                  AND phone IN (v_phone, v_local_phone)
            ) THEN
                RAISE EXCEPTION 'phone number already exists'
                    USING ERRCODE = '23505';
            END IF;

            INSERT INTO public.users (auth_user_id, phone, name, role, active, language, must_change_pin)
            VALUES (NEW.id, v_local_phone, v_name, v_role, TRUE, 'ar',
                    v_role <> 'customer'::public.user_role)
            RETURNING * INTO v_user;
        END IF;
    END IF;

    IF v_role = 'customer'::public.user_role THEN
        INSERT INTO public.customers (user_id, price_tier)
        VALUES (v_user.id, 'wholesale'::public.price_tier)
        ON CONFLICT (user_id) DO NOTHING;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT OR UPDATE OF phone, email, raw_app_meta_data
    ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_auth_user_change();

-- Re-run the safe backfill for legacy phone-auth identities. Existing linked
-- rows are left untouched; soft-deleted rows are never re-linked.
WITH candidates AS (
    SELECT
        u.id AS user_id,
        a.id AS auth_id,
        ROW_NUMBER() OVER (
            PARTITION BY u.id ORDER BY a.created_at NULLS LAST, a.id
        ) AS user_rank,
        ROW_NUMBER() OVER (
            PARTITION BY a.id ORDER BY u.created_at NULLS LAST, u.id
        ) AS auth_rank
    FROM public.users u
    JOIN auth.users a
      ON COALESCE(
             public.normalize_phone(a.phone),
             CASE
                 WHEN lower(a.email) ~ '^[0-9]{9,15}@vip[.]algomend[.]app$'
                 THEN public.normalize_phone(split_part(a.email, '@', 1))
             END
         ) IS NOT NULL
     AND public.normalize_phone(u.phone) = COALESCE(
             public.normalize_phone(a.phone),
             CASE
                 WHEN lower(a.email) ~ '^[0-9]{9,15}@vip[.]algomend[.]app$'
                 THEN public.normalize_phone(split_part(a.email, '@', 1))
             END
         )
    WHERE u.auth_user_id IS NULL
      AND u.deleted_at IS NULL
      AND u.role = CASE
          WHEN a.raw_app_meta_data->>'role'
               IN ('customer', 'driver', 'cashier', 'manager', 'moderator')
          THEN (a.raw_app_meta_data->>'role')::public.user_role
          ELSE 'customer'::public.user_role
      END
      AND NOT EXISTS (
          SELECT 1 FROM public.users linked
          WHERE linked.auth_user_id = a.id
      )
)
UPDATE public.users u
SET auth_user_id = c.auth_id
FROM candidates c
WHERE u.id = c.user_id
  AND u.auth_user_id IS NULL
  AND u.deleted_at IS NULL
  AND c.user_rank = 1
  AND c.auth_rank = 1;

CREATE OR REPLACE FUNCTION public.rpc_bootstrap_my_account()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_phone TEXT;
    v_local_phone TEXT;
    v_name TEXT;
    v_role public.user_role := 'customer'::public.user_role;
    v_user public.users%ROWTYPE;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'not authenticated' USING ERRCODE = '42501';
    END IF;

    -- A soft-deleted staff account must never bootstrap a fresh customer row
    -- using a still-unexpired JWT.
    IF EXISTS (
        SELECT 1 FROM public.users
        WHERE auth_user_id = v_uid
          AND deleted_at IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'account has been deleted' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_user
    FROM public.users
    WHERE auth_user_id = v_uid
      AND deleted_at IS NULL
    LIMIT 1;
    IF FOUND THEN
        IF v_user.role = 'customer'::public.user_role THEN
            INSERT INTO public.customers (user_id, price_tier)
            VALUES (v_user.id, 'wholesale'::public.price_tier)
            ON CONFLICT (user_id) DO NOTHING;
        END IF;
        RETURN jsonb_build_object('user_id', v_user.id, 'role', v_user.role, 'phone', v_user.phone);
    END IF;

    -- Identity comes from verified phone/email claims only. user_metadata is
    -- client-editable and must never choose the public phone for a JWT.
    v_phone := public.normalize_phone(auth.jwt()->>'phone');
    IF v_phone IS NULL
       AND lower(COALESCE(auth.jwt()->>'email', ''))
           ~ '^[0-9]{9,15}@vip[.]algomend[.]app$'
    THEN
        v_phone := public.normalize_phone(split_part(auth.jwt()->>'email', '@', 1));
    END IF;
    IF v_phone IS NULL THEN
        RAISE EXCEPTION 'auth phone claim missing' USING ERRCODE = '42501';
    END IF;
    v_local_phone := regexp_replace(v_phone, '^\+213', '0');

    BEGIN
        v_role := COALESCE((auth.jwt()->'app_metadata'->>'role')::public.user_role,
                           'customer'::public.user_role);
    EXCEPTION WHEN invalid_text_representation THEN
        v_role := 'customer'::public.user_role;
    END;

    v_name := COALESCE(
        NULLIF(trim(auth.jwt()->'user_metadata'->>'name'), ''),
        NULLIF(trim(auth.jwt()->'user_metadata'->>'full_name'), ''),
        'زبون'
    );

    -- Customers never claim an unlinked pre-created row from a JWT claim.
    -- A trusted server-set staff app_metadata role may adopt an existing
    -- unlinked staff row (needed for the seeded moderator).
    IF v_role <> 'customer'::public.user_role THEN
        SELECT * INTO v_user
        FROM public.users
        WHERE deleted_at IS NULL
          AND active IS TRUE
          AND auth_user_id IS NULL
          AND role = v_role
          AND phone IN (v_phone, v_local_phone)
        LIMIT 1;
        IF FOUND THEN
            UPDATE public.users
            SET auth_user_id = v_uid,
                phone = v_local_phone,
                must_change_pin = must_change_pin OR (pin_code IS NULL),
                updated_at = NOW()
            WHERE id = v_user.id;
        END IF;
    END IF;

    IF v_user.id IS NULL THEN
        IF EXISTS (
            SELECT 1 FROM public.users
            WHERE deleted_at IS NULL
              AND phone IN (v_phone, v_local_phone)
        ) THEN
            RAISE EXCEPTION 'phone number already exists' USING ERRCODE = '23505';
        END IF;

        INSERT INTO public.users (
            auth_user_id, phone, name, role, active, language, must_change_pin
        ) VALUES (
            v_uid, v_local_phone, v_name, v_role, TRUE, 'ar',
            v_role <> 'customer'::public.user_role
        )
        RETURNING * INTO v_user;
    END IF;

    IF v_role = 'customer'::public.user_role THEN
        INSERT INTO public.customers (user_id, price_tier)
        VALUES (v_user.id, 'wholesale'::public.price_tier)
        ON CONFLICT (user_id) DO NOTHING;
    END IF;

    RETURN jsonb_build_object('user_id', v_user.id, 'role', v_user.role, 'phone', v_user.phone);
END;
$$;

-- ----------------------------------------------------------------------------
-- 4. CUSTOMER RECOVERY CODES & AUTH RATE LIMITS
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.customer_recovery (
    user_id          UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
    code_hash        TEXT NOT NULL,
    failed_attempts  INTEGER NOT NULL DEFAULT 0,
    last_failed_at   TIMESTAMPTZ,
    locked_until     TIMESTAMPTZ,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.customer_recovery ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.customer_recovery FROM PUBLIC, anon, authenticated;

CREATE TABLE IF NOT EXISTS public.auth_rate_limits (
    bucket             TEXT PRIMARY KEY,
    attempt_count      INTEGER NOT NULL DEFAULT 0,
    window_started_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    locked_until       TIMESTAMPTZ,
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.auth_rate_limits ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.auth_rate_limits FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.rpc_auth_rate_limit(
    p_bucket TEXT,
    p_max INTEGER,
    p_window_seconds INTEGER,
    p_lock_seconds INTEGER
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_row public.auth_rate_limits%ROWTYPE;
    v_now TIMESTAMPTZ := NOW();
    v_retry INTEGER;
BEGIN
    IF p_bucket IS NULL OR trim(p_bucket) = ''
       OR p_max IS NULL OR p_max < 1
       OR p_window_seconds IS NULL OR p_window_seconds < 1
       OR p_lock_seconds IS NULL OR p_lock_seconds < 1
    THEN
        RAISE EXCEPTION 'invalid rate limit parameters' USING ERRCODE = '22023';
    END IF;

    DELETE FROM public.auth_rate_limits
    WHERE updated_at < v_now - INTERVAL '7 days';

    INSERT INTO public.auth_rate_limits (bucket)
    VALUES (trim(p_bucket))
    ON CONFLICT (bucket) DO NOTHING;

    SELECT * INTO v_row
    FROM public.auth_rate_limits
    WHERE bucket = trim(p_bucket)
    FOR UPDATE;

    IF v_row.locked_until IS NOT NULL AND v_row.locked_until > v_now THEN
        v_retry := GREATEST(
            1,
            CEIL(EXTRACT(EPOCH FROM (v_row.locked_until - v_now)))::INTEGER
        );
        RETURN jsonb_build_object(
            'allowed', FALSE,
            'locked', TRUE,
            'retry_after', v_retry
        );
    END IF;

    IF v_row.window_started_at <= v_now - make_interval(secs => p_window_seconds)
       OR v_row.locked_until IS NOT NULL
    THEN
        UPDATE public.auth_rate_limits
        SET attempt_count = 0,
            window_started_at = v_now,
            locked_until = NULL,
            updated_at = v_now
        WHERE bucket = v_row.bucket
        RETURNING * INTO v_row;
    END IF;

    IF v_row.attempt_count >= p_max THEN
        UPDATE public.auth_rate_limits
        SET locked_until = v_now + make_interval(secs => p_lock_seconds),
            updated_at = v_now
        WHERE bucket = v_row.bucket;

        RETURN jsonb_build_object(
            'allowed', FALSE,
            'locked', TRUE,
            'retry_after', p_lock_seconds
        );
    END IF;

    UPDATE public.auth_rate_limits
    SET attempt_count = attempt_count + 1,
        updated_at = v_now
    WHERE bucket = v_row.bucket;

    RETURN jsonb_build_object(
        'allowed', TRUE,
        'remaining', GREATEST(0, p_max - v_row.attempt_count - 1)
    );
END;
$$;

-- ----------------------------------------------------------------------------
-- 5. AUTH-ADMIN SERVICE-ROLE RPCs
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.rpc_auth_verify_moderator_pin(
    p_auth_user_id UUID,
    p_pin TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user public.users%ROWTYPE;
    v_result JSONB;
BEGIN
    SELECT * INTO v_user
    FROM public.users
    WHERE auth_user_id = p_auth_user_id
      AND deleted_at IS NULL
    LIMIT 1;

    IF NOT FOUND
       OR v_user.role <> 'moderator'::public.user_role
       OR v_user.active IS NOT TRUE
    THEN
        RETURN jsonb_build_object('valid', FALSE, 'message', 'غير مصرح');
    END IF;

    v_result := public.internal_verify_user_pin(v_user.id, p_pin);
    RETURN v_result || jsonb_build_object('app_user_id', v_user.id);
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_auth_customer_register_finalize(
    p_auth_user_id UUID,
    p_phone TEXT,
    p_name TEXT,
    p_recovery_code TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_phone TEXT := public.normalize_phone(p_phone);
    v_local_phone TEXT;
    v_name TEXT := NULLIF(trim(COALESCE(p_name, '')), '');
    v_code TEXT := public.normalize_recovery_code(p_recovery_code);
    v_user public.users%ROWTYPE;
    v_customer_id UUID;
BEGIN
    IF p_auth_user_id IS NULL OR v_phone IS NULL THEN
        RAISE EXCEPTION 'invalid registration payload' USING ERRCODE = '22023';
    END IF;
    v_local_phone := regexp_replace(v_phone, '^\+213', '0');
    IF v_local_phone !~ '^0[5-7][0-9]{8}$' THEN
        RAISE EXCEPTION 'invalid Algerian phone number' USING ERRCODE = '22023';
    END IF;
    IF v_name IS NULL OR length(v_name) < 2 OR length(v_name) > 100 THEN
        RAISE EXCEPTION 'invalid customer name' USING ERRCODE = '22023';
    END IF;
    IF length(v_code) < 8 OR length(v_code) > 64 THEN
        RAISE EXCEPTION 'invalid recovery code' USING ERRCODE = '22023';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM auth.users a
        WHERE a.id = p_auth_user_id
          AND lower(a.email) = lower(public.auth_email_for_phone(v_local_phone))
          AND COALESCE(a.raw_app_meta_data->>'role', 'customer') = 'customer'
    ) THEN
        RAISE EXCEPTION 'auth identity does not match the phone number'
            USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_user
    FROM public.users
    WHERE auth_user_id = p_auth_user_id
    LIMIT 1;

    IF FOUND THEN
        IF v_user.deleted_at IS NOT NULL
           OR v_user.active IS NOT TRUE
           OR v_user.role <> 'customer'::public.user_role
        THEN
            RAISE EXCEPTION 'account cannot be registered as a customer'
                USING ERRCODE = '42501';
        END IF;
        UPDATE public.users
        SET name = v_name,
            phone = v_local_phone,
            updated_at = NOW()
        WHERE id = v_user.id;
    ELSE
        -- Never hijack an unlinked pre-created customer row. Knowing a phone
        -- number is not proof that the caller owns that account.
        IF EXISTS (
            SELECT 1 FROM public.users
            WHERE phone = v_local_phone
              AND deleted_at IS NULL
        ) THEN
            RAISE EXCEPTION 'phone number already exists'
                USING ERRCODE = '23505';
        END IF;

        INSERT INTO public.users (
            auth_user_id, phone, name, role, active, language, must_change_pin
        ) VALUES (
            p_auth_user_id, v_local_phone, v_name, 'customer', TRUE, 'ar', FALSE
        )
        RETURNING * INTO v_user;
    END IF;

    INSERT INTO public.customers (user_id, price_tier)
    VALUES (v_user.id, 'wholesale'::public.price_tier)
    ON CONFLICT (user_id) DO UPDATE
    SET updated_at = NOW()
    RETURNING id INTO v_customer_id;

    INSERT INTO public.customer_recovery (
        user_id, code_hash, failed_attempts, last_failed_at, locked_until, updated_at
    ) VALUES (
        v_user.id, crypt(v_code, gen_salt('bf', 10)), 0, NULL, NULL, NOW()
    )
    ON CONFLICT (user_id) DO UPDATE
    SET code_hash = EXCLUDED.code_hash,
        failed_attempts = 0,
        last_failed_at = NULL,
        locked_until = NULL,
        updated_at = NOW();

    INSERT INTO public.audit_log (
        user_id, action, target_table, target_id, after_state
    ) VALUES (
        v_user.id, 'CUSTOMER_REGISTERED', 'users', v_user.id,
        jsonb_build_object('phone', v_local_phone, 'method', 'password')
    );

    RETURN jsonb_build_object(
        'status', 'success',
        'user_id', v_user.id,
        'customer_id', v_customer_id,
        'phone', v_local_phone
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_auth_customer_recovery_verify(
    p_phone TEXT,
    p_recovery_code TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_e164 TEXT := public.normalize_phone(p_phone);
    v_local TEXT;
    v_code TEXT := public.normalize_recovery_code(p_recovery_code);
    v_user_id UUID;
    v_auth_user_id UUID;
    v_hash TEXT;
    v_failed INTEGER;
    v_locked_until TIMESTAMPTZ;
    v_now TIMESTAMPTZ := NOW();
    v_next_failed INTEGER;
BEGIN
    IF v_e164 IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'code', 'invalid',
            'error', 'رقم الهاتف أو رمز الاستعادة غير صحيح'
        );
    END IF;
    v_local := regexp_replace(v_e164, '^\+213', '0');

    SELECT u.id, u.auth_user_id, r.code_hash, r.failed_attempts, r.locked_until
    INTO v_user_id, v_auth_user_id, v_hash, v_failed, v_locked_until
    FROM public.users u
    JOIN public.customer_recovery r ON r.user_id = u.id
    WHERE u.phone IN (v_local, v_e164)
      AND u.role = 'customer'::public.user_role
      AND u.active IS TRUE
      AND u.deleted_at IS NULL
      AND u.auth_user_id IS NOT NULL
      -- Recovery codes are only issued for synthetic-email customer
      -- identities. This prevents a recovery record from ever resetting a
      -- staff Auth identity that happened to share the phone number.
      AND EXISTS (
          SELECT 1
          FROM auth.users a
          WHERE a.id = u.auth_user_id
            AND lower(a.email) =
                lower(public.auth_email_for_phone(u.phone))
            AND COALESCE(a.raw_app_meta_data->>'role', 'customer') =
                'customer'
      )
    LIMIT 1
    FOR UPDATE OF u, r;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'code', 'invalid',
            'error', 'رقم الهاتف أو رمز الاستعادة غير صحيح'
        );
    END IF;

    IF v_locked_until IS NOT NULL AND v_locked_until > v_now THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'code', 'locked',
            'error', 'تم قفل الاستعادة مؤقتاً بعد محاولات كثيرة. حاول لاحقاً.',
            'retry_after', GREATEST(
                1,
                CEIL(EXTRACT(EPOCH FROM (v_locked_until - v_now)))::INTEGER
            )
        );
    END IF;

    IF v_locked_until IS NOT NULL THEN
        v_failed := 0;
        UPDATE public.customer_recovery
        SET failed_attempts = 0,
            locked_until = NULL,
            updated_at = v_now
        WHERE user_id = v_user_id;
    END IF;

    IF length(v_code) < 8 OR crypt(v_code, v_hash) <> v_hash THEN
        v_next_failed := COALESCE(v_failed, 0) + 1;
        IF v_next_failed >= 5 THEN
            UPDATE public.customer_recovery
            SET failed_attempts = 0,
                last_failed_at = v_now,
                locked_until = v_now + INTERVAL '15 minutes',
                updated_at = v_now
            WHERE user_id = v_user_id;

            RETURN jsonb_build_object(
                'status', 'error',
                'code', 'locked',
                'error', 'تم قفل الاستعادة مؤقتاً بعد محاولات كثيرة. حاول بعد 15 دقيقة.',
                'retry_after', 900
            );
        END IF;

        UPDATE public.customer_recovery
        SET failed_attempts = v_next_failed,
            last_failed_at = v_now,
            updated_at = v_now
        WHERE user_id = v_user_id;

        RETURN jsonb_build_object(
            'status', 'error',
            'code', 'invalid',
            'error', 'رقم الهاتف أو رمز الاستعادة غير صحيح'
        );
    END IF;

    UPDATE public.customer_recovery
    SET failed_attempts = 0,
        locked_until = NULL,
        updated_at = v_now
    WHERE user_id = v_user_id;

    RETURN jsonb_build_object(
        'status', 'success',
        'user_id', v_user_id,
        'auth_user_id', v_auth_user_id
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_auth_customer_recovery_rotate(
    p_auth_user_id UUID,
    p_user_id UUID,
    p_new_recovery_code TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_code TEXT := public.normalize_recovery_code(p_new_recovery_code);
    v_user public.users%ROWTYPE;
BEGIN
    IF length(v_code) < 8 OR length(v_code) > 64 THEN
        RAISE EXCEPTION 'invalid recovery code' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_user
    FROM public.users
    WHERE id = p_user_id
      AND auth_user_id = p_auth_user_id
      AND role = 'customer'::public.user_role
      AND active IS TRUE
      AND deleted_at IS NULL
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'customer account not found' USING ERRCODE = '42501';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM auth.users a
        WHERE a.id = p_auth_user_id
          AND lower(a.email) = lower(public.auth_email_for_phone(v_user.phone))
          AND COALESCE(a.raw_app_meta_data->>'role', 'customer') = 'customer'
    ) THEN
        RAISE EXCEPTION 'customer auth identity does not match'
            USING ERRCODE = '42501';
    END IF;

    UPDATE public.customer_recovery
    SET code_hash = crypt(v_code, gen_salt('bf', 10)),
        failed_attempts = 0,
        last_failed_at = NULL,
        locked_until = NULL,
        updated_at = NOW()
    WHERE user_id = v_user.id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'recovery record not found' USING ERRCODE = 'P0002';
    END IF;

    INSERT INTO public.audit_log (
        user_id, action, target_table, target_id, after_state
    ) VALUES (
        v_user.id, 'CUSTOMER_PASSWORD_RESET', 'users', v_user.id,
        jsonb_build_object('method', 'recovery_code')
    );

    RETURN jsonb_build_object('status', 'success');
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_auth_staff_create_finalize(
    p_actor_id UUID,
    p_auth_user_id UUID,
    p_name TEXT,
    p_phone TEXT,
    p_role public.user_role,
    p_initial_pin TEXT,
    p_language TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_actor public.users%ROWTYPE;
    v_user public.users%ROWTYPE;
    v_phone TEXT := public.normalize_phone(p_phone);
    v_local_phone TEXT;
    v_name TEXT := NULLIF(trim(COALESCE(p_name, '')), '');
    v_pin TEXT := NULLIF(trim(COALESCE(p_initial_pin, '')), '');
    v_language TEXT := COALESCE(NULLIF(trim(p_language), ''), 'ar');
BEGIN
    SELECT * INTO v_actor
    FROM public.users
    WHERE id = p_actor_id
      AND role = 'moderator'::public.user_role
      AND active IS TRUE
      AND deleted_at IS NULL
    LIMIT 1;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'forbidden: moderator only' USING ERRCODE = '42501';
    END IF;

    IF p_auth_user_id IS NULL OR v_phone IS NULL THEN
        RAISE EXCEPTION 'invalid staff payload' USING ERRCODE = '22023';
    END IF;
    v_local_phone := regexp_replace(v_phone, '^\+213', '0');
    IF v_local_phone !~ '^0[5-7][0-9]{8}$' THEN
        RAISE EXCEPTION 'invalid Algerian phone number' USING ERRCODE = '22023';
    END IF;
    IF v_name IS NULL OR length(v_name) < 2 OR length(v_name) > 100 THEN
        RAISE EXCEPTION 'invalid staff name' USING ERRCODE = '22023';
    END IF;
    IF p_role IS NULL
       OR p_role NOT IN ('moderator', 'manager', 'cashier', 'driver')
    THEN
        RAISE EXCEPTION 'invalid staff role' USING ERRCODE = '22023';
    END IF;
    IF v_pin IS NULL OR v_pin !~ '^[0-9]{4,8}$' THEN
        RAISE EXCEPTION 'invalid initial pin' USING ERRCODE = '22023';
    END IF;
    IF v_language NOT IN ('ar', 'fr') THEN
        RAISE EXCEPTION 'invalid language' USING ERRCODE = '22023';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM auth.users a
        WHERE a.id = p_auth_user_id
          AND lower(a.email) = lower(public.auth_email_for_phone(v_local_phone))
          AND COALESCE(a.raw_app_meta_data->>'role', '') = p_role::text
    ) THEN
        RAISE EXCEPTION 'auth identity does not match the phone number'
            USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_user
    FROM public.users
    WHERE auth_user_id = p_auth_user_id
    LIMIT 1;

    IF FOUND THEN
        IF v_user.deleted_at IS NOT NULL THEN
            RAISE EXCEPTION 'account has been deleted' USING ERRCODE = '42501';
        END IF;
        UPDATE public.users
        SET name = v_name,
            phone = v_local_phone,
            role = p_role,
            active = TRUE,
            language = v_language,
            pin_code = crypt(v_pin, gen_salt('bf', 10)),
            must_change_pin = TRUE,
            deleted_at = NULL,
            deleted_by = NULL,
            updated_at = NOW()
        WHERE id = v_user.id
        RETURNING * INTO v_user;
    ELSE
        IF EXISTS (
            SELECT 1 FROM public.users
            WHERE phone = v_local_phone
              AND deleted_at IS NULL
        ) THEN
            RAISE EXCEPTION 'phone number already exists'
                USING ERRCODE = '23505';
        END IF;

        INSERT INTO public.users (
            auth_user_id, phone, name, role, active, language, pin_code,
            must_change_pin
        ) VALUES (
            p_auth_user_id, v_local_phone, v_name, p_role, TRUE, v_language,
            crypt(v_pin, gen_salt('bf', 10)), TRUE
        )
        RETURNING * INTO v_user;
    END IF;

    INSERT INTO public.audit_log (
        user_id, action, target_table, target_id, after_state
    ) VALUES (
        v_actor.id, 'STAFF_CREATED', 'users', v_user.id,
        jsonb_build_object('role', p_role, 'phone', v_local_phone)
    );

    RETURN jsonb_build_object(
        'status', 'success',
        'user_id', v_user.id,
        'phone', v_user.phone,
        'role', v_user.role
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_auth_staff_delete_prepare(
    p_actor_id UUID,
    p_target_user_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor public.users%ROWTYPE;
    v_target public.users%ROWTYPE;
    v_other_moderators INTEGER;
BEGIN
    SELECT * INTO v_actor
    FROM public.users
    WHERE id = p_actor_id
      AND role = 'moderator'::public.user_role
      AND active IS TRUE
      AND deleted_at IS NULL
    LIMIT 1;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'forbidden: moderator only' USING ERRCODE = '42501';
    END IF;

    IF p_target_user_id = p_actor_id THEN
        RAISE EXCEPTION 'a moderator cannot delete their own account'
            USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_target
    FROM public.users
    WHERE id = p_target_user_id
    FOR UPDATE;

    IF NOT FOUND OR v_target.deleted_at IS NOT NULL THEN
        RAISE EXCEPTION 'staff account not found' USING ERRCODE = 'P0002';
    END IF;
    IF v_target.role = 'customer'::public.user_role THEN
        RAISE EXCEPTION 'only staff accounts can be deleted here' USING ERRCODE = '42501';
    END IF;

    IF v_target.role = 'moderator'::public.user_role
       AND v_target.active IS TRUE
    THEN
        SELECT COUNT(*) INTO v_other_moderators
        FROM public.users
        WHERE role = 'moderator'::public.user_role
          AND active IS TRUE
          AND deleted_at IS NULL
          AND id <> v_target.id;

        IF v_other_moderators = 0 THEN
            RAISE EXCEPTION 'cannot delete the last active moderator'
                USING ERRCODE = '42501';
        END IF;
    END IF;

    UPDATE public.users
    SET active = FALSE,
        pin_code = NULL,
        must_change_pin = FALSE,
        deleted_at = NOW(),
        deleted_by = v_actor.id,
        updated_at = NOW()
    WHERE id = v_target.id;

    INSERT INTO public.audit_log (
        user_id, action, target_table, target_id, before_state
    ) VALUES (
        v_actor.id, 'STAFF_DELETED', 'users', v_target.id,
        jsonb_build_object(
            'role', v_target.role,
            'phone', v_target.phone,
            'active', v_target.active
        )
    );

    RETURN jsonb_build_object(
        'status', 'success',
        'user_id', v_target.id,
        'auth_user_id', v_target.auth_user_id
    );
END;
$$;

-- ----------------------------------------------------------------------------
-- 6. GRANTS
-- ----------------------------------------------------------------------------

-- Staff creation must go through auth-admin so that the Supabase Auth
-- identity is provisioned atomically. Revoke the legacy public-row-only path.
REVOKE EXECUTE ON FUNCTION public.rpc_create_staff_member(
    UUID, TEXT, VARCHAR, VARCHAR, public.user_role, TEXT, VARCHAR
) FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.rpc_auth_rate_limit(TEXT, INTEGER, INTEGER, INTEGER)
    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rpc_auth_verify_moderator_pin(UUID, TEXT)
    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rpc_auth_customer_register_finalize(UUID, TEXT, TEXT, TEXT)
    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rpc_auth_customer_recovery_verify(TEXT, TEXT)
    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rpc_auth_customer_recovery_rotate(UUID, UUID, TEXT)
    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rpc_auth_staff_create_finalize(
    UUID, UUID, TEXT, TEXT, public.user_role, TEXT, TEXT
) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rpc_auth_staff_delete_prepare(UUID, UUID)
    FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.rpc_auth_rate_limit(TEXT, INTEGER, INTEGER, INTEGER)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.rpc_auth_verify_moderator_pin(UUID, TEXT)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.rpc_auth_customer_register_finalize(UUID, TEXT, TEXT, TEXT)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.rpc_auth_customer_recovery_verify(TEXT, TEXT)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.rpc_auth_customer_recovery_rotate(UUID, UUID, TEXT)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.rpc_auth_staff_create_finalize(
    UUID, UUID, TEXT, TEXT, public.user_role, TEXT, TEXT
) TO service_role;
GRANT EXECUTE ON FUNCTION public.rpc_auth_staff_delete_prepare(UUID, UUID)
    TO service_role;

INSERT INTO public.schema_migrations (version, description)
VALUES
    ('00036', '00036 - driver location RPC hardening'),
    ('00037', '00037 - password-only auth management, recovery codes, staff lifecycle')
ON CONFLICT (version) DO NOTHING;

NOTIFY pgrst, 'reload schema';

COMMIT;
