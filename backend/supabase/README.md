# VIP Wholesale & POS - Supabase Backend

This folder is the complete database backend for the VIP Wholesale & POS system. It contains the authoritative baseline and incremental schemas, the Auth lifecycle Edge Function, an admin-only seed, operational scripts, and an archive of the superseded migration history.

---

## Folder layout

```
backend/supabase/
├── schema/
│   ├── 001_fresh_schema.sql      # Complete baseline schema (through 00034)
│   ├── 005_phase0_security.sql   # Phase 0 hardening, JWT identity, PIN/RLS/RPC lockdown
│   ├── 006_auth_management.sql   # Password-only auth, recovery codes, staff lifecycle
│   └── 007_storage_policy_hardening.sql  # product-images writes restricted to staff
├── functions/
│   ├── auth-admin/index.ts       # Service-role Auth lifecycle Edge Function
│   └── README.md                 # Deployment and secret notes
├── seeds/
│   └── 001_admin.sql             # Admin-only seed: one moderator account
├── operations/
│   ├── reset_database.sql        # DESTRUCTIVE: drop and recreate the public schema
│   ├── verify_installation.sql   # Read-only installation health check
│   ├── check_storage_footprint.sql # Read-only disk usage & archivable candidate audit
│   └── storage_lifecycle_management.sql # Retention policy & rpc_purge_historical_data
├── migrations/
│   └── README.md                 # Where future incremental migrations go (00035+)
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
   - Creates the full baseline schema: tables, enum types, immutable ledgers, triggers, RBAC, RLS policies, audit trail, RPC functions, storage buckets, and performance indexes.
   - Includes everything through migration `00034`.
2. **`schema/002_migration_00035.sql`**
   - Blocker fixes: snapshot views, RLS performance, audit integrity, PIN gates, stock checks.
3. **`schema/003_migration_00035b.sql`**
   - Stock conflict queue and `rpc_resolve_stock_conflict`.
4. **`schema/004_migration_00036.sql`**
   - Driver-location RPC hardening.
5. **`schema/005_phase0_security.sql`**
   - Hardens identity and authorization: JWT-derived user identity, PIN step-up, device binding, RPC/RLS lockdown, and audit protections.
6. **`schema/006_auth_management.sql`**
   - Adds password-only auth helpers, deterministic phone-to-email mapping, customer recovery codes, soft deletion, and moderator-managed staff lifecycle RPCs.
7. **`schema/007_storage_policy_hardening.sql`**
   - Restricts `product-images` INSERT/UPDATE/DELETE to authenticated staff with `products.manage`.
   - Closes an anon-key upload path that could consume the project storage quota.
8. **`seeds/001_admin.sql`**
   - Creates the single master moderator row.
   - No demo staff, customers, suppliers, products, prices, or stock are created.
   - `app_versions` starts empty; releases are added by `scripts/publish_release.ps1` after the artifact is uploaded.

Then deploy the Auth lifecycle Edge Function from the repository root:

```powershell
cd backend
supabase login
supabase link --project-ref <project-ref>
supabase functions deploy auth-admin --no-verify-jwt
```

`auth-admin` must be deployed with JWT verification **disabled** because customer
registration and recovery are unauthenticated. The function validates staff JWTs
and PINs itself; see [`functions/README.md`](functions/README.md).

Optional:

8. **`operations/verify_installation.sql`**
   - Read-only checks for tables, RPCs, RLS coverage, the admin account, RBAC reference data, and storage buckets.

### Default moderator

| Field | Value |
| :--- | :--- |
| Phone | `0673336972` |
| Synthetic login email | `213673336972@vip.algomend.app` |
| PIN | `1234` |
| Role | `moderator` |
| Password | Set by the owner in **Authentication → Users** |

> The seed only creates the `public.users` row. Create the matching Supabase
> Auth user once:
>
> 1. In **Authentication → Users → Add user**, use the temporary email
>    `bootstrap-moderator@vip.algomend.app`, set a strong password, and enable
>    **Auto Confirm User**. Leave the user metadata and app metadata empty.
>    This email is deliberately not phone-shaped: a synthetic phone email would
>    make the insert trigger derive the seeded phone and collide with the
>    moderator row.
> 2. Run this SQL to set the real synthetic email and attach the phone and the
>    trusted server-side role. The `auth.users` update trigger will adopt the
>    seeded moderator row; the CTE also refreshes the email identity data:
>
>    ```sql
>    WITH updated AS (
>        UPDATE auth.users
>        SET email = '213673336972@vip.algomend.app',
>            email_confirmed_at = COALESCE(email_confirmed_at, NOW()),
>            raw_app_meta_data =
>              COALESCE(raw_app_meta_data, '{}'::jsonb)
>              || '{"role":"moderator"}'::jsonb,
>            raw_user_meta_data =
>              COALESCE(raw_user_meta_data, '{}'::jsonb)
>              || '{"phone":"0673336972","name":"المدير العام"}'::jsonb,
>            updated_at = NOW()
>        WHERE email = 'bootstrap-moderator@vip.algomend.app'
>        RETURNING id, email
>    )
>    UPDATE auth.identities i
>    SET identity_data =
>          COALESCE(i.identity_data, '{}'::jsonb)
>          || jsonb_build_object('email', u.email, 'email_verified', TRUE),
>        updated_at = NOW()
>    FROM updated u
>    WHERE i.user_id = u.id AND i.provider = 'email';
>    ```
>
> 3. Verify the link:
>
>    ```sql
>    SELECT id, phone, role, auth_user_id
>    FROM public.users
>    WHERE phone = '0673336972';
>    ```
>
> The real synthetic email is set in step 2; do not set phone metadata before
> the trusted `app_metadata.role` exists. New customer identities are never
> auto-linked to an existing row by phone; only the one-time `006` backfill
> links legacy identities, and staff adoption requires a matching trusted role.
>
> **Change the PIN immediately after the first login.** The seed uses bcrypt via
> `crypt(..., gen_salt('bf'))`; it never stores a plaintext PIN.

---

## Reset an existing project

`operations/reset_database.sql` drops and recreates the `public` schema. It removes all VIP tables and data, but deliberately leaves Supabase Auth users and uploaded Storage files untouched.

After running the reset, run **`schema/001_fresh_schema.sql`**,
**`schema/002_migration_00035.sql`**, **`schema/003_migration_00035b.sql`**,
**`schema/004_migration_00036.sql`**, **`schema/005_phase0_security.sql`**,
**`schema/006_auth_management.sql`**, **`schema/007_storage_policy_hardening.sql`**,
and **`seeds/001_admin.sql`** again.
Existing Auth users are left untouched; if you want a completely clean identity
store, delete the old Auth users manually before re-seeding.

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
# Releases are published to GitHub Releases by default, which needs a token
# with "Contents: Read and write":
#   GITHUB_TOKEN=github_pat_...
.\scripts\publish_release.ps1 -AppType staff_app -Platform android -Version 1.1.0
```

