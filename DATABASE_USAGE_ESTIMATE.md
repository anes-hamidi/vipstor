# Database Usage Estimate — VIP Wholesale & POS System

> **Scenario:** 5,000 monthly active users, 100 online orders/day, 500 cashier/POS sales/day, 10 staff members.
>
> **Basis:** Current repository schema and application query paths, including migrations `00027` (audit minimization), `00028` (driver telemetry optimization), `00029` (balance snapshots), `00030` (audit partitioning readiness), and `00031` (offline sync resilience).
>
> **Important interpretation:** “5,000 online users per month” is treated as **5,000 monthly active users (MAU)**, not 5,000 concurrent users. If it means concurrent, multiply connection, read, and egress figures by roughly 20–50×.

---

## 1. Executive Summary

| Metric | Estimate |
|---|---:|
| Orders per month | 18,000 |
| Order lines / stock-ledger entries per month | ~57,000 |
| Database row writes per day | ~10,000 |
| Average write rate | ~0.12 rows/sec (peak ~20–40/sec) |
| **Storage growth (current optimized schema)** | **~140–160 MB/month** |
| 1-year database growth | ~1.8 GB |
| 3-year database growth | ~5.4 GB |
| Catalogue read egress | ~10–15 GB/month compressed |
| Non-dashboard read egress | ~12–20 GB/month compressed |
| **Manager live-order screen egress** | **~0.5–1.5 GB/month compressed after the split-feed fix** (was 0.1–10 TB/month) |
| Main bottleneck | Full-ledger product views and order-history pagination |

**Bottom line:** The schema is light on writes and storage. At current telemetry/audit settings it grows by roughly **150 MB per month**, so the included 8 GB on Supabase Pro should last around **3–4 years**. The manager live-order screen now keeps every active online order live, fetches only the single order that changes, and serves history through a date-filtered paginated query. That removes the previous multi-terabyte egress risk. The remaining CPU concern is that product reads still aggregate full ledgers; switch those reads to the `00029` snapshot tables.

---

## 2. Workload Assumptions

| Assumption | Base value | Notes |
|---|---:|---|
| Monthly active users | 5,000 | Customer portal accounts |
| Daily active users | 1,000–1,700 | 20–33% of MAU |
| Peak concurrent sessions | 100–250 | Typical for this MAU |
| Sessions per user per month | 6 | Low 4, high 10 |
| Online orders/day | 100 | 3,000/month |
| POS cashier sales/day | 500 | 15,000/month |
| Total orders/day | 600 | 18,000/month |
| Average lines per order | 3.17 | ~57,000 lines/month |
| Staff members | 10 | Logins, shifts, admin actions |
| Drivers | 5 | Used for GPS/event volume |
| Active products | 1,500 | Catalog size assumption; storage is mostly static |
| Price tiers per product | 3 | Retail / wholesale / bulk |
| Barcodes per product | 1.2 | Some products have multiple pack barcodes |
| Business hours | 12 hours/day | Peak around 11:00–13:00 and 17:00–19:00 |
| Audit/telemetry migrations applied | Yes | `00027`, `00028`, `00029` |

If the real product count is 5,000 instead of 1,500, catalogue read egress roughly triples, but database storage changes only slightly because products/prices are mostly one-time master data.

---

## 3. Write-Path Analysis

### 3.1 Rows written per online order

An online order moves through `submitted → confirmed/assigned → preparing → ready → accepted → out_for_delivery → delivered → settled`.

| Write | Rows per order |
|---|---:|
| `orders` insert | 1 |
| `order_items` insert | 3.5 |
| `stock_ledger` insert at delivery | 3.5 |
| `payments` insert at delivery | 1 |
| `wallet_entries` collection | 1 |
| `customer_ledger` (only unpaid balance) | 0.1 |
| `audit_log` (insert + total update + ~7 status updates + wallet) | ~9 |
| Snapshot triggers (`product_stock_snapshot`, `driver_wallet_snapshot`, `customer_balance_snapshot`) | ~4.7 |
| **Total** | **~24 rows** |

### 3.2 Rows written per POS sale

A POS sale is inserted directly as `delivered`; it does not pass through the online status pipeline.

