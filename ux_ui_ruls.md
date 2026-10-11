# Flutter SaaS UX/UI Design Rules (for AI Agents)

**Scope:** One Flutter codebase for a SaaS platform running on **Windows, Android, iOS**, and on **TV, laptop/desktop, tablet, phone** form factors.
**Audience:** AI coding agents generating or modifying UI code.
**Keywords:** MUST / MUST NOT = non-negotiable. SHOULD = default unless there is a written reason. MAY = optional.

---

## 0. How the Agent Must Work

1. **Read before writing.** Inspect the existing theme, tokens, router, and shared widgets. Reuse them. Never introduce a parallel style system.
2. **Design the layout contract first**, then code: which breakpoint classes the screen supports, what changes at each, what the primary action is.
3. **No hard-coded visual values** in screens (colors, font sizes, paddings, radii, durations). Use design tokens (section 3).
4. **No hard-coded user-facing strings.** Use localization (section 12).
5. **Every screen ships with all states:** loading, empty, error, partial, success, offline, no-permission (section 9).
6. **Before finishing, run the Definition of Done (section 20).** If an item cannot be met, say so explicitly in the output.
7. **Prefer small widgets.** A `build` method over ~120 lines MUST be split. Dialogs and forms MUST be their own widgets, not 300-line methods inside a screen class.

---

## 1. Core UX Principles

1. **Task first.** Each screen has ONE primary job and ONE primary action. Everything else is secondary or tertiary in visual weight.
2. **Consistency over novelty.** Same action = same icon, label, position, and behavior everywhere.
3. **Progressive disclosure.** Show common options; tuck advanced ones behind "More", expanders, or detail screens.
4. **Forgiveness.** Destructive actions are reversible (undo snackbar) or confirmed. Never lose user input silently.
5. **Feedback within 100 ms** (pressed state), **within 1 s** (progress indicator), **always** (success/failure result).
6. **Respect the platform.** Same brand, native feel (scrolling physics, back gestures, dialogs, keyboard shortcuts, window chrome).
7. **Speed is a feature.** Perceived performance (skeletons, optimistic updates) matters as much as real performance.
8. **Density is a user choice.** Offer compact / comfortable density on desktop/tablet data screens.

---

## 2. Device Classes & Responsive System

### 2.1 Window-size classes (use width of the **available window**, not the device type)

| Class | Width (logical px) | Typical devices | Columns | Margin | Gutter |
|---|---|---|---|---|---|
| `compact` | 0 – 599 | phones (portrait) | 4 | 16 | 16 |
| `medium` | 600 – 839 | tablets portrait, foldables, phone landscape | 8 | 24 | 24 |
| `expanded` | 840 – 1199 | tablets landscape, small windows | 12 | 24 | 24 |
| `large` | 1200 – 1599 | laptops, desktop windows | 12 | 32 | 24 |
| `extraLarge` | ≥ 1600 | big monitors, **TV** | 12 | 48 | 32 |

```dart
enum WindowClass { compact, medium, expanded, large, extraLarge }

WindowClass windowClassOf(double width) {
  if (width < 600) return WindowClass.compact;
  if (width < 840) return WindowClass.medium;
  if (width < 1200) return WindowClass.expanded;
  if (width < 1600) return WindowClass.large;
  return WindowClass.extraLarge;
}
```

### 2.2 Rules

- **MUST** derive layout from `LayoutBuilder` / `MediaQuery.sizeOf(context)` of the *available* space. **MUST NOT** use `Platform.isX` to decide layout (a Windows window can be phone-sized; an iPad can be split-screen).
- **MUST** react live to window resizing (Windows/desktop), split-screen, rotation, and foldable posture changes. No state may be lost on resize.
- **MUST** use `MediaQuery.sizeOf` / `MediaQuery.paddingOf` (not `MediaQuery.of`) to limit rebuilds.
- **MUST** cap content width on large screens: forms 480–640, reading text 680, dashboards ≤ 1440 centered (TV excepted, see 2.5). Never stretch a single text field across 1800 px.
- **MUST NOT** hard-code pixel widths for containers that hold content. Use `Flexible`, `Expanded`, `ConstrainedBox`, `FractionallySizedBox`, grid delegates with `maxCrossAxisExtent`.
- **MUST** test every screen at: 360×640, 390×844, 600×960, 820×1180, 1280×800, 1920×1080, 3840×2160 @ 2x (TV), plus text scale 1.0 and 2.0.
- **SHOULD** build screens as *one widget tree with adaptive slots*, not N separate screens per device.

### 2.3 Layout patterns per class

| Pattern | compact | medium | expanded | large / XL |
|---|---|---|---|---|
| Primary navigation | Bottom `NavigationBar` (3–5 items) | `NavigationRail` | `NavigationRail` (extended optional) | Permanent side drawer / extended rail |
| List + detail | Separate routes (push) | Separate or 2-pane | 2-pane (list 360–420 / detail flex) | 2-pane or 3-pane |
| Dialogs | Full-screen or bottom sheet | Centered dialog (max 560) | Centered dialog | Centered dialog / side panel |
| Forms | Single column | Single column, max 560 | 2 columns for long forms | 2 columns, sticky summary |
| Data tables | Cards / list tiles | Table with 3–5 key columns | Full table, column chooser | Full table, resizable columns |
| Search | Full-screen search | Inline | Inline + filters panel | Inline + persistent filters |
| Primary action | FAB or bottom bar | FAB / app-bar button | App-bar / toolbar button | Toolbar button + shortcut |

