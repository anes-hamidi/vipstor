import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:domain/domain.dart';
import 'package:core/core.dart';

import '../../../providers/inventory_providers.dart';
import '../../../providers/staff_providers.dart';
import '../../../router/staff_router.dart';
import 'create_purchase_order_dialog.dart';
import 'create_product_dialog.dart';
import 'cycle_count_audit_sheet.dart';
import 'low_stock_replenishment_dashboard.dart';
import 'purchase_order_details_dialog.dart';
import 'stock_adjustment_dialog.dart';
import 'stock_transfer_dialog.dart';

/// Manager command centre: a live operational cockpit built on real inventory,
/// order, purchasing, transfer, and audit data.
class ManagerCommandCenterView extends ConsumerWidget {
  final ValueChanged<int> onNavigateTab;

  const ManagerCommandCenterView({
    super.key,
    required this.onNavigateTab,
  });

  Future<void> _openLowStock(BuildContext context, WidgetRef ref) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => LowStockReplenishmentDashboard(
          onOpenPurchaseOrders: () {
            Navigator.of(context).pop();
            onNavigateTab(4);
          },
        ),
      ),
    );
    ref.invalidate(lowStockProductsProvider);
    ref.invalidate(purchaseOrdersListProvider);
  }

  Future<void> _openCycleCount(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.94,
      ),
      builder: (_) => const CycleCountAuditSheet(),
    );
    ref.invalidate(auditHistoryProvider);
    ref.invalidate(activeCycleCountProvider);
    ref.invalidate(liveProductsProvider);
    ref.invalidate(lowStockProductsProvider);
    ref.invalidate(stockAdjustmentHistoryProvider);
  }

  Future<void> _openAdjustment(BuildContext context, WidgetRef ref) async {
    await showDialog<void>(
      context: context,
      builder: (_) => const StockAdjustmentDialog(),
    );
    ref.invalidate(stockAdjustmentHistoryProvider);
    ref.invalidate(liveProductsProvider);
    ref.invalidate(lowStockProductsProvider);
  }

  Future<void> _openTransfer(BuildContext context, WidgetRef ref) async {
    await showDialog<void>(
      context: context,
      builder: (_) => const StockTransferDialog(),
    );
    ref.invalidate(stockTransfersProvider);
  }

  Future<void> _openCreatePurchaseOrder(
    BuildContext context,
    WidgetRef ref,
  ) async {
    await showDialog<PurchaseOrderEntity>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const CreatePurchaseOrderDialog(),
    );
    ref.invalidate(purchaseOrdersListProvider);
    ref.invalidate(lowStockProductsProvider);
  }

  Future<void> _openCreateProduct(BuildContext context, WidgetRef ref) async {
    await showDialog<void>(
      context: context,
      builder: (_) => const CreateProductDialog(),
    );
    ref.invalidate(liveProductsProvider);
    ref.invalidate(lowStockProductsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final lowStockAsync = ref.watch(lowStockProductsProvider);
    final productsAsync = ref.watch(liveProductsProvider);
    final ordersAsync = ref.watch(managerOnlineOrdersProvider);
    final posAsync = ref.watch(purchaseOrdersListProvider);
    final adjustmentsAsync = ref.watch(stockAdjustmentHistoryProvider);
    final transfersAsync = ref.watch(stockTransfersProvider);
    final auditsAsync = ref.watch(auditHistoryProvider);
    final authUser = ref.watch(authStateProvider);

    final lowStock = lowStockAsync.value ?? const <ProductEntity>[];
    final products = productsAsync.value ?? const <ProductEntity>[];
    final orders = ordersAsync.value ?? const <OrderEntity>[];
    final purchaseOrders = posAsync.value ?? const <PurchaseOrderEntity>[];
    final adjustments =
        adjustmentsAsync.value ?? const <StockAdjustmentEntity>[];
    final transfers = transfersAsync.value ?? const <StockTransferEntity>[];
    final audits = auditsAsync.value ?? const <CycleCountAuditEntity>[];

    final outOfStock = lowStock.where((p) => p.isOutOfStock).length;
    final critical = lowStock.where((p) => p.isCritical).length;
    final unverified = orders
        .where(
          (o) =>
              o.status == OrderStatus.submitted ||
              o.status == OrderStatus.requiresManagerReview,
        )
        .length;
    final inPreparation = orders
        .where(
          (o) =>
              o.status == OrderStatus.confirmed ||
              o.status == OrderStatus.preparing,
        )
        .length;
    final inDispatch = orders
        .where(
          (o) =>
              o.status == OrderStatus.ready ||
              o.status == OrderStatus.assigned ||
              o.status == OrderStatus.accepted ||
              o.status == OrderStatus.outForDelivery,
        )
        .length;
    final openPurchaseOrders = purchaseOrders
        .where((po) => po.isOrdered || po.isPartiallyReceived)
        .toList();
    final pendingTransfers =
        transfers.where((t) => t.isPending || t.isInTransit).length;
    final inventoryValue = products.fold<int>(
      0,
      (sum, p) => sum + (p.availableQty * p.costCentimes),
    );
    final latestAudit = audits.isEmpty
        ? null
        : (audits.toList()..sort((a, b) => b.startedAt.compareTo(a.startedAt)))
            .first;

    final attentionCount =
        critical + outOfStock + unverified + openPurchaseOrders.length;

    final content = <Widget>[
      _hero(
        context,
        ref,
        theme,
        authUser?.name ?? 'مدير المخزون',
        attentionCount,
      ),
      AppSpacing.gapMd,
      _kpis(
        lowStock: lowStock.length,
        outOfStock: outOfStock,
        critical: critical,
        inventoryValue: inventoryValue,
        unverified: unverified,
        activeOrders: orders.length,
        openPos: openPurchaseOrders.length,
        openPoValue: openPurchaseOrders.fold<int>(
          0,
          (sum, po) => sum + po.totalOrderedAmountCentimes,
        ),
      ),
      AppSpacing.gapMd,
      if (critical + outOfStock > 0)
        _banner(
          icon: Icons.warning_amber_rounded,
          color: Colors.red,
          title:
              '${critical + outOfStock} صنف في حالة حرجة أو منفد — يحتاج إعادة تزويد فورية.',
          actionLabel: 'معالجة النقص',
          onAction: () => _openLowStock(context, ref),
        ),
      if (critical + outOfStock > 0) AppSpacing.gapSm,
      if (unverified > 0)
        _banner(
          icon: Icons.notifications_active_outlined,
          color: const Color(0xFFF2994A),
          title: '$unverified طلب زبون بانتظار التحقق والتأكيد.',
          actionLabel: 'مراجعة الطلبات',
          onAction: () => onNavigateTab(1),
        ),
      if (unverified > 0) AppSpacing.gapSm,
      if (pendingTransfers > 0)
        _banner(
          icon: Icons.swap_horiz_rounded,
          color: const Color(0xFF2F80ED),
          title: '$pendingTransfers حركة نقل داخلي نشطة أو بانتظار البدء.',
          actionLabel: 'متابعة النقل',
          onAction: () => onNavigateTab(5),
        ),
      if (pendingTransfers > 0) AppSpacing.gapMd,
      _quickActions(context, ref, lowStock.length),
      AppSpacing.gapLg,
      _pipeline(theme, unverified, inPreparation, inDispatch),
      AppSpacing.gapLg,
      LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 980;
          final left = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _lowStockPanel(context, ref, lowStock, theme),
              AppSpacing.gapMd,
              _purchaseOrdersPanel(context, ref, openPurchaseOrders, theme),
            ],
          );
          final right = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _movementsPanel(context, adjustments, theme),
              AppSpacing.gapMd,
              _auditPanel(context, ref, latestAudit, pendingTransfers, theme),
            ],
          );
          if (!wide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [left, AppSpacing.gapMd, right],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: left),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: right),
            ],
          );
        },
      ),
      AppSpacing.gapLg,
    ];

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(lowStockProductsProvider);
        ref.invalidate(liveProductsProvider);
        ref.invalidate(managerOnlineOrdersProvider);
        ref.invalidate(purchaseOrdersListProvider);
        ref.invalidate(stockAdjustmentHistoryProvider);
        ref.invalidate(stockTransfersProvider);
        ref.invalidate(auditHistoryProvider);
        await Future.wait([
          ref.read(lowStockProductsProvider.future),
          ref.read(liveProductsProvider.future),
          ref.read(purchaseOrdersListProvider.future),
        ]);
      },
      child: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        children: content,
      ),
    );
  }

  Widget _hero(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    String userName,
    int attentionCount,
  ) {
    final now = DateTime.now();
    final dateLabel = _formatArabicDate(now);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF2A2116), const Color(0xFF14110D)]
              : [const Color(0xFF2A2116), const Color(0xFF4A371B)],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        borderRadius: AppRadius.lgAll,
        border: Border.all(
          color: const Color(0xFFD4AF37).withValues(alpha: 0.34),
        ),
        boxShadow: const [AppShadows.goldGlowSm],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  gradient: AppGradients.gold,
                  borderRadius: AppRadius.mdAll,
                  boxShadow: [AppShadows.goldGlow],
                ),
                child: const Icon(
                  Icons.diamond_outlined,
                  size: 26,
                  color: Color(0xFF1A1400),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'مركز عمليات المخزون',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      dateLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.62),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: attentionCount > 0
                      ? const Color(0xFFF2994A).withValues(alpha: 0.18)
                      : const Color(0xFF27AE60).withValues(alpha: 0.18),
                  borderRadius: AppRadius.pillAll,
                  border: Border.all(
                    color: attentionCount > 0
                        ? const Color(0xFFF2994A)
                        : const Color(0xFF27AE60),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  attentionCount > 0
                      ? '$attentionCount مهام معلقة'
                      : 'كل شيء تحت السيطرة',
                  style: TextStyle(
                    color: attentionCount > 0
                        ? const Color(0xFFF2994A)
                        : const Color(0xFF27AE60),
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          AppSpacing.gapMd,
          Text(
            'مرحباً، $userName',
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            attentionCount > 0
                ? 'لديك $attentionCount مهمة تحتاج انتباهك اليوم. ابدأ بالأصناف الحرجة والطلبات غير المؤكدة.'
                : 'المخزون والطلبات في وضع ممتاز. واصل المتابعة الدورية للحفاظ على هذا المستوى.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.72),
            ),
          ),
          AppSpacing.gapMd,
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              GoldButton.icon(
                icon: Icons.playlist_add_check_rounded,
                label: 'استلام فاتورة',
                compact: true,
                height: 40,
                onPressed: () => onNavigateTab(2),
              ),
              OutlinedButton.icon(
                onPressed: () => _openCreatePurchaseOrder(context, ref),
                icon: const Icon(Icons.receipt_long_rounded, size: 16),
                label: const Text('أمر شراء'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.28),
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _openLowStock(context, ref),
                icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                label: const Text('إعادة التزويد'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.28),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kpis({
    required int lowStock,
    required int outOfStock,
    required int critical,
    required int inventoryValue,
    required int unverified,
    required int activeOrders,
    required int openPos,
    required int openPoValue,
  }) {
    final items = [
      _ManagerKpi(
        label: 'أصناف تحتاج تزويد',
        value: '$lowStock',
        subtitle: '$critical حرج • $outOfStock منفد',
        icon: Icons.inventory_2_outlined,
        color: lowStock > 0 ? const Color(0xFFF2994A) : const Color(0xFF27AE60),
      ),
      _ManagerKpi(
        label: 'قيمة المخزون',
        value: DzdFormatter.formatCentimes(inventoryValue),
        subtitle: 'بالتكلفة الحالية',
        icon: Icons.account_balance_wallet_outlined,
        color: const Color(0xFFD4AF37),
      ),
      _ManagerKpi(
        label: 'طلبات بانتظار التحقق',
        value: '$unverified',
        subtitle: '$activeOrders طلب نشط',
        icon: Icons.shopping_bag_outlined,
        color:
            unverified > 0 ? const Color(0xFF2F80ED) : const Color(0xFF27AE60),
      ),
      _ManagerKpi(
        label: 'أوامر شراء مفتوحة',
        value: '$openPos',
        subtitle: DzdFormatter.formatCentimes(openPoValue),
        icon: Icons.receipt_long_outlined,
        color: openPos > 0 ? const Color(0xFF9B51E0) : const Color(0xFF27AE60),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 980
            ? 4
            : constraints.maxWidth >= 600
                ? 2
                : 1;
        const spacing = AppSpacing.md;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children:
              items.map((item) => SizedBox(width: width, child: item)).toList(),
        );
      },
    );
  }

  Widget _banner({
    required IconData icon,
    required Color color,
    required String title,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: color,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(
              actionLabel,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickActions(BuildContext context, WidgetRef ref, int lowStockCount) {
    final actions = [
      _QuickAction(
        label: 'استلام فاتورة',
        icon: Icons.receipt_long_rounded,
        color: const Color(0xFFD4AF37),
        onTap: () => onNavigateTab(2),
      ),
      _QuickAction(
        label: 'أمر شراء',
        icon: Icons.post_add_rounded,
        color: const Color(0xFF9B51E0),
        onTap: () => _openCreatePurchaseOrder(context, ref),
      ),
      _QuickAction(
        label: 'تسوية مخزون',
        icon: Icons.tune_rounded,
        color: const Color(0xFF2F80ED),
        onTap: () => _openAdjustment(context, ref),
      ),
      _QuickAction(
        label: 'نقل داخلي',
        icon: Icons.swap_horiz_rounded,
        color: const Color(0xFFF2994A),
        onTap: () => _openTransfer(context, ref),
      ),
      _QuickAction(
        label: 'جرد دوري',
        icon: Icons.fact_check_outlined,
        color: const Color(0xFF27AE60),
        onTap: () => _openCycleCount(context, ref),
      ),
      _QuickAction(
        label: 'منتج جديد',
        icon: Icons.add_box_outlined,
        color: const Color(0xFFEB5757),
        onTap: () => _openCreateProduct(context, ref),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1100
            ? 6
            : constraints.maxWidth >= 760
                ? 3
                : 2;
        const spacing = AppSpacing.sm;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: actions
              .map((action) => SizedBox(width: width, child: action))
              .toList(),
        );
      },
    );
  }

  Widget _pipeline(
    ThemeData theme,
    int verify,
    int prepare,
    int dispatch,
  ) {
    final stages = [
      ('التحقق والتأكيد', verify, Icons.inbox_rounded, const Color(0xFF2F80ED)),
      (
        'التحضير والتغليف',
        prepare,
        Icons.inventory_2_rounded,
        const Color(0xFFD4AF37)
      ),
      (
        'تعيين السائق',
        dispatch,
        Icons.local_shipping_rounded,
        const Color(0xFFF2994A)
      ),
    ];

    return LuxuryCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: SectionHeader(
                  title: 'مسار طلبات الزبائن',
                  dense: true,
                ),
              ),
              TextButton(
                onPressed: () => onNavigateTab(1),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('فتح المسار'),
              ),
            ],
          ),
          AppSpacing.gapSm,
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 620;
              final children = stages.map((stage) {
                final selectedColor = stage.$4;
                return _pipelineStage(
                  theme,
                  stage.$1,
                  stage.$2,
                  stage.$3,
                  selectedColor,
                );
              }).toList();
              if (compact) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: children
                        .map(
                          (child) => Padding(
                            padding: const EdgeInsetsDirectional.only(
                              end: AppSpacing.sm,
                            ),
                            child: SizedBox(width: 170, child: child),
                          ),
                        )
                        .toList(),
                  ),
                );
              }
              return Row(
                children: children
                    .map(
                      (child) => Expanded(
                        child: Padding(
                          padding: const EdgeInsetsDirectional.only(
                            end: AppSpacing.sm,
                          ),
                          child: child,
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _pipelineStage(
    ThemeData theme,
    String label,
    int count,
    IconData icon,
    Color color,
  ) {
    return InkWell(
      onTap: () => onNavigateTab(1),
      borderRadius: AppRadius.mdAll,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: AppRadius.mdAll,
          border: Border.all(color: color.withValues(alpha: 0.28)),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: AppRadius.smAll,
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 9.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lowStockPanel(
    BuildContext context,
    WidgetRef ref,
    List<ProductEntity> lowStock,
    ThemeData theme,
  ) {
    final sorted = lowStock.toList()
      ..sort((a, b) {
        int priority(ProductEntity p) {
          if (p.isOutOfStock) return 0;
          if (p.isCritical) return 1;
          if (p.isLowStock) return 2;
          return 3;
        }

        final byPriority = priority(a).compareTo(priority(b));
        if (byPriority != 0) return byPriority;
        return a.availableQty.compareTo(b.availableQty);
      });
    final items = sorted.take(5).toList();

    return LuxuryCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: SectionHeader(
                  title: 'أولويات إعادة التزويد (${lowStock.length})',
                  dense: true,
                ),
              ),
              TextButton(
                onPressed: () => _openLowStock(context, ref),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('عرض الكل'),
              ),
            ],
          ),
          AppSpacing.gapXs,
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Column(
                children: [
                  const Icon(
                    Icons.verified_rounded,
                    size: 34,
                    color: Color(0xFF27AE60),
                  ),
                  AppSpacing.gapXs,
                  Text(
                    'لا أصناف تحتاج تزويداً حالياً.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          else
            ...items.map((product) {
              final urgent = product.isOutOfStock || product.isCritical;
              final color = urgent
                  ? Colors.red
                  : product.isLowStock
                      ? Colors.orange
                      : const Color(0xFF27AE60);
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.nameAr,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'متاح ${product.availableQty} ${product.unit} • ROP ${product.reorderPoint} • المقترح +${product.suggestedReplenishmentQty}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 9.5,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: AppRadius.pillAll,
                      ),
                      child: Text(
                        '${product.availableQty}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _purchaseOrdersPanel(
    BuildContext context,
    WidgetRef ref,
    List<PurchaseOrderEntity> openPos,
    ThemeData theme,
  ) {
    final sorted = openPos.toList()
      ..sort((a, b) => b.orderDate.compareTo(a.orderDate));
    final items = sorted.take(4).toList();

    return LuxuryCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: SectionHeader(
                  title: 'أوامر الشراء المفتوحة',
                  dense: true,
                ),
              ),
              TextButton(
                onPressed: () => onNavigateTab(4),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('إدارة'),
              ),
            ],
          ),
          AppSpacing.gapXs,
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Column(
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 34,
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.45),
                  ),
                  AppSpacing.gapXs,
                  Text(
                    'لا توجد أوامر شراء مفتوحة.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          else
            ...items.map((po) {
              final progress = po.totalOrderedQuantity == 0
                  ? 0.0
                  : po.totalReceivedQuantity / po.totalOrderedQuantity;
              return InkWell(
                onTap: () => PurchaseOrderDetailsDialog.show(context, po),
                borderRadius: AppRadius.smAll,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.xs,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF9B51E0).withValues(alpha: 0.10),
                          borderRadius: AppRadius.smAll,
                        ),
                        child: const Icon(
                          Icons.receipt_long_rounded,
                          size: 16,
                          color: Color(0xFF9B51E0),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              po.poNumber,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '${po.supplierName} • ${po.status.labelAr}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 9.5,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            DzdFormatter.formatCentimes(
                              po.totalOrderedAmountCentimes,
                            ),
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFB8860B),
                            ),
                          ),
                          Text(
                            '${(progress * 100).toStringAsFixed(0)}% مستلم',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 9,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _movementsPanel(
    BuildContext context,
    List<StockAdjustmentEntity> adjustments,
    ThemeData theme,
  ) {
    final sorted = adjustments.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final items = sorted.take(5).toList();

    return LuxuryCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: SectionHeader(
                  title: 'آخر الحركات المخزنية',
                  dense: true,
                ),
              ),
              TextButton(
                onPressed: () => onNavigateTab(5),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('السجل'),
              ),
            ],
          ),
          AppSpacing.gapXs,
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Column(
                children: [
                  Icon(
                    Icons.history_rounded,
                    size: 34,
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.45),
                  ),
                  AppSpacing.gapXs,
                  Text(
                    'لا توجد حركات مسجلة بعد.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          else
            ...items.map((adjustment) {
              final firstItem =
                  adjustment.items.isEmpty ? null : adjustment.items.first;
              final totalDelta = adjustment.items.fold<int>(
                0,
                (sum, item) => sum + item.qtyChange,
              );
              final positive = totalDelta >= 0;
              return Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: (positive ? const Color(0xFF27AE60) : Colors.red)
                            .withValues(alpha: 0.10),
                        borderRadius: AppRadius.smAll,
                      ),
                      child: Icon(
                        positive
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: 15,
                        color: positive ? const Color(0xFF27AE60) : Colors.red,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            firstItem?.productName ??
                                adjustment.referenceNumber,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${adjustment.reason.labelAr} • ${adjustment.adjustedByName} • ${_shortDate(adjustment.createdAt)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 9,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${positive ? '+' : ''}$totalDelta',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: positive ? const Color(0xFF27AE60) : Colors.red,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _auditPanel(
    BuildContext context,
    WidgetRef ref,
    CycleCountAuditEntity? audit,
    int pendingTransfers,
    ThemeData theme,
  ) {
    return LuxuryCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'الجرد والرقابة', dense: true),
          AppSpacing.gapSm,
          if (audit == null)
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: AppRadius.mdAll,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.fact_check_outlined,
                    size: 26,
                    color: Color(0xFF27AE60),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'لم يتم إجراء جرد دوري بعد. ابدأ جلسة لمراجعة الفروقات.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () => _openCycleCount(context, ref),
                    child: const Text('بدء'),
                  ),
                ],
              ),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        audit.auditNumber,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                        ),
                      ),
                      Text(
                        '${audit.status.labelAr} • ${audit.countedByName}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 9.5,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                _auditAccuracyChip(audit),
              ],
            ),
            AppSpacing.gapXs,
            Row(
              children: [
                Text(
                  '${audit.discrepantItemsCount} فروقات من ${audit.totalItemsCount} صنف',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 9.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Text(
                  DzdFormatter.formatCentimes(
                    audit.netCostVarianceCentimes,
                  ),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: audit.netCostVarianceCentimes < 0
                        ? Colors.red
                        : const Color(0xFF27AE60),
                  ),
                ),
              ],
            ),
          ],
          const Divider(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: _miniStatus(
                  Icons.swap_horiz_rounded,
                  'نقل نشط',
                  '$pendingTransfers',
                  const Color(0xFFF2994A),
                  () => onNavigateTab(5),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _miniStatus(
                  Icons.receipt_long_rounded,
                  'أوامر شراء',
                  'فتح',
                  const Color(0xFF9B51E0),
                  () => onNavigateTab(4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _auditAccuracyChip(CycleCountAuditEntity audit) {
    final color = audit.accuracyRate >= 98
        ? const Color(0xFF27AE60)
        : audit.accuracyRate >= 90
            ? const Color(0xFFF2994A)
            : Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.pillAll,
      ),
      child: Text(
        '${audit.accuracyRate.toStringAsFixed(1)}%',
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _miniStatus(
    IconData icon,
    String label,
    String value,
    Color color,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.smAll,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: AppRadius.smAll,
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 9.5),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _shortDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$month/$day';
  }

  String _formatArabicDate(DateTime date) {
    const weekdays = [
      'الاثنين',
      'الثلاثاء',
      'الأربعاء',
      'الخميس',
      'الجمعة',
      'السبت',
      'الأحد',
    ];
    const months = [
      'جانفي',
      'فيفري',
      'مارس',
      'أفريل',
      'ماي',
      'جوان',
      'جويلية',
      'أوت',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر',
    ];
    return '${weekdays[date.weekday - 1]} ${date.day} ${months[date.month - 1]} ${date.year}';
  }
}

class _ManagerKpi extends StatelessWidget {
  final String label;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _ManagerKpi({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.11),
              borderRadius: AppRadius.smAll,
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 9.5,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLowest,
      borderRadius: AppRadius.mdAll,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.mdAll,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            borderRadius: AppRadius.mdAll,
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.11),
                  borderRadius: AppRadius.smAll,
                ),
                child: Icon(icon, size: 17, color: color),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
