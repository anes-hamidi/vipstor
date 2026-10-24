-- ============================================================
-- 00011_driver_locations_tracking.sql
-- REALTIME DRIVER TRACKING FOR CUSTOMERS AND STAFF
-- ============================================================

CREATE TABLE IF NOT EXISTS driver_locations (
    driver_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    heading DOUBLE PRECISION,
    speed DOUBLE PRECISION,
    battery_level INTEGER,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE driver_locations ENABLE ROW LEVEL SECURITY;

-- 1. Drivers can view and update their own live location
CREATE POLICY "Drivers can upsert their own location"
ON driver_locations FOR ALL
USING (
    driver_id = auth.uid() 
    OR get_auth_role() IN ('moderator', 'manager', 'cashier')
)
WITH CHECK (
    driver_id = auth.uid() 
    OR get_auth_role() IN ('moderator', 'manager', 'cashier')
);

-- 2. Staff (cashiers, managers, moderators) can view all driver locations
CREATE POLICY "Staff can view all driver locations"
ON driver_locations FOR SELECT
USING (
    get_auth_role() IN ('moderator', 'manager', 'cashier')
);

-- 3. Customers can view driver location ONLY if that driver is currently delivering an active order for them
CREATE POLICY "Customers can track active delivery driver"
ON driver_locations FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM orders o
        JOIN customers c ON o.customer_id = c.id
        WHERE c.user_id = auth.uid()
          AND o.driver_id = driver_locations.driver_id
          AND o.status IN ('assigned', 'accepted', 'out_for_delivery')
    )
);

-- Enable Supabase Realtime publication for driver_locations
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' 
          AND schemaname = 'public' 
          AND tablename = 'driver_locations'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE driver_locations;
    END IF;
END $$;
