-- ============================================================
-- VIP WHOLESALE & POS MANAGEMENT SYSTEM
-- STORAGE POLICY HARDENING (00038)
-- ============================================================
-- Closes an open write path on the public 'product-images' bucket.
--
-- Problem
-- -------
-- The baseline policies created by 001_fresh_schema.sql (SECTION 14) only
-- checked bucket_id:
--
--     FOR INSERT WITH CHECK (bucket_id = 'product-images')
--     FOR UPDATE USING       (bucket_id = 'product-images')
--
-- Neither policy was restricted to an authenticated role, so the anon key
-- that ships inside both Flutter apps could insert or overwrite objects.
-- Anyone who extracts that key from an APK could fill the bucket (5 MB per
-- object, unlimited object count) and consume the project storage and egress
-- quota.
--
-- Fix
-- ---
--   * INSERT / UPDATE / DELETE require an authenticated session that maps to
--     an active public.users row whose role holds the 'products.manage'
--     permission (moderator and manager; see the role_permissions seed).
--   * SELECT stays public because the bucket is public and product images are
--     rendered by the customer app.
--
-- can_manage_product_images() is SECURITY DEFINER with a pinned search_path,
-- so it resolves the caller's role and permission regardless of the search
-- path used by the Storage API. auth.uid() is NULL for anon requests, so the
-- helper returns false and anonymous writes are rejected.
--
-- Prerequisite: staff must be linked to an Auth identity
-- (public.users.auth_user_id = auth.uid()). 005_phase0_security.sql and
-- 006_auth_management.sql link the seeded moderator when its synthetic email
-- is set. The diagnostic at the end of this file lists unlinked staff rows.
--
-- Apply order: after 006_auth_management.sql.
-- ============================================================


-- ------------------------------------------------------------------
-- 1. Helper: does the current JWT map to active staff who manage products?
-- ------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.can_manage_product_images()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.users u
        JOIN public.role_permissions rp
          ON rp.role = u.role
        WHERE u.auth_user_id = auth.uid()
          AND u.active
          AND u.deleted_at IS NULL
          AND rp.permission_code = 'products.manage'
    );
$$;

REVOKE ALL ON FUNCTION public.can_manage_product_images() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_manage_product_images() TO anon, authenticated;


-- ------------------------------------------------------------------
-- 2. Remove the permissive policies from the baseline
-- ------------------------------------------------------------------
DROP POLICY IF EXISTS "Allow staff upload product images" ON storage.objects;
DROP POLICY IF EXISTS "Allow staff update product images" ON storage.objects;
DROP POLICY IF EXISTS "Public read product images" ON storage.objects;
DROP POLICY IF EXISTS "Staff manage product images insert" ON storage.objects;
DROP POLICY IF EXISTS "Staff manage product images update" ON storage.objects;
DROP POLICY IF EXISTS "Staff manage product images delete" ON storage.objects;


-- ------------------------------------------------------------------
-- 3. Public read (bucket is public; images are served to customers)
-- ------------------------------------------------------------------
CREATE POLICY "Public read product images"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'product-images');


-- ------------------------------------------------------------------
-- 4. Staff-only writes, gated by the RBAC permission table
-- ------------------------------------------------------------------
CREATE POLICY "Staff manage product images insert"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'product-images'
    AND public.can_manage_product_images()
);

CREATE POLICY "Staff manage product images update"
ON storage.objects FOR UPDATE
TO authenticated
USING (
    bucket_id = 'product-images'
    AND public.can_manage_product_images()
)
WITH CHECK (
    bucket_id = 'product-images'
    AND public.can_manage_product_images()
);

CREATE POLICY "Staff manage product images delete"
ON storage.objects FOR DELETE
TO authenticated
USING (
    bucket_id = 'product-images'
    AND public.can_manage_product_images()
);


-- ------------------------------------------------------------------
-- 5. Re-assert the bucket limits (5 MB, image MIME types only)
--    Matches 001_fresh_schema.sql; harmless when already set.
-- ------------------------------------------------------------------
UPDATE storage.buckets
SET file_size_limit = 5242880,
    allowed_mime_types = ARRAY['image/jpeg','image/jpg','image/png','image/webp','image/gif']
WHERE id = 'product-images';


-- ------------------------------------------------------------------
-- 6. Record the applied version
-- ------------------------------------------------------------------
INSERT INTO public.schema_migrations (version, description)
VALUES ('00038', '00038 - storage policy hardening for product-images')
ON CONFLICT (version) DO NOTHING;


-- ------------------------------------------------------------------
-- 7. Verification (read-only; uncomment to run)
-- ------------------------------------------------------------------
-- Expected: one SELECT policy for {public} and three write policies for
-- {authenticated}, all scoped to the product-images bucket.
--
-- SELECT policyname, cmd, roles, qual, with_check
-- FROM pg_policies
-- WHERE schemaname = 'storage'
--   AND tablename = 'objects'
--   AND (coalesce(qual, '') LIKE '%product-images%'
--        OR coalesce(with_check, '') LIKE '%product-images%')
-- ORDER BY cmd, policyname;
--
-- Expected: can_manage_product_images is owned by postgres and pinned to
-- search_path=public, pg_temp.
--
-- SELECT n.nspname, p.proname, p.prosecdef, p.proconfig
-- FROM pg_proc p
-- JOIN pg_namespace n ON n.oid = p.pronamespace
-- WHERE n.nspname = 'public' AND p.proname = 'can_manage_product_images';
--
-- Expected: no rows. Every active moderator/manager must be linked before the
-- hardened policies can accept their uploads. If a staff row is listed, sign
-- that person in once with the synthetic email (006 maps it automatically), or
-- set auth_user_id explicitly from the Auth dashboard.
--
-- SELECT id, phone, role, auth_user_id, active, deleted_at
-- FROM public.users
-- WHERE role IN ('moderator'::public.user_role, 'manager'::public.user_role)
--   AND active
--   AND deleted_at IS NULL
--   AND auth_user_id IS NULL;
