import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:core/core.dart';
import '../../../providers/staff_providers.dart';

class DriverWalletSheet extends ConsumerWidget {
  final String driverId;
  final String driverName;

  const DriverWalletSheet({
    super.key,
    required this.driverId,
    required this.driverName,
  });

  static Future<void> show(BuildContext context, {required String driverId, required String driverName}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DriverWalletSheet(driverId: driverId, driverName: driverName),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final walletAsync = ref.watch(driverWalletBalanceProvider);
    final ordersAsync = ref.watch(driverUnsettledOrdersProvider(driverId));
    final settlementsAsync = ref.watch(recentSettlementsProvider(driverId));

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: colors.obsidianSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: colors.gold, width: 2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.gold.withValues(alpha: 0.4),
                borderRadius: AppRadius.pillAll,
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    gradient: AppGradients.goldFoil,
                    borderRadius: AppRadius.mdAll,
                  ),
                  child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.black, size: 24),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'كشف عهدة الكاش والتسويات',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colors.onObsidian,
                        ),
                      ),
                      Text(
                        'السائق: $driverName',
                        style: theme.textTheme.bodySmall?.copyWith(color: colors.gold),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Balance card
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: walletAsync.when(
              data: (balance) {
                final hasCash = balance > 0;
                return LuxuryCard(
                  goldAccent: true,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'المبلغ المطلوب تسليمه (الكاش في عهدتك):',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onObsidian.withValues(alpha: 0.65),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: hasCash
                                  ? colors.gold.withValues(alpha: 0.2)
                                  : colors.success.withValues(alpha: 0.2),
                              borderRadius: AppRadius.pillAll,
                            ),
                            child: Text(
                              hasCash ? 'بانتظار التسوية' : 'تمت التسوية',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: hasCash ? colors.gold : colors.success,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        DzdFormatter.formatCentimes(balance),
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colors.gold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hasCash
                            ? 'يتم تسليم هذا المبلغ لأمين الصندوق في المتجر أو للمشرف بنهاية الوردية.'
                            : 'لا توجد مبالغ نقدية معلقة في عهدتك حالياً.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: colors.onObsidian.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ),
                );
              },
              loading: () => AppStates.loading(),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ),

          // Tabs for Unsettled Orders vs Settlement History
          Expanded(
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  TabBar(
                    indicatorColor: colors.gold,
                    labelColor: colors.gold,
                    unselectedLabelColor: colors.onObsidian.withValues(alpha: 0.65),
                    tabs: const [
                      Tab(
                        icon: Icon(Icons.receipt_long_rounded, size: 18),
                        text: 'الطلبات المحصلة غير المسواة',
                      ),
                      Tab(
                        icon: Icon(Icons.history_rounded, size: 18),
                        text: 'سجل التسويات السابقة',
                      ),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        // 1. Unsettled Orders Tab
                        ordersAsync.when(
                          data: (orders) {
                            if (orders.isEmpty) {
                              return Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(AppSpacing.lg),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.check_circle_outline, size: 48, color: colors.success),
                                      const SizedBox(height: 8),
                                      const Text('جميع الطلبات المسلمة تمت تسويتها'),
                                    ],
                                  ),
                                ),
                              );
                            }
                            return ListView.separated(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              itemCount: orders.length,
                              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                              itemBuilder: (ctx, i) {
                                final o = orders[i];
                                return LuxuryCard(
                                  padding: const EdgeInsets.all(AppSpacing.sm),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: colors.obsidianCard,
                                          borderRadius: AppRadius.smAll,
                                        ),
                                        child: const Icon(Icons.local_shipping_rounded, size: 20),
                                      ),
                                      const SizedBox(width: AppSpacing.sm),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'طلب #${o.orderNumber ?? o.id.substring(0, 6)}',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                            ),
                                            Text(
                                              o.customerName ?? 'زبون',
                                              style: TextStyle(color: colors.onObsidian.withValues(alpha: 0.65), fontSize: 11),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            DzdFormatter.formatCentimes(o.paidAmountCentimes),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.greenAccent,
                                              fontSize: 13,
                                            ),
                                          ),
                                          Text(
                                            'كاش محصل',
                                            style: TextStyle(color: colors.onObsidian.withValues(alpha: 0.65), fontSize: 10),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                          loading: () => AppStates.loading(),
                          error: (e, _) => AppStates.error('تعذر جلب الطلبات: $e'),
                        ),

                        // 2. Recent Settlements Tab
                        settlementsAsync.when(
                          data: (settlements) {
                            if (settlements.isEmpty) {
                              return Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(AppSpacing.lg),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.history_edu_outlined, size: 48, color: colors.onObsidian.withValues(alpha: 0.65)),
                                      const SizedBox(height: 8),
                                      const Text('لا يوجد سجل تسويات سابقة بعد'),
                                    ],
                                  ),
                                ),
                              );
                            }
                            return ListView.separated(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              itemCount: settlements.length,
                              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                              itemBuilder: (ctx, i) {
                                final s = settlements[i];
                                final isExact = s.status == 'settled' && s.differenceCentimes == 0;
                                return LuxuryCard(
                                  padding: const EdgeInsets.all(AppSpacing.sm),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'تسوية #${s.id.substring(0, 8)}',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                          ),
                                          Text(
                                            s.createdAt.toString().substring(0, 16),
                                            style: TextStyle(color: colors.onObsidian.withValues(alpha: 0.65), fontSize: 10),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Text(
                                            'المستلم: ${s.cashierName}',
                                            style: const TextStyle(fontSize: 11),
                                          ),
                                          const Spacer(),
                                          Text(
                                            DzdFormatter.formatCentimes(s.countedAmountCentimes),
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: colors.gold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (!isExact) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          s.differenceCentimes < 0
                                              ? 'عجز: ${DzdFormatter.formatCentimes(s.differenceCentimes.abs())}'
                                              : 'فائض: ${DzdFormatter.formatCentimes(s.differenceCentimes)}',
                                          style: TextStyle(
                                            color: s.differenceCentimes < 0 ? colors.error : Colors.blue,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                      if (s.notes != null && s.notes!.isNotEmpty)
                                        Text(
                                          'ملاحظة: ${s.notes}',
                                          style: TextStyle(color: colors.onObsidian.withValues(alpha: 0.65), fontSize: 10),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                          loading: () => AppStates.loading(),
                          error: (e, _) => AppStates.error('تعذر جلب سجل التسويات: $e'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
