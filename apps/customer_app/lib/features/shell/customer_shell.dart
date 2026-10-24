import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../providers/customer_providers.dart';
import '../catalog/catalog_screen.dart';
import '../common/widgets/app_update_dialog.dart';
import '../orders/my_orders_screen.dart';
import '../profile/profile_screen.dart';
import '../wallet/wallet_screen.dart';

/// Root shell for the customer app: four destinations + persistent state.
class CustomerShell extends ConsumerStatefulWidget {
  final VoidCallback? onExit;

  const CustomerShell({super.key, this.onExit});

  @override
  ConsumerState<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends ConsumerState<CustomerShell> {
  int _index = 0;
  bool _checkedUpdate = false;

  static const _destinations = [
    (
      icon: Icons.storefront_outlined,
      active: Icons.storefront_rounded,
      label: 'المتجر'
    ),
    (
      icon: Icons.receipt_long_outlined,
      active: Icons.receipt_long_rounded,
      label: 'طلبياتي'
    ),
    (
      icon: Icons.account_balance_wallet_outlined,
      active: Icons.account_balance_wallet_rounded,
      label: 'محفظتي'
    ),
    (
      icon: Icons.person_outline_rounded,
      active: Icons.person_rounded,
      label: 'حسابي'
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _checkedUpdate) return;
      _checkedUpdate = true;
      _checkForUpdate();
    });
  }

  Future<void> _checkForUpdate() async {
    try {
      final service = ref.read(customerAppUpdateServiceProvider);
      final res = await service.checkForUpdate();
      if (!mounted || !res.hasUpdate || res.newRelease == null) return;
      await AppUpdateDialog.show(
        context,
        release: res.newRelease!,
        currentVersion: res.currentVersion,
        currentBuild: res.currentBuild,
        updateService: service,
        force: res.isForceUpdate,
      );
    } catch (e) {
      debugPrint('[Shell] Update check failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Connectivity is app-wide state. React to the provider transition instead
    // of keeping a duplicated `_wasOnline` copy inside this widget.
    ref.listen<bool>(customerIsOnlineProvider, (previous, next) {
      if (next && previous == false) {
        ref.read(customerSyncCoordinatorProvider).refreshAll();
      }
    });

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final brand = context.roleTheme.roleBrandColor;
    final cartCount = ref.watch(
      customerCartProvider.select(
        (items) => items.fold<int>(0, (sum, item) => sum + item.quantity),
      ),
    );

    return Scaffold(
      backgroundColor: scheme.surface,
      body: IndexedStack(
        index: _index,
        children: [
          CatalogScreen(onExit: widget.onExit),
          const MyOrdersScreen(),
          const WalletScreen(),
          ProfileScreen(onNavigate: (i) => setState(() => _index = i)),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          border: Border(
            top: BorderSide(
              color: brand.withValues(alpha: isDark ? 0.26 : 0.18),
            ),
          ),
          boxShadow: isDark ? AppShadows.navDark : AppShadows.navLight,
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              children: List.generate(_destinations.length, (i) {
                final dest = _destinations[i];
                final selected = i == _index;
                return Expanded(
                  child: _ShellNavItem(
                    icon: selected ? dest.active : dest.icon,
                    label: dest.label,
                    selected: selected,
                    badge: i == 0 && cartCount > 0 ? cartCount : null,
                    onTap: () => setState(() => _index = i),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShellNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final int? badge;
  final VoidCallback onTap;

  const _ShellNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brand = context.roleTheme.roleBrandColor;

    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        splashColor: brand.withValues(alpha: 0.14),
        highlightColor: Colors.transparent,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: selected ? brand : null,
                borderRadius: AppRadius.pillAll,
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: brand.withValues(alpha: 0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    icon,
                    size: 21,
                    color: selected
                        ? scheme.onPrimary
                        : scheme.onSurfaceVariant.withValues(alpha: 0.72),
                  ),
                  if (badge != null)
                    PositionedDirectional(
                      top: -7,
                      end: -10,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 16),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: scheme.error,
                          borderRadius: AppRadius.pillAll,
                          border: Border.all(
                            color: scheme.surface,
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          badge! > 99 ? '99+' : '$badge',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: scheme.onError,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                color: selected ? brand : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
