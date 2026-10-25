import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:domain/domain.dart';
import 'package:core/core.dart';

/// Explicit State Machine Representation for Online Orders:
/// [Draft / Submitted] -> [Pending Review] -> [Confirmed / Reserved] -> [Processing / Packing] -> [Dispatched] -> [Delivered]
/// and [Cancelled / Refunded]
class OrderStateStepper extends StatelessWidget {
  final OrderStatus status;
  final bool compact;

  const OrderStateStepper({
    super.key,
    required this.status,
    this.compact = false,
  });

  int get _currentStepIndex {
    switch (status) {
      case OrderStatus.submitted:
        return 0;
      case OrderStatus.requiresManagerReview:
        return 1;
      case OrderStatus.confirmed:
        return 2;
      case OrderStatus.preparing:
      case OrderStatus.ready:
        return 3;
      case OrderStatus.assigned:
      case OrderStatus.accepted:
      case OrderStatus.outForDelivery:
        return 4;
      case OrderStatus.delivered:
      case OrderStatus.settled:
        return 5;
      case OrderStatus.cancelled:
      case OrderStatus.refused:
        return -1;
    }
  }

  static const _steps = [
    _StepDef(title: 'مسودة واردة', icon: Icons.inbox_outlined),
    _StepDef(title: 'مراجعة وتدقيق', icon: Icons.rule_folder_outlined),
    _StepDef(title: 'مؤكد ومحجوز', icon: Icons.lock_clock_outlined),
    _StepDef(title: 'تجهيز وتغليف', icon: Icons.inventory_2_outlined),
    _StepDef(title: 'شحن مع السائق', icon: Icons.local_shipping_outlined),
    _StepDef(title: 'تسليم وتسوية', icon: Icons.verified_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final activeIndex = _currentStepIndex;
    final isCancelled = activeIndex == -1;

    if (isCancelled) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer.withValues(alpha: 0.25),
          borderRadius: AppRadius.smAll,
          border: Border.all(color: theme.colorScheme.error.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(Icons.cancel_outlined, color: theme.colorScheme.error, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'الطلبية ملغاة / مرفوضة — تم إرجاع وحل حجز المخزون وتحديث الحساب المالي.',
                style: TextStyle(
                  color: theme.colorScheme.error,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (compact) {
      final step = _steps[activeIndex.clamp(0, _steps.length - 1)];
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFD4AF37).withValues(alpha: isDark ? 0.15 : 0.10),
          borderRadius: AppRadius.xsAll,
          border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(step.icon, size: 14, color: const Color(0xFFD4AF37)),
            const SizedBox(width: 4),
            Text(
              'المرحلة (${activeIndex + 1}/${_steps.length}): ${step.title}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFFD4AF37),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF171512) : const Color(0xFFFAF7F0),
        borderRadius: AppRadius.mdAll,
        border: Border.all(
          color: const Color(0xFFD4AF37).withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'مسار دورة حياة الطلبية وحجز المخزون',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFFD4AF37),
                ),
              ),
              Text(
                'المرحلة الحالية: ${_steps[activeIndex.clamp(0, _steps.length - 1)].title}',
                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final stepWidth = (constraints.maxWidth - (AppSpacing.xs * (_steps.length - 1))) / _steps.length;
              return Row(
                children: List.generate(_steps.length, (idx) {
                  final step = _steps[idx];
                  final isDone = idx < activeIndex;
                  final isCurrent = idx == activeIndex;

                  Color dotColor;
                  Color textColor;
                  if (isDone) {
                    dotColor = Colors.green;
                    textColor = Colors.green;
                  } else if (isCurrent) {
                    dotColor = const Color(0xFFD4AF37);
                    textColor = isDark ? const Color(0xFFF6D98D) : const Color(0xFF916A08);
                  } else {
                    dotColor = isDark ? Colors.white24 : Colors.black26;
                    textColor = theme.colorScheme.onSurfaceVariant;
                  }

                  return SizedBox(
                    width: stepWidth,
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                height: 2,
                                color: idx == 0
                                    ? Colors.transparent
                                    : (idx <= activeIndex ? Colors.green : (isDark ? Colors.white12 : Colors.black12)),
                              ),
                            ),
                            Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isCurrent
                                    ? const Color(0xFFD4AF37)
                                    : (isDone ? Colors.green.withValues(alpha: 0.2) : Colors.transparent),
                                border: Border.all(
                                  color: dotColor,
                                  width: isCurrent ? 2 : 1.5,
                                ),
                              ),
                              child: Center(
                                child: isDone
                                    ? const Icon(Icons.check, size: 12, color: Colors.green)
                                    : (isCurrent
                                        ? const Icon(Icons.circle, size: 8, color: Color(0xFF1A1400))
                                        : Text(
                                            '${idx + 1}',
                                            style: TextStyle(
                                              fontSize: 9,
                                              color: textColor,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          )),
                              ),
                            ),
                            Expanded(
                              child: Container(
                                height: 2,
                                color: idx == _steps.length - 1
                                    ? Colors.transparent
                                    : (idx < activeIndex ? Colors.green : (isDark ? Colors.white12 : Colors.black12)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          step.title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                            color: textColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  );
                }),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StepDef {
  final String title;
  final IconData icon;
  const _StepDef({required this.title, required this.icon});
}

/// Customer Ledger Synchronization Card
/// Shows atomic synchronization with customer balance sheet
class CustomerLedgerSyncCard extends StatelessWidget {
  final OrderEntity order;

  const CustomerLedgerSyncCard({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final customerName = order.customerName ??
        order.customerSnapshot?['customer_name'] ??
        order.customerSnapshot?['store_name'] ??
        'زبون مسجل';
    final customerPhone = order.customerPhone ??
        order.customerSnapshot?['phone'] ??
        'غير متوفر';
    final address = order.customerSnapshot?['address'] ??
        order.customerSnapshot?['address_text'] ??
        'توصيل قياسي';

    return LuxuryCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.account_balance_wallet_outlined, size: 16, color: Color(0xFFD4AF37)),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'مزامنة دفتر أستاذ الزبون (Customer Ledger)',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: AppRadius.pillAll,
                  border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.sync_rounded, size: 10, color: Colors.green),
                    SizedBox(width: 3),
                    Text(
                      'مربوط آلياً',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFFD4AF37).withValues(alpha: 0.15),
                child: const Icon(Icons.storefront_rounded, size: 18, color: Color(0xFFD4AF37)),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customerName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'هاتف: $customerPhone • $address',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const GoldDivider(margin: EdgeInsets.symmetric(vertical: AppSpacing.sm)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('قيمة الطلبية الحالية', style: theme.textTheme.bodySmall),
                  DzdPriceTag(centimes: order.totalAmountCentimes, gold: true),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('المدفوع / المحصل', style: theme.textTheme.bodySmall),
                  Text(
                    order.paidAmountCentimes > 0
                        ? DzdFormatter.formatCentimes(order.paidAmountCentimes)
                        : 'عند التسليم',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: order.paidAmountCentimes > 0 ? Colors.green : Colors.orange,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Stock Allocation Breakdown: Decouples physical inventory from reserved orders
class OrderStockAllocationCard extends StatelessWidget {
  final OrderEntity order;
  final List<ProductEntity> products;

  const OrderStockAllocationCard({
    super.key,
    required this.order,
    required this.products,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final isReserved = order.status != OrderStatus.submitted &&
        order.status != OrderStatus.requiresManagerReview &&
        order.status != OrderStatus.cancelled &&
        order.status != OrderStatus.refused;

    return LuxuryCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.inventory_rounded, size: 16, color: Color(0xFFD4AF37)),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'قاعدة تخصيص وحجز المخزون (Stock Allocation)',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: (isReserved ? Colors.blueAccent : Colors.amber).withValues(alpha: 0.15),
                  borderRadius: AppRadius.pillAll,
                  border: Border.all(
                    color: (isReserved ? Colors.blueAccent : Colors.amber).withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  isReserved ? 'مخزون محجوز مؤقتاً' : 'بانتظار تأكيد الحجز',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isReserved ? Colors.blueAccent : Colors.amber.shade800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'قاعدة العمل: يتم حجز المخزون مؤقتاً عند التأكيد (ينقص المتاح ويبقى الفعلي دون مساس) ويخصم نهائياً عند الشحن مع السائق.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 10.5,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: order.items.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.xs),
            itemBuilder: (context, idx) {
              final item = order.items[idx];
              final product = products.firstWhere(
                (p) => p.id == item.productId,
                orElse: () => ProductEntity(
                  id: item.productId,
                  nameAr: item.productName,
                  nameFr: '',
                  category: '',
                  unit: item.unit ?? 'قطعة',
                  packSize: 1,
                  availableQty: 0,
                  onHandQty: 0,
                  active: true,
                ),
              );

              final isShortage = product.availableQty < item.quantity;

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF141210) : const Color(0xFFF9F6F0),
                  borderRadius: AppRadius.xsAll,
                  border: Border.all(
                    color: isShortage
                        ? Colors.red.withValues(alpha: 0.35)
                        : (isDark ? Colors.white12 : Colors.black12),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isShortage ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                      size: 14,
                      color: isShortage ? Colors.red : Colors.green,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        item.productName,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      'مطلوب: ${item.quantity}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'المتاح: ${product.availableQty}',
                      style: TextStyle(
                        fontSize: 11,
                        color: isShortage ? Colors.red : Colors.green,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'الفعلي بالمستودع: ${product.onHandQty}',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Floating / Sticky Batch Actions Bar for Desktop & Tablet
class OrderBatchActionBar extends StatelessWidget {
  final int selectedCount;
  final VoidCallback onClearSelection;
  final VoidCallback? onBatchConfirm;
  final VoidCallback? onBatchPrepare;
  final VoidCallback? onBatchPrint;
  final bool isLoading;

  const OrderBatchActionBar({
    super.key,
    required this.selectedCount,
    required this.onClearSelection,
    this.onBatchConfirm,
    this.onBatchPrepare,
    this.onBatchPrint,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    if (selectedCount == 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.all(AppSpacing.md),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F1B16) : const Color(0xFFFAF2DC),
        borderRadius: AppRadius.mdAll,
        border: Border.all(
          color: const Color(0xFFD4AF37),
          width: 1.5,
        ),
        boxShadow: const [AppShadows.goldGlowSm],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: const BoxDecoration(
              gradient: AppGradients.gold,
              borderRadius: AppRadius.pillAll,
            ),
            child: Text(
              '$selectedCount محددة',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: Color(0xFF1A1400),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Text(
            'عمليات مجمعة على الطلبيات المحددة:',
            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          if (onBatchConfirm != null) ...[
            GoldButton.icon(
              icon: Icons.check_circle_rounded,
              label: 'تأكيد وحجز المخزون ($selectedCount)',
              compact: true,
              loading: isLoading,
              onPressed: isLoading ? null : onBatchConfirm,
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          if (onBatchPrepare != null) ...[
            OutlinedButton.icon(
              icon: const Icon(Icons.inventory_2_outlined, size: 16),
              label: Text('تجهيز مجمع ($selectedCount)'),
              onPressed: isLoading ? null : onBatchPrepare,
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          if (onBatchPrint != null) ...[
            IconButton(
              icon: const Icon(Icons.print_outlined),
              tooltip: 'طباعة الوصولات المحددة',
              onPressed: isLoading ? null : onBatchPrint,
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
          TextButton(
            onPressed: isLoading ? null : onClearSelection,
            child: const Text('إلغاء التحديد'),
          ),
        ],
      ),
    );
  }
}
