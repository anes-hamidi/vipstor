import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:maps_launcher/maps_launcher.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:core/core.dart';
import 'package:domain/domain.dart';
import '../../providers/staff_providers.dart';
import '../../router/staff_router.dart';
import 'services/driver_telemetry_service.dart';
import 'widgets/driver_map_view.dart';
import 'widgets/proof_of_delivery_dialog.dart';

final driverOrdersProvider = FutureProvider<List<OrderEntity>>((ref) async {
  final repo = ref.watch(orderRepositoryProvider);
  final user = ref.watch(authStateProvider);
  if (user == null) return [];
  return repo.getOrders(driverId: user.id);
});

final driverWalletBalanceProvider = FutureProvider<int>((ref) async {
  final repo = ref.watch(settlementRepositoryProvider);
  final user = ref.watch(authStateProvider);
  if (user == null) return 0;
  return repo.getDriverExpectedWallet(user.id);
});

class DriverDeliveriesScreen extends ConsumerStatefulWidget {
  const DriverDeliveriesScreen({super.key});

  @override
  ConsumerState<DriverDeliveriesScreen> createState() => _DriverDeliveriesScreenState();
}

class _DriverDeliveriesScreenState extends ConsumerState<DriverDeliveriesScreen> {
  final DriverTelemetryService _telemetry = DriverTelemetryService();
  bool _isMapView = false;

  @override
  void initState() {
    super.initState();
    _telemetry.addListener(_onTelemetryUpdate);
  }

  @override
  void dispose() {
    _telemetry.removeListener(_onTelemetryUpdate);
    super.dispose();
  }

  void _onTelemetryUpdate() {
    if (mounted) setState(() {});
  }

  void _refresh() {
    ref.invalidate(driverOrdersProvider);
    ref.invalidate(driverWalletBalanceProvider);
  }

