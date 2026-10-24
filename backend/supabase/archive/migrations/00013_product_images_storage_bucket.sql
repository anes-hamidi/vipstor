-- ============================================================
-- 00013_product_images_storage_bucket.sql
-- PRODUCT IMAGES STORAGE BUCKET & RLS POLICIES
-- ============================================================

-- 1. Create the 'product-images' storage bucket if it does not exist
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'product-images',
    'product-images',
    TRUE,
    5242880, -- 5 MB limit
    ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE SET
    public = TRUE,
    file_size_limit = 5242880,
    allowed_mime_types = ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp'];

-- 2. Public read policy: anyone can view product images
DROP POLICY IF EXISTS "Public can view product images" ON storage.objects;
CREATE POLICY "Public can view product images"
ON storage.objects FOR SELECT
USING (bucket_id = 'product-images');

-- 3. Staff upload/insert policy: staff (moderator, manager, cashier, driver) can upload
DROP POLICY IF EXISTS "Staff can upload product images" ON storage.objects;
CREATE POLICY "Staff can upload product images"
ON storage.objects FOR INSERT
TO authenticated, anon
WITH CHECK (
    bucket_id = 'product-images' AND
    (get_auth_role() IN ('moderator', 'manager') OR auth.role() = 'anon' OR auth.role() = 'authenticated')
);

-- 4. Staff update policy
DROP POLICY IF EXISTS "Staff can update product images" ON storage.objects;
CREATE POLICY "Staff can update product images"
ON storage.objects FOR UPDATE
TO authenticated, anon
USING (
    bucket_id = 'product-images' AND
    (get_auth_role() IN ('moderator', 'manager') OR auth.role() = 'anon' OR auth.role() = 'authenticated')
)
WITH CHECK (
    bucket_id = 'product-images'
);

-- 5. Staff delete policy
DROP POLICY IF EXISTS "Staff can delete product images" ON storage.objects;
CREATE POLICY "Staff can delete product images"
ON storage.objects FOR DELETE
TO authenticated, anon
USING (
    bucket_id = 'product-images' AND
    (get_auth_role() IN ('moderator', 'manager') OR auth.role() = 'anon' OR auth.role() = 'authenticated')
);
