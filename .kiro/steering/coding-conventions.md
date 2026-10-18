# Coding Conventions

## Dart / Flutter

### Naming
- Files: `snake_case.dart` — always.
- Classes: `PascalCase`. Entities end in `Entity` (e.g. `ProductEntity`). Repository interfaces start with `I` (e.g. `IProductRepository`). Repository implementations end in `Impl` (e.g. `ProductRepositoryImpl`).
- Riverpod providers: `camelCase` ending in `Provider` or `Notifier` (e.g. `cartProvider`, `checkoutNotifier`).
- Private members: `_camelCase`.

### File length
- A `build` method longer than ~120 lines **must** be split into smaller widgets.
- Dialogs and forms **must** be their own widget files, not inner methods of a screen.
- Each feature folder owns its own `widgets/`, `services/`, `models/` sub-folders.

### State management
- Use **Riverpod 2.x** exclusively. No `setState` outside pure local UI state (e.g., animation controllers, text focus).
- Providers live in `apps/<app>/lib/providers/` or co-located in the feature folder for feature-scoped state.
- Use `AsyncNotifier` for async operations. Expose `AsyncValue<T>` to the UI.
- Never call a repository directly from a widget — always go through a provider.

### Error handling
- Repository implementations **never** throw. Catch all exceptions; return `FailureResult(SomeFailure(...))`.
- At the provider layer, pattern-match `Result` with exhaustive `switch`.
- In the UI, show `AppStates.error(...)` widget on `FailureResult` — never a raw `print` or uncaught exception.

### Imports
- Use package-relative imports (`import 'package:core/core.dart'`), never relative cross-package imports.
- Within a single package, relative imports are fine.

### Formatting
- Run `dart format .` before committing.
- `analysis_options.yaml` is at the repo root — do not suppress lints without a comment explaining why.

---

## Localization

- **Every** user-facing string goes through the `l10n` package (`AppLocalizations.of(context)!.someKey`).
- Arabic is the default locale (RTL). French is the secondary locale (LTR).
- ARB files: `packages/l10n/lib/l10n/app_ar.arb` and `app_fr.arb`.
- Never hard-code Arabic or French text in widget files.

---

## Currency & Money

- All money is `int` centimes in Dart, `BIGINT` centimes in SQL.
- Display using `DzdFormatter.formatCentimes(int centimes)` from `packages/core`.
- Use the `DzdPriceTag` widget from `packages/ui_kit` for price display in the UI.
- Never do arithmetic on `double` money values. Never pass a `double` to an RPC.
- Input fields that accept money amounts must use `MoneyField` from `packages/ui_kit`, which converts at the boundary.

---

## UI / Widgets

- Use design tokens from `packages/ui_kit/lib/tokens/` — never hard-code colors, font sizes, radii, or padding values.
- Use `AppColors`, `AppSpacing`, `AppRadius`, `AppShadows`, `AppGradients` from `packages/ui_kit`.
- Reuse atomic widgets: `GoldButton`, `LuxuryCard`, `KpiCard`, `StatusBadge`, `StockBadge`, `DzdPriceTag`, `AdaptiveScaffold`.
- Every screen ships with all states: **loading**, **empty**, **error**, **offline**, **no-permission**, **success**. Use `AppStates` from `packages/ui_kit`.
- Responsive layout uses `WindowClass` from `packages/ui_kit/lib/tokens/window_class.dart`. Derive layout from `LayoutBuilder` — never from `Platform.isX`.

---

## Navigation

- GoRouter 14.x is the single routing system.
- Route guards enforce role-based access (`moderator`, `manager`, `cashier`, `driver`, `customer`).
- Staff roles authenticate via PIN (4-digit) after initial Supabase auth. Auth state lives in the `AuthRepository`.
- Never use `Navigator.push` for top-level navigation; use named GoRouter routes.

---

## Testing

- Unit tests live in `test/` at the repo root or within each package under its own `test/` folder.
- Test repository interactions by injecting a mock that returns `Success` / `FailureResult` values.
- Do not test widgets directly against Supabase — mock the repository layer.
