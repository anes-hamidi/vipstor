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

class OnlineOrdersPipelineView extends ConsumerStatefulWidget {
  const OnlineOrdersPipelineView({super.key});

  @override
  ConsumerState<OnlineOrdersPipelineView> createState() => _OnlineOrdersPipelineViewState();
}

class _OnlineOrdersPipelineViewState extends ConsumerState<OnlineOrdersPipelineView> with SingleTickerProviderStateMixin {
  late TabController _pipelineTabController;
  bool _isActionLoading = false;

  @override
  void initState() {
    super.initState();
    _pipelineTabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _pipelineTabController.dispose();
    super.dispose();
  }

  void _refreshOrders() {
    ref.invalidate(managerOnlineOrdersProvider);
    ref.invalidate(liveProductsProvider);
  }

  void _showValidationDialog(OrderEntity order, List<ProductEntity> products) {
    final theme = Theme.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final successColor = context.appColors.success;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          bool allInStock = true;
          final stockEvaluations = order.items.map((item) {
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
            final hasEnough = product.availableQty >= item.quantity;
            if (!hasEnough) allInStock = false;
            return {
              'item': item,
              'product': product,
              'hasEnough': hasEnough,
              'available': product.availableQty,
            };
          }).toList();

          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.verified_outlined, color: Colors.blue),
                const SizedBox(width: AppSpacing.sm),
                Text('التحقق من الطلبية رقم #${order.orderNumber ?? order.id.substring(0, 8)}'),
              ],
            ),
            content: SingleChildScrollView(
              child: ContentConstrainedBox.form(
                maxWidth: 550,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      color: theme.colorScheme.surfaceContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'بيانات الزبون وعنوان التوصيل:',
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const Divider(height: 12),
                            Text('الاسم / المحل: ${order.customerName ?? order.customerSnapshot?['customer_name'] ?? order.customerSnapshot?['store_name'] ?? "زبون"}',
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                            if (order.customerPhone != null || order.customerSnapshot?['phone'] != null)
                              Text('رقم الهاتف: ${order.customerPhone ?? order.customerSnapshot?['phone']}'),
                            if (order.customerSnapshot?['address'] != null || order.customerSnapshot?['address_text'] != null)
                              Text('العنوان: ${order.customerSnapshot?['address'] ?? order.customerSnapshot?['address_text']}'),
                            if (order.customerSnapshot?['latitude'] != null)
                              Row(
                                children: [
                                  const Icon(Icons.gps_fixed, size: 14, color: Colors.green),
                                  const SizedBox(width: 4),
                                  Text(
                                    'GPS: (${order.customerSnapshot!['latitude']}, ${order.customerSnapshot!['longitude']})',
                                    style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                    AppSpacing.gapMd,
                    Text('السلع المطلوبة وتدقيق المخزون المتاح:', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                    AppSpacing.gapSm,
                    ...stockEvaluations.map((eval) {
                      final item = eval['item'] as OrderItemEntity;
                      final hasEnough = eval['hasEnough'] as bool;
                      final available = eval['available'] as int;

                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: hasEnough ? Colors.green.withAlpha(20) : Colors.red.withAlpha(25),
                          borderRadius: AppRadius.smAll,
                          border: Border.all(color: hasEnough ? Colors.green.withAlpha(80) : Colors.red.withAlpha(100)),
                        ),
                        child: Row(
                          children: [
                            Icon(hasEnough ? Icons.check_circle : Icons.warning_amber_rounded,
                                color: hasEnough ? Colors.green : Colors.red, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.productName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  Text('مطلوب: ${item.quantity} | المتاح بالمستودع: $available',
                                      style: TextStyle(fontSize: 11, color: hasEnough ? Colors.black87 : Colors.red.shade900)),
                                ],
                              ),
                            ),
                            DzdPriceTag(centimes: item.lineTotalCentimes, style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      );
                    }),
                    AppSpacing.gapMd,
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('المبلغ الإجمالي:', style: TextStyle(fontWeight: FontWeight.bold)),
                        DzdPriceTag(centimes: order.totalAmountCentimes, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
                      ],
                    ),
                    if (!allInStock) ...[
                      AppSpacing.gapSm,
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.orange.withAlpha(30), borderRadius: AppRadius.smAll),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.orange, size: 18),
                            SizedBox(width: 6),
                            Expanded(
                              child: Text('تنبيه: بعض السلع تتجاوز المخزون الفعلي الحالي.', style: TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إغلاق'),
              ),
              OutlinedButton.icon(
                onPressed: _isActionLoading
                    ? null
                    : () async {
                        Navigator.pop(ctx);
                        setState(() => _isActionLoading = true);
                        try {
                          final repo = ref.read(orderRepositoryProvider);
                          await repo.updateOrderStatus(orderId: order.id, status: OrderStatus.refused, notes: 'رفض من طرف مسؤول المخزون');
                          _refreshOrders();
                          if (mounted) {
                            messenger.showSnackBar(
                              const SnackBar(content: Text('تم رفض الطلبية وتحديث حالتها.')),
                            );
                          }
                        } finally {
                          if (mounted) setState(() => _isActionLoading = false);
                        }
                      },
                icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                label: const Text('رفض الطلب', style: TextStyle(color: Colors.red)),
              ),
              FilledButton.icon(
                onPressed: _isActionLoading
                    ? null
                    : () async {
                        Navigator.pop(ctx);
                        setState(() => _isActionLoading = true);
                        try {
                          final repo = ref.read(orderRepositoryProvider);
                          final auth = ref.read(authStateProvider);
                          await repo.confirmOrder(orderId: order.id, cashierId: auth?.id ?? '11111111-1111-1111-1111-111111111111');
                          _refreshOrders();
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: const Text('تم تأكيد الطلبية وحجز المخزون بنجاح! انتقلت لمرحلة التحضير والتجهيز.'),
                                backgroundColor: successColor,
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(content: Text('فشل تأكيد الطلبية: $e'), backgroundColor: Colors.red),
                            );
                          }
                        } finally {
                          if (mounted) setState(() => _isActionLoading = false);
                        }
                      },
                icon: const Icon(Icons.check_circle),
                label: const Text('تأكيد الطلبية وحجز المخزون'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showPreparationDialog(OrderEntity order) {
    final messenger = ScaffoldMessenger.of(context);
    final successColor = context.appColors.success;
    final checkedItems = <String, bool>{for (final it in order.items) it.id: false};

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          final allChecked = checkedItems.values.every((val) => val == true);

          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.inventory_2_outlined, color: Colors.amber),
                const SizedBox(width: AppSpacing.sm),
                Text('قائمة تحضير وتجهيز السلع #${order.orderNumber ?? order.id.substring(0, 8)}'),
              ],
            ),
            content: SingleChildScrollView(
              child: ContentConstrainedBox.form(
                maxWidth: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('قم بالتأشير على كل عنصر أثناء جمعه وتغليفه في كرتونة الطلب:'),
                    AppSpacing.gapMd,
                    ...order.items.map((item) {
                      final isChecked = checkedItems[item.id] ?? false;
                      return CheckboxListTile(
                        value: isChecked,
                        activeColor: Colors.green,
                        title: Text(item.productName, style: TextStyle(fontWeight: FontWeight.bold, decoration: isChecked ? TextDecoration.lineThrough : null)),
                        subtitle: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('الكمية: ${item.quantity} وحدة'),
                            DzdPriceTag(centimes: item.lineTotalCentimes, style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        onChanged: (val) {
                          setDialogState(() {
                            checkedItems[item.id] = val ?? false;
                          });
                        },
                      );
                    }),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
              FilledButton.icon(
                onPressed: _isActionLoading
                    ? null
                    : () async {
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
                            messenger.showSnackBar(
                              SnackBar(
                                content: const Text('تم تسجيل تجهيز وتغليف الطلبية! أصبحت جاهزة لتعيين السائق.'),
                                backgroundColor: successColor,
                              ),
                            );
                          }
                        } finally {
                          if (mounted) setState(() => _isActionLoading = false);
                        }
                      },
                icon: const Icon(Icons.done_all),
                label: Text(allChecked ? 'اكتمال التجهيز - جاهز للتسليم' : 'حفظ كجاهز للتسليم'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAssignDriverDialog(OrderEntity order, List<Map<String, dynamic>> staffMembers) {
    final messenger = ScaffoldMessenger.of(context);
    final successColor = context.appColors.success;
    final theme = Theme.of(context);
    final drivers = staffMembers.where((s) => s['role'] == 'driver').toList();
    String? selectedDriverId = drivers.isNotEmpty ? drivers.first['id'] as String : null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.local_shipping, color: Colors.blue),
                const SizedBox(width: AppSpacing.sm),
                Text('تعيين سائق التوصيل للطلب #${order.orderNumber ?? order.id.substring(0, 8)}'),
              ],
            ),
            content: SingleChildScrollView(
              child: ContentConstrainedBox.form(
                maxWidth: 450,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainer,
                        borderRadius: AppRadius.mdAll,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('الزبون: ${order.customerName ?? order.customerSnapshot?['customer_name'] ?? "زبون"}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text('الهاتف: ${order.customerPhone ?? order.customerSnapshot?['phone'] ?? "غير محدد"}'),
                          Text('العنوان: ${order.customerSnapshot?['address'] ?? order.customerSnapshot?['address_text'] ?? "غير محدد"}'),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('المبلغ المطلوب تحصيله:'),
                              DzdPriceTag(centimes: order.totalAmountCentimes, style: const TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    AppSpacing.gapLg,
                    if (drivers.isEmpty)
                      const Text('لا يوجد سائقون مسجلون حاليًا في قائمة الموظفين. يرجى إضافة سائق من لوحة المشرف.')
                    else
                      DropdownButtonFormField<String>(
                        initialValue: selectedDriverId,
                        decoration: const InputDecoration(
                          labelText: 'اختر سائق التوصيل *',
                          prefixIcon: Icon(Icons.person_pin_circle_outlined),
                        ),
                        items: drivers.map((d) {
                          return DropdownMenuItem<String>(
                            value: d['id'] as String,
                            child: Text('${d['name']} (${d['phone'] ?? ""})'),
                          );
                        }).toList(),
                        onChanged: (val) => setDialogState(() => selectedDriverId = val),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
              FilledButton.icon(
                onPressed: selectedDriverId == null || _isActionLoading
                    ? null
                    : () async {
                        Navigator.pop(ctx);
                        setState(() => _isActionLoading = true);
                        try {
                          final selectedDriver = drivers.firstWhere((d) => d['id'] == selectedDriverId);
                          final repo = ref.read(orderRepositoryProvider);
                          await repo.assignOrderToDriver(
                            orderId: order.id,
                            driverId: selectedDriverId!,
                            driverName: selectedDriver['name'] as String,
                            driverPhone: selectedDriver['phone'] as String?,
                          );
                          _refreshOrders();
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('تم تعيين الطلبية للسائق "${selectedDriver['name']}" بنجاح!'),
                                backgroundColor: successColor,
                              ),
                            );
                          }
                        } finally {
                          if (mounted) setState(() => _isActionLoading = false);
                        }
                      },
                icon: const Icon(Icons.send_rounded),
                label: const Text('تعيين وإرسال للسائق'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _printDeliverySlip(OrderEntity order) async {
    await PdfInvoiceService.printDeliverySlip(order);
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(managerOnlineOrdersProvider);
    final productsAsync = ref.watch(liveProductsProvider);
    final staffAsync = ref.watch(staffMembersProvider);

    return Column(
      children: [
        TabBar(
          controller: _pipelineTabController,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.inbox), text: '1. التحقق وتأكيد الطلبيات (Validation)'),
            Tab(icon: Icon(Icons.inventory_2), text: '2. تحضير وتغليف السلع (Preparation)'),
            Tab(icon: Icon(Icons.local_shipping), text: '3. تعيين السائق والتوزيع (Dispatch)'),
            Tab(icon: Icon(Icons.history), text: '4. سجل كافة الطلبيات (History)'),
          ],
        ),
        Expanded(
          child: ordersAsync.when(
            data: (orders) {
              final submittedOrders = orders.where((o) => o.status == OrderStatus.submitted).toList();
              final confirmedOrders = orders.where((o) => o.status == OrderStatus.confirmed || o.status == OrderStatus.preparing).toList();
              final readyOrders = orders.where((o) => o.status == OrderStatus.ready || o.status == OrderStatus.assigned || o.status == OrderStatus.accepted || o.status == OrderStatus.outForDelivery).toList();
              final historyOrders = orders.where((o) => o.status == OrderStatus.delivered || o.status == OrderStatus.settled || o.status == OrderStatus.refused || o.status == OrderStatus.cancelled).toList();

              final products = productsAsync.value ?? [];
              final staff = staffAsync.value ?? [];

              return TabBarView(
                controller: _pipelineTabController,
                children: [
                  _buildOrdersList(
                    orders: submittedOrders,
                    emptyMessage: 'لا توجد طلبيات جديدة واردة في انتظار التحقق.',
                    actionBuilder: (order) => FilledButton.icon(
                      onPressed: () => _showValidationDialog(order, products),
                      icon: const Icon(Icons.verified),
                      label: const Text('تدقيق وتأكيد الطلبية'),
                    ),
                  ),
                  _buildOrdersList(
                    orders: confirmedOrders,
                    emptyMessage: 'لا توجد طلبيات قيد التحضير والتجهيز حالياً.',
                    actionBuilder: (order) => FilledButton.tonalIcon(
                      onPressed: () => _showPreparationDialog(order),
                      icon: const Icon(Icons.inventory_2),
                      label: const Text('تجهيز السلع في المستودع'),
                    ),
                  ),
                  _buildOrdersList(
                    orders: readyOrders,
                    emptyMessage: 'لا توجد طلبيات جاهزة في انتظار تعيين السائق أو التوزيع.',
                    actionBuilder: (order) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton.outlined(
                          tooltip: 'طباعة وصل التسليم (Bon de Livraison)',
                          onPressed: () => _printDeliverySlip(order),
                          icon: const Icon(Icons.print),
                        ),
                        const SizedBox(width: 8),
                        if (order.status == OrderStatus.ready || order.driverId == null)
                          FilledButton.icon(
                            onPressed: () => _showAssignDriverDialog(order, staff),
                            icon: const Icon(Icons.person_pin_circle),
                            label: const Text('تعيين سائق التوصيل'),
                          )
                        else
                          OutlinedButton.icon(
                            onPressed: () => _showAssignDriverDialog(order, staff),
                            icon: const Icon(Icons.sync_alt),
                            label: Text('مع السائق: ${order.driverName ?? "تعديل"}'),
                          ),
                      ],
                    ),
                  ),
                  _buildOrdersList(
                    orders: historyOrders,
                    emptyMessage: 'سجل الطلبيات فارغ.',
                    actionBuilder: (order) => OutlinedButton.icon(
                      onPressed: () => _printDeliverySlip(order),
                      icon: const Icon(Icons.print),
                      label: const Text('طباعة الوصل'),
                    ),
                  ),
                ],
              );
            },
            loading: () => const AppLoadingView(message: 'جاري تحميل طلبيات الزبائن...'),
            error: (err, _) => AppErrorView(
              message: 'تعذر تحميل طلبيات الزبائن',
              onRetry: _refreshOrders,
            ),
          ),
        ),
      ],
    );
  }
              
  

  Widget _buildOrdersList({
    required List<OrderEntity> orders,
    required String emptyMessage,
    required Widget Function(OrderEntity order) actionBuilder,
  }) {
    if (orders.isEmpty) {
      return AppEmptyView(
        icon: Icons.check_circle_outline,
        title: 'كل شيء محدث!',
        description: emptyMessage,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: orders.length,
      separatorBuilder: (_, __) => AppSpacing.gapMd,
      itemBuilder: (context, index) {
        final order = orders[index];
        final theme = Theme.of(context);

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.receipt_long, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'طلب #${order.orderNumber ?? order.id.substring(0, 8)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ],
                    ),
                    DzdPriceTag(
                      centimes: order.totalAmountCentimes,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                    ),
                  ],
                ),
                const Divider(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'الزبون: ${order.customerName ?? order.customerSnapshot?['customer_name'] ?? order.customerSnapshot?['store_name'] ?? "زبون"}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          if (order.customerPhone != null || order.customerSnapshot?['phone'] != null)
                            Text('الهاتف: ${order.customerPhone ?? order.customerSnapshot?['phone']}', style: theme.textTheme.bodySmall),
                          if (order.customerSnapshot?['address'] != null || order.customerSnapshot?['address_text'] != null)
                            Text('العنوان: ${order.customerSnapshot?['address'] ?? order.customerSnapshot?['address_text']}', style: theme.textTheme.bodySmall),
                          if (order.driverName != null)
                            Text('السائق المعين: ${order.driverName}', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade800, fontSize: 13)),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('${order.items.length} أصناف في الطلب', style: theme.textTheme.bodySmall),
                          Text(
                            'التاريخ: ${order.createdAt.toLocal().toString().split(".").first}',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                AppSpacing.gapMd,
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: actionBuilder(order),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
