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
/// NavigationRail (medium/expanded/large) layouts. The rail receives a premium
/// obsidian-with-gold-accents treatment in dark mode.
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final railBg = scaffold.railBackgroundColor ??
        (isDark ? const Color(0xFF1A1814) : const Color(0xFFFFFDF8));

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
            // Gold hairline divider replacing default VerticalDivider
            Container(
              width: 1,
              decoration: BoxDecoration(
                gradient: isDark
                    ? const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x00D4AF37),
                          Color(0x40D4AF37),
                          Color(0x20D4AF37),
                          Color(0x00D4AF37),
                        ],
                      )
                    : const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x00C59B27),
                          Color(0x28C59B27),
                          Color(0x14C59B27),
                          Color(0x00C59B27),
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
        indicatorColor: isDark
            ? const Color(0xFFD4AF37).withValues(alpha: 0.18)
            : const Color(0xFFC59B27).withValues(alpha: 0.14),
        selectedIconTheme: IconThemeData(
          color: isDark ? const Color(0xFFF3D278) : const Color(0xFF9A7319),
          size: 22,
        ),
        unselectedIconTheme: IconThemeData(
          color: isDark
              ? const Color(0xFF8A7A52)
              : const Color(0xFF9A8A60),
          size: 22,
        ),
        selectedLabelTextStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: isDark ? const Color(0xFFF3D278) : const Color(0xFF9A7319),
        ),
        unselectedLabelTextStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: isDark ? const Color(0xFF8A7A52) : const Color(0xFF9A8A60),
        ),
        destinations: destinations
            .asMap()
            .entries
            .map((e) => _buildDest(e.key, e.value))
            .toList(),
      ),
    );
  }

  NavigationRailDestination _buildDest(int idx, NavDestination d) {
    final isSelected = idx == selectedIndex;
    return NavigationRailDestination(
      padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      icon: d.icon,
      selectedIcon: Stack(
        alignment: Alignment.center,
        children: [
          if (isSelected)
            // Gold glow ring behind selected icon
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFD4AF37).withValues(alpha: 0.20),
                    const Color(0xFFD4AF37).withValues(alpha: 0.0),
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
