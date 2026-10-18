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

  static ({StatusBadgeType badge, String label}) _statusInfo(OrderEntity order) {
    return switch (order.status) {
      OrderStatus.submitted => (
          badge: StatusBadgeType.draft,
          label: order.notes?.contains('محفوظ محلياً') == true
              ? 'في انتظار الاتصال'
              : 'تم الإرسال — قيد المراجعة',
        ),
      OrderStatus.confirmed =>
        (badge: StatusBadgeType.pending, label: 'تم التأكيد وحجز المخزون'),
      OrderStatus.preparing =>
        (badge: StatusBadgeType.preparing, label: 'قيد التجهيز في المستودع'),
      OrderStatus.ready =>
        (badge: StatusBadgeType.ready, label: 'جاهز للتسليم'),
      OrderStatus.assigned ||
      OrderStatus.accepted ||
      OrderStatus.outForDelivery =>
        (
          badge: StatusBadgeType.processing,
          label: order.driverName != null
              ? 'مع السائق: ${order.driverName}'
              : 'قيد التوصيل',
        ),
      OrderStatus.delivered ||
      OrderStatus.settled =>
        (badge: StatusBadgeType.delivered, label: 'تم التسليم بنجاح'),
      OrderStatus.cancelled ||
      OrderStatus.refused =>
        (badge: StatusBadgeType.cancelled, label: 'ملغى'),
    };
  }

  static void _showDetails(BuildContext context, OrderEntity order) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1A1814) : const Color(0xFFFFFDF8),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.topOnly(AppRadius.xxl),
        side: BorderSide(
          color: const Color(0xFFD4AF37).withValues(alpha: isDark ? 0.25 : 0.18),
          width: 1,
        ),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.82,
        minChildSize: 0.50,
        maxChildSize: 0.96,
        expand: false,
        builder: (_, sc) => _OrderDetailSheet(
          order: order,
          scrollController: sc,
          isDark: isDark,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(customerOrdersProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: AppGradients.gold,
                borderRadius: AppRadius.smAll,
                boxShadow: [AppShadows.goldGlowSm],
              ),
              child: Padding(
                padding: EdgeInsets.all(5),
                child: Icon(Icons.receipt_long_rounded,
                    size: 16, color: Color(0xFF1A1400)),
              ),
            ),
            SizedBox(width: AppSpacing.sm),
            Text('طلبياتي'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(customerOrdersProvider),
          ),
        ],
      ),
      body: ContentConstrainedBox.dashboard(
        padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
        child: ordersAsync.when(
          loading: () => ListView.separated(
            itemCount: 4,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (_, __) => AppStates.skeleton(
                height: 110, borderRadius: AppRadius.lgAll),
          ),
          error: (err, _) => AppStates.error(
            'تعذر جلب الطلبيات. ${err.toString().replaceFirst('Exception: ', '')}',
            onRetry: () => ref.invalidate(customerOrdersProvider),
          ),
          data: (orders) {
            if (orders.isEmpty) {
              return AppStates.empty(
                icon: Icons.receipt_long_outlined,
                title: 'لا توجد طلبات سابقة',
                description:
                    'لم تقم بتسجيل أي طلبيات بعد. تصفح الكتالوج لبدء التسوق.',
                actionLabel: 'ابدأ التسوق',
                onAction: () => Navigator.pop(context),
              );
            }
            return ListView.separated(
              itemCount: orders.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.md),
              itemBuilder: (_, i) {
                final order = orders[i];
                final info = _statusInfo(order);
                return _OrderCard(
                  order: order,
                  badge: info.badge,
                  statusLabel: info.label,
                  isDark: isDark,
                  onTap: () => _showDetails(context, order),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

// ── Order Card ────────────────────────────────────────────────────────────────

class _OrderCard extends StatelessWidget {
  final OrderEntity order;
  final StatusBadgeType badge;
  final String statusLabel;
  final bool isDark;
  final VoidCallback onTap;

  const _OrderCard({
    required this.order,
    required this.badge,
    required this.statusLabel,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDelivered = badge == StatusBadgeType.delivered;

    return LuxuryCard(
      goldAccent: isDelivered,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  order.orderNumber != null
                      ? 'طلب #${order.orderNumber}'
                      : 'طلب #${order.id.length > 8 ? order.id.substring(0, 8) : order.id}',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                DzdPriceTag(centimes: order.totalAmountCentimes, gold: isDelivered),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                StatusBadge(type: badge, customLabel: statusLabel, compact: true),
                Text('${order.items.length} منتجات',
                    style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _fmt(order.createdAt),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                Row(
                  children: [
                    Text(
                      'التفاصيل والتتبع',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? const Color(0xFFF3D278)
                            : const Color(0xFFC59B27),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.arrow_forward_ios_rounded,
                        size: 10,
                        color: isDark
                            ? const Color(0xFFF3D278)
                            : const Color(0xFFC59B27)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime dt) {
    final l = dt.toLocal();
    return '${l.year}/${l.month.toString().padLeft(2, '0')}/${l.day.toString().padLeft(2, '0')}  '
        '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }
}

// ── Order Detail Sheet ────────────────────────────────────────────────────────

class _OrderDetailSheet extends StatelessWidget {
  final OrderEntity order;
  final ScrollController scrollController;
  final bool isDark;

  const _OrderDetailSheet({
    required this.order,
    required this.scrollController,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ListView(
      controller: scrollController,
      padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
      children: [
        // Header
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    order.orderNumber != null
                        ? 'طلب #${order.orderNumber}'
                        : 'طلب #${order.id.substring(0, 8)}',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    _fmt(order.createdAt),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                side: const BorderSide(color: Color(0xFFD4AF37), width: 1),
              ),
              onPressed: () =>
                  CustomerInvoiceService.printCustomerOrderInvoice(order),
              icon: const Icon(Icons.picture_as_pdf_outlined,
                  size: 15, color: Color(0xFFD4AF37)),
              label: const Text('الفاتورة',
                  style: TextStyle(
                      color: Color(0xFFD4AF37), fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: AppSpacing.xs),
            IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context)),
          ],
        ),
        const GoldDivider(margin: EdgeInsets.symmetric(vertical: AppSpacing.md)),

        // Timeline
        const SectionHeader(title: 'تتبع حالة الطلب'),
        const SizedBox(height: AppSpacing.sm),
        _GoldTimeline(status: order.status),
        const GoldDivider(margin: EdgeInsets.symmetric(vertical: AppSpacing.md)),

        // Driver
        if (order.driverName != null) ...[
          const SectionHeader(title: 'سائق التوصيل'),
          const SizedBox(height: AppSpacing.sm),
          _DriverCard(order: order, isDark: isDark),
          const SizedBox(height: AppSpacing.md),
          if (order.driverId != null &&
              (order.status == OrderStatus.outForDelivery ||
                  order.status == OrderStatus.accepted ||
                  order.status == OrderStatus.assigned)) ...[
            CustomerOrderTrackingView(
              driverId: order.driverId!,
              driverName: order.driverName ?? 'السائق',
              driverPhone: order.driverPhone,
              destinationLat: order.deliveryLat ??
                  (order.deliveryAddress?['latitude'] as num?)?.toDouble(),
              destinationLng: order.deliveryLng ??
                  (order.deliveryAddress?['longitude'] as num?)?.toDouble(),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          const GoldDivider(
              margin: EdgeInsets.symmetric(vertical: AppSpacing.md)),
        ],

        // Items
        SectionHeader(title: 'السلع المطلوبة (${order.items.length})'),
        const SizedBox(height: AppSpacing.sm),
        ...order.items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: LuxuryCard(
                padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        gradient: isDark
                            ? null
                            : AppGradients.goldSubtleLight,
                        color: isDark ? const Color(0xFF2A2518) : null,
                        borderRadius: AppRadius.smAll,
                        border: Border.all(
                          color: const Color(0xFFD4AF37).withValues(alpha: 0.20),
                          width: 1,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '${item.quantity}×',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? const Color(0xFFF3D278)
                                : const Color(0xFF9A7319),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(item.productName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                    DzdPriceTag(
                        centimes: item.lineTotalCentimes,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            )),

        const GoldDivider(
            margin: EdgeInsets.only(
                top: AppSpacing.sm, bottom: AppSpacing.md)),

        // Total
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('المبلغ الإجمالي',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            DzdPriceTag.hero(centimes: order.totalAmountCentimes, gold: true),
          ],
        ),
        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }

  String _fmt(DateTime dt) {
    final l = dt.toLocal();
    return '${l.year}/${l.month.toString().padLeft(2, '0')}/${l.day.toString().padLeft(2, '0')}  '
        '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }
}

// ── Gold Timeline ─────────────────────────────────────────────────────────────

class _GoldTimeline extends StatelessWidget {
  final OrderStatus status;
  const _GoldTimeline({required this.status});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final currentStep = switch (status) {
      OrderStatus.submitted => 0,
      OrderStatus.confirmed => 1,
      OrderStatus.preparing => 2,
      OrderStatus.ready ||
      OrderStatus.assigned ||
      OrderStatus.accepted ||
      OrderStatus.outForDelivery =>
        3,
      OrderStatus.delivered || OrderStatus.settled => 4,
      _ => -1,
    };

    if (currentStep == -1) {
      return LuxuryCard(
        padding: const EdgeInsetsDirectional.all(AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: AppRadius.smAll),
              child: Icon(Icons.cancel_outlined,
                  color: theme.colorScheme.error, size: 20),
            ),
            const SizedBox(width: AppSpacing.md),
            Text('تم إلغاء أو رفض هذا الطلب',
                style: TextStyle(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }

    const steps = [
      (icon: Icons.send_rounded, title: 'تم الإرسال', sub: 'قيد مراجعة المخزون'),
      (icon: Icons.verified_outlined, title: 'تم التأكيد', sub: 'تم حجز المخزون'),
      (icon: Icons.inventory_2_outlined, title: 'قيد التجهيز', sub: 'تغليف السلع'),
      (icon: Icons.local_shipping_outlined, title: 'مع السائق', sub: 'قيد التوصيل'),
      (icon: Icons.check_circle_outline, title: 'تم التسليم', sub: 'تم الاستلام'),
    ];

    return Column(
      children: List.generate(steps.length, (idx) {
        final isDone = idx <= currentStep;
        final isCurrent = idx == currentStep;
        final step = steps[idx];

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    gradient: isDone ? AppGradients.gold : null,
                    color: isDone
                        ? null
                        : (isDark
                            ? const Color(0xFF2A2518)
                            : const Color(0xFFEDE3B8)),
                    borderRadius: AppRadius.smAll,
                    boxShadow: isDone ? [AppShadows.goldGlowSm] : null,
                  ),
                  child: Icon(
                    isDone ? Icons.check_rounded : step.icon,
                    size: 14,
                    color: isDone
                        ? const Color(0xFF1A1400)
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (idx < steps.length - 1)
                  Container(
                    width: 2,
                    height: 32,
                    decoration: BoxDecoration(
                      gradient: idx < currentStep
                          ? AppGradients.goldLuminous
                          : null,
                      color: idx < currentStep
                          ? null
                          : (isDark
                              ? const Color(0xFF3D3620)
                              : const Color(0xFFE4D9B0)),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          step.title,
                          style: TextStyle(
                            fontWeight: isCurrent
                                ? FontWeight.bold
                                : FontWeight.w600,
                            fontSize: 13,
                            color: isDone
                                ? (isDark
                                    ? const Color(0xFFF3D278)
                                    : const Color(0xFF9A7319))
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (isCurrent) ...[
                          const SizedBox(width: AppSpacing.xs),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: colors.success.withValues(alpha: 0.12),
                              borderRadius: AppRadius.pillAll,
                              border: Border.all(
                                color: colors.success.withValues(alpha: 0.30),
                              ),
                            ),
                            child: Text('الحالة الحالية',
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: colors.success)),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      step.sub,
                      style: TextStyle(
                        fontSize: 11,
                        color: isCurrent
                            ? colors.success
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}

// ── Driver Card ───────────────────────────────────────────────────────────────

class _DriverCard extends StatelessWidget {
  final OrderEntity order;
  final bool isDark;
  const _DriverCard({required this.order, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LuxuryCard(
      padding: const EdgeInsetsDirectional.all(AppSpacing.md),
      child: Row(
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: AppGradients.gold,
              shape: BoxShape.circle,
              boxShadow: [AppShadows.goldGlowSm],
            ),
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.sm),
              child: Icon(Icons.local_shipping_rounded,
                  size: 20, color: Color(0xFF1A1400)),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('سائق التوصيل',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? const Color(0xFFB8A882)
                            : const Color(0xFF9A8A60))),
                Text(order.driverName!,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                if (order.driverPhone != null)
                  Text(order.driverPhone!,
                      style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          if (order.driverPhone != null)
            GoldButton.icon(
              icon: Icons.call_rounded,
              label: 'اتصال',
              onPressed: () =>
                  launchUrl(Uri.parse('tel:${order.driverPhone}')),
              compact: true,
            ),
        ],
      ),
    );
  }
}
