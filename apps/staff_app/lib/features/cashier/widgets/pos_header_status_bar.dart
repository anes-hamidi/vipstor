import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:domain/domain.dart';
import 'package:data/data.dart';
import '../models/pos_models.dart';
import 'pos_theme.dart';

/// Premium POS header with:
/// - Role-tinted chrome bar with brand logo accent
/// - Brand shift badge with glow
/// - Customer sub-bar with debt indicators
/// - Keyboard shortcut pills
class PosHeaderStatusBar extends StatelessWidget
    implements PreferredSizeWidget {
  final UserEntity? cashierUser;
  final PosShiftSession? activeShift;
  final CustomerProfileEntity? activeCustomer;
  final int heldTicketsCount;
  final VoidCallback onOpenShift;
  final VoidCallback onOpenCustomerSearch;
  final VoidCallback onClearCustomer;
  final VoidCallback onCollectDebt;
  final VoidCallback onOpenHeldTickets;
  final VoidCallback onOpenSalesHistory;
  final VoidCallback onOpenReturns;
  final VoidCallback onOpenShiftAudit;
  final VoidCallback onOpenPrinterSettings;
  final VoidCallback? onPaySupplier; // Pays supplier dues in cash
  final VoidCallback? onSettleDriver; // Settle driver delivery wallet cash
  final VoidCallback onFastSwitchCashier;
  final VoidCallback onLockScreen;
  final VoidCallback onRefreshStock;
  final VoidCallback onLogout;
  final VoidCallback? onEditProfile; // NEW — opens StaffProfileEditSheet
  final VoidCallback? onCheckUpdates; // Checks for OTA updates

  const PosHeaderStatusBar({
    super.key,
    required this.cashierUser,
    required this.activeShift,
    required this.activeCustomer,
    required this.heldTicketsCount,
    required this.onOpenShift,
    required this.onOpenCustomerSearch,
    required this.onClearCustomer,
    required this.onCollectDebt,
    required this.onOpenHeldTickets,
    required this.onOpenSalesHistory,
    required this.onOpenReturns,
    required this.onOpenShiftAudit,
    required this.onOpenPrinterSettings,
    this.onPaySupplier,
    this.onSettleDriver,
    required this.onFastSwitchCashier,
    required this.onLockScreen,
    required this.onRefreshStock,
    required this.onLogout,
    this.onEditProfile,
    this.onCheckUpdates,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 42);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final isDark = theme.brightness == Brightness.dark;
    final wc = context.windowClass;
    final isPhone = wc == WindowClass.compact;
    // Keyboard hints only make sense with a physical keyboard (desktop sizes).
    final showShortcuts = wc != WindowClass.compact && wc != WindowClass.medium;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Main AppBar ──────────────────────────────────────────────────
        Container(
          height: kToolbarHeight,
          decoration: BoxDecoration(
            color: context.posChrome,
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.shadow
                    .withValues(alpha: isDark ? 0.38 : 0.06),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border(
              bottom: BorderSide(color: context.posHairline, width: 1),
            ),
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: AppSpacing.md),
            child: Row(
              children: [
                // Logo + title
                const _VipPosLogo(),
                const SizedBox(width: AppSpacing.sm),
                // Role avatar chip — taps to edit profile
                GestureDetector(
                  onTap: onEditProfile,
                  child: Container(
                    padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: AppSpacing.sm, vertical: 4),
                    decoration: BoxDecoration(
                      color: context.roleTheme.badgeBackground,
                      borderRadius: AppRadius.pillAll,
                      border: Border.all(
                        color: context.posBrand.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: context.posBrand,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              ((cashierUser?.name ?? '?').isEmpty
                                      ? '?'
                                      : (cashierUser?.name ?? '?')[0])
                                  .toUpperCase(),
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: context.posOnBrand),
                            ),
                          ),
                        ),
                        if (!isPhone) const SizedBox(width: 6),
                        if (!isPhone)
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 100),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  cashierUser?.name ?? 'أمين الصندوق',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.1),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  'أمين صندوق',
                                  style: TextStyle(
                                      fontSize: 9,
                                      color: context.roleTheme.badgeText
                                          .withValues(alpha: 0.8)),
                                ),
                              ],
                            ),
                          ),
                        if (onEditProfile != null && !isPhone) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.edit_rounded,
                              size: 11,
                              color: context.roleTheme.badgeText
                                  .withValues(alpha: 0.7)),
                        ],
                      ],
                    ),
                  ),
                ),
                SizedBox(width: isPhone ? AppSpacing.sm : AppSpacing.md),

                // Shift badge
                _ShiftBadge(
                  activeShift: activeShift,
                  onOpenShift: onOpenShift,
                  onOpenShiftAudit: onOpenShiftAudit,
                ),

                const Spacer(),

                // ── Offline indicator ────────────────────────────────────────
                const _OfflineBadge(),

                // Held tickets chip
                if (heldTicketsCount > 0)
                  Padding(
                    padding:
                        const EdgeInsetsDirectional.only(end: AppSpacing.sm),
                    child: _HeldChip(
                        count: heldTicketsCount, onTap: onOpenHeldTickets),
                  ),

                // Action icons
                _HeaderIcon(
                    icon: Icons.person_pin_circle_outlined,
                    tooltip: 'الزبون [F2]',
                    onTap: onOpenCustomerSearch,
                    active: activeCustomer != null,
                    colors: colors),
                if (isPhone)
                  PopupMenuButton<VoidCallback>(
                    tooltip: 'المزيد',
                    icon: const Icon(Icons.more_vert_rounded, size: 20),
                    padding: EdgeInsets.zero,
                    onSelected: (cb) => cb(),
                    itemBuilder: (_) => [
                      if (onPaySupplier != null)
                        _menuItem(Icons.payments_outlined,
                            'سداد مستحقات المورد', onPaySupplier!),
                      if (onSettleDriver != null)
                        _menuItem(Icons.local_shipping_outlined,
                            'تسوية عهدة سائق توصيل', onSettleDriver!),
                      _menuItem(Icons.print_outlined, 'الطابعة',
                          onOpenPrinterSettings),
                      _menuItem(Icons.history_edu_outlined, 'سجل المبيعات',
                          onOpenSalesHistory),
                      _menuItem(Icons.assignment_return_outlined, 'الإرجاع',
                          onOpenReturns),
                      _menuItem(Icons.receipt_long_outlined, 'تقرير Z',
                          onOpenShiftAudit),
                      _menuItem(Icons.lock_outline, 'قفل', onLockScreen),
                      _menuItem(Icons.swap_horiz_rounded, 'تبديل الكاشير',
                          onFastSwitchCashier),
                      _menuItem(Icons.refresh, 'تحديث المخزون', onRefreshStock),
                      if (onCheckUpdates != null)
                        _menuItem(Icons.system_update_rounded,
                            'التحقق من التحديثات', onCheckUpdates!),
                      _menuItem(Icons.logout, 'خروج', onLogout),
                    ],
                  )
                else ...[
                  if (onPaySupplier != null)
                    _HeaderIcon(
                      icon: Icons.payments_outlined,
                      tooltip: 'سداد مستحقات مورد (نقدًا)',
                      onTap: onPaySupplier!,
                      colors: colors,
                    ),
                  if (onSettleDriver != null)
                    _HeaderIcon(
                      icon: Icons.local_shipping_outlined,
                      tooltip: 'تسوية عهدة سائق التوصيل (نقدًا)',
                      onTap: onSettleDriver!,
                      colors: colors,
                    ),
                  _HeaderIcon(
                      icon: Icons.print_outlined,
                      tooltip: 'الطابعة [F6]',
                      onTap: onOpenPrinterSettings,
                      colors: colors),
                  _HeaderIcon(
                      icon: Icons.history_edu_outlined,
                      tooltip: 'سجل المبيعات [F8]',
                      onTap: onOpenSalesHistory,
                      colors: colors),
                  _HeaderIcon(
                      icon: Icons.assignment_return_outlined,
                      tooltip: 'الإرجاع [F9]',
                      onTap: onOpenReturns,
                      colors: colors),
                  _HeaderIcon(
                      icon: Icons.receipt_long_outlined,
                      tooltip: 'تقرير Z [F10]',
                      onTap: onOpenShiftAudit,
                      colors: colors),
                  _HeaderIcon(
                      icon: Icons.lock_outline,
                      tooltip: 'قفل [F11]',
                      onTap: onLockScreen,
                      colors: colors),
                  _HeaderIcon(
                      icon: Icons.swap_horiz_rounded,
                      tooltip: 'تبديل الكاشير',
                      onTap: onFastSwitchCashier,
                      colors: colors),
                  _HeaderIcon(
                      icon: Icons.refresh,
                      tooltip: 'تحديث المخزون',
                      onTap: onRefreshStock,
                      colors: colors),
                  if (onCheckUpdates != null)
                    _HeaderIcon(
                        icon: Icons.system_update_rounded,
                        tooltip: 'التحقق من التحديثات',
                        onTap: onCheckUpdates!,
                        colors: colors),
                  _HeaderIcon(
                      icon: Icons.logout,
                      tooltip: 'خروج',
                      onTap: onLogout,
                      colors: colors),
                ],
              ],
            ),
          ),
        ),

        // ── Customer Sub-Bar ─────────────────────────────────────────────
        if (activeCustomer != null)
          _CustomerSubBar(
            customer: activeCustomer!,
            onCollectDebt: onCollectDebt,
            onClearCustomer: onClearCustomer,
            colors: colors,
          )
        else
          _NoCustomerBar(
            onOpenCustomerSearch: onOpenCustomerSearch,
            showShortcuts: showShortcuts,
          ),
      ],
    );
  }
}

