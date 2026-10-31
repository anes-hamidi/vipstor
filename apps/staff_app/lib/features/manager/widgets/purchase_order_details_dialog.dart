import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:core/core.dart';
import 'package:domain/domain.dart';

/// Read-only detail sheet for a purchase order and its GRN progress.
class PurchaseOrderDetailsDialog extends StatelessWidget {
  final PurchaseOrderEntity purchaseOrder;

  const PurchaseOrderDetailsDialog({
    super.key,
    required this.purchaseOrder,
  });

  static Future<void> show(
    BuildContext context,
    PurchaseOrderEntity purchaseOrder,
  ) {
    return showDialog<void>(
      context: context,
      builder: (_) => PurchaseOrderDetailsDialog(purchaseOrder: purchaseOrder),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final po = purchaseOrder;
    final progress = po.totalOrderedQuantity == 0
        ? 0.0
        : po.totalReceivedQuantity / po.totalOrderedQuantity;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.lg,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 860),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      gradient: AppGradients.gold,
                      borderRadius: AppRadius.mdAll,
                    ),
                    child: const Icon(
                      Icons.receipt_long_rounded,
                      size: 22,
                      color: Color(0xFF1A1400),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          po.poNumber,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${po.supplierName} • ${po.createdByName}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  StatusBadge(
                    type: purchaseOrderBadgeType(po.status),
                    customLabel: po.status.labelAr,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  IconButton(
                    tooltip: 'إغلاق',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LuxuryCard(
                      goldAccent: true,
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'تقدم الاستلام',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Text(
                                '${(progress * 100).toStringAsFixed(0)}%',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFB8860B),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          ClipRRect(
                            borderRadius: AppRadius.pillAll,
                            child: LinearProgressIndicator(
                              value: progress.clamp(0, 1),
                              minHeight: 8,
                              backgroundColor:
                                  theme.colorScheme.surfaceContainerHighest,
                              valueColor: const AlwaysStoppedAnimation(
                                Color(0xFFD4AF37),
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Wrap(
                            spacing: AppSpacing.md,
                            runSpacing: AppSpacing.xs,
                            children: [
                              _meta(
                                Icons.event_outlined,
                                'تاريخ الطلب: ${_date(po.orderDate)}',
                              ),
                              if (po.expectedDeliveryDate != null)
                                _meta(
                                  Icons.local_shipping_outlined,
                                  'التسليم المتوقع: ${_date(po.expectedDeliveryDate!)}',
                                ),
                              if (po.completedDate != null)
                                _meta(
                                  Icons.check_circle_outline_rounded,
                                  'اكتمل: ${_date(po.completedDate!)}',
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    AppSpacing.gapLg,
                    const SectionHeader(title: 'أصناف أمر الشراء', dense: true),
                    AppSpacing.gapSm,
                    ...po.items.map((item) => _itemTile(item, theme)),
                    if (po.notes != null && po.notes!.trim().isNotEmpty) ...[
                      AppSpacing.gapLg,
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerLow,
                          borderRadius: AppRadius.mdAll,
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.notes_rounded,
                              size: 18,
                              color: Color(0xFFB8860B),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                po.notes!,
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'الإجمالي المطلوب',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        DzdPriceTag.lg(
                          centimes: po.totalOrderedAmountCentimes,
                          gold: true,
                        ),
                      ],
                    ),
                  ),
                  if (po.totalReceivedQuantity > 0)
                    Text(
                      'المستلم: ${DzdFormatter.formatCentimes(po.totalReceivedAmountCentimes)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: context.appColors.success,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  const SizedBox(width: AppSpacing.md),
                  GoldButton(
                    label: 'إغلاق',
                    compact: true,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _itemTile(PurchaseOrderItemEntity item, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.productName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              Text(
                DzdFormatter.formatCentimes(item.lineOrderedCostCentimes),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: Color(0xFFB8860B),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: 4,
            children: [
              _meta(
                Icons.shopping_cart_outlined,
                'مطلوب: ${item.orderedQty} ${item.unit}',
              ),
              _meta(
                Icons.download_done_rounded,
                'مستلم: ${item.receivedQty} ${item.unit}',
              ),
              _meta(
                Icons.hourglass_bottom_rounded,
                'متبقي: ${item.remainingQty} ${item.unit}',
              ),
              _meta(
                Icons.payments_outlined,
                'تكلفة الوحدة: ${DzdFormatter.formatCentimes(item.unitCostCentimes)}',
              ),
              if (item.batchNumber != null)
                _meta(Icons.qr_code_2_rounded, 'الدفعة: ${item.batchNumber}'),
              if (item.expiryDate != null)
                _meta(
                  Icons.event_busy_outlined,
                  'الصلاحية: ${_date(item.expiryDate!)}',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _meta(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: const Color(0xFFB8860B)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  String _date(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}

StatusBadgeType purchaseOrderBadgeType(PurchaseOrderStatus status) {
  return switch (status) {
    PurchaseOrderStatus.draft => StatusBadgeType.draft,
    PurchaseOrderStatus.ordered => StatusBadgeType.pending,
    PurchaseOrderStatus.partiallyReceived => StatusBadgeType.processing,
    PurchaseOrderStatus.fullyReceived => StatusBadgeType.completed,
    PurchaseOrderStatus.cancelled => StatusBadgeType.cancelled,
  };
}
