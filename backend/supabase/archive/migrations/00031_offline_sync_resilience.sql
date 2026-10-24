-- ============================================================
-- MIGRATION 00031: OFFLINE SYNC RESILIENCE
--
-- Adds conflict-policy metadata to pending_operations and a
-- failed_operations table for permanently-failed sync items.
-- No existing tables or columns are dropped.
-- ============================================================

-- ------------------------------------------------------------------
-- 1. Add conflict-policy and last-attempt columns to pending_operations
-- ------------------------------------------------------------------
ALTER TABLE pending_operations
    ADD COLUMN IF NOT EXISTS conflict_policy TEXT DEFAULT 'server_wins';

ALTER TABLE pending_operations
    ADD COLUMN IF NOT EXISTS last_attempt_at TIMESTAMPTZ;

-- ------------------------------------------------------------------
-- 2. Failed operations table: permanently-failed sync items that
--    require manual intervention (e.g., stock conflict needing manager
--    review, invalid customer reference, duplicate key that cannot be
--    resolved automatically).
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS failed_operations (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id      UUID        NOT NULL,
    operation_type TEXT        NOT NULL,
    payload_json   TEXT        NOT NULL,
    last_error     TEXT        NOT NULL,
    retry_count    INT         NOT NULL DEFAULT 0,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_attempted TIMESTAMPTZ,
    resolved       BOOLEAN     NOT NULL DEFAULT FALSE,
    resolution_note TEXT
);

CREATE INDEX IF NOT EXISTS idx_failed_operations_client_id
    ON failed_operations(client_id);
CREATE INDEX IF NOT EXISTS idx_failed_operations_resolved
    ON failed_operations(resolved);
CREATE INDEX IF NOT EXISTS idx_failed_operations_created_at
    ON failed_operations(created_at DESC);