### 2.4 Adaptive scaffold (reference implementation)

```dart
class AdaptiveScaffold extends StatelessWidget {
  const AdaptiveScaffold({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.body,
  });

  final List<NavDestination> destinations; // icon, selectedIcon, label
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final w = windowClassOf(MediaQuery.sizeOf(context).width);
    switch (w) {
      case WindowClass.compact:
        return Scaffold(
          body: SafeArea(child: body),
          bottomNavigationBar: NavigationBar(
            selectedIndex: selectedIndex,
            onDestinationSelected: onSelected,
            destinations: [for (final d in destinations) d.toBarItem()],
          ),
        );
      case WindowClass.medium:
      case WindowClass.expanded:
        return Scaffold(
          body: Row(children: [
            NavigationRail(
              selectedIndex: selectedIndex,
              onDestinationSelected: onSelected,
              labelType: NavigationRailLabelType.all,
              destinations: [for (final d in destinations) d.toRailItem()],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ]),
        );
      case WindowClass.large:
      case WindowClass.extraLarge:
        return Scaffold(
          body: Row(children: [
            NavigationRail(
              extended: true,
              selectedIndex: selectedIndex,
              onDestinationSelected: onSelected,
              destinations: [for (final d in destinations) d.toRailItem()],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ]),
        );
    }
  }
}
```

### 2.5 TV-specific rules (Android TV / Google TV / large Windows displays)

- **Input is a D-pad/remote, not touch.** Every interactive element MUST be focusable and reachable with arrow keys + Enter/Select + Back.
- **Focus is the cursor.** Focus indicator MUST be unmistakable: ≥ 3 px outline or scale ≥ 1.05 + elevation, contrast ≥ 3:1 against its surroundings. Never rely on color alone.
- **Focus order MUST be predictable and spatial.** Use `FocusTraversalGroup` + `ReadingOrderTraversalPolicy` or `OrderedTraversalPolicy`. Never trap focus. Back always exits one level.
- **Initial focus MUST be set** on each screen (`autofocus: true` on the primary item). Restore the previous focus when returning.
- **Overscan-safe margins:** 48 px horizontal / 27 px vertical minimum (5% title-safe area).
- **Type for 3 m viewing:** body ≥ 20 sp, secondary ≥ 16 sp, titles ≥ 28 sp. Min target size 56×56 dp.
- **No hover-only, long-press-only, or gesture-only features.** No text-heavy forms; use pickers, voice, or companion-phone input for long text.
- **Layout:** landscape only, horizontal rails/carousels, left nav rail or top tabs. Avoid vertical scroll of long pages; prefer paged rows.
- **Dark theme default** (comfort in living rooms), reduced bright whites.
- **Keyboard/remote shortcuts:** map `Shortcuts`/`Actions` for Select, Back, Play/Pause where relevant.

```dart
FocusableActionDetector(
  autofocus: isFirst,
  onShowFocusHighlight: (v) => setState(() => _focused = v),
  actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => onTap())},
  child: AnimatedScale(
    scale: _focused ? 1.06 : 1.0,
    duration: AppMotion.fast,
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AppRadius.mdAll,
        border: Border.all(
          color: _focused ? scheme.primary : Colors.transparent, width: 3),
      ),
      child: child,
    ),
  ),
)
```

### 2.6 Desktop (Windows / laptop) rules

- **Pointer + keyboard first.** Hover states, tooltips (500 ms delay), right-click context menus, drag & drop, resizable panes, multi-select (Ctrl/Shift), column sorting/resizing.
- **Keyboard shortcuts MUST exist** for frequent actions (see section 13) and be shown in tooltips/menus.
- **Window management:** set a min window size (≈ 800×600), remember size/position, support maximize, snap, and multi-monitor DPI changes.
- **Scrollbars visible** and draggable on desktop (`Scrollbar(thumbVisibility: true)` for primary scroll areas).
- **Text is selectable** where users might copy it (`SelectableText` / `SelectionArea`): IDs, invoice numbers, emails, errors.
- **Menus:** use `MenuBar` / context menus for secondary actions; don't bury everything in 3-dot menus when space exists.
- **Dense by default allowed** (`VisualDensity.compact` on pointer devices), but targets MUST stay ≥ 32×32 px for mouse.

### 2.7 Mobile (Android / iOS) rules

- **Touch targets ≥ 48×48 dp** (Android) / **44×44 pt** (iOS) with ≥ 8 dp spacing between targets.
- **Thumb zone:** put primary actions in the bottom third; destructive and rare actions out of easy reach.
- **Respect safe areas** (notch, home indicator, gesture bar, punch-hole): `SafeArea` or `MediaQuery.paddingOf`.
- **Keyboard handling:** screens with inputs MUST scroll when the keyboard opens (`resizeToAvoidBottomInset`, `SingleChildScrollView`, `Scaffold` + `viewInsets`). Primary submit button stays reachable.
- **Back behavior:** Android system back and iOS swipe-back MUST work as users expect; use `PopScope` for unsaved-changes guards.
- **Pull-to-refresh** on remotely loaded lists. **Haptics** (light) on key confirmations only.
- **Orientation:** support portrait and landscape on phones unless a screen has a strong reason not to.

