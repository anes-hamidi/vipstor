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
import 'widgets/driver_wallet_sheet.dart';

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
    final colors = context.appColors;

    return Scaffold(
      backgroundColor: colors.obsidian,
      appBar: AppBar(
        backgroundColor: colors.obsidianSurface,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            decoration: const BoxDecoration(gradient: AppGradients.goldFoil),
          ),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: const BoxDecoration(
                gradient: AppGradients.goldFoil,
                borderRadius: AppRadius.smAll,
              ),
              child: Text(
                'VIP',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.obsidian,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                'مهام التوصيل - ${authUser?.name ?? "السائق"}',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colors.onObsidian,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          GoldIconButton(
            icon: _isMapView ? Icons.view_list_rounded : Icons.map_rounded,
            tooltip: _isMapView ? 'عرض القائمة' : 'عرض الخريطة',
            onPressed: () => setState(() => _isMapView = !_isMapView),
          ),
          GoldIconButton(
            icon: Icons.refresh,
            tooltip: 'تحديث',
            onPressed: _refresh,
          ),
          GoldIconButton(
            icon: Icons.logout,
            tooltip: 'تسجيل الخروج',
            onPressed: () => ref.read(authStateProvider.notifier).state = null,
          ),
        ],
      ),
      body: Column(
        children: [
          // Top Telemetry Bar
          Container(
            decoration: BoxDecoration(
              color: colors.obsidianCard,
              border: Border(
                bottom: BorderSide(
                  color: colors.gold.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
            ),
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
                        data: (balanceCentimes) => InkWell(
                          onTap: () {
                            if (authUser != null) {
                              DriverWalletSheet.show(
                                context,
                                driverId: authUser.id,
                                driverName: authUser.name,
                              );
                            }
                          },
                          borderRadius: AppRadius.mdAll,
                          child: KpiCard(
                            title: 'الكاش في عهدتك (المحفظة)',
                            value: DzdFormatter.formatCentimes(balanceCentimes),
                            icon: Icons.account_balance_wallet_outlined,
                            subtitle: 'اضغط هنا لعرض تفاصيل العهدة والتسوية',
                            accentColor: colors.gold,
                          ),
                        ),
                        loading: () => AppStates.loading(),
                        error: (_, __) => const SizedBox.shrink(),
                      ),
                      AppSpacing.gapMd,
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'الطلبات الموكلة إليك (${orders.length}):',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colors.onObsidian,
                            ),
                          ),
                          GoldButton.icon(
                            onPressed: () => setState(() => _isMapView = true),
                            icon: Icons.map,
                            label: 'عرض الخريطة',
                            compact: true,
                          ),
                        ],
                      ),
                      AppSpacing.gapSm,
                      Expanded(
                        child: orders.isEmpty
                            ? AppStates.empty(
                                icon: Icons.local_shipping_outlined,
                                title: 'لا توجد طلبات توصيل',
                                description: 'ستظهر الطلبات الجديدة هنا بمجرد تعيينها لك.',
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

                                  return LuxuryCard(
                                    goldAccent: !isDelivered,
                                    selected: !isDelivered,
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
                                                  Container(
                                                    padding: const EdgeInsets.all(6),
                                                    decoration: BoxDecoration(
                                                      gradient: isDelivered ? null : AppGradients.goldFoil,
                                                      color: isDelivered ? colors.obsidianMuted : null,
                                                      borderRadius: AppRadius.smAll,
                                                    ),
                                                    child: Icon(
                                                      Icons.receipt_long,
                                                      size: 18,
                                                      color: isDelivered ? colors.onObsidian.withValues(alpha: 0.5) : colors.obsidian,
                                                    ),
                                                  ),
                                                  const SizedBox(width: AppSpacing.sm),
                                                  Text(
                                                    'طلب رقم #${order.orderNumber ?? order.id.substring(0, 8)}',
                                                    style: theme.textTheme.titleSmall?.copyWith(
                                                      fontWeight: FontWeight.bold,
                                                      color: colors.onObsidian,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              StatusBadge(
                                                type: isDelivered ? StatusBadgeType.completed : StatusBadgeType.processing,
                                                customLabel: isDelivered ? 'تم التسليم' : 'قيد التوصيل',
                                              ),
                                            ],
                                          ),
                                          const GoldDivider(),
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
                                              Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'المبلغ المطلوب تحصيله',
                                                    style: theme.textTheme.labelSmall?.copyWith(
                                                      color: colors.onObsidian.withValues(alpha: 0.6),
                                                    ),
                                                  ),
                                                  DzdPriceTag.lg(centimes: order.totalAmountCentimes, gold: !isDelivered),
                                                ],
                                              ),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: colors.obsidianMuted,
                                                  borderRadius: AppRadius.pillAll,
                                                ),
                                                child: Text(
                                                  '${order.items.length} أصناف',
                                                  style: theme.textTheme.labelSmall?.copyWith(color: colors.onObsidian),
                                                ),
                                              ),
                                            ],
                                          ),
                                          AppSpacing.gapMd,
                                          Row(
                                            children: [
                                              // Navigation
                                              Expanded(
                                                child: OutlinedButton.icon(
                                                  style: OutlinedButton.styleFrom(
                                                    side: BorderSide(color: colors.gold.withValues(alpha: 0.5)),
                                                    foregroundColor: colors.gold,
                                                  ),
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
                                                  icon: const Icon(Icons.navigation_outlined, size: 16),
                                                  label: const Text('الملاحة GPS'),
                                                ),
                                              ),
                                              if (order.customerPhone != null || order.customerSnapshot?['phone'] != null) ...[
                                                const SizedBox(width: AppSpacing.sm),
                                                GoldIconButton(
                                                  icon: Icons.call_rounded,
                                                  tooltip: 'اتصال بالزبون',
                                                  onPressed: () {
                                                    final phone = order.customerPhone ?? order.customerSnapshot?['phone'];
                                                    if (phone != null) launchUrl(Uri.parse('tel:$phone'));
                                                  },
                                                ),
                                              ],
                                              if (!isDelivered) ...[
                                                const SizedBox(width: AppSpacing.sm),
                                                Expanded(
                                                  child: GoldButton.icon(
                                                    onPressed: () => _openProofOfDeliveryDialog(order),
                                                    icon: Icons.check_circle_outline,
                                                    label: 'تسليم وإثبات',
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
              loading: () => AppStates.loading(),
              error: (err, _) => AppStates.error(
               'تعذر تحميل مهام التوصيل',
                onRetry: _refresh,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
