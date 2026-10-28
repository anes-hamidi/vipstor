-- ============================================================================
-- 005_phase0_security.sql
-- Phase 0 security hardening: real Supabase Auth, JWT-derived actors,
-- RLS replacement, grant lockdown, secure views/storage, hardened RPCs.
--
-- Apply ONCE after 004_migration_00036.sql, as the project owner (postgres).
--
-- Operational prerequisites (not SQL):
--   1. Enable Phone auth in Supabase Auth.
--   2. Configure an SMS provider for customer/staff OTP.
--   3. Provision staff auth users with phone + password, and put the app role
--      in app_metadata: { "role": "moderator" | "manager" | "cashier" | "driver" }.
--      Existing public.users rows are linked by phone by the trigger/backfill.
-- ============================================================================

BEGIN;

-- Supabase installs pgcrypto in the `extensions` schema on most projects.
-- Keep it resolvable for the legacy-token hash migration below without
-- weakening any function's own search_path.
SET LOCAL search_path = public, extensions, pg_temp;

-- ----------------------------------------------------------------------------
-- 1. AUTH LINKAGE + SECRET STORAGE COLUMNS
-- ----------------------------------------------------------------------------

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS auth_user_id UUID,
    ADD COLUMN IF NOT EXISTS must_change_pin BOOLEAN NOT NULL DEFAULT FALSE;

-- Status changes need a monotonic cursor for delta sync and for the hardened
-- order RPCs below.
ALTER TABLE public.orders
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'users_auth_user_id_fkey'
          AND conrelid = 'public.users'::regclass
    ) THEN
        ALTER TABLE public.users
            ADD CONSTRAINT users_auth_user_id_fkey
            FOREIGN KEY (auth_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
    END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_users_auth_user_id
    ON public.users(auth_user_id)
    WHERE auth_user_id IS NOT NULL;

ALTER TABLE public.customers
    ADD COLUMN IF NOT EXISTS device_token_hash TEXT,
    ADD COLUMN IF NOT EXISTS device_token_rotated_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS device_token_revoked_at TIMESTAMPTZ;

-- Migrate any legacy plaintext device token to a hash, then destroy plaintext.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'customers'
          AND column_name = 'device_token'
    ) THEN
        EXECUTE $mig$
            UPDATE public.customers
            SET device_token_hash = encode(sha256(convert_to(device_token, 'UTF8')), 'hex'),
                device_token_rotated_at = COALESCE(device_token_rotated_at, NOW())
            WHERE device_token IS NOT NULL AND trim(device_token) <> ''
              AND device_token_hash IS NULL
        $mig$;
        EXECUTE 'UPDATE public.customers SET device_token = NULL WHERE device_token IS NOT NULL';
        EXECUTE 'DROP INDEX IF EXISTS public.idx_customers_device_token';
    END IF;
END $$;

-- A physical device token may only belong to one customer. If legacy data
-- contains duplicates, keep the most recently rotated row and revoke the rest
-- before creating the unique index.
WITH ranked AS (
    SELECT id,
           ROW_NUMBER() OVER (
               PARTITION BY device_token_hash
               ORDER BY updated_at DESC NULLS LAST, id
           ) AS rn
    FROM public.customers
    WHERE device_token_hash IS NOT NULL
)
UPDATE public.customers c
SET device_token_hash = NULL,
    device_token_revoked_at = COALESCE(c.device_token_revoked_at, NOW())
FROM ranked r
WHERE c.id = r.id AND r.rn > 1;

CREATE UNIQUE INDEX IF NOT EXISTS uq_customers_device_token_hash
    ON public.customers(device_token_hash)
    WHERE device_token_hash IS NOT NULL;

-- ----------------------------------------------------------------------------
-- 2. PHONE NORMALIZATION + JWT ACTOR HELPERS
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.normalize_phone(p_phone TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE
        WHEN p_phone IS NULL OR trim(p_phone) = '' THEN NULL
        WHEN regexp_replace(p_phone, '[^0-9+]', '', 'g') LIKE '+%'
            THEN regexp_replace(p_phone, '[^0-9+]', '', 'g')
        WHEN regexp_replace(p_phone, '[^0-9]', '', 'g') LIKE '00%'
            THEN '+' || substr(regexp_replace(p_phone, '[^0-9]', '', 'g'), 3)
        WHEN regexp_replace(p_phone, '[^0-9]', '', 'g') LIKE '213%'
            THEN '+' || regexp_replace(p_phone, '[^0-9]', '', 'g')
        WHEN regexp_replace(p_phone, '[^0-9]', '', 'g') ~ '^0[5-7][0-9]{8}$'
            THEN '+213' || substr(regexp_replace(p_phone, '[^0-9]', '', 'g'), 2)
        ELSE regexp_replace(p_phone, '[^0-9+]', '', 'g')
    END;
$$;

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
    LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.get_auth_role()
RETURNS public.user_role
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT public.current_app_role();
$$;

CREATE OR REPLACE FUNCTION public.is_staff()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT COALESCE(public.current_app_role() IN
        ('moderator'::public.user_role, 'manager'::public.user_role,
         'cashier'::public.user_role, 'driver'::public.user_role), FALSE);
$$;

CREATE OR REPLACE FUNCTION public.is_management()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT COALESCE(public.current_app_role() IN
        ('moderator'::public.user_role, 'manager'::public.user_role), FALSE);
$$;

CREATE OR REPLACE FUNCTION public.is_cashier_or_above()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT COALESCE(public.current_app_role() IN
        ('moderator'::public.user_role, 'manager'::public.user_role,
         'cashier'::public.user_role), FALSE);
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
    LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.can_access_order(p_order_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.orders o
        WHERE o.id = p_order_id
          AND (
              public.current_app_role() IN
                  ('moderator'::public.user_role, 'manager'::public.user_role,
                   'cashier'::public.user_role)
              OR (public.current_app_role() = 'driver'::public.user_role
                  AND o.driver_id = public.current_app_user_id())
              OR (o.customer_id IS NOT NULL
                  AND o.customer_id = public.current_customer_id())
          )
    );
$$;

CREATE OR REPLACE FUNCTION public.can_access_customer(p_customer_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.customers c
        WHERE c.id = p_customer_id
          AND (public.is_cashier_or_above() OR c.id = public.current_customer_id())
    );
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
    v_existing_role public.user_role;
BEGIN
    v_phone := public.normalize_phone(NEW.phone);
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
       OR (length(regexp_replace(v_phone, '\D', '', 'g')) >= 9
           AND phone IN (v_phone, v_local_phone))
    ORDER BY (auth_user_id = NEW.id) DESC
    LIMIT 1;

    IF FOUND THEN
        -- Never let a new auth identity steal a public row that is already
        -- linked to another auth user (for example after a phone-number
        -- change reused an old number). Refuse the auth write instead.
        IF v_user.auth_user_id IS NOT NULL AND v_user.auth_user_id <> NEW.id THEN
            RAISE EXCEPTION 'phone number is already linked to another auth identity'
                USING ERRCODE = '23505';
        END IF;
        v_existing_role := v_user.role;
        UPDATE public.users
        SET auth_user_id = NEW.id,
            phone = v_local_phone,
            must_change_pin = must_change_pin
                OR (role <> 'customer'::public.user_role AND pin_code IS NULL),
            updated_at = NOW()
        WHERE id = v_user.id;
        -- Existing database role wins; app_metadata is only used for new rows.
        v_role := v_existing_role;
    ELSE
        INSERT INTO public.users (auth_user_id, phone, name, role, active, language, must_change_pin)
        VALUES (NEW.id, v_local_phone, v_name, v_role, TRUE, 'ar',
                v_role <> 'customer'::public.user_role)
        RETURNING * INTO v_user;
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
    AFTER INSERT OR UPDATE OF phone, raw_user_meta_data, raw_app_meta_data
    ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_auth_user_change();

-- Backfill links for auth users that already exist. Rank both sides so a
-- formatting collision cannot assign the same auth identity to two public
-- users (the unique index would otherwise abort the migration).
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
      ON a.phone IS NOT NULL
     AND (
          public.normalize_phone(a.phone) = public.normalize_phone(u.phone)
          OR right(regexp_replace(a.phone, '\D', '', 'g'), 9) =
             right(regexp_replace(u.phone, '\D', '', 'g'), 9)
     )
    WHERE u.auth_user_id IS NULL
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
  AND c.user_rank = 1
  AND c.auth_rank = 1;

INSERT INTO public.customers (user_id, price_tier)
SELECT u.id, 'wholesale'::public.price_tier
FROM public.users u
WHERE u.role = 'customer'::public.user_role
ON CONFLICT (user_id) DO NOTHING;

-- Staff rows linked by backfill without a PIN must establish one before any
-- PIN-checked operation can be used.
UPDATE public.users
SET must_change_pin = TRUE, updated_at = NOW()
WHERE auth_user_id IS NOT NULL
  AND role <> 'customer'::public.user_role
  AND pin_code IS NULL;

-- Creates/links the current auth identity when the auth trigger did not run.
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

    SELECT * INTO v_user FROM public.users WHERE auth_user_id = v_uid LIMIT 1;
    IF FOUND THEN
        IF v_user.role = 'customer'::public.user_role THEN
            INSERT INTO public.customers (user_id, price_tier)
            VALUES (v_user.id, 'wholesale'::public.price_tier)
            ON CONFLICT (user_id) DO NOTHING;
        END IF;
        RETURN jsonb_build_object('user_id', v_user.id, 'role', v_user.role, 'phone', v_user.phone);
    END IF;

    v_phone := public.normalize_phone(auth.jwt()->>'phone');
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

    SELECT * INTO v_user
    FROM public.users
    WHERE length(regexp_replace(v_phone, '\D', '', 'g')) >= 9
      AND phone IN (v_phone, v_local_phone)
    LIMIT 1;

    IF FOUND THEN
        IF v_user.auth_user_id IS NOT NULL AND v_user.auth_user_id <> v_uid THEN
            RAISE EXCEPTION 'phone number is already linked to another auth identity'
                USING ERRCODE = '23505';
        END IF;
        v_role := v_user.role;
        UPDATE public.users
        SET auth_user_id = v_uid,
            phone = v_local_phone,
            must_change_pin = must_change_pin
                OR (role <> 'customer'::public.user_role AND pin_code IS NULL),
            updated_at = NOW()
        WHERE id = v_user.id;
    ELSE
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
-- 4. REPLACE ALL LEGACY POLICIES WITH AUTHENTICATED/OWNERSHIP POLICIES
-- ----------------------------------------------------------------------------

DO $$
DECLARE r RECORD;
BEGIN
    FOR r IN
        SELECT schemaname, tablename, policyname
        FROM pg_policies
        WHERE schemaname = 'public'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I',
                       r.policyname, r.schemaname, r.tablename);
    END LOOP;
END $$;

ALTER TABLE public.users                      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.addresses                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_barcodes           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_prices             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchases                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_items             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders                     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items                ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stock_ledger               ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_ledger            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_ledger            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.settlements                ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallet_entries             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.driver_locations           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.driver_location_events     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_shifts                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.permissions                ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.role_permissions           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_versions               ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.failed_operations          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_balance_snapshot  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.driver_wallet_snapshot     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_balance_snapshot  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_stock_snapshot     ENABLE ROW LEVEL SECURITY;

-- users
CREATE POLICY users_select_self_or_staff ON public.users
    FOR SELECT TO authenticated
    USING (
        id = public.current_app_user_id()
        OR public.is_cashier_or_above()
        -- Drivers may resolve staff names on their own settlements, but they
        -- must not be able to enumerate customer phone numbers.
        OR (public.current_app_role() = 'driver'::public.user_role
            AND role <> 'customer'::public.user_role)
    );

-- customers
CREATE POLICY customers_select_self_or_staff ON public.customers
    FOR SELECT TO authenticated
    USING (id = public.current_customer_id() OR public.is_cashier_or_above());

-- addresses
CREATE POLICY addresses_select_self_or_staff ON public.addresses
    FOR SELECT TO authenticated
    USING (customer_id = public.current_customer_id() OR public.is_cashier_or_above());

CREATE POLICY addresses_insert_self ON public.addresses
    FOR INSERT TO authenticated
    WITH CHECK (customer_id = public.current_customer_id());

CREATE POLICY addresses_update_self ON public.addresses
    FOR UPDATE TO authenticated
    USING (customer_id = public.current_customer_id())
    WITH CHECK (customer_id = public.current_customer_id());

CREATE POLICY addresses_delete_self ON public.addresses
    FOR DELETE TO authenticated
    USING (customer_id = public.current_customer_id());

-- catalogue
CREATE POLICY products_select ON public.products
    FOR SELECT TO authenticated
    USING (active = TRUE OR public.is_staff());

CREATE POLICY product_barcodes_select ON public.product_barcodes
    FOR SELECT TO authenticated
    USING (TRUE);

CREATE POLICY product_prices_select ON public.product_prices
    FOR SELECT TO authenticated
    USING (
        public.is_cashier_or_above()
        OR tier = 'retail'::public.price_tier
        OR tier = public.current_customer_tier()
    );

-- purchases / suppliers
CREATE POLICY suppliers_select_staff ON public.suppliers
    FOR SELECT TO authenticated
    USING (public.is_cashier_or_above());

CREATE POLICY purchases_select_staff ON public.purchases
    FOR SELECT TO authenticated
    USING (public.is_cashier_or_above());

