# VIP Wholesale & POS Management — Supabase Backend

## 📌 Overview

This directory contains the **authoritative, unified database schema, security policies (RLS), role-based permissions (RBAC), immutable ledgers, and transaction RPC functions** for the VIP Wholesale & POS System.

Instead of dozens of fragmented and conflicting migration patches, the entire backend is now consolidated into **two authoritative scripts**:

1. **[`init_fresh_database.sql`](./init_fresh_database.sql)** — The master schema, tables, immutable ledgers, triggers, audit logging, security policies, and atomic RPC functions.
2. **[`seed.sql`](./seed.sql)** — Initial master data with the default Moderator, sample staff, sample customer, suppliers, products with multi-tier pricing, and opening inventory.

---

## 🚀 Quick Setup Instructions

### On a Brand New or Reset Supabase Project:
1. Open the **SQL Editor** in your Supabase Dashboard.
2. Copy and execute **[`init_fresh_database.sql`](./init_fresh_database.sql)**.
3. Copy and execute **[`seed.sql`](./seed.sql)**.

That is all! Your database is now completely initialized, secure, and ready for both the **Staff App** and the **Customer App**.

---

## 🔑 Default Accounts (Seed)

| Role | Name | Phone Number | Default PIN | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| **Moderator** | المدير العام | `0673336972` | `1234` | Full system administrator, staff management, audit log, KPI reports |
| **Manager** | مسؤول المخزن أحمد | `0550000002` | `1234` | Stock management, purchases, supplier invoices, inventory adjustments |
| **Cashier** | كاشير الكاونتر يوسف | `0550000003` | `1234` | Counter POS sales, customer debt collections, driver settlements |
| **Driver** | سائق التوصيل علي | `0550000004` | `1234` | Assigned deliveries, cash collection on delivery, live GPS telemetry |
| **Customer** | ميني ماركت الأمل | `0550000005` | _(Phone OTP)_ | Wholesale customer catalog browsing, online ordering, delivery tracking |

> ⚠️ **Security Warning**: Change all default PINs immediately upon production deployment using the app's in-app PIN settings.

---

## 🛡️ Architecture & Security Model

### 1. Hybrid Authentication & RLS Compatibility
- **Staff Authentication**:
  - Staff authenticate via their **4-digit PIN** verified on the server using **bcrypt** via `rpc_verify_user_pin`.
  - Rate-limiting and progressive lockout prevents brute-force attempts:
    - 5 failed attempts $\rightarrow$ 1 minute lockout
    - 10 failed attempts $\rightarrow$ 5 minute lockout
    - 15 failed attempts $\rightarrow$ 15 minute lockout
  - The client interacts using the Supabase client without requiring a separate email/password Supabase Auth session.
  - Sensitive columns (`pin_code`) are **never exposed** through PostgREST column grants.
- **Customer Authentication**:
  - Customers authenticate via phone OTP or self-register their profile and delivery addresses.
  - Customers can only see their own orders, items, and debt balances.

### 2. Role-Based Access Control (RBAC)
Granular permissions are stored in `permissions` and bound to roles in `role_permissions`:
- `products.read`, `products.manage`
- `orders.view_all`, `orders.view_assigned`, `orders.view_own`, `orders.create_counter`, `orders.create_online`, `orders.manage_status`, `orders.deliver`
- `purchases.manage`, `suppliers.manage`, `customers.manage`
- `finance.collect_debt`, `finance.settle_wallet`, `finance.view_reports`
- `staff.manage`, `staff.reset_pin`, `audit.view`, `telemetry.driver_gps`

Helper functions:
- `has_permission(p_role, p_permission_code)`
- `get_role_permissions(p_role)`

### 3. Strictly Immutable Append-Only Ledgers
Financial and inventory transactions are **never modified or deleted**. Three append-only ledgers serve as the single source of truth:
- **`stock_ledger`**: All inventory movements (sales, purchases, returns, adjustments).
- **`customer_ledger`**: Customer credit/debt balances.
- **`supplier_ledger`**: Shop liabilities to suppliers.

Triggers (`trg_block_immutable_ledger_modifications`) actively intercept and reject any `UPDATE` or `DELETE` statements on these tables.

### 4. Comprehensive Audit Trail
- The **`audit_log`** table automatically captures all inserts, updates, and deletes across all 16 operational tables.
- Strips confidential fields (`pin_code`) before recording states.
- Automatically resolves actor attribution (`user_id`, `cashier_id`, `driver_id`, `created_by`, `customer_id`).
- Captures caller IP address (`inet_client_addr()`).
- Direct client writes to `audit_log` are **strictly forbidden**.
- The **`view_audit_log_enriched`** view translates technical events into intelligent, categorized Arabic action titles for the Moderator Dashboard.

### 5. Atomic Transaction RPC Functions (ACID)
All critical business operations are encapsulated within `SECURITY DEFINER` functions with transaction management, deadlock prevention (ordered locks), and idempotency:
- `rpc_verify_user_pin`: Rate-limited PIN verification.
- `rpc_change_user_pin`: Self PIN update.
- `rpc_reset_user_pin_by_admin`: Moderator PIN reset.
- `rpc_create_staff_member`: Moderator-authorized staff creation.
- `rpc_post_store_sale`: Counter POS sale with stock verification, ledger debits, and customer credit checks.
- `rpc_collect_customer_debt`: Customer debt collection and payment generation.
- `rpc_confirm_online_order`: Online order confirmation and stock reservation.
- `rpc_record_order_delivery`: Idempotent order delivery and driver cash collection.
- `rpc_settle_driver_wallet`: End-of-day driver cash settlement and discrepancy flagging.
- `rpc_post_purchase`: Post supplier purchase invoice and update inventory cost.
- `rpc_adjust_stock`: Manual stock adjustment.
- `rpc_create_product`: Atomic creation of product, barcodes, tiered prices, and opening stock.
- `rpc_submit_customer_order`: Online customer order submission with server-side tiered price resolution.

---

## 📊 Derived Views Reference

| View Name | Target Audience | Description |
| :--- | :--- | :--- |
| **`view_product_stock`** | Staff / Moderator | Inventory stock with `on_hand_qty`, `reserved_qty`, `available_qty`, and unit cost. |
| **`view_customer_products`** | Customers / Anon | Sanitized catalog masking internal costs and margins, showing stock status. |
| **`view_driver_wallet_balance`**| Drivers / Cashier | Net driver cash balance from collected payments minus handovers. |
| **`view_customer_balance`** | Cashier / Moderator | Real-time customer debt balance computed from `customer_ledger`. |
| **`view_supplier_balance`** | Manager / Moderator | Real-time supplier liability computed from `supplier_ledger`. |
| **`view_audit_log_enriched`** | Moderator | Human-readable audit trail with categorized Arabic labels for dashboard monitoring. |
