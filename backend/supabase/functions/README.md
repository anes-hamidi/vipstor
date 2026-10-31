# Supabase Edge Functions

## `auth-admin`

Service-role account lifecycle for the PIN-only staff and password-based
moderator authentication model.

The function exists because Supabase Auth's admin API requires the service-role
key, which must never ship inside the Flutter apps. The function accepts only
the small set of actions below and never exposes a generic Auth proxy.

### Actions

| Action | Caller | Purpose |
| :--- | :--- | :--- |
| `customer_register` | Public | Creates a customer Auth identity + public row and returns a one-time recovery code. |
| `customer_reset_password` | Public | Verifies phone + recovery code, sets a new password, and rotates the recovery code. |
| `staff_directory` | Public | Lists active cashiers, managers and drivers for the PIN terminal (names/roles only). |
| `staff_pin_login` | Public | Verifies a staff PIN, rotates the hidden Auth password and returns a real Supabase session. Moderators are rejected. |
| `staff_create` | Moderator | Creates the staff Auth identity and public profile. PIN staff receive a hidden random Auth password; moderators receive the supplied password. |
| `staff_update` | Moderator | Updates profile, phone/login email, role, active state, and optional PIN. Passwords are only settable on moderator targets; demoting a moderator retires the old password. |
| `staff_delete` | Moderator | Soft-deletes the public staff row and deletes the Auth identity. |

Every response is JSON. Success responses include `"success": true`; failures
include `"success": false`, `"error"`, and a stable `"code"`.

### Deploy

Run the SQL migrations first (at minimum `005_phase0_security.sql`,
`006_auth_management.sql`, and `009_staff_pin_auth.sql`). Then, from the
repository root:

```powershell
cd backend
supabase login
supabase link --project-ref <project-ref>
supabase functions deploy auth-admin --no-verify-jwt
```

JWT verification **must be disabled**: `customer_register`,
`customer_reset_password`, `staff_directory` and `staff_pin_login` are
intentionally unauthenticated. The function validates staff Bearer tokens and
moderator PINs itself before any administrative staff action.
If you manage functions in `supabase/config.toml`, use:

```toml
[functions.auth-admin]
verify_jwt = false
```

No custom secrets are required. Supabase provides these to deployed functions
automatically:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `SUPABASE_ANON_KEY` (or the newer `SUPABASE_PUBLISHABLE_KEY`)

From the repository root, local serve:

```powershell
cd backend
supabase functions serve auth-admin --no-verify-jwt --env-file supabase/.env
```

The local `supabase/.env` must contain `SUPABASE_URL`,
`SUPABASE_SERVICE_ROLE_KEY`, and `SUPABASE_ANON_KEY`.

### Security model

- Public customer actions are rate-limited through `rpc_auth_rate_limit`.
- `staff_directory` and `staff_pin_login` are also rate-limited. The directory
  only returns active cashiers, managers and drivers; it never returns phone
  numbers or moderator accounts.
- Customer registration rejects any live `public.users.phone` row. Without a
  prior verified identity, an unlinked pre-created customer row cannot be
  claimed.
- Recovery codes are generated from a CSPRNG, formatted `XXXX-XXXX-XXXX`,
  returned exactly once, and stored only as a bcrypt hash in
  `public.customer_recovery`. Five wrong attempts lock recovery for 15 minutes.
- Staff actions require a valid Bearer token. `auth.getUser()` resolves the Auth
  user, then the function requires a live, active `moderator` row in
  `public.users` and verifies the moderator PIN through
  `rpc_auth_verify_moderator_pin`.
- `staff_update` requires the target row to have a linked Auth identity. Legacy
  public-only staff rows from `rpc_create_staff_member` must be linked manually
  or recreated; `staff_delete` still works for them.
- `staff_update` saves business fields through `rpc_save_user_profile` using the
  **caller's** JWT, so the existing SECURITY DEFINER checks still apply. A
  changed phone rotates the deterministic synthetic login email; the auth
  trigger derives the public phone from that email, never from client-editable
  user metadata.
- `staff_delete` marks `deleted_at`, clears the PIN, keeps the row for historical
  foreign keys, and deletes the Auth identity. The last active moderator and
  self-deletion are rejected in SQL.
- `staff_pin_login` verifies the PIN through the service-role-only
  `internal_verify_user_pin` RPC (bcrypt comparison + escalating lockout),
  rejects moderators, rotates the hidden Auth password to a random secret, and
  returns access/refresh tokens. The app installs them with `auth.setSession`,
  so staff get a normal Supabase JWT and RLS keeps working without ever seeing
  a password. `009_staff_pin_auth.sql` grants the internal RPC to
  `service_role` only.
- `staff_create` ignores any client-supplied password for cashiers, managers
  and drivers and generates a hidden random one. `staff_update` ignores
  `new_password` for those roles, requires a new password when promoting a
  staff member to moderator, and rotates the password to a random secret when
  a moderator is demoted. A password therefore never becomes a usable login
  path for PIN staff.
- Phone numbers map to `<international digits>@vip.algomend.app`. No mail is
  ever sent, and no SMS provider is used.

### Rollout order

1. Apply `005_phase0_security.sql` if not already applied.
2. Apply `006_auth_management.sql`.
3. Apply `007_storage_policy_hardening.sql` and `008_fix_audit_log_actor.sql`
   if they are not already applied.
4. Apply `009_staff_pin_auth.sql` (service-role grant for the internal PIN RPC).
5. Deploy `auth-admin` with `--no-verify-jwt`.
6. Release the updated customer and staff apps.

`006` revokes the legacy `rpc_create_staff_member` grant from `PUBLIC`, `anon`,
and `authenticated`. Staff creation in an older app build will fail until the
updated staff app is released.

### Smoke test

```powershell
# Public registration (use a disposable phone)
Invoke-RestMethod -Method Post `
  -Uri "$SUPABASE_URL/functions/v1/auth-admin" `
  -Headers @{ apikey = $ANON_KEY; Authorization = "Bearer $ANON_KEY" } `
  -ContentType 'application/json' `
  -Body (@{
    action = 'customer_register'
    name = 'Test Customer'
    phone = '0550000000'
    password = 'TestPass123!'
  } | ConvertTo-Json)
```

The response contains `recovery_code`; store it, then use it with
`customer_reset_password`. Do not reuse the test phone in production.
