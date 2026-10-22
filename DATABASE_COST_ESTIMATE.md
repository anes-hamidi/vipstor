# Database Cost Estimate — VIP Wholesale & POS System

> **Scenario:** 5,000 monthly active users, 100 online orders/day, 500 POS cashier sales/day, 10 staff members.
>
> **Source:** Based on `DATABASE_USAGE_ESTIMATE.md` analysis of the actual schema (append-only ledgers, `audit_log` triggers, `driver_locations` telemetry, `view_product_stock` full-ledger aggregation).
>
> **Pricing basis:** Supabase Pro tier reference pricing (subject to change; verify on supabase.com/pricing before budgeting).
>
> **Update — current code:** The storage scenarios below reflect the older telemetry/audit configuration (per-ping GPS audit plus audit triggers on `order_items`, `stock_ledger`, and `payments`). With migrations `00027`–`00029` applied, current growth is ~150 MB/month (~1.8 GB/year, ~5.4 GB over 3 years). See `DATABASE_USAGE_ESTIMATE.md` §4. The manager live-order screen now keeps all active online orders live, fetches only the changed order in Realtime, and serves history through a date-filtered paginated query, removing its previous multi-terabyte egress risk.

---

## 1. Workload Summary

### Current optimized code (`00027`–`00029` applied)

| Metric | Monthly Value |
|---|---:|
| Total orders | 18,000 |
| Order lines (items) | 57,000 |
| Stock ledger entries | 57,000 |
| Payments | 18,000 |
| Customer ledger entries | ~1,800 |
| Driver wallet entries | ~3,150 |
| Audit log rows | ~55,000 |
| Business + audit growth | ~125 MB/month |
| **Total DB growth (with bloat)** | **~150 MB/month** |
| Non-dashboard read egress (compressed) | ~12–20 GB/month |
| Average write rate | ~0.12 rows/sec (peak ~20–40/sec) |

### Legacy baseline used in the cost scenarios below

The older model assumed **~523,000 audit rows/month** and **~0.5–0.8 GB/month** because it audited every GPS ping and every `order_item`, `stock_ledger`, and `payments` row. Those triggers were removed by `00027`/`00028`. The scenarios in Sections 2–9 retain those legacy assumptions so the original cost comparison remains readable; use `DATABASE_USAGE_ESTIMATE.md` for current figures.

| Metric | Legacy Monthly Value |
|---|---:|
| Customer ledger entries | ~5,100 |
| Driver wallet entries | ~2,100 |
| Audit log rows | ~523,000 |
| Business data growth | ~51 MB/month |
| **Total DB growth** | **~0.5–0.8 GB/month** |
| Read egress (compressed) | ~15–20 GB/month |
| Read egress (raw/uncompressed) | ~45–50 GB/month |

---

## 2. Storage Cost by Scenario

The dominant cost driver is **audit log storage** (≈90% of growth), driven overwhelmingly by `driver_locations` GPS pings.

| Scenario | 1-year DB size | 3-year DB size | Monthly growth |
|---|---:|---:|---:|
| **Current optimized** — `00027`–`00029` applied | ~1.8 GB | ~5.4 GB | ~150 MB |
| **No audit log + no driver telemetry** | ~0.8 GB | ~2.4 GB | ~65–70 MB |
| **Lean** — no telemetry audit, 400 B audit rows | ~6 GB | ~18 GB | ~430 MB |
| **Base** — as-coded telemetry audit, 500 B rows | ~7–8 GB | ~22–24 GB | ~520 MB |
| **Heavy** — more drivers/longer hours, 800 B rows | ~11–12 GB | ~34–36 GB | ~800 MB |

### Storage tier mapping (Supabase Pro reference)

| Plan | Included DB storage | Coverage at base growth | When to upgrade |
|---|---:|---:|---|
| **Pro** | 8 GB | ~10–15 months | At ~12–18 months |
| **Pro + storage add-on** | 8 GB + pay-per-GB | Indefinite (pay for extra) | Continuous |
| **Team / custom** | 16+ GB | 2+ years at base growth | If you need >8 GB included |

**Recommendation:** Start on **Pro** ($25/month typically). Add storage add-on around month 12–18 at base growth. If you remove `driver_locations` auditing (Phase 3), you can stretch Pro to ~2+ years before needing extra storage.

---

## 3. Read Egress Cost

Egress is the second-largest variable cost. The customer app fetches the full catalogue (~1 MB uncompressed, ~0.37 MB compressed) per session.

| Scenario | Sessions/user/month | Full catalogue loads/session | Compressed egress/month |
|---|---:|---:|---:|
| Low | 4 | 1 | ~7 GB |
| **Base** | **6** | **1.5** | **~16 GB** |
| High | 10 | 2 | ~37 GB |

Plus order history, audit dashboard, manager pipeline: ~1–5 GB/month additional.

**Total base egress ≈ 15–25 GB/month compressed.**

### Egress tier mapping

| Plan | Included egress | Coverage |
|---|---:|---:|
| Free | 5 GB | Exceeded in days–weeks |
| **Pro** | 250 GB | ~10+ months at base |
| Team / custom | Higher | For aggressive sync patterns |

