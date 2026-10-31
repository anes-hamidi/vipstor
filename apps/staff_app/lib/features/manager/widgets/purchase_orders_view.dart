import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:core/core.dart';
import 'package:domain/domain.dart';

import '../../../providers/inventory_providers.dart';
import '../../../providers/staff_providers.dart';
import '../../../router/staff_router.dart';
import 'create_purchase_order_dialog.dart';
import 'grn_receiving_dialog.dart';
import 'low_stock_replenishment_dashboard.dart';
import 'purchase_order_details_dialog.dart';

/// Purchase-order workspace: lifecycle tracking, manual creation, and GRN
/// receiving against supplier orders.
class PurchaseOrdersView extends ConsumerStatefulWidget {
  const PurchaseOrdersView({super.key});

  @override
  ConsumerState<PurchaseOrdersView> createState() => _PurchaseOrdersViewState();
}

class _PurchaseOrdersViewState extends ConsumerState<PurchaseOrdersView> {
  final _searchController = TextEditingController();
  String _search = '';
  PurchaseOrderStatus? _statusFilter;
  bool _busy = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _createOrder() async {
    final created = await showDialog<PurchaseOrderEntity>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const CreatePurchaseOrderDialog(),
    );
    if (created != null && mounted) {
      _showSnack(
        created.status == PurchaseOrderStatus.draft
            ? 'تم حفظ أمر الشراء [${created.poNumber}] كمسودة.'
            : 'تم إنشاء أمر الشراء [${created.poNumber}] وإرساله للمورد.',
      );
    }
  }

  Future<void> _openReplenishment() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => const LowStockReplenishmentDashboard(),
      ),
    );
    if (mounted) {
      ref.invalidate(purchaseOrdersListProvider);
      ref.invalidate(lowStockProductsProvider);
    }
  }

  Future<void> _receive(PurchaseOrderEntity po) async {
    final received = await GrnReceivingDialog.show(context, po);
    if (received == true && mounted) {
      ref.invalidate(liveProductsProvider);
      ref.invalidate(lowStockProductsProvider);
      ref.invalidate(purchaseOrdersListProvider);
      ref.invalidate(stockAdjustmentHistoryProvider);
    }
  }

  Future<void> _moveToOrdered(PurchaseOrderEntity po) async {
    final user = ref.read(authStateProvider);
    if (user == null) return;
    final confirmed = await _confirm(
      title: 'إرسال أمر الشراء للمورد',
      message:
          'سيتم تحويل [${po.poNumber}] من مسودة إلى طلب مرسل للمورد. هل تريد المتابعة؟',
      confirmLabel: 'إرسال الطلب',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(inventoryRepositoryProvider).updatePurchaseOrderStatus(
            poId: po.id,
            status: PurchaseOrderStatus.ordered,
            userId: user.id,
            userName: user.name,
          );
      ref.invalidate(purchaseOrdersListProvider);
      _showSnack('تم إرسال أمر الشراء [${po.poNumber}] إلى المورد.');
    } catch (e) {
      _showError('تعذر تحديث أمر الشراء: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel(PurchaseOrderEntity po) async {
    final user = ref.read(authStateProvider);
    if (user == null) return;
    final confirmed = await _confirm(
      title: 'إلغاء أمر الشراء',
      message:
          'سيتم إلغاء [${po.poNumber}] ولن يمكن استلام بضاعته. هل تريد المتابعة؟',
      confirmLabel: 'إلغاء الطلب',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(inventoryRepositoryProvider).updatePurchaseOrderStatus(
            poId: po.id,
            status: PurchaseOrderStatus.cancelled,
            userId: user.id,
            userName: user.name,
          );
      ref.invalidate(purchaseOrdersListProvider);
      _showSnack('تم إلغاء أمر الشراء [${po.poNumber}].');
    } catch (e) {
      _showError('تعذر إلغاء أمر الشراء: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          destructive
              ? Icons.warning_amber_rounded
              : Icons.help_outline_rounded,
          color: destructive
              ? Theme.of(ctx).colorScheme.error
              : const Color(0xFFD4AF37),
        ),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('تراجع'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error,
                  )
                : null,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: context.appColors.success,
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ordersAsync = ref.watch(purchaseOrdersListProvider);

    return ordersAsync.when(
      skipLoadingOnRefresh: true,
      loading: () =>
          const AppLoadingView(message: 'جاري تحميل أوامر الشراء...'),
      error: (error, _) => AppErrorView(
        message: '$error',
        onRetry: () => ref.invalidate(purchaseOrdersListProvider),
      ),
      data: (orders) {
        final filtered = _applyFilters(orders);
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(purchaseOrdersListProvider);
            await ref.read(purchaseOrdersListProvider.future);
          },
          child: ListView(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.xxl,
            ),
            children: [
              _header(theme),
              AppSpacing.gapLg,
              _metrics(orders),
              AppSpacing.gapLg,
              _toolbar(theme, orders),
              AppSpacing.gapMd,
              if (filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xxl),
                  child: AppEmptyView(
                    icon: Icons.receipt_long_outlined,
                    title: orders.isEmpty
                        ? 'لا توجد أوامر شراء بعد'
                        : 'لا توجد نتائج مطابقة',
                    description: orders.isEmpty
                        ? 'أنشئ أمر شراء يدوياً أو ولّده تلقائياً من الأصناف منخفضة المخزون.'
                        : 'جرّب تغيير كلمات البحث أو فلتر الحالة.',
                    actionLabel: orders.isEmpty ? 'إنشاء أمر شراء' : null,
                    onAction: orders.isEmpty ? _createOrder : null,
                  ),
                )
              else
                ...filtered.map(
                  (po) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: PurchaseOrderCard(
                      purchaseOrder: po,
                      onTap: () => PurchaseOrderDetailsDialog.show(context, po),
                      onReceive: po.isOrdered || po.isPartiallyReceived
                          ? () => _receive(po)
                          : null,
                      onSend: po.isDraft && !_busy
                          ? () => _moveToOrdered(po)
                          : null,
                      onCancel: !po.isFullyReceived && !po.isCancelled && !_busy
                          ? () => _cancel(po)
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  List<PurchaseOrderEntity> _applyFilters(List<PurchaseOrderEntity> orders) {
    final query = _search.trim().toLowerCase();
    final result = orders.where((po) {
      if (_statusFilter != null && po.status != _statusFilter) return false;
      if (query.isEmpty) return true;
      return po.poNumber.toLowerCase().contains(query) ||
          po.supplierName.toLowerCase().contains(query) ||
          (po.supplierPhone ?? '').contains(query) ||
          po.createdByName.toLowerCase().contains(query) ||
          po.items.any(
            (item) => item.productName.toLowerCase().contains(query),
          );
    }).toList();

    result.sort((a, b) {
      int priority(PurchaseOrderStatus status) => switch (status) {
            PurchaseOrderStatus.partiallyReceived => 0,
            PurchaseOrderStatus.ordered => 1,
            PurchaseOrderStatus.draft => 2,
            PurchaseOrderStatus.fullyReceived => 3,
            PurchaseOrderStatus.cancelled => 4,
          };
      final byStatus = priority(a.status).compareTo(priority(b.status));
      if (byStatus != 0) return byStatus;
      return b.orderDate.compareTo(a.orderDate);
    });
    return result;
  }

  Widget _header(ThemeData theme) {
    final isCompact = context.isCompact;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFD4AF37).withValues(alpha: 0.14),
            theme.colorScheme.surfaceContainerLowest,
          ],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        borderRadius: AppRadius.lgAll,
        border: Border.all(
          color: const Color(0xFFD4AF37).withValues(alpha: 0.22),
        ),
      ),
      child: Flex(
        direction: isCompact ? Axis.vertical : Axis.horizontal,
        crossAxisAlignment:
            isCompact ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  gradient: AppGradients.gold,
                  borderRadius: AppRadius.mdAll,
                  boxShadow: [AppShadows.goldGlowSm],
                ),
                child: const Icon(
                  Icons.receipt_long_rounded,
                  size: 24,
                  color: Color(0xFF1A1400),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'أوامر الشراء والتوريد',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'تابع دورة حياة الطلبات، أرسلها للموردين، وسجّل الاستلام عبر GRN.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (isCompact) AppSpacing.gapMd else const Spacer(),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              OutlinedButton.icon(
                onPressed: _openReplenishment,
                icon: const Icon(Icons.auto_awesome_rounded, size: 17),
                label: const Text('توليد من النقص'),
              ),
              GoldButton.icon(
                icon: Icons.add_rounded,
                label: 'أمر شراء جديد',
                compact: true,
                onPressed: _createOrder,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metrics(List<PurchaseOrderEntity> orders) {
    final openOrders = orders.where(
      (po) => po.isOrdered || po.isPartiallyReceived,
    );
    final openValue = openOrders.fold<int>(
      0,
      (sum, po) => sum + po.totalOrderedAmountCentimes,
    );
    final awaiting = orders.where((po) => po.isOrdered).length;
    final partial = orders.where((po) => po.isPartiallyReceived).length;
    final dueSoon = openOrders.where((po) {
      final date = po.expectedDeliveryDate;
      if (date == null) return false;
      return date.isBefore(DateTime.now().add(const Duration(days: 7)));
    }).length;

    final metrics = [
      _PoMetric(
        label: 'طلبات مفتوحة',
        value: '${openOrders.length}',
        icon: Icons.pending_actions_rounded,
        color: const Color(0xFF2F80ED),
      ),
      _PoMetric(
        label: 'بانتظار التوريد',
        value: '$awaiting',
        icon: Icons.local_shipping_outlined,
        color: const Color(0xFFD4AF37),
      ),
      _PoMetric(
        label: 'استلام جزئي',
        value: '$partial',
        icon: Icons.downloading_rounded,
        color: const Color(0xFFF2994A),
      ),
      _PoMetric(
        label: 'قيمة الطلبات المفتوحة',
        value: DzdFormatter.formatCentimes(openValue),
        icon: Icons.account_balance_wallet_outlined,
        color: const Color(0xFF27AE60),
        subtitle: dueSoon > 0 ? '$dueSoon تسليم قريب' : null,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 980
            ? 4
            : constraints.maxWidth >= 620
                ? 2
                : 1;
        const spacing = AppSpacing.md;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children:
              metrics.map((m) => SizedBox(width: width, child: m)).toList(),
        );
      },
    );
  }

  Widget _toolbar(ThemeData theme, List<PurchaseOrderEntity> orders) {
    final isCompact = context.isCompact;
    final filters = <PurchaseOrderStatus?>[
      null,
      PurchaseOrderStatus.draft,
      PurchaseOrderStatus.ordered,
      PurchaseOrderStatus.partiallyReceived,
      PurchaseOrderStatus.fullyReceived,
      PurchaseOrderStatus.cancelled,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isCompact)
          Column(
            children: [
              _searchField(theme),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Text(
                  '${orders.length} أمر شراء',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          )
        else
          Row(
            children: [
              Expanded(child: _searchField(theme)),
              const SizedBox(width: AppSpacing.md),
              Text(
                '${orders.length} أمر شراء',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        const SizedBox(height: AppSpacing.sm),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: filters.map((status) {
              final count = status == null
                  ? orders.length
                  : orders.where((po) => po.status == status).length;
              final selected = _statusFilter == status;
              return Padding(
                padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
                child: ChoiceChip(
                  selected: selected,
                  showCheckmark: false,
                  avatar: Icon(
                    status == null ? Icons.apps_rounded : _statusIcon(status),
                    size: 15,
                    color: selected
                        ? const Color(0xFF1A1400)
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  label: Text(
                    '${status == null ? 'الكل' : status.labelAr} ($count)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          selected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  labelStyle: TextStyle(
                    color: selected
                        ? const Color(0xFF1A1400)
                        : theme.colorScheme.onSurface,
                  ),
                  selectedColor: const Color(0xFFD4AF37),
                  backgroundColor: theme.colorScheme.surfaceContainerLow,
                  side: BorderSide(
                    color: selected
                        ? const Color(0xFFD4AF37)
                        : theme.colorScheme.outlineVariant,
                  ),
                  onSelected: (_) => setState(() => _statusFilter = status),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _searchField(ThemeData theme) {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        isDense: true,
        hintText: 'بحث برقم الأمر، المورد، أو الصنف...',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: _search.isEmpty
            ? null
            : IconButton(
                tooltip: 'مسح البحث',
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _search = '');
                },
              ),
      ),
      onChanged: (value) => setState(() => _search = value),
    );
  }

  IconData _statusIcon(PurchaseOrderStatus status) {
    return switch (status) {
      PurchaseOrderStatus.draft => Icons.edit_note_rounded,
      PurchaseOrderStatus.ordered => Icons.send_rounded,
      PurchaseOrderStatus.partiallyReceived => Icons.downloading_rounded,
      PurchaseOrderStatus.fullyReceived => Icons.task_alt_rounded,
      PurchaseOrderStatus.cancelled => Icons.cancel_outlined,
    };
  }
}

/// Purchase-order summary card with GRN progress and lifecycle actions.
class PurchaseOrderCard extends StatelessWidget {
  final PurchaseOrderEntity purchaseOrder;
  final VoidCallback onTap;
  final VoidCallback? onReceive;
  final VoidCallback? onSend;
  final VoidCallback? onCancel;

  const PurchaseOrderCard({
    super.key,
    required this.purchaseOrder,
    required this.onTap,
    this.onReceive,
    this.onSend,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final po = purchaseOrder;
    final progress = po.totalOrderedQuantity == 0
        ? 0.0
        : po.totalReceivedQuantity / po.totalOrderedQuantity;
    final isCompact = context.isCompact;

    return LuxuryCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFD4AF37).withValues(alpha: 0.12),
                  borderRadius: AppRadius.mdAll,
                  border: Border.all(
                    color: const Color(0xFFD4AF37).withValues(alpha: 0.25),
                  ),
                ),
                child: Icon(
                  po.isCancelled
                      ? Icons.cancel_outlined
                      : po.isFullyReceived
                          ? Icons.task_alt_rounded
                          : Icons.receipt_long_rounded,
                  size: 20,
                  color: po.isCancelled
                      ? theme.colorScheme.error
                      : const Color(0xFFB8860B),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            po.poNumber,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        StatusBadge(
                          type: purchaseOrderBadgeType(po.status),
                          customLabel: po.status.labelAr,
                          compact: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          Icons.storefront_outlined,
                          size: 13,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            po.supplierName,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    DzdFormatter.formatCentimes(
                      po.totalOrderedAmountCentimes,
                    ),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: Color(0xFFB8860B),
                    ),
                  ),
                  Text(
                    '${po.items.length} أصناف',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 10,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: AppRadius.pillAll,
            child: LinearProgressIndicator(
              value: progress.clamp(0, 1),
              minHeight: 6,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(
                po.isCancelled
                    ? theme.colorScheme.error
                    : po.isFullyReceived
                        ? const Color(0xFF27AE60)
                        : const Color(0xFFD4AF37),
              ),
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Text(
                'تم استلام ${po.totalReceivedQuantity} من ${po.totalOrderedQuantity}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 10.5,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Text(
                '${(progress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 10.5,
                  color: Color(0xFFB8860B),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: 4,
            children: [
              _meta(
                Icons.event_outlined,
                _date(po.orderDate),
                theme,
              ),
              if (po.expectedDeliveryDate != null)
                _meta(
                  Icons.local_shipping_outlined,
                  'التسليم ${_date(po.expectedDeliveryDate!)}',
                  theme,
                ),
              _meta(
                Icons.person_outline_rounded,
                po.createdByName,
                theme,
              ),
            ],
          ),
          if (onReceive != null || onSend != null || onCancel != null) ...[
            const Divider(height: AppSpacing.lg),
            if (isCompact)
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                alignment: WrapAlignment.end,
                children: _actions(compact: true),
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: _actions(compact: false),
              ),
          ],
        ],
      ),
    );
  }

  List<Widget> _actions({required bool compact}) {
    return [
      if (onCancel != null)
        TextButton.icon(
          onPressed: onCancel,
          icon: const Icon(Icons.close_rounded, size: 16),
          label: const Text('إلغاء'),
          style: TextButton.styleFrom(
            foregroundColor: Colors.red,
            visualDensity: VisualDensity.compact,
          ),
        ),
      if (onSend != null)
        OutlinedButton.icon(
          onPressed: onSend,
          icon: const Icon(Icons.send_rounded, size: 16),
          label: const Text('إرسال للمورد'),
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
          ),
        ),
      if (onReceive != null)
        GoldButton.icon(
          icon: Icons.download_done_rounded,
          label: 'استلام (GRN)',
          compact: true,
          height: 38,
          onPressed: onReceive,
        ),
    ];
  }

  Widget _meta(IconData icon, String label, ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 3),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 10.5,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  String _date(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}

class _PoMetric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;

  const _PoMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
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
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: AppRadius.smAll,
            ),
            child: Icon(icon, size: 19, color: color),
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
                    fontSize: 10.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 9.5,
                      color: color,
                      fontWeight: FontWeight.bold,
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
