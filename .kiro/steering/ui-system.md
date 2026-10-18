# UI/UX System

## Design Tokens — always use these, never hard-code values

All tokens live in `packages/ui_kit/lib/tokens/`:

| Token class | File | What it covers |
|---|---|---|
| `AppColors` | `app_colors.dart` | Brand palette (gold, dark, surface, semantic) |
| `AppSpacing` | `app_spacing.dart` | 4-pt grid spacing constants |
| `AppRadius` | `app_radius.dart` | Corner radii (sm / md / lg / xl) |
| `AppShadows` | `app_shadows.dart` | Elevation shadow presets |
| `AppGradients` | `app_gradients.dart` | Brand gradient definitions |
| `AppMotion` | `app_motion.dart` | Duration + curve constants |
| `WindowClass` | `window_class.dart` | Breakpoint enum + helper |

**Never** hard-code a hex color, pixel padding, border radius, or animation duration in a widget.

---

## Responsive Layout

Breakpoints (based on available window width, not device type):

| Class | Width | Columns |
|---|---|---|
| `compact` | 0–599 px | 4 |
| `medium` | 600–839 px | 8 |
| `expanded` | 840–1199 px | 12 |
| `large` | 1200–1599 px | 12 |
| `extraLarge` | ≥ 1600 px | 12 |

- Derive layout from `LayoutBuilder` / `MediaQuery.sizeOf(context)` — **never** `Platform.isX`.
- `WindowClass` helper is in `packages/ui_kit/lib/tokens/window_class.dart`.
- Use `AdaptiveScaffold` from `packages/ui_kit` for top-level screen layout.

---

## Atomic Widgets (reuse before creating new)

Located in `packages/ui_kit/lib/widgets/`:

| Widget | Use case |
|---|---|
| `GoldButton` | Primary CTA (checkout, confirm, save) |
| `LuxuryCard` | Content card with brand surface style |
| `KpiCard` | Dashboard metric tile |
| `StatusBadge` | Order / delivery status chip |
| `StockBadge` | In-stock / low / out-of-stock indicator |
| `DzdPriceTag` | Formatted currency display |
| `MoneyField` | Currency input — converts DZD → centimes at boundary |
| `AdaptiveScaffold` | Shell scaffold with responsive nav rail/drawer |
| `ContentConstrainedBox` | Max-width content wrapper for large screens |
| `AppStates` | Loading / empty / error / offline / no-permission states |

---

## Screen States (mandatory for every screen)

Every screen **must** handle all of these:

1. **Loading** — skeleton or spinner while data fetches
2. **Empty** — zero-items state with an action prompt
3. **Error** — `AppStates.error(...)` with the failure message + retry
4. **Offline** — connectivity lost banner or full-screen notice
5. **No-permission** — role cannot access this screen
6. **Success** — the happy-path content

Use `AppStates` from `packages/ui_kit` to render the first five states consistently.

---

## Theme

The theme is defined in `packages/ui_kit/lib/theme/app_theme.dart`. It provides both light and dark `ThemeData`. Always consume `Theme.of(context)` — never construct a raw `TextStyle` or `ButtonStyle` in a screen widget.

---

## Localization

- Arabic is the **default** locale (RTL layout).
- French is the secondary locale (LTR layout).
- Every user-facing string must use `AppLocalizations.of(context)!.someKey`.
- ARB source files: `packages/l10n/lib/l10n/app_ar.arb` and `app_fr.arb`.
- Never hard-code Arabic or French text inline in widget files.
- RTL/LTR layout is handled automatically by Flutter when the locale switches — do not manually mirror layouts.

---

## POS-specific UX rules

- The barcode scanner `FocusNode` must auto-refocus after every cart action so the scanner is always active.
- Keyboard shortcuts (`F1–F12`, `Space`, `Enter`, `Esc`) are dispatched through `pos_keyboard_dispatcher.dart` — never bind them ad-hoc in individual widgets.
- Checkout dialogs must show the change amount (tendered − total) in real time as the cashier types.
- Cart line items must support quantity stepper and unit switcher (Piece / Pack / Carton / Box) inline without opening a dialog.
