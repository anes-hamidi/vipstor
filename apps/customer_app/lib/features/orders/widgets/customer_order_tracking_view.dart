import 'package:customer_app/providers/customer_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:ui_kit/ui_kit.dart';

/// StreamProvider that listens in realtime to driver's live location in Supabase
final driverLiveLocationProvider = StreamProvider.autoDispose.family<Map<String, dynamic>?, String>((ref, driverId) {
  final client = ref.watch(customerSupabaseClientProvider);

  return client
      .from('driver_locations')
      .stream(primaryKey: ['driver_id'])
      .eq('driver_id', driverId)
      .map((list) {
        if (list.isEmpty) return null;
        return list.first;
      });
});

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
  ConsumerState<CustomerOrderTrackingView> createState() => _CustomerOrderTrackingViewState();
}

class _CustomerOrderTrackingViewState extends ConsumerState<CustomerOrderTrackingView> {
  late final MapController _mapController;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
  }

  @override
  Widget build(BuildContext context) {
    final liveLocationAsync = ref.watch(driverLiveLocationProvider(widget.driverId));
    final theme = Theme.of(context);

    final destPoint = (widget.destinationLat != null && widget.destinationLng != null)
        ? LatLng(widget.destinationLat!, widget.destinationLng!)
        : null;

    return Container(
      decoration: BoxDecoration(
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: theme.colorScheme.primary.withAlpha(50)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header info
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            color: theme.colorScheme.primaryContainer.withAlpha(60),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.radar_rounded, color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'تتبع مسار السائق مباشرة (${widget.driverName})',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
                liveLocationAsync.when(
                  data: (data) {
                    if (data == null) {
                      return const Text('في انتظار الإشارة...', style: TextStyle(fontSize: 11, color: Colors.grey));
                    }
                    final battery = data['battery_level'];
                    return Row(
                      children: [
                        if (battery != null) ...[
                          Icon(
                            (battery as num) < 20 ? Icons.battery_alert : Icons.battery_full,
                            size: 14,
                            color: battery < 20 ? Colors.red : Colors.green,
                          ),
                          const SizedBox(width: 2),
                          Text('$battery%', style: const TextStyle(fontSize: 11)),
                          const SizedBox(width: 6),
                        ],
                        const Icon(Icons.circle, color: Colors.green, size: 10),
                        const SizedBox(width: 4),
                        const Text('مباشر', style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold)),
                      ],
                    );
                  },
                  loading: () => const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  error: (_, __) => const Text('غير متصل', style: TextStyle(fontSize: 11, color: Colors.grey)),
                ),
              ],
            ),
          ),

          // Map View
          SizedBox(
            height: 220,
            child: liveLocationAsync.when(
              data: (data) {
                LatLng? driverPoint;
                if (data != null && data['latitude'] != null && data['longitude'] != null) {
                  driverPoint = LatLng(
                    (data['latitude'] as num).toDouble(),
                    (data['longitude'] as num).toDouble(),
                  );
                }

                final center = driverPoint ?? destPoint ?? const LatLng(36.7525, 3.042);

                final markers = <Marker>[];

                // Customer Destination Pin
                if (destPoint != null) {
                  markers.add(
                    Marker(
                      point: destPoint,
                      width: 40,
                      height: 40,
                      child: const Tooltip(
                        message: 'موقع التسليم الخاص بك',
                        child: Icon(Icons.location_on, color: Colors.red, size: 36),
                      ),
                    ),
                  );
                }

                // Driver Live Moving Pin
                if (driverPoint != null) {
                  markers.add(
                    Marker(
                      point: driverPoint,
                      width: 44,
                      height: 44,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue.shade700,
                          shape: BoxShape.circle,
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                          ],
                        ),
                        child: const Icon(Icons.local_shipping_rounded, color: Colors.white, size: 24),
                      ),
                    ),
                  );
                }

                return Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: center,
                        initialZoom: 14.5,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.vip.customer',
                        ),
                        if (driverPoint != null && destPoint != null)
                          PolylineLayer(
                            polylines: [
                              Polyline(
                                points: [driverPoint, destPoint],
                                strokeWidth: 3.5,
                                color: Colors.blueAccent,
                              ),
                            ],
                          ),
                        MarkerLayer(markers: markers),
                      ],
                    ),
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: FloatingActionButton.small(
                        heroTag: 'recenter_driver_${widget.driverId}',
                        tooltip: 'توسيط الخريطة',
                        onPressed: () {
                          if (driverPoint != null && destPoint != null) {
                            final bounds = LatLngBounds.fromPoints([driverPoint, destPoint]);
                            _mapController.fitCamera(
                              CameraFit.bounds(
                                bounds: bounds,
                                padding: const EdgeInsets.all(35),
                              ),
                            );
                          } else if (driverPoint != null) {
                            _mapController.move(driverPoint, 15.0);
                          } else if (destPoint != null) {
                            _mapController.move(destPoint, 15.0);
                          }
                        },
                        child: const Icon(Icons.my_location),
                      ),
                    ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('خطأ في تحميل الخريطة: $err')),
            ),
          ),
        ],
      ),
    );
  }
}
