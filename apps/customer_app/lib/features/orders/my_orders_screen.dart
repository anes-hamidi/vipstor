import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:domain/domain.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/customer_models.dart';
import '../../providers/customer_providers.dart';
import '../cart/cart_screen.dart';
import 'services/customer_invoice_service.dart';
import 'widgets/customer_order_tracking_view.dart';

enum _OrdersFilter { all, active, finished }

class MyOrdersScreen extends ConsumerStatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  ConsumerState<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends ConsumerState<MyOrdersScreen> {
  _OrdersFilter _filter = _OrdersFilter.all;

  Future<void> _refresh() =>
      ref.read(customerOrdersProvider.notifier).refresh();

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(customerOrdersProvider);
    final online = ref.watch(customerIsOnlineProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF1DAB61), Color(0xFF034F40)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: AppRadius.smAll,
                boxShadow: [BoxShadow(color: Color(0x3D1DAB61), blurRadius: 8, offset: Offset(0,3))],
              ),
              child: Padding(
                padding: EdgeInsets.all(5),
                child: Icon(Icons.receipt_long_rounded,
                    size: 16, color: Colors.white),
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
            onPressed: _refresh,
          ),
        ],
      ),
      body: ordersAsync.when(
        loading: () => const _OrdersSkeleton(),
        error: (err, _) => ContentConstrainedBox.dashboard(
          padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
          child: AppStates.error(
            'تعذر جلب الطلبيات. ${err.toString().replaceFirst('Exception: ', '')}',
            title: 'لم نتمكن من فتح طلبياتك',
            onRetry: _refresh,
          ),
        ),
        data: (snapshot) => _OrdersBody(
          snapshot: snapshot,
          online: online,
          filter: _filter,
          onFilterChanged: (value) => setState(() => _filter = value),
          onRefresh: _refresh,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Body
// ─────────────────────────────────────────────────────────────────────────────

class _OrdersBody extends ConsumerWidget {
  final OrdersSnapshot snapshot;
  final bool online;
  final _OrdersFilter filter;
  final ValueChanged<_OrdersFilter> onFilterChanged;
  final Future<void> Function() onRefresh;

  const _OrdersBody({
    required this.snapshot,
    required this.online,
    required this.filter,
    required this.onFilterChanged,
    required this.onRefresh,
  });

  List<OrderEntity> get _filtered {
    switch (filter) {
      case _OrdersFilter.all:
        return snapshot.orders;
      case _OrdersFilter.active:
        return snapshot.activeOrders;
      case _OrdersFilter.finished:
        return snapshot.pastOrders;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final orders = _filtered;
    final offline = !online || snapshot.isOffline;

    if (snapshot.orders.isEmpty) {
      return RefreshIndicator(
        color: const Color(0xFF1DAB61),
        backgroundColor:
            isDark ? const Color(0xFF131B16) : const Color(0xFFEEF5F0),
        onRefresh: onRefresh,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: AppStates.empty(
                icon: Icons.receipt_long_outlined,
                title: 'لا توجد طلبات بعد',
                description:
                    'لم تقم بتسجيل أي طلبية بعد. تصفح المتجر لتبدأ التسوق.',
              ),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: const Color(0xFF1DAB61),
      backgroundColor:
          isDark ? const Color(0xFF131B16) : const Color(0xFFEEF5F0),
      onRefresh: onRefresh,
      child: ContentConstrainedBox.dashboard(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.xxl,
          ),
          children: [
            if (offline || snapshot.lastError != null)
              _OrdersNotice(
                offline: offline,
                message: snapshot.lastError,
                pendingCount: snapshot.pendingCount,
                fetchedAt: snapshot.fetchedAt,
                onRetry: onRefresh,
              ),
            if (offline || snapshot.lastError != null)
              const SizedBox(height: AppSpacing.md),
            _FilterRow(
              filter: filter,
              total: snapshot.orders.length,
              active: snapshot.activeOrders.length,
              finished: snapshot.pastOrders.length,
              onChanged: onFilterChanged,
            ),
            const SizedBox(height: AppSpacing.sm),
            if (orders.isEmpty)
              Padding(
                padding: const EdgeInsetsDirectional.only(top: AppSpacing.xxl),
                child: AppStates.empty(
                  icon: Icons.filter_alt_off_outlined,
                  title: filter == _OrdersFilter.active
                      ? 'لا توجد طلبيات جارية'
                      : 'لا توجد طلبيات منتهية',
                  description: filter == _OrdersFilter.active
                      ? 'طلبياتك المكتملة تظهر في تبويب "المنتهية".'
                      : 'ستظهر هنا طلبياتك بعد التسليم.',
                  actionLabel: 'عرض الكل',
                  onAction: () => onFilterChanged(_OrdersFilter.all),
                ),
              )
            else
              ...orders.map(
                (order) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: _OrderCard(
                    order: order,
                    isDark: isDark,
                    onTap: () => _showDetails(context, order),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  final _OrdersFilter filter;
  final int total;
  final int active;
  final int finished;
  final ValueChanged<_OrdersFilter> onChanged;

  const _FilterRow({
    required this.filter,
    required this.total,
    required this.active,
    required this.finished,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _FilterChip(
            label: 'الكل',
            count: total,
            selected: filter == _OrdersFilter.all,
            onTap: () => onChanged(_OrdersFilter.all),
          ),
          _FilterChip(
            label: 'جارية',
            count: active,
            selected: filter == _OrdersFilter.active,
            onTap: () => onChanged(_OrdersFilter.active),
          ),
          _FilterChip(
            label: 'منتهية',
            count: finished,
            selected: filter == _OrdersFilter.finished,
            onTap: () => onChanged(_OrdersFilter.finished),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.pillAll,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: AppSpacing.md, vertical: 6),
            decoration: BoxDecoration(
              gradient: selected ? const LinearGradient(colors: [Color(0xFF1DAB61), Color(0xFF034F40)], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
              color: selected
                  ? null
                  : (isDark
                      ? const Color(0xFF131B16)
                      : const Color(0xFFEEF5F0)),
              borderRadius: AppRadius.pillAll,
              border: Border.all(
                color: selected
                    ? Colors.transparent
                    : const Color(0xFF1DAB61)
                        .withValues(alpha: isDark ? 0.22 : 0.16),
              ),
              boxShadow: selected ? const [BoxShadow(color: Color(0x3D1DAB61), blurRadius: 8, offset: Offset(0,3))] : null,
            ),
            child: Row(
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight:
                        selected ? FontWeight.bold : FontWeight.w600,
                    color: selected
                        ? Colors.white
                        : theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 5),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 0.5),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0x33000000)
                        : const Color(0xFF1DAB61).withValues(alpha: 0.14),
                    borderRadius: AppRadius.pillAll,
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: selected
                          ? Colors.white
                          : (isDark
                              ? const Color(0xFF72DFA0)
                              : const Color(0xFF0A6B3A)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OrdersNotice extends StatelessWidget {
  final bool offline;
  final String? message;
  final int pendingCount;
  final DateTime? fetchedAt;
  final Future<void> Function() onRetry;

  const _OrdersNotice({
    required this.offline,
    required this.message,
    required this.pendingCount,
    required this.fetchedAt,
    required this.onRetry,
  });

  String get _subtitle {
    if (pendingCount > 0) {
      return '$pendingCount طلبية محفوظة محلياً في انتظار المزامنة.';
    }
    if (fetchedAt != null) {
      final local = fetchedAt!.toLocal();
      final d =
          '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}';
      final t =
          '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
      return 'آخر تحديث $d · $t';
    }
    return message ?? 'تُعرض آخر نسخة محفوظة على جهازك.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final gold = isDark ? const Color(0xFF72DFA0) : const Color(0xFF0A6B3A);

    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D1F18) : const Color(0xFFE8F7EF),
        borderRadius: AppRadius.mdAll,
        border: Border.all(
          color: const Color(0xFF1DAB61).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Icon(
            offline ? Icons.wifi_off_rounded : Icons.cloud_off_rounded,
            size: 17,
            color: gold,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  offline
                      ? 'وضع عدم الاتصال — طلبياتك محفوظة على جهازك'
                      : 'تعذر تحديث الطلبيات الآن',
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.bold),
                ),
                Text(
                  _subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 9.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'إعادة المحاولة',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.refresh_rounded, size: 17),
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Order card
// ─────────────────────────────────────────────────────────────────────────────

class _OrderCard extends ConsumerWidget {
  final OrderEntity order;
  final bool isDark;
  final VoidCallback onTap;

  const _OrderCard({
    required this.order,
    required this.isDark,
    required this.onTap,
  });

  static bool isPending(OrderEntity order) =>
      order.notes?.contains('محفوظ محلياً') == true;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final info = _statusInfo(order);
    final pending = isPending(order);

    return LuxuryCard(
      goldAccent: order.isFinished,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsetsDirectional.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _orderTitle(order),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                DzdPriceTag(
                  centimes: order.totalAmountCentimes,
                  gold: order.isFinished,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                StatusBadge(
                  type: info.badge,
                  customLabel: info.label,
                  compact: true,
                ),
                if (pending) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Icon(Icons.cloud_upload_outlined,
                      size: 13,
                      color: isDark
                          ? const Color(0xFF72DFA0)
                          : const Color(0xFF0A6B3A)),
                ],
                const Spacer(),
                Text(
                  '${order.items.length} منتجات',
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _MiniTimeline(order: order),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Icon(Icons.schedule_rounded,
                    size: 12,
                    color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _fmt(order.createdAt),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 10,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (order.isFinished)
                  _ReorderButton(order: order, compact: true),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'التفاصيل',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: isDark
                        ? const Color(0xFF72DFA0)
                        : const Color(0xFFC59B27),
                  ),
                ),
                const SizedBox(width: 2),
                Icon(Icons.arrow_forward_ios_rounded,
                    size: 9,
                    color: isDark
                        ? const Color(0xFF72DFA0)
                        : const Color(0xFFC59B27)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReorderButton extends ConsumerWidget {
  final OrderEntity order;
  final bool compact;

  const _ReorderButton({required this.order, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (compact) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppRadius.pillAll,
          onTap: () => _reorder(context, ref, order),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF1DAB61).withValues(alpha: 0.12),
              borderRadius: AppRadius.pillAll,
              border: Border.all(
                color: const Color(0xFF1DAB61).withValues(alpha: 0.40),
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.replay_rounded,
                    size: 11, color: Color(0xFF1DAB61)),
                SizedBox(width: 3),
                Text(
                  'أعد الطلب',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFC59B27),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return GoldButton.icon(
      icon: Icons.replay_rounded,
      label: 'إعادة هذه الطلبية إلى السلة',
      onPressed: () => _reorder(context, ref, order),
      width: double.infinity,
      height: 46,
    );
  }
}

void _reorder(BuildContext context, WidgetRef ref, OrderEntity order) {
  final catalog =
      ref.read(customerCatalogProvider).valueOrNull?.products ?? const [];
  final result =
      ref.read(customerCartProvider.notifier).reorder(order, catalog);
  final messenger = ScaffoldMessenger.of(context);

  if (result.added == 0) {
    messenger.showSnackBar(
      const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('المنتجات غير متوفرة حالياً في المتجر.'),
      ),
    );
    return;
  }

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        content: Text(
          result.skipped > 0
              ? 'أُضيف ${result.added} منتج — ${result.skipped} غير متوفر حالياً.'
              : 'أُضيف ${result.added} منتج إلى السلة.',
        ),
        action: SnackBarAction(
          label: 'عرض السلة',
          textColor: const Color(0xFF72DFA0),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CartScreen()),
          ),
        ),
      ),
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Mini timeline
// ─────────────────────────────────────────────────────────────────────────────

class _MiniTimeline extends StatelessWidget {
  final OrderEntity order;

  const _MiniTimeline({required this.order});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = context.appColors;
    final cancelled = order.isCancelled;
    final step = order.timelineStep;
    const labels = ['أُرسل', 'تأكيد', 'تجهيز', 'توصيل', 'تسليم'];
    final activeColor = cancelled ? colors.cancelled : const Color(0xFF1DAB61);
    final inactiveColor =
        isDark ? const Color(0xFF3D3620) : const Color(0xFFE4D9B0);

    return Row(
      children: List.generate(5, (i) {
        final done = !cancelled && i <= step;
        return Expanded(
          child: Column(
            children: [
              Row(
                children: [
                  if (i > 0)
                    Expanded(
                      child: Container(
                        height: 2,
                        color: i <= step && !cancelled
                            ? activeColor
                            : inactiveColor,
                      ),
                    ),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: done ? activeColor : inactiveColor,
                      shape: BoxShape.circle,
                      boxShadow: done
                          ? [
                              BoxShadow(
                                color: activeColor.withValues(alpha: 0.35),
                                blurRadius: 4,
                              )
                            ]
                          : null,
                    ),
                  ),
                  if (i < 4)
                    Expanded(
                      child: Container(
                        height: 2,
                        color: i < step && !cancelled
                            ? activeColor
                            : inactiveColor,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                labels[i],
                style: TextStyle(
                  fontSize: 8,
                  fontWeight:
                      done ? FontWeight.bold : FontWeight.w500,
                  color: done
                      ? activeColor
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Details sheet
// ─────────────────────────────────────────────────────────────────────────────

void _showDetails(BuildContext context, OrderEntity order) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.52,
      maxChildSize: 0.97,
      expand: false,
      builder: (_, sc) => _OrderDetailSheet(
        order: order,
        scrollController: sc,
        isDark: isDark,
      ),
    ),
  );
}

class _OrderDetailSheet extends ConsumerWidget {
  final OrderEntity order;
  final ScrollController scrollController;
  final bool isDark;

  const _OrderDetailSheet({
    required this.order,
    required this.scrollController,
    required this.isDark,
  });

  bool get _pending => _OrderCard.isPending(order);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final online = ref.watch(customerIsOnlineProvider);
    // Locally queued orders use a client-generated UUID that has no server
    // row yet, so polling would only produce noise.
    final liveAsync = _pending || order.id.length < 20
        ? AsyncData<LiveOrderUpdate>(LiveOrderUpdate(orderId: order.id))
        : ref.watch(customerLiveOrderProvider(order.id));
    final live = liveAsync.valueOrNull;

    final status = live?.status ?? order.status;
    final displayOrder = order.copyWith(
      status: status,
      confirmedAt: live?.confirmedAt ?? order.confirmedAt,
      deliveredAt: live?.deliveredAt ?? order.deliveredAt,
      settledAt: live?.settledAt ?? order.settledAt,
    );
    final info = _statusInfo(displayOrder);
    final driverName = live?.driverName ?? order.driverName;
    final driverPhone = live?.driverPhone ?? order.driverPhone;
    final driverId = live?.driverId ?? order.driverId;
    final canTrack = !_pending &&
        displayOrder.isOpen &&
        driverId != null &&
        driverId.isNotEmpty;
    final destinationLat = live?.destinationLat ??
        order.deliveryLat ??
        (order.deliveryAddress?['latitude'] as num?)?.toDouble();
    final destinationLng = live?.destinationLng ??
        order.deliveryLng ??
        (order.deliveryAddress?['longitude'] as num?)?.toDouble();

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF191714) : const Color(0xFFEEF5F0),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: const Color(0xFF1DAB61).withValues(alpha: 0.35),
        ),
        boxShadow: AppShadows.dialogLuxury,
      ),
      child: ListView(
        controller: scrollController,
        padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
        children: [
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: AppRadius.fullAll,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _orderTitle(displayOrder),
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _fmt(displayOrder.createdAt),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'إغلاق',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              StatusBadge(
                type: info.badge,
                customLabel: info.label,
              ),
              const Spacer(),
              DzdPriceTag(
                centimes: displayOrder.totalAmountCentimes,
                gold: displayOrder.isFinished,
              ),
            ],
          ),
          if (_pending) ...[
            const SizedBox(height: AppSpacing.md),
            _PendingNotice(offline: !online),
          ],
          const SizedBox(height: AppSpacing.md),
          Container(height: 0.7, margin: const EdgeInsets.symmetric(vertical: 8), decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0x001DAB61), Color(0xFF1DAB61), Color(0x001DAB61)]))),
          const SizedBox(height: AppSpacing.md),
          const SectionHeader(title: 'تتبع حالة الطلب'),
          const SizedBox(height: AppSpacing.sm),
          _GoldTimeline(order: displayOrder, live: live),
          if (!_pending && (canTrack || displayOrder.isOpen)) ...[
            const SizedBox(height: AppSpacing.md),
            CustomerOrderTrackingView(
              order: displayOrder,
              destinationLat: destinationLat,
              destinationLng: destinationLng,
              driverName: driverName,
              driverPhone: driverPhone,
              onStatusChanged: (_) => unawaited(
                ref.read(customerOrdersProvider.notifier).refresh(silent: true),
              ),
            ),
          ],
          if (driverName != null && driverName.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _DriverCard(
              name: driverName,
              phone: driverPhone,
              isLive: live?.status == OrderStatus.outForDelivery,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Container(height: 0.7, margin: const EdgeInsets.symmetric(vertical: 8), decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0x001DAB61), Color(0xFF1DAB61), Color(0x001DAB61)]))),
          const SizedBox(height: AppSpacing.md),
          SectionHeader(title: 'السلع المطلوبة (${displayOrder.items.length})'),
          const SizedBox(height: AppSpacing.sm),
          ...displayOrder.items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: LuxuryCard(
                padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        gradient:
                            isDark ? null : const LinearGradient(colors: [Color(0x1A1DAB61), Color(0x1A034F40)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                        color: isDark ? const Color(0xFF2A2518) : null,
                        borderRadius: AppRadius.smAll,
                        border: Border.all(
                          color:
                              const Color(0xFF1DAB61).withValues(alpha: 0.20),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '${item.quantity}×',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? const Color(0xFF72DFA0)
                                : const Color(0xFF0A6B3A),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.productName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 12),
                          ),
                          if (item.unit != null)
                            Text(
                              item.formattedQuantityWithUnit,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(fontSize: 9.5),
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
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _TotalsCard(order: displayOrder),
          if (_deliverySummary(displayOrder).isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _AddressCard(summary: _deliverySummary(displayOrder)),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _ReorderButton(order: order),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(
                        color: Color(0x661DAB61), width: 1),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: const RoundedRectangleBorder(
                        borderRadius: AppRadius.mdAll),
                  ),
                  onPressed: () =>
                      CustomerInvoiceService.printCustomerOrderInvoice(order),
                  icon: const Icon(Icons.picture_as_pdf_outlined,
                      size: 16, color: Color(0xFF1DAB61)),
                  label: const Text(
                    'تنزيل الفاتورة',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFC59B27),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}

class _PendingNotice extends StatelessWidget {
  final bool offline;

  const _PendingNotice({required this.offline});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsetsDirectional.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.warningContainer,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: colors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_upload_outlined,
              size: 18, color: colors.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              offline
                  ? 'طلبية محفوظة على جهازك وستُرسل تلقائياً عند عودة الاتصال.'
                  : 'طلبية محفوظة محلياً، جاري مزامنتها مع المتجر...',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: colors.onWarningContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Timeline
// ─────────────────────────────────────────────────────────────────────────────

class _GoldTimeline extends StatelessWidget {
  final OrderEntity order;
  final LiveOrderUpdate? live;

  const _GoldTimeline({required this.order, this.live});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (order.isCancelled) {
      return LuxuryCard(
        padding: const EdgeInsetsDirectional.all(AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: AppRadius.smAll,
              ),
              child: Icon(Icons.cancel_outlined,
                  color: theme.colorScheme.error, size: 20),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                'تم إلغاء أو رفض هذا الطلب',
                style: TextStyle(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final steps = <({IconData icon, String title, String sub, DateTime? at})>[
      (
        icon: Icons.send_rounded,
        title: 'تم الإرسال',
        sub: 'استلم المتجر طلبيتك',
        at: order.createdAt,
      ),
      (
        icon: Icons.verified_outlined,
        title: 'تم التأكيد',
        sub: 'تم حجز المخزون',
        at: live?.confirmedAt ?? order.confirmedAt,
      ),
      (
        icon: Icons.inventory_2_outlined,
        title: 'قيد التجهيز',
        sub: 'تغليف السلع',
        at: order.preparedAt,
      ),
      (
        icon: Icons.local_shipping_outlined,
        title: 'مع السائق',
        sub: 'قيد التوصيل',
        at: null,
      ),
      (
        icon: Icons.check_circle_outline,
        title: 'تم التسليم',
        sub: 'تم الاستلام',
        at: live?.deliveredAt ??
            order.deliveredAt ??
            live?.settledAt ??
            order.settledAt,
      ),
    ];

    final currentStep = order.timelineStep;

    return Column(
      children: List.generate(steps.length, (idx) {
        final isDone = idx <= currentStep;
        final isCurrent = idx == currentStep;
        final step = steps[idx];
        final timestamp = isDone ? step.at : null;

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
                    gradient: isDone ? const LinearGradient(colors: [Color(0xFF1DAB61), Color(0xFF034F40)], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
                    color: isDone
                        ? null
                        : (isDark
                            ? const Color(0xFF2A2518)
                            : const Color(0xFFEDE3B8)),
                    borderRadius: AppRadius.smAll,
                    boxShadow: isDone ? const [BoxShadow(color: Color(0x3D1DAB61), blurRadius: 8, offset: Offset(0,3))] : null,
                  ),
                  child: Icon(
                    isDone ? Icons.check_rounded : step.icon,
                    size: 14,
                    color: isDone
                        ? Colors.white
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (idx < steps.length - 1)
                  Container(
                    width: 2,
                    height: 34,
                    decoration: BoxDecoration(
                      gradient: idx < currentStep
                          ? const LinearGradient(colors: [Color(0xFF1DAB61), Color(0xFF034F40)], begin: Alignment.topLeft, end: Alignment.bottomRight)
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
                            fontSize: 12.5,
                            color: isDone
                                ? (isDark
                                    ? const Color(0xFF72DFA0)
                                    : const Color(0xFF0A6B3A))
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (isCurrent) ...[
                          const SizedBox(width: AppSpacing.xs),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color:
                                  colors.success.withValues(alpha: 0.12),
                              borderRadius: AppRadius.pillAll,
                              border: Border.all(
                                color: colors.success
                                    .withValues(alpha: 0.30),
                              ),
                            ),
                            child: Text(
                              'الحالة الحالية',
                              style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.bold,
                                color: colors.success,
                              ),
                            ),
                          ),
                        ],
                        if (timestamp != null) ...[
                          const Spacer(),
                          Text(
                            _fmtShort(timestamp),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 9,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      step.sub,
                      style: TextStyle(
                        fontSize: 10,
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

class _DriverCard extends StatelessWidget {
  final String name;
  final String? phone;
  final bool isLive;

  const _DriverCard({
    required this.name,
    required this.phone,
    required this.isLive,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    return LuxuryCard(
      padding: const EdgeInsetsDirectional.all(AppSpacing.md),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF1DAB61), Color(0xFF034F40)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Color(0x3D1DAB61), blurRadius: 8, offset: Offset(0,3))],
            ),
            child: const Icon(Icons.local_shipping_rounded,
                size: 20, color: Colors.white),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'سائق التوصيل',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 9.5,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (isLive) ...[
                      const SizedBox(width: 4),
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: colors.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  name,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                ),
                if (phone != null && phone!.isNotEmpty)
                  Text(phone!,
                      style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 10.5)),
              ],
            ),
          ),
          if (phone != null && phone!.isNotEmpty)
            GoldButton.icon(
              icon: Icons.call_rounded,
              label: 'اتصال',
              onPressed: () => launchUrl(Uri.parse('tel:$phone')),
              compact: true,
            ),
        ],
      ),
    );
  }
}

class _TotalsCard extends StatelessWidget {
  final OrderEntity order;

  const _TotalsCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return LuxuryCard(
      padding: const EdgeInsetsDirectional.all(AppSpacing.md),
      child: Column(
        children: [
          _row(context, 'المبلغ الإجمالي', order.totalAmountCentimes,
              bold: true),
          if (order.paidAmountCentimes > 0) ...[
            const SizedBox(height: 4),
            _row(context, 'المدفوع', order.paidAmountCentimes,
                color: context.appColors.success),
          ],
          if (order.dueAmountCentimes > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(height: 0.7, margin: const EdgeInsets.symmetric(vertical: 8), decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0x001DAB61), Color(0xFF1DAB61), Color(0x001DAB61)]))),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'المتبقي على الحساب',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                DzdPriceTag(
                  centimes: order.dueAmountCentimes,
                  gold: true,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    String label,
    int centimes, {
    bool bold = false,
    Color? color,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: bold ? FontWeight.bold : FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        DzdPriceTag(
          centimes: centimes,
          color: color,
          style: TextStyle(
            fontWeight: bold ? FontWeight.bold : FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _AddressCard extends StatelessWidget {
  final String summary;

  const _AddressCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LuxuryCard(
      padding: const EdgeInsetsDirectional.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.location_on_outlined,
              size: 17, color: Color(0xFF1DAB61)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'عنوان التوصيل',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 9.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  summary,
                  style: const TextStyle(fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Skeleton
// ─────────────────────────────────────────────────────────────────────────────

class _OrdersSkeleton extends StatelessWidget {
  const _OrdersSkeleton();

  @override
  Widget build(BuildContext context) {
    return ContentConstrainedBox.dashboard(
      padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
      child: ListView.separated(
        itemCount: 5,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (_, __) => AppStates.skeleton(
            height: 142, borderRadius: AppRadius.lgAll),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

({StatusBadgeType badge, String label}) _statusInfo(OrderEntity order) {
  final pending = _OrderCard.isPending(order);
  if (pending) {
    return (badge: StatusBadgeType.draft, label: 'في انتظار المزامنة');
  }
  return switch (order.status) {
    OrderStatus.submitted => (
        badge: StatusBadgeType.pending,
        label: 'تم الإرسال — قيد المراجعة',
      ),
    OrderStatus.confirmed => (
        badge: StatusBadgeType.pending,
        label: 'تم التأكيد وحجز المخزون',
      ),
    OrderStatus.preparing => (
        badge: StatusBadgeType.preparing,
        label: 'قيد التجهيز في المستودع',
      ),
    OrderStatus.ready => (
        badge: StatusBadgeType.ready,
        label: 'جاهز للتسليم',
      ),
    OrderStatus.assigned ||
    OrderStatus.accepted ||
    OrderStatus.outForDelivery =>
      (
        badge: StatusBadgeType.processing,
        label: order.driverName != null
            ? 'مع السائق: ${order.driverName}'
            : 'قيد التوصيل',
      ),
    OrderStatus.delivered || OrderStatus.settled => (
        badge: StatusBadgeType.delivered,
        label: 'تم التسليم بنجاح',
      ),
    OrderStatus.cancelled || OrderStatus.refused => (
        badge: StatusBadgeType.cancelled,
        label: 'ملغى',
      ),
    OrderStatus.requiresManagerReview => (
        badge: StatusBadgeType.pending,
        label: 'قيد مراجعة الإدارة',
      ),
  };
}

String _orderTitle(OrderEntity order) {
  if (_OrderCard.isPending(order)) {
    final short = order.id.length > 8 ? order.id.substring(0, 8) : order.id;
    return 'طلبية محلية #$short';
  }
  if (order.orderNumber != null) return 'طلب #${order.orderNumber}';
  final short = order.id.length > 8 ? order.id.substring(0, 8) : order.id;
  return 'طلب #$short';
}

String _deliverySummary(OrderEntity order) {
  final address = order.deliveryAddress;
  if (address == null) return '';
  final parts = <String>[
    if ((address['wilaya'] as String?)?.trim().isNotEmpty == true)
      address['wilaya'] as String,
    if ((address['commune'] as String?)?.trim().isNotEmpty == true)
      address['commune'] as String,
    if ((address['address_text'] as String?)?.trim().isNotEmpty == true)
      address['address_text'] as String,
    if ((address['address'] as String?)?.trim().isNotEmpty == true)
      address['address'] as String,
  ];
  return parts.toSet().join(' · ');
}

String _fmt(DateTime dt) {
  final l = dt.toLocal();
  return '${l.year}/${l.month.toString().padLeft(2, '0')}/${l.day.toString().padLeft(2, '0')} '
      '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

String _fmtShort(DateTime dt) {
  final l = dt.toLocal();
  return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')} '
      '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}