CREATE POLICY purchase_items_select_staff ON public.purchase_items
    FOR SELECT TO authenticated
    USING (public.is_cashier_or_above());

-- orders
CREATE POLICY orders_select_authorized ON public.orders
    FOR SELECT TO authenticated
    USING (
        public.current_app_role() IN
            ('moderator'::public.user_role, 'manager'::public.user_role,
             'cashier'::public.user_role)
        OR (public.current_app_role() = 'driver'::public.user_role
            AND driver_id = public.current_app_user_id())
        OR (customer_id IS NOT NULL
            AND customer_id = public.current_customer_id())
    );

CREATE POLICY order_items_select_authorized ON public.order_items
    FOR SELECT TO authenticated
    USING (public.can_access_order(order_id));

-- ledgers / money
CREATE POLICY stock_ledger_select_staff ON public.stock_ledger
    FOR SELECT TO authenticated
    USING (public.is_cashier_or_above());

CREATE POLICY customer_ledger_select_authorized ON public.customer_ledger
    FOR SELECT TO authenticated
    USING (public.is_cashier_or_above() OR customer_id = public.current_customer_id());

CREATE POLICY supplier_ledger_select_staff ON public.supplier_ledger
    FOR SELECT TO authenticated
    USING (public.is_cashier_or_above());

CREATE POLICY payments_select_authorized ON public.payments
    FOR SELECT TO authenticated
    USING (
        public.is_cashier_or_above()
        OR customer_id = public.current_customer_id()
        OR received_by = public.current_app_user_id()
    );

CREATE POLICY settlements_select_authorized ON public.settlements
    FOR SELECT TO authenticated
    USING (public.is_cashier_or_above() OR driver_id = public.current_app_user_id());

CREATE POLICY wallet_entries_select_authorized ON public.wallet_entries
    FOR SELECT TO authenticated
    USING (public.is_cashier_or_above() OR driver_id = public.current_app_user_id());

-- driver telemetry / shifts
CREATE POLICY driver_locations_select_authorized ON public.driver_locations
    FOR SELECT TO authenticated
    USING (public.is_cashier_or_above() OR driver_id = public.current_app_user_id());

CREATE POLICY driver_events_select_authorized ON public.driver_location_events
    FOR SELECT TO authenticated
    USING (public.is_cashier_or_above() OR driver_id = public.current_app_user_id());

CREATE POLICY pos_shifts_select_authorized ON public.pos_shifts
    FOR SELECT TO authenticated
    USING (public.is_cashier_or_above() OR cashier_id = public.current_app_user_id());

-- audit / permissions / updates
CREATE POLICY audit_log_select_management ON public.audit_log
    FOR SELECT TO authenticated
    USING (public.is_management());

CREATE POLICY failed_operations_select_management ON public.failed_operations
    FOR SELECT TO authenticated
    USING (public.is_management());

CREATE POLICY permissions_select_staff ON public.permissions
    FOR SELECT TO authenticated
    USING (public.is_staff());

CREATE POLICY role_permissions_select_staff ON public.role_permissions
    FOR SELECT TO authenticated
    USING (public.is_staff());

CREATE POLICY app_versions_select_public ON public.app_versions
    FOR SELECT TO anon, authenticated
    USING (TRUE);

CREATE POLICY app_versions_manage_moderator ON public.app_versions
    FOR ALL TO authenticated
    USING (public.current_app_role() = 'moderator'::public.user_role)
    WITH CHECK (public.current_app_role() = 'moderator'::public.user_role);

CREATE POLICY failed_operations_insert_staff ON public.failed_operations
    FOR INSERT TO authenticated
    WITH CHECK (public.is_staff());

-- snapshot support for security_invoker views
CREATE POLICY product_stock_snapshot_select_staff ON public.product_stock_snapshot
    FOR SELECT TO authenticated
    USING (public.is_cashier_or_above());

CREATE POLICY customer_balance_snapshot_select_authorized ON public.customer_balance_snapshot
    FOR SELECT TO authenticated
    USING (public.is_cashier_or_above() OR customer_id = public.current_customer_id());

CREATE POLICY supplier_balance_snapshot_select_staff ON public.supplier_balance_snapshot
    FOR SELECT TO authenticated
    USING (public.is_cashier_or_above());

CREATE POLICY driver_wallet_snapshot_select_authorized ON public.driver_wallet_snapshot
    FOR SELECT TO authenticated
    USING (public.is_cashier_or_above() OR driver_id = public.current_app_user_id());

-- ----------------------------------------------------------------------------
-- 5. TABLE/VIEW GRANT LOCKDOWN
-- ----------------------------------------------------------------------------

REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon, authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon, authenticated;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC, anon, authenticated;

-- Table-level REVOKE does not remove column-level grants left by earlier
-- migrations (for example GRANT UPDATE (status, driver_id, notes) ON orders).
-- Clear every column ACL before re-granting the narrow, explicit surface below.
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT table_name, column_name
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name IN (
              SELECT table_name
              FROM information_schema.tables
              WHERE table_schema = 'public'
                AND table_type = 'BASE TABLE'
          )
    LOOP
        EXECUTE format(
            'REVOKE ALL (%I) ON TABLE public.%I FROM anon, authenticated',
            r.column_name, r.table_name
        );
    END LOOP;
END $$;

-- Public read-only catalogue. The view is a narrow projection and is the only
-- catalogue object anon can read.
GRANT SELECT ON public.app_versions TO anon, authenticated;

-- Authenticated table reads. RLS still decides which rows are visible.
-- users.pin_code and the customer device-token hash are deliberately excluded
-- from API column grants; only SECURITY DEFINER RPCs may read them.
GRANT SELECT (id, auth_user_id, phone, name, role, active, language,
              must_change_pin, created_at, updated_at)
    ON public.users TO authenticated;
GRANT SELECT (id, user_id, price_tier, credit_limit, created_at, updated_at)
    ON public.customers TO authenticated;
GRANT SELECT ON public.suppliers, public.products, public.product_barcodes,
    public.product_prices, public.purchases, public.purchase_items,
    public.orders, public.order_items, public.stock_ledger,
    public.customer_ledger, public.supplier_ledger, public.payments,
    public.settlements, public.wallet_entries, public.driver_locations,
    public.driver_location_events, public.pos_shifts, public.audit_log,
    public.failed_operations, public.customer_balance_snapshot,
    public.driver_wallet_snapshot, public.supplier_balance_snapshot,
    public.product_stock_snapshot
    TO authenticated;

-- Narrow direct writes. Everything financial and every user-profile/role
-- change goes through SECURITY DEFINER RPCs.
GRANT INSERT, UPDATE, DELETE ON public.app_versions TO authenticated;
GRANT INSERT ON public.failed_operations TO authenticated;

-- View grants are applied after each view is recreated in section 6, because
-- dropping/recreating a view discards its grants.

-- ----------------------------------------------------------------------------
-- 6. VIEW HARDENING
-- ----------------------------------------------------------------------------

-- Public catalogue: intentionally owner-run (security definer) because it
-- aggregates reserved stock from orders. It exposes only product fields and
-- computed prices; it never returns customer, order or cost data.
DROP VIEW IF EXISTS public.view_customer_products CASCADE;
CREATE VIEW public.view_customer_products AS
SELECT
    p.id          AS product_id,
    p.name_ar,
    p.name_fr,
    p.category,
    p.unit,
    p.pack_size,
    p.photo_url,
    p.active,
    GREATEST(0, (COALESCE(s.on_hand_qty, 0) - COALESCE(res.reserved_qty, 0))) AS available_qty,
    ((COALESCE(s.on_hand_qty, 0) - COALESCE(res.reserved_qty, 0)) > 0)         AS in_stock,
    COALESCE(prices.retail_price, 0) AS retail_price,
    CASE
        WHEN public.is_cashier_or_above() OR public.current_customer_id() IS NOT NULL
            THEN COALESCE(prices.wholesale_price, prices.retail_price, 0)
        ELSE COALESCE(prices.retail_price, 0)
    END AS wholesale_price
FROM public.products p
LEFT JOIN public.product_stock_snapshot s ON p.id = s.product_id
LEFT JOIN (
    SELECT oi.product_id, SUM(oi.quantity) AS reserved_qty
    FROM public.order_items oi
    JOIN public.orders o ON oi.order_id = o.id
    WHERE o.status IN ('confirmed','preparing','ready','assigned','accepted','out_for_delivery')
    GROUP BY oi.product_id
) res ON p.id = res.product_id
LEFT JOIN LATERAL (
    SELECT
        (SELECT pp.price FROM public.product_prices pp
         WHERE pp.product_id = p.id AND pp.tier = 'retail'::public.price_tier
         ORDER BY pp.min_qty ASC LIMIT 1) AS retail_price,
        (SELECT pp.price FROM public.product_prices pp
         WHERE pp.product_id = p.id AND pp.tier = 'wholesale'::public.price_tier
         ORDER BY pp.min_qty ASC LIMIT 1) AS wholesale_price
) prices ON TRUE
WHERE p.active = TRUE;

GRANT SELECT ON public.view_customer_products TO anon, authenticated;

-- Customer balance: security_invoker + ownership predicate.
DROP VIEW IF EXISTS public.view_customer_balance CASCADE;
CREATE VIEW public.view_customer_balance
WITH (security_invoker = TRUE)
AS
SELECT
    c.id           AS customer_id,
    c.user_id,
    u.name         AS customer_name,
    u.phone        AS customer_phone,
    c.price_tier,
    c.credit_limit,
    COALESCE(s.current_balance, 0) AS current_balance
FROM public.customers c
JOIN public.users u ON c.user_id = u.id
LEFT JOIN public.customer_balance_snapshot s ON c.id = s.customer_id
WHERE public.is_cashier_or_above() OR u.id = public.current_app_user_id();

GRANT SELECT ON public.view_customer_balance TO authenticated;

-- Supplier balance: staff-only predicate.
DROP VIEW IF EXISTS public.view_supplier_balance CASCADE;
CREATE VIEW public.view_supplier_balance
WITH (security_invoker = TRUE)
AS
SELECT
    s.id            AS supplier_id,
    s.name          AS supplier_name,
    s.phone         AS supplier_phone,
    COALESCE(sn.current_balance, 0) AS current_balance
FROM public.suppliers s
LEFT JOIN public.supplier_balance_snapshot sn ON s.id = sn.supplier_id
WHERE public.is_cashier_or_above();

GRANT SELECT ON public.view_supplier_balance TO authenticated;

-- Driver wallet: staff or the driver themselves.
DROP VIEW IF EXISTS public.view_driver_wallet_balance CASCADE;
CREATE VIEW public.view_driver_wallet_balance
WITH (security_invoker = TRUE)
AS
SELECT
    driver_id,
    COALESCE(current_wallet_balance, 0) AS current_wallet_balance
FROM public.driver_wallet_snapshot
WHERE public.is_cashier_or_above() OR driver_id = public.current_app_user_id();

GRANT SELECT ON public.view_driver_wallet_balance TO authenticated;

-- Product stock: staff-only predicate; includes cost, so customers get 0 rows.
DROP VIEW IF EXISTS public.view_product_stock CASCADE;
CREATE VIEW public.view_product_stock
WITH (security_invoker = TRUE)
AS
SELECT
    p.id              AS product_id,
    p.name_ar,
    p.name_fr,
    p.category,
    p.active,
    p.unit,
    p.pack_size,
    p.last_unit_cost,
    p.min_stock_alert,
    COALESCE(s.on_hand_qty, 0)                                    AS on_hand_qty,
    COALESCE(res.reserved_qty, 0)                                 AS reserved_qty,
    (COALESCE(s.on_hand_qty, 0) - COALESCE(res.reserved_qty, 0))  AS available_qty
FROM public.products p
LEFT JOIN public.product_stock_snapshot s ON p.id = s.product_id
LEFT JOIN (
    SELECT oi.product_id, SUM(oi.quantity) AS reserved_qty
    FROM public.order_items oi
    JOIN public.orders o ON oi.order_id = o.id
    WHERE o.status IN ('confirmed','preparing','ready','assigned','accepted','out_for_delivery')
    GROUP BY oi.product_id
) res ON p.id = res.product_id
WHERE public.is_cashier_or_above();

GRANT SELECT ON public.view_product_stock TO authenticated;