| Write | Rows per sale |
|---|---:|
| `orders` insert | 1 |
| `order_items` insert | 3.1 |
| `stock_ledger` insert | 3.1 |
| `payments` insert | 1 |
| `customer_ledger` (credit sale only) | 0.1 |
| `audit_log` (order insert + occasional ledger entry) | ~1.1 |
| Snapshot triggers | ~3.2 |
| **Total** | **~12.6 rows** |

### 3.3 Daily write volume

| Source | Row writes/day |
|---|---:|
| 500 POS sales × 12.6 | 6,300 |
| 100 online orders × 24 | 2,400 |
| Driver GPS upserts (~5 drivers × 300) | 1,500 |
| Driver location events + their audit rows | ~420 |
| Staff logins, shifts, admin/audit | ~50 |
| **Total** | **~10,700/day** |

That is **~321,000 row writes/month**, equal to **~0.12 writes/sec averaged over 24 hours** or **~0.25/sec over a 12-hour business day**. Peak counter activity plus telemetry might reach **20–40 row writes/sec**, which is comfortably within PostgreSQL/Supabase Pro capacity.

> Note: the 1,500 GPS “writes” are upserts against a table with only 5 current rows. They create little stored data but do create WAL and dead tuples. The 60-second / 50-metre throttle in `driver_telemetry_service.dart` keeps this safe.

---

## 4. Storage Growth by Table

The numbers below include heap + index overhead and use an estimated 75–85% page fill factor. They are approximate (±25–30%).

| Table | Rows/month | Effective bytes/row | Storage/month | Storage/year |
|---|---:|---:|---:|---:|
| `orders` | 18,000 | ~1,000 | 18.0 MB | 216 MB |
| `order_items` | 57,000 | ~200 | 11.4 MB | 137 MB |
| `stock_ledger` | 57,000 | ~360 | 20.5 MB | 246 MB |
| `payments` | 18,000 | ~160 | 2.9 MB | 35 MB |
| `customer_ledger` | 1,800 | ~190 | 0.3 MB | 4 MB |
| `wallet_entries` | 3,150 | ~290 | 0.9 MB | 11 MB |
| `settlements` | 150 | ~200 | 0.03 MB | 0.4 MB |
| `pos_shifts` | 60 | ~600 | 0.04 MB | 0.5 MB |
| `driver_location_events` | 6,300 | ~260 | 1.6 MB | 20 MB |
| `audit_log` | ~55,000 | ~1,250 | 68.8 MB | 826 MB |
| Snapshots, failed ops, versions | fixed | — | ~0.4 MB | ~5 MB |
| **Subtotal** | | | **~125 MB** | **~1.5 GB** |
| Bloat, TOAST, vacuum slack (+20%) | | | **~25 MB** | **~0.3 GB** |
| **Total** | | | **~150 MB** | **~1.8 GB** |

### 4.1 Projection

| Horizon | Current optimized code | Legacy pre-`00027`/`00028`* |
|---|---:|---:|
| 1 month | ~150 MB | ~0.8–1.2 GB |
| 1 year | ~1.8 GB | ~10–14 GB |
| 3 years | ~5.4 GB | ~30–42 GB |
| Supabase Pro 8 GB included storage lasts | ~3–4 years | ~7–10 months |

\* Legacy assumes per-ping GPS audit at a 5-second interval and audit triggers on `order_items`, `stock_ledger`, and `payments`. At the current 60-second throttle and with per-ping audit removed, that volume no longer applies.

### 4.2 Scenario range

| Scenario | Monthly growth | 8 GB lasts |
|---|---:|---:|
| Lean — 4 sessions/user, 2.5 lines/order, 3 drivers | ~110–130 MB | ~5 years |
| **Base — assumptions above** | **~140–160 MB** | **~3–4 years** |
| Heavy — 5 lines/order, 10 drivers, more audit | ~250–350 MB | ~2 years |
| Legacy telemetry/audit configuration | ~800–1,200 MB | ~7–10 months |

---

## 5. Audit-Log Growth

`00027` removed audit triggers from `order_items`, `stock_ledger`, `payments`, and `driver_locations`; `00028` replaced per-ping GPS auditing with event-based `driver_location_events`. As a result, the audit log is no longer the dominant storage driver.

