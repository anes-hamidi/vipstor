import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:domain/domain.dart';
import 'package:core/core.dart';

import '../../../providers/inventory_providers.dart';
import '../../../providers/staff_providers.dart';
import 'stock_adjustment_dialog.dart';
import 'cycle_count_audit_sheet.dart';
import 'low_stock_replenishment_dashboard.dart';
import 'stock_transfer_dialog.dart';
import 'create_product_dialog.dart';


class ManagerCommandCenterView extends ConsumerWidget {
  final ValueChanged<int> onNavigateTab;

  const ManagerCommandCenterView({
    super.key,
    required this.onNavigateTab,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final lowStockAsync = ref.watch(lowStockProductsProvider);
    final productsAsync = ref.watch(liveProductsProvider);
    final ordersAsync = ref.watch(managerOnlineOrdersProvider);
    final adjustmentsAsync = ref.watch(stockAdjustmentHistoryProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 1. Hero Summary Banner ─────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              gradient: isDark
                  ? const LinearGradient(
                      colors: [Color(0xFF241E15), Color(0xFF14120F)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : const LinearGradient(
                      colors: [Color(0xFFFFF9ED), Color(0xFFF5EEDB)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
              borderRadius: AppRadius.lgAll,
              border: Border.all(
                color: const Color(0xFFD4AF37).withValues(alpha: 0.35),
              ),
              boxShadow: const [AppShadows.goldGlowSm],
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 650;
                return Flex(
                  direction: isNarrow ? Axis.vertical : Axis.horizontal,
                  crossAxisAlignment: isNarrow
                      ? CrossAxisAlignment.start
                      : CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: const BoxDecoration(
                            gradient: AppGradients.gold,
                            borderRadius: AppRadius.mdAll,
                            boxShadow: [AppShadows.goldGlow],
                          ),
                          child: const Icon(
                            Icons.dashboard_customize_rounded,
                            size: 28,
                            color: Color(0xFF1A1400),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'مركز القيادة والعمليات اليومية',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'رؤية شاملة ومباشرة للطلبيات، المخزون، ونقاط إعادة التزويد',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (isNarrow) const SizedBox(height: AppSpacing.md),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      children: [
                        GoldButton.icon(
                          icon: Icons.tune_rounded,
                          label: 'تسوية سريعة',
                          compact: true,
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (_) => const StockAdjustmentDialog(),
                            );
                          },
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.add_shopping_cart_rounded, size: 16),
                          label: const Text('استلام فاتورة'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFD4AF37),
                            side: const BorderSide(color: Color(0xFFD4AF37)),
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () => onNavigateTab(1),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
          AppSpacing.gapLg,

          // ── 2. Live KPI Pulse Metrics ──────────────────────────────────────
          LayoutBuilder(
            builder: (context, constraints) {
              final isPhone = constraints.maxWidth < 600;
              final crossAxisCount = isPhone ? 2 : 4;
              return GridView.count(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: AppSpacing.md,
                mainAxisSpacing: AppSpacing.md,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: isPhone ? 1.4 : 1.7,
                children: [
                  // KPI 1: Pending Online Orders
                  ordersAsync.when(
                    data: (orders) {
                      final pendingCount = orders
                          .where((o) =>
                              o.status == OrderStatus.submitted ||
                              o.status ==
                                  OrderStatus.requiresManagerReview)
                          .length;
                      return _MetricCard(
                        title: 'طلبيات تنتظر التأكيد',
                        value: '$pendingCount',
                        subtitle: 'انقر للمعالجة في المسار',
                        icon: Icons.shopping_bag_outlined,
                        color: pendingCount > 0 ? Colors.orange : Colors.green,
                        onTap: () => onNavigateTab(0),
                      );
                    },
                    loading: () => const _LoadingMetricCard(),
                    error: (_, __) => const _ErrorMetricCard(title: 'الطلبيات'),
                  ),

                  // KPI 2: Low & Critical Stock Items
                  lowStockAsync.when(
                    data: (lowItems) {
                      final criticalCount = lowItems
                          .where((p) => p.isCritical || p.isOutOfStock)
                          .length;
                      return _MetricCard(
                        title: 'أصناف تحتاج تزويد',
                        value: '${lowItems.length}',
                        subtitle: '$criticalCount صنف بحالة حرجة',
                        icon: Icons.warning_amber_rounded,
                        color: lowItems.isNotEmpty ? Colors.red : Colors.green,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const LowStockReplenishmentDashboard(),
                            ),
                          );
                        },
                      );
                    },
                    loading: () => const _LoadingMetricCard(),
                    error: (_, __) => const _ErrorMetricCard(title: 'المخزون'),
                  ),

                  // KPI 3: Total Inventory Valuation
                  productsAsync.when(
                    data: (products) {
                      final totalValuationCentimes = products.fold<int>(
                        0,
                        (sum, p) => sum + p.inventoryValuationCentimes,
                      );
                      return _MetricCard(
                        title: 'تقييم المخزون المالي',
                        value: DzdFormatter.formatCentimes(totalValuationCentimes),
                        subtitle: '${products.length} صنف نشط مسجل',
                        icon: Icons.account_balance_wallet_outlined,
                        color: const Color(0xFFD4AF37),
                        onTap: () => onNavigateTab(3),
                      );
                    },
                    loading: () => const _LoadingMetricCard(),
                    error: (_, __) => const _ErrorMetricCard(title: 'التقييم'),
                  ),

                  // KPI 4: Active Cycle Counting
                  _MetricCard(
                    title: 'الجرد الدوري والمطابقة',
                    value: 'جاهز للجرد',
                    subtitle: 'تدقيق حي بدون إيقاف الصندوق',
                    icon: Icons.fact_check_outlined,
                    color: Colors.blueAccent,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const CycleCountAuditSheet(),
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),
          AppSpacing.gapXl,

          // ── 3. Quick Actions & Operations Grid ─────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'العمليات والمحطات الرئيسية',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'اختصارات العمليات اليومية',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          AppSpacing.gapMd,

          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 750;
              return Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  _ActionLauncherTile(
                    width: isWide ? (constraints.maxWidth - AppSpacing.md * 2) / 3 : constraints.maxWidth,
                    icon: Icons.swap_horiz_rounded,
                    title: 'نقل مخزون داخلي',
                    description: 'نقل البضائع بين المستودع الرئيسي وصالة العرض أو الرفوف',
                    actionLabel: 'بدء نقل جديد',
                    color: const Color(0xFF9C27B0),
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (_) => const StockTransferDialog(),
                      );
                    },
                  ),
                  _ActionLauncherTile(
                    width: isWide ? (constraints.maxWidth - AppSpacing.md * 2) / 3 : constraints.maxWidth,
                    icon: Icons.post_add_rounded,
                    title: 'إعادة التزويد الذكية',
                    description: 'إنشاء مسودات أوامر الشراء للمنتجات تحت نقطة الطلب',
                    actionLabel: 'فتح لوحة التزويد',
                    color: const Color(0xFFD4AF37),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const LowStockReplenishmentDashboard(),
                        ),
                      );
                    },
                  ),
                  _ActionLauncherTile(
                    width: isWide ? (constraints.maxWidth - AppSpacing.md * 2) / 3 : constraints.maxWidth,
                    icon: Icons.inventory_2_outlined,
                    title: 'إضافة منتج للكتالوج',
                    description: 'تسجيل صنف جديد، إعداد الباركود، والأسعار المتعددة',
                    actionLabel: 'إضافة منتج الآن',
                    color: Colors.green,
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (_) => const CreateProductDialog(),
                      );
                    },
                  ),
                ],
              );
            },
          ),
          AppSpacing.gapXl,

          // ── 4. Recent Stock Adjustments & Activity Audit ───────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'آخر تسويات وتعديلات المخزون',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.history_rounded, size: 16),
                label: const Text('سجل المشتريات'),
                onPressed: () => onNavigateTab(2),
              ),
            ],
          ),
          AppSpacing.gapSm,

          adjustmentsAsync.when(
            data: (adjustments) {
              if (adjustments.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF191714) : Colors.white,
                    borderRadius: AppRadius.mdAll,
                    border: Border.all(
                      color: isDark ? const Color(0x38D4AF37) : const Color(0x28C59B27),
                    ),
                  ),
                  child: const Center(
                    child: Text('لا توجد تسويات مسجلة مؤخراً. المخزون متوازن.'),
                  ),
                );
              }

              final displayItems = adjustments.take(4).toList();

              return Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF191714) : Colors.white,
                  borderRadius: AppRadius.mdAll,
                  border: Border.all(
                    color: isDark ? const Color(0x38D4AF37) : const Color(0x28C59B27),
                  ),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: displayItems.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final adj = displayItems[i];
                    final firstItem = adj.items.isNotEmpty ? adj.items.first : null;
                    final isNegative = firstItem != null && firstItem.qtyChange < 0;

                    return ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: (isNegative ? Colors.red : Colors.green).withValues(alpha: 0.12),
                          borderRadius: AppRadius.xsAll,
                        ),
                        child: Icon(
                          isNegative ? Icons.remove_circle_outline : Icons.add_circle_outline,
                          color: isNegative ? Colors.red : Colors.green,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        firstItem?.productName ?? adj.referenceNumber,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      subtitle: Text(
                        '${adj.reason.labelAr}  •  ${adj.adjustedByName}  •  ${adj.createdAt.day}/${adj.createdAt.month} ${adj.createdAt.hour}:${adj.createdAt.minute.toString().padLeft(2, '0')}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: Text(
                        firstItem != null
                            ? '${firstItem.qtyChange > 0 ? "+" : ""}${firstItem.qtyChange} ${firstItem.unit}'
                            : '',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: isNegative ? Colors.red : Colors.green,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

// ── Subcomponents ────────────────────────────────────────────────────────────

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.mdAll,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF191714) : Colors.white,
          borderRadius: AppRadius.mdAll,
          border: Border.all(
            color: color.withValues(alpha: 0.3),
          ),
          boxShadow: isDark ? null : AppShadows.cardSoftLight,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(icon, size: 20, color: color),
              ],
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: color,
                ),
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 10,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingMetricCard extends StatelessWidget {
  const _LoadingMetricCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: AppRadius.mdAll,
      ),
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _ErrorMetricCard extends StatelessWidget {
  final String title;

  const _ErrorMetricCard({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: AppRadius.mdAll,
      ),
      child: Center(
        child: Text(
          '$title: خطأ في الاتصال',
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ),
    );
  }
}

class _ActionLauncherTile extends StatelessWidget {
  final double width;
  final IconData icon;
  final String title;
  final String description;
  final String actionLabel;
  final Color color;
  final VoidCallback onTap;

  const _ActionLauncherTile({
    required this.width,
    required this.icon,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1A16) : Colors.white,
          borderRadius: AppRadius.mdAll,
          border: Border.all(
            color: color.withValues(alpha: 0.25),
          ),
          boxShadow: isDark ? null : AppShadows.cardSoftLight,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: AppRadius.xsAll,
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.md),
            InkWell(
              onTap: onTap,
              borderRadius: AppRadius.xsAll,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    actionLabel,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_rounded, size: 14, color: color),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
