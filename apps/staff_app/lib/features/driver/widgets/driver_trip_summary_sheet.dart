import 'package:flutter/material.dart';
import 'package:core/core.dart';
import 'package:domain/domain.dart';
import 'package:ui_kit/ui_kit.dart';

import 'driver_order_utils.dart';

/// Compact end-of-trip report shown when the driver ends a route.
class DriverTripSummarySheet extends StatelessWidget {
  final Duration tripDuration;
  final double distanceKm;
  final List<OrderEntity> orders;

  const DriverTripSummarySheet({
    super.key,
    required this.tripDuration,
    required this.distanceKm,
    required this.orders,
  });

  static Future<bool?> show(
    BuildContext context, {
    required Duration tripDuration,
    required double distanceKm,
    required List<OrderEntity> orders,
  }) {
    final content = DriverTripSummarySheet(
      tripDuration: tripDuration,
      distanceKm: distanceKm,
      orders: orders,
    );
    final width = MediaQuery.sizeOf(context).width;

    if (width >= 720) {
      return showDialog<bool>(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(AppSpacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: content,
          ),
        ),
      );
    }

    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => content,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final now = DateTime.now();

    final todayCompleted = orders.where((order) {
      if (!isOrderCompleted(order.status)) return false;
      final date = order.deliveredAt ?? order.settledAt ?? order.createdAt;
      return date.year == now.year &&
          date.month == now.month &&
          date.day == now.day;
    }).toList(growable: false);

    final collectedToday = todayCompleted.fold<int>(
      0,
      (sum, order) => sum + order.paidAmountCentimes,
    );
    final remaining = orders.where(isDriverDeliveryActive).length;
    final failedToday = orders.where((order) {
      if (!isDeliveryFailure(order)) return false;
      final date = order.deliveryAttemptedAt ?? order.createdAt;
      return date.year == now.year &&
          date.month == now.month &&
          date.day == now.day;
    }).length;

    return Container(
      decoration: BoxDecoration(
        gradient: AppGradients.obsidianHero,
        borderRadius: AppRadius.xxlAll,
        border: Border.all(color: colors.gold.withValues(alpha: 0.34)),
        boxShadow: AppShadows.dialogLuxury,
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsetsDirectional.all(10),
                  decoration: const BoxDecoration(
                    gradient: AppGradients.gold,
                    borderRadius: AppRadius.mdAll,
                    boxShadow: [AppShadows.goldGlowSm],
                  ),
                  child: const Icon(
                    Icons.flag_rounded,
                    size: 22,
                    color: Color(0xFF1A1400),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'انتهت الجولة',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: const Color(0xFFFBF8F0),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'ملخص سريع قبل إغلاق اليوم',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: const Color(0xB8FBF8F0),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                _TripMetric(
                  icon: Icons.timer_outlined,
                  label: 'مدة الجولة',
                  value: _formatDuration(tripDuration),
                ),
                _TripMetric(
                  icon: Icons.route_rounded,
                  label: 'المسافة المقطوعة',
                  value:
                      '${distanceKm.toStringAsFixed(distanceKm >= 10 ? 0 : 1)} كم',
                ),
                _TripMetric(
                  icon: Icons.task_alt_rounded,
                  label: 'تم التسليم اليوم',
                  value: '${todayCompleted.length}',
                  color: const Color(0xFF6EE7B7),
                ),
                _TripMetric(
                  icon: Icons.payments_outlined,
                  label: 'تحصيل اليوم',
                  value: DzdFormatter.formatCentimes(
                    collectedToday,
                    showDecimals: false,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Container(
              padding: const EdgeInsetsDirectional.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.22),
                borderRadius: AppRadius.lgAll,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    remaining > 0
                        ? Icons.pending_actions_rounded
                        : Icons.check_circle_outline_rounded,
                    size: 18,
                    color: remaining > 0
                        ? const Color(0xFFFBBF24)
                        : const Color(0xFF6EE7B7),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      remaining > 0
                          ? '$remaining محطة ما زالت نشطة. يمكنك بدء جولة جديدة في أي وقت.'
                          : 'كل المحطات النشطة أُنجزت. عمل ممتاز!',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFFBF8F0),
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (failedToday > 0) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Icon(
                    Icons.assignment_return_outlined,
                    size: 16,
                    color: colors.cancelled,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      '$failedToday محاولة تعذر تسليم أُرسلت لمراجعة المشرف.',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: const Color(0xB8FBF8F0),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFBF8F0),
                      side: BorderSide(
                        color: const Color(0xFFFBF8F0).withValues(alpha: 0.25),
                      ),
                      minimumSize: const Size(0, 46),
                    ),
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('متابعة العمل'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: GoldButton.icon(
                    onPressed: () => Navigator.of(context).pop(true),
                    icon: Icons.task_alt_rounded,
                    label: 'عرض المكتملة',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    if (duration.inMinutes < 1) return 'أقل من دقيقة';
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours == 0) return '$minutes د';
    return '$hours س $minutes د';
  }
}

class _TripMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _TripMetric({
    required this.icon,
    required this.label,
    required this.value,
    this.color = const Color(0xFFF3D278),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = (MediaQuery.sizeOf(context).width - 72) / 2;
    return Container(
      width: width.clamp(130.0, 220.0),
      padding: const EdgeInsetsDirectional.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.20),
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: const Color(0xB8FBF8F0),
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