| Audit source | Rows/day | Rows/month | Approx. bytes/row* | Storage/month |
|---|---:|---:|---:|---:|
| POS order insert | 500 | 15,000 | 1,100 | 16.5 MB |
| Online order insert + status updates | 900 | 27,000 | 1,550 | 41.9 MB |
| Wallet entries + settlements | 115 | 3,450 | 700 | 2.4 MB |
| Driver location events | 210 | 6,300 | 600 | 3.8 MB |
| Customer/supplier ledger entries | 60 | 1,800 | 450 | 0.8 MB |
| Staff login/logout, shifts, switches | 26 | 780 | 600 | 0.5 MB |
| Product/user/supplier changes | 8 | 240 | 1,000 | 0.2 MB |
| **Total** | **~1,820** | **~54,500** | **~1,250 avg** | **~66 MB** |

\* Includes heap row plus the seven audit indexes. Online order `UPDATE` audits store both `before_state` and `after_state`, so they are the largest rows.

**Annual audit growth:** ~0.8 GB. That is roughly **10× lower** than the 523,000 rows/month assumed in the earlier cost estimate, because that estimate reflected the old GPS/audit configuration.

### 5.1 Audit retention

At 55,000 rows/month, retaining 24 months produces ~1.3 million rows and ~1.6 GB. This is manageable without partitioning, but partitioning is still recommended for maintenance and retention:

- The partitioned `audit_log_partitioned` table and monthly partitions already exist from `00030`, but application writes still go to the old `audit_log` table.
- Either migrate writes to the partitioned table or add a monthly archive/delete job.
- Suggested policy: 12–24 months hot, older rows exported to object storage.

---

## 6. Read Volume and Egress

### 6.1 Catalogue reads

The customer app fetches the full catalogue whenever its 5-minute cache is stale:

- `view_customer_products` (product + stock + prices)
- `product_prices` for all product IDs
- `product_barcodes` for all product IDs

At 1,500 products, the response is roughly **1 MB uncompressed / 0.25–0.35 MB compressed** per full sync.

| Item | Estimate |
|---|---:|
| Sessions/month | 5,000 × 6 = 30,000 |
| Full catalogue loads/session | ~1.3 |
| Catalogue loads/month | ~39,000 |
| Compressed egress | **~10–14 GB/month** |

At 5,000 products, this becomes roughly **30–40 GB/month**. Still acceptable on Pro, but delta sync would cut it by 80–95%.

### 6.2 Order history and staff operations

| Source | Estimate |
|---|---:|
| Customer order history (30,000 sessions × ~30 KB) | ~0.9 GB/month |
| Staff catalogue/product syncs | ~0.2 GB/month |
| Staff sales history, dashboards, audit views | ~1–3 GB/month |
| **Non-dashboard total** | **~12–20 GB/month compressed** |

### 6.3 Manager live-order screen — split live feed and date-filtered history

The previous implementation called `repo.getOrders()` with no channel filter, no status filter, and no pagination, then reloaded the entire order history every 6 seconds plus on every `orders`/`order_items` Realtime event. That could reach **0.1–10 TB/month**.

The current implementation separates the screen into two paths:

1. **Live pipeline:** loads all active online orders only (`submitted`, `requires_manager_review`, `confirmed`, `preparing`, `ready`, `assigned`, `accepted`, `out_for_delivery`). There is no row limit and no date filter, so an old stuck order cannot disappear.
2. **Realtime:** subscribes to `orders` only. On a new or updated active online order, fetches **only that one order** with `getOrderById()`. POS/store events are ignored. Terminal orders are removed from the live list immediately.
3. **History:** queries online orders in the four terminal statuses (`delivered`, `settled`, `refused`, `cancelled`) by a selected date range. It is paginated at 100 rows per page with a date-range picker; the default is the last 30 days. There is no hard 500-row cap.
4. **Fallback:** refreshes the small active list every **60 seconds** if Realtime is unavailable. The history list refreshes on demand, on date change, and after terminal-order events.

Approximate post-fix payload:

