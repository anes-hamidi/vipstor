import 'package:flutter/material.dart';
import '../tokens/window_class.dart';

/// Navigation item model for AdaptiveScaffold.
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

  NavigationDestination toBarItem() {
    return NavigationDestination(
      icon: icon,
      selectedIcon: selectedIcon,
      label: label,
      tooltip: tooltip,
    );
  }

  NavigationRailDestination toRailItem() {
    return NavigationRailDestination(
      icon: icon,
      selectedIcon: selectedIcon,
      label: Text(label),
    );
  }
}

/// Adaptive scaffold adapting navigation from BottomBar (Compact) to NavigationRail (Medium/Expanded) and Extended Rail (Large/ExtraLarge).
class AdaptiveScaffold extends StatelessWidget {
  final List<NavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? trailingRail;
  final Widget? leadingRail;
  final Widget? floatingActionButton;

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
  });

  @override
  Widget build(BuildContext context) {
    final windowClass = context.windowClass;

    switch (windowClass) {
      case WindowClass.compact:
        return Scaffold(
          appBar: appBar,
          body: SafeArea(child: body),
          floatingActionButton: floatingActionButton,
          bottomNavigationBar: destinations.isNotEmpty
              ? NavigationBar(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: onSelected,
                  destinations: destinations.map((d) => d.toBarItem()).toList(),
                )
              : null,
        );

      case WindowClass.medium:
      case WindowClass.expanded:
        return Scaffold(
          appBar: appBar,
          floatingActionButton: floatingActionButton,
          body: Row(
            children: [
              if (destinations.isNotEmpty)
                NavigationRail(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: onSelected,
                  labelType: NavigationRailLabelType.all,
                  leading: leadingRail,
                  trailing: trailingRail,
                  destinations: destinations.map((d) => d.toRailItem()).toList(),
                ),
              if (destinations.isNotEmpty) const VerticalDivider(width: 1),
              Expanded(child: body),
            ],
          ),
        );

      case WindowClass.large:
      case WindowClass.extraLarge:
        return Scaffold(
          appBar: appBar,
          floatingActionButton: floatingActionButton,
          body: Row(
            children: [
              if (destinations.isNotEmpty)
                NavigationRail(
                  extended: true,
                  minExtendedWidth: 220,
                  selectedIndex: selectedIndex,
                  onDestinationSelected: onSelected,
                  leading: leadingRail,
                  trailing: trailingRail,
                  destinations: destinations.map((d) => d.toRailItem()).toList(),
                ),
              if (destinations.isNotEmpty) const VerticalDivider(width: 1),
              Expanded(child: body),
            ],
          ),
        );
    }
  }
}