PopupMenuItem<VoidCallback> _menuItem(
    IconData icon, String label, VoidCallback cb) {
  return PopupMenuItem<VoidCallback>(
    value: cb,
    height: 44,
    child: Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: AppSpacing.sm),
        Text(label, style: const TextStyle(fontSize: 13)),
      ],
    ),
  );
}

// ── Logo ────────────────────────────────────────────────────────────────────

class _VipPosLogo extends StatelessWidget {
  const _VipPosLogo();

  @override
  Widget build(BuildContext context) {
    final brand = context.posBrand;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            Color.lerp(brand, Colors.white, 0.30)!,
            brand,
            Color.lerp(brand, Colors.black, 0.16)!,
          ],
        ),
        borderRadius: AppRadius.smAll,
        boxShadow: [
          BoxShadow(
            color: brand.withValues(alpha: 0.32),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(Icons.point_of_sale_rounded,
            color: context.posOnBrand, size: 18),
      ),
    );
  }
}

// ── Shift Badge ─────────────────────────────────────────────────────────────

class _ShiftBadge extends StatelessWidget {
  final PosShiftSession? activeShift;
  final VoidCallback onOpenShift;
  final VoidCallback onOpenShiftAudit;

  const _ShiftBadge({
    required this.activeShift,
    required this.onOpenShift,
    required this.onOpenShiftAudit,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    if (activeShift != null) {
      return InkWell(
        onTap: onOpenShiftAudit,
        borderRadius: AppRadius.pillAll,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.successContainer,
            borderRadius: AppRadius.pillAll,
            border: Border.all(
                color: colors.success.withValues(alpha: 0.40), width: 1),
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: AppSpacing.md, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_open_rounded,
                    size: 12, color: colors.onSuccessContainer),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'وردية Z-#${activeShift!.zReportNumber}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: colors.onSuccessContainer,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return GoldButton.icon(
      icon: Icons.lock_open_rounded,
      label: 'فتح وردية [F10]',
      onPressed: onOpenShift,
      compact: true,
    );
  }
}

// ── Held tickets chip ────────────────────────────────────────────────────────

class _HeldChip extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _HeldChip({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final role = context.roleTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.pillAll,
      child: Container(
        padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.md, vertical: 4),
        decoration: BoxDecoration(
          color: role.badgeBackground,
          borderRadius: AppRadius.pillAll,
          border: Border.all(
            color: context.posBrand.withValues(alpha: 0.40),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.pause_circle_outline, size: 13, color: role.badgeText),
            const SizedBox(width: 4),
            Text(
              '$count معلقة [F5]',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: role.badgeText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Header icon button ───────────────────────────────────────────────────────

class _HeaderIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;
  final AppColors colors;

  const _HeaderIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.colors,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        icon,
        size: 20,
        color: active ? context.posBrand : null,
      ),
      tooltip: tooltip,
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
    );
  }
}

// ── Customer sub-bar ─────────────────────────────────────────────────────────

class _CustomerSubBar extends StatelessWidget {
  final CustomerProfileEntity customer;
  final VoidCallback onCollectDebt;
  final VoidCallback onClearCustomer;
  final AppColors colors;