### 2.8 Tablet rules

- Never show a stretched phone UI. Use 2-pane master-detail at ≥ 840 px.
- Support split-screen, Slide Over, Stage Manager and foldable hinge (`DisplayFeatureSubScreen`).
- Support both touch and keyboard/mouse/stylus input; hover states appear when a pointer is present.

---

## 3. Design Tokens (single source of truth)

All visuals MUST come from tokens defined in one `ui_kit` / `core` package. The agent MUST NOT create colors, text styles, or sizes inline.

### 3.1 Color

- Use **Material 3** `ColorScheme.fromSeed` (or a brand-generated scheme) for **light and dark**. Both themes are mandatory.
- Access colors ONLY via `Theme.of(context).colorScheme` or a `ThemeExtension<AppColors>` for semantic extras:

```dart
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({required this.success, required this.onSuccess,
    required this.warning, required this.onWarning,
    required this.info, required this.onInfo});
  final Color success, onSuccess, warning, onWarning, info, onInfo;
  // copyWith + lerp required
}
```

- **MUST NOT** use `Colors.orange`, `Colors.redAccent`, `Colors.green`, raw hex, or `Colors.white` in screens. (Replace with `colorScheme.error`, `AppColors.warning`, `AppColors.success`, `colorScheme.onPrimary`...)
- **Semantic mapping:** primary = main action/brand; secondary = supporting; error = destructive/failed; success = completed/positive; warning = needs attention; info = neutral notices. Never use red for non-error decoration.
- **Contrast (WCAG 2.2 AA):** text ≥ 4.5:1 (large text ≥ 3:1), UI components & focus indicators ≥ 3:1. Verify in BOTH themes.
- **Never convey meaning by color alone.** Pair with icon, text, or shape (e.g., status chip = color + icon + label).
- Use `withValues(alpha: …)` (not deprecated `withOpacity`) for overlays; prefer scheme surface-container roles for elevation tint.

### 3.2 Typography

- One type family for Latin + one for Arabic/other scripts if needed (e.g., Inter/Roboto + Noto Sans Arabic / Cairo / IBM Plex Sans Arabic). Bundle fonts; do not rely on network font loading in production.
- Use the Material 3 type scale via `Theme.of(context).textTheme` only:

| Role | Use |
|---|---|
| `displayLarge/Medium` | Hero / marketing / TV headlines |
| `headlineLarge/Medium/Small` | Page titles, dashboard KPIs |
| `titleLarge/Medium/Small` | Card/section titles, dialogs, app bars |
| `bodyLarge/Medium/Small` | Content (default `bodyMedium`) |
| `labelLarge/Medium/Small` | Buttons, chips, captions, table headers |

- **MUST** support OS text scaling up to **200%** without clipping or overlap. Use `Flexible`/`Wrap`, no fixed-height text containers, no `maxLines: 1` on critical labels without tooltip/fallback.
- Minimum sizes: body 14 sp (mobile/desktop), 16 sp preferred for reading; TV ≥ 20 sp. Never below 11 sp.
- Line length for reading text: 45–80 characters.
- Numbers in tables/KPIs: use **tabular figures** (`FontFeature.tabularFigures()`), right-aligned (left-aligned in RTL context for numerals only if the locale convention requires; keep consistent per column).

### 3.3 Spacing, radius, elevation, size

- **4-pt base grid.** Spacing tokens: `xxs 2, xs 4, sm 8, md 12, lg 16, xl 24, xxl 32, xxxl 48, huge 64`.
- Radius tokens: `sm 4, md 8, lg 12, xl 16, pill 999`. Pick one radius language and keep it.
- Elevation: use Material 3 surface tones; shadows only for floating layers (menus, dialogs, drag).
- Icon sizes: 16 (dense), 20, 24 (default), 32, 48 (empty states). Stroke style consistent (one icon family: Material Symbols rounded OR outlined, not mixed).
- **MUST NOT** use magic numbers: `EdgeInsets.all(16)` → `AppSpacing.lg`.

### 3.4 Motion

| Token | Duration | Use |
|---|---|---|
| `instant` | 0–50 ms | state toggles with reduced motion |
| `fast` | 100–150 ms | hover, press, focus, ripple |
| `medium` | 200–300 ms | expand/collapse, fades, small transitions |
| `slow` | 350–500 ms | page/shared-element transitions |

- Curves: `Curves.easeOutCubic` (enter), `Curves.easeInCubic` (exit), `Curves.easeInOutCubic` (move). Avoid bounce in business apps.
- **MUST** honor reduced motion: `MediaQuery.disableAnimationsOf(context)` → skip/shorten animations.
- Animate to explain (cause/effect, spatial continuity), never for decoration. No infinite looping animations except progress indicators.

---

## 4. Theming Implementation

