import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:domain/domain.dart';
import '../../../providers/staff_providers.dart';
import '../../../router/staff_router.dart';
import '../services/pdf_invoice_service.dart';

final managerOnlineOrdersProvider = FutureProvider<List<OrderEntity>>((ref) async {
  final repo = ref.watch(orderRepositoryProvider);
  return repo.getOrders();
});

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

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    _tabCtrl.addListener(_onInnerTabChanged);
  }

  @override
  void dispose() {
    _tabCtrl.removeListener(_onInnerTabChanged);
    _tabCtrl.dispose();
    super.dispose();
  }

  void _onInnerTabChanged() {
    if (mounted) setState(() {});
  }

  void _refreshOrders() {
    ref.invalidate(managerOnlineOrdersProvider);
    ref.invalidate(liveProductsProvider);
  }

  // ─── Stage Counts ─────────────────────────────────────────────────────────

  Map<_PipelineStage, int> _stageCounts(List<OrderEntity> orders) => {
        _PipelineStage.verify:
            orders.where((o) => o.status == OrderStatus.submitted).length,
        _PipelineStage.prepare: orders
            .where((o) =>
                o.status == OrderStatus.confirmed ||
                o.status == OrderStatus.preparing)
            .length,
        _PipelineStage.dispatch: orders
            .where((o) =>
                o.status == OrderStatus.ready ||
                o.status == OrderStatus.assigned ||
                o.status == OrderStatus.accepted ||
                o.status == OrderStatus.outForDelivery)
            .length,
        _PipelineStage.history: orders
            .where((o) =>
                o.status == OrderStatus.delivered ||
                o.status == OrderStatus.settled ||
                o.status == OrderStatus.refused ||
                o.status == OrderStatus.cancelled)
            .length,
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
    final ordersAsync = ref.watch(managerOnlineOrdersProvider);
    final productsAsync = ref.watch(liveProductsProvider);
    final staffAsync = ref.watch(staffMembersProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      children: [
        // ── Pipeline Tab Bar ─────────────────────────────────────────
        ordersAsync.when(
          skipLoadingOnReload: true,
          data: (orders) => _PipelineTabBar(
            controller: _tabCtrl,
            stages: _PipelineStage.values,
            counts: _stageCounts(orders),
            isDark: isDark,
          ),
          loading: () => _PipelineTabBar(
            controller: _tabCtrl,
            stages: _PipelineStage.values,
            counts: const {},
            isDark: isDark,
          ),
          error: (_, __) => _PipelineTabBar(
            controller: _tabCtrl,
            stages: _PipelineStage.values,
            counts: const {},
            isDark: isDark,
          ),
        ),

        Container(
          height: 1,
          color: const Color(0xFFD4AF37)
              .withValues(alpha: isDark ? 0.15 : 0.10),
        ),

        // ── Tab Content ──────────────────────────────────────────────
        Expanded(
          child: ordersAsync.when(
            skipLoadingOnReload: true,
            data: (orders) {
              final submitted = orders
                  .where((o) => o.status == OrderStatus.submitted)
                  .toList();
              final confirming = orders
                  .where((o) =>
                      o.status == OrderStatus.confirmed ||
                      o.status == OrderStatus.preparing)
                  .toList();
              final ready = orders
                  .where((o) =>
                      o.status == OrderStatus.ready ||
                      o.status == OrderStatus.assigned ||
                      o.status == OrderStatus.accepted ||
                      o.status == OrderStatus.outForDelivery)
                  .toList();
              final history = orders
                  .where((o) =>
                      o.status == OrderStatus.delivered ||
                      o.status == OrderStatus.settled ||
                      o.status == OrderStatus.refused ||
                      o.status == OrderStatus.cancelled)
                  .toList();

              final products = productsAsync.value ?? [];
              final staff = staffAsync.value ?? [];

              return TabBarView(
                controller: _tabCtrl,
                children: [
                  // Stage 1: Verify
                  _buildOrderList(
                    orders: submitted,
                    emptyIcon: Icons.inbox_outlined,
                    emptyTitle: 'لا طلبيات واردة جديدة',
                    emptyDesc: 'ستظهر هنا طلبيات الزبائن الجديدة.',
                    actionBuilder: (o) => GoldButton.icon(
                      icon: Icons.verified_rounded,
                      label: 'تدقيق وتأكيد',
                      onPressed: () =>
                          _showValidationDialog(o, products),
                      compact: true,
                    ),
                  ),
                  // Stage 2: Prepare
                  _buildOrderList(
                    orders: confirming,
                    emptyIcon: Icons.inventory_2_outlined,
                    emptyTitle: 'لا طلبيات قيد التحضير',
                    emptyDesc:
                        'الطلبيات المؤكدة تنتظر التجهيز هنا.',
                    actionBuilder: (o) => OutlinedButton.icon(
                      onPressed: () => _showPreparationDialog(o),
                      icon: const Icon(Icons.inventory_2_outlined,
                          size: 16),
                      label: const Text('تجهيز السلع'),
                    ),
                  ),
                  // Stage 3: Dispatch
                  _buildOrderList(
                    orders: ready,
                    emptyIcon: Icons.local_shipping_outlined,
                    emptyTitle: 'لا طلبيات جاهزة للإرسال',
                    emptyDesc:
                        'الطلبيات الجاهزة للتوصيل ستظهر هنا.',
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
                  // Stage 4: History
                  _buildOrderList(
                    orders: history,
                    emptyIcon: Icons.history_rounded,
                    emptyTitle: 'سجل الطلبيات فارغ',
                    emptyDesc:
                        'الطلبيات المُسلَّمة والمرفوضة ستظهر هنا.',
                    actionBuilder: (o) => OutlinedButton.icon(
                      onPressed: () =>
                          PdfInvoiceService.printDeliverySlip(o),
                      icon: const Icon(Icons.print_outlined, size: 16),
                      label: const Text('طباعة الوصل'),
                    ),
                  ),
                ],
              );
            },
            loading: () => AppStates.loading(
                message: 'جاري تحميل طلبيات الزبائن...'),
            error: (err, _) => AppStates.error(
              'تعذر تحميل الطلبيات',
              onRetry: _refreshOrders,
            ),
          ),
        ),
      ],
    );
  }

  // ─── Order List ───────────────────────────────────────────────────────────

  Widget _buildOrderList({
    required List<OrderEntity> orders,
    required IconData emptyIcon,
    required String emptyTitle,
    required String emptyDesc,
    required Widget Function(OrderEntity) actionBuilder,
  }) {
    if (orders.isEmpty) {
      return AppStates.empty(
          icon: emptyIcon, title: emptyTitle, description: emptyDesc);
    }
    return RefreshIndicator(
      onRefresh: () async => _refreshOrders(),
      child: ListView.separated(
        padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
        itemCount: orders.length,
        separatorBuilder: (_, __) =>
            const SizedBox(height: AppSpacing.md),
        itemBuilder: (context, i) =>
            _OrderCard(order: orders[i], actionBuilder: actionBuilder),
      ),
    );
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
  final bool isDark;

  const _PipelineTabBar({
    required this.controller,
    required this.stages,
    required this.counts,
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
      child: TabBar(
        controller: controller,
        isScrollable: true,
        indicatorColor: const Color(0xFFD4AF37),
        indicatorWeight: 2.5,
        tabs: stages.map((stage) {
          final count = counts[stage] ?? 0;
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
                      '$count',
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
    );
  }
}

class _OrderCard extends StatelessWidget {
  final OrderEntity order;
  final Widget Function(OrderEntity) actionBuilder;

  const _OrderCard({required this.order, required this.actionBuilder});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return LuxuryCard(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: order number + total
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
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: actionBuilder(order),
            ),
          ],
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
