# VIP Wholesale & POS - Supabase Backend

This folder is the complete database backend for the VIP Wholesale & POS system. It contains one authoritative fresh-install schema, an admin-only seed, operational scripts, and an archive of the superseded migration history.

---

## Folder layout

```
backend/supabase/
├── schema/
│   └── 001_fresh_schema.sql      # Complete schema for a NEW database (through 00033)
├── seeds/
│   └── 001_admin.sql             # Admin-only seed: one moderator account
├── operations/
│   ├── reset_database.sql        # DESTRUCTIVE: drop and recreate the public schema
│   └── verify_installation.sql   # Read-only installation health check
├── migrations/
│   └── README.md                 # Where future incremental migrations go (00034+)
├── archive/
│   ├── migrations/               # Historical migrations 00001-00033 (reference only)
│   └── legacy/                   # Stale consolidated schemas and the old demo seed
└── README.md
```

The old `init_fresh_database.sql`, `combined.sql`, `000_fresh_schema.sql`, and the numbered migrations stopped at roughly migration 00015 and did **not** match the current app. They are archived and must not be used for a new database.

---

## Fresh database setup

Use a brand-new Supabase project. In the Supabase Dashboard, open **SQL Editor** and run these files **in order**:

1. **`schema/001_fresh_schema.sql`**
   - Creates the full schema: tables, enum types, immutable ledgers, triggers, RBAC, RLS policies, audit trail, RPC functions, storage buckets, and performance indexes.
   - Includes everything through migration `00033`.
2. **`seeds/001_admin.sql`**
   - Creates the single master moderator account.
   - No demo staff, customers, suppliers, products, prices, or stock are created.
   - `app_versions` starts empty; releases are added by
     `scripts/publish_release.ps1` after the artifact is uploaded.

Optional:

3. **`operations/verify_installation.sql`**
   - Read-only checks for tables, RPCs, RLS coverage, the admin account, RBAC reference data, and storage buckets.

### Default moderator

| Field | Value |
| :--- | :--- |
| Phone | `0673336972` |
| PIN | `1234` |
| Role | `moderator` |

> **Change the PIN immediately after the first login.** The seed uses bcrypt via `crypt(..., gen_salt('bf'))`; it never stores a plaintext PIN.

---

## Reset an existing project

`operations/reset_database.sql` drops and recreates the `public` schema. It removes all VIP tables and data, but deliberately leaves Supabase Auth users and uploaded Storage files untouched.

After running the reset, run **`schema/001_fresh_schema.sql`** and **`seeds/001_admin.sql`** again.

> Do not run the reset on a project whose data you need.

---

## Point the Flutter apps at the new project

The apps read the Supabase URL and anon key through `String.fromEnvironment`
in `packages/core/lib/constants/app_constants.dart`.

For local development, copy the template and fill in the new project's values
(Supabase Dashboard → Project Settings → API):

```powershell
Copy-Item .env.example .env
# Edit .env: SUPABASE_URL and SUPABASE_ANON_KEY
flutter run -d windows --dart-define-from-file=.env
flutter build apk --release --dart-define-from-file=.env
```

`.env` is git-ignored and `.env.example` documents the variables. Add the same
`--dart-define-from-file=.env` flag to your IDE run configuration. The path is
relative to the directory you run Flutter from; from `apps/<app>` use
`--dart-define-from-file=..\..\.env`. You can also pass
`--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`
explicitly, or export them as environment variables.

The release publisher loads `.env` from the repository root automatically
(existing environment variables win) and passes the URL and anon key to every
build as `--dart-define`, so a release cannot be built against one project and
registered in another:

```powershell
# .env also needs SUPABASE_SERVICE_ROLE_KEY for publishing
# (legacy service_role JWT or a new sb_secret_... key)
.\scripts\publish_release.ps1 -AppType staff_app -Platform android -Version 1.1.0
```

The publisher refuses to mix a URL and a key that belong to different projects.
For CI releases, set the GitHub Actions secrets `SUPABASE_URL`,
`SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` to the new project before
running the workflow. All three are required because the apps have no compiled
fallback project.

`app_constants.dart` intentionally has no fallback project: a build without
`SUPABASE_URL` and `SUPABASE_ANON_KEY` fails with a message explaining the
`--dart-define` flags. This prevents an accidental release against an old
project. Never put the `service_role` key in the Flutter apps; only the release
publisher and CI use it.

---

## What the schema includes

### Authentication

- **Staff:** phone + PIN. PINs are bcrypt hashes in `users.pin_code`; verification and progressive lockout happen inside `rpc_verify_user_pin`.
- **Customers:** device-bound token handshake (`rpc_register_or_bind_customer_device`), replacing SMS OTP.
- Sensitive columns are excluded from client grants and audit payloads.

### RBAC and RLS

- `permissions` and `role_permissions` define granular capabilities.
- Every table in `public` has Row Level Security enabled.
- Staff clients operate as `anon` plus PIN verification; policies are written to support that model.
- `service_role` retains full access for trusted server-side tasks.

### Append-only ledgers

- `stock_ledger`, `customer_ledger`, and `supplier_ledger` reject `UPDATE` and `DELETE`.
- Balance views remain available, with incrementally maintained snapshot tables for scale.

### Audit trail

- `audit_log` automatically captures inserts, updates, and deletes on critical tables.
- `view_audit_log_enriched` / `view_audit_trail_intelligence` provide readable moderator history.
- Direct client reads of raw audit payloads are revoked; writes are constrained by RLS.

### Business logic

All state changes go through atomic, idempotent `SECURITY DEFINER` RPC functions, including:

- `rpc_post_store_sale`, `rpc_submit_customer_order`
- `rpc_confirm_online_order`, `rpc_record_order_delivery`
- `rpc_settle_driver_wallet`, `rpc_collect_customer_debt`
- `rpc_post_purchase`, `rpc_adjust_stock`, `rpc_create_product`
- `rpc_open_pos_shift`, `rpc_close_pos_shift`
- Staff/customer profile and PIN management RPCs

### Storage

- `product-images` bucket (public read, staff write).
- `app-releases` bucket for OTA application packages.

---

## Version tracking

The baseline creates a `schema_migrations` table and records every bundled migration:

```
00015, 00016, 00017, ... 00020a, 00020b, ... 00033
```

It is read-only to clients. Future migrations should insert a row for their version after they run.

---

## Adding future migrations

Put new incremental files in `migrations/`, starting at `00034_...`. See `migrations/README.md`.

Rules:

- Never edit a migration that has already been applied to production.
- Make new migrations idempotent where practical (`IF NOT EXISTS`, `CREATE OR REPLACE`, `DROP ... IF EXISTS`).
- Keep all business writes inside RPC functions; do not add direct client table writes.
- Update `schema/001_fresh_schema.sql` only when you intentionally create a new baseline.

The archived demo data (`archive/legacy/seed.sql`) can be used as a reference if sample staff, suppliers, products, and opening stock are needed for a test project.

---

## Validation performed

The baseline, admin seed, reset script, and verification script were executed against a PostgreSQL-compatible engine (PGlite) with Supabase `auth`/`storage` shims. Results:

- Full schema executed without errors.
- 43 public tables created; RLS enabled on all 43.
- 41 public functions, 50 RLS policies.
- Admin seed created exactly one moderator; product/order/customer/supplier counts stayed at zero.
- `rpc_verify_user_pin` accepted `1234` and rejected an incorrect PIN.
- The full reset → schema → seed → verify cycle succeeded.
