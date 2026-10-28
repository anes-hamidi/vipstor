-- ============================================================================
-- Migration 00036 — rpc_update_driver_location
-- Replaces the direct driver_locations.upsert() call in the Dart client.
-- The RPC validates that the caller owns the driver row (auth.uid() = p_driver_id),
-- preventing any authenticated user from spoofing another driver's GPS position.
-- Apply in Supabase SQL Editor after 003_migration_00035b.sql.
-- ============================================================================

-- 1. Create the RPC
CREATE OR REPLACE FUNCTION public.rpc_update_driver_location(
  p_driver_id      UUID,
  p_latitude       DOUBLE PRECISION,
  p_longitude      DOUBLE PRECISION,
  p_heading        DOUBLE PRECISION DEFAULT NULL,
  p_speed          DOUBLE PRECISION DEFAULT NULL,
  p_battery_level  INTEGER          DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Validate caller: only the driver themselves may update their location
  IF (SELECT auth.uid()) IS DISTINCT FROM p_driver_id THEN
    RAISE EXCEPTION 'unauthorized: caller is not the driver'
      USING ERRCODE = 'P0401';
  END IF;

  INSERT INTO driver_locations (
    driver_id,
    latitude,
    longitude,
    heading,
    speed,
    battery_level,
    updated_at
  )
  VALUES (
    p_driver_id,
    p_latitude,
    p_longitude,
    p_heading,
    p_speed,
    p_battery_level,
    NOW()
  )
  ON CONFLICT (driver_id) DO UPDATE SET
    latitude      = EXCLUDED.latitude,
    longitude     = EXCLUDED.longitude,
    heading       = EXCLUDED.heading,
    speed         = EXCLUDED.speed,
    battery_level = EXCLUDED.battery_level,
    updated_at    = NOW();
END;
$$;

-- 2. Restrict execution: revoke from public, grant only to authenticated drivers
REVOKE EXECUTE ON FUNCTION public.rpc_update_driver_location(UUID, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, INTEGER) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_update_driver_location(UUID, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, INTEGER) TO authenticated;

-- 3. Tighten RLS on driver_locations so the old direct-write path is fully closed.
--    INSERT/UPDATE go through the RPC (SECURITY DEFINER bypasses RLS).
ALTER TABLE driver_locations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS driver_locations_own_read        ON driver_locations;
DROP POLICY IF EXISTS driver_locations_deny_direct_write ON driver_locations;

CREATE POLICY driver_locations_own_read
  ON driver_locations
  FOR SELECT
  USING ((SELECT auth.uid()) = driver_id);

-- Deny direct INSERT/UPDATE/DELETE from any client; the RPC handles writes.
CREATE POLICY driver_locations_deny_direct_write
  ON driver_locations
  FOR ALL
  USING (FALSE)
  WITH CHECK (FALSE);

GRANT SELECT ON driver_locations TO authenticated;
