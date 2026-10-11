import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:domain/domain.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/customer_providers.dart';
import 'services/customer_invoice_service.dart';
import 'widgets/customer_order_tracking_view.dart';

class MyOrdersScreen extends ConsumerWidget {
  const MyOrdersScreen({super.key});

  void _showOrderDetailsDialog(BuildContext context, OrderEntity order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ListView(
            controller: scrollController,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'تفاصيل الطلب #${order.orderNumber ?? order.id.substring(0, 8)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: () => CustomerInvoiceService.printCustomerOrderInvoice(order),
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                    label: const Text('الفاتورة'),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                ],
              ),
              const Divider(),
              _buildTimelineStepper(context, order.status),
              const Divider(),
              if (order.driverName != null) ...[
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer.withAlpha(50),
                    borderRadius: AppRadius.mdAll,
                    border: Border.all(color: Theme.of(context).colorScheme.primary.withAlpha(80)),
                  ),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        child: Icon(Icons.local_shipping),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('سائق التوصيل المكلف:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            Text(order.driverName!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            if (order.driverPhone != null)
                              Text('الهاتف: ${order.driverPhone!}', style: const TextStyle(fontSize: 13)),
                          ],
                        ),
                      ),
                      if (order.driverPhone != null)
                        FilledButton.tonalIcon(
                          onPressed: () => launchUrl(Uri.parse('tel:${order.driverPhone}')),
                          icon: const Icon(Icons.call, size: 16),
                          label: const Text('اتصال'),
                        ),
                    ],
                  ),
                ),
                if (order.driverId != null &&
                    (order.status == OrderStatus.outForDelivery ||
                     order.status == OrderStatus.accepted ||
                     order.status == OrderStatus.assigned)) ...[
                  AppSpacing.gapSm,
                  CustomerOrderTrackingView(
                    driverId: order.driverId!,
                    driverName: order.driverName ?? 'السائق',
                    driverPhone: order.driverPhone,
                    destinationLat: order.deliveryLat ?? (order.deliveryAddress?['latitude'] as num?)?.toDouble(),
                    destinationLng: order.deliveryLng ?? (order.deliveryAddress?['longitude'] as num?)?.toDouble(),
                  ),
                ],
                AppSpacing.gapMd,
              ],
              const Text('السلع المطلوبة:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              AppSpacing.gapSm,
              ...order.items.map((item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text('${item.quantity}x  ${item.productName}', style: const TextStyle(fontSize: 14)),
                        ),
                        DzdPriceTag(centimes: item.lineTotalCentimes, style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  )),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('المبلغ الإجمالي:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  DzdPriceTag(centimes: order.totalAmountCentimes, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Theme.of(context).colorScheme.primary)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildTimelineStepper(BuildContext context, OrderStatus status) {
    int currentStep = 0;
    switch (status) {
      case OrderStatus.submitted:
        currentStep = 0;
        break;
      case OrderStatus.confirmed:
        currentStep = 1;
        break;
      case OrderStatus.preparing:
        currentStep = 2;
        break;
      case OrderStatus.ready:
      case OrderStatus.assigned:
      case OrderStatus.accepted:
      case OrderStatus.outForDelivery:
        currentStep = 3;
        break;
      case OrderStatus.delivered:
      case OrderStatus.settled:
        currentStep = 4;
        break;
      case OrderStatus.cancelled:
      case OrderStatus.refused:
        currentStep = -1;
        break;
    }

    final steps = [
      {'title': 'تم الإرسال', 'subtitle': 'في انتظار مراجعة مسؤول المخزون'},
      {'title': 'تم التأكيد', 'subtitle': 'تم التحقق وحجز المخزون'},
      {'title': 'قيد التجهيز', 'subtitle': 'تجهيز وتغليف السلع في المستودع'},
      {'title': 'مع السائق', 'subtitle': 'قيد التوصيل إلى عنوان المحل'},
      {'title': 'تم التسليم', 'subtitle': 'تم الاستلام والتحصيل بنجاح'},
    ];

    if (currentStep == -1) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(color: Colors.red.withAlpha(20), borderRadius: AppRadius.mdAll),
        child: const Row(
          children: [
            Icon(Icons.cancel, color: Colors.red),
            SizedBox(width: 8),
            Text('تم إلغاء أو رفض هذا الطلب', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }

    return Column(
      children: List.generate(steps.length, (idx) {
        final isDone = idx <= currentStep;
        final isCurrent = idx == currentStep;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: isDone ? Colors.green : Colors.grey.shade300,
                  child: Icon(
                    isDone ? Icons.check : Icons.circle,
                    size: 14,
                    color: isDone ? Colors.white : Colors.grey.shade600,
                  ),
                ),
                if (idx < steps.length - 1)
                  Container(
                    width: 2,
                    height: 28,
                    color: idx < currentStep ? Colors.green : Colors.grey.shade300,
                  ),
              ],
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    steps[idx]['title']!,
                    style: TextStyle(
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
                      color: isDone ? Colors.black87 : Colors.grey,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    steps[idx]['subtitle']!,
                    style: TextStyle(fontSize: 11, color: isCurrent ? Colors.green.shade800 : Colors.grey),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(customerOrdersProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.receipt_long_rounded),
            SizedBox(width: AppSpacing.sm),
            Text('طلبياتي وحالة التوصيل المباشرة'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'تحديث الطلبات',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(customerOrdersProvider),
          ),
        ],
      ),
      body: ContentConstrainedBox.dashboard(
        padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
        child: ordersAsync.when(
          data: (orders) {
            if (orders.isEmpty) {
              return AppEmptyView(
                icon: Icons.receipt_long_outlined,
                title: 'لا توجد طلبات سابقة',
                description: 'لم تقم بتسجيل أي طلبيات بعد. تصفح الكتالوج لبدء التسوق.',
                actionLabel: 'ابدأ التسوق الآن',
                onAction: () => Navigator.pop(context),
              );
            }

            return ListView.separated(
              itemCount: orders.length,
              separatorBuilder: (_, __) => AppSpacing.gapMd,
              itemBuilder: (context, index) {
                final order = orders[index];

                StatusBadgeType badgeType;
                String statusLabel;

                switch (order.status) {
                  case OrderStatus.submitted:
                    badgeType = StatusBadgeType.draft;
                    statusLabel = 'تم الإرسال - قيد المراجعة';
                    break;
                  case OrderStatus.confirmed:
                    badgeType = StatusBadgeType.pending;
                    statusLabel = 'تم التأكيد وحجز المخزون';
                    break;
                  case OrderStatus.preparing:
                    badgeType = StatusBadgeType.pending;
                    statusLabel = 'قيد التجهيز في المستودع';
                    break;
                  case OrderStatus.ready:
                  case OrderStatus.assigned:
                  case OrderStatus.accepted:
                  case OrderStatus.outForDelivery:
                    badgeType = StatusBadgeType.processing;
                    statusLabel = order.driverName != null ? 'مع السائق: ${order.driverName}' : 'قيد التوصيل';
                    break;
                  case OrderStatus.delivered:
                  case OrderStatus.settled:
                    badgeType = StatusBadgeType.completed;
                    statusLabel = 'تم التسليم بنجاح';
                    break;
                  case OrderStatus.cancelled:
                  case OrderStatus.refused:
                    badgeType = StatusBadgeType.cancelled;
                    statusLabel = 'ملغى';
                    break;
                }

                return Card(
                  child: InkWell(
                    borderRadius: AppRadius.mdAll,
                    onTap: () => _showOrderDetailsDialog(context, order),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'طلب #${order.orderNumber ?? order.id.substring(0, 8)}',
                                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              DzdPriceTag(centimes: order.totalAmountCentimes),
                            ],
                          ),
                          AppSpacing.gapSm,
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              StatusBadge(type: badgeType, customLabel: statusLabel),
                              Text('${order.items.length} منتجات', style: theme.textTheme.bodySmall),
                            ],
                          ),
                          AppSpacing.gapSm,
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'التاريخ: ${order.createdAt.toLocal().toString().split(".").first}',
                                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                              ),
                              const Row(
                                children: [
                                  Text('عرض التتبع والتفاصيل', style: TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.bold)),
                                  Icon(Icons.arrow_forward_ios, size: 12, color: Colors.blue),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
          loading: () => const AppLoadingView(message: 'جاري جلب سجل الطلبيات...'),
          error: (err, _) => AppErrorView(
            message: 'تعذر الاتصال بقاعدة البيانات لجلب الطلبيات',
            onRetry: () => ref.invalidate(customerOrdersProvider),
          ),
        ),
      ),
    );
  }
}