**Recommendation:** Pro tier covers base egress comfortably. Only upgrade if you remove delta sync and refetch full catalogues frequently.

---

## 4. Compute / Request Cost

Write volume is very light: ~35,000 row writes/day (~0.4/sec average). Even at peak (busy counter + telemetry), this is ~20–50 row writes/sec.

Supabase Pro includes generous request/compute quotas. At this volume:
- **API requests:** Well within Pro limits
- **Concurrent connections:** Use PgBouncer/Supavisor; 50–250 concurrent users at peak is manageable on Pro compute (2 vCPU / 4 GB)
- **CPU risk:** The O(N) full-ledger aggregation views (`view_product_stock`, `view_customer_balance`, etc.) will become the main CPU/IO bottleneck as ledgers pass millions of rows — not the write volume itself.

**Recommendation:** Pro compute tier is sufficient. The performance fix (Phase 4 incremental snapshots) matters more than a bigger compute tier.

---

## 5. Monthly Cost Estimate (Reference Pricing)

> *All figures are estimates. Verify current pricing at supabase.com/pricing.*

| Cost component | Low scenario | **Base scenario** | High scenario |
|---|---:|---:|---:|
| Database compute (Pro) | ~$25/mo | **~$25/mo** | ~$25/mo |
| Additional DB storage (add-on) | ~$0–5/mo | **~$5–10/mo** | ~$10–20/mo |
| Egress overage (beyond included) | $0 | **$0** | $0–5/mo (if >250 GB) |
| PITR / backups (if extra) | $0–5/mo | **$0–5/mo** | ~$5–10/mo |
| **Estimated monthly total** | **~$25–30/mo** | **~$30–40/mo** | **~$40–60/mo** |
| **Estimated annual total** | **~$300–360/yr** | **~$360–480/yr** | **~$480–720/yr** |

### 3-year total cost of ownership (storage growth)

| Scenario | Year 1 | Year 3 cumulative |
|---|---:|---:|
| Lean (telemetry audit removed) | ~$300–360 | ~$900–1,200 |
| **Base (as-coded)** | **~$360–480** | **~$1,100–1,500** |
| Heavy | ~$480–720 | ~$1,400–2,200 |

---

## 6. Cost-Saving Actions (Ranked by Impact)

| Action | Estimated monthly savings | Effort |
|---|---:|---:|
| **Remove `driver_locations` per-ping audit** (Phase 3) | Cuts DB growth ~60%; delays storage upgrade by ~12–18 months | Low |
| **Replace full-ledger views with incremental snapshots** (Phase 4) | Avoids compute upgrade as ledger scales; reduces read CPU | Medium |
| **Add delta sync + pagination** (Phase 4) | Cuts egress by 80–95% once catalogues aren't refetched fully each session | Medium |
| **Remove audit on `order_items`, `stock_ledger`, `payments`** (Phase 2) | Cuts audit rows ~33%; small storage saving | Low |
| **Compress images to WebP** (Phase 1) | Cuts storage+egress for product images ~30–50% | Low |
| **Keep 12 months hot audit + archive older** | Caps steady-state DB size | Medium |

**Biggest lever:** Removing per-ping GPS audit logging. It reduces projected 3-year storage from ~22–24 GB to ~8–10 GB, potentially keeping you on the base Pro plan without storage add-ons for years.

---

## 7. Recommended Starting Tier

| Tier | Why |
|---|---|
| **Supabase Pro** | Minimum viable. Includes 8 GB DB, 250 GB egress, sufficient compute. Fits base scenario for ~12–18 months. |
| **Add storage add-on at month 12–18** | Base growth (~0.52 GB/month) will consume the included 8 GB around that time. |
| **Upgrade to Team/custom only if** | You keep per-ping GPS auditing AND need >8 GB included storage, OR you have 100+ concurrent catalogue syncs at peak. |

---

## 8. Risks That Could Increase Cost

| Risk | Cost impact |
|---|---|
| 5,000 users are **concurrent** (not monthly active) | 10–50× request/egress volume; may need read replicas + larger compute |
| Drivers increase from 2 to 5+, running 24/7 | Telemetry audit alone could exceed 1 GB/month; storage cost doubles |
| Full catalogue fetched every few minutes (no delta sync) | Egress could exceed 250 GB/month included limit |
| No audit retention policy | DB grows unbounded; storage cost scales linearly forever |
| Full-ledger views not replaced with snapshots | CPU/IO spikes as ledgers pass millions of rows; may force compute upgrade |

---

## 9. Bottom Line

- **Starting cost: ~$25–40/month** on Supabase Pro for the stated workload.
- **3-year cost: ~$1,100–1,500** at base growth (as-coded), or ~$900–1,200 if you remove per-ping GPS auditing.
- **Storage is the long-term cost driver**, not writes. The audit log (~90% of growth) and GPS telemetry (~66% of audit rows) are the levers to pull.
- **Pro tier is sufficient to start.** Plan for a storage add-on around month 12–18 unless you implement the audit minimization (Phases 2 & 3), which can push that out to 2+ years.
