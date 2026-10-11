import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:domain/domain.dart';
import '../models/pos_models.dart';

class PosHeaderStatusBar extends StatelessWidget implements PreferredSizeWidget {
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
  final VoidCallback onFastSwitchCashier;
  final VoidCallback onLockScreen;
  final VoidCallback onRefreshStock;
  final VoidCallback onLogout;

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
    required this.onFastSwitchCashier,
    required this.onLockScreen,
    required this.onRefreshStock,
    required this.onLogout,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 42);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final colors = context.appColors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Main AppBar
        AppBar(
          titleSpacing: AppSpacing.md,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsetsDirectional.all(6),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: AppRadius.smAll,
                ),
                child: Icon(Icons.point_of_sale_rounded, color: colorScheme.onPrimaryContainer, size: 20),
              ),
              const SizedBox(width: AppSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('VIP Point of Sale (POS)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  Text(
                    cashierUser?.name ?? 'أمين الصندوق',
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 11, color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(width: AppSpacing.md),
              // Shift Status Badge
              if (activeShift != null)
                InkWell(
                  onTap: onOpenShiftAudit,
                  borderRadius: AppRadius.pillAll,
                  child: Container(
                    padding: const EdgeInsetsDirectional.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: colors.successContainer,
                      borderRadius: AppRadius.pillAll,
                      border: Border.all(color: colors.success),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_open, size: 12, color: colors.onSuccessContainer),
                        const SizedBox(width: 4),
                        Text(
                          'وردية مفتوحة Z-#${activeShift!.zReportNumber}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: colors.onSuccessContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsetsDirectional.symmetric(horizontal: 10, vertical: 6),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: onOpenShift,
                  icon: const Icon(Icons.lock_open, size: 14),
                  label: const Text('فتح وردية [F10]', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          actions: [
            // Held Carts Pill
            if (heldTicketsCount > 0)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: AppSpacing.sm),
                child: ActionChip(
                  avatar: Badge(
                    label: Text('$heldTicketsCount'),
                    child: const Icon(Icons.pause_circle_outline, size: 16),
                  ),
                  label: const Text('معلقة [F5]', style: TextStyle(fontSize: 11)),
                  onPressed: onOpenHeldTickets,
                ),
              ),
            IconButton(
              tooltip: 'تحديد الزبون والديون [F2]',
              icon: Icon(
                Icons.person_pin_circle_outlined,
                color: activeCustomer != null ? colorScheme.primary : null,
              ),
              onPressed: onOpenCustomerSearch,
            ),
            IconButton(
              tooltip: 'إعدادات واكتشاف الطابعات [F6]',
              icon: const Icon(Icons.print_outlined),
              onPressed: onOpenPrinterSettings,
            ),
            IconButton(
              tooltip: 'سجل المبيعات [F8]',
              icon: const Icon(Icons.history_edu_outlined),
              onPressed: onOpenSalesHistory,
            ),
            IconButton(
              tooltip: 'إرجاع واستبدال [F9]',
              icon: const Icon(Icons.assignment_return_outlined),
              onPressed: onOpenReturns,
            ),
            IconButton(
              tooltip: 'تقرير Z وإغلاق الوردية [F10]',
              icon: const Icon(Icons.receipt_long_outlined),
              onPressed: onOpenShiftAudit,
            ),
            IconButton(
              tooltip: 'قفل الشاشة [F11]',
              icon: const Icon(Icons.lock_outline),
              onPressed: onLockScreen,
            ),
            IconButton(
              tooltip: 'تبديل الكاشير (PIN)',
              icon: const Icon(Icons.swap_horiz_rounded),
              onPressed: onFastSwitchCashier,
            ),
            IconButton(
              tooltip: 'تحديث المخزون',
              icon: const Icon(Icons.refresh),
              onPressed: onRefreshStock,
            ),
            IconButton(
              tooltip: 'تسجيل الخروج',
              icon: const Icon(Icons.logout),
              onPressed: onLogout,
            ),
          ],
        ),
        // Secondary Customer Debt Sub-Bar
        if (activeCustomer != null)
          Container(
            height: 38,
            color: activeCustomer!.isCreditExceeded(0)
                ? colorScheme.errorContainer
                : colorScheme.primaryContainer.withValues(alpha: 0.8),
            padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              children: [
                Icon(
                  activeCustomer!.isCreditExceeded(0) ? Icons.warning_amber_rounded : Icons.account_circle,
                  size: 18,
                  color: activeCustomer!.isCreditExceeded(0)
                      ? colorScheme.onErrorContainer
                      : colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'الزبون: ${activeCustomer!.name} (${activeCustomer!.phone})',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: activeCustomer!.isCreditExceeded(0)
                        ? colorScheme.onErrorContainer
                        : colorScheme.onPrimaryContainer,
                  ),
                ),
                const Spacer(),
                Text(
                  'الدين الحالي: ',
                  style: TextStyle(
                    fontSize: 11,
                    color: activeCustomer!.isCreditExceeded(0)
                        ? colorScheme.onErrorContainer
                        : colorScheme.onPrimaryContainer,
                  ),
                ),
                DzdPriceTag(
                  centimes: activeCustomer!.currentDebtCentimes,
                  color: activeCustomer!.isCreditExceeded(0)
                      ? colorScheme.onErrorContainer
                      : colorScheme.onPrimaryContainer,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(width: AppSpacing.lg),
                Text(
                  'سقف الائتمان: ',
                  style: TextStyle(
                    fontSize: 11,
                    color: activeCustomer!.isCreditExceeded(0)
                        ? colorScheme.onErrorContainer
                        : colorScheme.onPrimaryContainer,
                  ),
                ),
                DzdPriceTag(
                  centimes: activeCustomer!.creditLimitCentimes,
                  color: activeCustomer!.isCreditExceeded(0)
                      ? colorScheme.onErrorContainer
                      : colorScheme.onPrimaryContainer,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(width: AppSpacing.md),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsetsDirectional.symmetric(horizontal: 10, vertical: 4),
                  ),
                  onPressed: onCollectDebt,
                  icon: const Icon(Icons.payments_outlined, size: 14),
                  label: const Text('سداد دين [F7]', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: AppSpacing.sm),
                InkWell(
                  onTap: onClearCustomer,
                  borderRadius: AppRadius.pillAll,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.all(4),
                    child: Icon(
                      Icons.close,
                      size: 16,
                      color: activeCustomer!.isCreditExceeded(0)
                          ? colorScheme.onErrorContainer
                          : colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            height: 38,
            color: colorScheme.surfaceContainer,
            padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              children: [
                Icon(Icons.person_outline, size: 16, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'زبون مباشر (بدون تسجيل دين)',
                  style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(width: AppSpacing.md),
                InkWell(
                  onTap: onOpenCustomerSearch,
                  child: Text(
                    '+ تعيين حساب زبون [F2]',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.primary),
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    _shortcutPill('F1', 'بحث'),
                    _shortcutPill('F3', 'يدوي'),
                    _shortcutPill('F4', 'تعليق'),
                    _shortcutPill('F12', 'دفع'),
                    _shortcutPill('Esc', 'تفريغ'),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _shortcutPill(String keyLabel, String actionLabel) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 6),
      child: Container(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.06),
          borderRadius: AppRadius.xsAll,
        ),
        child: Text(
          '$keyLabel: $actionLabel',
          style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
