# VIP Wholesale & POS Enterprise System

An offline-resilient, high-throughput Point of Sale (POS), Wholesale Shop Management, and Logistics Distribution platform built with **Flutter**, **Dart**, **Riverpod**, and **Supabase / PostgreSQL**.

---

## 📚 Master Documentation Index

To maintain consistency and follow the development process without architectural deviations or merge conflicts, refer to the following comprehensive documentation:

1. **[PROJECT_CONTEXT.md](PROJECT_CONTEXT.md)**:
   - As-built overview of the monorepo, backend schema/RPCs, auth, offline sync, workflows, and known risks.
   - Generated from the current source; prefer it over older docs when they disagree.
2. **[DATABASE_USAGE_ESTIMATE.md](DATABASE_USAGE_ESTIMATE.md)**:
   - Capacity model for 5,000 monthly users, 100 online orders/day, and 500 POS sales/day.
   - Storage, audit-log growth, write throughput, egress, and Supabase sizing recommendations.
3. **[CONTEXT.md](file:///c:/Users/fethi/Desktop/vipSmock/vip/CONTEXT.md)**:
   - Complete system vision, domain models, business workflows, and directory hierarchy.
   - Non-negotiable architectural rules (Zero-Editable State, Centimes Integer Precision, Result Pattern).
   - Module specifications (Cashier POS, Manager Purchases, Driver Deliveries, Moderator Audits).
4. **[CHANGELOG_AUDIT.md](file:///c:/Users/fethi/Desktop/vipSmock/vip/CHANGELOG_AUDIT.md)**:
   - Full chronological audit log of all release milestones, migrations, and file mutations.
   - Verification benchmarks, test results, and guidelines to avoid regressions.
5. **[DEVELOPER_GUIDE.md](file:///c:/Users/fethi/Desktop/vipSmock/vip/DEVELOPER_GUIDE.md)**:
   - Technical guide covering PostgreSQL single-transaction RPC procedures, dynamic ledger balance views, and role-based access control (RBAC).

---

## 🏗️ Architecture & Monorepo Structure

```
vip/
├── .env.example           # Local Supabase configuration template (copy to .env)
├── apps/
│   ├── staff_app/         # Moderator, Manager, Cashier (POS), Driver
│   └── customer_app/      # Wholesale B2B Client Ordering Portal
├── packages/
│   ├── core/              # Currency Formatter, Result<S,F>, Failures, Constants
│   ├── domain/            # Pure Dart Entities & Repository Interfaces
│   ├── data/              # Repositories, Remote Supabase, Local Drift SQLite
│   ├── ui_kit/            # Design System (Tokens, Themes, Atomic Widgets)
│   └── l10n/              # Arabic (RTL) & French Localization
├── backend/
│   └── supabase/          # Fresh schema, admin seed, operations, archived migrations
└── lib/
    └── main.dart          # Universal Root Application Launcher
```

---

## 🚀 Quick Start

### 1. Run the Desktop Windows POS Application
```powershell
flutter run -d windows
```

### 2. Run the Web Version
```powershell
flutter run -d chrome
```

### 3. Run Static Code Analysis
```powershell
dart analyze apps/staff_app/lib/features/cashier apps/staff_app/lib/providers
```

### Supabase configuration

The app reads `SUPABASE_URL` and `SUPABASE_ANON_KEY` at build time. Copy
`.env.example` to `.env`, fill in the new project's values, then run:

```powershell
flutter run -d windows --dart-define-from-file=.env
```

`.env` is git-ignored. Add the same flag to your IDE run configuration.
Explicit `--dart-define=SUPABASE_URL=...` flags also work. The apps have no
compiled fallback project, so a build without these values fails fast.

Release builds and CI use the same flags; see
[`backend/supabase/README.md`](backend/supabase/README.md#point-the-flutter-apps-at-the-new-project).
Never embed the `service_role` key in a client app.
