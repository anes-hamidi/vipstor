# Backend: Supabase & PostgreSQL

## Schema & Migration Strategy

The authoritative fresh-install schema is:

- `backend/supabase/schema/001_fresh_schema.sql` — bundles all migrations through `00033`.

To initialize a new Supabase project, run in order:

1. `backend/supabase/schema/001_fresh_schema.sql`
2. `backend/supabase/seeds/001_admin.sql` (admin only, no demo data)
3. `backend/supabase/operations/verify_installation.sql` (optional health check)

Future schema changes go in `backend/supabase/migrations/` as sequential files starting at `00034`. Historical migrations `00001`–`00033` are archived in `backend/supabase/archive/migrations/` and are reference-only. The old consolidated scripts and the demo seed are in `backend/supabase/archive/legacy/`.

See `backend/supabase/README.md` for setup, reset, and verification commands.

**Never** edit a migration after it has been applied. Always create a new numbered file.  
**Never** write DDL or DML directly from the Flutter client — only via named RPC functions.

## Client Configuration

The Flutter apps read `SUPABASE_URL` and `SUPABASE_ANON_KEY` through `String.fromEnvironment` in `packages/core/lib/constants/app_constants.dart`. There is no compiled fallback project: `ensureSupabaseConfigured()` fails fast when a build omits the values. Local values live in a git-ignored `.env` (template: `.env.example`) and are passed with `--dart-define-from-file=.env`. `scripts/publish_release.ps1` loads `.env` automatically (environment variables win) and forwards the values to every build as `--dart-define`. Never put the `service_role` key in a client app; only the publisher and CI use it.

---

## Append-Only Ledger Tables

```sql
-- Stock movements
stock_ledger (id, product_id, qty_delta, reason, reference_id, client_id, created_at)

-- Customer credit/debit history
customer_ledger (id, customer_id, amount_centimes, ledger_type, reference_id, client_id, created_at)

-- Supplier purchase liabilities
supplier_ledger (id, supplier_id, amount_centimes, ledger_type, reference_id, created_at)

-- Driver cash collections
wallet_entries (id, driver_id, amount_centimes, entry_type, order_id, settlement_id, client_id, created_at)
```

Balance views derived from these tables:
- `view_product_stock` — net `qty_delta` per product
- `view_customer_balance` — net `amount_centimes` per customer
- `view_driver_wallet_balance` — net `amount_centimes` per driver
- `view_supplier_balance` — net `amount_centimes` per supplier

---

## RPC Contracts

All state-mutating operations go through these RPCs. Each is atomic (single transaction) and idempotent via `client_id`.

### `rpc_post_sale`
```sql
rpc_post_sale(
  p_client_id UUID,
  p_cashier_id UUID,
  p_customer_id UUID,          -- nullable (cash sale)
  p_items JSONB,               -- [{product_id, qty, unit_price_centimes, ...}]
  p_payment_method TEXT,       -- 'cash' | 'on_account'
  p_amount_tendered_centimes BIGINT
)
```
Side effects: inserts `order`, `order_items`, `payments`; inserts negative `stock_ledger` rows; inserts `customer_ledger` row if `on_account`.

### `rpc_post_purchase`
```sql
rpc_post_purchase(
  p_client_id UUID,
  p_manager_id UUID,
  p_supplier_id UUID,
  p_items JSONB,               -- [{product_id, qty, unit_cost_centimes}]
  p_invoice_ref TEXT
)
```
Side effects: inserts `purchase`, `purchase_items`; inserts positive `stock_ledger` rows; updates `products.last_unit_cost`; inserts `supplier_ledger` row.

### `rpc_deliver_order`
```sql
rpc_deliver_order(
  p_client_id UUID,
  p_driver_id UUID,
  p_order_id UUID,
  p_cash_collected_centimes BIGINT,
  p_proof_signature TEXT        -- base64 SVG
)
```
Side effects: updates order status → `delivered`; inserts `wallet_entries` row for driver.

### `rpc_settle_driver_wallet`
```sql
rpc_settle_driver_wallet(
  p_driver_id UUID,
  p_cashier_id UUID,
  p_amount_centimes BIGINT
)
```
Side effects: inserts `settlements` row; inserts zero-balancing `wallet_entries` row.

### `rpc_collect_customer_debt`
```sql
rpc_collect_customer_debt(
  p_client_id UUID,
  p_cashier_id UUID,
  p_customer_id UUID,
  p_amount_centimes BIGINT
)
```
Side effects: inserts negative (credit) `customer_ledger` row.

### `rpc_post_return`
```sql
rpc_post_return(
  p_client_id UUID,
  p_cashier_id UUID,
  p_original_order_id UUID,
  p_items JSONB,
  p_restock BOOLEAN
)
```
Side effects: inserts positive `stock_ledger` rows if `p_restock`; inserts `customer_ledger` credit row.

---

## Row-Level Security

All tables have RLS enabled. The Flutter client sends the Supabase JWT; policies map to roles stored in `users.role`.

| Role | Allowed access |
|---|---|
| `moderator` | Full read/write on all tables via RPCs |
| `manager` | Products, purchases, orders (confirm), suppliers |
| `cashier` | Orders (create via RPC), customers, payments |
| `driver` | Own deliveries and wallet entries only |
| `customer` | Own orders and profile only |

Clients never bypass RLS by calling RPCs via `supabase.functions.invoke` — always use `supabase.rpc(...)`.

---

## Staff PIN Authentication

Staff authenticate in two steps:
1. Supabase email/password (or magic link) for the account session.
2. 4-digit PIN checked via `rpc_verify_staff_pin` — PIN stored as `pgcrypto` hash in `users.pin_hash`.

PIN management lives in `packages/data/lib/repositories/auth_repository_impl.dart`. The `IAuthRepository` interface is in `packages/domain/lib/repositories/i_auth_repository.dart`.