-- Audit views: management-only predicate; underlying audit_log RLS is also
-- management-only.
DROP VIEW IF EXISTS public.view_audit_log_enriched CASCADE;
CREATE VIEW public.view_audit_log_enriched
WITH (security_invoker = TRUE)
AS
SELECT
    a.id,
    a.created_at,
    a.action,
    a.target_table,
    a.target_id,
    a.user_id,
    u.name AS actor_name,
    u.role AS actor_role,
    u.phone AS actor_phone,
    CASE
        WHEN a.target_table = 'orders' AND a.action = 'INSERT' THEN
            'طلب جديد تم تسجيله (' || COALESCE(a.after_state->>'channel', 'store') || ')'
        WHEN a.target_table = 'orders' AND a.action = 'UPDATE' THEN
            'تحديث حالة الطلب إلى: ' || COALESCE(a.after_state->>'status', '')
        WHEN a.target_table = 'orders' AND a.action = 'DELETE' THEN 'حذف أو إلغاء طلب'
        WHEN a.target_table = 'payments' AND a.action = 'INSERT' THEN
            'تحصيل مالي: ' || COALESCE(((a.after_state->>'amount')::numeric / 100)::text, '0') || ' دج'
        WHEN a.target_table = 'payments' AND a.action = 'UPDATE' THEN 'تعديل دفعة مالية'
        WHEN a.target_table = 'settlements' THEN 'إغلاق تسوية سائق (End-of-day)'
        WHEN a.target_table = 'wallet_entries' AND a.action = 'INSERT' THEN
            'حركة بمحفظة السائق: ' || COALESCE(a.after_state->>'type', '') ||
            ' (' || COALESCE(((a.after_state->>'amount')::numeric / 100)::text, '0') || ' دج)'
        WHEN a.target_table = 'stock_ledger' AND a.action = 'INSERT' THEN
            'حركة مخزون (' || COALESCE(a.after_state->>'reason', '') || '): ' ||
            COALESCE(a.after_state->>'qty_change', '0') || ' وحدة'
        WHEN a.target_table = 'purchases' AND a.action = 'INSERT' THEN
            'فاتورة شراء جديدة: ' || COALESCE(a.after_state->>'invoice_no', '')
        WHEN a.target_table = 'purchases' AND a.action = 'UPDATE' THEN
            'تحديث حالة فاتورة شراء إلى: ' || COALESCE(a.after_state->>'status', '')
        WHEN a.target_table = 'purchase_items' THEN 'إضافة / تعديل بنود فاتورة شراء'
        WHEN a.target_table = 'products' AND a.action = 'INSERT' THEN
            'إضافة منتج جديد: ' || COALESCE(a.after_state->>'name_ar', '')
        WHEN a.target_table = 'products' AND a.action = 'UPDATE' THEN
            'تعديل منتج: ' || COALESCE(a.after_state->>'name_ar', '')
        WHEN a.target_table = 'products' AND a.action = 'DELETE' THEN 'حذف منتج من الكتالوج'
        WHEN a.target_table = 'product_prices' THEN
            'تحديث تسعيرة منتج (' || COALESCE(a.after_state->>'tier', '') || '): ' ||
            COALESCE(((a.after_state->>'price')::numeric / 100)::text, '0') || ' دج'
        WHEN a.target_table = 'product_barcodes' THEN 'إضافة أو تعديل باركود لمنتج'
        WHEN a.target_table = 'customer_ledger' AND a.action = 'INSERT' THEN
            'قيد دين زبون: ' || COALESCE(((a.after_state->>'amount_change')::numeric / 100)::text, '0') || ' دج'
        WHEN a.target_table = 'supplier_ledger' AND a.action = 'INSERT' THEN
            'قيد حساب مورد: ' || COALESCE(((a.after_state->>'amount_change')::numeric / 100)::text, '0') || ' دج'
        WHEN a.target_table = 'users' AND a.action = 'INSERT' THEN
            'إنشاء حساب جديد: ' || COALESCE(a.after_state->>'name', '') || ' (' ||
            COALESCE(a.after_state->>'role', '') || ')'
        WHEN a.target_table = 'users' AND a.action = 'UPDATE' THEN
            'تحديث بيانات مستخدم: ' || COALESCE(a.after_state->>'name', '')
        WHEN a.target_table = 'customers' THEN 'تحديث بيانات زبون / حد الائتمان'
        WHEN a.target_table = 'suppliers' THEN 'إضافة أو تعديل مورد'
        WHEN a.target_table = 'addresses' THEN 'إضافة أو تعديل عنوان توصيل'
        WHEN a.target_table = 'driver_locations' THEN 'تحديث موقع سائق التوصيل'
        WHEN a.action = 'STAFF_LOGIN' THEN
            'تسجيل دخول موظف: ' || COALESCE(a.after_state->>'name', u.name, '') || ' (' ||
            COALESCE(a.after_state->>'role', u.role::text, '') || ')'
        WHEN a.action = 'STAFF_LOGOUT' THEN
            'تسجيل خروج موظف: ' || COALESCE(a.after_state->>'name', u.name, '')
        WHEN a.action = 'CASHIER_SWITCH' THEN
            'تبديل كاشير: ' || COALESCE(a.after_state->>'new_cashier_name', '') ||
            ' (السابق: ' || COALESCE(a.before_state->>'previous_cashier_name', '') || ')'
        WHEN a.action = 'SHIFT_OPENED' THEN
            'فتح وردية كاشير جديدة (Z-#' || COALESCE(a.after_state->>'z_report_number', '') ||
            ') برصيد: ' || COALESCE(((a.after_state->>'opening_float_centimes')::numeric / 100)::text, '0') || ' دج'
        WHEN a.action = 'SHIFT_CLOSED' THEN
            'إغلاق وردية كاشير (Z-#' || COALESCE(a.after_state->>'z_report_number', '') ||
            ') بفارق: ' || COALESCE(((a.after_state->>'variance_centimes')::numeric / 100)::text, '0') || ' دج'
        WHEN a.action = 'SUPPLIER_PAYMENT' THEN
            'سداد نقدي للمورد: ' || COALESCE(a.after_state->>'supplier_name', '') || ' بمبلغ ' ||
            COALESCE(((a.after_state->>'amount_centimes')::numeric / 100)::text, '0') || ' دج'
        WHEN a.action = 'MODERATOR_RESET_USER_PIN' THEN 'إعادة تعيين رمز PIN لموظف بواسطة المشرف'
        WHEN a.action = 'USER_PIN_CHANGED' THEN 'تغيير رمز PIN الحساب'
        WHEN a.action = 'STAFF_MEMBER_CREATED' THEN 'إنشاء حساب موظف جديد'
        ELSE a.action || ' على ' || a.target_table
    END AS intelligent_title,
    CASE
        WHEN a.action IN ('SHIFT_OPENED', 'SHIFT_CLOSED', 'SUPPLIER_PAYMENT') THEN 'finance'
        WHEN a.target_table IN ('payments', 'settlements', 'customer_ledger', 'supplier_ledger', 'wallet_entries') THEN 'finance'
        WHEN a.target_table IN ('orders', 'order_items') THEN 'sales'
        WHEN a.target_table IN ('stock_ledger', 'purchases', 'purchase_items', 'products', 'product_prices', 'product_barcodes') THEN 'inventory'
        WHEN a.target_table IN ('users', 'customers') OR a.action IN ('STAFF_LOGIN', 'STAFF_LOGOUT', 'CASHIER_SWITCH', 'MODERATOR_RESET_USER_PIN', 'USER_PIN_CHANGED', 'STAFF_MEMBER_CREATED') THEN 'security'
        ELSE 'general'
    END AS category,
    CASE
        WHEN u.role = 'customer' THEN 'customer'
        WHEN u.role IN ('cashier', 'driver', 'manager', 'moderator') THEN 'staff'
        WHEN a.action IN ('STAFF_LOGIN', 'STAFF_LOGOUT', 'CASHIER_SWITCH', 'SHIFT_OPENED', 'SHIFT_CLOSED') THEN 'staff'
        ELSE 'system'
    END AS actor_type,
    a.ip_address,
    a.before_state,
    a.after_state
FROM public.audit_log a
LEFT JOIN public.users u ON a.user_id = u.id
WHERE public.is_management()
ORDER BY a.created_at DESC;

GRANT SELECT ON public.view_audit_log_enriched TO authenticated;

DROP VIEW IF EXISTS public.view_audit_trail_intelligence CASCADE;
CREATE VIEW public.view_audit_trail_intelligence
WITH (security_invoker = TRUE)
AS
SELECT * FROM public.view_audit_log_enriched;

GRANT SELECT ON public.view_audit_trail_intelligence TO authenticated;

-- Stock conflict queue: management only.
DROP VIEW IF EXISTS public.view_stock_conflict_queue CASCADE;
CREATE VIEW public.view_stock_conflict_queue
WITH (security_invoker = TRUE)
AS
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
FROM public.orders o
LEFT JOIN public.users u  ON u.id = o.cashier_id
LEFT JOIN public.customers c ON c.id = o.customer_id
LEFT JOIN public.users cu ON cu.id = c.user_id
JOIN public.order_items oi ON oi.order_id = o.id
JOIN public.products p ON p.id = oi.product_id
LEFT JOIN public.product_stock_snapshot ss ON ss.product_id = p.id
WHERE o.status = 'requires_manager_review'
  AND public.is_management()
GROUP BY o.id, o.order_number, o.created_at, o.total_amount,
         o.paid_amount, o.notes, u.name, c.id, cu.name, cu.phone
ORDER BY o.created_at ASC;

GRANT SELECT ON public.view_stock_conflict_queue TO authenticated;

-- ----------------------------------------------------------------------------
-- 7. HARDENED RPCS: GUARDED WRAPPERS FOR LEGACY BODIES
-- ----------------------------------------------------------------------------
-- Legacy bodies remain as internal_* functions, are never executable by API
-- roles, and receive the JWT-derived actor instead of a client-supplied actor.

DO $$
BEGIN
    -- Drop obsolete overloads that trusted anon/actor parameters.
    DROP FUNCTION IF EXISTS public.rpc_adjust_stock(UUID, UUID, INTEGER, TEXT);
    DROP FUNCTION IF EXISTS public.rpc_post_store_sale(UUID, JSONB, BIGINT, BIGINT, UUID, UUID);
    DROP FUNCTION IF EXISTS public.rpc_submit_customer_order(UUID, UUID, JSONB, JSONB);
    DROP FUNCTION IF EXISTS public.rpc_open_pos_shift(UUID, UUID, TEXT, BIGINT, INTEGER, TIMESTAMPTZ);
    DROP FUNCTION IF EXISTS public.rpc_close_pos_shift(UUID, UUID, UUID, INTEGER,
        BIGINT, BIGINT, BIGINT, BIGINT, BIGINT, BIGINT, BIGINT, BIGINT, BIGINT,
        JSONB, TIMESTAMPTZ);
END $$;

