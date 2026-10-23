import 'package:core/core.dart';
import 'package:flutter/material.dart';
import '../tokens/app_radius.dart';
import '../tokens/app_shadows.dart';
import '../tokens/app_spacing.dart';
import '../tokens/window_class.dart';

/// Navigation destination model for [AdaptiveScaffold].
class NavDestination {
  final Widget icon;
  final Widget? selectedIcon;
  final String label;
  final String? tooltip;

  const NavDestination({
    required this.icon,
    this.selectedIcon,
    required this.label,
    this.tooltip,
  });

  NavigationDestination toBarItem() => NavigationDestination(
        icon: icon,
        selectedIcon: selectedIcon,
        label: label,
        tooltip: tooltip,
      );

  NavigationRailDestination toRailItem() => NavigationRailDestination(
        icon: icon,
        selectedIcon: selectedIcon,
        label: Text(label),
      );
}

/// Adaptive scaffold that switches between BottomNavigationBar (compact) and
/// NavigationRail (medium/expanded/large) layouts. The rail receives the active
/// workspace brand treatment derived from the role theme.
class AdaptiveScaffold extends StatelessWidget {
  final List<NavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? trailingRail;
  final Widget? leadingRail;
  final Widget? floatingActionButton;
  final Color? railBackgroundColor;

  const AdaptiveScaffold({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.body,
    this.appBar,
    this.trailingRail,
    this.leadingRail,
    this.floatingActionButton,
    this.railBackgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final windowClass = context.windowClass;

    return switch (windowClass) {
      WindowClass.compact => _CompactLayout(scaffold: this),
      WindowClass.medium  => _RailLayout(scaffold: this, extended: false),
      WindowClass.expanded=> _RailLayout(scaffold: this, extended: false),
      WindowClass.large   => _RailLayout(scaffold: this, extended: true),
      WindowClass.extraLarge => _RailLayout(scaffold: this, extended: true),
    };
  }
}

// ── Compact layout ─────────────────────────────────────────────────────────

class _CompactLayout extends StatelessWidget {
  final AdaptiveScaffold scaffold;
  const _CompactLayout({required this.scaffold});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: scaffold.appBar,
      body: SafeArea(child: scaffold.body),
      floatingActionButton: scaffold.floatingActionButton,
      bottomNavigationBar: scaffold.destinations.isNotEmpty
          ? NavigationBar(
              selectedIndex: scaffold.selectedIndex,
              onDestinationSelected: scaffold.onSelected,
              destinations:
                  scaffold.destinations.map((d) => d.toBarItem()).toList(),
            )
          : null,
    );
  }
}

// ── Rail layout ────────────────────────────────────────────────────────────

class _RailLayout extends StatelessWidget {
  final AdaptiveScaffold scaffold;
  final bool extended;
  const _RailLayout({required this.scaffold, required this.extended});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final brand = context.roleTheme.roleBrandColor;
    final railBg = scaffold.railBackgroundColor ?? scheme.surfaceContainerLowest;

    return Scaffold(
      appBar: scaffold.appBar,
      floatingActionButton: scaffold.floatingActionButton,
      body: Row(
        children: [
          if (scaffold.destinations.isNotEmpty)
            _PremiumRail(
              destinations: scaffold.destinations,
              selectedIndex: scaffold.selectedIndex,
              onSelected: scaffold.onSelected,
              leading: scaffold.leadingRail,
              trailing: scaffold.trailingRail,
              extended: extended,
              backgroundColor: railBg,
              isDark: isDark,
            ),
          if (scaffold.destinations.isNotEmpty)
            // Brand hairline divider
            Container(
              width: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    brand.withValues(alpha: 0.0),
                    brand.withValues(alpha: 0.28),
                    brand.withValues(alpha: 0.12),
                    brand.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          Expanded(child: scaffold.body),
        ],
      ),
    );
  }
}

// ── Premium NavigationRail ─────────────────────────────────────────────────

class _PremiumRail extends StatelessWidget {
  final List<NavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Widget? leading;
  final Widget? trailing;
  final bool extended;
  final Color backgroundColor;
  final bool isDark;

  const _PremiumRail({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.leading,
    required this.trailing,
    required this.extended,
    required this.backgroundColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brand = context.roleTheme.roleBrandColor;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        boxShadow: isDark ? AppShadows.navDark : AppShadows.navLight,
      ),
      child: NavigationRail(
        backgroundColor: Colors.transparent,
        extended: extended,
        minWidth: 72,
        minExtendedWidth: 220,
        selectedIndex: selectedIndex,
        onDestinationSelected: onSelected,
        leading: leading != null
            ? Padding(
                padding: const EdgeInsetsDirectional.only(
                    top: AppSpacing.lg, bottom: AppSpacing.md),
                child: leading,
              )
            : const SizedBox(height: AppSpacing.lg),
        trailing: trailing != null
            ? Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(
                        bottom: AppSpacing.xl),
                    child: trailing,
                  ),
                ),
              )
            : null,
        indicatorShape: const RoundedRectangleBorder(
          borderRadius: AppRadius.lgAll,
        ),
        indicatorColor: brand.withValues(alpha: isDark ? 0.20 : 0.14),
        selectedIconTheme: IconThemeData(
          color: scheme.primary,
          size: 22,
        ),
        unselectedIconTheme: IconThemeData(
          color: scheme.onSurfaceVariant,
          size: 22,
        ),
        selectedLabelTextStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: scheme.primary,
        ),
        unselectedLabelTextStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: scheme.onSurfaceVariant,
        ),
        destinations: destinations
            .asMap()
            .entries
            .map((e) => _buildDest(e.key, e.value, brand))
            .toList(),
      ),
    );
  }

  NavigationRailDestination _buildDest(int idx, NavDestination d, Color brand) {
    final isSelected = idx == selectedIndex;
    return NavigationRailDestination(
      padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      icon: d.icon,
      selectedIcon: Stack(
        alignment: Alignment.center,
        children: [
          if (isSelected)
            // Brand glow ring behind the selected icon.
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    brand.withValues(alpha: 0.20),
                    brand.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          d.selectedIcon ?? d.icon,
        ],
      ),
      label: Text(d.label),
    );
  }
}
