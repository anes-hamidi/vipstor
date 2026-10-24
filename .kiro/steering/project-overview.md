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

Supabase (PostgreSQL 15+). A new project is created from `backend/supabase/schema/001_fresh_schema.sql` (through migration `00033`) plus `backend/supabase/seeds/001_admin.sql`. Future schema changes go in `backend/supabase/migrations/` starting at `00034`; older migrations are archived under `backend/supabase/archive/migrations/`. Business logic lives exclusively in PostgreSQL RPC functions — the client never writes to tables directly. Clients receive `SUPABASE_URL` and `SUPABASE_ANON_KEY` at build time through `--dart-define-from-file=.env` (template: `.env.example`); the service role key is never shipped.

## Key Tech Stack

- Flutter 3.x / Dart 3.x
- Riverpod 2.x (state management)
- GoRouter 14.x (navigation with role guards)
- Supabase (remote database + auth + storage)
- Drift (local SQLite cache)
- `pdf` + `printing` (ESC/POS thermal receipts, Z-reports, PDF invoices)
- Geolocator + flutter_map (driver location tracking)
- Melos (monorepo tooling)
