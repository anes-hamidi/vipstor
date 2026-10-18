import 'package:customer_app/providers/customer_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:ui_kit/ui_kit.dart';

/// StreamProvider that listens in realtime to driver's live location in Supabase.
final driverLiveLocationProvider =
    StreamProvider.autoDispose.family<Map<String, dynamic>?, String>(
        (ref, driverId) {
  final client = ref.watch(customerSupabaseClientProvider);
  return client
      .from('driver_locations')
      .stream(primaryKey: ['driver_id'])
      .eq('driver_id', driverId)
      .map((list) => list.isEmpty ? null : list.first);
});

/// Real-time driver tracking map widget with gold-black luxury styling.
class CustomerOrderTrackingView extends ConsumerStatefulWidget {
  final String driverId;
  final String driverName;
  final String? driverPhone;
  final double? destinationLat;
  final double? destinationLng;

  const CustomerOrderTrackingView({
    super.key,
    required this.driverId,
    required this.driverName,
    this.driverPhone,
    this.destinationLat,
    this.destinationLng,
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
    final liveLocationAsync =
        ref.watch(driverLiveLocationProvider(widget.driverId));
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colors = context.appColors;

    final destPoint =
        (widget.destinationLat != null && widget.destinationLng != null)
            ? LatLng(widget.destinationLat!, widget.destinationLng!)
            : null;

    return LuxuryCard(
      goldAccent: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            child: Row(
              children: [
                // Pulsing live dot
                AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (_, __) => Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.success,
                      boxShadow: [
                        BoxShadow(
                          color: colors.success
                              .withValues(alpha: 0.30 + 0.30 * _pulseCtrl.value),
                          blurRadius: 6 + 4 * _pulseCtrl.value,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'تتبع السائق مباشرة — ${widget.driverName}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                // Live/battery status
                liveLocationAsync.when(
                  data: (data) {
                    if (data == null) {
                      return Text('في انتظار الإشارة...',
                          style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant));
                    }
                    final battery = data['battery_level'];
                    return Row(
                      children: [
                        if (battery != null) ...[
                          Icon(
                            (battery as num) < 20
                                ? Icons.battery_alert
                                : Icons.battery_full,
                            size: 13,
                            color: battery < 20
                                ? colors.cancelled
                                : colors.success,
                          ),
                          const SizedBox(width: 2),
                          Text('$battery%',
                              style: const TextStyle(fontSize: 10)),
                          const SizedBox(width: AppSpacing.sm),
                        ],
                        const GoldBadge(label: 'مباشر', small: true),
                      ],
                    );
                  },
                  loading: () => const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  error: (_, __) => Text('غير متصل',
                      style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant)),
                ),
              ],
            ),
          ),

          // ── Map ────────────────────────────────────────────────────────
          Container(
            height: 220,
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: const Color(0xFFD4AF37)
                      .withValues(alpha: isDark ? 0.20 : 0.14),
                  width: 1,
                ),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: liveLocationAsync.when(
              data: (data) => _MapView(
                data: data,
                destPoint: destPoint,
                driverId: widget.driverId,
                mapController: _mapController,
                isDark: isDark,
                colors: colors,
              ),
              loading: () => Center(child: AppStates.loading()),
              error: (err, _) => AppStates.error('خطأ في تحميل الخريطة'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapView extends StatelessWidget {
  final Map<String, dynamic>? data;
  final LatLng? destPoint;
  final String driverId;
  final MapController mapController;
  final bool isDark;
  final AppColors colors;

  const _MapView({
    required this.data,
    required this.destPoint,
    required this.driverId,
    required this.mapController,
    required this.isDark,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {

    LatLng? driverPoint;
    if (data != null &&
        data!['latitude'] != null &&
        data!['longitude'] != null) {
      driverPoint = LatLng(
        (data!['latitude'] as num).toDouble(),
        (data!['longitude'] as num).toDouble(),
      );
    }

    final center =
        driverPoint ?? destPoint ?? const LatLng(36.7525, 3.042);

    final markers = <Marker>[
      // Destination pin
      if (destPoint != null)
        Marker(
          point: destPoint!,
          width: 40,
          height: 40,
          child: Tooltip(
            message: 'موقع التسليم',
            child: Icon(Icons.location_on_rounded,
                color: colors.cancelled, size: 36),
          ),
        ),
      // Driver pin — gold-branded
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
            child: Icon(Icons.local_shipping_rounded,
                color: Color(0xFF1A1400), size: 22),
          ),
        ),
    ];

    return Stack(
      children: [
        FlutterMap(
          mapController: mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 14.5,
            maxZoom: 18.0,
            minZoom: 6.0,
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
                    points: [driverPoint, destPoint!],
                    strokeWidth: 3.5,
                    color: const Color(0xFFD4AF37),
                    strokeCap: StrokeCap.round,
                  ),
                ],
              ),
            MarkerLayer(markers: markers),
          ],
        ),
        // Re-center FAB
        Positioned(
          bottom: 8,
          right: 8,
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
                onTap: () {
                  if (driverPoint != null && destPoint != null) {
                    final bounds = LatLngBounds.fromPoints(
                        [driverPoint, destPoint!]);
                    mapController.fitCamera(CameraFit.bounds(
                      bounds: bounds,
                      padding: const EdgeInsets.all(35),
                    ));
                  } else if (driverPoint != null) {
                    mapController.move(driverPoint, 15.0);
                  } else if (destPoint != null) {
                    mapController.move(destPoint!, 15.0);
                  }
                },
                child: const Padding(
                  padding: EdgeInsets.all(AppSpacing.sm),
                  child: Icon(Icons.my_location_rounded,
                      size: 18, color: Color(0xFF1A1400)),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
