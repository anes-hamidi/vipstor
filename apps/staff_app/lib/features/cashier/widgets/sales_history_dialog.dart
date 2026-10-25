import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:core/core.dart';
import 'package:domain/domain.dart';
import '../../../providers/staff_providers.dart';
import '../services/pos_thermal_printer.dart';
import 'sales_return_dialog.dart';

/// A responsive, high-fidelity screen for viewing past sales, receipts, and triggering returns.
class SalesHistoryDialog extends ConsumerStatefulWidget {
  const SalesHistoryDialog({super.key});

  /// Opens the sales history as a dedicated fullscreen screen route.
  static Future<void> show(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const SalesHistoryDialog(),
      ),
    );
  }

  @override
  ConsumerState<SalesHistoryDialog> createState() => _SalesHistoryDialogState();
}

class _SalesHistoryDialogState extends ConsumerState<SalesHistoryDialog> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  OrderEntity? _selectedOrder;
  String _filterType = 'all'; // all, cash, credit

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reprintReceipt(OrderEntity order) {
    final posItems = order.items.map((i) {
      return PosCartItem(
        id: i.id,
        productId: i.productId,
        nameAr: i.productName,
        nameFr: i.productName,
        barcode: '',
        unit: PosItemUnit.fromString(i.unit),
        quantity: i.quantity,
        baseUnitPriceCentimes: i.unitPriceCentimes,
        unitCostCentimes: i.unitCostCentimes,
        availableStock: 999,
      );
    }).toList();

    PosThermalPrinterService.printSalesReceipt(
      orderId: order.id,
      cashierName: 'أمين الصندوق',
      customer: order.customerId != null
          ? CustomerProfileEntity(
              id: order.customerId!,
              userId: '',
              name: order.customerName ?? 'زبون',
              phone: order.customerPhone ?? '',
              creditLimitCentimes: 0,
              currentDebtCentimes: 0,
            )
          : null,
      items: posItems,
      totalCentimes: order.totalAmountCentimes,
      paidCashCentimes: order.paidAmountCentimes,
      onAccountCentimes: order.dueAmountCentimes,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تم إرسال أمر طباعة الوصل #${order.orderNumber ?? order.id.substring(0, 8)} للمطبعة'),
        backgroundColor: context.appColors.success,
      ),
    );
  }

  StatusBadgeType _mapStatusToBadge(OrderStatus status) {
    switch (status) {
      case OrderStatus.submitted:
        return StatusBadgeType.pending;
      case OrderStatus.confirmed:
      case OrderStatus.preparing:
      case OrderStatus.ready:
      case OrderStatus.assigned:
      case OrderStatus.accepted:
      case OrderStatus.outForDelivery:
        return StatusBadgeType.processing;
      case OrderStatus.delivered:
      case OrderStatus.settled:
        return StatusBadgeType.completed;
      case OrderStatus.refused:
      case OrderStatus.cancelled:
        return StatusBadgeType.cancelled;
      case OrderStatus.requiresManagerReview:
        return StatusBadgeType.pending;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final colors = context.appColors;
    final role = context.roleTheme;
    final brand = role.roleBrandColor;
    final orderRepo = ref.read(orderRepositoryProvider);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: colorScheme.surface,
          appBar: AppBar(
            elevation: 0,
            scrolledUnderElevation: 2,
            backgroundColor: colorScheme.surfaceContainer,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'رجوع [Esc]',
              onPressed: () => Navigator.pop(context),
            ),
            title: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: role.badgeBackground,
                    borderRadius: AppRadius.smAll,
                    border: Border.all(color: brand.withValues(alpha: 0.30)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(Icons.history_edu_rounded,
                        size: 20, color: role.badgeText),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'سجل المبيعات والوصولات السابقة [F8]',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 17),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'أرشيف وصولات البيع والطباعة وإرجاع السلع',
                        style:
                            theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          body: FutureBuilder<List<OrderEntity>>(
            future: orderRepo.getOrders(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: AppLoadingView(message: 'جاري جلب سجل الوصولات...'),
                );
              }

              if (snapshot.hasError) {
                return Center(
                  child: AppErrorView(
                    message: 'تعذر جلب سجل المبيعات من قاعدة البيانات',
                    onRetry: () => setState(() {}),
                  ),
                );
              }

              var orders = snapshot.data ?? [];
              if (_searchQuery.trim().isNotEmpty) {
                final clean = _searchQuery.trim().toLowerCase();
                orders = orders.where((o) {
                  return o.id.toLowerCase().contains(clean) ||
                      (o.orderNumber != null &&
                          o.orderNumber.toString().contains(clean)) ||
                      (o.customerName != null &&
                          o.customerName!.toLowerCase().contains(clean));
                }).toList();
              }

              if (_filterType == 'credit') {
                orders = orders.where((o) => o.dueAmountCentimes > 0).toList();
              } else if (_filterType == 'cash') {
                orders = orders.where((o) => o.dueAmountCentimes == 0).toList();
              }

              return LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 850;

                  if (isWide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Master: Left search and orders list
                        SizedBox(
                          width: 420,
                          child: Container(
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerLow,
                              border: BorderDirectional(
                                end: BorderSide(
                                  color: colorScheme.outlineVariant
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                            ),
                            child: Column(
                              children: [
                                _buildSearchHeader(theme, colorScheme, role),
                                const Divider(height: 1),
                                Expanded(
                                  child: orders.isEmpty
                                      ? const Center(
                                          child: AppEmptyView(
                                            icon: Icons.receipt_long_outlined,
                                            title: 'لا توجد وصولات مطابقة',
                                            description:
                                                'جرب البحث برقم وصل آخر.',
                                          ),
                                        )
                                      : ListView.separated(
                                          itemCount: orders.length,
                                          separatorBuilder: (_, __) =>
                                              const Divider(height: 1),
                                          itemBuilder: (context, idx) {
                                            final o = orders[idx];
                                            final isSelected =
                                                _selectedOrder?.id == o.id;
                                            return _buildOrderListTile(
                                              o,
                                              isSelected,
                                              colors,
                                              theme,
                                              colorScheme,
                                              onTap: () {
                                                setState(() {
                                                  _selectedOrder = o;
                                                });
                                              },
                                            );
                                          },
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Detail: Right panel inspecting the selected order
                        Expanded(
                          child: _selectedOrder == null
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.receipt_long_rounded,
                                        size: 64,
                                        color: colorScheme.outlineVariant,
                                      ),
                                      AppSpacing.gapMd,
                                      Text(
                                        'اختر وصلاً من القائمة لعرض تفاصيله',
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'يمكنك إعادة طباعة الوصل الحراري أو إجراء استرجاع للمواد',
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                )
                              : _buildOrderDetailView(
                                  _selectedOrder!, theme, colorScheme, colors),
                        ),
                      ],
                    );
                  }

                  // Mobile Layout: List with bottom sheet or modal detail
                  return Column(
                    children: [
                      _buildSearchHeader(theme, colorScheme, role),
                      const Divider(height: 1),
                      Expanded(
                        child: orders.isEmpty
                            ? const Center(
                                child: AppEmptyView(
                                  icon: Icons.receipt_long_outlined,
                                  title: 'لا توجد وصولات',
                                  description: 'لم يتم العثور على أي وصل بيع.',
                                ),
                              )
                            : ListView.separated(
                                itemCount: orders.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, idx) {
                                  final o = orders[idx];
                                  return _buildOrderListTile(
                                    o,
                                    false,
                                    colors,
                                    theme,
                                    colorScheme,
                                    onTap: () => _showMobileDetailSheet(
                                        o, theme, colorScheme, colors),
                                  );
                                },
                              ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSearchHeader(
      ThemeData theme, ColorScheme colorScheme, dynamic role) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'ابحث برقم الوصل، الزبون، أو المعرّف...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: colorScheme.surfaceContainer,
              border: const OutlineInputBorder(borderRadius: AppRadius.mdAll),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('جميع الوصولات'),
                  selected: _filterType == 'all',
                  onSelected: (val) {
                    if (val) setState(() => _filterType = 'all');
                  },
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('نقدية فقط'),
                  selected: _filterType == 'cash',
                  onSelected: (val) {
                    if (val) setState(() => _filterType = 'cash');
                  },
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('على الحساب (دين)'),
                  selected: _filterType == 'credit',
                  onSelected: (val) {
                    if (val) setState(() => _filterType = 'credit');
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderListTile(
    OrderEntity o,
    bool isSelected,
    dynamic colors,
    ThemeData theme,
    ColorScheme colorScheme, {
    required VoidCallback onTap,
  }) {
    final isCredit = o.dueAmountCentimes > 0;

    return ListTile(
      selected: isSelected,
      selectedTileColor: colorScheme.primaryContainer.withValues(alpha: 0.25),
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor:
            isCredit ? colors.warningContainer : colors.successContainer,
        child: Icon(
          isCredit ? Icons.credit_card : Icons.receipt,
          color:
              isCredit ? colors.onWarningContainer : colors.onSuccessContainer,
        ),
      ),
      title: Row(
        children: [
          Text(
            'وصل #${o.orderNumber ?? o.id.substring(0, 8)}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: AppSpacing.xs),
          StatusBadge(type: _mapStatusToBadge(o.status)),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (o.customerName != null) ...[
            Text(
              'الزبون: ${o.customerName}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ],
          Text(
            '${o.createdAt.toString().substring(0, 16)} • ${o.items.length} مواد',
            style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
          ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          DzdPriceTag(
            centimes: o.totalAmountCentimes,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          if (isCredit)
            Text(
              'دين: ${DzdFormatter.formatCentimes(o.dueAmountCentimes)}',
              style: TextStyle(
                fontSize: 10,
                color: colors.warning,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOrderDetailView(OrderEntity o, ThemeData theme,
      ColorScheme colorScheme, dynamic colors) {
    final isCredit = o.dueAmountCentimes > 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Card
              LuxuryCard(
                goldAccent: true,
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'وصل رقم #${o.orderNumber ?? o.id.substring(0, 8)}',
                              style: theme.textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'معرّف النظام: ${o.id}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                        StatusBadge(type: _mapStatusToBadge(o.status)),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _infoItem('تاريخ الإنشاء',
                            o.createdAt.toString().substring(0, 16)),
                        _infoItem('الزبون', o.customerName ?? 'زبون عام (مجهول)'),
                        _infoItem('الهاتف', o.customerPhone ?? 'غير مسجل'),
                      ],
                    ),
                  ],
                ),
              ),
              AppSpacing.gapMd,
              // Financial breakdown
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: AppRadius.mdAll,
                  border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _financialStat('الإجمالي المستحق', o.totalAmountCentimes,
                        colorScheme.onSurface),
                    _financialStat('المدفوع نقدًا', o.paidAmountCentimes,
                        colors.success),
                    _financialStat('المتبقي على الحساب (دين)',
                        o.dueAmountCentimes, isCredit ? colors.warning : null),
                  ],
                ),
              ),
              AppSpacing.gapLg,
              // Items List Table
              Text(
                'قائمة المواد المضمنة بالوصل (${o.items.length}):',
                style:
                    theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              AppSpacing.gapSm,
              Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: AppRadius.mdAll,
                  border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: o.items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, idx) {
                    final it = o.items[idx];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  it.productName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  'سعر الوحدة: ${DzdFormatter.formatCentimes(it.unitPriceCentimes)}',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 1,
                            child: Text(
                              it.formattedQuantityWithUnit,
                              textAlign: TextAlign.center,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: DzdPriceTag(
                                centimes: it.lineTotalCentimes,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              AppSpacing.gapXl,
              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    icon:
                        const Icon(Icons.assignment_return_outlined, size: 18),
                    label: const Text('إرجاع مواد من هذا الوصل [F9]'),
                    onPressed: () {
                      SalesReturnDialog.show(context, initialOrderId: o.id);
                    },
                  ),
                  const SizedBox(width: AppSpacing.md),
                  GoldButton.icon(
                    icon: Icons.print_rounded,
                    label: 'إعادة طباعة الوصل الحراري [F8]',
                    onPressed: () => _reprintReceipt(o),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ],
    );
  }

  Widget _financialStat(String label, int centimes, Color? color) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11),
        ),
        const SizedBox(height: 4),
        DzdPriceTag(
          centimes: centimes,
          color: color,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
      ],
    );
  }

  void _showMobileDetailSheet(OrderEntity o, ThemeData theme,
      ColorScheme colorScheme, dynamic colors) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          expand: false,
          builder: (_, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(AppSpacing.md),
              child: _buildOrderDetailView(o, theme, colorScheme, colors),
            );
          },
        );
      },
    );
  }
}