| Item | Estimate |
|---|---:|
| Active list (~50 active orders × ~1.3 KB) | ~65 KB uncompressed |
| Compressed active refresh (~4:1) | ~16 KB |
| 8 hours/day, 60-second fallback (480 refreshes) | ~31 MB/day raw (~8 MB/day compressed) |
| Single-order fetches (~1,000 online events/day × ~2 KB) | ~2 MB/day raw |
| History page (100 orders × ~1.3 KB) | ~130 KB uncompressed (~33 KB compressed) |
| **Manager screen egress, worst case** | **~0.5–1.5 GB/month compressed** |

This removes the multi-terabyte egress risk while keeping the full active pipeline live. History is no longer capped at 500 rows; it is bounded by the selected date range and loaded page by page.

---

## 7. Throughput, Connections, and Compute

### 7.1 Request rate

| Source | Requests/day |
|---|---:|
| Catalogue syncs (~1,300 loads × 3 requests) | ~3,900 |
| Customer order history | ~1,000 |
| Manager realtime patches + 60-second active refresh + history pages (8 h/day) | ~1,500 |
| POS sale RPCs | 500 |
| Online order RPCs/status updates | ~1,000 |
| Staff/admin operations | ~100 |
| **Total** | **~8,000/day** |

That is roughly **0.13 requests/sec average** and perhaps **5–20 requests/sec at peak** — very low for PostgreSQL.

### 7.2 Connections

- 100–250 concurrent app sessions at peak.
- Most sessions are idle and hold no database connection.
- Use Supavisor/PgBouncer in transaction mode.
- Supabase Pro compute (2 vCPU / 4 GB) is sufficient **if** the expensive query patterns below are fixed.

### 7.3 Where CPU actually goes

1. **Full-ledger product views.** `view_product_stock` and `view_customer_products` aggregate the entire `stock_ledger` (and active `order_items`) on every catalogue sync. That is ~39,000 full aggregations per month, over a ledger that reaches ~684,000 rows by month 12 and ~2 million rows by year 3.
2. **Moderator dashboard.** It fetches all orders and all product stock rows to compute KPIs client-side. This is infrequent, but it becomes slower as history grows.
3. **Manager live-order feed.** The old 6-second full-history reload was removed. It now refreshes the small active-order list every 60 seconds, fetches one order per Realtime event, and loads history only for the selected date range and page. This is no longer a CPU concern.

`00029` created `product_stock_snapshot`, `customer_balance_snapshot`, `driver_wallet_snapshot`, and `supplier_balance_snapshot`, but the repositories and RPCs still read the old aggregation views. Switching to the snapshots removes the biggest recurring CPU cost.

---

## 8. Fit Against Supabase Pro Reference Limits

| Resource | Included on Pro | This workload | Verdict |
|---|---:|---|---|
| Database storage | 8 GB | ~150 MB/month → ~1.8 GB/year | Fine for ~3–4 years |
| Egress | 250 GB/month | 12–20 GB without manager screen | Fine |
| Egress with manager screen open | 250 GB/month | ~13–22 GB/month after fix | Fine |
| Compute | 2 vCPU / 4 GB | Low writes; high query cost from full-ledger views | Fine after P0 fixes |
| Connections | Pooled | 100–250 concurrent sessions | Fine with pooler |
| PITR/backups | Add-on | ~2 GB year 1 | Low cost |

---

## 9. Recommendations

### P0 — before production launch

1. **Manager live-order feed — implemented.**
   - The live pipeline loads all active online orders; there is no 500-row cap or date filter.
   - Realtime events fetch a single order by ID and patch it into local state.
   - POS/store events are ignored; terminal orders move to the history path.
   - History is date-filtered with a range picker and paginated at 100 rows/page (default last 30 days).
   - The active-list fallback is now 60 seconds.
   - Expected impact: order-screen egress drops from **TB/month to ~0.5–1.5 GB/month**.

2. **Read balances from snapshots, not ledger aggregates.**
   - Replace `view_product_stock` with `product_stock_snapshot` in product sync and RPC stock checks.
   - Replace `view_customer_balance`, `view_driver_wallet_balance`, and `view_supplier_balance` with their snapshot tables.
   - Keep the views only as compatibility fallbacks.
   - Expected impact: removes an O(N) full-ledger scan from every catalogue sync and stock check.