DO $$
BEGIN
    IF to_regprocedure('public.internal_post_purchase(uuid,uuid)') IS NULL
       AND to_regprocedure('public.rpc_post_purchase(uuid,uuid)') IS NOT NULL THEN
        ALTER FUNCTION public.rpc_post_purchase(UUID, UUID) RENAME TO internal_post_purchase;
    END IF;
    IF to_regprocedure('public.internal_collect_customer_debt(uuid,uuid,bigint,public.payment_method,text,uuid)') IS NULL
       AND to_regprocedure('public.rpc_collect_customer_debt(uuid,uuid,bigint,payment_method,text,uuid)') IS NOT NULL THEN
        ALTER FUNCTION public.rpc_collect_customer_debt(UUID, UUID, BIGINT, payment_method, TEXT, UUID)
            RENAME TO internal_collect_customer_debt;
    END IF;
    IF to_regprocedure('public.internal_confirm_online_order(uuid,uuid,uuid)') IS NULL
       AND to_regprocedure('public.rpc_confirm_online_order(uuid,uuid,uuid)') IS NOT NULL THEN
        ALTER FUNCTION public.rpc_confirm_online_order(UUID, UUID, UUID) RENAME TO internal_confirm_online_order;
    END IF;
    IF to_regprocedure('public.internal_record_order_delivery(uuid,uuid,bigint,uuid)') IS NULL
       AND to_regprocedure('public.rpc_record_order_delivery(uuid,uuid,bigint,uuid)') IS NOT NULL THEN
        ALTER FUNCTION public.rpc_record_order_delivery(UUID, UUID, BIGINT, UUID)
            RENAME TO internal_record_order_delivery;
    END IF;
    IF to_regprocedure('public.internal_settle_driver_wallet(uuid,uuid,bigint,text)') IS NULL
       AND to_regprocedure('public.rpc_settle_driver_wallet(uuid,uuid,bigint,text)') IS NOT NULL THEN
        ALTER FUNCTION public.rpc_settle_driver_wallet(UUID, UUID, BIGINT, TEXT)
            RENAME TO internal_settle_driver_wallet;
    END IF;
    IF to_regprocedure('public.internal_create_product(jsonb,jsonb,jsonb,integer,uuid)') IS NULL
       AND to_regprocedure('public.rpc_create_product(jsonb,jsonb,jsonb,integer,uuid)') IS NOT NULL THEN
        ALTER FUNCTION public.rpc_create_product(JSONB, JSONB, JSONB, INTEGER, UUID)
            RENAME TO internal_create_product;
    END IF;
    IF to_regprocedure('public.internal_create_supplier(character varying,character varying,character varying,text)') IS NULL
       AND to_regprocedure('public.rpc_create_supplier(character varying,character varying,character varying,text)') IS NOT NULL THEN
        ALTER FUNCTION public.rpc_create_supplier(VARCHAR, VARCHAR, VARCHAR, TEXT)
            RENAME TO internal_create_supplier;
    END IF;
    IF to_regprocedure('public.internal_create_draft_purchase(uuid,character varying,date,bigint,uuid,jsonb)') IS NULL
       AND to_regprocedure('public.rpc_create_draft_purchase(uuid,character varying,date,bigint,uuid,jsonb)') IS NOT NULL THEN
        ALTER FUNCTION public.rpc_create_draft_purchase(UUID, VARCHAR, DATE, BIGINT, UUID, JSONB)
            RENAME TO internal_create_draft_purchase;
    END IF;
    IF to_regprocedure('public.internal_adjust_stock(uuid,text,uuid,integer,text)') IS NULL
       AND to_regprocedure('public.rpc_adjust_stock(uuid,text,uuid,integer,text)') IS NOT NULL THEN
        ALTER FUNCTION public.rpc_adjust_stock(UUID, TEXT, UUID, INTEGER, TEXT) RENAME TO internal_adjust_stock;
    END IF;
    IF to_regprocedure('public.internal_open_pos_shift(uuid,uuid,text,text,bigint,integer,timestamptz)') IS NULL
       AND to_regprocedure('public.rpc_open_pos_shift(uuid,uuid,text,text,bigint,integer,timestamptz)') IS NOT NULL THEN
        ALTER FUNCTION public.rpc_open_pos_shift(UUID, UUID, TEXT, TEXT, BIGINT, INTEGER, TIMESTAMPTZ)
            RENAME TO internal_open_pos_shift;
    END IF;
    IF to_regprocedure('public.internal_close_pos_shift(uuid,uuid,text,uuid,integer,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint,jsonb,timestamptz)') IS NULL
       AND to_regprocedure('public.rpc_close_pos_shift(uuid,uuid,text,uuid,integer,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint,jsonb,timestamptz)') IS NOT NULL THEN
        ALTER FUNCTION public.rpc_close_pos_shift(UUID, UUID, TEXT, UUID, INTEGER, BIGINT, BIGINT,
            BIGINT, BIGINT, BIGINT, BIGINT, BIGINT, BIGINT, BIGINT, JSONB, TIMESTAMPTZ)
            RENAME TO internal_close_pos_shift;
    END IF;
    IF to_regprocedure('public.internal_resolve_stock_conflict(uuid,text,uuid,text,jsonb,text)') IS NULL
       AND to_regprocedure('public.rpc_resolve_stock_conflict(uuid,text,uuid,text,jsonb,text)') IS NOT NULL THEN
        ALTER FUNCTION public.rpc_resolve_stock_conflict(UUID, TEXT, UUID, TEXT, JSONB, TEXT)
            RENAME TO internal_resolve_stock_conflict;
    END IF;
    IF to_regprocedure('public.internal_verify_user_pin(uuid,text)') IS NULL
       AND to_regprocedure('public.rpc_verify_user_pin(uuid,text)') IS NOT NULL THEN
        ALTER FUNCTION public.rpc_verify_user_pin(UUID, TEXT) RENAME TO internal_verify_user_pin;
    END IF;
    IF to_regprocedure('public.internal_change_user_pin(uuid,text,text)') IS NULL
       AND to_regprocedure('public.rpc_change_user_pin(uuid,text,text)') IS NOT NULL THEN
        ALTER FUNCTION public.rpc_change_user_pin(UUID, TEXT, TEXT) RENAME TO internal_change_user_pin;
    END IF;
    IF to_regprocedure('public.internal_reset_user_pin_by_admin(uuid,text,uuid,text)') IS NULL
       AND to_regprocedure('public.rpc_reset_user_pin_by_admin(uuid,text,uuid,text)') IS NOT NULL THEN
        ALTER FUNCTION public.rpc_reset_user_pin_by_admin(UUID, TEXT, UUID, TEXT)
            RENAME TO internal_reset_user_pin_by_admin;
    END IF;
    IF to_regprocedure('public.internal_create_staff_member(uuid,text,character varying,character varying,public.user_role,text,character varying)') IS NULL
       AND to_regprocedure('public.rpc_create_staff_member(uuid,text,character varying,character varying,user_role,text,character varying)') IS NOT NULL THEN
        ALTER FUNCTION public.rpc_create_staff_member(UUID, TEXT, VARCHAR, VARCHAR, public.user_role, TEXT, VARCHAR)
            RENAME TO internal_create_staff_member;
    END IF;
    IF to_regprocedure('public.internal_update_user_profile(uuid,text,uuid,character varying,character varying,character varying,public.user_role,boolean)') IS NULL
       AND to_regprocedure('public.rpc_update_user_profile(uuid,text,uuid,character varying,character varying,character varying,user_role,boolean)') IS NOT NULL THEN
        ALTER FUNCTION public.rpc_update_user_profile(UUID, TEXT, UUID, VARCHAR, VARCHAR, VARCHAR, public.user_role, BOOLEAN)
            RENAME TO internal_update_user_profile;
    END IF;
    IF to_regprocedure('public.internal_save_user_profile(uuid,text,uuid,character varying,character varying,character varying,text,boolean,text)') IS NULL
       AND to_regprocedure('public.rpc_save_user_profile(uuid,text,uuid,character varying,character varying,character varying,text,boolean,text)') IS NOT NULL THEN
        ALTER FUNCTION public.rpc_save_user_profile(UUID, TEXT, UUID, VARCHAR, VARCHAR, VARCHAR, TEXT, BOOLEAN, TEXT)
            RENAME TO internal_save_user_profile;
    END IF;
    IF to_regprocedure('public.internal_create_customer_by_staff(uuid,text,character varying,character varying,bigint,text)') IS NULL
       AND to_regprocedure('public.rpc_create_customer_by_staff(uuid,text,character varying,character varying,bigint,text)') IS NOT NULL THEN
        ALTER FUNCTION public.rpc_create_customer_by_staff(UUID, TEXT, VARCHAR, VARCHAR, BIGINT, TEXT)
            RENAME TO internal_create_customer_by_staff;
    END IF;
    IF to_regprocedure('public.internal_record_supplier_payment(uuid,uuid,bigint,uuid,uuid,text,text)') IS NULL
       AND to_regprocedure('public.rpc_record_supplier_payment(uuid,uuid,bigint,uuid,uuid,text,text)') IS NOT NULL THEN
        ALTER FUNCTION public.rpc_record_supplier_payment(UUID, UUID, BIGINT, UUID, UUID, TEXT, TEXT)
            RENAME TO internal_record_supplier_payment;
    END IF;
    IF to_regprocedure('public.internal_sync_customer_profile(character varying,character varying,character varying,character varying,text,double precision,double precision,uuid,uuid)') IS NULL
       AND to_regprocedure('public.rpc_sync_customer_profile(character varying,character varying,character varying,character varying,text,double precision,double precision,uuid,uuid)') IS NOT NULL THEN
        ALTER FUNCTION public.rpc_sync_customer_profile(VARCHAR, VARCHAR, VARCHAR, VARCHAR, TEXT,
            DOUBLE PRECISION, DOUBLE PRECISION, UUID, UUID)
            RENAME TO internal_sync_customer_profile;
    END IF;
    IF to_regprocedure('public.internal_submit_customer_order(uuid,uuid,jsonb,jsonb,text)') IS NULL
       AND to_regprocedure('public.rpc_submit_customer_order(uuid,uuid,jsonb,jsonb,text)') IS NOT NULL THEN
        ALTER FUNCTION public.rpc_submit_customer_order(UUID, UUID, JSONB, JSONB, TEXT)
            RENAME TO internal_submit_customer_order;
    END IF;
END $$;

