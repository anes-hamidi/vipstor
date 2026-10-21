import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:domain/domain.dart';
import '../../../providers/staff_providers.dart';
import '../services/pos_thermal_printer.dart';
import 'sales_return_dialog.dart';

class SalesHistoryDialog extends ConsumerStatefulWidget {
  const SalesHistoryDialog({super.key});

  @override
  ConsumerState<SalesHistoryDialog> createState() => _SalesHistoryDialogState();
}

class _SalesHistoryDialogState extends ConsumerState<SalesHistoryDialog> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

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
    final orderRepo = ref.read(orderRepositoryProvider);

    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.history_edu_rounded, size: 28),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        'سجل المبيعات والوصولات السابقة [F8]',
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'ابحث برقم الوصل أو معرّف الطلب...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
              AppSpacing.gapMd,
              Expanded(
                child: FutureBuilder<List<OrderEntity>>(
                  future: orderRepo.getOrders(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const AppLoadingView(message: 'جاري جلب سجل الوصولات...');
                    }

                    if (snapshot.hasError) {
                      return AppErrorView(
                        message: 'تعذر جلب سجل المبيعات من قاعدة البيانات',
                        onRetry: () => setState(() {}),
                      );
                    }

                    var orders = snapshot.data ?? [];
                    if (_searchQuery.trim().isNotEmpty) {
                      final clean = _searchQuery.trim().toLowerCase();
                      orders = orders.where((o) {
                        return o.id.toLowerCase().contains(clean) ||
                            (o.orderNumber != null && o.orderNumber.toString().contains(clean)) ||
                            (o.customerName != null && o.customerName!.toLowerCase().contains(clean));
                      }).toList();
                    }

                    if (orders.isEmpty) {
                      return const AppEmptyView(
                        icon: Icons.receipt_long_outlined,
                        title: 'لا توجد وصولات سابقة',
                        description: 'لم يتم العثور على أي وصل بيع مطابق.',
                      );
                    }

                    return ListView.separated(
                      itemCount: orders.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, idx) {
                        final o = orders[idx];
                        final isCredit = o.dueAmountCentimes > 0;

                        return ExpansionTile(
                          leading: CircleAvatar(
                            backgroundColor: isCredit ? context.appColors.warningContainer : context.appColors.successContainer,
                            child: Icon(
                              isCredit ? Icons.credit_card : Icons.receipt,
                              color: isCredit ? context.appColors.onWarningContainer : context.appColors.onSuccessContainer,
                            ),
                          ),
                          title: Row(
                            children: [
                              Text(
                                'وصل #${o.orderNumber ?? o.id.substring(0, 8)}',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              StatusBadge(type: _mapStatusToBadge(o.status)),
                              if (isCredit) ...[
                                const SizedBox(width: AppSpacing.xs),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: context.appColors.warningContainer,
                                    borderRadius: AppRadius.smAll,
                                  ),
                                  child: const Text('على الحساب', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Text(
                            'التاريخ: ${o.createdAt.toString().substring(0, 16)} | ${o.items.length} منتجات',
                            style: theme.textTheme.bodySmall,
                          ),
                          trailing: DzdPriceTag(
                            centimes: o.totalAmountCentimes,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  ...o.items.map((it) => Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 2),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text('${it.formattedQuantityWithUnit} x ${it.productName}'),
                                            DzdPriceTag(centimes: it.lineTotalCentimes),
                                          ],
                                        ),
                                      )),
                                  const Divider(),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      OutlinedButton.icon(
                                        icon: const Icon(Icons.assignment_return_outlined, size: 16),
                                        label: const Text('إرجاع مواد من هذا الوصل'),
                                        onPressed: () {
                                          Navigator.pop(context);
                                          showDialog(
                                            context: context,
                                            builder: (_) => SalesReturnDialog(initialOrderId: o.id),
                                          );
                                        },
                                      ),
                                      const SizedBox(width: AppSpacing.md),
                                      FilledButton.icon(
                                        icon: const Icon(Icons.print, size: 16),
                                        label: const Text('إعادة طباعة الوصل الحراري'),
                                        onPressed: () => _reprintReceipt(o),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
