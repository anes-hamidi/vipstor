import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:domain/domain.dart';
import 'package:latlong2/latlong.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/catalog_ranking.dart';
import '../../../models/customer_models.dart';
import '../../../providers/customer_providers.dart';

/// Live order / driver tracking card.
///
/// Polls [customerLiveOrderProvider] (secure RPC when available, direct table
/// reads as a fallback) and renders ETA, distance, last-seen and a map.
class CustomerOrderTrackingView extends ConsumerStatefulWidget {
  final OrderEntity order;
  final double? destinationLat;
  final double? destinationLng;
  final String? driverName;
  final String? driverPhone;
  final ValueChanged<OrderStatus>? onStatusChanged;

  const CustomerOrderTrackingView({
    super.key,
    required this.order,
    this.destinationLat,
    this.destinationLng,
    this.driverName,
    this.driverPhone,
    this.onStatusChanged,
  });

  @override
  ConsumerState<CustomerOrderTrackingView> createState() =>
      _CustomerOrderTrackingViewState();
}

class _CustomerOrderTrackingViewState
    extends ConsumerState<CustomerOrderTrackingView>
    with SingleTickerProviderStateMixin {
  late final MapController _mapController;
  late final AnimationController _pulseCtrl;
  OrderStatus? _lastNotifiedStatus;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _mapController.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colors = context.appColors;
    final online = ref.watch(customerIsOnlineProvider);
    final liveAsync = ref.watch(customerLiveOrderProvider(widget.order.id));
    final live = liveAsync.valueOrNull;

    ref.listen<AsyncValue<LiveOrderUpdate>>(
      customerLiveOrderProvider(widget.order.id),
      (previous, next) {
        final status = next.valueOrNull?.status;
        if (status == null) return;
        if (status != _lastNotifiedStatus) {
          _lastNotifiedStatus = status;
          widget.onStatusChanged?.call(status);
        }
      },
    );

    final driverName = live?.driverName ?? widget.driverName;
    final driverPhone = live?.driverPhone ?? widget.driverPhone;
    final driverPoint = (live?.hasDriverLocation ?? false)
        ? LatLng(live!.driverLat!, live.driverLng!)
        : null;
    final destPoint =
        (widget.destinationLat != null && widget.destinationLng != null)
            ? LatLng(widget.destinationLat!, widget.destinationLng!)
            : (live?.destinationLat != null && live?.destinationLng != null)
                ? LatLng(live!.destinationLat!, live.destinationLng!)
                : null;

    final offline = !online || (live?.isOffline ?? false);
    final status =
        live?.status ?? widget.order.status;
    final isMoving = status == OrderStatus.outForDelivery ||
        status == OrderStatus.accepted ||
        status == OrderStatus.assigned;

    final distanceKm = (driverPoint != null && destPoint != null)
        ? haversineKm(
            driverPoint.latitude,
            driverPoint.longitude,
            destPoint.latitude,
            destPoint.longitude,
          )
        : null;

    final eta = _etaLabel(
      distanceKm: distanceKm,
      isMoving: isMoving,
      hasDriverPoint: driverPoint != null,
      status: status,
    );

    return LuxuryCard(
      goldAccent: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                if (offline)
                  Icon(Icons.wifi_off_rounded,
                      size: 12, color: colors.warning)
                else
                  AnimatedBuilder(
                    animation: _pulseCtrl,
                    builder: (_, __) => Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors.success,
                        boxShadow: [
                          BoxShadow(
                            color: colors.success.withValues(
                                alpha:
                                    0.25 + 0.35 * _pulseCtrl.value),
                            blurRadius: 5 + 5 * _pulseCtrl.value,
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        offline
                            ? 'التتبع متوقف — لا يوجد اتصال'
                            : driverName != null && driverName.isNotEmpty
                                ? 'تتبع السائق مباشرة · $driverName'
                                : 'تتبع الطلب مباشرة',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                        ),
                      ),
                      Text(
                        _statusLine(
                          status: status,
                          online: online,
                          hasDriverPoint: driverPoint != null,
                          error: live?.error,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 9.5,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (driverPhone != null && driverPhone.isNotEmpty)
                  GoldIconButton(
                    icon: Icons.call_rounded,
                    tooltip: 'اتصال بالسائق',
                    size: 32,
                    filled: true,
                    onPressed: () =>
                        launchUrl(Uri.parse('tel:$driverPhone')),
                  ),
                if (!offline)
                  const Padding(
                    padding: EdgeInsetsDirectional.only(start: 4),
                    child: GoldBadge(label: 'مباشر', small: true),
                  ),
              ],
            ),
          ),

          // ── Stats strip ─────────────────────────────────────────────────
          Container(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF14120F)
                  : const Color(0xFFFBF4DC),
              border: Border(
                top: BorderSide(
                  color: const Color(0xFFD4AF37)
                      .withValues(alpha: isDark ? 0.18 : 0.12),
                ),
                bottom: BorderSide(
                  color: const Color(0xFFD4AF37)
                      .withValues(alpha: isDark ? 0.18 : 0.12),
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _TrackingStat(
                    icon: Icons.schedule_rounded,
                    label: 'الوقت المتوقع',
                    value: eta,
                    highlight: isMoving && distanceKm != null,
                  ),
                ),
                _StatDivider(isDark: isDark),
                Expanded(
                  child: _TrackingStat(
                    icon: Icons.route_rounded,
                    label: 'المسافة',
                    value: distanceKm == null
                        ? '—'
                        : distanceKm < 1
                            ? '${(distanceKm * 1000).round()} م'
                            : '${distanceKm.toStringAsFixed(1)} كم',
                  ),
                ),
                _StatDivider(isDark: isDark),
                Expanded(
                  child: _TrackingStat(
                    icon: Icons.update_rounded,
                    label: 'آخر إشارة',
                    value: _lastSeen(live?.driverUpdatedAt),
                    stale: _isStale(live?.driverUpdatedAt),
                  ),
                ),
              ],
            ),
          ),

          // ── Map / placeholder ───────────────────────────────────────────
          if (driverPoint != null || destPoint != null)
            SizedBox(
              height: 210,
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: driverPoint ??
                          destPoint ??
                          const LatLng(36.7525, 3.042),
                      initialZoom: 14.5,
                      maxZoom: 18,
                      minZoom: 6,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.vip.customer',
                      ),
                      if (driverPoint != null && destPoint != null)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: [driverPoint, destPoint],
                              strokeWidth: 3.5,
                              color: const Color(0xFFD4AF37),
                              strokeCap: StrokeCap.round,
                            ),
                          ],
                        ),
                      MarkerLayer(
                        markers: [
                          if (destPoint != null)
                            Marker(
                              point: destPoint,
                              width: 40,
                              height: 40,
                              child: Tooltip(
                                message: 'موقع التسليم',
                                child: Icon(
                                  Icons.location_on_rounded,
                                  color: colors.cancelled,
                                  size: 34,
                                  shadows: const [
                                    Shadow(
                                      color: Colors.black38,
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (driverPoint != null)
                            Marker(
                              point: driverPoint,
                              width: 44,
                              height: 44,
                              child: const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: AppGradients.gold,
                                  shape: BoxShape.circle,
                                  boxShadow: [AppShadows.goldGlow],
                                ),
                                child: Icon(
                                  Icons.local_shipping_rounded,
                                  color: Color(0xFF1A1400),
                                  size: 21,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  PositionedDirectional(
                    bottom: 8,
                    end: 8,
                    child: _MapButton(
                      icon: Icons.my_location_rounded,
                      tooltip: 'توسيط الخريطة',
                      onTap: () {
                        if (driverPoint != null && destPoint != null) {
                          final bounds = LatLngBounds.fromPoints(
                              [driverPoint, destPoint]);
                          _mapController.fitCamera(
                            CameraFit.bounds(
                              bounds: bounds,
                              padding: const EdgeInsets.all(36),
                            ),
                          );
                        } else if (driverPoint != null) {
                          _mapController.move(driverPoint, 15);
                        } else if (destPoint != null) {
                          _mapController.move(destPoint, 15);
                        }
                      },
                    ),
                  ),
                  if (driverPoint == null)
                    PositionedDirectional(
                      top: 8,
                      start: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.60),
                          borderRadius: AppRadius.pillAll,
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.gps_off_rounded,
                                size: 10, color: Color(0xFFF3D278)),
                            SizedBox(width: 3),
                            Text(
                              'بانتظار موقع السائق',
                              style: TextStyle(
                                  fontSize: 8, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF14120F)
                    : const Color(0xFFFBF4DC),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.location_searching_rounded,
                    size: 26,
                    color: const Color(0xFFD4AF37)
                        .withValues(alpha: 0.55),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  const Text(
                    'بانتظار إشارة GPS',
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'سيظهر موقع السائق هنا فور بدء التوصيل.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 9.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),

          if (live?.error != null && live?.found != true)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.sm),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 12, color: colors.warning),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      live!.error!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9,
                        color: colors.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _statusLine({
    required OrderStatus status,
    required bool online,
    required bool hasDriverPoint,
    String? error,
  }) {
    if (!online) return 'سيُستأنف التتبع تلقائياً عند عودة الاتصال';
    switch (status) {
      case OrderStatus.assigned:
      case OrderStatus.accepted:
        return 'تم تعيين السائق، في انتظار انطلاقه';
      case OrderStatus.outForDelivery:
        return hasDriverPoint
            ? 'السائق في الطريق إليك — يتم التحديث تلقائياً'
            : 'السائق في الطريق — بانتظار تحديد موقعه';
      case OrderStatus.ready:
        return 'طلبيتك جاهزة وسيتم تسليمها للسائق';
      case OrderStatus.delivered:
      case OrderStatus.settled:
        return 'تم تسليم الطلبية بنجاح';
      case OrderStatus.cancelled:
      case OrderStatus.refused:
        return 'تم إلغاء الطلبية';
      default:
        return error ?? 'يتم تحديث حالة الطلب تلقائياً';
    }
  }

  String _etaLabel({
    required double? distanceKm,
    required bool isMoving,
    required bool hasDriverPoint,
    required OrderStatus status,
  }) {
    if (status == OrderStatus.delivered || status == OrderStatus.settled) {
      return 'تم التسليم';
    }
    if (!hasDriverPoint || distanceKm == null) return '—';
    if (!isMoving) return 'قريباً';
    if (distanceKm < 0.25) return 'على الأبواب';
    // Average urban delivery speed, including traffic and stops.
    final minutes = ((distanceKm / 28) * 60 + 4).clamp(2, 120).round();
    return '~$minutes دقيقة';
  }

  String _lastSeen(DateTime? at) {
    if (at == null) return '—';
    final diff = DateTime.now().difference(at.toLocal());
    if (diff.inSeconds < 45) return 'الآن';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} د';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} س';
    return 'منذ ${diff.inDays} يوم';
  }

  bool _isStale(DateTime? at) {
    if (at == null) return true;
    return DateTime.now().difference(at.toLocal()).inMinutes > 5;
  }
}

class _TrackingStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool highlight;
  final bool stale;

  const _TrackingStat({
    required this.icon,
    required this.label,
    required this.value,
    this.highlight = false,
    this.stale = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colors = context.appColors;
    final color = stale
        ? colors.warning
        : highlight
            ? (isDark ? const Color(0xFFF3D278) : const Color(0xFF9A7319))
            : theme.colorScheme.onSurface;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 10,
                color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 8.5,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _StatDivider extends StatelessWidget {
  final bool isDark;

  const _StatDivider({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 26,
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      color: const Color(0xFFD4AF37)
          .withValues(alpha: isDark ? 0.22 : 0.18),
    );
  }
}

class _MapButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _MapButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: AppGradients.gold,
          borderRadius: AppRadius.mdAll,
          boxShadow: [AppShadows.goldGlowSm],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: AppRadius.mdAll,
          child: InkWell(
            borderRadius: AppRadius.mdAll,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Icon(icon, size: 17, color: const Color(0xFF1A1400)),
            ),
          ),
        ),
      ),
    );
  }
}