3. **Apply the same date-filtered pagination to the remaining order-history paths.**
   - Manager online-order history is now date-filtered and paginated.
   - Customer order history should load recent orders first, with “load more”.
   - Staff sales history should be date-filtered and paginated.

4. **Stop full-table KPI scans in the moderator dashboard.**
   - Compute totals with server-side aggregate RPCs or filtered queries (`created_at >= now() - interval '30 days'`).
   - Fetch only the 7-day window needed for the sparkline.

### P1 — first month after launch

5. **Implement audit retention/partitioning.**
   - Switch writes to `audit_log_partitioned` or add a monthly archive job.
   - Retain 12–24 months hot; export older partitions.
   - This is not urgent at 55k rows/month, but it prevents unbounded growth.

6. **Add catalogue delta sync.**
   - Send `updated_at` and fetch only changed products/prices/barcodes.
   - Add ETag/If-None-Match or a `last_sync` timestamp.
   - Compress product images to WebP.
   - Expected impact: catalogue egress drops from ~12–15 GB to ~2–4 GB/month.

7. **Slim order audit payloads.**
   - On status updates, store only changed fields or a compact diff instead of full `before_state` + `after_state`.
   - Expected impact: up to 50–60% reduction in audit storage, if needed.

8. **Add targeted indexes.**
   - Partial index for the active online pipeline:
     ```sql
     CREATE INDEX IF NOT EXISTS idx_orders_active_online
     ON orders (created_at DESC)
     WHERE channel = 'online'
       AND status IN ('submitted','confirmed','preparing','ready',
                      'assigned','accepted','out_for_delivery');
     ```
   - Add `payments(order_id)` and `wallet_entries(payment_id)` if missing.
   - Keep `order_items(order_id, product_id)`.

### P2 — scale/ops

9. Keep the current 60-second / 50-metre GPS throttle. Do not reintroduce per-ping audit rows.
10. Tune autovacuum for `driver_locations`, `orders`, and the snapshot tables.
11. Alert on egress, `pg_stat_statements` total time, and table bloat.

---

## 10. Monitoring Queries

Run these monthly (or weekly after launch) to replace estimates with real numbers.

### Table sizes and row counts

```sql
SELECT
    relname,
    n_live_tup,
    pg_size_pretty(pg_total_relation_size(relid)) AS total_size,
    pg_size_pretty(pg_relation_size(relid))       AS heap_size,
    pg_size_pretty(pg_total_relation_size(relid) - pg_relation_size(relid)) AS index_toast
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(relid) DESC;
```

### Monthly audit growth and average row size

```sql
SELECT
    date_trunc('month', created_at) AS month,
    count(*) AS rows,
    pg_size_pretty(sum(pg_column_size(t))::bigint) AS payload,
    round(avg(pg_column_size(t))) AS avg_row_bytes
FROM audit_log t
GROUP BY 1
ORDER BY 1 DESC;
```

### Orders per day by channel

```sql
SELECT
    date_trunc('day', created_at) AS day,
    channel,
    count(*) AS orders
FROM orders
GROUP BY 1, 2
ORDER BY 1 DESC;
```

### Largest queries by total time

```sql
SELECT
    calls,
    rows,
    round(total_exec_time::numeric, 1) AS total_ms,
    round(mean_exec_time::numeric, 1) AS mean_ms,
    left(query, 120) AS query
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 20;
```

### Table bloat / dead tuples

```sql
SELECT
    relname,
    n_live_tup,
    n_dead_tup,
    last_autovacuum,
    last_autoanalyze
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC;
```

---

## 11. Bottom Line

- **Storage is not the problem.** Current optimized code grows ~150 MB/month (~1.8 GB/year, ~5.4 GB over 3 years). Supabase Pro’s 8 GB included storage should last roughly 3–4 years.
- **Audit logging is no longer the dominant cost.** `00027`/`00028` cut audit growth from hundreds of thousands of rows per month to ~55,000.
- **The manager screen egress issue is fixed.** It now keeps all active online orders live, fetches only the changed order, and serves history through a date-filtered paginated query, reducing egress from **0.1–10 TB/month** to roughly **0.5–1.5 GB/month**.
- **Full-ledger views are the remaining CPU problem.** `00029` snapshots exist but are not used by the read paths. Switch to them before the ledger reaches millions of rows.
- **Supabase Pro is sufficient** once P0 items are fixed. Without them, egress overages and CPU will force a larger plan long before storage does.

