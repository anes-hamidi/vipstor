-- ============================================================
-- MIGRATION 00028: DRIVER TELEMETRY OPTIMIZATION
--
-- Replaces per-ping audit logging on driver_locations with
-- event-based auditing in a new driver_location_events table.
-- The driver_locations table is kept for real-time map display
-- (latest location only) but is no longer audited on every upsert.
--
-- Safety: No tables or columns are dropped. A new table is added.
-- Existing driver_locations data is preserved.
-- ============================================================

-- ------------------------------------------------------------------
-- 1. New table: driver_location_events (event-based auditing)
--    Logs only significant events: trip start/end, clock-in/out,
--    geofence entry/exit. Not every GPS ping.
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS driver_location_events (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id    UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    event_type   TEXT        NOT NULL, -- 'trip_start', 'trip_end', 'clock_in', 'clock_out', 'geofence_entry', 'geofence_exit'
    latitude     DOUBLE PRECISION,
    longitude    DOUBLE PRECISION,
    recorded_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_driver_location_events_driver_id
    ON driver_location_events(driver_id);
CREATE INDEX IF NOT EXISTS idx_driver_location_events_recorded_at
    ON driver_location_events(recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_driver_location_events_type
    ON driver_location_events(event_type);

-- ------------------------------------------------------------------
-- 2. Remove per-ping audit trigger on driver_locations
--    (trigger dropped, table preserved for real-time map display)
-- ------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_audit_driver_locations ON driver_locations;

-- ------------------------------------------------------------------
-- 3. Add audit trigger on driver_location_events for event auditing
-- ------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_audit_driver_location_events()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    INSERT INTO audit_log (user_id, action, target_table, target_id, after_state)
    VALUES (
        NEW.driver_id,
        'DRIVER_LOCATION_EVENT',
        'driver_location_events',
        NEW.id,
        jsonb_build_object(
            'event_type', NEW.event_type,
            'driver_id', NEW.driver_id,
            'latitude', NEW.latitude,
            'longitude', NEW.longitude,
            'recorded_at', NEW.recorded_at
        )
    );
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_audit_driver_location_events
AFTER INSERT ON driver_location_events
FOR EACH ROW EXECUTE FUNCTION trg_audit_driver_location_events();