  const _CustomerSubBar({
    required this.customer,
    required this.onCollectDebt,
    required this.onClearCustomer,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final isOverLimit = customer.isCreditExceeded(0);
    final cs = Theme.of(context).colorScheme;

    final bg = isOverLimit ? cs.errorContainer : colors.successContainer;
    final fg = isOverLimit ? cs.onErrorContainer : colors.onSuccessContainer;

    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          bottom: BorderSide(
            color: (isOverLimit ? cs.error : colors.success)
                .withValues(alpha: 0.30),
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: [
          Icon(
            isOverLimit ? Icons.warning_amber_rounded : Icons.account_circle,
            size: 16,
            color: fg,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '${customer.name}  •  ${customer.phone}',
            style:
                TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: fg),
          ),
          const Spacer(),
          Text('الدين: ',
              style:
                  TextStyle(fontSize: 11, color: fg.withValues(alpha: 0.80))),
          DzdPriceTag(
            centimes: customer.currentDebtCentimes,
            color: fg,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(width: AppSpacing.lg),
          Text('الحد: ',
              style:
                  TextStyle(fontSize: 11, color: fg.withValues(alpha: 0.80))),
          DzdPriceTag(
            centimes: customer.creditLimitCentimes,
            color: fg,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(width: AppSpacing.md),
          GoldButton.icon(
            icon: Icons.payments_outlined,
            label: 'سداد [F7]',
            onPressed: onCollectDebt,
            compact: true,
          ),
          const SizedBox(width: AppSpacing.sm),
          InkWell(
            onTap: onClearCustomer,
            borderRadius: AppRadius.pillAll,
            child: Padding(
              padding: const EdgeInsetsDirectional.all(4),
              child: Icon(Icons.close, size: 15, color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

// ── No-customer bar ──────────────────────────────────────────────────────────

class _NoCustomerBar extends StatelessWidget {
  final VoidCallback onOpenCustomerSearch;
  final bool showShortcuts;

  const _NoCustomerBar({
    required this.onOpenCustomerSearch,
    required this.showShortcuts,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      height: 42,
      color: cs.surfaceContainerLow,
      padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: [
          Icon(Icons.person_outline, size: 15, color: cs.onSurfaceVariant),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              'زبون مباشر (بيع نقدي)',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          InkWell(
            onTap: onOpenCustomerSearch,
            child: Text(
              showShortcuts ? '+ تعيين زبون [F2]' : '+ تعيين زبون',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: context.posBrand,
              ),
            ),
          ),
          if (showShortcuts) ...[
            const Spacer(),
            // Shortcut pills (desktop only)
            ...[
              ('F1', 'بحث'),
              ('F3', 'يدوي'),
              ('F4', 'تعليق'),
              ('F12', 'دفع'),
              ('Esc', 'تفريغ'),
            ].map((e) => _ShortcutPill(keyLabel: e.$1, action: e.$2)),
          ],
        ],
      ),
    );
  }
}

class _ShortcutPill extends StatelessWidget {
  final String keyLabel;
  final String action;

  const _ShortcutPill({required this.keyLabel, required this.action});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 6),
      child: Container(
        padding:
            const EdgeInsetsDirectional.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: AppRadius.xsAll,
          border: Border.all(
            color: context.posBrand.withValues(alpha: 0.20),
            width: 1,
          ),
        ),
        child: Text(
          '$keyLabel: $action',
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w600,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

// ─── Offline indicator ────────────────────────────────────────────────────────
/// Appears in the POS header only when the device has no internet connection.
/// Shows a pulsing amber "غير متصل" chip, and hides when online.
class _OfflineBadge extends StatefulWidget {
  const _OfflineBadge();

  @override
  State<_OfflineBadge> createState() => _OfflineBadgeState();
}

class _OfflineBadgeState extends State<_OfflineBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  bool _online = true;

  @override
  void initState() {
    super.initState();
    _online = ConnectivityService.instance.isOnline;
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    ConnectivityService.instance.onStatusChange.listen((online) {
      if (mounted) setState(() => _online = online);
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_online) return const SizedBox.shrink();

    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsetsDirectional.only(end: AppSpacing.sm),
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.55, end: 1.0).animate(_pulse),
        child: Container(
          padding: const EdgeInsetsDirectional.symmetric(
              horizontal: AppSpacing.sm, vertical: 3),
          decoration: BoxDecoration(
            color: colors.warningContainer,
            borderRadius: AppRadius.pillAll,
            border: Border.all(
              color: colors.warning.withValues(alpha: 0.6),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off_rounded,
                  size: 12, color: colors.onWarningContainer),
              const SizedBox(width: 4),
              Text(
                'غير متصل',
                style: TextStyle(
                  fontSize: 11,
                  color: colors.onWarningContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