The publisher refuses to mix a URL and a key that belong to different projects.
For CI releases, set the GitHub Actions secrets `SUPABASE_URL`,
`SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, and `GITHUB_TOKEN` (or rely on
the workflow's built-in `GITHUB_TOKEN`) before running the workflow. All three
Supabase values are required because the apps have no compiled fallback project.

Because a fresh project starts with an empty `app_versions` table, the first
release would otherwise auto-select build `1`. OTA clients only update when
`build_number` increases, so set the workflow's `build_number` input to a value
greater than the last build installed on devices (for example `3`). After that,
leave it at `0` to auto-increment from the database.

`app_constants.dart` intentionally has no fallback project: a build without
`SUPABASE_URL` and `SUPABASE_ANON_KEY` fails with a message explaining the
`--dart-define` flags. This prevents an accidental release against an old
project. Never put the `service_role` key in the Flutter apps; only the release
publisher and CI use it.

---

## What the schema includes

### Authentication

- **Password-only Supabase Auth.** There is no SMS/OTP flow and no mail is
  sent. A phone number is mapped to a deterministic synthetic email:
  `<international digits>@vip.algomend.app` (for example
  `213673336972@vip.algomend.app`). The apps submit phone + password; the
  synthetic email stays an implementation detail.
- **Disable public sign-ups** in **Authentication → Providers → Email**.
  Customer accounts must be created through `auth-admin` so the recovery code
  and `public.users` row are provisioned together. The Email provider itself
  stays enabled for password sign-in.
- **Staff:** phone + password for login. PINs are separate step-up secrets and
  are bcrypt hashes in `users.pin_code`; verification and progressive lockout
  happen inside `rpc_verify_user_pin`. Moderators create/edit/delete staff
  through the `auth-admin` Edge Function, which provisions or removes the
  Supabase Auth identity alongside the `public.users` row.
- **Customers:** self-registration through `auth-admin`; the server returns a
  one-time 12-character recovery code (`XXXX-XXXX-XXXX`), stores only its bcrypt
  hash, and rotates it after a successful password reset. Recovery requires the
  phone number and that code. Accounts created before `006` keep their current
  password but have no recovery code; the owner can reset those manually in
  **Authentication → Users**.
- **Legacy phone-auth identities** can use the phone-password fallback only
  while the Supabase **Phone** provider is enabled; password sign-in does not
  send an SMS. If phone auth is disabled, migrate the Auth email to the
  synthetic address (or reset/recreate the account) before release.
- **Soft deletion:** deleting a staff account sets `users.deleted_at`, disables
  the row, and deletes the Auth identity. A partial unique index
  (`uq_users_phone_live`) lets the phone number be reused without breaking
  historical foreign keys.
- **Device binding:** customer sessions remain bound to an opaque device token
  (`rpc_register_or_bind_customer_device`). A password login rotates the token;
  a mismatch is rejected.
- Sensitive columns are excluded from client grants and audit payloads.

### RBAC and RLS

- `permissions` and `role_permissions` define granular capabilities.
- Every table in `public` has Row Level Security enabled.
- Authenticated clients carry a Supabase JWT; `current_app_user_id()` and
  `current_app_role()` resolve identity from that JWT, never from client-supplied
  user ids. PIN is required only for step-up operations.
- The Auth trigger derives the public phone from the verified Auth `phone` claim
  or the deterministic synthetic email. Client-editable `user_metadata.phone`
  is never trusted for identity or linkage.
- The `006` backfill links a legacy identity only when its trusted
  `app_metadata.role` matches the public row's role. A legacy staff Auth user
  without that metadata must be linked manually or recreated through
  `auth-admin`; it is never auto-promoted from a customer identity.
- `service_role` retains full access for trusted server-side tasks. The apps
  never embed it; only the `auth-admin` Edge Function uses it.

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

### Storage & Free Tier Optimization (00034, 00038)

- `product-images` bucket (public read; writes restricted to authenticated staff with `products.manage` as of `00038`).
- `app-releases` bucket for OTA application packages. **Optional:** `scripts/publish_release.ps1` now publishes to GitHub Releases by default (`-ReleaseHost github`), which avoids the Free-tier 50 MB per-file limit and egress charges. Pass `-ReleaseHost supabase` to keep using this bucket.
- **Storage Lifecycle & Auto-Purge:** `rpc_purge_historical_data` automatically archives and prunes closed orders (>60 days), audit logs (>30 days), and driver telemetry (>7 days) while strictly preserving products, customers, suppliers, ledgers, and wallets.
- **Automated Pre-Purge Backup Action:** `.github/workflows/database_backup_and_prune.yml` exports historical datasets to compressed JSON artifacts in GitHub Artifacts before executing the database prune.
- **Storage Inspection Tool:** `operations/check_storage_footprint.sql` audits disk usage against the 500 MB Supabase Free Tier ceiling.

---

## Version tracking

The baseline creates a `schema_migrations` table and records every bundled migration:

```
00015, 00016, 00017, ... 00020a, 00020b, ... 00034
```

`002`/`003` insert `00035`/`00035b`; `006_auth_management.sql` records `00036`
and `00037`. The `005` hardening script does not insert its own row. The table
is read-only to clients. Future migrations should insert a row for their version
after they run.

---

## Adding future migrations

Put new incremental files in `schema/`, starting at `007_...`. See
`migrations/README.md` for the archive convention.

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
- All public tables created; RLS enabled on every table.
- Public RPCs and RLS policies deployed successfully.
- Admin seed created exactly one moderator; product/order/customer/supplier counts stayed at zero.
- `rpc_verify_user_pin` accepted `1234` and rejected an incorrect PIN.
- The full reset → schema → seed → verify cycle succeeded.
- The `006` auth-lifecycle suite passed 15/15 checks: synthetic email
  mapping, Auth-trigger provisioning, client-metadata phone isolation,
  unlinked-phone takeover rejection, registration finalize, recovery
  verification/rotation/lockout, staff-Auth recovery isolation, rate limiting,
  moderator PIN, staff create/delete with phone reuse, service-role cleanup,
  last-moderator protection, and deleted-session bootstrap rejection.
