import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:domain/domain.dart';
import '../../../providers/staff_providers.dart';
import '../../../router/staff_router.dart';
import '../services/pdf_invoice_service.dart';
import 'order_state_inspector.dart';

export '../../../providers/staff_providers.dart' show managerOnlineOrdersProvider, unverifiedOrdersCountProvider;

// ─── Pipeline Stage Enum ───────────────────────────────────────────────────

enum _PipelineStage {
  verify('التحقق والتأكيد', Icons.inbox_rounded),
  prepare('التحضير والتغليف', Icons.inventory_2_rounded),
  dispatch('تعيين السائق', Icons.local_shipping_rounded),
  history('السجل والتاريخ', Icons.history_rounded);

  final String label;
  final IconData icon;

  const _PipelineStage(this.label, this.icon);
}

class OnlineOrdersPipelineView extends ConsumerStatefulWidget {
  const OnlineOrdersPipelineView({super.key});

  @override
  ConsumerState<OnlineOrdersPipelineView> createState() =>
      _OnlineOrdersPipelineViewState();
}

class _OnlineOrdersPipelineViewState
    extends ConsumerState<OnlineOrdersPipelineView>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  bool _isActionLoading = false;

  // Search, sorting, selection & master-detail state
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchFilter = '';
  final Set<String> _selectedOrderIds = {};
  OrderEntity? _selectedOrder;
  bool _sortAscending = false;
  String _sortColumn = 'date';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    _tabCtrl.addListener(_onInnerTabChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _tabCtrl.removeListener(_onInnerTabChanged);
    _tabCtrl.dispose();
    super.dispose();
  }

  void _onInnerTabChanged() {
    if (mounted) setState(() {});
  }

  void _refreshOrders() {
    ref.invalidate(managerOnlineOrdersProvider);
    ref
        .read(managerOnlineOrderHistoryProvider.notifier)
        .refresh();
    ref.invalidate(liveProductsProvider);
  }

  // Batch actions
  Future<void> _handleBatchConfirm(List<OrderEntity> orders) async {
    final auth = ref.read(authStateProvider);
    if (auth == null) return;
    final submitted = orders.where((o) => _selectedOrderIds.contains(o.id) && 
        (o.status == OrderStatus.submitted || o.status == OrderStatus.requiresManagerReview)).toList();
    if (submitted.isEmpty) return;
    
    setState(() => _isActionLoading = true);
    final repo = ref.read(orderRepositoryProvider);
    int successCount = 0;
    try {
      for (final order in submitted) {
        await repo.confirmOrder(orderId: order.id, cashierId: auth.id);
        successCount++;
      }
      _selectedOrderIds.clear();
      _refreshOrders();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تأكيد وحجز المخزون لـ ($successCount) طلبية بنجاح!'),
            backgroundColor: context.appColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل التأكيد الجماعي: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _handleBatchPrepare(List<OrderEntity> orders) async {
    final auth = ref.read(authStateProvider);
    final confirmed = orders.where((o) => _selectedOrderIds.contains(o.id) && 
        (o.status == OrderStatus.confirmed || o.status == OrderStatus.preparing)).toList();
    if (confirmed.isEmpty) return;
    
    setState(() => _isActionLoading = true);
    final repo = ref.read(orderRepositoryProvider);
    int successCount = 0;
    try {
      for (final order in confirmed) {
        await repo.updateOrderPreparation(orderId: order.id, preparedBy: auth?.name ?? 'مدير المخزون');
        successCount++;
      }
      _selectedOrderIds.clear();
      _refreshOrders();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تجهيز ($successCount) طلبية بنجاح!'),
            backgroundColor: context.appColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل التجهيز المجمع: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _handleBatchPrint(List<OrderEntity> orders) async {
    final selected = orders.where((o) => _selectedOrderIds.contains(o.id)).toList();
    for (final order in selected) {
      await PdfInvoiceService.printDeliverySlip(order);
    }
  }

  void _showOrderInspectionSheet(OrderEntity order, List<ProductEntity> products, List<Map<String, dynamic>> staff) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, scrollController) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
          ),
          padding: const EdgeInsets.all(AppSpacing.md),
          child: ListView(
            controller: scrollController,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'طلب #${order.orderNumber ?? order.id.substring(0, 8)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  DzdPriceTag.lg(centimes: order.totalAmountCentimes, gold: true),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              OrderStateStepper(status: order.status),
              const SizedBox(height: AppSpacing.md),
              CustomerLedgerSyncCard(order: order),
              const SizedBox(height: AppSpacing.md),
              OrderStockAllocationCard(order: order, products: products),
              const SizedBox(height: AppSpacing.lg),
              _buildInspectorActions(order, products, staff),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInspectorActions(OrderEntity order, List<ProductEntity> products, List<Map<String, dynamic>> staff) {
    final theme = Theme.of(context);
    switch (order.status) {
      case OrderStatus.submitted:
      case OrderStatus.requiresManagerReview:
        return Row(
          children: [
            Expanded(
              child: GoldButton.icon(
                icon: Icons.verified_rounded,
                label: 'تدقيق وتأكيد وحجز المخزون',
                onPressed: () => _showValidationDialog(order, products),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
              icon: const Icon(Icons.cancel_outlined, size: 16),
              label: const Text('رفض'),
              onPressed: () => _showValidationDialog(order, products),
            ),
          ],
        );
      case OrderStatus.confirmed:
        return Row(
          children: [
            Expanded(
              child: GoldButton.icon(
                icon: Icons.inventory_2_outlined,
                label: 'بدء تجهيز وتغليف السلع',
                onPressed: () => _showPreparationDialog(order),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton(
              icon: const Icon(Icons.print_outlined),
              tooltip: 'طباعة وصل التجهيز',
              onPressed: () => PdfInvoiceService.printDeliverySlip(order),
            ),
          ],
        );
      case OrderStatus.preparing:
        return Row(
          children: [
            Expanded(
              child: GoldButton.icon(
                icon: Icons.done_all_rounded,
                label: 'إكمال التجهيز وجاهز للإرسال',
                onPressed: () => _showPreparationDialog(order),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton(
              icon: const Icon(Icons.print_outlined),
              tooltip: 'طباعة وصل التجهيز',
              onPressed: () => PdfInvoiceService.printDeliverySlip(order),
            ),
          ],
        );
      case OrderStatus.ready:
      case OrderStatus.assigned:
      case OrderStatus.accepted:
      case OrderStatus.outForDelivery:
        return Row(
          children: [
            Expanded(
              child: GoldButton.icon(
                icon: Icons.local_shipping_outlined,
                label: order.driverName != null ? 'تغيير السائق (${order.driverName})' : 'تعيين سائق التوصيل',
                onPressed: () => _showAssignDriverDialog(order, staff),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            OutlinedButton.icon(
              icon: const Icon(Icons.print_outlined, size: 16),
              label: const Text('طباعة الوصل'),
              onPressed: () => PdfInvoiceService.printDeliverySlip(order),
            ),
          ],
        );
      case OrderStatus.delivered:
      case OrderStatus.settled:
      case OrderStatus.cancelled:
      case OrderStatus.refused:
        return OutlinedButton.icon(
          icon: const Icon(Icons.print_outlined, size: 16),
          label: const Text('طباعة وصل التسليم'),
          onPressed: () => PdfInvoiceService.printDeliverySlip(order),
        );
    }
  }

  // ─── Stage Counts ─────────────────────────────────────────────────────────

  Map<_PipelineStage, int> _stageCounts(
    List<OrderEntity> liveOrders,
    List<OrderEntity> historyOrders,
  ) =>
      {
        _PipelineStage.verify: liveOrders
            .where((o) =>
                o.status == OrderStatus.submitted ||
                o.status == OrderStatus.requiresManagerReview)
            .length,
        _PipelineStage.prepare: liveOrders
            .where((o) =>
                o.status == OrderStatus.confirmed ||
                o.status == OrderStatus.preparing)
            .length,
        _PipelineStage.dispatch: liveOrders
            .where((o) =>
                o.status == OrderStatus.ready ||
                o.status == OrderStatus.assigned ||
                o.status == OrderStatus.accepted ||
                o.status == OrderStatus.outForDelivery)
            .length,
        _PipelineStage.history: historyOrders.length,
      };

  // ─── Dialogs ──────────────────────────────────────────────────────────────

  void _showValidationDialog(OrderEntity order, List<ProductEntity> products) {
    final theme = Theme.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final colors = context.appColors;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          bool allInStock = true;
          final stockEvals = order.items.map((item) {
            final product = products.firstWhere(
              (p) => p.id == item.productId,
              orElse: () => ProductEntity(
                id: item.productId,
                nameAr: item.productName,
                nameFr: '',
                category: '',
                unit: 'قطعة',
                packSize: 1,
                lastUnitCostCentimes: item.unitCostCentimes,
                availableQty: 0,
                active: true,
                barcodes: const [],
              ),
            );
            final ok = product.availableQty >= item.quantity;
            if (!ok) allInStock = false;
            return {
              'item': item,
              'product': product,
              'ok': ok,
              'available': product.availableQty,
            };
          }).toList();

          return Dialog(
            shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 580, maxHeight: 720),
              child: Column(
                children: [
                  _dialogHeader(
                    context: context,
                    icon: Icons.verified_outlined,
                    iconColor: theme.colorScheme.primary,
                    title:
                        'تدقيق الطلبية #${order.orderNumber ?? order.id.substring(0, 8)}',
                    onClose: () => Navigator.pop(ctx),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding:
                          const EdgeInsetsDirectional.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          LuxuryCard(
                            padding:
                                const EdgeInsets.all(AppSpacing.md),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SectionHeader(
                                    title: 'بيانات الزبون', dense: true),
                                AppSpacing.gapSm,
                                _infoRow(
                                  Icons.person_outline,
                                  order.customerName ??
                                      order.customerSnapshot?[
                                          'customer_name'] ??
                                      order.customerSnapshot?[
                                          'store_name'] ??
                                      'زبون',
                                ),
                                if (order.customerPhone != null ||
                                    order.customerSnapshot?['phone'] !=
                                        null)
                                  _infoRow(
                                    Icons.phone_outlined,
                                    order.customerPhone ??
                                        order.customerSnapshot?['phone'],
                                  ),
                                if (order.customerSnapshot?['address'] !=
                                        null ||
                                    order.customerSnapshot?[
                                            'address_text'] !=
                                        null)
                                  _infoRow(
                                    Icons.location_on_outlined,
                                    order.customerSnapshot?['address'] ??
                                        order.customerSnapshot?[
                                            'address_text'],
                                  ),
                                if (order.customerSnapshot?['latitude'] !=
                                    null)
                                  _infoRow(
                                    Icons.gps_fixed,
                                    'GPS: (${order.customerSnapshot!['latitude']}, ${order.customerSnapshot!['longitude']})',
                                    color: colors.success,
                                  ),
                              ],
                            ),
                          ),
                          AppSpacing.gapMd,
                          const SectionHeader(
                              title: 'مراجعة المخزون', dense: true),
                          AppSpacing.gapSm,
                          ...stockEvals.map((eval) {
                            final item = eval['item'] as OrderItemEntity;
                            final ok = eval['ok'] as bool;
                            final available = eval['available'] as int;
                            return _StockCheckRow(
                                item: item,
                                ok: ok,
                                available: available);
                          }),
                          AppSpacing.gapMd,
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                                vertical: AppSpacing.sm),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainer,
                              borderRadius: AppRadius.smAll,
                            ),
                            child: Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'المبلغ الإجمالي:',
                                  style: theme.textTheme.titleSmall
                                      ?.copyWith(
                                          fontWeight: FontWeight.bold),
                                ),
                                DzdPriceTag.lg(
                                    centimes: order.totalAmountCentimes,
                                    gold: true),
                              ],
                            ),
                          ),
                          if (!allInStock) ...[
                            AppSpacing.gapSm,
                            _warningBanner(
                                'بعض السلع تتجاوز المخزون الفعلي — يمكنك التأكيد مع العلم بالنقص.'),
                          ],
                        ],
                      ),
                    ),
                  ),
                  _dialogFooter(
                    context: ctx,
                    loading: _isActionLoading,
                    cancelLabel: 'إغلاق',
                    onCancel: () => Navigator.pop(ctx),
                    secondaryLabel: 'رفض الطلب',
                    secondaryIcon: Icons.cancel_outlined,
                    secondaryDanger: true,
                    onSecondary: () async {
                      Navigator.pop(ctx);
                      setState(() => _isActionLoading = true);
                      try {
                        final repo = ref.read(orderRepositoryProvider);
                        await repo.updateOrderStatus(
                          orderId: order.id,
                          status: OrderStatus.refused,
                          notes: 'رفض من طرف مسؤول المخزون',
                        );
                        _refreshOrders();
                        if (mounted) {
                          messenger.showSnackBar(const SnackBar(
                              content: Text('تم رفض الطلبية.')));
                        }
                      } finally {
                        if (mounted) {
                          setState(() => _isActionLoading = false);
                        }
                      }
                    },
                    primaryLabel: 'تأكيد وحجز المخزون',
                    primaryIcon: Icons.check_circle_rounded,
                    onPrimary: () async {
                      Navigator.pop(ctx);
                      setState(() => _isActionLoading = true);
                      try {
                        final repo = ref.read(orderRepositoryProvider);
                        final auth = ref.read(authStateProvider);
                        if (auth == null) return;
                        await repo.confirmOrder(
                            orderId: order.id, cashierId: auth.id);
                        _refreshOrders();
                        if (mounted) {
                          messenger.showSnackBar(SnackBar(
                            content: const Text(
                                'تم تأكيد الطلبية! انتقلت لمرحلة التحضير.'),
                            backgroundColor: context.appColors.success,
                          ));
                        }
                      } catch (e) {
                        if (mounted) {
                          messenger.showSnackBar(SnackBar(
                              content: Text('فشل التأكيد: $e'),
                              backgroundColor: Colors.red));
                        }
                      } finally {
                        if (mounted) {
                          setState(() => _isActionLoading = false);
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showPreparationDialog(OrderEntity order) {
    final messenger = ScaffoldMessenger.of(context);
    final checkedItems = <String, bool>{
      for (final it in order.items) it.id: false,
    };

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          final allChecked =
              checkedItems.values.every((v) => v == true);
          final checkedCount =
              checkedItems.values.where((v) => v).length;

          return Dialog(
            shape: const RoundedRectangleBorder(
                borderRadius: AppRadius.lgAll),
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: 520, maxHeight: 680),
              child: Column(
                children: [
                  _dialogHeader(
                    context: context,
                    icon: Icons.inventory_2_outlined,
                    iconColor: const Color(0xFFD4AF37),
                    title:
                        'تجهيز الطلبية #${order.orderNumber ?? order.id.substring(0, 8)}',
                    onClose: () => Navigator.pop(ctx),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsetsDirectional.all(
                          AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _PicklistProgress(
                              checked: checkedCount,
                              total: order.items.length),
                          AppSpacing.gapMd,
                          Text(
                            'أشّر على كل صنف أثناء جمعه وتغليفه:',
                            style:
                                Theme.of(context).textTheme.bodyMedium,
                          ),
                          AppSpacing.gapSm,
                          ...order.items.map((item) {
                            final isChecked =
                                checkedItems[item.id] ?? false;
                            return _PicklistItemTile(
                              item: item,
                              isChecked: isChecked,
                              onChanged: (val) => setDialogState(() =>
                                  checkedItems[item.id] = val ?? false),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                  _dialogFooter(
                    context: ctx,
                    loading: _isActionLoading,
                    cancelLabel: 'إلغاء',
                    onCancel: () => Navigator.pop(ctx),
                    primaryLabel: allChecked
                        ? 'اكتمل التجهيز — جاهز للتسليم'
                        : 'حفظ كجاهز للتسليم',
                    primaryIcon: Icons.done_all_rounded,
                    onPrimary: () async {
                      Navigator.pop(ctx);
                      setState(() => _isActionLoading = true);
                      try {
                        final repo = ref.read(orderRepositoryProvider);
                        final auth = ref.read(authStateProvider);
                        await repo.updateOrderPreparation(
                          orderId: order.id,
                          preparedBy: auth?.name ?? 'مدير المخزون',
                        );
                        _refreshOrders();
                        if (mounted) {
                          messenger.showSnackBar(SnackBar(
                            content: const Text(
                                'الطلبية جاهزة! يمكنك الآن تعيين السائق.'),
                            backgroundColor:
                                context.appColors.success,
                          ));
                        }
                      } finally {
                        if (mounted) {
                          setState(() => _isActionLoading = false);
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showAssignDriverDialog(
      OrderEntity order, List<Map<String, dynamic>> staffMembers) {
    final messenger = ScaffoldMessenger.of(context);
    final theme = Theme.of(context);
    final drivers =
        staffMembers.where((s) => s['role'] == 'driver').toList();
    String? selectedDriverId =
        drivers.isNotEmpty ? drivers.first['id'] as String : null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          return Dialog(
            shape: const RoundedRectangleBorder(
                borderRadius: AppRadius.lgAll),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _dialogHeader(
                    context: context,
                    icon: Icons.local_shipping_rounded,
                    iconColor: theme.colorScheme.primary,
                    title:
                        'تعيين سائق — طلب #${order.orderNumber ?? order.id.substring(0, 8)}',
                    onClose: () => Navigator.pop(ctx),
                  ),
                  Padding(
                    padding: const EdgeInsetsDirectional.all(
                        AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LuxuryCard(
                          padding:
                              const EdgeInsets.all(AppSpacing.md),
                          child: Column(
                            children: [
                              _infoRow(
                                Icons.person_outline,
                                order.customerName ??
                                    order.customerSnapshot?[
                                        'customer_name'] ??
                                    'زبون',
                                bold: true,
                              ),
                              _infoRow(
                                Icons.phone_outlined,
                                order.customerPhone ??
                                    order.customerSnapshot?['phone'] ??
                                    'غير محدد',
                              ),
                              _infoRow(
                                Icons.location_on_outlined,
                                order.customerSnapshot?['address'] ??
                                    order.customerSnapshot?[
                                        'address_text'] ??
                                    'غير محدد',
                              ),
                              const GoldDivider(
                                  margin: EdgeInsets.symmetric(
                                      vertical: AppSpacing.sm)),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'المبلغ المطلوب تحصيله:',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                  DzdPriceTag.lg(
                                      centimes:
                                          order.totalAmountCentimes,
                                      gold: true),
                                ],
                              ),
                            ],
                          ),
                        ),
                        AppSpacing.gapLg,
                        if (drivers.isEmpty)
                          _warningBanner(
                              'لا يوجد سائقون مسجلون. أضف سائقاً من لوحة المشرف.')
                        else
                          DropdownButtonFormField<String>(
                            initialValue: selectedDriverId,
                            decoration: const InputDecoration(
                              labelText: 'اختر سائق التوصيل *',
                              prefixIcon: Icon(
                                  Icons.person_pin_circle_outlined),
                            ),
                            items: drivers.map((d) {
                              return DropdownMenuItem<String>(
                                value: d['id'] as String,
                                child: Text(
                                    '${d['name']} (${d['phone'] ?? ""})'),
                              );
                            }).toList(),
                            onChanged: (val) => setDialogState(
                                () => selectedDriverId = val),
                          ),
                      ],
                    ),
                  ),
                  _dialogFooter(
                    context: ctx,
                    loading: _isActionLoading,
                    cancelLabel: 'إلغاء',
                    onCancel: () => Navigator.pop(ctx),
                    primaryLabel: 'تعيين وإرسال للسائق',
                    primaryIcon: Icons.send_rounded,
                    primaryEnabled: selectedDriverId != null,
                    onPrimary: () async {
                      Navigator.pop(ctx);
                      setState(() => _isActionLoading = true);
                      try {
                        final selectedDriver = drivers.firstWhere(
                            (d) => d['id'] == selectedDriverId);
                        final repo = ref.read(orderRepositoryProvider);
                        await repo.assignOrderToDriver(
                          orderId: order.id,
                          driverId: selectedDriverId!,
                          driverName:
                              selectedDriver['name'] as String,
                          driverPhone:
                              selectedDriver['phone'] as String?,
                        );
                        _refreshOrders();
                        if (mounted) {
                          messenger.showSnackBar(SnackBar(
                            content: Text(
                                'تم التعيين للسائق "${selectedDriver['name']}"!'),
                            backgroundColor:
                                context.appColors.success,
                          ));
                        }
                      } finally {
                        if (mounted) {
                          setState(() => _isActionLoading = false);
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<List<OrderEntity>>>(managerOnlineOrdersProvider, (prev, next) {
      final prevList = prev?.value ?? [];
      final nextList = next.value ?? [];
      final prevPending = prevList
          .where((o) =>
              o.status == OrderStatus.submitted ||
              o.status == OrderStatus.requiresManagerReview)
          .length;
      final nextPending = nextList
          .where((o) =>
              o.status == OrderStatus.submitted ||
              o.status == OrderStatus.requiresManagerReview)
          .length;

      if (prev != null && nextPending > prevPending) {
        SystemSound.play(SystemSoundType.alert);
        HapticFeedback.mediumImpact();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.notifications_active_rounded, color: Colors.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('🔔 طلبية زبون جديدة وردت الآن! ($nextPending بانتظار التدقيق)'),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF1F1A12),
              duration: const Duration(seconds: 4),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    });

    final liveAsync = ref.watch(managerOnlineOrdersProvider);
    final historyState = ref.watch(managerOnlineOrderHistoryProvider);
    final productsAsync = ref.watch(liveProductsProvider);
    final staffAsync = ref.watch(staffMembersProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final liveOrders = liveAsync.value ?? const <OrderEntity>[];
    final historyOrders = historyState.orders;
    final products = productsAsync.value ?? [];
    final staff = staffAsync.value ?? [];

    final submitted = liveOrders
        .where((o) =>
            o.status == OrderStatus.submitted ||
            o.status == OrderStatus.requiresManagerReview)
        .toList();
    final confirming = liveOrders
        .where((o) =>
            o.status == OrderStatus.confirmed ||
            o.status == OrderStatus.preparing)
        .toList();
    final ready = liveOrders
        .where((o) =>
            o.status == OrderStatus.ready ||
            o.status == OrderStatus.assigned ||
            o.status == OrderStatus.accepted ||
            o.status == OrderStatus.outForDelivery)
        .toList();

    final mainContent = Column(
      children: [
        // ── Pipeline Tab Bar ─────────────────────────────────────────
        _PipelineTabBar(
          controller: _tabCtrl,
          stages: _PipelineStage.values,
          counts: _stageCounts(liveOrders, historyOrders),
          plusCounts: historyState.hasMore
              ? const {_PipelineStage.history}
              : const {},
          isDark: isDark,
        ),

        Container(
          height: 1,
          color: const Color(0xFFD4AF37)
              .withValues(alpha: isDark ? 0.15 : 0.10),
        ),

        // ── Tab Content ──────────────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              // Stage 1: Verify
              _buildLiveStage(
                liveAsync: liveAsync,
                orders: submitted,
                products: products,
                staff: staff,
                emptyIcon: Icons.inbox_outlined,
                emptyTitle: 'لا طلبيات واردة جديدة',
                emptyDesc: 'ستظهر هنا طلبيات الزبائن الجديدة.',
                actionBuilder: (o) => GoldButton.icon(
                  icon: Icons.verified_rounded,
                  label: 'تدقيق وتأكيد',
                  onPressed: () => _showValidationDialog(o, products),
                  compact: true,
                ),
              ),
              // Stage 2: Prepare
              _buildLiveStage(
                liveAsync: liveAsync,
                orders: confirming,
                products: products,
                staff: staff,
                emptyIcon: Icons.inventory_2_outlined,
                emptyTitle: 'لا طلبيات قيد التحضير',
                emptyDesc: 'الطلبيات المؤكدة تنتظر التجهيز هنا.',
                actionBuilder: (o) => OutlinedButton.icon(
                  onPressed: () => _showPreparationDialog(o),
                  icon: const Icon(Icons.inventory_2_outlined, size: 16),
                  label: const Text('تجهيز السلع'),
                ),
              ),
              // Stage 3: Dispatch
              _buildLiveStage(
                liveAsync: liveAsync,
                orders: ready,
                products: products,
                staff: staff,
                emptyIcon: Icons.local_shipping_outlined,
                emptyTitle: 'لا طلبيات جاهزة للإرسال',
                emptyDesc: 'الطلبيات الجاهزة للتوصيل ستظهر هنا.',
                actionBuilder: (o) => Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    GoldIconButton(
                      icon: Icons.print_outlined,
                      tooltip: 'طباعة وصل التسليم',
                      onPressed: () =>
                          PdfInvoiceService.printDeliverySlip(o),
                      size: 32,
                    ),
                    if (o.status == OrderStatus.ready ||
                        o.driverId == null)
                      OutlinedButton.icon(
                        onPressed: () =>
                            _showAssignDriverDialog(o, staff),
                        icon: const Icon(
                            Icons.person_pin_circle_outlined,
                            size: 16),
                        label: const Text('تعيين سائق'),
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: () =>
                            _showAssignDriverDialog(o, staff),
                        icon: const Icon(Icons.sync_alt_rounded,
                            size: 16),
                        label: Text(
                          o.driverName != null
                              ? 'تغيير: ${o.driverName}'
                              : 'تغيير السائق',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              // Stage 4: Date-filtered history
              _buildHistoryTab(historyState, products, staff),
            ],
          ),
        ),
      ],
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
          _searchFocusNode.requestFocus();
        },
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () {
          _searchFocusNode.requestFocus();
        },
        const SingleActivator(LogicalKeyboardKey.escape): () {
          setState(() {
            _selectedOrderIds.clear();
            _selectedOrder = null;
          });
        },
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () {
          _refreshOrders();
        },
      },
      child: Focus(
        autofocus: true,
        child: mainContent,
      ),
    );
  }

  Widget _buildLiveStage({
    required AsyncValue<List<OrderEntity>> liveAsync,
    required List<OrderEntity> orders,
    required List<ProductEntity> products,
    required List<Map<String, dynamic>> staff,
    required IconData emptyIcon,
    required String emptyTitle,
    required String emptyDesc,
    required Widget Function(OrderEntity) actionBuilder,
  }) {
    if (!liveAsync.hasValue && liveAsync.isLoading) {
      return AppStates.loading(
        message: 'جاري تحميل طلبيات الزبائن...',
      );
    }
    if (!liveAsync.hasValue && liveAsync.hasError) {
      return AppStates.error(
        'تعذر تحميل الطلبيات',
        onRetry: _refreshOrders,
      );
    }
    return _buildOrderList(
      orders: orders,
      products: products,
      staff: staff,
      emptyIcon: emptyIcon,
      emptyTitle: emptyTitle,
      emptyDesc: emptyDesc,
      actionBuilder: actionBuilder,
    );
  }

  Widget _buildHistoryTab(
    ManagerOrderHistoryState state,
    List<ProductEntity> products,
    List<Map<String, dynamic>> staff,
  ) {
    return Column(
      children: [
        _buildHistoryFilterCard(state),
        if (state.isLoading && state.orders.isNotEmpty)
          const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: state.isLoading && state.orders.isEmpty
              ? AppStates.loading(
                  message: 'جاري تحميل سجل الطلبيات...',
                )
              : state.error != null && state.orders.isEmpty
                  ? AppStates.error(
                      'تعذر تحميل سجل الطلبيات',
                      onRetry: () => ref
                          .read(managerOnlineOrderHistoryProvider.notifier)
                          .refresh(),
                    )
                  : state.orders.isEmpty
                      ? AppStates.empty(
                          icon: Icons.history_rounded,
                          title: 'لا توجد طلبيات في هذه الفترة',
                          description:
                              'غيّر فترة التاريخ لعرض طلبيات أخرى.',
                        )
                      : Column(
                          children: [
                            Expanded(
                              child: _buildOrderList(
                                orders: state.orders,
                                products: products,
                                staff: staff,
                                emptyIcon: Icons.history_rounded,
                                emptyTitle: 'لا توجد طلبيات في هذه الفترة',
                                emptyDesc: 'غيّر فترة التاريخ لعرض طلبيات أخرى.',
                                actionBuilder: (o) => OutlinedButton.icon(
                                  onPressed: () =>
                                      PdfInvoiceService.printDeliverySlip(o),
                                  icon: const Icon(Icons.print_outlined, size: 16),
                                  label: const Text('طباعة الوصل'),
                                ),
                              ),
                            ),
                            if (state.hasMore) _buildHistoryLoadMore(state),
                          ],
                        ),
        ),
      ],
    );
  }

  Widget _buildHistoryFilterCard(ManagerOrderHistoryState state) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
      child: LuxuryCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Icon(
              Icons.date_range_rounded,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'فترة سجل الطلبيات',
                    style: theme.textTheme.labelMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_formatHistoryDate(state.rangeStart)}  —  ${_formatHistoryDate(state.rangeEnd)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Wrap(
              spacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _pickHistoryDateRange,
                  icon: const Icon(Icons.edit_calendar_outlined,
                      size: 16),
                  label: const Text('تغيير الفترة'),
                ),
                GoldIconButton(
                  icon: Icons.refresh_rounded,
                  tooltip: 'تحديث السجل',
                  onPressed: () => ref
                      .read(managerOnlineOrderHistoryProvider.notifier)
                      .refresh(),
                  size: 32,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryLoadMore(ManagerOrderHistoryState state) {
    if (state.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (state.error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Center(
          child: TextButton.icon(
            onPressed: () => ref
                .read(managerOnlineOrderHistoryProvider.notifier)
                .loadMore(),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('إعادة محاولة تحميل المزيد'),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Center(
        child: OutlinedButton.icon(
          onPressed: () => ref
              .read(managerOnlineOrderHistoryProvider.notifier)
              .loadMore(),
          icon: const Icon(Icons.expand_more_rounded, size: 18),
          label: const Text('تحميل المزيد'),
        ),
      ),
    );
  }

  Future<void> _pickHistoryDateRange() async {
    final state = ref.read(managerOnlineOrderHistoryProvider);
    final now = DateTime.now();
    final firstDate = DateTime(2020);
    final lastDate = DateTime(
      now.year,
      now.month,
      now.day,
      23,
      59,
      59,
      999,
    );
    final initialStart = state.rangeStart.isBefore(firstDate)
        ? firstDate
        : state.rangeStart;
    final initialEnd =
        state.rangeEnd.isAfter(lastDate) ? lastDate : state.rangeEnd;

    final picked = await showDateRangePicker(
      context: context,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDateRange: DateTimeRange(
        start: initialStart,
        end: initialEnd,
      ),
      helpText: 'اختر فترة سجل الطلبيات',
      saveText: 'تطبيق',
      cancelText: 'إلغاء',
    );
    if (picked == null) return;

    await ref
        .read(managerOnlineOrderHistoryProvider.notifier)
        .setRange(start: picked.start, end: picked.end);
  }

  String _formatHistoryDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    return '${local.day}/${local.month} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  StatusBadgeType _statusBadgeType(OrderStatus status) {
    switch (status) {
      case OrderStatus.submitted:
        return StatusBadgeType.pending;
      case OrderStatus.confirmed:
        return StatusBadgeType.processing;
      case OrderStatus.preparing:
        return StatusBadgeType.preparing;
      case OrderStatus.ready:
      case OrderStatus.assigned:
      case OrderStatus.accepted:
      case OrderStatus.outForDelivery:
        return StatusBadgeType.ready;
      case OrderStatus.delivered:
        return StatusBadgeType.delivered;
      case OrderStatus.settled:
        return StatusBadgeType.completed;
      case OrderStatus.refused:
      case OrderStatus.cancelled:
        return StatusBadgeType.cancelled;
      case OrderStatus.requiresManagerReview:
        return StatusBadgeType.draft;
      // ignore: unreachable_switch_default
      default:
        return StatusBadgeType.draft;
    }
  }

  // ─── Order List & Responsive Layouts ─────────────────────────────────────────

  Widget _buildOrderList({
    required List<OrderEntity> orders,
    required List<ProductEntity> products,
    required List<Map<String, dynamic>> staff,
    required IconData emptyIcon,
    required String emptyTitle,
    required String emptyDesc,
    required Widget Function(OrderEntity) actionBuilder,
  }) {
    var filtered = orders.where((o) {
      if (_searchFilter.isEmpty) return true;
      final q = _searchFilter.toLowerCase();
      final numStr = o.orderNumber?.toString() ?? o.id;
      final customer = (o.customerName ?? o.customerSnapshot?['customer_name'] ?? '').toLowerCase();
      final phone = (o.customerPhone ?? o.customerSnapshot?['phone'] ?? '');
      return numStr.contains(q) || customer.contains(q) || phone.contains(q);
    }).toList();

    filtered.sort((a, b) {
      int cmp = 0;
      if (_sortColumn == 'date') {
        cmp = b.createdAt.compareTo(a.createdAt);
      } else if (_sortColumn == 'amount') {
        cmp = b.totalAmountCentimes.compareTo(a.totalAmountCentimes);
      } else if (_sortColumn == 'customer') {
        final nameA = a.customerName ?? '';
        final nameB = b.customerName ?? '';
        cmp = nameA.compareTo(nameB);
      } else if (_sortColumn == 'number') {
        final numA = a.orderNumber ?? 0;
        final numB = b.orderNumber ?? 0;
        cmp = numB.compareTo(numA);
      }
      return _sortAscending ? -cmp : cmp;
    });

    if (filtered.isEmpty) {
      if (_searchFilter.isNotEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.search_off_rounded, size: 48, color: Colors.grey),
              const SizedBox(height: AppSpacing.sm),
              Text('لا توجد نتائج تطابق: "$_searchFilter"'),
              TextButton(
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchFilter = '');
                },
                child: const Text('مسح البحث'),
              ),
            ],
          ),
        );
      }
      return AppStates.empty(icon: emptyIcon, title: emptyTitle, description: emptyDesc);
    }

    final screenWidth = MediaQuery.sizeOf(context).width;

    if (screenWidth >= 1024) {
      return _buildDesktopMasterDetailView(
        orders: filtered,
        products: products,
        staff: staff,
        actionBuilder: actionBuilder,
      );
    } else if (screenWidth >= 600) {
      return _buildTabletCardGrid(
        orders: filtered,
        products: products,
        staff: staff,
        actionBuilder: actionBuilder,
      );
    } else {
      return _buildMobileOrderList(
        orders: filtered,
        products: products,
        staff: staff,
        actionBuilder: actionBuilder,
      );
    }
  }

  Widget _buildDesktopMasterDetailView({
    required List<OrderEntity> orders,
    required List<ProductEntity> products,
    required List<Map<String, dynamic>> staff,
    required Widget Function(OrderEntity) actionBuilder,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final selected = _selectedOrder != null && orders.any((o) => o.id == _selectedOrder!.id)
        ? orders.firstWhere((o) => o.id == _selectedOrder!.id)
        : orders.first;

    final allSelected = orders.isNotEmpty && orders.every((o) => _selectedOrderIds.contains(o.id));

    return Column(
      children: [
        // Desktop Top Search & Controls Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
          color: isDark ? const Color(0xFF141210) : const Color(0xFFFAF7F0),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    decoration: InputDecoration(
                      hintText: 'بحث سريع (رقم الطلب، اسم الزبون، الهاتف)...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            margin: const EdgeInsetsDirectional.only(end: 6),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white12 : Colors.black12,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('Ctrl+F', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                          if (_searchFilter.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchFilter = '');
                              },
                            ),
                        ],
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onChanged: (v) => setState(() => _searchFilter = v.trim()),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('تحديث'),
                onPressed: _refreshOrders,
              ),
            ],
          ),
        ),

        // Batch Action Bar when checkboxes selected
        OrderBatchActionBar(
          selectedCount: _selectedOrderIds.length,
          onClearSelection: () => setState(() => _selectedOrderIds.clear()),
          onBatchConfirm: () => _handleBatchConfirm(orders),
          onBatchPrepare: () => _handleBatchPrepare(orders),
          onBatchPrint: () => _handleBatchPrint(orders),
          isLoading: _isActionLoading,
        ),

        // Master-Detail Split Row
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left side: Advanced Data Grid (Master)
              Expanded(
                flex: 3,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: const Color(0xFFD4AF37).withValues(alpha: 0.20),
                      ),
                    ),
                  ),
                  child: Column(
                    children: [
                      // Sticky Table Header
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 8),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF191714) : const Color(0xFFF5EEDB),
                          border: Border(
                            bottom: BorderSide(
                              color: const Color(0xFFD4AF37).withValues(alpha: 0.25),
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Checkbox(
                              value: allSelected,
                              activeColor: const Color(0xFFD4AF37),
                              onChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    _selectedOrderIds.addAll(orders.map((o) => o.id));
                                  } else {
                                    _selectedOrderIds.clear();
                                  }
                                });
                              },
                            ),
                            _sortableHeader('الطلب', 'number', flex: 2),
                            _sortableHeader('الزبون', 'customer', flex: 3),
                            _sortableHeader('المبلغ', 'amount', flex: 2),
                            const Expanded(
                              flex: 2,
                              child: Text(
                                'حالة المخزون',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 80, child: Text('الإجراء', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                          ],
                        ),
                      ),
                      // Scrollable Table Body
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: () async => _refreshOrders(),
                          child: ListView.separated(
                            itemCount: orders.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final o = orders[i];
                              final isRowSelected = o.id == selected.id;
                              final isChecked = _selectedOrderIds.contains(o.id);

                              return InkWell(
                                onTap: () => setState(() => _selectedOrder = o),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isRowSelected
                                        ? const Color(0xFFD4AF37).withValues(alpha: isDark ? 0.15 : 0.10)
                                        : Colors.transparent,
                                    border: isRowSelected
                                        ? const Border(
                                            right: BorderSide(color: Color(0xFFD4AF37), width: 3),
                                          )
                                        : null,
                                  ),
                                  child: Row(
                                    children: [
                                      Checkbox(
                                        value: isChecked,
                                        activeColor: const Color(0xFFD4AF37),
                                        onChanged: (val) {
                                          setState(() {
                                            if (val == true) {
                                              _selectedOrderIds.add(o.id);
                                            } else {
                                              _selectedOrderIds.remove(o.id);
                                            }
                                          });
                                        },
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '#${o.orderNumber ?? o.id.substring(0, 8)}',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                            ),
                                            Text(
                                              _formatDate(o.createdAt),
                                              style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              o.customerName ?? o.customerSnapshot?['customer_name'] ?? 'زبون',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            if (o.customerPhone != null || o.customerSnapshot?['phone'] != null)
                                              Text(
                                                o.customerPhone ?? o.customerSnapshot?['phone'] ?? '',
                                                style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
                                              ),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: DzdPriceTag(centimes: o.totalAmountCentimes, gold: true),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            StatusBadge(type: _statusBadgeType(o.status)),
                                            const SizedBox(height: 2),
                                            Text(
                                              _stockReservationLabel(o.status),
                                              style: TextStyle(fontSize: 10, color: _stockReservationColor(o.status)),
                                            ),
                                          ],
                                        ),
                                      ),
                                      SizedBox(
                                        width: 80,
                                        child: actionBuilder(o),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Right side: Master Order Inspector & Action Console (Detail)
              Expanded(
                flex: 2,
                child: Container(
                  color: isDark ? const Color(0xFF141210) : const Color(0xFFFFFDF8),
                  child: ListView(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.receipt_long_rounded, color: Color(0xFFD4AF37)),
                              const SizedBox(width: AppSpacing.xs),
                              Text(
                                'طلب #${selected.orderNumber ?? selected.id.substring(0, 8)}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ],
                          ),
                          DzdPriceTag.lg(centimes: selected.totalAmountCentimes, gold: true),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      OrderStateStepper(status: selected.status),
                      const SizedBox(height: AppSpacing.md),
                      CustomerLedgerSyncCard(order: selected),
                      const SizedBox(height: AppSpacing.md),
                      OrderStockAllocationCard(order: selected, products: products),
                      const SizedBox(height: AppSpacing.md),
                      _buildInspectorActions(selected, products, staff),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabletCardGrid({
    required List<OrderEntity> orders,
    required List<ProductEntity> products,
    required List<Map<String, dynamic>> staff,
    required Widget Function(OrderEntity) actionBuilder,
  }) {
    return RefreshIndicator(
      onRefresh: () async => _refreshOrders(),
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: orders.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (context, i) {
          final order = orders[i];
          return Dismissible(
            key: Key('order-${order.id}'),
            direction: DismissDirection.horizontal,
            background: Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              alignment: AlignmentDirectional.centerStart,
              color: Colors.green.withValues(alpha: 0.8),
              child: const Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: Colors.white, size: 28),
                  SizedBox(width: AppSpacing.sm),
                  Text('تأكيد / تجهيز الطلب', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            secondaryBackground: Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              alignment: AlignmentDirectional.centerEnd,
              color: Colors.red.withValues(alpha: 0.8),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('مراجعة / إلغاء', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  SizedBox(width: AppSpacing.sm),
                  Icon(Icons.cancel_outlined, color: Colors.white, size: 28),
                ],
              ),
            ),
            confirmDismiss: (dir) async {
              if (dir == DismissDirection.startToEnd) {
                if (order.status == OrderStatus.submitted || order.status == OrderStatus.requiresManagerReview) {
                  _showValidationDialog(order, products);
                } else if (order.status == OrderStatus.confirmed) {
                  _showPreparationDialog(order);
                } else if (order.status == OrderStatus.ready) {
                  _showAssignDriverDialog(order, staff);
                }
              } else {
                _showValidationDialog(order, products);
              }
              return false;
            },
            child: InkWell(
              onTap: () => _showOrderInspectionSheet(order, products, staff),
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: _OrderCard(
                order: order,
                actionBuilder: actionBuilder,
                products: products,
                onTap: () => _showOrderInspectionSheet(order, products, staff),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMobileOrderList({
    required List<OrderEntity> orders,
    required List<ProductEntity> products,
    required List<Map<String, dynamic>> staff,
    required Widget Function(OrderEntity) actionBuilder,
  }) {
    return Column(
      children: [
        // Offline resilience indicator
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
          color: Colors.green.withValues(alpha: 0.12),
          child: const Row(
            children: [
              Icon(Icons.cloud_done_rounded, size: 14, color: Colors.green),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'المزامنة دون اتصال نشطة: يتم حفظ العمليات محلياً ومزامنتها فور توفر الشبكة.',
                  style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => _refreshOrders(),
            child: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: orders.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
              itemBuilder: (context, i) {
                final order = orders[i];
                return _OrderCard(
                  order: order,
                  actionBuilder: actionBuilder,
                  products: products,
                  onTap: () => _showOrderInspectionSheet(order, products, staff),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _sortableHeader(String title, String colKey, {required int flex}) {
    final isCurrent = _sortColumn == colKey;
    return Expanded(
      flex: flex,
      child: InkWell(
        onTap: () {
          setState(() {
            if (_sortColumn == colKey) {
              _sortAscending = !_sortAscending;
            } else {
              _sortColumn = colKey;
              _sortAscending = true;
            }
          });
        },
        child: Row(
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isCurrent ? const Color(0xFFD4AF37) : null,
              ),
            ),
            if (isCurrent)
              Icon(
                _sortAscending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                size: 12,
                color: const Color(0xFFD4AF37),
              ),
          ],
        ),
      ),
    );
  }

  String _stockReservationLabel(OrderStatus status) {
    switch (status) {
      case OrderStatus.confirmed:
      case OrderStatus.preparing:
      case OrderStatus.ready:
        return 'محجوز مؤقتاً';
      case OrderStatus.assigned:
      case OrderStatus.accepted:
      case OrderStatus.outForDelivery:
      case OrderStatus.delivered:
      case OrderStatus.settled:
        return 'مخصوم نهائياً';
      case OrderStatus.submitted:
      case OrderStatus.requiresManagerReview:
        return 'بانتظار التأكيد';
      case OrderStatus.cancelled:
      case OrderStatus.refused:
        return 'محرر من الحجز';
    }
  }

  Color _stockReservationColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.confirmed:
      case OrderStatus.preparing:
      case OrderStatus.ready:
        return Colors.blueAccent;
      case OrderStatus.assigned:
      case OrderStatus.accepted:
      case OrderStatus.outForDelivery:
      case OrderStatus.delivered:
      case OrderStatus.settled:
        return Colors.green;
      case OrderStatus.submitted:
      case OrderStatus.requiresManagerReview:
        return Colors.amber.shade800;
      case OrderStatus.cancelled:
      case OrderStatus.refused:
        return Colors.red;
    }
  }

  // ─── Shared dialog helpers ────────────────────────────────────────────────

  static Widget _dialogHeader({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required VoidCallback onClose,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.md, AppSpacing.md),
      decoration: BoxDecoration(
        color:
            isDark ? const Color(0xFF141210) : const Color(0xFFFAF7F0),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(AppRadius.lg),
          topRight: Radius.circular(AppRadius.lg),
        ),
        border: Border(
          bottom: BorderSide(
            color:
                const Color(0xFFD4AF37).withValues(alpha: 0.22),
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: AppRadius.smAll,
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: onClose,
            style: IconButton.styleFrom(
                foregroundColor:
                    theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  static Widget _dialogFooter({
    required BuildContext context,
    required bool loading,
    required String cancelLabel,
    required VoidCallback onCancel,
    String? secondaryLabel,
    IconData? secondaryIcon,
    bool secondaryDanger = false,
    VoidCallback? onSecondary,
    required String primaryLabel,
    required IconData primaryIcon,
    bool primaryEnabled = true,
    required VoidCallback onPrimary,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
      decoration: BoxDecoration(
        color:
            isDark ? const Color(0xFF141210) : const Color(0xFFFAF7F0),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(AppRadius.lg),
          bottomRight: Radius.circular(AppRadius.lg),
        ),
        border: Border(
          top: BorderSide(
            color:
                const Color(0xFFD4AF37).withValues(alpha: 0.18),
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (_, constraints) {
          final narrow = constraints.maxWidth < 400;

          final primaryBtn = GoldButton.icon(
            onPressed: (loading || !primaryEnabled) ? null : onPrimary,
            loading: loading,
            icon: primaryIcon,
            label: primaryLabel,
            width: narrow ? double.infinity : null,
          );

          final secondaryBtn =
              (secondaryLabel != null && onSecondary != null)
                  ? OutlinedButton.icon(
                      onPressed: loading ? null : onSecondary,
                      icon: Icon(
                        secondaryIcon,
                        color: secondaryDanger
                            ? theme.colorScheme.error
                            : null,
                        size: 16,
                      ),
                      label: Text(
                        secondaryLabel,
                        style: TextStyle(
                          color: secondaryDanger
                              ? theme.colorScheme.error
                              : null,
                        ),
                      ),
                    )
                  : null;

          final cancelBtn = TextButton(
            onPressed: loading ? null : onCancel,
            child: Text(cancelLabel),
          );

          if (narrow) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                primaryBtn,
                if (secondaryBtn != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  secondaryBtn,
                ],
                const SizedBox(height: AppSpacing.xs),
                cancelBtn,
              ],
            );
          }

          return Row(
            children: [
              cancelBtn,
              const Spacer(),
              if (secondaryBtn != null) ...[
                secondaryBtn,
                const SizedBox(width: AppSpacing.sm),
              ],
              primaryBtn,
            ],
          );
        },
      ),
    );
  }

  static Widget _infoRow(IconData icon, String? text,
      {Color? color, bool bold = false}) {
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color ?? Colors.grey),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    bold ? FontWeight.bold : FontWeight.normal,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  static Widget _warningBanner(String message) {
    return Container(
      padding: const EdgeInsetsDirectional.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.12),
        borderRadius: AppRadius.smAll,
        border: Border.all(
            color: Colors.orange.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Colors.orange, size: 16),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                  fontSize: 12,
                  color: Colors.orange,
                  fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _PipelineTabBar extends StatelessWidget {
  final TabController controller;
  final List<_PipelineStage> stages;
  final Map<_PipelineStage, int> counts;
  final Set<_PipelineStage> plusCounts;
  final bool isDark;

  const _PipelineTabBar({
    required this.controller,
    required this.stages,
    required this.counts,
    this.plusCounts = const {},
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF141210)
            : const Color(0xFFFAF7F0),
        border: Border(
          bottom: BorderSide(
            color: const Color(0xFFD4AF37).withValues(alpha: 0.20),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TabBar(
              controller: controller,
              isScrollable: true,
              indicatorColor: const Color(0xFFD4AF37),
              indicatorWeight: 2.5,
              tabs: stages.map((stage) {
                final count = counts[stage] ?? 0;
                final countLabel =
                    plusCounts.contains(stage) ? '$count+' : '$count';
                return Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(stage.icon, size: 16),
                      const SizedBox(width: AppSpacing.xs),
                      Text(stage.label),
                      if (count > 0) ...[
                        const SizedBox(width: AppSpacing.xs),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: const BoxDecoration(
                            gradient: AppGradients.gold,
                            borderRadius: AppRadius.pillAll,
                          ),
                          child: Text(
                            countLabel,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1400),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: AppSpacing.md),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.green.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Text(
                    'بث حي',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
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

class _OrderCard extends StatefulWidget {
  final OrderEntity order;
  final Widget Function(OrderEntity) actionBuilder;
  final List<ProductEntity>? products;
  final VoidCallback? onTap;

  const _OrderCard({
    required this.order,
    required this.actionBuilder,
    this.products,
    this.onTap,
  });

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final order = widget.order;

    return LuxuryCard(
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsetsDirectional.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: order number + state badge + total
              Row(
                children: [
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: AppGradients.gold,
                      borderRadius: AppRadius.xsAll,
                      boxShadow: [AppShadows.goldGlowSm],
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.receipt_long_rounded,
                          size: 14, color: Color(0xFF1A1400)),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'طلب #${order.orderNumber ?? order.id.substring(0, 8)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                  DzdPriceTag.lg(
                      centimes: order.totalAmountCentimes, gold: true),
                ],
              ),
              const SizedBox(height: 6),
              // State Machine Stepper (compact inline)
              OrderStateStepper(status: order.status, compact: true),
              const GoldDivider(
                  margin: EdgeInsets.symmetric(vertical: AppSpacing.sm)),

              // Customer info + meta
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.person_outline,
                                size: 13, color: Colors.grey),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                order.customerName ??
                                    order.customerSnapshot?[
                                        'customer_name'] ??
                                    order.customerSnapshot?[
                                        'store_name'] ??
                                    'زبون',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        if (order.customerPhone != null ||
                            order.customerSnapshot?['phone'] != null)
                          _miniRow(
                            Icons.phone_outlined,
                            order.customerPhone ??
                                order.customerSnapshot?['phone'],
                          ),
                        if (order.customerSnapshot?['address'] != null ||
                            order.customerSnapshot?['address_text'] !=
                                null)
                          _miniRow(
                            Icons.location_on_outlined,
                            order.customerSnapshot?['address'] ??
                                order.customerSnapshot?['address_text'],
                          ),
                        if (order.driverName != null)
                          _miniRow(
                            Icons.local_shipping_rounded,
                            'السائق: ${order.driverName}',
                            color: isDark
                                ? const Color(0xFFF3D278)
                                : const Color(0xFFC59B27),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      StatusBadge(type: _statusBadgeType(order.status)),
                      const SizedBox(height: AppSpacing.xs),
                      Text('${order.items.length} أصناف',
                          style: theme.textTheme.bodySmall),
                      Text(
                        _formatDate(order.createdAt),
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ],
              ),

              // Progressive Disclosure Toggle (Items & Stock Accordion)
              const SizedBox(height: AppSpacing.sm),
              InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                        size: 18,
                        color: const Color(0xFFD4AF37),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _expanded ? 'إخفاء تفاصيل السلع' : 'عرض تفاصيل السلع وحجز المخزون (${order.items.length})',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isDark ? const Color(0xFFF3D278) : const Color(0xFF916A08),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (_expanded) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF141210) : const Color(0xFFFBF8F0),
                    borderRadius: AppRadius.smAll,
                    border: Border.all(
                      color: const Color(0xFFD4AF37).withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ...order.items.map((it) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  '• ${it.productName} (×${it.quantity})',
                                  style: const TextStyle(fontSize: 11),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              DzdPriceTag(centimes: it.lineTotalCentimes),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 4),
                      Text(
                        'قاعدة التخصيص: مؤكدة = حجز مؤقت بالمخزون | شحن = خصم نهائي',
                        style: TextStyle(
                          fontSize: 9.5,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: AppSpacing.md),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: widget.actionBuilder(order),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Maps OrderStatus to the valid StatusBadgeType enum values
  StatusBadgeType _statusBadgeType(OrderStatus status) {
    switch (status) {
      case OrderStatus.submitted:
        return StatusBadgeType.pending;
      case OrderStatus.confirmed:
        return StatusBadgeType.processing;
      case OrderStatus.preparing:
        return StatusBadgeType.preparing;
      case OrderStatus.ready:
      case OrderStatus.assigned:
      case OrderStatus.accepted:
      case OrderStatus.outForDelivery:
        return StatusBadgeType.ready;
      case OrderStatus.delivered:
        return StatusBadgeType.delivered;
      case OrderStatus.settled:
        return StatusBadgeType.completed;
      case OrderStatus.refused:
      case OrderStatus.cancelled:
        return StatusBadgeType.cancelled;
      case OrderStatus.requiresManagerReview:
        return StatusBadgeType.draft;
      // ignore: unreachable_switch_default — future-proofs against new enum values from the DB
      default:
        return StatusBadgeType.draft;
    }
  }

  Widget _miniRow(IconData icon, String? text, {Color? color}) {
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(icon, size: 12, color: color ?? Colors.grey),
          const SizedBox(width: 3),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 11, color: color),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    return '${local.day}/${local.month} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class _StockCheckRow extends StatelessWidget {
  final OrderItemEntity item;
  final bool ok;
  final int available;

  const _StockCheckRow({
    required this.item,
    required this.ok,
    required this.available,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsetsDirectional.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: ok
            ? theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.50)
            : theme.colorScheme.errorContainer.withValues(alpha: 0.25),
        borderRadius: AppRadius.smAll,
        border: Border.all(
          color: ok
              ? theme.colorScheme.primary.withValues(alpha: 0.30)
              : theme.colorScheme.error.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Icon(
            ok
                ? Icons.check_circle_outline
                : Icons.warning_amber_rounded,
            color:
                ok ? theme.colorScheme.primary : theme.colorScheme.error,
            size: 18,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Text(
                  'مطلوب: ${item.quantity}  |  المتاح: $available',
                  style: TextStyle(
                    fontSize: 11,
                    color: ok
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.error,
                  ),
                ),
              ],
            ),
          ),
          DzdPriceTag(
            centimes: item.lineTotalCentimes,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _PicklistProgress extends StatelessWidget {
  final int checked;
  final int total;

  const _PicklistProgress({required this.checked, required this.total});

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : checked / total;
    final colors = context.appColors;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'تم التجهيز: $checked / $total',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              '${(pct * 100).round()}%',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: pct == 1.0 ? colors.success : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        ClipRRect(
          borderRadius: AppRadius.pillAll,
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 8,
            backgroundColor: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.50),
            valueColor: AlwaysStoppedAnimation(
              pct == 1.0
                  ? colors.success
                  : const Color(0xFFD4AF37),
            ),
          ),
        ),
      ],
    );
  }
}

class _PicklistItemTile extends StatelessWidget {
  final OrderItemEntity item;
  final bool isChecked;
  final ValueChanged<bool?> onChanged;

  const _PicklistItemTile({
    required this.item,
    required this.isChecked,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: isChecked
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.30)
            : theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.50),
        borderRadius: AppRadius.smAll,
        border: Border.all(
          color: isChecked
              ? theme.colorScheme.primary.withValues(alpha: 0.35)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.40),
        ),
      ),
      child: CheckboxListTile(
        value: isChecked,
        activeColor: theme.colorScheme.primary,
        shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.smAll),
        title: Text(
          item.productName,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            decoration:
                isChecked ? TextDecoration.lineThrough : null,
            color: isChecked
                ? theme.colorScheme.onSurfaceVariant
                : null,
          ),
        ),
        subtitle: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('الكمية: ${item.quantity}',
                style: theme.textTheme.bodySmall),
            DzdPriceTag(
              centimes: item.lineTotalCentimes,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ],
        ),
        onChanged: onChanged,
      ),
    );
  }
}
