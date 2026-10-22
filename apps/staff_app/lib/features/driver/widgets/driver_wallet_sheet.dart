import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/core.dart';
import 'package:domain/domain.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../../providers/staff_providers.dart';
import 'driver_order_utils.dart';

/// Driver cash-handover and settlement statement.
///
/// Responsive by design: a draggable-style bottom sheet on phones and a
/// centered, bounded dialog on tablets/desktops. The content prioritises the
/// driver's current cash liability first, then unresolved orders, then history.
class DriverWalletSheet extends ConsumerWidget {
  static const Color _heroGold = Color(0xFFF3D278);
  static const Color _heroCream = Color(0xFFFBF8F0);
  static const Color _heroMuted = Color(0xB8FBF8F0);

  final String driverId;
  final String driverName;
  final bool asDialog;

  const DriverWalletSheet({
    super.key,
    required this.driverId,
    required this.driverName,
    this.asDialog = false,
  });

  static Future<void> show(
    BuildContext context, {
    required String driverId,
    required String driverName,
  }) {
    final isCompact = MediaQuery.sizeOf(context).width < 720;

    if (isCompact) {
      return showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (_) => DriverWalletSheet(
          driverId: driverId,
          driverName: driverName,
        ),
      );
    }

    return showDialog<void>(
      context: context,
      builder: (_) => DriverWalletSheet(
        driverId: driverId,
        driverName: driverName,
        asDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = context.appColors;

    final walletAsync = ref.watch(driverWalletBalanceProvider);
    final ordersAsync = ref.watch(driverUnsettledOrdersProvider(driverId));
    final settlementsAsync = ref.watch(recentSettlementsProvider(driverId));

    final screenHeight = MediaQuery.sizeOf(context).height;
    final contentHeight = asDialog
        ? (screenHeight * 0.82).clamp(480.0, 820.0).toDouble()
        : screenHeight * 0.90;
    final unsettledCount = ordersAsync.valueOrNull?.length ?? 0;

    final content = Container(
      height: contentHeight,
      constraints: BoxConstraints(
        maxWidth: asDialog ? 760 : double.infinity,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: asDialog
            ? AppRadius.xxlAll
            : const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: colors.gold.withValues(alpha: asDialog ? 0.25 : 0.35),
        ),
        boxShadow: AppShadows.dialogLuxury,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!asDialog)
            Center(
              child: Container(
                width: 42,
                height: 4,
                margin: const EdgeInsetsDirectional.only(top: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: colors.gold.withValues(alpha: 0.35),
                  borderRadius: AppRadius.pillAll,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsetsDirectional.all(8),
                  decoration: const BoxDecoration(
                    gradient: AppGradients.gold,
                    borderRadius: AppRadius.mdAll,
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet_rounded,
                    color: Color(0xFF1A1400),
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'عهدة الكاش والتسويات',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'السائق: $driverName',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'تحديث',
                  onPressed: () {
                    ref.invalidate(driverWalletBalanceProvider);
                    ref.invalidate(driverUnsettledOrdersProvider(driverId));
                    ref.invalidate(recentSettlementsProvider(driverId));
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                ),
                IconButton(
                  tooltip: 'إغلاق',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: _buildBalanceCard(
              context,
              theme,
              colors,
              walletAsync,
              unsettledCount,
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsetsDirectional.symmetric(
                horizontal: AppSpacing.lg,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: AppRadius.lgAll,
                border: Border.all(
                  color:
                      theme.colorScheme.outlineVariant.withValues(alpha: 0.8),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    TabBar(
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicator: const BoxDecoration(
                        gradient: AppGradients.gold,
                        borderRadius: AppRadius.mdAll,
                      ),
                      labelColor: const Color(0xFF1A1400),
                      unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                      labelStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                      dividerColor: Colors.transparent,
                      padding: const EdgeInsetsDirectional.all(4),
                      tabs: [
                        Tab(text: 'غير مسواة ($unsettledCount)'),
                        const Tab(text: 'سجل التسويات'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _UnsettledOrdersTab(
                            ordersAsync: ordersAsync,
                            onRetry: () => ref.invalidate(
                              driverUnsettledOrdersProvider(driverId),
                            ),
                          ),
                          _SettlementHistoryTab(
                            settlementsAsync: settlementsAsync,
                            onRetry: () => ref.invalidate(
                              recentSettlementsProvider(driverId),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );

    if (!asDialog) return content;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(AppSpacing.xl),
      child: content,
    );
  }

  Widget _buildBalanceCard(
    BuildContext context,
    ThemeData theme,
    AppColors colors,
    AsyncValue<int> walletAsync,
    int unsettledCount,
  ) {
    final balance = walletAsync.valueOrNull ?? 0;
    final hasCash = balance > 0;

    return Container(
      padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: AppGradients.obsidianHero,
        borderRadius: AppRadius.xlAll,
        border: Border.all(color: _heroGold.withValues(alpha: 0.32)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'المبلغ المطلوب تسليمه',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: _heroMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: (hasCash
                                ? const Color(0xFFFBBF24)
                                : const Color(0xFF34D399))
                            .withValues(alpha: 0.14),
                        borderRadius: AppRadius.pillAll,
                        border: Border.all(
                          color: (hasCash
                                  ? const Color(0xFFFBBF24)
                                  : const Color(0xFF34D399))
                              .withValues(alpha: 0.28),
                        ),
                      ),
                      child: Text(
                        hasCash ? 'بانتظار التسوية' : 'العهدة مصفّاة',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: hasCash
                              ? const Color(0xFFFBBF24)
                              : const Color(0xFF6EE7B7),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  walletAsync.when(
                    data: (value) => DzdFormatter.formatCentimes(
                      value,
                      showDecimals: false,
                    ),
                    loading: () => '...',
                    error: (_, __) => '—',
                  ),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: _heroGold,
                    fontWeight: FontWeight.w900,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'سلّم هذا المبلغ لأمين الصندوق أو المشرف عند إغلاق الوردية.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: _heroMuted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Container(
            padding: const EdgeInsetsDirectional.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: AppRadius.mdAll,
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: Column(
              children: [
                Text(
                  '$unsettledCount',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: _heroCream,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'طلب',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: _heroMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tabs
// ─────────────────────────────────────────────────────────────────────────────

class _UnsettledOrdersTab extends StatelessWidget {
  final AsyncValue<List<OrderEntity>> ordersAsync;
  final VoidCallback onRetry;

  const _UnsettledOrdersTab({
    required this.ordersAsync,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return ordersAsync.when(
      loading: () => AppStates.loading(
        message: 'جارٍ تحميل الطلبات غير المسواة...',
      ),
      error: (_, __) => AppStates.error(
        'تعذر جلب الطلبات غير المسواة.',
        onRetry: onRetry,
      ),
      data: (orders) {
        if (orders.isEmpty) {
          return const _EmptyTab(
            icon: Icons.check_circle_outline_rounded,
            title: 'كل الطلبات مسواة',
            description:
                'لا توجد مبالغ كاش معلقة في عهدتك من الطلبات المسلّمة.',
          );
        }

        final total = orders.fold<int>(
          0,
          (sum, order) => sum + order.paidAmountCentimes,
        );

        return Column(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              child: Row(
                children: [
                  Text(
                    '${orders.length} طلب مسلّم',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const Spacer(),
                  Text(
                    'إجمالي الكاش: ',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  Text(
                    '${DzdFormatter.formatCentimes(total, showDecimals: false)} دج',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: context.appColors.gold,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.md,
                  AppSpacing.xs,
                  AppSpacing.md,
                  AppSpacing.lg,
                ),
                itemCount: orders.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, index) =>
                    _UnsettledOrderTile(order: orders[index]),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SettlementHistoryTab extends StatelessWidget {
  final AsyncValue<List<SettlementEntity>> settlementsAsync;
  final VoidCallback onRetry;

  const _SettlementHistoryTab({
    required this.settlementsAsync,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return settlementsAsync.when(
      loading: () => AppStates.loading(
        message: 'جارٍ تحميل سجل التسويات...',
      ),
      error: (_, __) => AppStates.error(
        'تعذر جلب سجل التسويات.',
        onRetry: onRetry,
      ),
      data: (settlements) {
        if (settlements.isEmpty) {
          return const _EmptyTab(
            icon: Icons.history_edu_outlined,
            title: 'لا يوجد سجل تسويات بعد',
            description:
                'بعد تسليم العهدة لأمين الصندوق ستظهر تفاصيل كل تسوية هنا.',
          );
        }

        return ListView.separated(
          padding: const EdgeInsetsDirectional.all(AppSpacing.md),
          itemCount: settlements.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (context, index) =>
              _SettlementHistoryTile(settlement: settlements[index]),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tiles
// ─────────────────────────────────────────────────────────────────────────────

class _UnsettledOrderTile extends StatelessWidget {
  final OrderEntity order;

  const _UnsettledOrderTile({required this.order});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;

    return Container(
      padding: const EdgeInsetsDirectional.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: AppRadius.lgAll,
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.75),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: colors.successContainer.withValues(alpha: 0.45),
              borderRadius: AppRadius.mdAll,
            ),
            child: Icon(
              Icons.receipt_long_rounded,
              size: 18,
              color: colors.success,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'طلب #${orderShortNumber(order)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${deliveryCustomerName(order)} • ${formatDateShort(order.createdAt)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${DzdFormatter.formatCentimes(order.paidAmountCentimes, showDecimals: false)} دج',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.success,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                'كاش محصل',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettlementHistoryTile extends StatelessWidget {
  final SettlementEntity settlement;

  const _SettlementHistoryTile({required this.settlement});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final isExact = settlement.differenceCentimes == 0;
    final isShortage = settlement.differenceCentimes < 0;
    final isFlagged = settlement.status != 'settled';

    return Container(
      padding: const EdgeInsetsDirectional.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: AppRadius.lgAll,
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.75),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isExact ? colors.success : colors.warning,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  formatDateTimeShort(settlement.createdAt),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: (isFlagged ? colors.warning : colors.success)
                      .withValues(alpha: 0.10),
                  borderRadius: AppRadius.pillAll,
                ),
                child: Text(
                  isFlagged ? 'قيد المراجعة' : (isExact ? 'مطابقة' : 'بفرق'),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isFlagged ? colors.warning : colors.success,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  'المستلم: ${settlement.cashierName}',
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${DzdFormatter.formatCentimes(settlement.countedAmountCentimes, showDecimals: false)} دج',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.gold,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          if (!isExact) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              isShortage
                  ? 'عجز: ${DzdFormatter.formatCentimes(settlement.differenceCentimes.abs(), showDecimals: false)} دج'
                  : 'فائض: ${DzdFormatter.formatCentimes(settlement.differenceCentimes, showDecimals: false)} دج',
              style: theme.textTheme.labelSmall?.copyWith(
                color: isShortage ? colors.error : colors.info,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (settlement.notes != null &&
              settlement.notes!.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              settlement.notes!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyTab extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _EmptyTab({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;

    return Center(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: colors.goldMuted,
                shape: BoxShape.circle,
                border: Border.all(
                  color: colors.gold.withValues(alpha: 0.25),
                ),
              ),
              child: Icon(icon, size: 28, color: colors.gold),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Text(
                description,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