- Build `ThemeData` once in a theme factory: `useMaterial3: true`, `colorScheme`, `textTheme`, component themes (`FilledButtonTheme`, `InputDecorationTheme`, `CardTheme`, `DialogTheme`, `NavigationBarTheme`, `DataTableTheme`, `SnackBarTheme`, …). Screens inherit; they don't restyle.
- Theme mode: **System / Light / Dark** selectable and persisted. Switching MUST NOT restart the app.
- Platform adaptation via `ThemeData.platform` aware widgets: use `.adaptive` constructors (`Switch.adaptive`, `CircularProgressIndicator.adaptive`, `Slider.adaptive`) and `showAdaptiveDialog` where native feel matters. Page transitions: platform defaults (`PageTransitionsTheme`).
- Support **dynamic color** (Android 12+) as an option; brand color remains the fallback.
- Provide **high-contrast** variant when `MediaQuery.highContrastOf(context)` is true.
- Multi-tenant SaaS: tenant branding (logo, accent color) is injected through the **same token pipeline** (regenerate `ColorScheme` from tenant seed, validate contrast automatically; if it fails AA, adjust or fall back).

---

## 5. Navigation & Information Architecture

- **Max 5 top-level destinations** in bottom nav; more → overflow "More" screen or rail/drawer sections.
- Use a **declarative router** (`go_router`) with typed routes, deep links, and **URL-safe paths on every platform** (even if desktop/mobile don't show URLs). Each screen has a stable route.
- **Preserve state per tab** (`StatefulShellRoute` / `IndexedStack`): scroll position, filters, form drafts.
- **Breadcrumbs** on desktop for depth ≥ 3. **Back** is always visible on mobile sub-screens.
- **Role-based navigation:** destinations a role can't use MUST be hidden (not just disabled). Direct-URL access MUST be guarded by the router (redirect + friendly "no permission" screen).
- **Global search / command palette** (`Ctrl/Cmd+K`) on desktop for SaaS with > 8 modules.
- **Modal vs page:** use a dialog for quick, single-purpose, ≤ 4-field tasks; use a full page/side panel for anything longer, multi-step, or needing the keyboard for long.
- **Never** open a dialog from a dialog. Max one modal layer (confirmations excepted).

---

## 6. Components: Rules & Anatomy

### 6.1 Buttons

- Hierarchy: **FilledButton** (primary, max 1 per view) → **FilledButton.tonal** (secondary) → **OutlinedButton** → **TextButton** (tertiary). Destructive = error-colored variant with confirmation.
- Label = verb + object ("Save supplier", not "OK"). Sentence case. Icons optional, leading only.
- Loading state: disable, show inline progress, keep width stable. Prevent double submit.
- Min size per platform (see 2.6/2.7/2.5). Never rely on icon-only without tooltip + semantic label.

### 6.2 Text fields & forms

- Always visible label (floating or above). Placeholder is a hint, never the only label.
- Use proper `keyboardType`, `textInputAction`, `autofillHints`, `inputFormatters`, `textCapitalization`; move focus with `onFieldSubmitted`.
- **Validate on blur and on submit**, not on every keystroke (except password strength/format hints). Error text is specific and actionable ("Phone must start with +213"), shown under the field with an icon, not only red.
- Group related fields; one column on compact/medium; use 2 columns only when fields are short and logically paired.
- Mark required fields consistently (`*` + semantic label) OR mark optional ones; pick one convention app-wide.
- **Numeric/money inputs:** use a dedicated `MoneyField`/`QuantityField` that: parses decimals (never `int.tryParse` for money), stores **integer minor units** (e.g., centimes) in state, formats on blur, shows the currency, supports locale separators, and rejects negatives where invalid. Never store money as `double`.
- **Unsaved changes:** warn on leave (`PopScope`), auto-save drafts for long forms.
- Disable the submit button only when it's explained; otherwise allow press and show errors.
- Don't use `TextEditingController` inside a method-level dialog without disposing; own controllers in a `StatefulWidget` and `dispose()` them.

### 6.3 Dialogs, sheets, snackbars

- **Dialog:** title (what), body (why/impact), actions (right-aligned: cancel left of confirm; destructive confirm uses error style). Max width 560. Scrollable body.
- **Bottom sheet:** mobile contextual actions/filters; drag handle; `isScrollControlled` for forms.
- **Snackbar:** transient result of a user action, ≤ 2 lines, with **Undo** when reversible, 4–6 s. Errors needing action use a banner or inline message, not a vanishing snackbar.
- **Banner:** persistent, page-level (offline, subscription expired, maintenance).
- **Never** show raw exceptions (`$e`) to users. Map to friendly messages + a "Details/Copy" affordance + log the technical error.
- After `await`, check `if (!context.mounted) return;` (or `mounted` in State) before using context.

### 6.4 Lists & cards

- Use `ListView.builder` / `SliverList` (lazy) for anything > 20 items. Provide `itemExtent`/`prototypeItem` if uniform. Stable keys for reorderable/stateful items.
- A list tile: leading (avatar/icon), title (1 line), subtitle (≤ 2 lines), trailing (status/amount/action). Entire tile tappable with ≥ 48 dp height.
- Card = one entity or one logical group. Don't nest cards in cards. Don't use cards just for spacing.
- Swipe actions on mobile (with undo) must have a visible alternative (menu button) for accessibility and desktop.

### 6.5 Data tables (core of SaaS)

- Desktop/large: real table (`PaginatedDataTable`, `DataTable2`, or custom `TableView`) with sticky header, sortable columns, column visibility chooser, resizable columns, row selection (checkbox + Shift/Ctrl), bulk-action bar, density toggle, export (CSV/PDF) where relevant.
- Compact: transform each row into a card/list tile with 2–4 key fields; secondary data in a detail view.
- **Server-side** pagination/sorting/filtering for large datasets (cursor-based preferred). Show total count and active filters as removable chips.
- Align: text left (start), numbers right (end) with tabular figures, status centered/chip; units in header, not in every cell.
- Row actions: primary = row tap; secondary = overflow menu; destructive requires confirmation.
- Empty table state distinguishes **"no data yet"** from **"no results for filters"** (with a "Clear filters" action).

### 6.6 Search, filter, sort

- Search is debounced (300 ms), cancels stale requests, shows recent searches, highlights matches.
- Filters: chips for quick toggles; a filter panel/sheet for complex ones; always show an "Applied filters" summary and "Reset".
- Sort control shows current field + direction. Persist per-user view settings (saved views for power users).

### 6.7 Charts & dashboards

- Every chart: title, units, legend only when > 1 series, accessible color palette (colorblind-safe, ≥ 3:1 vs background), tooltips on hover/tap, a table/summary alternative for screen readers.
- KPI card: value (`headline`), label (`label`), delta with icon + color + text (e.g., "▲ 12% vs last week"), tap to drill down.
- Dashboard grid: responsive columns (1 / 2 / 3 / 4 by window class). Most important KPIs top-left (top-right in RTL).
- Dates: always show the time range and timezone context; provide presets (Today, 7d, 30d, custom).

### 6.8 Status, badges, chips

- Status chip = color + icon + text, from a single `StatusStyle` mapping (e.g., `draft`, `pending`, `posted`, `failed`, `cancelled`). Never invent per-screen colors.
- Stock/availability, payment, delivery, and sync statuses each have a defined enum → style mapping in `ui_kit`.

### 6.9 Empty, loading, error states (see section 9)

---

## 7. Layout Rules

- Build with **flex + constraints**, not absolute sizes. Prefer `Wrap` for chip/button groups so they reflow.
- Use `Spacer`/`Gap` widgets or `Column(spacing:)`/`Row(spacing:)` rather than ad-hoc `SizedBox` chains when possible; spacing values come from tokens.
- Avoid unbounded constraints bugs: no `ListView` directly in `Column` without `Expanded`; no `Row` of text without `Flexible`.
- **Scrolling:** one primary scroll axis per screen. Nested scrollables use `shrinkWrap` only for tiny lists; otherwise `CustomScrollView` + slivers.
- Sticky elements: app bar, table header, form action bar (bottom on mobile, bottom-right on desktop).
- **Primary action placement:** mobile = bottom (full-width or FAB); desktop/tablet = bottom-end of the form/dialog or top toolbar.
- **Grids:** `SliverGridDelegateWithMaxCrossAxisExtent` for card grids (e.g., 280–360 px per card).
- Whitespace separates groups (≥ 24 dp between sections, 8–12 dp within).
- Use `SafeArea`, `ScrollConfiguration`, and `Scaffold` consistently; no nested `Scaffold`s unless required (e.g., per-tab).

---

## 8. Platform Adaptation Matrix

| Concern | Android | iOS | Windows / Desktop | TV |
|---|---|---|---|---|
| Navigation | Bottom bar / rail, system back | Bottom bar, swipe-back | Rail/drawer, breadcrumbs | Rail / top tabs, D-pad |
| Dialogs | Material | `showAdaptiveDialog` | Material, keyboard-first | Large, focus-trapped |
| Scroll physics | Clamping | Bouncing | Clamping + visible scrollbar | Paged / focus-driven |
| Text input | Soft keyboard | Soft keyboard | Physical keyboard | Avoid; use pickers |
| Pickers | Material date/time | Cupertino style optional | Dropdown/calendar popup | Large list pickers |
| Context actions | Long-press, menus | Long-press, context menu | Right-click menu | Options button |
| Haptics | Yes | Yes | No | No |
| Window | Edge-to-edge | Safe areas | Resizable, min size | Fixed full-screen |
| Permissions | Runtime, explain first | Runtime, explain first | Rare | Rare |
| Files | SAF / share sheet | Share sheet / Files | Native file dialogs, drag&drop | N/A |

- **Never ship a platform plugin call without a fallback** for platforms that don't support it (check support, hide the feature gracefully).
- Use conditional imports/`kIsWeb`/`defaultTargetPlatform` only for **capability**, never for layout.

---

## 9. States: The Complete Set (every screen & async widget)

| State | Required behavior |
|---|---|
| **Loading (initial)** | Skeleton/shimmer matching final layout (not a lone spinner on big screens). Show after 150 ms to avoid flicker. |
| **Loading (refresh)** | Keep old data visible; subtle progress indicator. |
| **Empty (first use)** | Illustration/icon + 1-line explanation + primary CTA ("Add first product"). |
| **Empty (filtered)** | "No results" + clear-filters action. |
| **Error (recoverable)** | Plain-language message, **Retry** button, keep stale data if any. |
| **Error (fatal)** | Full-page error with support code and navigation out. |
| **Offline** | Persistent banner; read from cache; queue writes; show "pending sync" badges. |
| **Partial / degraded** | Show what loaded; mark failed sections independently. |
| **No permission** | Explain what is missing and who can grant it. |
| **Success** | Confirmation (snackbar/inline), next-step suggestion. |
| **Disabled** | Explain why (tooltip/helper text). |

- Use Riverpod `AsyncValue.when(...)` (or equivalent) with **all three branches implemented** and `skipLoadingOnRefresh` appropriately. `loading: () => CircularProgressIndicator()` alone is not acceptable for main content on large screens.
- Optimistic UI for low-risk actions; roll back and notify on failure.

---

## 10. Accessibility (WCAG 2.2 AA minimum)

1. **Semantics:** every interactive element has a label (`Semantics`, `tooltip`, `semanticLabel`). Decorative images: `excludeSemantics`. Group related info with `MergeSemantics`.
2. **Screen readers:** TalkBack (Android), VoiceOver (iOS), Narrator (Windows) — logical reading order, announce state changes (`SemanticsService.announce`) for async results and errors.
3. **Focus & keyboard:** full keyboard operability on desktop/TV; visible focus; logical tab order; no keyboard traps; `Esc` closes dialogs; `Enter` submits.
4. **Targets:** see platform minimums; spacing ≥ 8.
5. **Text scaling** to 200%, **bold text** and **reduce motion** OS settings honored.
6. **Color independence & contrast** (3.1). Test in grayscale and with color-blindness simulation.
7. **Forms:** programmatic label association, error identification, `autofillHints`, input purpose.
8. **Timeouts:** warn before session expiry with an option to extend.
9. **No flashing** > 3 times/second. Video/audio: captions/controls.
10. Use Flutter's `meetsGuideline(androidTapTargetGuideline)`, `iOSTapTargetGuideline`, `labeledTapTargetGuideline`, `textContrastGuideline` in widget tests.

---

## 11. RTL, Bidi & Multilingual (Arabic / French / English)

- **Use directional APIs only:** `EdgeInsetsDirectional`, `AlignmentDirectional`, `BorderRadiusDirectional`, `PositionedDirectional`, `TextAlign.start/end`. **MUST NOT** use `left/right` in layout code.
- Mirror: navigation order, back arrows (`Icons.arrow_back` auto-mirrors; for custom icons set `matchTextDirection: true`), progress direction, sliders, carousels, swipe gestures, and table column order.
- **Do NOT mirror:** logos, media controls (play/pause), numerals, charts' time axis (convention: time flows left→right unless product decision), phone numbers, code, and Latin brand names.
- **Numerals:** decide per locale (Western `0-9` vs Eastern Arabic `٠-٩`). Money/IDs in business documents keep Western digits unless specified; be consistent app-wide.
- **Mixed-direction text** (Arabic + Latin/digits): wrap with `Directionality`/Unicode isolates (`\u2068…\u2069`) when concatenating dynamic values (names, SKUs, phone numbers).
- **Never concatenate translated sentence fragments.** Use ICU messages with placeholders and plural/gender rules.
- **Bilingual labels** such as "المورد (Fournisseur)" MUST come from the localization files as separate keys (or a dedicated bilingual-label widget), never hard-coded inline in screens. Let the user choose primary language + optional secondary.
- Layout MUST tolerate **30–40% text expansion** (French/German) and taller Arabic glyphs (line height ≥ 1.4 for Arabic body).
- Language switch applies instantly, persists, and doesn't lose navigation state.
- Locale-aware formatting through `intl`: dates, times (24h/12h), number grouping, currency (DZD: symbol/position per locale), first day of week, calendar.
- Input: Arabic keyboards, `textDirection: TextDirection.ltr` for email/URL/code fields.

---

## 12. Localization & Content (UX Writing)

- All strings in ARB files (`flutter gen-l10n`); keys are semantic (`supplier_create_title`), not literal text.
- Voice: clear, short, active, human. No jargon, no blame ("Couldn't save the supplier. Check your connection and try again.").
- Buttons: verb + object. Titles: noun phrases. Errors: what happened + how to fix. Empty states: what this is + what to do.
- Consistent terminology glossary (one word per concept: "Supplier" not "Vendor/Provider" mixed). Maintain it in `docs/glossary.md`.
- Dates relative for recent ("2 h ago") with absolute on hover/long-press; always absolute in exports and audit logs.
- Currency always with unit/symbol; negative amounts clearly distinguished (sign + color + label).

---

## 13. Input Models & Shortcuts

**Pointer/keyboard (desktop):**

| Action | Shortcut (Win/Linux · macOS-like iPad keyboards) |
|---|---|
| Command palette / global search | `Ctrl+K` · `Cmd+K` |
| New item | `Ctrl+N` · `Cmd+N` |
| Save / submit | `Ctrl+S` or `Ctrl+Enter` · `Cmd+S` |
| Find in page | `Ctrl+F` · `Cmd+F` |
| Refresh data | `F5` / `Ctrl+R` |
| Close dialog/panel | `Esc` |
| Undo / Redo | `Ctrl+Z` / `Ctrl+Y` · `Cmd+Z` / `Cmd+Shift+Z` |
| Delete selected | `Delete` (with confirm) |
| Select all | `Ctrl+A` |

Implement with `Shortcuts` + `Actions` + `Intent`s (not raw `RawKeyboardListener`). Show shortcuts in tooltips and a "Keyboard shortcuts" help dialog (`?`).

**Barcode scanners / POS (wholesale, retail):** HID scanners act as keyboards → provide a focusable scan field that captures fast key bursts (+ Enter), beeps/vibrates on success, and shows a clear error on unknown codes. Camera scanning on mobile with torch toggle and manual fallback.

**Touch gestures:** tap, long-press (contextual), swipe (secondary), pinch/zoom for media only. Every gesture has a visible alternative.

**Voice/remote (TV):** see 2.5.

---

## 14. Performance Rules (UX-relevant)

- **60/120 fps target.** Avoid jank: no heavy work in `build`; move parsing/computation to `compute`/isolates.
- `const` constructors everywhere possible. Split widgets to narrow rebuilds. With Riverpod use `select`/`ref.watch(provider.select(...))` and `Consumer` at leaf level.
- Lazy lists (builders/slivers); paginate; `cacheExtent` tuned for fast scrolling lists.
- **Images:** correct size (`cacheWidth/Height`), caching (`cached_network_image`), placeholders, WebP/AVIF, never decode 4000 px images for a 48 px avatar.
- **Startup:** show first meaningful UI < 2 s on mid-range Android; defer non-critical init; use native splash that matches the first frame.
- **Memory:** dispose controllers, focus nodes, subscriptions, timers, animation controllers.
- Avoid `Opacity`/`ClipRRect`/`saveLayer`-heavy trees in scrolling items; use `RepaintBoundary` thoughtfully; profile with DevTools (Performance, CPU, Memory) in **profile mode** on real devices.
- Debounce/throttle inputs, cancel stale requests, cache with TTL, deduplicate in-flight requests.
- Large datasets on desktop: virtualize tables; never render > ~200 rows at once.

---

## 15. Offline, Sync & Reliability UX (SaaS-critical)

- Show **connection status** and **sync status** globally (small indicator) with details on tap.
- Local-first for POS/field flows: write to local DB (Drift/Isar/SQLite), sync via outbox queue with retries, backoff, and **idempotency keys**.
- Each queued item displays status: pending → syncing → synced / failed (with retry & conflict resolution).
- Conflict policy is explicit per entity (last-write-wins, server-wins, merge, or ask the user) and communicated in plain language.
- Long operations: progress, cancel (if safe), background completion notification.
- Never block the whole UI for a background sync.

---

## 16. Security & Privacy UX

- **Auth:** biometric/PIN unlock on mobile, passkey/SSO support, session timeout with warning, secure storage (`flutter_secure_storage`) for tokens. Never store secrets/API keys in the client bundle.
- **Role-based UI:** hide unauthorized features; server enforces everything (UI is not security).
- **Sensitive data:** mask by default (balances, IDs, card numbers) with reveal toggle; blur app in task switcher for sensitive screens; disable screenshots where required.
- **Destructive/financial actions:** confirmation with summary of consequences; for high-risk, require re-authentication or typed confirmation.
- **Audit-friendly UX:** show "created by / updated by / when" on key records; show activity history.
- **Permissions (camera, storage, notifications, location):** ask in context, explain why first, handle denial and "don't ask again" with a path to settings.
- **Privacy:** consent screens, data export/delete flows where applicable. Don't log PII in analytics or crash reports.

---

## 17. Multi-Tenant SaaS Specifics

- Tenant/org switcher in the nav (name + logo), switching resets caches and navigation safely.
- Branding tokens per tenant (section 4). Never let tenant content break layout (long names → ellipsis + tooltip; missing logo → monogram).
- Plan/limit awareness: show usage, upgrade prompts at the point of need (non-blocking), clear locked-feature affordances.
- Onboarding: checklist, sample data option, contextual tooltips (dismissible, never repeated after dismissal).
- Notifications center (in-app) + preferences per channel; unread badge; deep-link from notification to the exact record.
- Admin areas visually distinct (header label), with audit trail and bulk-safe operations.
- Support: "Help" entry, copyable diagnostic info (app version, tenant id, request id).

---

## 18. Code Architecture Rules for UI

- Folder pattern: `features/<feature>/{presentation,application,domain,data}`. UI in `presentation` only; no business logic or repository calls inside widgets' event handlers beyond dispatching to a controller/notifier.
- **State:** Riverpod (or the project's chosen solution) with immutable state classes; UI is a function of state. No `setState` for shared/async/business state; `setState` only for ephemeral UI state (hover, focus, tab).
- **Shared widgets** live in `ui_kit` with a gallery/Widgetbook entry, documented props, and golden tests.
- Dialog/form widgets are standalone classes with their own controllers & `dispose`.
- Navigation via router service, not `Navigator.push` scattered in widgets.
- Use `sealed` classes/enums for view states and status mappings (exhaustive `switch`).
- Money = integer minor units + `Money` value object; formatting only in a formatter.
- Errors modeled as typed failures → mapped to user messages in one place (`ErrorPresenter`).
- No `print`; use a logger. No business strings in code (section 12).
- Lint: `flutter_lints` strict / `very_good_analysis`; zero analyzer warnings on merge. Treat `use_build_context_synchronously` as an error.

---

## 19. Testing & QA Matrix

**Automated**
- **Widget tests** for every shared component and every screen state (loading/empty/error/data).
- **Golden tests** for key components across: light/dark × LTR/RTL × text scale 1.0/2.0 × compact/medium/large.
- **Accessibility guideline tests** (`meetsGuideline`) on key screens.
- **Integration tests** for core journeys on Android emulator, iOS simulator, and Windows desktop.
- **Responsive tests:** pump at the 7 reference sizes (2.2) and assert no `RenderFlex overflow` exceptions.
- **Performance tests:** frame timing for long lists/tables.

**Manual (per release)**
- Real devices: low-end Android, current iPhone, iPad, Windows laptop with touch + mouse + keyboard, Android TV with remote.
- Screen readers on each OS. 200% text scale. Dark mode. Offline mode. RTL (Arabic). Slow network (3G throttling).
- Orientation change, multi-window, window resize, DPI change, keyboard-only navigation, D-pad-only navigation.

---

## 20. Definition of Done (checklist the agent MUST verify)

**Layout & Responsiveness**
- [ ] Works at compact, medium, expanded, large, and extra-large widths with no overflow.
- [ ] Navigation pattern matches the window class (bar / rail / extended rail).
- [ ] Content width is capped on large screens; no stretched forms.
- [ ] Orientation change & window resize preserve state.
- [ ] TV: all elements focusable, visible focus, overscan-safe margins (if TV is targeted).

**Visual System**
- [ ] Zero hard-coded colors, font sizes, spacings, radii, durations.
- [ ] Light and dark themes verified; contrast AA.
- [ ] Only theme text styles; supports 200% text scale.
- [ ] Icons from one family; consistent semantics.

**UX**
- [ ] One clear primary action; button hierarchy respected.
- [ ] Loading, empty, error, offline, no-permission, success states implemented.
- [ ] Destructive actions confirmed or undoable.
- [ ] Forms: labels, validation timing, keyboard types, autofill, focus order, unsaved-changes guard.
- [ ] Money & quantities use dedicated inputs with integer minor units.
- [ ] No raw exception text in UI; friendly, localized messages.

**Platform**
- [ ] Touch targets ≥ platform minimum; hover/focus/pressed states present.
- [ ] Keyboard shortcuts + context menus on desktop; D-pad on TV; safe areas + keyboard insets on mobile.
- [ ] Back navigation correct on every platform.
- [ ] Platform-specific plugins guarded with fallbacks.

**Accessibility & i18n**
- [ ] Screen reader labels, reading order, and announcements verified.
- [ ] Reduced motion honored.
- [ ] All strings localized; no string concatenation; plural/gender via ICU.
- [ ] RTL mirrored correctly with directional APIs; mixed-direction text isolated.

**Code Quality**
- [ ] Widgets split, `const` used, controllers disposed, `context.mounted` checked after awaits.
- [ ] Business logic outside widgets; state immutable; router used for navigation.
- [ ] Analyzer clean; tests + goldens added/updated.
- [ ] No jank in profile mode on a mid-range device.

---

## 21. Anti-Patterns (the agent MUST NOT produce)

1. `Platform.isAndroid ? phoneLayout : desktopLayout` for responsive layout.
2. `Colors.red`, `Colors.orange`, hex literals, or `EdgeInsets.all(16)` in screen code.
3. 300-line `showDialog` bodies inside screen state classes; controllers created per call and never disposed.
4. `int.tryParse` / `double` for money; silently falling back to 0 on parse failure.
5. Fake fallback IDs/users (`'2222-...'`) used when auth is missing. Fail loudly and route to sign-in.
6. Showing `'$e'` exceptions in snackbars.
7. Spinner-only loading for entire pages; missing empty/error states.
8. Using `left/right`/`EdgeInsets.only(left: …)` in layouts that must support RTL.
9. Hard-coded bilingual strings in widgets.
10. Dialog stacked on dialog; wizard crammed into a dialog.
11. Icon-only buttons without tooltips/semantics; hover-only or long-press-only features.
12. Fixed-height text containers; `maxLines: 1` on critical info; clipped Arabic text.
13. Nested scroll views with `shrinkWrap: true` on large lists.
14. `setState` for server data; business logic in `onPressed`.
15. Disabling the submit button with no explanation.
16. Infinite or decorative animations; ignoring reduced-motion.
17. Relying on color alone for status or errors.
18. Using `MediaQuery.of(context)` everywhere (rebuild storms) instead of `sizeOf`/`paddingOf`.
19. Shipping features that only work with a mouse (or only touch).
20. Copy-pasting a screen per device instead of adapting one widget tree.

---

## 22. Quick Reference Cheat Sheet

```
Breakpoints:  <600 compact | 600–839 medium | 840–1199 expanded | 1200–1599 large | ≥1600 XL/TV
Nav:          bottom bar → rail → extended rail/drawer
Targets:      48dp Android · 44pt iOS · 32px mouse min · 56dp TV
Type:         body 14–16sp · TV ≥20sp · support 200% scale
Spacing:      4-pt grid (4 8 12 16 24 32 48 64)
Contrast:     text 4.5:1 · large text/UI 3:1 · focus 3:1
Motion:       100–150 fast · 200–300 medium · honor reduced-motion
Max widths:   form 480–640 · reading 680 · dashboard ≤1440 (TV exempt)
RTL:          *Directional APIs only · mirror nav/icons · isolate mixed text
Money:        integer minor units · dedicated field · locale formatter
States:       loading · empty · filtered-empty · error · offline · no-permission · success
```

*End of rules. When a rule conflicts with an explicit product requirement, follow the requirement, note the deviation in code comments (`// DESIGN-DEVIATION: reason`), and keep accessibility and data-safety rules intact.*