# Project Overview

## What This Project Is

**VIP Wholesale & POS Management System** — an offline-resilient, high-throughput enterprise platform built with Flutter/Dart, backed by an append-only PostgreSQL/Supabase engine and a local-first Drift SQLite cache.

This is a Melos monorepo targeting Android, iOS, Windows, macOS, Linux, and Web. It ships two separate Flutter applications and five shared packages under one workspace.

## The Two Apps

| App | Path | Users |
|---|---|---|
| `staff_app` | `apps/staff_app/` | Moderators (admin), Managers (inventory), Cashiers (POS), Drivers (logistics) |
| `customer_app` | `apps/customer_app/` | B2B wholesale buyers placing and tracking orders |

A universal launcher at `lib/main.dart` routes between them at runtime.

## Shared Packages (Melos workspace)

| Package | Path | Role |
|---|---|---|
| `core` | `packages/core/` | Zero dependencies. `Result<S,F>`, `Failure` types, `DzdFormatter`, `AppConstants`. |
| `domain` | `packages/domain/` | Pure Dart. Entities and repository interfaces only. No Flutter. |
| `data` | `packages/data/` | Infrastructure: Supabase RPCs, Drift SQLite, repository implementations. |
| `ui_kit` | `packages/ui_kit/` | Design tokens (colors, spacing, radius, shadows, gradients) + atomic widgets. |
| `l10n` | `packages/l10n/` | Arabic (RTL, default) and French (LTR) ARB localizations. |

## Backend

Supabase (PostgreSQL 15+). All schema changes are sequential numbered migrations under `backend/supabase/migrations/`. Business logic lives exclusively in PostgreSQL RPC functions — the client never writes to tables directly.

## Key Tech Stack

- Flutter 3.x / Dart 3.x
- Riverpod 2.x (state management)
- GoRouter 14.x (navigation with role guards)
- Supabase (remote database + auth + storage)
- Drift (local SQLite cache)
- `pdf` + `printing` (ESC/POS thermal receipts, Z-reports, PDF invoices)
- Geolocator + flutter_map (driver location tracking)
- Melos (monorepo tooling)