---

## 12. Scenario: Remove the Audit Log and Driver Telemetry Entirely

This scenario assumes:

- `audit_log`, all audit triggers, and all application audit inserts are removed.
- `driver_locations`, `driver_location_events`, the telemetry service, and customer live-tracking are removed.
- Core business tables (`orders`, `order_items`, `stock_ledger`, `payments`, `wallet_entries`, `settlements`, `pos_shifts`) remain.

### 12.1 Storage impact

| Metric | With audit + telemetry | Without both | Difference |
|---|---:|---:|---:|
| Storage growth | ~150 MB/month | **~65–70 MB/month** | ~80–85 MB/month |
| 1-year growth | ~1.8 GB | **~0.8 GB** | ~1.0 GB |
| 3-year growth | ~5.4 GB | **~2.4 GB** | ~3.0 GB |
| Row writes/day | ~10,700 | ~7,000 | ~3,700 |
| 8 GB Pro disk exhausted | ~4.3 years | **~9–10 years** | ~5–6 years later |

The savings come almost entirely from the audit log (~69 MB/month). Driver telemetry is already small:

- `driver_location_events`: ~1.6 MB/month.
- Its audit rows: ~3.8 MB/month.
- `driver_locations`: 5 current rows; removing it saves essentially no storage.
- GPS uploads: ~1,500 upserts/day; they cost WAL/CPU, not meaningful disk space.

In other words, removing driver telemetry saves **~5 MB/month**. Removing the audit log saves **~69 MB/month**.

### 12.2 Cost impact at Supabase Pro pricing

Reference pricing (supabase.com/pricing): Pro from **$25/month**, including 8 GB disk and 250 GB egress. Disk overage is **$0.125/GB-month**; egress overage is **$0.09/GB**.

| Cost item | With audit + telemetry | Without both |
|---|---:|---:|
| Pro plan | $25/month | $25/month |
| Disk overage in year 1–3 | $0 | $0 |
| Disk overage around year 5 | ~$0.13/month | $0 |
| Disk overage around year 10 | ~$1.25/month | $0 |
| **3-year TCO (no egress overage)** | **~$900** | **~$900** |
| Egress overage with the current live/date-filtered manager feed | $0 | $0 |
| Egress overage if the old 6-second full-history polling returns | $90–900+/month by year 1–2 | **unchanged** |

**The monthly cost is identical for the first ~4 years.** Both scenarios fit inside the included 8 GB. Over a 10-year horizon, removing the audit log might save roughly **$1/month**, which is not a meaningful optimization.

### 12.3 What you lose

- **No audit trail:** no evidence of who changed prices, stock, credit limits, payments, or staff permissions; no fraud/discrepancy investigation; no shift/security accountability; possible accounting/compliance exposure.
- **No driver tracking:** customer live tracking, driver map, ETA, clock-in/out, and trip history stop working.
- **No operational history:** the audit dashboard and driver event timeline become empty.

### 12.4 Recommendation

Do **not** remove them for cost reasons. The current audit + telemetry footprint is only about **5–6% of the 8 GB Pro disk in year 1**. The manager live-order screen now uses a live active-order feed plus date-filtered paginated history, which removes the previous **$90–900+/month** egress risk.

If you need to reduce the audit footprint without losing protection:

1. Keep 6–12 months of hot audit data and archive older partitions.
2. Audit only financial/security tables (`orders`, `payments`, `settlements`, `wallet_entries`, `users`, `purchases`).
3. Store changed fields or a compact diff instead of full `before_state` + `after_state` on order updates.
4. Keep driver telemetry at the current 60-second throttle; its storage cost is negligible.
5. Keep the manager order feed bounded and switch product reads to the snapshot tables — those changes save far more than deleting audit/telemetry.
