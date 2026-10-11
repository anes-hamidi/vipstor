import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:maps_launcher/maps_launcher.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:domain/domain.dart';
import 'package:ui_kit/ui_kit.dart';
import 'proof_of_delivery_dialog.dart';

class DriverMapView extends StatefulWidget {
  final List<OrderEntity> orders;
  final LatLng? driverLocation;
  final VoidCallback onOrdersUpdated;

  const DriverMapView({
    super.key,
    required this.orders,
    this.driverLocation,
    required this.onOrdersUpdated,
  });

  @override
  State<DriverMapView> createState() => _DriverMapViewState();
}

class _DriverMapViewState extends State<DriverMapView> {
  late final MapController _mapController;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
  }

  void _recenterOnDriver() {
    if (widget.driverLocation != null) {
      _mapController.move(widget.driverLocation!, 15.0);
    }
  }

  void _fitAllStops() {
    final points = <LatLng>[];
    if (widget.driverLocation != null) {
      points.add(widget.driverLocation!);
    }

    for (final order in widget.orders) {
      final lat = (order.deliveryAddress?['latitude'] as num?)?.toDouble() ?? (order.customerSnapshot?['latitude'] as num?)?.toDouble();
      final lng = (order.deliveryAddress?['longitude'] as num?)?.toDouble() ?? (order.customerSnapshot?['longitude'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        points.add(LatLng(lat, lng));
      }
    }

    if (points.isNotEmpty) {
      final bounds = LatLngBounds.fromPoints(points);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(50),
        ),
      );
    }
  }

  void _showOrderBottomSheet(OrderEntity order) {
    final lat = (order.deliveryAddress?['latitude'] as num?)?.toDouble() ?? (order.customerSnapshot?['latitude'] as num?)?.toDouble();
    final lng = (order.deliveryAddress?['longitude'] as num?)?.toDouble() ?? (order.customerSnapshot?['longitude'] as num?)?.toDouble();
    final isDelivered = order.status == OrderStatus.delivered;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.receipt_long, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'طلب #${order.orderNumber ?? order.id.substring(0, 8)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
                StatusBadge(
                  type: isDelivered ? StatusBadgeType.completed : StatusBadgeType.processing,
                  customLabel: isDelivered ? 'تم التسليم' : 'قيد التوصيل',
                ),
              ],
            ),
            const Divider(),
            Text('الزبون: ${order.customerName ?? order.customerSnapshot?['customer_name'] ?? order.customerSnapshot?['store_name'] ?? "زبون"}', style: const TextStyle(fontWeight: FontWeight.bold)),
            if (order.customerPhone != null || order.customerSnapshot?['phone'] != null)
              Text('الهاتف: ${order.customerPhone ?? order.customerSnapshot?['phone']}'),
            if (order.customerSnapshot?['address'] != null || order.customerSnapshot?['address_text'] != null)
              Text('العنوان: ${order.customerSnapshot?['address'] ?? order.customerSnapshot?['address_text']}'),
            AppSpacing.gapSm,
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('المبلغ المطلوب تحصيله:', style: TextStyle(fontWeight: FontWeight.bold)),
                DzdPriceTag(centimes: order.totalAmountCentimes, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            AppSpacing.gapLg,
            Row(
              children: [
                // 1-Tap navigation launcher
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      if (lat != null && lng != null) {
                        MapsLauncher.launchCoordinates(lat, lng, order.customerName ?? 'موقع الزبون');
                      } else {
                        final addr = order.customerSnapshot?['address'] ?? order.customerSnapshot?['address_text'] ?? 'Algeria';
                        MapsLauncher.launchQuery(addr);
                      }
                    },
                    icon: const Icon(Icons.navigation, color: Colors.blue),
                    label: const Text('الملاحة GPS'),
                  ),
                ),
                if (order.customerPhone != null || order.customerSnapshot?['phone'] != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  IconButton.outlined(
                    tooltip: 'اتصال هاتفي',
                    onPressed: () {
                      final phone = order.customerPhone ?? order.customerSnapshot?['phone'];
                      if (phone != null) launchUrl(Uri.parse('tel:$phone'));
                    },
                    icon: const Icon(Icons.call, color: Colors.green),
                  ),
                ],
                if (!isDelivered) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        showDialog(
                          context: context,
                          builder: (_) => ProofOfDeliveryDialog(
                            order: order,
                            onDelivered: widget.onOrdersUpdated,
                          ),
                        );
                      },
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('تسليم وتحصيل'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final defaultCenter = widget.driverLocation ?? const LatLng(36.7538, 3.0588); // Default Algiers

    final markers = <Marker>[];

    // Driver location marker
    if (widget.driverLocation != null) {
      markers.add(
        Marker(
          point: widget.driverLocation!,
          width: 50,
          height: 50,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue.withAlpha(50),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                ),
                child: const Icon(Icons.navigation, color: Colors.white, size: 20),
              ),
            ),
          ),
        ),
      );
    }

    // Delivery destination markers
    for (int i = 0; i < widget.orders.length; i++) {
      final order = widget.orders[i];
      final isDelivered = order.status == OrderStatus.delivered;
      // Fallback coordinate offset around Algiers if none set
      final lat = (order.deliveryAddress?['latitude'] as num?)?.toDouble() ??
          (order.customerSnapshot?['latitude'] as num?)?.toDouble() ??
          (36.7200 + (i * 0.008));
      final lng = (order.deliveryAddress?['longitude'] as num?)?.toDouble() ??
          (order.customerSnapshot?['longitude'] as num?)?.toDouble() ??
          (3.1800 + (i * 0.008));

      final stopPoint = LatLng(lat, lng);

      markers.add(
        Marker(
          point: stopPoint,
          width: 44,
          height: 44,
          child: GestureDetector(
            onTap: () => _showOrderBottomSheet(order),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDelivered ? Colors.green : Colors.deepOrange,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(isDelivered ? Icons.check : Icons.store, color: Colors.white, size: 12),
                      const SizedBox(width: 2),
                      Text(
                        '#${i + 1}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.location_on,
                  color: isDelivered ? Colors.green : Colors.deepOrange,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: defaultCenter,
            initialZoom: 13.0,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'dz.vip.wholesale.staff',
            ),
            MarkerLayer(markers: markers),
          ],
        ),
        // Floating action buttons for controls
        PositionedDirectional(
          bottom: 16,
          end: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton.small(
                heroTag: 'recenter_driver',
                tooltip: 'تمركز على موقعي',
                onPressed: _recenterOnDriver,
                child: const Icon(Icons.my_location),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.small(
                heroTag: 'fit_all_stops',
                tooltip: 'عرض جميع محطات التوصيل',
                onPressed: _fitAllStops,
                child: const Icon(Icons.zoom_out_map),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