  void _openProofOfDeliveryDialog(OrderEntity order) {
    showDialog(
      context: context,
      builder: (_) => ProofOfDeliveryDialog(
        order: order,
        onDelivered: _refresh,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(driverOrdersProvider);
    final walletAsync = ref.watch(driverWalletBalanceProvider);
    final authUser = ref.watch(authStateProvider);
    if (authUser != null) {
      _telemetry.setDriverId(authUser.id);
    }
    final theme = Theme.of(context);
    final telemetryState = _telemetry.state;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.local_shipping_rounded),
            const SizedBox(width: AppSpacing.sm),
            Text('مهام التوصيل والملاحة - ${authUser?.name ?? "السائق"}'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _isMapView ? 'عرض القائمة' : 'عرض الخريطة المباشرة',
            icon: Icon(_isMapView ? Icons.view_list_rounded : Icons.map_rounded),
            onPressed: () => setState(() => _isMapView = !_isMapView),
          ),
          IconButton(
            tooltip: 'تحديث المهام والمحفظة',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
          IconButton(
            tooltip: 'تسجيل الخروج',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authStateProvider.notifier).state = null,
          ),
        ],
      ),
      body: Column(
        children: [
          // ----------------------------------------------------
          // Top Telemetry Bar (Battery, Wakelock, GPS, Background)
          // ----------------------------------------------------
          Container(
            color: theme.colorScheme.surfaceContainer,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Battery status
                Row(
                  children: [
                    Icon(
                      telemetryState.batteryState == BatteryState.charging
                          ? Icons.battery_charging_full
                          : (telemetryState.isLowBattery ? Icons.battery_alert : Icons.battery_full),
                      color: telemetryState.isLowBattery ? Colors.red : Colors.green,
                      size: 20,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${telemetryState.batteryLevel}%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: telemetryState.isLowBattery ? Colors.red : null,
                      ),
                    ),
                  ],
                ),
                // GPS indicator
                Row(
                  children: [
                    Icon(
                      telemetryState.currentPosition != null ? Icons.gps_fixed : Icons.gps_not_fixed,
                      color: telemetryState.currentPosition != null ? Colors.blue : Colors.grey,
                      size: 18,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      telemetryState.currentPosition != null
                          ? '${telemetryState.currentPosition!.latitude.toStringAsFixed(3)}, ${telemetryState.currentPosition!.longitude.toStringAsFixed(3)}'
                          : 'GPS نشط',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
                // Wakelock toggle
                InkWell(
                  onTap: () => _telemetry.toggleWakelock(!telemetryState.isWakelockEnabled),
                  borderRadius: AppRadius.smAll,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      children: [
                        Icon(
                          telemetryState.isWakelockEnabled ? Icons.screen_lock_portrait : Icons.screen_lock_portrait_outlined,
                          size: 16,
                          color: telemetryState.isWakelockEnabled ? Colors.orange : Colors.grey,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          telemetryState.isWakelockEnabled ? 'الشاشة مفعلة' : 'قفل الشاشة',
                          style: TextStyle(fontSize: 11, color: telemetryState.isWakelockEnabled ? Colors.orange.shade800 : Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
                // Background service toggle
                InkWell(
                  onTap: () => _telemetry.toggleBackgroundTracking(!telemetryState.isBackgroundServiceActive),
                  borderRadius: AppRadius.smAll,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      children: [
                        Icon(
                          Icons.radar,
                          size: 16,
                          color: telemetryState.isBackgroundServiceActive ? Colors.green : Colors.grey,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          telemetryState.isBackgroundServiceActive ? 'تتبع بالخلفية' : 'تتبع عادي',
                          style: TextStyle(fontSize: 11, color: telemetryState.isBackgroundServiceActive ? Colors.green : Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ----------------------------------------------------
          // Main Body: List View or Interactive OSM Map View
          // ----------------------------------------------------
          Expanded(
            child: ordersAsync.when(
              data: (orders) {
                if (_isMapView) {
                  final driverLatLng = telemetryState.currentPosition != null
                      ? LatLng(telemetryState.currentPosition!.latitude, telemetryState.currentPosition!.longitude)
                      : null;

                  return DriverMapView(
                    orders: orders,
                    driverLocation: driverLatLng,
                    onOrdersUpdated: _refresh,
                  );
                }

                return ContentConstrainedBox.dashboard(
                  padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Driver Wallet KPI Card
                      walletAsync.when(
                        data: (balanceCentimes) => KpiCard(
                          title: 'الكاش الإجمالي في عهدتك حالياً (Wallet Balance)',
                          value: DzdFormatter.formatCentimes(balanceCentimes),
                          icon: Icons.account_balance_wallet_outlined,
                          subtitle: 'يتم تسليم هذه المبالغ للمشرف بنهاية جولة التوصيل',
                          accentColor: context.appColors.warning,
                        ),
                        loading: () => const LinearProgressIndicator(),
                        error: (_, __) => const SizedBox.shrink(),
                      ),
                      AppSpacing.gapMd,
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'الطلبات الموكلة إليك (${orders.length}):',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: () => setState(() => _isMapView = true),
                            icon: const Icon(Icons.map, size: 16),
                            label: const Text('عرض الخريطة وتوزيع المحطات'),
                          ),
                        ],
                      ),
                      AppSpacing.gapSm,
                      Expanded(
                        child: orders.isEmpty
                            ? const AppEmptyView(
                                icon: Icons.local_shipping_outlined,
                                title: 'لا توجد طلبات توصيل موكلة إليك حاليًا',
                                description: 'ستظهر الطلبات الجديدة هنا بمجرد تعيينها لك من طرف مسؤول المخزون.',
                              )
                            : ListView.separated(
                                itemCount: orders.length,
                                separatorBuilder: (_, __) => AppSpacing.gapMd,
                                itemBuilder: (context, index) {
                                  final order = orders[index];
                                  final isDelivered = order.status == OrderStatus.delivered;
                                  final lat = (order.deliveryAddress?['latitude'] as num?)?.toDouble() ??
                                      (order.customerSnapshot?['latitude'] as num?)?.toDouble();
                                  final lng = (order.deliveryAddress?['longitude'] as num?)?.toDouble() ??
                                      (order.customerSnapshot?['longitude'] as num?)?.toDouble();

                                  return Card(
                                    child: Padding(
                                      padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Row(
                                                children: [
                                                  const Icon(Icons.receipt_long, size: 20),
                                                  const SizedBox(width: AppSpacing.xs),
                                                  Text(
                                                    'طلب رقم #${order.orderNumber ?? order.id.substring(0, 8)}',
                                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
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
                                          if (order.customerSnapshot != null) ...[
                                            Row(
                                              children: [
                                                const Icon(Icons.storefront, size: 16),
                                                const SizedBox(width: AppSpacing.xs),
                                                Text(
                                                  'المحل: ${order.customerSnapshot?['store_name'] ?? order.customerSnapshot?['customer_name'] ?? order.customerSnapshot?['full_name'] ?? "زبون"}',
                                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                                ),
                                              ],
                                            ),
                                            if (order.customerSnapshot?['phone'] != null || order.customerSnapshot?['customer_phone'] != null) ...[
                                              const SizedBox(height: AppSpacing.xs),
                                              Row(
                                                children: [
                                                  const Icon(Icons.phone, size: 16),
                                                  const SizedBox(width: AppSpacing.xs),
                                                  Text('الهاتف: ${order.customerSnapshot?['phone'] ?? order.customerSnapshot?['customer_phone']}'),
                                                ],
                                              ),
                                            ],
                                            if (order.customerSnapshot?['address'] != null || order.customerSnapshot?['address_text'] != null) ...[
                                              const SizedBox(height: AppSpacing.xs),
                                              Row(
                                                children: [
                                                  const Icon(Icons.location_on_outlined, size: 16),
                                                  const SizedBox(width: AppSpacing.xs),
                                                  Expanded(
                                                    child: Text(
                                                      'العنوان: ${order.customerSnapshot?['address'] ?? order.customerSnapshot?['address_text']}',
                                                      style: theme.textTheme.bodySmall,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                            AppSpacing.gapSm,
                                          ],
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Row(
                                                children: [
                                                  const Text('المبلغ المطلوب تحصيله: ', style: TextStyle(fontWeight: FontWeight.bold)),
                                                  DzdPriceTag(centimes: order.totalAmountCentimes),
                                                ],
                                              ),
                                              Text('${order.items.length} أصناف', style: theme.textTheme.bodySmall),
                                            ],
                                          ),
                                          AppSpacing.gapMd,
                                          Row(
                                            children: [
                                              // 1-Tap navigation launcher
                                              Expanded(
                                                child: OutlinedButton.icon(
                                                  onPressed: () {
                                                    if (lat != null && lng != null) {
                                                      MapsLauncher.launchCoordinates(lat, lng, order.customerName ?? 'عنوان الزبون');
                                                    } else {
                                                      final query = order.customerSnapshot?['address'] ??
                                                          order.customerSnapshot?['address_text'] ??
                                                          'Algeria';
                                                      MapsLauncher.launchQuery(query);
                                                    }
                                                  },
                                                  icon: const Icon(Icons.navigation_outlined, color: Colors.blue),
                                                  label: const Text('الملاحة GPS'),
                                                ),
                                              ),
                                              if (order.customerPhone != null || order.customerSnapshot?['phone'] != null) ...[
                                                const SizedBox(width: AppSpacing.sm),
                                                IconButton.outlined(
                                                  tooltip: 'اتصال هاتفي بالزبون',
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
                                                    onPressed: () => _openProofOfDeliveryDialog(order),
                                                    icon: const Icon(Icons.check_circle_outline),
                                                    label: const Text('تسليم وإثبات'),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
              loading: () => const AppLoadingView(message: 'جاري جلب مهام التوصيل...'),
              error: (err, _) => AppErrorView(
                message: 'تعذر تحميل مهام التوصيل',
                onRetry: _refresh,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
