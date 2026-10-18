# Features & Module Map

## staff_app — Role Breakdown

### Cashier (`apps/staff_app/lib/features/cashier/`)

High-speed POS counter used by cashiers.

**Key files:**
- `counter_pos_screen.dart` — main POS screen
- `models/pos_models.dart` — `PosCartItem`, `PosHeldTicket`, etc.
- `services/pos_thermal_printer.dart` — ESC/POS 80mm receipt printing
- `services/thermal_hardware_service.dart` — Bluetooth/USB printer discovery

**Widgets:**
| Widget | Purpose |
|---|---|
| `pos_checkout_dialog.dart` | Finalize sale, select payment method, cash tendering |
| `customer_select_dialog.dart` | Search customers for on-account sales |
| `customer_debt_dialog.dart` | Collect debt payment from a customer |
| `sales_return_dialog.dart` | Process item-level returns with reason codes |
| `shift_audit_dialog.dart` | Z-Report: denomination counter + variance |
| `held_tickets_sheet.dart` | Suspend / resume carts |
| `item_discount_dialog.dart` | Per-line discount (% or fixed DZD) |
| `custom_item_dialog.dart` | Add an unlisted product to the cart |
| `sales_history_dialog.dart` | Look up past receipts by Order ID or barcode |
| `pos_keyboard_dispatcher.dart` | F1–F12 + Space/Enter/Esc hotkeys |
| `pos_header_status_bar.dart` | Connection status, cashier name, shift clock |
| `pos_product_card.dart` | Product tile in the catalog grid |
| `pos_cart_line_item_tile.dart` | Cart row with quantity stepper + unit switcher |
| `pos_category_filter_bar.dart` | Horizontal category chip scroller |
| `printer_settings_dialog.dart` | Configure thermal printer connection |

**Business rules:**
- Multi-unit selling: Piece / Pack / Carton / Box per SKU.
- Credit limit enforcement before confirming on-account sale.
- `client_id` UUID generated before every `rpc_post_sale` call.
- Shift audit Z-Report increments a sequential non-resettable counter.

---

### Manager (`apps/staff_app/lib/features/manager/`)

Inventory, purchases, and order pipeline management.

**Key files:**
- `purchase_receiving_screen.dart` — receive supplier invoices
- `services/pdf_invoice_service.dart` — generate PDF purchase invoices
- `widgets/online_orders_pipeline_view.dart` — Kanban-style order pipeline
- `widgets/create_product_dialog.dart` — create/edit products with image upload
- `widgets/create_supplier_dialog.dart` — add/edit suppliers

**Business rules:**
- Every purchase calls `rpc_post_purchase`; never directly inserts into `purchase_items`.
- Multi-tier pricing (Retail / Wholesale / Bulk) stored in `product_prices`.
- Product images uploaded to Supabase Storage bucket (`product-images`).
- Order confirmation triggers `rpc_confirm_order` → status `preparing`.

---

### Driver (`apps/staff_app/lib/features/driver/`)

Delivery logistics and cash collection.

**Key files:**
- `driver_deliveries_screen.dart` — list of assigned deliveries
- `widgets/proof_of_delivery_dialog.dart` — signature capture (base64 SVG)
- `widgets/driver_map_view.dart` — live route map via flutter_map
- `services/driver_telemetry_service.dart` — background GPS reporting to `driver_locations`

**Business rules:**
- Every delivery calls `rpc_deliver_order` with `client_id`, cash collected, and proof signature.
- Driver wallet balance derived from `view_driver_wallet_balance`.
- End-of-day settlement calls `rpc_settle_driver_wallet`.

---

### Auth (`apps/staff_app/lib/features/auth/`)

Two-factor staff login: Supabase email/password → 4-digit PIN.

**Key files:**
- `login_screen.dart` — email login screen
- `widgets/change_pin_dialog.dart` — change PIN dialog
- `widgets/cashier_pin_dialog.dart` — quick PIN re-entry for screen lock

**Business rules:**
- PIN verified via `rpc_verify_staff_pin`.
- GoRouter redirect guard checks both `session != null` AND `pinVerified == true`.

---

### Moderator (`apps/staff_app/lib/features/moderator/`)

Admin dashboard with financial KPIs, audit logs, and staff management.

**Key files:**
- `moderator_dashboard_screen.dart` — top-level dashboard
- `widgets/create_staff_dialog.dart` — create staff accounts with role
- `widgets/generate_staff_pin_dialog.dart` — reset/generate PIN for a staff member
- `widgets/audit_log_details_dialog.dart` — inspect individual audit trail entries

**Business rules:**
- Only `moderator` role can create staff users or reset PINs.
- KPI tiles read from `view_product_stock`, `view_customer_balance`, `view_driver_wallet_balance`.
- Full audit trail available via `audit_log` table (populated by DB triggers from migration 00003 + 00012).

---

## customer_app — Feature Breakdown

Located at `apps/customer_app/lib/features/`.

| Feature | Screen | Purpose |
|---|---|---|
| `catalog` | `catalog_screen.dart` | Browse wholesale product catalog with tiered prices |
| `cart` | `cart_screen.dart` | Manage cart, view totals, place order |
| `orders` | `my_orders_screen.dart` | Track order lifecycle (pending → preparing → ready → delivered) |
| `orders/widgets` | `customer_order_tracking_view.dart` | Real-time status tracker widget per order |
| `orders/services` | `customer_invoice_service.dart` | Generate PDF delivery invoice for customer |
| `profile` | `profile_form_screen.dart` | Set delivery address, contact info |

**Business rules:**
- Customer auth uses the same Supabase JWT but with `role = customer` — no PIN step.
- Order placement calls `rpc_post_sale` with `p_payment_method = 'on_account'` and the customer's UUID.
- Customers see their own orders only (enforced by RLS).
- Catalog shows wholesale pricing tier by default.

---

## Providers Map

All providers live in `apps/<app>/lib/providers/` or co-located in the feature folder.

| Provider | App | Responsibility |
|---|---|---|
| `staff_providers.dart` | staff_app | Auth state, product list, customer list, order list |
| `customer_providers.dart` | customer_app | Auth state, catalog, cart, order tracking |

Repositories are injected via Riverpod `Provider`; screens consume `AsyncValue<T>` from `AsyncNotifier`.
