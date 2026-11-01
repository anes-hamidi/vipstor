import 'package:flutter/material.dart';
import 'package:core/core.dart';
import 'package:domain/domain.dart';
import 'package:ui_kit/ui_kit.dart';

import 'driver_order_utils.dart';
import 'driver_route_optimizer.dart';

/// Route planner for the driver queue.
///
/// The driver can reorder stops by dragging or ask the app to calculate a
/// nearest-neighbour route. The result is returned as an ordered list of order
/// IDs so the screen can keep stop numbers, map markers and the task list in
/// sync.
class DriverRouteSheet extends StatefulWidget {
  final List<OrderEntity> orders;
  final List<String> initialOrderIds;
  final Map<String, double> distances;
  final double? driverLat;
  final double? driverLng;

  const DriverRouteSheet({
    super.key,
    required this.orders,
    required this.initialOrderIds,
    required this.distances,
    this.driverLat,
    this.driverLng,
  });

  static Future<List<String>?> show(
    BuildContext context, {
    required List<OrderEntity> orders,
    required List<String> initialOrderIds,
    required Map<String, double> distances,
    double? driverLat,
    double? driverLng,
  }) {
    final content = DriverRouteSheet(
      orders: orders,
      initialOrderIds: initialOrderIds,
      distances: distances,
      driverLat: driverLat,
      driverLng: driverLng,
    );

    final width = MediaQuery.sizeOf(context).width;
    if (width >= 720) {
      return showDialog<List<String>>(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(AppSpacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 660, maxHeight: 760),
            child: content,
          ),
        ),
      );
    }

    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.92,
        child: content,
      ),
    );
  }

  @override
  State<DriverRouteSheet> createState() => _DriverRouteSheetState();
}

class _DriverRouteSheetState extends State<DriverRouteSheet> {
  late List<OrderEntity> _ordered;

  @override
  void initState() {
    super.initState();
    _ordered = _mergeOrder(widget.initialOrderIds);
  }

  List<OrderEntity> _mergeOrder(List<String> ids) {
    final byId = {for (final order in widget.orders) order.id: order};
    final ordered = <OrderEntity>[];
    final used = <String>{};

    for (final id in ids) {
      final order = byId[id];
      if (order != null && used.add(order.id)) ordered.add(order);
    }
    for (final order in widget.orders) {
      if (used.add(order.id)) ordered.add(order);
    }
    return ordered;
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      final item = _ordered.removeAt(oldIndex);
      _ordered.insert(newIndex, item);
    });
  }

  void _optimize() {
    final ids = optimizeDeliveryRoute(
      _ordered,
      startLat: widget.driverLat,
      startLng: widget.driverLng,
    );
    setState(() => _ordered = _mergeOrder(ids));
  }

  void _sortNewest() {
    final sorted = List<OrderEntity>.of(_ordered)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    setState(() => _ordered = sorted);
  }

  void _accept() {
    Navigator.of(context).pop(_ordered.map((order) => order.id).toList());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final totalCash = _ordered.fold<int>(
      0,
      (sum, order) => sum + order.dueAmountCentimes,
    );
    final locatedCount =
        _ordered.where((order) => orderLatitude(order) != null).length;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppRadius.xxlAll,
        border: Border.all(color: colors.gold.withValues(alpha: 0.30)),
        boxShadow: AppShadows.dialogLuxury,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsetsDirectional.all(8),
                  decoration: BoxDecoration(
                    color: colors.goldMuted,
                    borderRadius: AppRadius.mdAll,
                    border: Border.all(color: colors.goldBorder),
                  ),
                  child: Icon(
                    Icons.alt_route_rounded,
                    size: 19,
                    color: colors.gold,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ترتيب محطات الجولة',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'اسحب المحطات أو استخدم التحسين التلقائي',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'إغلاق',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: AppSpacing.lg,
            ),
            child: Row(
              children: [
                _RouteStat(
                  icon: Icons.location_on_outlined,
                  label: '${_ordered.length} محطة',
                  color: colors.gold,
                ),
                const SizedBox(width: AppSpacing.sm),
                _RouteStat(
                  icon: Icons.near_me_outlined,
                  label: '$locatedCount لها موقع',
                  color: colors.success,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _RouteStat(
                    icon: Icons.payments_outlined,
                    label:
                        'تحصيل ${DzdFormatter.formatCentimes(totalCash, showDecimals: false)}',
                    color: colors.warning,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                OutlinedButton.icon(
                  onPressed: _optimize,
                  icon: const Icon(Icons.auto_awesome_rounded, size: 17),
                  label: const Text('تحسين المسار'),
                ),
                TextButton.icon(
                  onPressed: _sortNewest,
                  icon: const Icon(Icons.schedule_rounded, size: 17),
                  label: const Text('الأحدث أولاً'),
                ),
              ],
            ),
          ),
          const GoldDivider(
            margin: EdgeInsetsDirectional.symmetric(
              horizontal: AppSpacing.lg,
            ),
          ),
          Expanded(
            child: _ordered.isEmpty
                ? Center(
                    child: Text(
                      'لا توجد محطات نشطة لترتيبها.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.sm,
                      AppSpacing.lg,
                      AppSpacing.md,
                    ),
                    buildDefaultDragHandles: false,
                    itemCount: _ordered.length,
                    onReorderItem: _reorder,
                    itemBuilder: (context, index) {
                      final order = _ordered[index];
                      return Padding(
                        key: ValueKey(order.id),
                        padding: const EdgeInsetsDirectional.only(
                          bottom: AppSpacing.sm,
                        ),
                        child: _RouteStopTile(
                          order: order,
                          sequence: index + 1,
                          distanceKm: widget.distances[order.id],
                          index: index,
                        ),
                      );
                    },
                  ),
          ),
          const GoldDivider(
            margin: EdgeInsetsDirectional.symmetric(
              horizontal: AppSpacing.lg,
            ),
          ),
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.md + MediaQuery.paddingOf(context).bottom,
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('إلغاء'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 2,
                  child: GoldButton.icon(
                    onPressed: _ordered.isEmpty ? null : _accept,
                    icon: Icons.check_rounded,
                    label: 'اعتماد ترتيب المحطات',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _RouteStat({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: AppRadius.pillAll,
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteStopTile extends StatelessWidget {
  final OrderEntity order;
  final int sequence;
  final double? distanceKm;
  final int index;

  const _RouteStopTile({
    required this.order,
    required this.sequence,
    required this.distanceKm,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final distance = formatDistanceKm(distanceKm);

    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.mdAll,
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.8),
        ),
      ),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 4),
              child: Icon(
                Icons.drag_indicator_rounded,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              gradient: AppGradients.gold,
              borderRadius: AppRadius.smAll,
            ),
            child: Text(
              '$sequence',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: Color(0xFF1A1400),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  deliveryCustomerName(order),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  deliveryAddressText(order) ?? 'بدون عنوان مسجل',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (distance.isNotEmpty)
            Text(
              distance,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.gold,
                fontWeight: FontWeight.w700,
              ),
            ),
          const SizedBox(width: AppSpacing.sm),
          DzdPriceTag.sm(
            centimes: order.dueAmountCentimes,
            gold: true,
          ),
        ],
      ),
    );
  }
}
