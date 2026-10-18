# Architecture & Non-Negotiable Invariants

## Five Core Architectural Laws

These rules are enforced everywhere — in every PR, every feature, every refactor. There are no exceptions.

---

### 1. Zero-Editable State (Append-Only Ledgers)

Stock levels, customer debts, driver wallets, and supplier balances are **never** stored as mutable columns. They are always derived from immutable ledger rows.

| Balance | Source Table | Materialized As |
|---|---|---|
| Stock on-hand | `stock_ledger` | `view_product_stock` |
| Customer debt | `customer_ledger` | `view_customer_balance` |
| Driver wallet | `wallet_entries` | `view_driver_wallet_balance` |
| Supplier balance | `supplier_ledger` | `view_supplier_balance` |

**Never** `UPDATE products SET stock = stock - 1`. Always `INSERT INTO stock_ledger (product_id, qty_delta, reason, ...)`.

---

### 2. Financial Precision — Integer Centimes

All monetary values throughout the entire stack are stored and calculated as **integer centimes**.

```
1 DZD = 100 centimes
price: 2500 DZD → stored as: 250000 (centimes)
```

- PostgreSQL: `BIGINT`, never `NUMERIC` or `FLOAT`.
- Dart: `int`, never `double`.
- Display: always via `DzdFormatter.formatCentimes(int centimes)` or the `DzdPriceTag` widget from `packages/ui_kit`.

**Never** pass a DZD float to any RPC or store it in any entity. Convert at the UI boundary only.

---

### 3. Clean Architecture Layer Separation

Packages have a strict one-way dependency graph. A lower layer must never import from a higher one.

```
ui_kit / apps  →  domain  →  core
                     ↑
                   data
```

- `core`: Zero dependencies. Dart-only primitives (`Result`, `Failure`, `DzdFormatter`, `AppConstants`).
- `domain`: Zero Flutter. Entities + repository interfaces only. No `http`, no `supabase`, no `drift`.
- `data`: Implements domain repository interfaces. Owns Supabase RPC calls and Drift database.
- `ui_kit`: Flutter only — design tokens and atomic widgets. No business logic.
- `apps/*`: Feature screens, Riverpod providers, GoRouter. Consumes domain + data + ui_kit.

**Never** import `data` from `domain`. **Never** put business logic in `ui_kit` or a screen widget.

---

### 4. Functional Error Handling — `Result<S, F>`

The POS must never crash during active checkout. All repository methods and services return a sealed `Result`.

```dart
// packages/core/lib/error/result.dart
sealed class Result<S, F extends Failure> { ... }
class Success<S, F extends Failure> extends Result<S, F> { final S value; ... }
class FailureResult<S, F extends Failure> extends Result<S, F> { final F error; ... }
```

- **Never** throw exceptions from repository implementations — catch and wrap as `FailureResult`.
- Use `switch` exhaustive pattern matching on `Result` at the Riverpod provider/notifier level.
- Propagate failures to the UI as typed `Failure` objects, not raw strings.

---

### 5. Offline Resilience & Client-Side Idempotency

Every state-mutation originating on a client device carries a **client-generated UUID** (`client_id`). Backend RPCs enforce idempotency so network retries or offline replay never double-count cash or duplicate inventory.

```sql
-- Pattern used in all write RPCs
INSERT INTO stock_ledger (..., client_id)
VALUES (..., p_client_id)
ON CONFLICT (client_id) DO NOTHING;
```

- Generate `client_id` with `const Uuid().v4()` (`uuid` package) before the RPC call.
- Never omit `client_id` from a write RPC payload.
- Backend migrations 00004 and 00014 contain the reference idempotency implementations.

---

## Package Dependency Graph (melos.yaml)

```
core
  └── domain
        └── data
              └── staff_app / customer_app
ui_kit
  └── staff_app / customer_app
l10n
  └── staff_app / customer_app
```

Each package declares only what it needs. `data` depends on `domain` and `core`. Apps depend on everything. Cross-sibling package imports (e.g., `data` importing `ui_kit`) are forbidden.

---

## Backend: RPC-First Principle

The client never writes to PostgreSQL tables directly. All writes go through named RPC functions.

| RPC | Triggered by | Side effects |
|---|---|---|
| `rpc_post_purchase` | Manager receiving invoice | `stock_ledger` ↑, `supplier_ledger` ↑, `product.last_unit_cost` updated |
| `rpc_post_sale` | Cashier checkout | `stock_ledger` ↓, `customer_ledger` ↑ (if on-account), `order` + `payments` inserted |
| `rpc_confirm_order` | Manager pipeline | Order status → `preparing` |
| `rpc_deliver_order` | Driver delivery | `wallet_entries` ↑, order status → `delivered` |
| `rpc_settle_driver_wallet` | End-of-day cashier | `wallet_entries` settlement row, driver balance → 0 |
| `rpc_collect_customer_debt` | Cashier | `customer_ledger` debt payment row |
| `rpc_post_return` | Cashier returns | `stock_ledger` ↑ (optional), `customer_ledger` credit row |