-- rpc_create_product used auth.uid() (an auth.users id) as stock_ledger.user_id
-- (a public.users id). The wrapper now passes the mapped public actor; replace
-- the internal body so it never prefers the raw auth id.
CREATE OR REPLACE FUNCTION public.internal_create_product(
    p_product       JSONB,
    p_barcodes      JSONB,
    p_prices        JSONB,
    p_opening_stock INT,
    p_user_id       UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_product_id UUID;
    v_operator   UUID := p_user_id;
    v_b          TEXT;
    v_p          JSONB;
BEGIN
    v_product_id := COALESCE((p_product->>'id')::UUID, gen_random_uuid());

    INSERT INTO public.products (id, name_ar, name_fr, category, unit, pack_size, photo_url, last_unit_cost, active)
    VALUES (
        v_product_id,
        p_product->>'name_ar',
        COALESCE(p_product->>'name_fr', p_product->>'name_ar'),
        COALESCE(p_product->>'category', 'عام'),
        COALESCE(p_product->>'unit', 'piece'),
        COALESCE((p_product->>'pack_size')::INT, 1),
        p_product->>'photo_url',
        COALESCE((p_product->>'last_unit_cost')::BIGINT, 0),
        COALESCE((p_product->>'active')::BOOLEAN, TRUE)
    )
    ON CONFLICT (id) DO UPDATE SET
        name_ar        = EXCLUDED.name_ar,
        name_fr        = EXCLUDED.name_fr,
        category       = EXCLUDED.category,
        unit           = EXCLUDED.unit,
        pack_size      = EXCLUDED.pack_size,
        photo_url      = EXCLUDED.photo_url,
        last_unit_cost = EXCLUDED.last_unit_cost,
        active         = EXCLUDED.active,
        updated_at     = NOW();

    IF p_barcodes IS NOT NULL THEN
        FOR v_b IN SELECT jsonb_array_elements_text(p_barcodes) LOOP
            IF v_b IS NOT NULL AND trim(v_b) <> '' THEN
                INSERT INTO public.product_barcodes (barcode, product_id)
                VALUES (trim(v_b), v_product_id)
                ON CONFLICT (barcode) DO NOTHING;
            END IF;
        END LOOP;
    END IF;

    IF p_prices IS NOT NULL THEN
        FOR v_p IN SELECT * FROM jsonb_array_elements(p_prices) LOOP
            INSERT INTO public.product_prices (id, product_id, tier, min_qty, price)
            VALUES (
                COALESCE((v_p->>'id')::UUID, gen_random_uuid()),
                v_product_id,
                (v_p->>'tier')::public.price_tier,
                COALESCE((v_p->>'min_qty')::INT, 1),
                (v_p->>'price')::BIGINT
            )
            ON CONFLICT (product_id, tier, min_qty) DO UPDATE SET price = EXCLUDED.price;
        END LOOP;
    END IF;

    IF p_opening_stock > 0 THEN
        INSERT INTO public.stock_ledger (
            product_id, qty_change, reason, ref_type, ref_id, user_id, notes
        ) VALUES (
            v_product_id, p_opening_stock, 'adjustment'::public.stock_ref_type,
            'opening_stock', v_product_id, v_operator, 'افتتاح رصيد المنتج'
        );
    END IF;

    RETURN v_product_id;
END;
$$;

-- Internal functions are not API-callable.
DO $$
DECLARE r RECORD;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS sig
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname LIKE 'internal\_%' ESCAPE '\'
    LOOP
        EXECUTE 'REVOKE ALL ON FUNCTION ' || r.sig || ' FROM PUBLIC, anon, authenticated';
    END LOOP;
END $$;

-- PIN step-up now only works for the current session (or management acting on
-- another staff member).
CREATE OR REPLACE FUNCTION public.rpc_verify_user_pin(p_user_id UUID, p_pin TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID := public.current_app_user_id();
    v_result JSONB;
    v_must_change BOOLEAN := FALSE;
BEGIN
    IF v_actor IS NULL THEN
        RETURN jsonb_build_object('valid', FALSE, 'message', 'يجب تسجيل الدخول أولاً');
    END IF;
    IF p_user_id IS DISTINCT FROM v_actor THEN
        RAISE EXCEPTION 'forbidden: PIN step-up is self only' USING ERRCODE = '42501';
    END IF;

    v_result := public.internal_verify_user_pin(v_actor, p_pin);
    IF COALESCE((v_result->>'valid')::BOOLEAN, FALSE) THEN
        SELECT must_change_pin INTO v_must_change FROM public.users WHERE id = p_user_id;
        v_result := v_result || jsonb_build_object('must_change_pin', COALESCE(v_must_change, FALSE));
    END IF;
    RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_change_user_pin(p_user_id UUID, p_old_pin TEXT, p_new_pin TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_actor UUID := public.current_app_user_id();
    v_result JSONB;
BEGIN
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'not authenticated' USING ERRCODE = '42501';
    END IF;
    IF p_user_id IS DISTINCT FROM v_actor
       AND public.current_app_role() <> 'moderator'::public.user_role THEN
        RAISE EXCEPTION 'forbidden: PIN change for another user' USING ERRCODE = '42501';
    END IF;
    IF p_new_pin IS NULL OR trim(p_new_pin) !~ '^[0-9]{4,8}$' THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'رمز PIN الجديد يجب أن يكون من 4 إلى 8 أرقام'
        );
    END IF;

    -- A staff account provisioned directly in Supabase Auth has no PIN yet.
    -- The authenticated session is sufficient to establish the first PIN.
    IF p_user_id = v_actor
       AND EXISTS (
           SELECT 1 FROM public.users
           WHERE id = v_actor AND pin_code IS NULL
       ) THEN
        UPDATE public.users
        SET pin_code = crypt(trim(p_new_pin), gen_salt('bf')),
            must_change_pin = FALSE,
            updated_at = NOW()
        WHERE id = v_actor;
        RETURN jsonb_build_object('status', 'success', 'initial', TRUE);
    END IF;

    v_result := public.internal_change_user_pin(p_user_id, p_old_pin, p_new_pin);
    IF v_result->>'status' = 'success' THEN
        UPDATE public.users SET must_change_pin = FALSE, updated_at = NOW() WHERE id = p_user_id;
    END IF;
    RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_reset_user_pin_by_admin(
    p_admin_id UUID, p_admin_pin TEXT, p_target_user_id UUID, p_new_pin TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID := public.current_app_user_id();
    v_result JSONB;
BEGIN
    IF v_actor IS NULL OR public.current_app_role() <> 'moderator'::public.user_role THEN
        RAISE EXCEPTION 'forbidden: moderator only' USING ERRCODE = '42501';
    END IF;
    IF p_admin_id IS DISTINCT FROM v_actor THEN
        RAISE EXCEPTION 'forbidden: admin id must match session' USING ERRCODE = '42501';
    END IF;
    IF p_new_pin IS NULL OR trim(p_new_pin) !~ '^[0-9]{4,8}$' THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'رمز PIN الجديد يجب أن يكون من 4 إلى 8 أرقام'
        );
    END IF;

    v_result := public.internal_reset_user_pin_by_admin(v_actor, p_admin_pin, p_target_user_id, p_new_pin);
    IF v_result->>'status' = 'success' THEN
        UPDATE public.users SET must_change_pin = TRUE, updated_at = NOW() WHERE id = p_target_user_id;
    END IF;
    RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_create_staff_member(
    p_admin_id UUID, p_admin_pin TEXT, p_name VARCHAR, p_phone VARCHAR,
    p_role public.user_role, p_initial_pin TEXT, p_language VARCHAR DEFAULT 'ar'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID := public.current_app_user_id();
    v_result JSONB;
BEGIN
    IF v_actor IS NULL OR public.current_app_role() <> 'moderator'::public.user_role THEN
        RAISE EXCEPTION 'forbidden: moderator only' USING ERRCODE = '42501';
    END IF;
    IF p_admin_id IS DISTINCT FROM v_actor THEN
        RAISE EXCEPTION 'forbidden: admin id must match session' USING ERRCODE = '42501';
    END IF;
    IF p_initial_pin IS NULL OR trim(p_initial_pin) !~ '^[0-9]{4,8}$' THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'رمز PIN يجب أن يكون من 4 إلى 8 أرقام'
        );
    END IF;
    v_result := public.internal_create_staff_member(v_actor, p_admin_pin, p_name, p_phone,
        p_role, p_initial_pin, p_language);
    IF v_result->>'status' = 'success' AND (v_result->>'id') IS NOT NULL THEN
        UPDATE public.users
        SET must_change_pin = TRUE, updated_at = NOW()
        WHERE id = (v_result->>'id')::UUID;
    END IF;
    RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_post_purchase(p_purchase_id UUID, p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID := public.current_app_user_id();
BEGIN
    IF v_actor IS NULL OR NOT public.is_management() THEN
        RAISE EXCEPTION 'forbidden: management only' USING ERRCODE = '42501';
    END IF;
    RETURN public.internal_post_purchase(p_purchase_id, v_actor);
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_collect_customer_debt(
    p_cashier_id UUID, p_customer_id UUID, p_amount BIGINT,
    p_method public.payment_method DEFAULT 'cash',
    p_notes TEXT DEFAULT NULL, p_client_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID := public.current_app_user_id();
BEGIN
    IF v_actor IS NULL OR NOT public.is_cashier_or_above() THEN
        RAISE EXCEPTION 'forbidden: cashier or above only' USING ERRCODE = '42501';
    END IF;
    RETURN public.internal_collect_customer_debt(
        v_actor, p_customer_id, p_amount, p_method, p_notes, p_client_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_confirm_online_order(
    p_order_id UUID, p_cashier_id UUID, p_driver_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID := public.current_app_user_id();
BEGIN
    IF v_actor IS NULL OR NOT public.is_cashier_or_above() THEN
        RAISE EXCEPTION 'forbidden: cashier or above only' USING ERRCODE = '42501';
    END IF;
    IF p_driver_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.users WHERE id = p_driver_id AND role = 'driver'::public.user_role
    ) THEN
        RAISE EXCEPTION 'invalid driver' USING ERRCODE = '22023';
    END IF;
    RETURN public.internal_confirm_online_order(p_order_id, v_actor, p_driver_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_record_order_delivery(
    p_driver_id UUID, p_order_id UUID, p_collected_cash BIGINT, p_client_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID := public.current_app_user_id();
    v_role public.user_role := public.current_app_role();
    v_driver UUID;
BEGIN
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'not authenticated' USING ERRCODE = '42501';
    END IF;
    IF p_collected_cash IS NULL OR p_collected_cash < 0 THEN
        RAISE EXCEPTION 'collected cash cannot be negative' USING ERRCODE = '22023';
    END IF;

    IF v_role = 'driver'::public.user_role THEN
        v_driver := v_actor;
    ELSIF public.is_cashier_or_above() THEN
        v_driver := p_driver_id;
        IF v_driver IS NULL THEN
            SELECT driver_id INTO v_driver FROM public.orders WHERE id = p_order_id;
        END IF;
    ELSE
        RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
    END IF;

    IF v_driver IS NULL
       OR NOT EXISTS (
           SELECT 1 FROM public.orders
           WHERE id = p_order_id AND driver_id = v_driver
       )
       OR NOT EXISTS (
           SELECT 1 FROM public.users
           WHERE id = v_driver AND role = 'driver'::public.user_role AND active
       ) THEN
        RAISE EXCEPTION 'forbidden: order is not assigned to this driver' USING ERRCODE = '42501';
    END IF;

    RETURN public.internal_record_order_delivery(
        v_driver, p_order_id, p_collected_cash, p_client_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_settle_driver_wallet(
    p_cashier_id UUID, p_driver_id UUID, p_counted_cash BIGINT, p_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID := public.current_app_user_id();
BEGIN
    IF v_actor IS NULL OR NOT public.is_cashier_or_above() THEN
        RAISE EXCEPTION 'forbidden: cashier or above only' USING ERRCODE = '42501';
    END IF;
    RETURN public.internal_settle_driver_wallet(v_actor, p_driver_id, p_counted_cash, p_notes);
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_create_product(
    p_product JSONB, p_barcodes JSONB, p_prices JSONB, p_opening_stock INT, p_user_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID := public.current_app_user_id();
BEGIN
    IF v_actor IS NULL OR NOT public.is_management() THEN
        RAISE EXCEPTION 'forbidden: management only' USING ERRCODE = '42501';
    END IF;
    RETURN public.internal_create_product(p_product, p_barcodes, p_prices, p_opening_stock, v_actor);
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_create_supplier(
    p_name VARCHAR, p_phone VARCHAR, p_company_register VARCHAR DEFAULT NULL, p_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT public.is_management() THEN
        RAISE EXCEPTION 'forbidden: management only' USING ERRCODE = '42501';
    END IF;
    RETURN public.internal_create_supplier(p_name, p_phone, p_company_register, p_notes);
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_create_draft_purchase(
    p_supplier_id UUID, p_invoice_no VARCHAR, p_invoice_date DATE,
    p_total_amount BIGINT, p_created_by UUID, p_items JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID := public.current_app_user_id();
BEGIN
    IF v_actor IS NULL OR NOT public.is_management() THEN
        RAISE EXCEPTION 'forbidden: management only' USING ERRCODE = '42501';
    END IF;
    RETURN public.internal_create_draft_purchase(
        p_supplier_id, p_invoice_no, p_invoice_date, p_total_amount, v_actor, p_items);
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_adjust_stock(
    p_user_id UUID, p_caller_pin TEXT, p_product_id UUID, p_qty_change INT, p_reason TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID := public.current_app_user_id();
BEGIN
    IF v_actor IS NULL OR NOT public.is_cashier_or_above() THEN
        RAISE EXCEPTION 'forbidden: cashier or above only' USING ERRCODE = '42501';
    END IF;
    RETURN public.internal_adjust_stock(v_actor, p_caller_pin, p_product_id, p_qty_change, p_reason);
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_open_pos_shift(
    p_client_id UUID, p_cashier_id UUID, p_cashier_pin TEXT, p_cashier_name TEXT,
    p_opening_float BIGINT, p_z_report_sequence INT, p_opened_at TIMESTAMPTZ DEFAULT NOW()
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID := public.current_app_user_id();
    v_name TEXT;
BEGIN
    IF v_actor IS NULL OR NOT public.is_cashier_or_above() THEN
        RAISE EXCEPTION 'forbidden: cashier or above only' USING ERRCODE = '42501';
    END IF;
    SELECT name INTO v_name FROM public.users WHERE id = v_actor;
    RETURN public.internal_open_pos_shift(
        p_client_id, v_actor, p_cashier_pin, COALESCE(v_name, p_cashier_name),
        p_opening_float, p_z_report_sequence, p_opened_at);
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_close_pos_shift(
    p_client_id UUID, p_cashier_id UUID, p_cashier_pin TEXT, p_shift_id UUID DEFAULT NULL,
    p_z_report_sequence INT DEFAULT NULL, p_expected_cash BIGINT DEFAULT 0,
    p_actual_cash BIGINT DEFAULT 0, p_variance BIGINT DEFAULT 0,
    p_cash_sales BIGINT DEFAULT 0, p_credit_sales BIGINT DEFAULT 0,
    p_debt_collected BIGINT DEFAULT 0, p_supplier_payments BIGINT DEFAULT 0,
    p_driver_settlements BIGINT DEFAULT 0, p_returns_amount BIGINT DEFAULT 0,
    p_denominations JSONB DEFAULT '{}'::jsonb, p_closed_at TIMESTAMPTZ DEFAULT NOW()
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID := public.current_app_user_id();
BEGIN
    IF v_actor IS NULL OR NOT public.is_cashier_or_above() THEN
        RAISE EXCEPTION 'forbidden: cashier or above only' USING ERRCODE = '42501';
    END IF;
    RETURN public.internal_close_pos_shift(
        p_client_id, v_actor, p_cashier_pin, p_shift_id, p_z_report_sequence,
        p_expected_cash, p_actual_cash, p_variance, p_cash_sales, p_credit_sales,
        p_debt_collected, p_supplier_payments, p_driver_settlements,
        p_returns_amount, p_denominations, p_closed_at);
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_resolve_stock_conflict(
    p_manager_id UUID, p_manager_pin TEXT, p_order_id UUID, p_action TEXT,
    p_adjustments JSONB DEFAULT NULL, p_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID := public.current_app_user_id();
BEGIN
    IF v_actor IS NULL OR NOT public.is_management() THEN
        RAISE EXCEPTION 'forbidden: management only' USING ERRCODE = '42501';
    END IF;
    RETURN public.internal_resolve_stock_conflict(
        v_actor, p_manager_pin, p_order_id, p_action, p_adjustments, p_notes);
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_update_user_profile(
    p_caller_id UUID, p_caller_pin TEXT, p_target_user_id UUID,
    p_name VARCHAR, p_phone VARCHAR, p_language VARCHAR DEFAULT 'ar',
    p_role public.user_role DEFAULT NULL, p_active BOOLEAN DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID := public.current_app_user_id();
    v_locked_phone TEXT;
    v_locked_auth UUID;
BEGIN
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'not authenticated' USING ERRCODE = '42501';
    END IF;
    IF p_target_user_id IS DISTINCT FROM v_actor AND NOT public.is_management() THEN
        RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
    END IF;
    -- The phone is the auth identity. Once a row is linked to Supabase Auth,
    -- the auth phone owns it and the DB phone may not drift. Unlinked rows can
    -- still be prepared before their auth user is provisioned.
    SELECT phone, auth_user_id INTO v_locked_phone, v_locked_auth
    FROM public.users WHERE id = p_target_user_id;
    IF v_locked_auth IS NOT NULL THEN
        p_phone := v_locked_phone;
    ELSIF p_target_user_id = v_actor
       AND public.current_app_role() <> 'moderator'::public.user_role THEN
        p_phone := COALESCE(v_locked_phone, p_phone);
    END IF;
    RETURN public.internal_update_user_profile(
        v_actor, p_caller_pin, p_target_user_id, p_name, p_phone, p_language, p_role, p_active);
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_save_user_profile(
    p_caller_id UUID, p_caller_pin TEXT, p_target_user_id UUID,
    p_name VARCHAR, p_phone VARCHAR, p_language VARCHAR DEFAULT 'ar',
    p_role TEXT DEFAULT NULL, p_active BOOLEAN DEFAULT NULL, p_new_pin TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID := public.current_app_user_id();
    v_locked_phone TEXT;
    v_locked_auth UUID;
BEGIN
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'not authenticated' USING ERRCODE = '42501';
    END IF;
    IF p_target_user_id IS DISTINCT FROM v_actor AND NOT public.is_management() THEN
        RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
    END IF;
    SELECT phone, auth_user_id INTO v_locked_phone, v_locked_auth
    FROM public.users WHERE id = p_target_user_id;
    IF v_locked_auth IS NOT NULL THEN
        p_phone := v_locked_phone;
    ELSIF p_target_user_id = v_actor
       AND public.current_app_role() <> 'moderator'::public.user_role THEN
        p_phone := COALESCE(v_locked_phone, p_phone);
    END IF;
    IF p_new_pin IS NOT NULL AND trim(p_new_pin) !~ '^[0-9]{4,8}$' THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'رمز PIN الجديد يجب أن يكون من 4 إلى 8 أرقام'
        );
    END IF;
    RETURN public.internal_save_user_profile(
        v_actor, p_caller_pin, p_target_user_id, p_name, p_phone, p_language,
        p_role, p_active, p_new_pin);
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_create_customer_by_staff(
    p_caller_id UUID, p_caller_pin TEXT, p_name VARCHAR, p_phone VARCHAR,
    p_credit_limit BIGINT DEFAULT 0, p_price_tier TEXT DEFAULT 'wholesale'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID := public.current_app_user_id();
BEGIN
    IF v_actor IS NULL OR NOT public.is_cashier_or_above() THEN
        RAISE EXCEPTION 'forbidden: cashier or above only' USING ERRCODE = '42501';
    END IF;
    RETURN public.internal_create_customer_by_staff(
        v_actor, p_caller_pin, p_name, p_phone, p_credit_limit, p_price_tier);
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_record_supplier_payment(
    p_client_id UUID, p_supplier_id UUID, p_amount BIGINT, p_payer_user_id UUID,
    p_purchase_id UUID DEFAULT NULL, p_notes TEXT DEFAULT NULL, p_caller_pin TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID := public.current_app_user_id();
BEGIN
    IF v_actor IS NULL OR NOT public.is_cashier_or_above() THEN
        RAISE EXCEPTION 'forbidden: cashier or above only' USING ERRCODE = '42501';
    END IF;
    RETURN public.internal_record_supplier_payment(
        p_client_id, p_supplier_id, p_amount, v_actor, p_purchase_id, p_notes, p_caller_pin);
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_sync_customer_profile(
    p_name VARCHAR, p_phone VARCHAR, p_wilaya VARCHAR, p_commune VARCHAR,
    p_address_text TEXT, p_latitude DOUBLE PRECISION DEFAULT NULL,
    p_longitude DOUBLE PRECISION DEFAULT NULL, p_existing_customer_id UUID DEFAULT NULL,
    p_existing_user_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user UUID := public.current_app_user_id();
    v_customer UUID := public.current_customer_id();
    v_cust public.customers%ROWTYPE;
    v_phone VARCHAR;
    v_name VARCHAR;
    v_addr_id UUID;
BEGIN
    IF v_user IS NULL THEN
        RAISE EXCEPTION 'not authenticated' USING ERRCODE = '42501';
    END IF;
    IF v_customer IS NULL THEN
        RAISE EXCEPTION 'customer profile not found' USING ERRCODE = 'P0002';
    END IF;

    SELECT phone, name INTO v_phone, v_name
    FROM public.users WHERE id = v_user;
    v_name := COALESCE(NULLIF(trim(p_name), ''), v_name);
    UPDATE public.users
    SET name = v_name, updated_at = NOW()
    WHERE id = v_user;

    SELECT * INTO v_cust FROM public.customers WHERE id = v_customer;

    IF p_wilaya IS NOT NULL AND p_commune IS NOT NULL THEN
        SELECT id INTO v_addr_id
        FROM public.addresses
        WHERE customer_id = v_customer
        ORDER BY is_default DESC, created_at DESC
        LIMIT 1;

        IF v_addr_id IS NULL THEN
            INSERT INTO public.addresses (
                customer_id, wilaya, commune, address_text, latitude, longitude, is_default
            ) VALUES (
                v_customer, trim(p_wilaya), trim(p_commune),
                COALESCE(trim(p_address_text), ''), p_latitude, p_longitude, TRUE
            );
        ELSE
            UPDATE public.addresses
            SET wilaya = trim(p_wilaya),
                commune = trim(p_commune),
                address_text = COALESCE(trim(p_address_text), ''),
                latitude = p_latitude,
                longitude = p_longitude
            WHERE id = v_addr_id;
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'customer_id', v_customer,
        'user_id', v_user,
        'name', v_name,
        'phone', v_phone,
        'wilaya', trim(p_wilaya),
        'commune', trim(p_commune),
        'address_text', trim(p_address_text),
        'credit_limit', v_cust.credit_limit,
        'price_tier', v_cust.price_tier
    );
END;
$$;

-- ----------------------------------------------------------------------------
-- 8. CUSTOMER IDENTITY + DEVICE TOKENS
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.rpc_bind_customer_device(
    p_device_token TEXT, p_rotate BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_customer UUID := public.current_customer_id();
    v_hash TEXT;
    v_existing TEXT;
BEGIN
    IF v_customer IS NULL THEN
        RAISE EXCEPTION 'forbidden: customer session required' USING ERRCODE = '42501';
    END IF;
    IF p_device_token IS NULL OR length(trim(p_device_token)) < 32 THEN
        RAISE EXCEPTION 'invalid device token' USING ERRCODE = '22023';
    END IF;

    v_hash := encode(sha256(convert_to(trim(p_device_token), 'UTF8')), 'hex');

    SELECT device_token_hash INTO v_existing FROM public.customers WHERE id = v_customer;

    IF v_existing IS NOT NULL AND v_existing <> v_hash AND NOT p_rotate THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'bound_to_other_device', TRUE,
            'error', 'هذا الحساب مرتبط بجهاز آخر. سجّل الدخول برمز التحقق لإعادة الربط.'
        );
    END IF;

    -- A device belongs to exactly one customer. Signing a new customer into
    -- the same physical device revokes the previous binding instead of
    -- violating the unique hash index.
    UPDATE public.customers
    SET device_token_hash = NULL,
        device_token_revoked_at = COALESCE(device_token_revoked_at, NOW())
    WHERE device_token_hash = v_hash AND id <> v_customer;

    UPDATE public.customers
    SET device_token_hash = v_hash,
        device_token_rotated_at = NOW(),
        device_token_revoked_at = NULL
    WHERE id = v_customer;

    RETURN jsonb_build_object('success', TRUE);
END;
$$;

-- Compatibility wrapper for the pre-Phase-0 customer registration call. The
-- old body trusted a client-supplied phone and plaintext device token; this
-- replacement derives the customer from the JWT and never creates auth users.
CREATE OR REPLACE FUNCTION public.rpc_register_or_bind_customer_device(
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
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_customer UUID := public.current_customer_id();
    v_bind JSONB;
    v_profile JSONB;
BEGIN
    IF public.current_app_user_id() IS NULL OR v_customer IS NULL THEN
        RAISE EXCEPTION 'forbidden: customer session required' USING ERRCODE = '42501';
    END IF;
    IF p_device_token IS NULL OR length(trim(p_device_token)) < 32 THEN
        RETURN jsonb_build_object('success', FALSE, 'error', 'معرف الجهاز غير صالح');
    END IF;

    v_bind := public.rpc_bind_customer_device(p_device_token, FALSE);
    IF v_bind->>'success' IS DISTINCT FROM 'true' THEN
        RETURN v_bind;
    END IF;

    v_profile := public.rpc_sync_customer_profile(
        p_name, p_phone, p_wilaya, p_commune, p_address_text,
        p_latitude, p_longitude, NULL, NULL);

    RETURN v_profile || jsonb_build_object('success', TRUE);
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_revoke_customer_device()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_customer UUID := public.current_customer_id();
BEGIN
    IF v_customer IS NULL THEN
        RAISE EXCEPTION 'forbidden: customer session required' USING ERRCODE = '42501';
    END IF;
    UPDATE public.customers
    SET device_token_hash = NULL,
        device_token_revoked_at = NOW()
    WHERE id = v_customer;
    RETURN jsonb_build_object('success', TRUE);
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_lookup_customer_by_phone(
    p_phone VARCHAR, p_device_token TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user public.users%ROWTYPE;
    v_cust public.customers%ROWTYPE;
    v_addr public.addresses%ROWTYPE;
BEGIN
    IF NOT public.is_cashier_or_above() THEN
        RAISE EXCEPTION 'forbidden: cashier or above only' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_user FROM public.users
    WHERE phone IN (trim(p_phone), public.normalize_phone(p_phone))
    LIMIT 1;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('found', FALSE, 'message', 'لا يوجد حساب مسجل بهذا الرقم');
    END IF;

    SELECT * INTO v_cust FROM public.customers WHERE user_id = v_user.id LIMIT 1;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('found', FALSE, 'message', 'لا يوجد ملف زبون مرتبط بهذا الرقم');
    END IF;

    SELECT * INTO v_addr FROM public.addresses
    WHERE customer_id = v_cust.id
    ORDER BY is_default DESC, created_at DESC
    LIMIT 1;

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

CREATE OR REPLACE FUNCTION public.rpc_get_my_customer_profile()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user public.users%ROWTYPE;
    v_cust public.customers%ROWTYPE;
    v_addr public.addresses%ROWTYPE;
    v_balance BIGINT := 0;
BEGIN
    SELECT * INTO v_user FROM public.users WHERE id = public.current_app_user_id();
    IF NOT FOUND THEN
        RAISE EXCEPTION 'not authenticated' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO v_cust FROM public.customers WHERE user_id = v_user.id LIMIT 1;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'customer profile not found' USING ERRCODE = 'P0002';
    END IF;
    SELECT * INTO v_addr FROM public.addresses
    WHERE customer_id = v_cust.id
    ORDER BY is_default DESC, created_at DESC
    LIMIT 1;
    SELECT COALESCE(current_balance, 0) INTO v_balance
    FROM public.customer_balance_snapshot WHERE customer_id = v_cust.id;

    RETURN jsonb_build_object(
        'customer_id', v_cust.id,
        'user_id', v_user.id,
        'name', v_user.name,
        'phone', v_user.phone,
        'wilaya', COALESCE(v_addr.wilaya, ''),
        'commune', COALESCE(v_addr.commune, ''),
        'address_text', COALESCE(v_addr.address_text, ''),
        'latitude', v_addr.latitude,
        'longitude', v_addr.longitude,
        'credit_limit', v_cust.credit_limit,
        'current_balance', v_balance,
        'price_tier', v_cust.price_tier
    );
END;
$$;

-- ----------------------------------------------------------------------------
-- 9. CUSTOMER ORDER RPC: JWT OWNERSHIP + HASHED DEVICE CHECK + SERVER PRICING
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.rpc_submit_customer_order(
    p_client_id UUID, p_customer_id UUID, p_delivery_address JSONB,
    p_items JSONB, p_device_token TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_order_id UUID;
    v_customer UUID := public.current_customer_id();
    v_tier public.price_tier := 'wholesale';
    v_stored_hash TEXT;
    v_item JSONB;
    v_product_id UUID;
    v_qty INT;
    v_unit_price BIGINT;
    v_unit_cost BIGINT;
    v_total BIGINT := 0;
    v_total_cost BIGINT := 0;
BEGIN
    IF public.current_app_user_id() IS NULL OR v_customer IS NULL THEN
        RAISE EXCEPTION 'forbidden: customer session required' USING ERRCODE = '42501';
    END IF;
    IF p_items IS NULL
       OR jsonb_typeof(p_items) <> 'array'
       OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'order has no items' USING ERRCODE = '22023';
    END IF;
    IF (SELECT COUNT(*) FROM jsonb_array_elements(p_items) AS item)
       <> (SELECT COUNT(DISTINCT item->>'product_id')
           FROM jsonb_array_elements(p_items) AS item) THEN
        RAISE EXCEPTION 'duplicate product lines are not allowed' USING ERRCODE = '22023';
    END IF;

    IF p_client_id IS NOT NULL THEN
        SELECT id INTO v_order_id
        FROM public.orders
        WHERE client_id = p_client_id AND customer_id = v_customer;
        IF v_order_id IS NOT NULL THEN
            RETURN v_order_id;
        END IF;
    END IF;

    SELECT price_tier, device_token_hash INTO v_tier, v_stored_hash
    FROM public.customers WHERE id = v_customer;

    IF v_stored_hash IS NOT NULL AND v_stored_hash <> '' THEN
        IF p_device_token IS NULL OR length(trim(p_device_token)) < 32
           OR encode(sha256(convert_to(trim(p_device_token), 'UTF8')), 'hex') <> v_stored_hash THEN
            RAISE EXCEPTION 'فشل التحقق من أمان الجهاز المرتبط بالطلب.' USING ERRCODE = '42501';
        END IF;
    END IF;

    v_tier := COALESCE(v_tier, 'wholesale'::public.price_tier);
    v_order_id := gen_random_uuid();

    INSERT INTO public.orders (
        id, client_id, channel, customer_id, status, delivery_address,
        total_amount, total_cost, paid_amount
    ) VALUES (
        v_order_id, p_client_id, 'online', v_customer, 'submitted',
        p_delivery_address, 0, 0, 0
    )
    ON CONFLICT (client_id) DO NOTHING;

    IF NOT FOUND THEN
        SELECT id INTO v_order_id FROM public.orders
        WHERE client_id = p_client_id AND customer_id = v_customer;
        RETURN v_order_id;
    END IF;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        v_product_id := (v_item->>'product_id')::UUID;
        v_qty := (v_item->>'quantity')::INT;
        IF v_qty IS NULL OR v_qty <= 0 THEN
            RAISE EXCEPTION 'quantity must be > 0' USING ERRCODE = '22023';
        END IF;

        IF NOT EXISTS (
            SELECT 1 FROM public.products WHERE id = v_product_id AND active = TRUE
        ) THEN
            RAISE EXCEPTION 'product % is not available', v_product_id USING ERRCODE = '22023';
        END IF;

        SELECT price INTO v_unit_price
        FROM public.product_prices
        WHERE product_id = v_product_id AND tier = v_tier AND min_qty <= v_qty
        ORDER BY min_qty DESC LIMIT 1;

        IF v_unit_price IS NULL AND v_tier <> 'retail'::public.price_tier THEN
            SELECT price INTO v_unit_price
            FROM public.product_prices
            WHERE product_id = v_product_id AND tier = 'retail'::public.price_tier
              AND min_qty <= v_qty
            ORDER BY min_qty DESC LIMIT 1;
        END IF;

        IF v_unit_price IS NULL THEN
            RAISE EXCEPTION 'no price configured for product %', v_product_id USING ERRCODE = '22023';
        END IF;

        SELECT COALESCE(last_unit_cost, 0) INTO v_unit_cost
        FROM public.products WHERE id = v_product_id;

        v_total := v_total + (v_qty * v_unit_price);
        v_total_cost := v_total_cost + (v_qty * v_unit_cost);

        INSERT INTO public.order_items (order_id, product_id, quantity, unit_price, unit_cost)
        VALUES (v_order_id, v_product_id, v_qty, v_unit_price, v_unit_cost);
    END LOOP;

    UPDATE public.orders
    SET total_amount = v_total, total_cost = v_total_cost
    WHERE id = v_order_id;

    RETURN v_order_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_get_customer_order_live(
    p_order_id UUID, p_device_token TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_order public.orders%ROWTYPE;
    v_driver public.users%ROWTYPE;
    v_location public.driver_locations%ROWTYPE;
    v_stored_hash TEXT;
    v_customer UUID;
    v_dest_lat DOUBLE PRECISION;
    v_dest_lng DOUBLE PRECISION;
BEGIN
    IF p_order_id IS NULL OR public.current_app_user_id() IS NULL THEN
        RETURN jsonb_build_object('found', FALSE, 'error', 'الطلب غير متوفر');
    END IF;

    SELECT * INTO v_order FROM public.orders WHERE id = p_order_id LIMIT 1;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('found', FALSE, 'error', 'الطلب غير متوفر');
    END IF;

    v_customer := public.current_customer_id();
    IF NOT (
        public.is_cashier_or_above()
        OR (public.current_app_role() = 'driver'::public.user_role
            AND v_order.driver_id = public.current_app_user_id())
        OR (v_order.customer_id IS NOT NULL
            AND v_order.customer_id = v_customer)
    ) THEN
        RETURN jsonb_build_object('found', FALSE, 'error', 'غير مصرح بتتبع هذا الطلب');
    END IF;

    -- Customers must present the device token bound to their account. Staff
    -- sessions are already role-checked and do not need a device token.
    IF public.current_app_role() = 'customer'::public.user_role
       AND v_order.customer_id IS NOT NULL
       AND v_order.customer_id = v_customer THEN
        SELECT device_token_hash INTO v_stored_hash
        FROM public.customers WHERE id = v_customer;

        IF v_stored_hash IS NULL OR v_stored_hash = '' THEN
            RETURN jsonb_build_object(
                'found', FALSE,
                'error', 'الجهاز غير مربوط بالحساب. سجّل الدخول من جديد.'
            );
        END IF;
        IF p_device_token IS NULL
           OR length(trim(p_device_token)) < 32
           OR encode(sha256(convert_to(trim(p_device_token), 'UTF8')), 'hex') <> v_stored_hash
        THEN
            RETURN jsonb_build_object(
                'found', FALSE,
                'error', 'فشل التحقق من أمان الجهاز المرتبط بالحساب.'
            );
        END IF;
    END IF;

    IF v_order.driver_id IS NOT NULL THEN
        SELECT * INTO v_driver FROM public.users WHERE id = v_order.driver_id LIMIT 1;
        SELECT * INTO v_location FROM public.driver_locations
        WHERE driver_id = v_order.driver_id LIMIT 1;
    END IF;

    IF v_order.delivery_address IS NOT NULL THEN
        BEGIN
            v_dest_lat := NULLIF(v_order.delivery_address->>'latitude', '')::DOUBLE PRECISION;
            v_dest_lng := NULLIF(v_order.delivery_address->>'longitude', '')::DOUBLE PRECISION;
        EXCEPTION WHEN OTHERS THEN
            v_dest_lat := NULL;
            v_dest_lng := NULL;
        END;
    END IF;

    RETURN jsonb_build_object(
        'found', TRUE,
        'order_id', v_order.id,
        'order_number', v_order.order_number,
        'status', v_order.status::text,
        'driver_id', v_order.driver_id,
        'driver_name', v_driver.name,
        'driver_phone', v_driver.phone,
        'driver_lat', v_location.latitude,
        'driver_lng', v_location.longitude,
        'driver_updated_at', v_location.updated_at,
        'destination_lat', v_dest_lat,
        'destination_lng', v_dest_lng,
        'confirmed_at', v_order.confirmed_at,
        'delivered_at', v_order.delivered_at,
        'settled_at', v_order.settled_at
    );
END;
$$;

-- ----------------------------------------------------------------------------
-- 10. STORE SALE: JWT CASHIER + SERVER PRICE/COST LOOKUP
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.rpc_post_store_sale(
    p_client_id UUID, p_cashier_id UUID, p_customer_id UUID, p_items JSONB,
    p_paid_cash BIGINT, p_on_account BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_order_id UUID := gen_random_uuid();
    v_cashier UUID := public.current_app_user_id();
    v_total BIGINT := 0;
    v_cost BIGINT := 0;
    v_item JSONB;
    v_product_id UUID;
    v_qty INT;
    v_price BIGINT;
    v_item_cost BIGINT;
    v_stock INT;
    v_existing_order public.orders%ROWTYPE;
    v_customer public.customers%ROWTYPE;
    v_tier public.price_tier := 'retail';
    v_current_debt BIGINT := 0;
    v_has_stock_conflict BOOLEAN := FALSE;
    v_conflict_details TEXT := '';
    v_order_status public.order_status := 'delivered';
    v_stock_map JSONB := '{}'::JSONB;
BEGIN
    IF v_cashier IS NULL OR NOT public.is_cashier_or_above() THEN
        RAISE EXCEPTION 'forbidden: cashier or above only' USING ERRCODE = '42501';
    END IF;
    IF p_items IS NULL
       OR jsonb_typeof(p_items) <> 'array'
       OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'sale has no items' USING ERRCODE = '22023';
    END IF;
    IF p_paid_cash IS NULL OR p_on_account IS NULL
       OR p_paid_cash < 0 OR p_on_account < 0 THEN
        RAISE EXCEPTION 'payments cannot be negative or null' USING ERRCODE = '22023';
    END IF;
    IF (SELECT COUNT(*) FROM jsonb_array_elements(p_items) AS item)
       <> (SELECT COUNT(DISTINCT item->>'product_id')
           FROM jsonb_array_elements(p_items) AS item) THEN
        RAISE EXCEPTION 'duplicate product lines are not allowed' USING ERRCODE = '22023';
    END IF;
    IF p_on_account > 0 AND p_customer_id IS NULL THEN
        RAISE EXCEPTION 'on-account sale requires a customer' USING ERRCODE = '22023';
    END IF;

    IF p_client_id IS NOT NULL THEN
        SELECT * INTO v_existing_order FROM public.orders WHERE client_id = p_client_id;
        IF FOUND THEN
            RETURN jsonb_build_object(
                'status', CASE WHEN v_existing_order.status = 'requires_manager_review'
                               THEN 'requires_manager_review' ELSE 'already_processed' END,
                'order_id', v_existing_order.id,
                'total_amount', v_existing_order.total_amount,
                'paid_cash', v_existing_order.paid_amount,
                'client_id', p_client_id
            );
        END IF;
    END IF;

    IF p_customer_id IS NOT NULL THEN
        SELECT * INTO v_customer FROM public.customers WHERE id = p_customer_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'customer % not found', p_customer_id USING ERRCODE = 'P0002';
        END IF;
        v_tier := v_customer.price_tier;
    END IF;

    IF p_customer_id IS NOT NULL AND p_on_account > 0 THEN
        SELECT COALESCE(current_balance, 0) INTO v_current_debt
        FROM public.customer_balance_snapshot WHERE customer_id = p_customer_id;

        IF (v_current_debt + p_on_account) > v_customer.credit_limit THEN
            RAISE EXCEPTION 'sale exceeds customer credit limit (limit %, debt %, requested %)',
                v_customer.credit_limit, v_current_debt, p_on_account USING ERRCODE = '22003';
        END IF;
    END IF;

    PERFORM id FROM public.products
    WHERE id IN (SELECT (item->>'product_id')::UUID FROM jsonb_array_elements(p_items) AS item)
    ORDER BY id FOR UPDATE;

    SELECT jsonb_object_agg(product_id::text, available_qty)
    INTO v_stock_map
    FROM public.view_product_stock
    WHERE product_id = ANY(
        SELECT (item->>'product_id')::UUID FROM jsonb_array_elements(p_items) AS item
    );

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        v_product_id := (v_item->>'product_id')::UUID;
        v_qty := (v_item->>'quantity')::INT;
        IF v_qty IS NULL OR v_qty <= 0 THEN
            RAISE EXCEPTION 'quantity must be > 0' USING ERRCODE = '22023';
        END IF;

        SELECT price INTO v_price
        FROM public.product_prices
        WHERE product_id = v_product_id AND tier = v_tier AND min_qty <= v_qty
        ORDER BY min_qty DESC LIMIT 1;

        IF v_price IS NULL AND v_tier <> 'retail'::public.price_tier THEN
            SELECT price INTO v_price
            FROM public.product_prices
            WHERE product_id = v_product_id AND tier = 'retail'::public.price_tier
              AND min_qty <= v_qty
            ORDER BY min_qty DESC LIMIT 1;
        END IF;

        IF v_price IS NULL THEN
            RAISE EXCEPTION 'no % price configured for product %', v_tier, v_product_id
                USING ERRCODE = '22023';
        END IF;

        SELECT COALESCE(last_unit_cost, 0) INTO v_item_cost
        FROM public.products WHERE id = v_product_id;
        IF v_item_cost IS NULL THEN
            RAISE EXCEPTION 'product % not found', v_product_id USING ERRCODE = 'P0002';
        END IF;

        v_stock := COALESCE((v_stock_map->>v_product_id::text)::INT, 0);
        IF v_stock < v_qty THEN
            v_has_stock_conflict := TRUE;
            v_conflict_details := v_conflict_details
                || format('[Product %s: requested %s, available %s] ', v_product_id, v_qty, v_stock);
        END IF;

        v_total := v_total + (v_qty * v_price);
        v_cost := v_cost + (v_qty * v_item_cost);
    END LOOP;

    IF (p_paid_cash + p_on_account) <> v_total THEN
        RAISE EXCEPTION 'payment mismatch: paid(%) + on_account(%) <> server total(%)',
            p_paid_cash, p_on_account, v_total USING ERRCODE = '22003';
    END IF;

    v_order_status := CASE WHEN v_has_stock_conflict
                           THEN 'requires_manager_review'::public.order_status
                           ELSE 'delivered'::public.order_status END;

    INSERT INTO public.orders (
        id, client_id, channel, customer_id, status, cashier_id,
        total_amount, total_cost, paid_amount, notes, delivered_at
    ) VALUES (
        v_order_id, p_client_id, 'store', p_customer_id, v_order_status, v_cashier,
        v_total, v_cost, p_paid_cash,
        CASE WHEN v_has_stock_conflict
             THEN 'OFFLINE_STOCK_CONFLICT: ' || v_conflict_details
             ELSE NULL END,
        CASE WHEN v_has_stock_conflict THEN NULL ELSE NOW() END
    );

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        v_product_id := (v_item->>'product_id')::UUID;
        v_qty := (v_item->>'quantity')::INT;

        SELECT price INTO v_price
        FROM public.product_prices
        WHERE product_id = v_product_id AND tier = v_tier AND min_qty <= v_qty
        ORDER BY min_qty DESC LIMIT 1;

        IF v_price IS NULL AND v_tier <> 'retail'::public.price_tier THEN
            SELECT price INTO v_price
            FROM public.product_prices
            WHERE product_id = v_product_id AND tier = 'retail'::public.price_tier
              AND min_qty <= v_qty
            ORDER BY min_qty DESC LIMIT 1;
        END IF;

        SELECT COALESCE(last_unit_cost, 0) INTO v_item_cost
        FROM public.products WHERE id = v_product_id;

        INSERT INTO public.order_items (order_id, product_id, quantity, unit_price, unit_cost)
        VALUES (v_order_id, v_product_id, v_qty, v_price, v_item_cost);

        IF NOT v_has_stock_conflict THEN
            INSERT INTO public.stock_ledger (
                product_id, qty_change, reason, ref_type, ref_id, user_id, notes
            ) VALUES (
                v_product_id, -v_qty, 'sale', 'order', v_order_id, v_cashier, 'Counter Sale'
            );
        END IF;
    END LOOP;

    IF p_on_account > 0 AND p_customer_id IS NOT NULL THEN
        INSERT INTO public.customer_ledger (customer_id, amount_change, ref_type, ref_id, notes)
        VALUES (p_customer_id, p_on_account, 'order_credit', v_order_id, 'Counter sale credit');
    END IF;

    IF p_paid_cash > 0 THEN
        INSERT INTO public.payments (
            order_id, customer_id, amount, method, received_by, status, client_id
        ) VALUES (
            v_order_id, p_customer_id, p_paid_cash, 'cash', v_cashier, 'settled', p_client_id
        );
    END IF;

    IF v_has_stock_conflict THEN
        INSERT INTO public.audit_log (user_id, action, target_table, target_id, after_state)
        VALUES (v_cashier, 'OFFLINE_STOCK_CONFLICT_FLAGGED', 'orders', v_order_id,
            jsonb_build_object(
                'order_id', v_order_id,
                'client_id', p_client_id,
                'conflict_details', v_conflict_details,
                'status', 'requires_manager_review',
                'total_amount', v_total,
                'note', 'stock_ledger NOT written - pending manager resolution'
            )
        );
    END IF;

    RETURN jsonb_build_object(
        'status', CASE WHEN v_has_stock_conflict THEN 'requires_manager_review' ELSE 'success' END,
        'order_id', v_order_id,
        'total_amount', v_total,
        'paid_cash', p_paid_cash,
        'on_account', p_on_account,
        'stock_conflict', v_has_stock_conflict
    );
END;
$$;

-- ----------------------------------------------------------------------------
-- 11. ORDER STATUS / DRIVER ASSIGNMENT / PREPARATION RPCS
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.rpc_update_order_status(
    p_order_id UUID, p_status TEXT, p_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID := public.current_app_user_id();
    v_role public.user_role := public.current_app_role();
    v_status public.order_status;
BEGIN
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'not authenticated' USING ERRCODE = '42501';
    END IF;
    BEGIN
        v_status := p_status::public.order_status;
    EXCEPTION WHEN invalid_text_representation THEN
        RAISE EXCEPTION 'invalid order status' USING ERRCODE = '22023';
    END;

    IF EXISTS (
        SELECT 1 FROM public.orders
        WHERE id = p_order_id
          AND status IN ('delivered'::public.order_status,
                         'settled'::public.order_status,
                         'cancelled'::public.order_status,
                         'refused'::public.order_status)
    ) THEN
        RAISE EXCEPTION 'terminal orders are immutable' USING ERRCODE = '42501';
    END IF;

    IF v_role = 'driver'::public.user_role THEN
        IF p_status NOT IN ('accepted', 'out_for_delivery')
           OR NOT EXISTS (SELECT 1 FROM public.orders WHERE id = p_order_id AND driver_id = v_actor) THEN
            RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
        END IF;
    ELSIF NOT public.is_cashier_or_above() THEN
        RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
    ELSIF v_status IN ('delivered'::public.order_status, 'settled'::public.order_status) THEN
        -- Delivery and settlement must go through the RPCs that write the
        -- wallet/ledger entries, never a bare status update.
        RAISE EXCEPTION 'use the delivery/settlement RPC for terminal statuses'
            USING ERRCODE = '42501';
    END IF;

    UPDATE public.orders
    SET status = v_status,
        notes = COALESCE(p_notes, notes),
        updated_at = NOW()
    WHERE id = p_order_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'order not found' USING ERRCODE = 'P0002';
    END IF;
    RETURN jsonb_build_object('status', 'success', 'order_id', p_order_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_assign_order_driver(
    p_order_id UUID, p_driver_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT public.is_cashier_or_above() THEN
        RAISE EXCEPTION 'forbidden: cashier or above only' USING ERRCODE = '42501';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.users WHERE id = p_driver_id AND role = 'driver'::public.user_role AND active
    ) THEN
        RAISE EXCEPTION 'invalid driver' USING ERRCODE = '22023';
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.orders
        WHERE id = p_order_id
          AND status IN ('delivered'::public.order_status,
                         'settled'::public.order_status,
                         'cancelled'::public.order_status,
                         'refused'::public.order_status)
    ) THEN
        RAISE EXCEPTION 'terminal orders cannot be reassigned' USING ERRCODE = '42501';
    END IF;
    UPDATE public.orders
    SET driver_id = p_driver_id,
        status = 'assigned'::public.order_status,
        updated_at = NOW()
    WHERE id = p_order_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'order not found' USING ERRCODE = 'P0002';
    END IF;
    RETURN jsonb_build_object('status', 'success', 'order_id', p_order_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_mark_order_ready(
    p_order_id UUID, p_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT public.is_cashier_or_above() THEN
        RAISE EXCEPTION 'forbidden: cashier or above only' USING ERRCODE = '42501';
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.orders
        WHERE id = p_order_id
          AND status IN ('delivered'::public.order_status,
                         'settled'::public.order_status,
                         'cancelled'::public.order_status,
                         'refused'::public.order_status)
    ) THEN
        RAISE EXCEPTION 'terminal orders are immutable' USING ERRCODE = '42501';
    END IF;
    UPDATE public.orders
    SET status = 'ready'::public.order_status,
        notes = COALESCE(p_notes, notes),
        updated_at = NOW()
    WHERE id = p_order_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'order not found' USING ERRCODE = 'P0002';
    END IF;
    RETURN jsonb_build_object('status', 'success', 'order_id', p_order_id);
END;
$$;

-- ----------------------------------------------------------------------------
-- 12. DRIVER TELEMETRY + STAFF AUDIT RPCS
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.rpc_update_driver_location(
    p_driver_id UUID, p_latitude DOUBLE PRECISION, p_longitude DOUBLE PRECISION,
    p_heading DOUBLE PRECISION DEFAULT NULL, p_speed DOUBLE PRECISION DEFAULT NULL,
    p_battery_level INTEGER DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID := public.current_app_user_id();
BEGIN
    IF v_actor IS NULL OR public.current_app_role() <> 'driver'::public.user_role
       OR v_actor IS DISTINCT FROM p_driver_id THEN
        RAISE EXCEPTION 'unauthorized: caller is not the driver' USING ERRCODE = '42501';
    END IF;

    INSERT INTO public.driver_locations (
        driver_id, latitude, longitude, heading, speed, battery_level, updated_at
    ) VALUES (
        v_actor, p_latitude, p_longitude, p_heading, p_speed, p_battery_level, NOW()
    )
    ON CONFLICT (driver_id) DO UPDATE SET
        latitude = EXCLUDED.latitude,
        longitude = EXCLUDED.longitude,
        heading = EXCLUDED.heading,
        speed = EXCLUDED.speed,
        battery_level = EXCLUDED.battery_level,
        updated_at = NOW();
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_log_driver_location_event(
    p_event_type TEXT, p_latitude DOUBLE PRECISION DEFAULT NULL,
    p_longitude DOUBLE PRECISION DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID := public.current_app_user_id();
BEGIN
    IF v_actor IS NULL OR public.current_app_role() <> 'driver'::public.user_role THEN
        RAISE EXCEPTION 'forbidden: driver only' USING ERRCODE = '42501';
    END IF;
    INSERT INTO public.driver_location_events (
        driver_id, event_type, latitude, longitude, recorded_at
    ) VALUES (v_actor, p_event_type, p_latitude, p_longitude, NOW());
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_log_staff_event(
    p_action TEXT, p_target_table TEXT DEFAULT NULL, p_target_id UUID DEFAULT NULL,
    p_before_state JSONB DEFAULT NULL, p_after_state JSONB DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID := public.current_app_user_id();
BEGIN
    IF v_actor IS NULL OR NOT public.is_staff() THEN
        RAISE EXCEPTION 'forbidden: staff only' USING ERRCODE = '42501';
    END IF;
    INSERT INTO public.audit_log (
        user_id, action, target_table, target_id, before_state, after_state
    ) VALUES (
        v_actor, p_action, p_target_table, p_target_id, p_before_state, p_after_state
    );
END;
$$;

-- ----------------------------------------------------------------------------
-- 13. STORAGE: ROLE-CHECKED WRITES, PUBLIC READ
-- ----------------------------------------------------------------------------

DROP POLICY IF EXISTS "Public read product images" ON storage.objects;
DROP POLICY IF EXISTS "Allow staff upload product images" ON storage.objects;
DROP POLICY IF EXISTS "Allow staff update product images" ON storage.objects;
DROP POLICY IF EXISTS "Allow staff delete product images" ON storage.objects;

CREATE POLICY "Public read product images" ON storage.objects
    FOR SELECT TO anon, authenticated
    USING (bucket_id = 'product-images');

CREATE POLICY "Staff upload product images" ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'product-images' AND public.is_management());

CREATE POLICY "Staff update product images" ON storage.objects
    FOR UPDATE TO authenticated
    USING (bucket_id = 'product-images' AND public.is_management())
    WITH CHECK (bucket_id = 'product-images' AND public.is_management());

CREATE POLICY "Staff delete product images" ON storage.objects
    FOR DELETE TO authenticated
    USING (bucket_id = 'product-images' AND public.is_management());

DROP POLICY IF EXISTS "Public Access for App Releases" ON storage.objects;
DROP POLICY IF EXISTS "Moderator and Service Upload for App Releases" ON storage.objects;
DROP POLICY IF EXISTS "Allow moderators to upload app releases" ON storage.objects;
DROP POLICY IF EXISTS "Allow moderators to update app releases" ON storage.objects;
DROP POLICY IF EXISTS "Allow moderators to delete app releases" ON storage.objects;

CREATE POLICY "Public Access for App Releases" ON storage.objects
    FOR SELECT TO anon, authenticated
    USING (bucket_id = 'app-releases');

CREATE POLICY "Allow moderators to upload app releases" ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'app-releases'
        AND public.current_app_role() = 'moderator'::public.user_role);

CREATE POLICY "Allow moderators to update app releases" ON storage.objects
    FOR UPDATE TO authenticated
    USING (bucket_id = 'app-releases'
        AND public.current_app_role() = 'moderator'::public.user_role)
    WITH CHECK (bucket_id = 'app-releases'
        AND public.current_app_role() = 'moderator'::public.user_role);

CREATE POLICY "Allow moderators to delete app releases" ON storage.objects
    FOR DELETE TO authenticated
    USING (bucket_id = 'app-releases'
        AND public.current_app_role() = 'moderator'::public.user_role);

-- ----------------------------------------------------------------------------
-- 14. FUNCTION GRANTS (EXPLICIT ONLY)
-- ----------------------------------------------------------------------------
-- CREATE FUNCTION grants EXECUTE to PUBLIC by default. Re-run the revoke after
-- all wrappers/helpers exist, then grant only the intended API roles.
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.current_app_user_id() TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_app_role() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_auth_role() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_staff() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_management() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_cashier_or_above() TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_customer_id() TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_customer_tier() TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_access_order(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_access_customer(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.normalize_phone(TEXT) TO authenticated;

GRANT EXECUTE ON FUNCTION public.rpc_bootstrap_my_account() TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_get_my_customer_profile() TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_bind_customer_device(TEXT, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_revoke_customer_device() TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_lookup_customer_by_phone(VARCHAR, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_register_or_bind_customer_device(
    VARCHAR, TEXT, VARCHAR, VARCHAR, VARCHAR, TEXT, DOUBLE PRECISION, DOUBLE PRECISION) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_sync_customer_profile(
    VARCHAR, VARCHAR, VARCHAR, VARCHAR, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_submit_customer_order(
    UUID, UUID, JSONB, JSONB, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_get_customer_order_live(UUID, TEXT) TO authenticated;

GRANT EXECUTE ON FUNCTION public.rpc_verify_user_pin(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_change_user_pin(UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_reset_user_pin_by_admin(UUID, TEXT, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_create_staff_member(
    UUID, TEXT, VARCHAR, VARCHAR, public.user_role, TEXT, VARCHAR) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_update_user_profile(
    UUID, TEXT, UUID, VARCHAR, VARCHAR, VARCHAR, public.user_role, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_save_user_profile(
    UUID, TEXT, UUID, VARCHAR, VARCHAR, VARCHAR, TEXT, BOOLEAN, TEXT) TO authenticated;

GRANT EXECUTE ON FUNCTION public.rpc_post_purchase(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_post_store_sale(
    UUID, UUID, UUID, JSONB, BIGINT, BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_collect_customer_debt(
    UUID, UUID, BIGINT, public.payment_method, TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_confirm_online_order(UUID, UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_record_order_delivery(UUID, UUID, BIGINT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_settle_driver_wallet(UUID, UUID, BIGINT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_create_product(
    JSONB, JSONB, JSONB, INTEGER, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_create_supplier(
    VARCHAR, VARCHAR, VARCHAR, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_create_draft_purchase(
    UUID, VARCHAR, DATE, BIGINT, UUID, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_adjust_stock(
    UUID, TEXT, UUID, INTEGER, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_open_pos_shift(
    UUID, UUID, TEXT, TEXT, BIGINT, INTEGER, TIMESTAMPTZ) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_close_pos_shift(
    UUID, UUID, TEXT, UUID, INTEGER, BIGINT, BIGINT, BIGINT, BIGINT, BIGINT,
    BIGINT, BIGINT, BIGINT, BIGINT, JSONB, TIMESTAMPTZ) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_resolve_stock_conflict(
    UUID, TEXT, UUID, TEXT, JSONB, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_create_customer_by_staff(
    UUID, TEXT, VARCHAR, VARCHAR, BIGINT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_record_supplier_payment(
    UUID, UUID, BIGINT, UUID, UUID, TEXT, TEXT) TO authenticated;

GRANT EXECUTE ON FUNCTION public.rpc_update_order_status(UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_assign_order_driver(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_mark_order_ready(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_update_driver_location(
    UUID, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_log_driver_location_event(
    TEXT, DOUBLE PRECISION, DOUBLE PRECISION) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_log_staff_event(
    TEXT, TEXT, UUID, JSONB, JSONB) TO authenticated;

-- Maintenance RPC is service-role only.
REVOKE ALL ON FUNCTION public.rpc_purge_historical_data(INT, INT, INT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_purge_historical_data(INT, INT, INT) TO service_role;

NOTIFY pgrst, 'reload schema';

COMMIT;
