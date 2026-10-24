import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:maps_launcher/maps_launcher.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:core/core.dart';
import 'package:domain/domain.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../providers/staff_providers.dart';
import '../../router/staff_router.dart';
import '../moderator/widgets/staff_profile_edit_sheet.dart';
import 'services/driver_telemetry_service.dart';
import 'widgets/delivery_order_card.dart';
import 'widgets/driver_map_view.dart';
import 'widgets/driver_order_utils.dart';
import 'widgets/driver_wallet_sheet.dart';
import 'widgets/proof_of_delivery_dialog.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Driver deliveries dashboard
// ─────────────────────────────────────────────────────────────────────────────

enum _DeliveryFilter { active, completed, all }

enum _DeliverySort { newest, nearest, highestValue }

class DriverDeliveriesScreen extends ConsumerStatefulWidget {
  const DriverDeliveriesScreen({super.key});

  @override
  ConsumerState<DriverDeliveriesScreen> createState() =>
      _DriverDeliveriesScreenState();
}

class _DriverDeliveriesScreenState
    extends ConsumerState<DriverDeliveriesScreen> {
  static const Color _heroGold = Color(0xFFF3D278);
  static const Color _heroCream = Color(0xFFFBF8F0);
  static const Color _heroMuted = Color(0xB8FBF8F0);

  final DriverTelemetryService _telemetry = DriverTelemetryService();

  bool _isMapView = false;
  _DeliveryFilter _filter = _DeliveryFilter.active;
  _DeliverySort _sort = _DeliverySort.newest;

  @override
  void initState() {
    super.initState();
    _telemetry.addListener(_onTelemetryUpdate);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAppUpdates();
    });
  }

  Future<void> _checkAppUpdates() async {
    try {
      final res = await ref.read(appUpdateServiceProvider).checkForUpdate();
      if (res.hasUpdate && mounted && res.newRelease != null) {
        final service = ref.read(appUpdateServiceProvider);
        AppUpdateDialog.show(
          context,
          release: res.newRelease!,
          currentVersion: res.currentVersion,
          currentBuild: res.currentBuild,
          updateService: service,
          force: res.isForceUpdate,
        );
      }
    } catch (e) {
      debugPrint('[Driver] Error checking updates: $e');
    }
  }

  Future<void> _checkUpdatesManually() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('جاري التحقق من التحديثات...'),
        duration: Duration(seconds: 1),
      ),
    );
    try {
      final res = await ref.read(appUpdateServiceProvider).checkForUpdate();
      if (!mounted) return;
      if (res.hasUpdate && res.newRelease != null) {
        final service = ref.read(appUpdateServiceProvider);
        AppUpdateDialog.show(
          context,
          release: res.newRelease!,
          currentVersion: res.currentVersion,
          currentBuild: res.currentBuild,
          updateService: service,
          force: res.isForceUpdate,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('أنت تستخدم أحدث إصدار متوفر (v${res.currentVersion} #${res.currentBuild})'),
            backgroundColor: const Color(0xFF1E3A2F),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر التحقق من التحديثات: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  void dispose() {
    _telemetry.removeListener(_onTelemetryUpdate);
    super.dispose();
  }

  void _onTelemetryUpdate() {
    if (mounted) setState(() {});
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _refresh() async {
    ref.invalidate(driverOrdersProvider);
    ref.invalidate(driverWalletBalanceProvider);

    final user = ref.read(authStateProvider);
    if (user != null) {
      ref.invalidate(driverUnsettledOrdersProvider(user.id));
      ref.invalidate(recentSettlementsProvider(user.id));
    }

    try {
      await ref.read(driverOrdersProvider.future);
      await ref.read(driverWalletBalanceProvider.future);
    } catch (_) {
      // The error state is rendered by the watched providers.
    }
  }

  void _openProofOfDeliveryDialog(OrderEntity order) {
    ProofOfDeliveryDialog.show(
      context,
      order: order,
      onDelivered: _refresh,
    );
  }

  Future<void> _openWallet() async {
    final user = ref.read(authStateProvider);
    if (user == null) return;

    await DriverWalletSheet.show(
      context,
      driverId: user.id,
      driverName: user.name,
    );
  }

  Future<void> _openEditProfile() async {
    final user = ref.read(authStateProvider);
    if (user == null) return;

    final updated = await StaffProfileEditSheet.show(
      context,
      ref,
      userId: user.id,
      name: user.name,
      phone: user.phone,
      role: user.role.name,
      active: user.active,
      language: user.language,
    );
    if (updated == true && mounted) {
      setState(() {});
    }
  }

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
        'تعذر فتح تطبيق الخرائط. يمكنك نسخ العنوان والبحث عنه يدوياً.',
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

  Future<void> _toggleTrip() async {
    final wasActive = _telemetry.state.isTripActive;
    if (wasActive) {
      await _telemetry.endTrip();
    } else {
      await _telemetry.startTrip();
    }

    _showSnack(
      wasActive
          ? 'تم إنهاء الجولة وتسجيل نهاية التتبع.'
          : 'بدأت الجولة! يتم الآن تسجيل مسار التوصيل.',
    );
  }

  Future<void> _toggleWakelock(bool enable) async {
    await _telemetry.toggleWakelock(enable);
    if (!mounted) return;
    _showSnack(
      enable
          ? 'تم تثبيت الشاشة مفتوحة أثناء التوصيل.'
          : 'تم إلغاء تثبيت الشاشة.',
    );
  }

  Future<void> _toggleBackgroundTracking(bool enable) async {
    await _telemetry.toggleBackgroundTracking(enable);
    if (!mounted) return;
    _showSnack(
      enable ? 'تم تفعيل التتبع في الخلفية.' : 'تم إيقاف التتبع في الخلفية.',
    );
  }

  Future<void> _confirmLogout() async {
    final colors = context.appColors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.logout_rounded, color: colors.error),
        title: const Text('تسجيل الخروج'),
        content: const Text(
          'هل تريد تسجيل الخروج من حساب السائق؟ سيتم إيقاف استقبال مهام جديدة حتى تسجيل الدخول مجدداً.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colors.error,
              foregroundColor: colors.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('تسجيل الخروج'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      ref.read(authStateProvider.notifier).state = null;
    }
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

  // ── Computed data ──────────────────────────────────────────────────────────

  Map<String, double> _distancesFor(List<OrderEntity> orders) {
    final position = _telemetry.state.currentPosition;
    final distances = <String, double>{};
    if (position == null) return distances;

    for (final order in orders) {
      final latitude = orderLatitude(order);
      final longitude = orderLongitude(order);
      if (latitude == null || longitude == null) continue;

      distances[order.id] = Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            latitude,
            longitude,
          ) /
          1000.0;
    }
    return distances;
  }

  List<OrderEntity> _sortOrders(
    List<OrderEntity> orders,
    Map<String, double> distances,
  ) {
    final sorted = List<OrderEntity>.of(orders);

    switch (_sort) {
      case _DeliverySort.newest:
        sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case _DeliverySort.nearest:
        sorted.sort((a, b) {
          final da = distances[a.id] ?? double.infinity;
          final db = distances[b.id] ?? double.infinity;
          final distanceCompare = da.compareTo(db);
          if (distanceCompare != 0) return distanceCompare;
          return b.createdAt.compareTo(a.createdAt);
        });
        break;
      case _DeliverySort.highestValue:
        sorted.sort((a, b) {
          final amountCompare = b.dueAmountCentimes.compareTo(
            a.dueAmountCentimes,
          );
          if (amountCompare != 0) return amountCompare;
          return b.createdAt.compareTo(a.createdAt);
        });
        break;
    }
    return sorted;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(driverOrdersProvider);
    final walletAsync = ref.watch(driverWalletBalanceProvider);
    final authUser = ref.watch(authStateProvider);

    if (authUser != null) {
      _telemetry.setDriverId(authUser.id);
    }

    final theme = Theme.of(context);
    final colors = context.appColors;
    final telemetryState = _telemetry.state;
    final knownOrders = ordersAsync.valueOrNull ?? const <OrderEntity>[];
    final activeCount =
        knownOrders.where((o) => isOrderActive(o.status)).length;
    final balance = walletAsync.valueOrNull;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: _buildAppBar(
        context,
        theme,
        colors,
        authUser,
        activeCount: activeCount,
        hasCashInHand: (balance ?? 0) > 0,
      ),
      body: ordersAsync.when(
        loading: () => AppStates.loading(
          message: 'جارٍ تحميل مهام التوصيل...',
        ),
        error: (error, _) => AppStates.error(
          'تعذر تحميل مهام التوصيل. تحقق من اتصالك ثم أعد المحاولة.',
          onRetry: _refresh,
        ),
        data: (orders) {
          if (_isMapView) {
            final driverLatLng = telemetryState.currentPosition != null
                ? LatLng(
                    telemetryState.currentPosition!.latitude,
                    telemetryState.currentPosition!.longitude,
                  )
                : null;

            return DriverMapView(
              orders: orders,
              driverLocation: driverLatLng,
              onOrdersUpdated: _refresh,
            );
          }

          return _buildDashboard(
            context,
            theme,
            colors,
            orders: orders,
            authUser: authUser,
            telemetryState: telemetryState,
            walletAsync: walletAsync,
          );
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    ThemeData theme,
    AppColors colors,
    UserEntity? authUser, {
    required int activeCount,
    required bool hasCashInHand,
  }) {
    final compact = context.isCompact;

    return AppBar(
      backgroundColor: theme.colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 16,
      title: InkWell(
        onTap: _openEditProfile,
        borderRadius: AppRadius.smAll,
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: const BoxDecoration(
                  gradient: AppGradients.goldFoil,
                  borderRadius: AppRadius.smAll,
                ),
                child: Text(
                  'VIP',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: const Color(0xFF1A1400),
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'مهام التوصيل',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      authUser?.name ?? 'السائق',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (_isMapView)
          _AppBarAction(
            icon: Icons.view_agenda_outlined,
            tooltip: 'العودة إلى قائمة المهام',
            onPressed: () => setState(() => _isMapView = false),
          ),
        _AppBarAction(
          icon: Icons.account_balance_wallet_outlined,
          tooltip: 'محفظة العهدة',
          onPressed: _openWallet,
          showNotificationDot: hasCashInHand,
        ),
        if (!compact) ...[
          _AppBarAction(
            icon: Icons.refresh_rounded,
            tooltip: 'تحديث المهام',
            onPressed: _refresh,
          ),
          _AppBarAction(
            icon: Icons.system_update_rounded,
            tooltip: 'التحقق من التحديثات',
            onPressed: _checkUpdatesManually,
          ),
          _AppBarAction(
            icon: Icons.manage_accounts_outlined,
            tooltip: 'تعديل الملف الشخصي',
            onPressed: _openEditProfile,
          ),
          _AppBarAction(
            icon: Icons.logout_rounded,
            tooltip: 'تسجيل الخروج',
            onPressed: _confirmLogout,
            color: colors.error,
          ),
        ] else
          PopupMenuButton<String>(
            tooltip: 'المزيد',
            icon: Icon(Icons.more_vert_rounded, color: colors.gold),
            onSelected: (value) {
              switch (value) {
                case 'refresh':
                  _refresh();
                  break;
                case 'update':
                  _checkUpdatesManually();
                  break;
                case 'profile':
                  _openEditProfile();
                  break;
                case 'logout':
                  _confirmLogout();
                  break;
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'refresh',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.refresh_rounded),
                  title: Text('تحديث المهام'),
                ),
              ),
              const PopupMenuItem(
                value: 'update',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.system_update_rounded),
                  title: Text('التحقق من التحديثات'),
                ),
              ),
              const PopupMenuItem(
                value: 'profile',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.manage_accounts_outlined),
                  title: Text('الملف الشخصي'),
                ),
              ),
              PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.logout_rounded, color: colors.error),
                  title: Text('تسجيل الخروج',
                      style: TextStyle(color: colors.error)),
                ),
              ),
            ],
          ),
        const SizedBox(width: AppSpacing.sm),
      ],
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: GoldDivider(),
      ),
    );
  }

  Widget _buildDashboard(
    BuildContext context,
    ThemeData theme,
    AppColors colors, {
    required List<OrderEntity> orders,
    required UserEntity? authUser,
    required DriverTelemetryState telemetryState,
    required AsyncValue<int> walletAsync,
  }) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 1180;
    final pagePadding = width >= 840 ? AppSpacing.xl : AppSpacing.lg;

    final activeOrders =
        orders.where((o) => isOrderActive(o.status)).toList(growable: false);
    final completedOrders =
        orders.where((o) => isOrderCompleted(o.status)).toList(growable: false);
    final cancelledOrders = orders
        .where(
          (o) =>
              o.status == OrderStatus.cancelled ||
              o.status == OrderStatus.refused,
        )
        .toList(growable: false);
    final distances = _distancesFor(orders);
    final sortedActive = _sortOrders(activeOrders, distances);
    final sortedCompleted = _sortOrders(completedOrders, distances);
    final sortedCancelled = _sortOrders(cancelledOrders, distances);

    final collectTotal = activeOrders.fold<int>(
      0,
      (sum, order) => sum + order.dueAmountCentimes,
    );

    return RefreshIndicator(
      color: colors.gold,
      backgroundColor: theme.colorScheme.surface,
      onRefresh: _refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: EdgeInsetsDirectional.fromSTEB(
              pagePadding,
              pagePadding,
              pagePadding,
              AppSpacing.xxl,
            ),
            sliver: SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeroHeader(
                        context,
                        theme,
                        colors,
                        authUser: authUser,
                        telemetryState: telemetryState,
                        activeOrders: activeOrders,
                        completedOrders: completedOrders,
                        collectTotal: collectTotal,
                        walletAsync: walletAsync,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      if (isDesktop)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildToolbar(
                                    context,
                                    theme,
                                    colors,
                                    activeCount: activeOrders.length,
                                    completedCount: completedOrders.length,
                                    totalCount: orders.length,
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  _buildOrdersArea(
                                    context,
                                    theme,
                                    colors,
                                    activeOrders: sortedActive,
                                    completedOrders: sortedCompleted,
                                    cancelledOrders: sortedCancelled,
                                    distances: distances,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xl),
                            SizedBox(
                              width: 320,
                              child: _buildSidePanel(
                                context,
                                theme,
                                colors,
                                activeOrders: sortedActive,
                                distances: distances,
                                collectTotal: collectTotal,
                                walletAsync: walletAsync,
                                telemetryState: telemetryState,
                              ),
                            ),
                          ],
                        )
                      else ...[
                        _buildToolbar(
                          context,
                          theme,
                          colors,
                          activeCount: activeOrders.length,
                          completedCount: completedOrders.length,
                          totalCount: orders.length,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _buildOrdersArea(
                          context,
                          theme,
                          colors,
                          activeOrders: sortedActive,
                          completedOrders: sortedCompleted,
                          cancelledOrders: sortedCancelled,
                          distances: distances,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Hero / cockpit header ──────────────────────────────────────────────────

  Widget _buildHeroHeader(
    BuildContext context,
    ThemeData theme,
    AppColors colors, {
    required UserEntity? authUser,
    required DriverTelemetryState telemetryState,
    required List<OrderEntity> activeOrders,
    required List<OrderEntity> completedOrders,
    required int collectTotal,
    required AsyncValue<int> walletAsync,
  }) {
    final firstName = (authUser?.name ?? 'السائق').split(' ').first;
    final balanceText = walletAsync.when(
      data: (value) => DzdFormatter.formatCentimes(value, showDecimals: false),
      loading: () => '...',
      error: (_, __) => '—',
    );

    final mainInfo = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsetsDirectional.all(9),
              decoration: const BoxDecoration(
                gradient: AppGradients.gold,
                borderRadius: AppRadius.mdAll,
                boxShadow: [AppShadows.goldGlowSm],
              ),
              child: const Icon(
                Icons.local_shipping_rounded,
                size: 21,
                color: Color(0xFF1A1400),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_greeting()}، $firstName',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: _heroCream,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    activeOrders.isEmpty
                        ? 'كل المهام مكتملة — جاهز للجولة القادمة'
                        : 'لديك ${activeOrders.length} ${activeOrders.length == 1 ? 'مهمة نشطة' : 'مهام نشطة'} على الطريق',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _heroMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _TelemetryChip(
              icon: telemetryState.currentPosition != null
                  ? Icons.gps_fixed_rounded
                  : Icons.gps_not_fixed_rounded,
              label: telemetryState.currentPosition != null
                  ? 'GPS نشط'
                  : 'GPS غير متاح',
              color: telemetryState.currentPosition != null
                  ? const Color(0xFF6EE7B7)
                  : const Color(0xFFFBBF24),
            ),
            _TelemetryChip(
              icon: _batteryIcon(telemetryState),
              label: '${telemetryState.batteryLevel}%',
              color: telemetryState.isLowBattery
                  ? const Color(0xFFF87171)
                  : _heroMuted,
            ),
            _TelemetryChip(
              icon: telemetryState.isWakelockEnabled
                  ? Icons.screen_lock_portrait_rounded
                  : Icons.screen_lock_portrait_outlined,
              label: telemetryState.isWakelockEnabled
                  ? 'الشاشة مفعلة'
                  : 'قفل الشاشة',
              color: telemetryState.isWakelockEnabled ? _heroGold : _heroMuted,
              onTap: () => _toggleWakelock(!telemetryState.isWakelockEnabled),
            ),
            _TelemetryChip(
              icon: Icons.radar_rounded,
              label: telemetryState.isBackgroundServiceActive
                  ? 'تتبع بالخلفية'
                  : 'تتبع عادي',
              color: telemetryState.isBackgroundServiceActive
                  ? const Color(0xFF6EE7B7)
                  : _heroMuted,
              onTap: () => _toggleBackgroundTracking(
                !telemetryState.isBackgroundServiceActive,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (telemetryState.isTripActive)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: _heroGold,
                  side: BorderSide(
                    color: _heroGold.withValues(alpha: 0.70),
                  ),
                  minimumSize: const Size(0, 44),
                ),
                onPressed: _toggleTrip,
                icon: const Icon(Icons.stop_circle_outlined, size: 18),
                label: const Text('إنهاء الجولة'),
              )
            else
              GoldButton.icon(
                onPressed: _toggleTrip,
                icon: Icons.play_arrow_rounded,
                label: 'بدء الجولة',
              ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: _heroCream,
                side: BorderSide(color: _heroCream.withValues(alpha: 0.25)),
                minimumSize: const Size(0, 44),
              ),
              onPressed: _openWallet,
              icon: const Icon(Icons.receipt_long_outlined, size: 17),
              label: const Text('كشف العهدة'),
            ),
          ],
        ),
      ],
    );

    final walletCard = Container(
      padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.20),
        borderRadius: AppRadius.xlAll,
        border: Border.all(color: _heroGold.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet_outlined,
                size: 16,
                color: _heroGold,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'الكاش في عهدتك',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: _heroMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if ((walletAsync.valueOrNull ?? 0) > 0)
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFBBF24),
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            balanceText,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: _heroGold,
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            'المبلغ المطلوب تسليمه للمشرف أو الصندوق',
            style: theme.textTheme.labelSmall?.copyWith(color: _heroMuted),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 42,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: _heroGold,
                side: BorderSide(color: _heroGold.withValues(alpha: 0.55)),
              ),
              onPressed: _openWallet,
              icon: const Icon(Icons.arrow_forward_rounded, size: 16),
              label: const Text('عرض المحفظة والتسويات'),
            ),
          ),
        ],
      ),
    );

    return Container(
      decoration: BoxDecoration(
        gradient: AppGradients.obsidianHero,
        borderRadius: AppRadius.xxlAll,
        border: Border.all(color: _heroGold.withValues(alpha: 0.30)),
        boxShadow: AppShadows.dialogLuxury,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          PositionedDirectional(
            top: -90,
            end: -70,
            child: IgnorePointer(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _heroGold.withValues(alpha: 0.20),
                      _heroGold.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.all(AppSpacing.xl),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final horizontal = constraints.maxWidth >= 760;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (horizontal)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: mainInfo),
                          const SizedBox(width: AppSpacing.xl),
                          SizedBox(width: 300, child: walletCard),
                        ],
                      )
                    else ...[
                      mainInfo,
                      const SizedBox(height: AppSpacing.lg),
                      walletCard,
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    Container(
                      padding: const EdgeInsetsDirectional.only(
                        top: AppSpacing.md,
                      ),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: _heroCream.withValues(alpha: 0.10),
                          ),
                        ),
                      ),
                      child: _buildHeroMetrics(
                        context,
                        theme,
                        activeOrders: activeOrders,
                        completedOrders: completedOrders,
                        collectTotal: collectTotal,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroMetrics(
    BuildContext context,
    ThemeData theme, {
    required List<OrderEntity> activeOrders,
    required List<OrderEntity> completedOrders,
    required int collectTotal,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = AppSpacing.sm;
        final columns = constraints.maxWidth < 380 ? 2 : 3;
        final itemWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: AppSpacing.md,
          children: [
            SizedBox(
              width: itemWidth,
              child: _HeroMetric(
                icon: Icons.local_shipping_outlined,
                value: '${activeOrders.length}',
                label: 'مهام نشطة',
                valueColor: _heroGold,
                theme: theme,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _HeroMetric(
                icon: Icons.task_alt_rounded,
                value: '${completedOrders.length}',
                label: 'مكتملة',
                valueColor: const Color(0xFF6EE7B7),
                theme: theme,
              ),
            ),
            SizedBox(
              // On narrow phones the money metric wraps to its own row; let it
              // use the full width so large amounts are not truncated.
              width: columns == 2 ? constraints.maxWidth : itemWidth,
              child: _HeroMetric(
                icon: Icons.payments_outlined,
                value: DzdFormatter.formatCentimes(
                  collectTotal,
                  showDecimals: false,
                ),
                label: 'للتحصيل',
                valueColor: _heroCream,
                theme: theme,
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Toolbar / filters ──────────────────────────────────────────────────────

  Widget _buildToolbar(
    BuildContext context,
    ThemeData theme,
    AppColors colors, {
    required int activeCount,
    required int completedCount,
    required int totalCount,
  }) {
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterPill(
                  label: 'نشطة',
                  count: activeCount,
                  icon: Icons.local_shipping_outlined,
                  selected: _filter == _DeliveryFilter.active,
                  onTap: () => setState(() => _filter = _DeliveryFilter.active),
                ),
                const SizedBox(width: AppSpacing.sm),
                _FilterPill(
                  label: 'مكتملة',
                  count: completedCount,
                  icon: Icons.task_alt_rounded,
                  selected: _filter == _DeliveryFilter.completed,
                  onTap: () =>
                      setState(() => _filter = _DeliveryFilter.completed),
                ),
                const SizedBox(width: AppSpacing.sm),
                _FilterPill(
                  label: 'الكل',
                  count: totalCount,
                  icon: Icons.all_inbox_outlined,
                  selected: _filter == _DeliveryFilter.all,
                  onTap: () => setState(() => _filter = _DeliveryFilter.all),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        PopupMenuButton<_DeliverySort>(
          tooltip: 'ترتيب المهام',
          initialValue: _sort,
          onSelected: (value) => setState(() => _sort = value),
          itemBuilder: (context) => [
            _sortMenuItem(
              value: _DeliverySort.newest,
              icon: Icons.schedule_rounded,
              label: 'الأحدث أولاً',
              selected: _sort == _DeliverySort.newest,
            ),
            _sortMenuItem(
              value: _DeliverySort.nearest,
              icon: Icons.near_me_rounded,
              label: 'الأقرب إليّ',
              selected: _sort == _DeliverySort.nearest,
            ),
            _sortMenuItem(
              value: _DeliverySort.highestValue,
              icon: Icons.trending_up_rounded,
              label: 'الأعلى قيمة',
              selected: _sort == _DeliverySort.highestValue,
            ),
          ],
          child: _ToolbarButton(
            icon: Icons.swap_vert_rounded,
            tooltip: 'ترتيب المهام',
            colors: colors,
            theme: theme,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        _ViewToggle(
          isMapView: _isMapView,
          onChanged: (isMap) => setState(() => _isMapView = isMap),
        ),
      ],
    );
  }

  PopupMenuItem<_DeliverySort> _sortMenuItem({
    required _DeliverySort value,
    required IconData icon,
    required String label,
    required bool selected,
  }) {
    final colors = context.appColors;
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 18, color: selected ? colors.gold : null),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          if (selected) Icon(Icons.check_rounded, size: 17, color: colors.gold),
        ],
      ),
    );
  }

  // ── Orders area ────────────────────────────────────────────────────────────

  Widget _buildOrdersArea(
    BuildContext context,
    ThemeData theme,
    AppColors colors, {
    required List<OrderEntity> activeOrders,
    required List<OrderEntity> completedOrders,
    required List<OrderEntity> cancelledOrders,
    required Map<String, double> distances,
  }) {
    final showActive = _filter != _DeliveryFilter.completed;
    final showCompleted = _filter != _DeliveryFilter.active;
    final showCancelled = _filter == _DeliveryFilter.all;
    final stopNumbers = <String, int>{
      for (var i = 0; i < activeOrders.length; i++) activeOrders[i].id: i + 1,
    };

    final sections = <Widget>[
      if (showActive && activeOrders.isNotEmpty)
        _buildOrderSection(
          context,
          theme,
          colors,
          title: 'المهام النشطة',
          icon: Icons.local_shipping_outlined,
          orders: activeOrders,
          distances: distances,
          stopNumbers: stopNumbers,
          completed: false,
        ),
      if (showCompleted && completedOrders.isNotEmpty)
        _buildOrderSection(
          context,
          theme,
          colors,
          title: 'المهام المكتملة',
          icon: Icons.task_alt_rounded,
          orders: completedOrders,
          distances: distances,
          stopNumbers: const {},
          completed: true,
        ),
      if (showCancelled && cancelledOrders.isNotEmpty)
        _buildOrderSection(
          context,
          theme,
          colors,
          title: 'ملغاة أو مرفوضة',
          icon: Icons.block_outlined,
          orders: cancelledOrders,
          distances: distances,
          stopNumbers: const {},
          completed: true,
          sectionColor: colors.cancelled,
        ),
    ];

    if (sections.isEmpty) {
      return _buildEmptyState(
        context,
        theme,
        colors,
        activeOrders: activeOrders,
        completedOrders: completedOrders,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < sections.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.xl),
          sections[i],
        ],
      ],
    );
  }

  Widget _buildOrderSection(
    BuildContext context,
    ThemeData theme,
    AppColors colors, {
    required String title,
    required IconData icon,
    required List<OrderEntity> orders,
    required Map<String, double> distances,
    required Map<String, int> stopNumbers,
    required bool completed,
    Color? sectionColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(
          title: title,
          icon: icon,
          count: orders.length,
          color: sectionColor ?? (completed ? colors.success : colors.gold),
        ),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = AppSpacing.md;
            final columns = constraints.maxWidth >= 1120
                ? 3
                : constraints.maxWidth >= 720
                    ? 2
                    : 1;
            final cardWidth = columns == 1
                ? constraints.maxWidth
                : (constraints.maxWidth - spacing * (columns - 1)) / columns;

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final order in orders)
                  SizedBox(
                    width: cardWidth,
                    child: DeliveryOrderCard(
                      order: order,
                      stopNumber: completed ? null : stopNumbers[order.id],
                      distanceKm: distances[order.id],
                      onNavigate: () => _openNavigation(order),
                      onCall: deliveryCustomerPhone(order) != null
                          ? () => _callCustomer(order)
                          : null,
                      onDeliver: completed
                          ? null
                          : () => _openProofOfDeliveryDialog(order),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    ThemeData theme,
    AppColors colors, {
    required List<OrderEntity> activeOrders,
    required List<OrderEntity> completedOrders,
  }) {
    final bool completedView = _filter == _DeliveryFilter.completed;
    final bool hasOther =
        completedView ? activeOrders.isNotEmpty : completedOrders.isNotEmpty;

    final String title = switch (_filter) {
      _DeliveryFilter.active => 'لا توجد مهام نشطة حالياً',
      _DeliveryFilter.completed => 'لا توجد مهام مكتملة بعد',
      _DeliveryFilter.all => 'لا توجد طلبات توصيل',
    };

    final String description = switch (_filter) {
      _DeliveryFilter.active =>
        'تم إنجاز كل المهام الموكلة إليك. سيظهر هنا أي طلب جديد فور تعيينه.',
      _DeliveryFilter.completed =>
        'ستظهر هنا الطلبات التي سلّمتها، مع مبالغ التحصيل وحالة التسوية.',
      _DeliveryFilter.all =>
        'ستظهر الطلبات الجديدة هنا بمجرد تعيينها لك من طرف المشرف أو الصندوق.',
    };

    final String? actionLabel = hasOther
        ? (completedView ? 'عرض المهام النشطة' : 'عرض المهام المكتملة')
        : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: AppRadius.xlAll,
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.75),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: colors.goldMuted,
              shape: BoxShape.circle,
              border: Border.all(
                color: colors.gold.withValues(alpha: 0.28),
                width: 1.5,
              ),
            ),
            child: Icon(
              completedView
                  ? Icons.task_alt_rounded
                  : Icons.local_shipping_outlined,
              size: 34,
              color: colors.gold,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              description,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _filter = completedView
                      ? _DeliveryFilter.active
                      : _DeliveryFilter.completed;
                });
              },
              icon: Icon(
                completedView
                    ? Icons.local_shipping_outlined
                    : Icons.task_alt_rounded,
                size: 17,
              ),
              label: Text(actionLabel),
            ),
          ],
        ],
      ),
    );
  }

  // ── Desktop side panel ─────────────────────────────────────────────────────

  Widget _buildSidePanel(
    BuildContext context,
    ThemeData theme,
    AppColors colors, {
    required List<OrderEntity> activeOrders,
    required Map<String, double> distances,
    required int collectTotal,
    required AsyncValue<int> walletAsync,
    required DriverTelemetryState telemetryState,
  }) {
    final nextOrder = activeOrders.isEmpty ? null : activeOrders.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelCard(
          title: 'المقصد التالي',
          icon: Icons.near_me_rounded,
          child: nextOrder == null
              ? const _SidePanelEmpty(
                  icon: Icons.check_circle_outline_rounded,
                  message: 'لا توجد محطات متبقية في هذه الجولة.',
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            deliveryCustomerName(nextOrder),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (distances[nextOrder.id] != null)
                          Container(
                            padding: const EdgeInsetsDirectional.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: colors.goldMuted,
                              borderRadius: AppRadius.pillAll,
                            ),
                            child: Text(
                              formatDistanceKm(distances[nextOrder.id]),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: colors.gold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      deliveryAddressText(nextOrder) ?? 'العنوان غير مسجل',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Text(
                          'تحصيل: ',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        DzdPriceTag.sm(
                          centimes: nextOrder.dueAmountCentimes,
                          gold: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _openNavigation(nextOrder),
                            icon: const Icon(
                              Icons.navigation_rounded,
                              size: 16,
                            ),
                            label: const Text('الملاحة'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        IconButton.outlined(
                          tooltip: 'اتصال',
                          onPressed: deliveryCustomerPhone(nextOrder) != null
                              ? () => _callCustomer(nextOrder)
                              : null,
                          icon: const Icon(Icons.call_rounded, size: 18),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
        const SizedBox(height: AppSpacing.md),
        _PanelCard(
          title: 'ملخص التحصيل',
          icon: Icons.account_balance_wallet_outlined,
          child: Column(
            children: [
              _SideMetricRow(
                label: 'للتحصيل في الجولة',
                value: DzdFormatter.formatCentimes(
                  collectTotal,
                  showDecimals: false,
                ),
                color: colors.gold,
              ),
              const SizedBox(height: AppSpacing.sm),
              _SideMetricRow(
                label: 'الكاش في العهدة',
                value: walletAsync.when(
                  data: (value) =>
                      DzdFormatter.formatCentimes(value, showDecimals: false),
                  loading: () => '...',
                  error: (_, __) => '—',
                ),
                color: colors.success,
              ),
              const SizedBox(height: AppSpacing.sm),
              Container(
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: AppRadius.pillAll,
                ),
                child: FractionallySizedBox(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: activeOrders.isEmpty ? 0 : 1,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: AppGradients.goldFoil,
                      borderRadius: AppRadius.pillAll,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  '${activeOrders.length} محطة متبقية',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _PanelCard(
          title: 'أدوات السائق',
          icon: Icons.tune_rounded,
          child: Column(
            children: [
              _SideSwitchRow(
                icon: Icons.screen_lock_portrait_rounded,
                label: 'إبقاء الشاشة مفتوحة',
                value: telemetryState.isWakelockEnabled,
                onChanged: _toggleWakelock,
              ),
              const SizedBox(height: AppSpacing.sm),
              _SideSwitchRow(
                icon: Icons.radar_rounded,
                label: 'التتبع في الخلفية',
                value: telemetryState.isBackgroundServiceActive,
                onChanged: _toggleBackgroundTracking,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Small helpers ──────────────────────────────────────────────────────────

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'صباح الخير';
    if (hour < 17) return 'نهارك سعيد';
    return 'مساء الخير';
  }

  IconData _batteryIcon(DriverTelemetryState state) {
    if (state.batteryState == BatteryState.charging) {
      return Icons.battery_charging_full_rounded;
    }
    if (state.isLowBattery) return Icons.battery_alert_rounded;
    return Icons.battery_full_rounded;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable driver UI pieces
// ─────────────────────────────────────────────────────────────────────────────

class _AppBarAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool showNotificationDot;
  final Color? color;

  const _AppBarAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.showNotificationDot = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        foregroundColor: color ?? colors.gold,
        minimumSize: const Size(44, 44),
      ),
      icon: Badge(
        isLabelVisible: showNotificationDot,
        smallSize: 8,
        backgroundColor: colors.gold,
        child: Icon(icon, size: 20),
      ),
    );
  }
}

class _TelemetryChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _TelemetryChip({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: AppRadius.pillAll,
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return chip;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.pillAll,
      child: chip,
    );
  }
}

class _HeroMetric extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color valueColor;
  final ThemeData theme;

  const _HeroMetric({
    required this.icon,
    required this.value,
    required this.label,
    required this.valueColor,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: valueColor.withValues(alpha: 0.85)),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: valueColor,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: _DriverDeliveriesScreenState._heroMuted,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final int count;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    required this.count,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.pillAll,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.md,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            gradient: selected ? AppGradients.gold : null,
            color: selected ? null : theme.colorScheme.surfaceContainerLow,
            borderRadius: AppRadius.pillAll,
            border: Border.all(
              color: selected
                  ? Colors.transparent
                  : theme.colorScheme.outlineVariant,
            ),
            boxShadow: selected ? const [AppShadows.goldGlowSm] : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: selected
                    ? const Color(0xFF1A1400)
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? const Color(0xFF1A1400)
                      : theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: 5,
                  vertical: 1,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFF1A1400).withValues(alpha: 0.14)
                      : colors.goldMuted,
                  borderRadius: AppRadius.pillAll,
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: selected ? const Color(0xFF1A1400) : colors.gold,
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

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final AppColors colors;
  final ThemeData theme;

  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.colors,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: AppRadius.mdAll,
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Icon(icon, size: 19, color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _ViewToggle extends StatelessWidget {
  final bool isMapView;
  final ValueChanged<bool> onChanged;

  const _ViewToggle({required this.isMapView, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;

    return Container(
      padding: const EdgeInsetsDirectional.all(3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ViewToggleButton(
            icon: Icons.view_list_rounded,
            tooltip: 'عرض القائمة',
            selected: !isMapView,
            onTap: () => onChanged(false),
            colors: colors,
            theme: theme,
          ),
          _ViewToggleButton(
            icon: Icons.map_rounded,
            tooltip: 'عرض الخريطة',
            selected: isMapView,
            onTap: () => onChanged(true),
            colors: colors,
            theme: theme,
          ),
        ],
      ),
    );
  }
}

class _ViewToggleButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;
  final AppColors colors;
  final ThemeData theme;

  const _ViewToggleButton({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
    required this.colors,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.smAll,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 34,
            height: 32,
            decoration: BoxDecoration(
              gradient: selected ? AppGradients.gold : null,
              borderRadius: AppRadius.smAll,
            ),
            child: Icon(
              icon,
              size: 17,
              color: selected
                  ? const Color(0xFF1A1400)
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  final int count;
  final Color color;

  const _SectionTitle({
    required this.title,
    required this.icon,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: AppSpacing.xs),
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Container(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: AppRadius.pillAll,
            border: Border.all(color: color.withValues(alpha: 0.22)),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _PanelCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _PanelCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;

    return Container(
      padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: AppRadius.xlAll,
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.75),
        ),
        boxShadow: theme.brightness == Brightness.dark
            ? AppShadows.cardSoftDark
            : AppShadows.cardSoftLight,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsetsDirectional.all(5),
                decoration: BoxDecoration(
                  color: colors.goldMuted,
                  borderRadius: AppRadius.smAll,
                ),
                child: Icon(icon, size: 13, color: colors.gold),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

class _SideMetricRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SideMetricRow({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          value,
          style: theme.textTheme.labelMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _SideSwitchRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SideSwitchRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;

    return Row(
      children: [
        Icon(
          icon,
          size: 17,
          color: value ? colors.gold : theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Switch.adaptive(
          value: value,
          onChanged: onChanged,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ],
    );
  }
}

class _SidePanelEmpty extends StatelessWidget {
  final IconData icon;
  final String message;

  const _SidePanelEmpty({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;

    return Column(
      children: [
        Icon(icon, size: 30, color: colors.success),
        const SizedBox(height: AppSpacing.sm),
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
