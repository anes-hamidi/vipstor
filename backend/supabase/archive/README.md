# Archive

Historical SQL kept for reference only. **Do not use these files to create a new database.**

## `migrations/`

The original numbered migration chain `00001` through `00033`, plus:

- `000_fresh_schema.sql` - an older consolidated schema used as the starting point for this baseline. It covers migrations 00001-00015 but is stale on its own.
- `000_audit_hardening.sql` - an unnumbered audit patch that was superseded by later audit migrations.
- `rollback_00015.sql` - rollback helper for migration 00015.
- Two files numbered `00020` - both were applied and both are included in the baseline.

Known issue in the archived chain: `00031_offline_sync_resilience.sql` contains unguarded `ALTER TABLE pending_operations` statements. `pending_operations` is a client-side Drift table and is not created by the PostgreSQL schema. The consolidated baseline guards those statements; the archived file retains the original history.

## `legacy/`

Superseded consolidated scripts:

- `init_fresh_database.sql` - stale full schema (through roughly 00015).
- `combined.sql` - stale duplicate of the full schema.
- `clean_start.sql` - old data-only truncate/reset script; replaced by `../operations/reset_database.sql`.
- `customer_app_catchup.sql` - old manual catch-up patch for migrations 00010-00016.
- `seed.sql` - full demo seed with sample staff, customer, suppliers, products, prices, and opening stock. Useful as a reference for a test project.
- `seed_default_moderator.sql` - old moderator-only seed; replaced by `../seeds/001_admin.sql`.

Use `../schema/001_fresh_schema.sql` and `../seeds/001_admin.sql` instead.
