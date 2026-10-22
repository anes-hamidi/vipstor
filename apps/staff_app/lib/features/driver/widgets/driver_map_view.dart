import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:maps_launcher/maps_launcher.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:core/core.dart';
import 'package:domain/domain.dart';
import 'package:ui_kit/ui_kit.dart';

import 'delivery_order_card.dart';
import 'driver_order_utils.dart';
import 'proof_of_delivery_dialog.dart';

/// Live delivery map for the driver dashboard.
///
/// Design goals:
///  - Only real coordinates are ever plotted. Orders without a location are
///    surfaced in a dedicated "without location" section instead of being
///    scattered around a fake fallback point.
///  - Phones get the map full-bleed with a compact nearest-stop banner and a
///    draggable stop list. Tablets/desktops get a persistent route panel that
///    reuses the same [DeliveryOrderCard] as the task list.
///  - The nearest active stop is linked to the driver with a dashed gold line,
///    giving an at-a-glance sense of direction without pretending to be a real
///    road route.
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
  static const LatLng _fallbackCenter = LatLng(36.7538, 3.0588); // Algiers.
  static const double _desktopBreakpoint = 960;

  final MapController _mapController = MapController();

  bool _mapReady = false;
  String? _selectedOrderId;
  String? _lastFitSignature;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  void _handleMapReady() {
    _mapReady = true;
    _scheduleInitialFit();
  }

  @override
  void didUpdateWidget(covariant DriverMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final signature = _fitSignature(widget.orders, widget.driverLocation);
    if (signature != _lastFitSignature && _mapReady) {
      _lastFitSignature = signature;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitAllStops();
      });
    }
  }

  void _scheduleInitialFit() {
    final signature = _fitSignature(widget.orders, widget.driverLocation);
    if (_lastFitSignature == signature) return;
    _lastFitSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitAllStops();
    });
  }

  String _fitSignature(List<OrderEntity> orders, LatLng? driver) {
    final buffer = StringBuffer(driver == null ? 'no-driver' : 'driver');
    for (final order in orders) {
      buffer
        ..write('|')
        ..write(order.id)
        ..write(':')
        ..write(order.status.name);
    }
    return buffer.toString();
  }

  // ── Map actions ────────────────────────────────────────────────────────────

  void _fitAllStops() {
    if (!_mapReady) return;
    final data = _MapData.from(widget.orders, widget.driverLocation);
    final points = <LatLng>[
      if (data.driverLocation != null) data.driverLocation!,
      for (final stop in data.activeStops) stop.point,
      for (final stop in data.completedStops) stop.point,
    ];

    if (points.isEmpty) return;

    if (points.length == 1) {
      _mapController.move(points.first, 15.0);
      return;
    }

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.all(58),
        maxZoom: 15.5,
      ),
    );
  }

  void _recenterOnDriver() {
    final driver = widget.driverLocation;
    if (driver == null) {
      _showSnack('بانتظار تحديد موقعك الحالي. تأكد من تفعيل GPS.');
      return;
    }
    if (!_mapReady) return;
    _mapController.move(driver, 15.5);
  }

  void _zoomBy(double delta) {
    if (!_mapReady) return;
    final camera = _mapController.camera;
    final zoom = (camera.zoom + delta).clamp(5.0, 18.0);
    _mapController.move(camera.center, zoom);
  }

  void _selectStop(_MapStop stop) {
    setState(() => _selectedOrderId = stop.order.id);
    if (_mapReady) {
      _mapController.move(stop.point, 15.2);
    }
    _showStopDetails(stop);
  }

  // ── External actions ───────────────────────────────────────────────────────

  Future<void> _openNavigation(OrderEntity order) async {
    final latitude = orderLatitude(order);
    final longitude = orderLongitude(order);
    final address = deliveryAddressText(order) ?? 'Algeria';

    try {
      final launched = latitude != null && longitude != null
          ? await MapsLauncher.launchCoordinates(
              latitude,
              longitude,
              deliveryCustomerName(order),
            )
          : await MapsLauncher.launchQuery(address);

      if (!launched) {
        await MapsLauncher.launchQuery(address);
      }
    } catch (_) {
      _showSnack(
        'تعذر فتح تطبيق الخرائط. يمكنك نسخ العنوان والبحث عنه يدويًا.',
        isError: true,
      );
    }
  }

  Future<void> _callCustomer(OrderEntity order) async {
    final rawPhone = deliveryCustomerPhone(order);
    if (rawPhone == null) return;

    final phone = rawPhone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (phone.isEmpty) return;

    try {
      final launched = await launchUrl(Uri.parse('tel:$phone'));
      if (!launched) {
        _showSnack('تعذر بدء المكالمة على هذا الجهاز.', isError: true);
      }
    } catch (_) {
      _showSnack('تعذر بدء المكالمة على هذا الجهاز.', isError: true);
    }
  }

  void _openProofOfDelivery(OrderEntity order) {
    ProofOfDeliveryDialog.show(
      context,
      order: order,
      onDelivered: widget.onOrdersUpdated,
    );
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    final colors = context.appColors;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? colors.error : colors.success,
          behavior: SnackBarBehavior.floating,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        ),
      );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final data = _MapData.from(widget.orders, widget.driverLocation);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= _desktopBreakpoint;

        if (isDesktop) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 388,
                child: _RoutePanel(
                  data: data,
                  selectedOrderId: _selectedOrderId,
                  onRefresh: widget.onOrdersUpdated,
                  onFitMap: _fitAllStops,
                  onNavigate: _openNavigation,
                  onCall: _callCustomer,
                  onDeliver: _openProofOfDelivery,
                  onShowDetails: _showStopDetails,
                  onOpenUnlocated: (order) => _showStopDetails(
                    _MapStop(
                      order: order,
                      point: data.initialCenter,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _buildMapArea(
                  context,
                  data,
                  isDesktop: true,
                ),
              ),
            ],
          );
        }

        return _buildMapArea(context, data, isDesktop: false);
      },
    );
  }

  Widget _buildMapArea(
    BuildContext context,
    _MapData data, {
    required bool isDesktop,
  }) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    return Stack(
      children: [
        Positioned.fill(child: _buildMap(context, data)),
        if (!isDesktop)
          PositionedDirectional(
            top: AppSpacing.sm,
            start: AppSpacing.sm,
            end: AppSpacing.sm,
            child: _NearestStopBanner(
              data: data,
              onTap: () => _showStopsSheet(data),
            ),
          )
        else
          PositionedDirectional(
            top: AppSpacing.md,
            start: AppSpacing.md,
            child:
                _GpsStatusPill(hasDriverLocation: data.driverLocation != null),
          ),
        PositionedDirectional(
          end: AppSpacing.md,
          bottom: safeBottom + AppSpacing.md,
          child: _MapControls(
            showZoom: isDesktop,
            onZoomIn: () => _zoomBy(1),
            onZoomOut: () => _zoomBy(-1),
            onRecenter: _recenterOnDriver,
            onFit: _fitAllStops,
            onOpenStops: isDesktop ? null : () => _showStopsSheet(data),
          ),
        ),
      ],
    );
  }

  Widget _buildMap(BuildContext context, _MapData data) {
    final theme = Theme.of(context);
    final colors = context.appColors;

    final markers = <Marker>[
      // Completed stops first so active stops stay on top.
      for (final stop in data.completedStops) _markerFor(stop, selected: false),
      if (data.driverLocation != null)
        Marker(
          point: data.driverLocation!,
          width: 58,
          height: 58,
          child: const _DriverMarker(),
        ),
      for (final stop in data.activeStops)
        if (stop.order.id != _selectedOrderId)
          _markerFor(stop, selected: false),
      for (final stop in data.activeStops)
        if (stop.order.id == _selectedOrderId) _markerFor(stop, selected: true),
    ];

    final nearest = data.nearestStop;
    final routePoints = data.driverLocation != null && nearest != null
        ? <LatLng>[data.driverLocation!, nearest.point]
        : const <LatLng>[];

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: data.initialCenter,
        initialZoom: data.driverLocation != null ? 14.5 : 12.5,
        minZoom: 5,
        maxZoom: 18,
        onMapReady: _handleMapReady,
        onTap: (_, __) {
          if (_selectedOrderId != null) {
            setState(() => _selectedOrderId = null);
          }
        },
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'dz.vip.wholesale.staff',
          maxNativeZoom: 19,
        ),
        if (routePoints.length == 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: routePoints,
                strokeWidth: 4,
                color: colors.gold,
                borderStrokeWidth: 1.5,
                borderColor: theme.colorScheme.surface.withValues(alpha: 0.8),
                pattern: StrokePattern.dashed(segments: const [12, 8]),
              ),
              Polyline(
                points: routePoints,
                strokeWidth: 12,
                color: colors.gold.withValues(alpha: 0.12),
              ),
            ],
          ),
        MarkerLayer(markers: markers),
        RichAttributionWidget(
          alignment: Directionality.of(context) == TextDirection.rtl
              ? AttributionAlignment.bottomRight
              : AttributionAlignment.bottomLeft,
          popupBackgroundColor: theme.colorScheme.surface,
          popupBorderRadius: AppRadius.mdAll,
          attributions: [
            TextSourceAttribution(
              'OpenStreetMap contributors',
              onTap: () => launchUrl(
                Uri.parse('https://openstreetmap.org/copyright'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Marker _markerFor(_MapStop stop, {required bool selected}) {
    return Marker(
      key: ValueKey('map-stop-${stop.order.id}'),
      point: stop.point,
      width: 60,
      height: 70,
      alignment: Alignment.topCenter,
      child: _StopMarker(
        stop: stop,
        selected: selected,
        onTap: () => _selectStop(stop),
      ),
    );
  }

  // ── Mobile stop list ───────────────────────────────────────────────────────

  Future<void> _showStopsSheet(_MapData data) async {
    final theme = Theme.of(context);
    final colors = context.appColors;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          minChildSize: 0.4,
          maxChildSize: 0.94,
          builder: (context, controller) {
            return Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(26),
                ),
                border: Border.all(
                  color: colors.gold.withValues(alpha: 0.32),
                ),
                boxShadow: AppShadows.dialogLuxury,
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SheetHandle(),
                  _SheetHeader(
                    icon: Icons.route_rounded,
                    title: 'محطات اليوم',
                    subtitle: _stopsSummary(data),
                    onClose: () => Navigator.of(sheetContext).pop(),
                  ),
                  const GoldDivider(
                    margin: EdgeInsetsDirectional.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      controller: controller,
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        AppSpacing.lg,
                        AppSpacing.sm,
                        AppSpacing.lg,
                        AppSpacing.xl,
                      ),
                      children: [
                        if (data.activeStops.isEmpty &&
                            data.completedStops.isEmpty &&
                            data.unlocatedOrders.isEmpty)
                          const _EmptyStopsState()
                        else ...[
                          if (data.activeStops.isNotEmpty) ...[
                            SectionHeader(
                              title: 'المحطات النشطة',
                              trailing: _CountChip(
                                label: '${data.activeStops.length}',
                              ),
                            ),
                            for (final stop in data.activeStops)
                              Padding(
                                padding: const EdgeInsetsDirectional.only(
                                  bottom: AppSpacing.md,
                                ),
                                child: DeliveryOrderCard(
                                  order: stop.order,
                                  stopNumber: stop.sequence,
                                  distanceKm: stop.distanceKm,
                                  highlighted:
                                      _selectedOrderId == stop.order.id,
                                  onNavigate: () => _openNavigation(stop.order),
                                  onCall: () => _callCustomer(stop.order),
                                  onDeliver: () => _deliverFromSheet(
                                      sheetContext, stop.order),
                                ),
                              ),
                          ],
                          if (data.completedStops.isNotEmpty) ...[
                            SectionHeader(
                              title: 'تم إنجازها',
                              trailing: _CountChip(
                                label: '${data.completedStops.length}',
                                muted: true,
                              ),
                            ),
                            for (final stop in data.completedStops)
                              Padding(
                                padding: const EdgeInsetsDirectional.only(
                                  bottom: AppSpacing.sm,
                                ),
                                child: _CompletedStopTile(
                                  stop: stop,
                                  onTap: () => _showStopDetails(stop),
                                ),
                              ),
                          ],
                          if (data.unlocatedOrders.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.sm),
                            _UnlocatedSection(
                              orders: data.unlocatedOrders,
                              onNavigate: _openNavigation,
                              onCall: _callCustomer,
                              onShowDetails: (order) => _showStopDetails(
                                _MapStop(
                                  order: order,
                                  point: data.initialCenter,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _deliverFromSheet(
    BuildContext sheetContext,
    OrderEntity order,
  ) async {
    Navigator.of(sheetContext).pop();
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (mounted) _openProofOfDelivery(order);
  }

  String _stopsSummary(_MapData data) {
    final parts = <String>[
      if (data.activeStops.isNotEmpty) '${data.activeStops.length} نشطة',
      if (data.completedStops.isNotEmpty)
        '${data.completedStops.length} مكتملة',
      if (data.unlocatedOrders.isNotEmpty)
        '${data.unlocatedOrders.length} بدون موقع',
    ];
    return parts.isEmpty ? 'لا توجد مهام مسندة' : parts.join(' • ');
  }

  // ── Stop details ───────────────────────────────────────────────────────────

  Future<void> _showStopDetails(_MapStop stop) async {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final isCompact = MediaQuery.sizeOf(context).width < 720;
    final order = stop.order;
    final isActive = isOrderActive(order.status);

    Widget buildCard(BuildContext routeContext) {
      return DeliveryOrderCard(
        order: order,
        stopNumber: stop.sequence,
        distanceKm: stop.distanceKm,
        onNavigate: () => _openNavigation(order),
        onCall: () => _callCustomer(order),
        onDeliver: isActive
            ? () async {
                Navigator.of(routeContext).pop();
                await Future<void>.delayed(const Duration(milliseconds: 220));
                if (mounted) _openProofOfDelivery(order);
              }
            : null,
      );
    }

    if (isCompact) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) {
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.7,
            minChildSize: 0.42,
            maxChildSize: 0.95,
            builder: (context, controller) {
              return Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(26),
                  ),
                  border: Border.all(
                    color: colors.gold.withValues(alpha: 0.32),
                  ),
                  boxShadow: AppShadows.dialogLuxury,
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SheetHandle(),
                    _SheetHeader(
                      icon: Icons.location_on_rounded,
                      title: stop.sequence != null
                          ? 'المحطة #${stop.sequence}'
                          : 'تفاصيل المهمة',
                      subtitle: deliveryCustomerName(order),
                      onClose: () => Navigator.of(sheetContext).pop(),
                    ),
                    const GoldDivider(
                      margin: EdgeInsetsDirectional.symmetric(
                        horizontal: AppSpacing.lg,
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        controller: controller,
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          AppSpacing.lg,
                          AppSpacing.sm,
                          AppSpacing.lg,
                          AppSpacing.xl,
                        ),
                        children: [buildCard(sheetContext)],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(AppSpacing.xl),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 560,
              maxHeight: (MediaQuery.sizeOf(context).height - 64).clamp(
                360.0,
                780.0,
              ),
            ),
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: AppRadius.xxlAll,
                border: Border.all(
                  color: colors.gold.withValues(alpha: 0.32),
                ),
                boxShadow: AppShadows.dialogLuxury,
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SheetHeader(
                    icon: Icons.location_on_rounded,
                    title: stop.sequence != null
                        ? 'المحطة #${stop.sequence}'
                        : 'تفاصيل المهمة',
                    subtitle: deliveryCustomerName(order),
                    onClose: () => Navigator.of(dialogContext).pop(),
                  ),
                  const GoldDivider(
                    margin: EdgeInsetsDirectional.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        AppSpacing.lg,
                        AppSpacing.sm,
                        AppSpacing.lg,
                        AppSpacing.lg,
                      ),
                      child: buildCard(dialogContext),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Map data
// ─────────────────────────────────────────────────────────────────────────────

class _MapStop {
  final OrderEntity order;
  final LatLng point;
  final bool active;
  final int? sequence;
  final double? distanceKm;

  const _MapStop({
    required this.order,
    required this.point,
    this.active = false,
    this.sequence,
    this.distanceKm,
  });

  _MapStop withSequence(int number) => _MapStop(
        order: order,
        point: point,
        active: active,
        sequence: number,
        distanceKm: distanceKm,
      );
}

class _MapData {
  final List<_MapStop> activeStops;
  final List<_MapStop> completedStops;
  final List<OrderEntity> unlocatedOrders;
  final LatLng? driverLocation;

  const _MapData({
    required this.activeStops,
    required this.completedStops,
    required this.unlocatedOrders,
    required this.driverLocation,
  });

  factory _MapData.from(
    List<OrderEntity> orders,
    LatLng? driverLocation,
  ) {
    const distance = Distance(roundResult: false);
    final active = <_MapStop>[];
    final completed = <_MapStop>[];
    final unlocated = <OrderEntity>[];

    for (final order in orders) {
      final isActive = isOrderActive(order.status);
      final isCompleted = order.status == OrderStatus.delivered ||
          order.status == OrderStatus.settled;

      // Cancelled/refused orders are not part of today's route and should not
      // distract the driver with a marker or a "without location" warning.
      if (!isActive && !isCompleted) continue;

      final latitude = orderLatitude(order);
      final longitude = orderLongitude(order);
      if (latitude == null || longitude == null) {
        unlocated.add(order);
        continue;
      }

      final point = LatLng(latitude, longitude);
      final distanceKm = driverLocation == null
          ? null
          : distance.as(LengthUnit.Kilometer, driverLocation, point);
      final stop = _MapStop(
        order: order,
        point: point,
        active: isActive,
        distanceKm: distanceKm,
      );

      if (stop.active) {
        active.add(stop);
      } else {
        completed.add(stop);
      }
    }

    active.sort((a, b) {
      final distanceCompare = (a.distanceKm ?? double.infinity).compareTo(
        b.distanceKm ?? double.infinity,
      );
      if (distanceCompare != 0) return distanceCompare;
      return b.order.createdAt.compareTo(a.order.createdAt);
    });

    final numbered = <_MapStop>[
      for (var i = 0; i < active.length; i++) active[i].withSequence(i + 1),
    ];

    completed.sort((a, b) => b.order.createdAt.compareTo(a.order.createdAt));
    unlocated.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return _MapData(
      activeStops: numbered,
      completedStops: completed,
      unlocatedOrders: unlocated,
      driverLocation: driverLocation,
    );
  }

  _MapStop? get nearestStop => activeStops.isEmpty ? null : activeStops.first;

  int get expectedCollectionCentimes => activeStops.fold(
        0,
        (total, stop) => total + stop.order.dueAmountCentimes,
      );

  LatLng get initialCenter {
    if (driverLocation != null) return driverLocation!;
    if (activeStops.isNotEmpty) return activeStops.first.point;
    if (completedStops.isNotEmpty) return completedStops.first.point;
    return _DriverMapViewState._fallbackCenter;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Desktop route panel
// ─────────────────────────────────────────────────────────────────────────────

class _RoutePanel extends StatelessWidget {
  final _MapData data;
  final String? selectedOrderId;
  final VoidCallback onRefresh;
  final VoidCallback onFitMap;
  final ValueChanged<OrderEntity> onNavigate;
  final ValueChanged<OrderEntity> onCall;
  final ValueChanged<OrderEntity> onDeliver;
  final ValueChanged<_MapStop> onShowDetails;
  final ValueChanged<OrderEntity> onOpenUnlocated;

  const _RoutePanel({
    required this.data,
    required this.selectedOrderId,
    required this.onRefresh,
    required this.onFitMap,
    required this.onNavigate,
    required this.onCall,
    required this.onDeliver,
    required this.onShowDetails,
    required this.onOpenUnlocated,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final nearest = data.nearestStop;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: BorderDirectional(
          end: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
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
                    width: 42,
                    height: 42,
                    decoration: const BoxDecoration(
                      gradient: AppGradients.gold,
                      borderRadius: AppRadius.mdAll,
                      boxShadow: [AppShadows.goldGlowSm],
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.route_rounded,
                      size: 22,
                      color: Color(0xFF1A1400),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'مسار التوصيل',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          data.driverLocation != null
                              ? 'مرتب حسب الأقرب إلى موقعك'
                              : 'بانتظار GPS لترتيب المحطات',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _MapControlButton(
                    icon: Icons.zoom_out_map_rounded,
                    tooltip: 'عرض جميع المحطات',
                    onPressed: onFitMap,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  _MapControlButton(
                    icon: Icons.refresh_rounded,
                    tooltip: 'تحديث المهام',
                    onPressed: onRefresh,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _PanelStat(
                      icon: Icons.pin_drop_outlined,
                      label: 'محطات نشطة',
                      value: '${data.activeStops.length}',
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _PanelStat(
                      icon: Icons.payments_outlined,
                      label: 'تحصيل متوقع',
                      value: '${DzdFormatter.formatCentimes(
                        data.expectedCollectionCentimes,
                        showDecimals: false,
                      )} دج',
                      accent: colors.gold,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _PanelStat(
                      icon: Icons.near_me_outlined,
                      label: 'أقرب محطة',
                      value: nearest?.distanceKm != null
                          ? formatDistanceKm(nearest!.distanceKm)
                          : '—',
                    ),
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
              child: ListView(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.xl,
                ),
                children: [
                  if (data.activeStops.isEmpty &&
                      data.completedStops.isEmpty &&
                      data.unlocatedOrders.isEmpty)
                    _EmptyStopsState(onRefresh: onRefresh)
                  else ...[
                    if (data.activeStops.isNotEmpty) ...[
                      SectionHeader(
                        title: 'المحطات النشطة',
                        trailing: _CountChip(
                          label: '${data.activeStops.length}',
                        ),
                      ),
                      for (final stop in data.activeStops)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(
                            bottom: AppSpacing.md,
                          ),
                          child: DeliveryOrderCard(
                            order: stop.order,
                            stopNumber: stop.sequence,
                            distanceKm: stop.distanceKm,
                            highlighted: selectedOrderId == stop.order.id,
                            onNavigate: () => onNavigate(stop.order),
                            onCall: () => onCall(stop.order),
                            onDeliver: () => onDeliver(stop.order),
                          ),
                        ),
                    ],
                    if (data.completedStops.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xs),
                      _CompletedStopsExpansion(
                        stops: data.completedStops,
                        onTap: onShowDetails,
                      ),
                    ],
                    if (data.unlocatedOrders.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.md),
                      _UnlocatedSection(
                        orders: data.unlocatedOrders,
                        onNavigate: onNavigate,
                        onCall: onCall,
                        onShowDetails: onOpenUnlocated,
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? accent;

  const _PanelStat({
    required this.icon,
    required this.label,
    required this.value,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final color = accent ?? theme.colorScheme.onSurface;

    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.mdAll,
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: colors.gold),
              const SizedBox(width: 3),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 9.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Map chrome
// ─────────────────────────────────────────────────────────────────────────────

class _NearestStopBanner extends StatelessWidget {
  final _MapData data;
  final VoidCallback onTap;

  const _NearestStopBanner({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final nearest = data.nearestStop;

    final title =
        nearest == null ? 'محطات التوصيل' : deliveryCustomerName(nearest.order);
    final subtitle = nearest == null
        ? (data.unlocatedOrders.isNotEmpty
            ? '${data.unlocatedOrders.length} مهمة بدون موقع محدد'
            : 'لا توجد مهام نشطة حالياً')
        : 'أقرب محطة • ${formatDistanceKm(nearest.distanceKm)}';

    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.97),
      borderRadius: AppRadius.lgAll,
      elevation: 6,
      shadowColor: Colors.black26,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.lgAll,
        child: Container(
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.sm,
            AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: AppRadius.lgAll,
            border: Border.all(color: colors.gold.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  gradient: AppGradients.gold,
                  borderRadius: AppRadius.mdAll,
                  boxShadow: [AppShadows.goldGlowSm],
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.near_me_rounded,
                  size: 20,
                  color: Color(0xFF1A1400),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      subtitle,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              _CountChip(
                label: '${data.activeStops.length}',
                icon: Icons.pin_drop_outlined,
              ),
              Icon(
                Icons.keyboard_arrow_up_rounded,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GpsStatusPill extends StatelessWidget {
  final bool hasDriverLocation;

  const _GpsStatusPill({required this.hasDriverLocation});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final color =
        hasDriverLocation ? colors.success : theme.colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.95),
        borderRadius: AppRadius.pillAll,
        border: Border.all(color: color.withValues(alpha: 0.3)),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasDriverLocation ? Icons.gps_fixed_rounded : Icons.gps_off_rounded,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            hasDriverLocation ? 'موقعك مباشر' : 'بانتظار GPS',
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MapControls extends StatelessWidget {
  final bool showZoom;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onRecenter;
  final VoidCallback onFit;
  final VoidCallback? onOpenStops;

  const _MapControls({
    required this.showZoom,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onRecenter,
    required this.onFit,
    this.onOpenStops,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showZoom) ...[
          _MapControlButton(
            icon: Icons.add_rounded,
            tooltip: 'تكبير الخريطة',
            onPressed: onZoomIn,
          ),
          const SizedBox(height: AppSpacing.xs),
          _MapControlButton(
            icon: Icons.remove_rounded,
            tooltip: 'تصغير الخريطة',
            onPressed: onZoomOut,
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        _MapControlButton(
          icon: Icons.my_location_rounded,
          tooltip: 'العودة إلى موقعي',
          onPressed: onRecenter,
          accent: true,
        ),
        const SizedBox(height: AppSpacing.xs),
        _MapControlButton(
          icon: Icons.zoom_out_map_rounded,
          tooltip: 'عرض جميع المحطات',
          onPressed: onFit,
        ),
        if (onOpenStops != null) ...[
          const SizedBox(height: AppSpacing.xs),
          _MapControlButton(
            icon: Icons.format_list_bulleted_rounded,
            tooltip: 'قائمة المحطات',
            onPressed: onOpenStops!,
          ),
        ],
      ],
    );
  }
}

class _MapControlButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool accent;

  const _MapControlButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final background = accent ? colors.gold : theme.colorScheme.surface;
    final foreground =
        accent ? const Color(0xFF1A1400) : theme.colorScheme.onSurface;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: background.withValues(alpha: 0.97),
        borderRadius: AppRadius.mdAll,
        elevation: 4,
        shadowColor: Colors.black26,
        child: InkWell(
          onTap: onPressed,
          borderRadius: AppRadius.mdAll,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: AppRadius.mdAll,
              border: Border.all(
                color: accent
                    ? colors.goldLight.withValues(alpha: 0.6)
                    : colors.gold.withValues(alpha: 0.3),
              ),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 20, color: foreground),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Markers
// ─────────────────────────────────────────────────────────────────────────────

class _StopMarker extends StatelessWidget {
  final _MapStop stop;
  final bool selected;
  final VoidCallback onTap;

  const _StopMarker({
    required this.stop,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final active = stop.active;
    final pinColor = active ? colors.gold : colors.success;
    final pinSize = selected ? 60.0 : 52.0;
    final discSize = selected ? 34.0 : 30.0;

    return Tooltip(
      message: stop.sequence != null
          ? 'المحطة #${stop.sequence} • ${deliveryCustomerName(stop.order)}'
          : deliveryCustomerName(stop.order),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 60,
          height: 70,
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              if (selected)
                Positioned(
                  top: -4,
                  child: Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: pinColor.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              Positioned(
                bottom: 0,
                child: Icon(
                  Icons.location_on_rounded,
                  size: pinSize,
                  color: pinColor,
                  shadows: const [
                    Shadow(
                      color: Colors.black26,
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: selected ? 4 : 5,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: discSize,
                  height: discSize,
                  decoration: BoxDecoration(
                    color: active ? const Color(0xFF1A1400) : colors.success,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: active ? pinColor : colors.onSuccess,
                      width: 1.5,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: active
                      ? Text(
                          '${stop.sequence ?? '•'}',
                          style: TextStyle(
                            color: pinColor,
                            fontSize: selected ? 14 : 12,
                            fontWeight: FontWeight.w900,
                          ),
                        )
                      : Icon(
                          Icons.check_rounded,
                          size: selected ? 19 : 17,
                          color: colors.onSuccess,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DriverMarker extends StatelessWidget {
  const _DriverMarker();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Tooltip(
      message: 'موقعك الحالي',
      child: Container(
        decoration: BoxDecoration(
          color: colors.gold.withValues(alpha: 0.16),
          shape: BoxShape.circle,
          border: Border.all(color: colors.gold.withValues(alpha: 0.4)),
        ),
        alignment: Alignment.center,
        child: Container(
          width: 38,
          height: 38,
          decoration: const BoxDecoration(
            gradient: AppGradients.gold,
            shape: BoxShape.circle,
            boxShadow: [AppShadows.goldGlow],
          ),
          child: const Icon(
            Icons.local_shipping_rounded,
            size: 20,
            color: Color(0xFF1A1400),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Route panel building blocks
// ─────────────────────────────────────────────────────────────────────────────

class _CompletedStopsExpansion extends StatelessWidget {
  final List<_MapStop> stops;
  final ValueChanged<_MapStop> onTap;

  const _CompletedStopsExpansion({required this.stops, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.65),
        borderRadius: AppRadius.mdAll,
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.md,
          ),
          childrenPadding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.sm,
            0,
            AppSpacing.sm,
            AppSpacing.sm,
          ),
          iconColor: colors.gold,
          collapsedIconColor: theme.colorScheme.onSurfaceVariant,
          leading: Icon(
            Icons.task_alt_rounded,
            size: 18,
            color: colors.success,
          ),
          title: Text(
            'تم إنجازها (${stops.length})',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          children: [
            for (final stop in stops)
              _CompletedStopTile(stop: stop, onTap: () => onTap(stop)),
          ],
        ),
      ),
    );
  }
}

class _CompletedStopTile extends StatelessWidget {
  final _MapStop stop;
  final VoidCallback onTap;

  const _CompletedStopTile({required this.stop, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final order = stop.order;
    final paid = order.paidAmountCentimes > 0
        ? DzdFormatter.formatCentimes(
            order.paidAmountCentimes,
            showDecimals: false,
          )
        : '0';

    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.smAll,
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(
              order.status == OrderStatus.settled
                  ? Icons.verified_rounded
                  : Icons.check_circle_rounded,
              size: 17,
              color: colors.success,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
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
                    'طلب #${orderShortNumber(order)} • ${formatTimeAgo(order.createdAt)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '$paid دج',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.success,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.chevron_left_rounded,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _UnlocatedSection extends StatelessWidget {
  final List<OrderEntity> orders;
  final ValueChanged<OrderEntity> onNavigate;
  final ValueChanged<OrderEntity> onCall;
  final ValueChanged<OrderEntity> onShowDetails;

  const _UnlocatedSection({
    required this.orders,
    required this.onNavigate,
    required this.onCall,
    required this.onShowDetails,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;

    return Container(
      decoration: BoxDecoration(
        color: colors.warningContainer.withValues(alpha: 0.32),
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: colors.warning.withValues(alpha: 0.3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.location_off_outlined,
                  size: 17,
                  color: colors.warning,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'مهام بدون إحداثيات (${orders.length})',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colors.onWarningContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Text(
              'لم يسجل الزبون موقعًا على الخريطة. استخدم العنوان أو الاتصال للوصول إليه.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onWarningContainer,
                height: 1.4,
              ),
            ),
          ),
          for (final order in orders)
            _UnlocatedOrderTile(
              order: order,
              onNavigate: () => onNavigate(order),
              onCall: () => onCall(order),
              onShowDetails: () => onShowDetails(order),
            ),
        ],
      ),
    );
  }
}

class _UnlocatedOrderTile extends StatelessWidget {
  final OrderEntity order;
  final VoidCallback onNavigate;
  final VoidCallback onCall;
  final VoidCallback onShowDetails;

  const _UnlocatedOrderTile({
    required this.order,
    required this.onNavigate,
    required this.onCall,
    required this.onShowDetails,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final address = deliveryAddressText(order) ?? 'عنوان غير مسجل';
    final hasPhone = deliveryCustomerPhone(order) != null;

    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.55),
      child: InkWell(
        onTap: onShowDetails,
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 7,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
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
                      address,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              IconButton(
                tooltip: 'الملاحة بالعنوان',
                visualDensity: VisualDensity.compact,
                onPressed: onNavigate,
                icon: Icon(
                  Icons.navigation_rounded,
                  size: 17,
                  color: colors.gold,
                ),
              ),
              if (hasPhone)
                IconButton(
                  tooltip: 'اتصال بالزبون',
                  visualDensity: VisualDensity.compact,
                  onPressed: onCall,
                  icon: Icon(
                    Icons.call_rounded,
                    size: 17,
                    color: colors.success,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared sheet pieces
// ─────────────────────────────────────────────────────────────────────────────

class _SheetHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Center(
      child: Container(
        width: 42,
        height: 4,
        margin: const EdgeInsetsDirectional.only(top: AppSpacing.sm),
        decoration: BoxDecoration(
          color: colors.gold.withValues(alpha: 0.35),
          borderRadius: AppRadius.pillAll,
        ),
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onClose;

  const _SheetHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: colors.goldMuted,
              borderRadius: AppRadius.mdAll,
              border: Border.all(color: colors.goldBorder),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 20, color: colors.gold),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'إغلاق',
            onPressed: onClose,
            icon: Icon(
              Icons.close_rounded,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  final String label;
  final bool muted;
  final IconData? icon;

  const _CountChip({required this.label, this.muted = false, this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final color = muted ? theme.colorScheme.onSurfaceVariant : colors.gold;

    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: AppRadius.pillAll,
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyStopsState extends StatelessWidget {
  final VoidCallback? onRefresh;

  const _EmptyStopsState({this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(
        vertical: AppSpacing.xxl,
        horizontal: AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: colors.goldMuted,
              shape: BoxShape.circle,
              border: Border.all(color: colors.goldBorder),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.route_outlined,
              size: 28,
              color: colors.gold,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'لا توجد مهام توصيل',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'ستظهر هنا محطات اليوم فور إسناد مهام جديدة إليك.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          if (onRefresh != null) ...[
            const SizedBox(height: AppSpacing.sm),
            TextButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded, size: 17),
              label: const Text('تحديث المهام'),
            ),
          ],
        ],
      ),
    );
  }
}
