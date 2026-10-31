import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:core/core.dart';
import 'package:staff_app/router/staff_router.dart';
import '../features/cashier/models/pos_models.dart';

import '../services/staff_audit_logger.dart';
import '../services/app_update_service.dart';

export '../features/cashier/models/pos_models.dart';
export '../services/staff_audit_logger.dart';
export '../services/app_update_service.dart';
export '../features/common/widgets/app_update_dialog.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final staffAuditLoggerProvider = Provider<StaffAuditLogger>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return StaffAuditLogger(client);
});

final supabaseServiceProvider = Provider<SupabaseService>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return SupabaseService(client);
});

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

/// Offline sync worker — started once; drains queue on reconnect.
final offlineSyncServiceProvider = Provider<OfflineSyncService>((ref) {
  final svc = OfflineSyncService(
    db: ref.watch(appDatabaseProvider),
    client: ref.watch(supabaseClientProvider),
    service: ref.watch(supabaseServiceProvider),
  );
  svc.start();
  ref.onDispose(svc.dispose);
  return svc;
});

/// Reactive pending-operations count — drives the offline indicator badge.
final pendingOpsCountProvider = StreamProvider<int>((ref) async* {
  final db = ref.watch(appDatabaseProvider);
  // Poll every 5 seconds — lightweight SQLite count query.
  while (true) {
    yield await db.countPendingOps();
    await Future<void>.delayed(const Duration(seconds: 5));
  }
});

/// Connectivity state stream.
final connectivityProvider = StreamProvider<bool>((ref) {
  return ConnectivityService.instance.onStatusChange;
});

final productRepositoryProvider = Provider<IProductRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final service = ref.watch(supabaseServiceProvider);
  final db = ref.watch(appDatabaseProvider);
  return ProductRepositoryImpl(client: client, service: service, db: db);
});

final orderRepositoryProvider = Provider<IOrderRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final service = ref.watch(supabaseServiceProvider);
  final db = ref.watch(appDatabaseProvider);
  return OrderRepositoryImpl(client: client, service: service, db: db);
});

final purchaseRepositoryProvider = Provider<IPurchaseRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final service = ref.watch(supabaseServiceProvider);
  final db = ref.watch(appDatabaseProvider);
  return PurchaseRepositoryImpl(client: client, service: service, db: db);
});

final purchasesListProvider = FutureProvider<List<PurchaseEntity>>((ref) async {
  final repo = ref.watch(purchaseRepositoryProvider);
  return repo.getPurchases();
});

final suppliersProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final repo = ref.watch(purchaseRepositoryProvider);
  return repo.getSuppliers();
});

final settlementRepositoryProvider = Provider<ISettlementRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final service = ref.watch(supabaseServiceProvider);
  return SettlementRepositoryImpl(client: client, service: service);
});

final customerRepositoryProvider = Provider<ICustomerRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final service = ref.watch(supabaseServiceProvider);
  final db = ref.watch(appDatabaseProvider);
  return CustomerRepositoryImpl(client: client, service: service, db: db);
});

final staffLocalAuthStoreProvider = Provider<StaffLocalAuthStore>((ref) {
  return const StaffLocalAuthStore();
});

final authRepositoryProvider = Provider<IAuthRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final localStore = ref.watch(staffLocalAuthStoreProvider);
  return AuthRepositoryImpl(client: client, localStore: localStore);
});

final appUpdateRepositoryProvider = Provider<IAppUpdateRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final service = ref.watch(supabaseServiceProvider);
  return AppUpdateRepositoryImpl(client: client, service: service);
});

final appUpdateServiceProvider = Provider<AppUpdateService>((ref) {
  final repo = ref.watch(appUpdateRepositoryProvider);
  return AppUpdateService(repository: repo, appType: 'staff_app');
});

final appUpdateCheckProvider =
    FutureProvider<AppUpdateCheckResult>((ref) async {
  final service = ref.watch(appUpdateServiceProvider);
  return service.checkForUpdate();
});

/// Staff shown on the PIN terminal. This uses the public directory action so
/// it can load before a Supabase session exists; moderators are excluded.
final liveStaffUsersProvider = FutureProvider<List<UserEntity>>((ref) async {
  final repo = ref.watch(authRepositoryProvider);
  return repo.getStaffDirectory();
});

final staffMembersProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final rows = await client
      .from('users')
      .select('id, name, phone, role, active, language, created_at')
      .neq('role', 'customer')
      .isFilter('deleted_at', null)
      .order('created_at', ascending: false);
  return List<Map<String, dynamic>>.from(rows as List);
});

// Products provider
final productsSearchQueryProvider = StateProvider<String>((ref) => '');

final liveProductsProvider = FutureProvider<List<ProductEntity>>((ref) async {
  final repo = ref.watch(productRepositoryProvider);
  final query = ref.watch(productsSearchQueryProvider);
  return repo.getProducts(search: query, onlyActive: true);
});

/// Derives the distinct, sorted category list from the full product catalogue
/// (unfiltered by search so all categories always appear in the bar).
/// Returns an empty list while products are loading.
final posCategoryListProvider = FutureProvider<List<String>>((ref) async {
  final repo = ref.watch(productRepositoryProvider);
  final all = await repo.getProducts(onlyActive: true);
  final cats = all
      .map((p) => p.category.trim())
      .where((c) => c.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
  return cats;
});

// Active Customer in Cart
final posActiveCustomerProvider =
    StateProvider<CustomerProfileEntity?>((ref) => null);

// Held Tickets (Suspended Carts)
final posHeldTicketsProvider = StateProvider<List<PosHeldTicket>>((ref) => []);

// Active Cashier Shift Session with local offline persistence and replay
class PosShiftNotifier extends StateNotifier<PosShiftSession?> {
  final StaffLocalAuthStore localStore;
  final AppDatabase db;
  final SupabaseClient? client;

  PosShiftNotifier({
    required this.localStore,
    required this.db,
    this.client,
  }) : super(null) {
    _restoreShift();
  }

  Future<void> _restoreShift() async {
    try {
      final jsonStr = await localStore.getActiveShiftJson();
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final m = jsonDecode(jsonStr) as Map<String, dynamic>;
        state = PosShiftSession(
          id: m['id'] as String,
          zReportNumber: (m['zReportNumber'] as num).toInt(),
          cashierId: m['cashierId'] as String,
          cashierName: m['cashierName'] as String,
          openingFloatCentimes: (m['openingFloatCentimes'] as num).toInt(),
          cashSalesCentimes: (m['cashSalesCentimes'] as num?)?.toInt() ?? 0,
          creditSalesCentimes: (m['creditSalesCentimes'] as num?)?.toInt() ?? 0,
          collectedDebtCashCentimes:
              (m['collectedDebtCashCentimes'] as num?)?.toInt() ?? 0,
          supplierPaymentsCashCentimes:
              (m['supplierPaymentsCashCentimes'] as num?)?.toInt() ?? 0,
          driverSettlementCashCentimes:
              (m['driverSettlementCashCentimes'] as num?)?.toInt() ?? 0,
          returnsCentimes: (m['returnsCentimes'] as num?)?.toInt() ?? 0,
          openedAt: DateTime.parse(m['openedAt'] as String),
          isOpen: (m['isOpen'] as bool?) ?? true,
        );
      }
    } catch (_) {}
  }

  Future<void> _persistCurrentState() async {
    if (state == null) {
      await localStore.clearActiveShift();
    } else {
      final m = {
        'id': state!.id,
        'zReportNumber': state!.zReportNumber,
        'cashierId': state!.cashierId,
        'cashierName': state!.cashierName,
        'openingFloatCentimes': state!.openingFloatCentimes,
        'cashSalesCentimes': state!.cashSalesCentimes,
        'creditSalesCentimes': state!.creditSalesCentimes,
        'collectedDebtCashCentimes': state!.collectedDebtCashCentimes,
        'supplierPaymentsCashCentimes': state!.supplierPaymentsCashCentimes,
        'driverSettlementCashCentimes': state!.driverSettlementCashCentimes,
        'returnsCentimes': state!.returnsCentimes,
        'openedAt': state!.openedAt.toIso8601String(),
        'isOpen': state!.isOpen,
      };
      await localStore.saveActiveShiftJson(jsonEncode(m));
    }
  }

  void openShift({
    required String cashierId,
    required String cashierPin,
    required String cashierName,
    required int openingFloatCentimes,
  }) async {
    final shiftId = const Uuid().v4();
    final zNum = (DateTime.now().millisecondsSinceEpoch ~/ 1000) % 1000000;
    final openedAt = DateTime.now();
    final clientId = const Uuid().v4();

    state = PosShiftSession(
      id: shiftId,
      zReportNumber: zNum,
      cashierId: cashierId,
      cashierName: cashierName,
      openingFloatCentimes: openingFloatCentimes,
      openedAt: openedAt,
      isOpen: true,
    );

    _persistCurrentState();

    final payload = {
      'shift_id': shiftId,
      'cashier_id': cashierId,
      'cashier_pin': cashierPin,
      'cashier_name': cashierName,
      'opening_float_centimes': openingFloatCentimes,
      'z_report_number': zNum,
      'opened_at': openedAt.toIso8601String(),
    };

    if (ConnectivityService.instance.isOnline && client != null) {
      try {
        await client!.rpc('rpc_open_pos_shift', params: {
          'p_client_id': clientId,
          'p_cashier_id': cashierId,
          'p_cashier_pin': cashierPin,
          'p_cashier_name': cashierName,
          'p_opening_float': openingFloatCentimes,
          'p_z_report_sequence': zNum,
          'p_opened_at': openedAt.toIso8601String(),
        });
        return;
      } catch (_) {
        // Enqueue offline operation on failure
      }
    }

    db.enqueuePendingOp(PendingOperationsCompanion.insert(
      clientId: clientId,
      operationType: 'pos_shift_open',
      payloadJson: jsonEncode(payload),
      createdAt: DateTime.now(),
    ));
  }

  void registerSale({required int cashCentimes, required int creditCentimes}) {
    if (state == null) return;
    state = state!.copyWith(
      cashSalesCentimes: state!.cashSalesCentimes + cashCentimes,
      creditSalesCentimes: state!.creditSalesCentimes + creditCentimes,
    );
    _persistCurrentState();
  }

  void registerReturn({required int refundCentimes}) {
    if (state == null) return;
    state = state!.copyWith(
      returnsCentimes: state!.returnsCentimes + refundCentimes,
    );
    _persistCurrentState();
  }

  void registerDebtCashPayment({required int cashCentimes}) {
    if (state == null || cashCentimes <= 0) return;
    state = state!.copyWith(
      collectedDebtCashCentimes:
          state!.collectedDebtCashCentimes + cashCentimes,
    );
    _persistCurrentState();
  }

  void registerSupplierCashPayment({required int cashCentimes}) {
    if (state == null || cashCentimes <= 0) return;
    state = state!.copyWith(
      supplierPaymentsCashCentimes:
          state!.supplierPaymentsCashCentimes + cashCentimes,
    );
    _persistCurrentState();
  }

  void registerDriverSettlement({required int cashCentimes}) {
    if (state == null || cashCentimes <= 0) return;
    state = state!.copyWith(
      driverSettlementCashCentimes:
          state!.driverSettlementCashCentimes + cashCentimes,
    );
    _persistCurrentState();
  }

  ZReportSummary closeShift({
    required String cashierPin,
    required int countedCashCentimes,
    required Map<int, int> denominations,
  }) {
    final current = state!;
    final variance = countedCashCentimes - current.expectedCashInDrawerCentimes;
    final closedAt = DateTime.now();
    final clientId = const Uuid().v4();

    final summary = ZReportSummary(
      zNumber: current.zReportNumber,
      cashierName: current.cashierName,
      openedAt: current.openedAt,
      closedAt: closedAt,
      openingFloatCentimes: current.openingFloatCentimes,
      cashSalesCentimes: current.cashSalesCentimes,
      creditSalesCentimes: current.creditSalesCentimes,
      collectedDebtCashCentimes: current.collectedDebtCashCentimes,
      supplierPaymentsCashCentimes: current.supplierPaymentsCashCentimes,
      driverSettlementCashCentimes: current.driverSettlementCashCentimes,
      totalSalesCentimes:
          current.cashSalesCentimes + current.creditSalesCentimes,
      returnsCentimes: current.returnsCentimes,
      expectedCashCentimes: current.expectedCashInDrawerCentimes,
      countedCashCentimes: countedCashCentimes,
      varianceCentimes: variance,
      denominations: denominations,
    );

    state = null; // Shift closed
    _persistCurrentState();

    final payload = {
      'shift_id': current.id,
      'cashier_id': current.cashierId,
      'cashier_pin': cashierPin,
      'cashier_name': current.cashierName,
      'z_number': summary.zNumber,
      'expected_centimes': summary.expectedCashCentimes,
      'counted_centimes': summary.countedCashCentimes,
      'variance_centimes': summary.varianceCentimes,
      'cash_sales_centimes': summary.cashSalesCentimes,
      'credit_sales_centimes': summary.creditSalesCentimes,
      'debt_collected_centimes': summary.collectedDebtCashCentimes,
      'supplier_payments_centimes': summary.supplierPaymentsCashCentimes,
      'driver_settlement_centimes': summary.driverSettlementCashCentimes,
      'returns_centimes': summary.returnsCentimes,
      'opened_at': summary.openedAt.toIso8601String(),
      'closed_at': closedAt.toIso8601String(),
      'denominations': denominations,
    };

    if (ConnectivityService.instance.isOnline && client != null) {
      client!
          .rpc('rpc_close_pos_shift', params: {
            'p_client_id': clientId,
            'p_shift_id': current.id,
            'p_cashier_id': current.cashierId,
            'p_cashier_pin': cashierPin,
            'p_z_report_sequence': summary.zNumber,
            'p_expected_cash': summary.expectedCashCentimes,
            'p_actual_cash': summary.countedCashCentimes,
            'p_variance': summary.varianceCentimes,
            'p_cash_sales': summary.cashSalesCentimes,
            'p_credit_sales': summary.creditSalesCentimes,
            'p_debt_collected': summary.collectedDebtCashCentimes,
            'p_supplier_payments': summary.supplierPaymentsCashCentimes,
            'p_driver_settlements': summary.driverSettlementCashCentimes,
            'p_returns_amount': summary.returnsCentimes,
            'p_denominations': denominations,
            'p_closed_at': closedAt.toIso8601String(),
          })
          .then((_) {})
          .catchError((_) {
            db.enqueuePendingOp(PendingOperationsCompanion.insert(
              clientId: clientId,
              operationType: 'pos_shift_close',
              payloadJson: jsonEncode(payload),
              createdAt: DateTime.now(),
            ));
          });
    } else {
      db.enqueuePendingOp(PendingOperationsCompanion.insert(
        clientId: clientId,
        operationType: 'pos_shift_close',
        payloadJson: jsonEncode(payload),
        createdAt: DateTime.now(),
      ));
    }

    return summary;
  }
}

final posActiveShiftProvider =
    StateNotifierProvider<PosShiftNotifier, PosShiftSession?>((ref) {
  final localStore = ref.watch(staffLocalAuthStoreProvider);
  final db = ref.watch(appDatabaseProvider);
  final client = ref.watch(supabaseClientProvider);
  return PosShiftNotifier(localStore: localStore, db: db, client: client);
});

final pendingDriverSettlementsProvider =
    FutureProvider<List<DriverSettlementSummaryEntity>>((ref) async {
  final repo = ref.watch(settlementRepositoryProvider);
  return repo.getPendingDriverSettlements();
});

final driverUnsettledOrdersProvider =
    FutureProvider.family<List<OrderEntity>, String>((ref, driverId) async {
  final repo = ref.watch(settlementRepositoryProvider);
  return repo.getDriverUnsettledOrders(driverId);
});

final recentSettlementsProvider =
    FutureProvider.family<List<SettlementEntity>, String?>(
        (ref, driverId) async {
  final repo = ref.watch(settlementRepositoryProvider);
  return repo.getRecentSettlements(driverId: driverId);
});

final driverOrdersProvider = FutureProvider<List<OrderEntity>>((ref) async {
  final repo = ref.watch(orderRepositoryProvider);
  final user = ref.watch(authStateProvider);
  if (user == null) return [];

  // Keep every active task (limited only by what is assigned to the driver)
  // while bounding the completed history. A single `limit` on all orders could
  // hide an old active task behind newer completed ones.
  final results = await Future.wait<List<OrderEntity>>([
    repo.getOrders(
      driverId: user.id,
      statuses: _activeOnlineStatuses.toList(growable: false),
    ),
    repo.getOrders(
      driverId: user.id,
      statuses: _terminalOnlineStatuses.toList(growable: false),
      limit: 60,
    ),
  ]);

  return [...results[0], ...results[1]];
});

final driverWalletBalanceProvider = FutureProvider<int>((ref) async {
  final repo = ref.watch(settlementRepositoryProvider);
  final user = ref.watch(authStateProvider);
  if (user == null) return 0;
  return repo.getDriverExpectedWallet(user.id);
});

final suppliersWithBalancesProvider =
    FutureProvider<List<SupplierProfileEntity>>((ref) async {
  final repo = ref.watch(purchaseRepositoryProvider);
  return repo.getSuppliersWithBalances();
});

/// Orders that still need manager/cashier action. These stay live and are
/// never limited by the history date filter.
const Set<OrderStatus> _activeOnlineStatuses = {
  OrderStatus.submitted,
  OrderStatus.requiresManagerReview,
  OrderStatus.confirmed,
  OrderStatus.preparing,
  OrderStatus.ready,
  OrderStatus.assigned,
  OrderStatus.accepted,
  OrderStatus.outForDelivery,
};

/// Orders that belong in the date-filtered history.
const Set<OrderStatus> _terminalOnlineStatuses = {
  OrderStatus.delivered,
  OrderStatus.settled,
  OrderStatus.refused,
  OrderStatus.cancelled,
};

bool _isActiveOnlineStatus(OrderStatus status) =>
    _activeOnlineStatuses.contains(status);

/// Incremented when an online order enters or leaves terminal history.
/// The history provider listens to this and refreshes with a debounce.
final managerHistoryRevisionProvider = StateProvider<int>((ref) => 0);

class ManagerOrderHistoryState {
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final List<OrderEntity> orders;
  final bool isLoading;
  final bool isLoadingMore;
  final Object? error;
  final bool hasMore;

  const ManagerOrderHistoryState({
    required this.rangeStart,
    required this.rangeEnd,
    this.orders = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
    this.hasMore = true,
  });

  ManagerOrderHistoryState copyWith({
    DateTime? rangeStart,
    DateTime? rangeEnd,
    List<OrderEntity>? orders,
    bool? isLoading,
    bool? isLoadingMore,
    Object? error,
    bool clearError = false,
    bool? hasMore,
  }) {
    return ManagerOrderHistoryState(
      rangeStart: rangeStart ?? this.rangeStart,
      rangeEnd: rangeEnd ?? this.rangeEnd,
      orders: orders ?? this.orders,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: clearError ? null : (error ?? this.error),
      hasMore: hasMore ?? this.hasMore,
    );
  }
}

class ManagerOnlineOrderHistoryNotifier
    extends StateNotifier<ManagerOrderHistoryState> {
  ManagerOnlineOrderHistoryNotifier({
    required IOrderRepository repository,
    required DateTime initialStart,
    required DateTime initialEnd,
  })  : _repository = repository,
        super(ManagerOrderHistoryState(
          rangeStart: _startOfDay(initialStart),
          rangeEnd: _endOfDay(initialEnd),
          isLoading: true,
        )) {
    unawaited(refresh());
  }

  static const int pageSize = 100;

  final IOrderRepository _repository;
  int _requestToken = 0;

  Future<void> setRange({
    required DateTime start,
    required DateTime end,
  }) async {
    state = state.copyWith(
      rangeStart: _startOfDay(start),
      rangeEnd: _endOfDay(end),
      orders: const [],
      isLoading: true,
      isLoadingMore: false,
      hasMore: true,
      clearError: true,
    );
    await refresh();
  }

  Future<void> refresh() async {
    final token = ++_requestToken;
    state = state.copyWith(
      isLoading: true,
      isLoadingMore: false,
      clearError: true,
    );
    await _fetch(page: 1, replace: true, token: token);
  }

  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    final token = _requestToken;
    state = state.copyWith(isLoadingMore: true, clearError: true);
    final nextPage = (state.orders.length ~/ pageSize) + 1;
    await _fetch(page: nextPage, replace: false, token: token);
  }

  Future<void> _fetch({
    required int page,
    required bool replace,
    required int token,
  }) async {
    try {
      final rows = await _repository.getOrdersPage(
        page: page,
        pageSize: pageSize,
        channel: OrderChannel.online,
        statuses: _terminalOnlineStatuses.toList(growable: false),
        createdFrom: state.rangeStart,
        createdTo: state.rangeEnd,
      );
      if (!mounted || token != _requestToken) return;

      final orders = replace ? rows : [...state.orders, ...rows];
      state = state.copyWith(
        orders: orders,
        isLoading: false,
        isLoadingMore: false,
        hasMore: rows.length == pageSize,
        clearError: true,
      );
    } catch (e) {
      if (!mounted || token != _requestToken) return;
      state = state.copyWith(
        isLoading: false,
        isLoadingMore: false,
        error: e,
      );
    }
  }

  static DateTime _startOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static DateTime _endOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
}

/// Date-filtered, paginated online-order history.
final managerOnlineOrderHistoryProvider = StateNotifierProvider<
    ManagerOnlineOrderHistoryNotifier, ManagerOrderHistoryState>((ref) {
  final repository = ref.watch(orderRepositoryProvider);
  final now = DateTime.now();
  final notifier = ManagerOnlineOrderHistoryNotifier(
    repository: repository,
    initialStart: DateTime(now.year, now.month, now.day - 29),
    initialEnd: DateTime(now.year, now.month, now.day),
  );

  Timer? refreshDebounce;
  ref.listen<int>(managerHistoryRevisionProvider, (_, __) {
    refreshDebounce?.cancel();
    refreshDebounce = Timer(const Duration(milliseconds: 600), () {
      if (notifier.mounted) unawaited(notifier.refresh());
    });
  });
  ref.onDispose(() => refreshDebounce?.cancel());

  return notifier;
});

/// Real-time stream of active online orders for the Manager.
///
/// There is no row limit and no date filter here: every active online order
/// stays live. Terminal orders are removed from this list and served by the
/// date-filtered history provider instead.
final managerOnlineOrdersProvider =
    StreamProvider<List<OrderEntity>>((ref) async* {
  final repo = ref.watch(orderRepositoryProvider);
  final client = ref.watch(supabaseClientProvider);

  var isDisposed = false;
  ref.onDispose(() => isDisposed = true);

  // 1. Initial snapshot: all active online orders.
  List<OrderEntity> currentOrders = await repo.getOrders(
    channel: OrderChannel.online,
    statuses: _activeOnlineStatuses.toList(growable: false),
  );
  if (isDisposed) return;
  yield currentOrders;

  final controller = StreamController<List<OrderEntity>>.broadcast();
  final pendingOrderIds = <String>{};
  Timer? debounceTimer;
  Timer? historyRevisionTimer;
  bool isWindowLoading = false;

  void publish(List<OrderEntity> orders) {
    if (!isDisposed && !controller.isClosed) controller.add(orders);
  }

  void scheduleHistoryRevision() {
    if (isDisposed) return;
    historyRevisionTimer?.cancel();
    historyRevisionTimer = Timer(const Duration(milliseconds: 500), () {
      if (!isDisposed) {
        ref.read(managerHistoryRevisionProvider.notifier).state++;
      }
    });
  }

  List<OrderEntity> mergeActiveOrders(Iterable<OrderEntity> updates) {
    final byId = <String, OrderEntity>{
      for (final order in currentOrders) order.id: order,
    };
    for (final order in updates) {
      if (order.channel != OrderChannel.online) continue;
      if (_isActiveOnlineStatus(order.status)) {
        byId[order.id] = order;
      } else {
        byId.remove(order.id);
      }
    }
    return byId.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> fetchOrder(String orderId) async {
    try {
      final order = await repo.getOrderById(orderId);
      if (order.channel != OrderChannel.online) return;
      currentOrders = mergeActiveOrders([order]);
      publish(currentOrders);
      if (!_isActiveOnlineStatus(order.status)) {
        scheduleHistoryRevision();
      }
    } catch (e) {
      // The order may have been deleted, or the row may not be visible yet.
      // The 60-second fallback reconciles the live list.
      debugPrint('[managerOnlineOrders] Single-order fetch failed: $e');
    }
  }

  void scheduleOrderFetch(String orderId) {
    pendingOrderIds.add(orderId);
    debounceTimer?.cancel();
    debounceTimer = Timer(const Duration(milliseconds: 250), () {
      final ids = pendingOrderIds.toList(growable: false);
      pendingOrderIds.clear();
      for (final id in ids) {
        unawaited(fetchOrder(id));
      }
    });
  }

  Future<void> refreshActiveOrders() async {
    if (isWindowLoading || isDisposed) return;
    isWindowLoading = true;
    try {
      final fresh = await repo.getOrders(
        channel: OrderChannel.online,
        statuses: _activeOnlineStatuses.toList(growable: false),
      );
      if (isDisposed) return;
      currentOrders = fresh;
      publish(currentOrders);
    } catch (e) {
      debugPrint('[managerOnlineOrders] Live refresh failed: $e');
    } finally {
      isWindowLoading = false;
    }
  }

  // 2. Realtime: order headers only. POS/store events are ignored, and
  // order_items is not subscribed because a single order fetch already
  // includes its items.
  final channel = client.channel(
    'manager_online_orders_${DateTime.now().millisecondsSinceEpoch}',
  )..onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'orders',
      callback: (payload) {
        if (isDisposed) return;

        if (payload.eventType == PostgresChangeEvent.delete) {
          final id = payload.oldRecord['id'] as String?;
          if (id == null) return;
          final wasTracked = currentOrders.any((o) => o.id == id);
          if (!wasTracked) return;
          currentOrders = currentOrders.where((o) => o.id != id).toList();
          publish(currentOrders);
          scheduleHistoryRevision();
          return;
        }

        final record = payload.newRecord;
        final id = record['id'] as String?;
        if (id == null) return;

        final channelValue = record['channel'] as String?;
        final isTracked = currentOrders.any((o) => o.id == id);
        if (!isTracked && channelValue != 'online') return;

        final statusValue = record['status'] as String?;
        final status =
            statusValue == null ? null : OrderStatus.fromString(statusValue);

        // Terminal order: remove it from the live pipeline immediately and
        // let the date-filtered history provider refresh.
        if (status != null && !_isActiveOnlineStatus(status)) {
          if (isTracked) {
            currentOrders = currentOrders.where((o) => o.id != id).toList();
            publish(currentOrders);
          }
          scheduleHistoryRevision();
          return;
        }

        // New/updated active online order: fetch just this order.
        scheduleOrderFetch(id);
      },
    );

  channel.subscribe((status, [error]) {
    if (status == RealtimeSubscribeStatus.subscribed) {
      unawaited(refreshActiveOrders());
    }
  });

  // 3. Fast safety net for missed realtime inserts/updates. Realtime is the
  // primary path; this only restores the small active-order list.
  final timer = Timer.periodic(
    const Duration(seconds: 60),
    (_) => unawaited(refreshActiveOrders()),
  );

  ref.onDispose(() {
    timer.cancel();
    debounceTimer?.cancel();
    historyRevisionTimer?.cancel();
    channel.unsubscribe();
    client.removeChannel(channel);
    controller.close();
  });

  yield* controller.stream;
});

/// Count of online orders awaiting manager review.
final unverifiedOrdersCountProvider = Provider<int>((ref) {
  final orders = ref.watch(managerOnlineOrdersProvider).value ?? [];
  return orders
      .where((o) =>
          o.status == OrderStatus.submitted ||
          o.status == OrderStatus.requiresManagerReview)
      .length;
});

// Customer Debt & Ledger Providers
final customerLedgerProvider =
    FutureProvider.family<List<CustomerLedgerEntryEntity>, String>(
        (ref, customerId) async {
  final repo = ref.watch(customerRepositoryProvider);
  return repo.getCustomerLedger(customerId);
});

final customerUnpaidOrdersProvider =
    FutureProvider.family<List<CustomerUnpaidOrderEntity>, String>(
        (ref, customerId) async {
  final repo = ref.watch(customerRepositoryProvider);
  return repo.getCustomerUnpaidOrders(customerId);
});

// staffListProvider
/*List<UserEntity> get _availableStaff {
    final currentAuth = ref.read(authStateProvider);
    final list = <UserEntity>[];
    final staffList = ref.read(staffListProvider);
    if (currentAuth != null) {
      list.add(currentAuth);
    }
    for (final staff in staffList) {
      if (!list.any((u) => u.id == staff.id)) {
        list.add(staff);
      }
    }
    return list;
  }
*/
final staffListProvider = FutureProvider<List<UserEntity>>((ref) async {
  final repo = ref.watch(authRepositoryProvider);

  return repo.getStaffMembers();
});

// ------------------------------------------------------
// Enterprise POS Cart StateNotifier
// ------------------------------------------------------
class PosCartNotifier extends StateNotifier<List<PosCartItem>> {
  final Ref ref;

  PosCartNotifier(this.ref) : super([]);

  // 1. Add / Merge Product
  void addProduct(ProductEntity product, {int qty = 1, PriceTier? tier}) {
    final activeCustomer = ref.read(posActiveCustomerProvider);
    final effectiveTier =
        tier ?? activeCustomer?.priceTier ?? PriceTier.wholesale;

    final initialUnit = PosItemUnit.fromString(product.unit);
    final idx = state.indexWhere(
        (it) => it.productId == product.id && it.unit == initialUnit);
    if (idx != -1) {
      final existing = state[idx];
      final newQty = existing.quantity + qty;
      updateQuantity(existing.id, newQty);
    } else {
      final newItem =
          PosCartItem.fromProduct(product, qty: qty, tier: effectiveTier);
      state = [...state, newItem];
    }
  }

  // 2. Add Custom / Unlisted Item
  void addCustomItem(String name, int priceCentimes,
      {int qty = 1, PosItemUnit unit = PosItemUnit.piece}) {
    final customItem = PosCartItem.custom(
        name: name, priceCentimes: priceCentimes, qty: qty, unit: unit);
    state = [...state, customItem];
  }

  // 3. Update Quantity
  Result<void, Failure> updateQuantity(String itemId, int quantity) {
    if (quantity <= 0) {
      removeProduct(itemId);
      return const Success(null);
    }

    final item = state.firstWhere((it) => it.id == itemId);
    if (!item.isCustomItem &&
        (quantity * item.unitMultiplier) > item.availableStock) {
      return FailureResult(InsufficientStockFailure(
        'الكمية المطلوبة ($quantity) تتجاوز المخزون المتاح (${item.availableStock})',
      ));
    }

    state = state.map((it) {
      if (it.id == itemId) {
        var updated = it.copyWith(quantity: quantity);
        if (!it.isCustomItem &&
            it.activeTier != null &&
            it.availableTiers.isNotEmpty) {
          final totalQty = updated.totalPieces;
          final matches = it.availableTiers
              .where((p) => p.tier == it.activeTier && totalQty >= p.minQty)
              .toList();
          if (matches.isNotEmpty) {
            matches.sort((a, b) => b.minQty.compareTo(a.minQty));
            updated = updated.copyWith(
                baseUnitPriceCentimes: matches.first.priceCentimes);
          }
        }
        return updated;
      }
      return it;
    }).toList();
    return const Success(null);
  }

  // 4. Update Item Unit (Piece vs Carton)
  void setItemUnit(String itemId, PosItemUnit unit) {
    state = state.map((it) {
      if (it.id == itemId) {
        return it.copyWith(unit: unit);
      }
      return it;
    }).toList();
  }

  // 4b. Switch Price Tier (Retail / Wholesale / Bulk)
  void setItemTier(String itemId, PriceTier tier) {
    state = state.map((it) {
      if (it.id != itemId || it.isCustomItem) return it;
      final totalQty = it.totalPieces;
      final matches = it.availableTiers
          .where((p) => p.tier == tier && totalQty >= p.minQty)
          .toList();
      int newPrice;
      if (matches.isNotEmpty) {
        matches.sort((a, b) => b.minQty.compareTo(a.minQty));
        newPrice = matches.first.priceCentimes;
      } else {
        final tierRows =
            it.availableTiers.where((p) => p.tier == tier).toList();
        if (tierRows.isNotEmpty) {
          tierRows.sort((a, b) => a.minQty.compareTo(b.minQty));
          newPrice = tierRows.first.priceCentimes;
        } else {
          newPrice = it.baseUnitPriceCentimes;
        }
      }
      return it.copyWith(activeTier: tier, baseUnitPriceCentimes: newPrice);
    }).toList();
  }

  // 5. Line Item Discount
  void setItemDiscount(String itemId, {double? percent, int? fixedCentimes}) {
    state = state.map((it) {
      if (it.id == itemId) {
        return it.copyWith(
          discountPercent: percent ?? it.discountPercent,
          manualDiscountCentimes: fixedCentimes ?? it.manualDiscountCentimes,
        );
      }
      return it;
    }).toList();
  }

  void removeProduct(String itemId) {
    state = state.where((it) => it.id != itemId).toList();
  }

  void clear() {
    state = [];
    ref.read(posActiveCustomerProvider.notifier).state = null;
  }

  int get totalCentimes =>
      state.fold(0, (sum, item) => sum + item.lineTotalCentimes);

  /// Ticket value before any line percentage or fixed discount is applied.
  ///
  /// Used by the cart summary to show how much the cashier's price tier and
  /// manual discounts saved the customer.
  int get subtotalCentimes => state.fold(
        0,
        (sum, item) =>
            sum +
            item.baseUnitPriceCentimes * item.unitMultiplier * item.quantity,
      );

  /// Total savings granted on the ticket (never negative).
  int get discountCentimes {
    final saved = subtotalCentimes - totalCentimes;
    return saved > 0 ? saved : 0;
  }

  // 6. Suspend Cart (Hold Ticket)
  String holdCurrentCart() {
    if (state.isEmpty) return '';
    final ticketId = const Uuid().v4();
    final customer = ref.read(posActiveCustomerProvider);
    final label = customer != null
        ? '${customer.name} (#${state.length})'
        : 'زبون مباشر (${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')})';

    final heldTicket = PosHeldTicket(
      id: ticketId,
      label: label,
      customer: customer,
      items: List.from(state),
      heldAt: DateTime.now(),
    );

    ref
        .read(posHeldTicketsProvider.notifier)
        .update((list) => [...list, heldTicket]);
    clear();
    return ticketId;
  }

  // 7. Resume Held Cart
  void resumeTicket(String ticketId) {
    final heldTickets = ref.read(posHeldTicketsProvider);
    final target = heldTickets.firstWhere((t) => t.id == ticketId);

    state = target.items;
    ref.read(posActiveCustomerProvider.notifier).state = target.customer;
    ref
        .read(posHeldTicketsProvider.notifier)
        .update((list) => list.where((t) => t.id != ticketId).toList());
  }

  // 8. Checkout Execution with Customer Debt Verification
  Future<Result<String, Failure>> checkout({
    required String cashierId,
    String? customerId,
    required int paidCashCentimes,
    required int onAccountCentimes,
  }) async {
    final customer = ref.read(posActiveCustomerProvider);

    // Debt Limit check
    if (onAccountCentimes > 0) {
      if (customer == null && customerId == null) {
        return const FailureResult(CreditLimitExceededFailure(
            'لا يمكن البيع بالدين بدون حساب زبون مسجل.'));
      }
      if (customer != null && customer.isCreditExceeded(onAccountCentimes)) {
        return FailureResult(CreditLimitExceededFailure(
          'تجاوز سقف الائتمان! السقف: ${DzdFormatter.formatCentimes(customer.creditLimitCentimes)}, الدين الحالي: ${DzdFormatter.formatCentimes(customer.currentDebtCentimes)}',
        ));
      }
    }

    try {
      final orderRepo = ref.read(orderRepositoryProvider);
      final itemsPayload = state.map((it) {
        return {
          'product_id': it.productId,
          'quantity': it.totalPieces,
          'unit_price':
              (it.effectiveUnitPriceCentimes / it.unitMultiplier).round(),
          'unit_cost': it.unitCostCentimes,
        };
      }).toList();

      final orderId = await orderRepo.createInStoreSale(
        cashierId: cashierId,
        customerId: customer?.id ?? customerId,
        items: itemsPayload,
        paidCashCentimes: paidCashCentimes,
        onAccountCentimes: onAccountCentimes,
      );

      // Register in active shift if present
      ref.read(posActiveShiftProvider.notifier).registerSale(
            cashCentimes: paidCashCentimes,
            creditCentimes: onAccountCentimes,
          );

      clear();
      ref.invalidate(liveProductsProvider);
      return Success(orderId);
    } catch (e) {
      return FailureResult(
          ServerFailure('تعذر تسجيل عملية البيع: ${e.toString()}'));
    }
  }

  // 9. Process Sales Return
  Future<Result<void, Failure>> processReturn({
    required String originalOrderId,
    required String cashierId,
    required String callerPin,
    required List<Map<String, dynamic>> returnItems,
    required int totalRefundCentimes,
    required String reason,
    required bool restockInventory,
  }) async {
    try {
      final supabaseService = ref.read(supabaseServiceProvider);

      if (restockInventory) {
        for (final item in returnItems) {
          await supabaseService.adjustStock(
            userId: cashierId,
            callerPin: callerPin,
            productId: item['productId'] as String,
            qtyChange: item['qty'] as int,
            reason: 'إرجاع مبيعات: $reason (وصل #$originalOrderId)',
          );
        }
      }

      // Record return against shift
      ref.read(posActiveShiftProvider.notifier).registerReturn(
            refundCentimes: totalRefundCentimes,
          );

      ref.invalidate(liveProductsProvider);
      return const Success(null);
    } catch (e) {
      return FailureResult(
          ServerFailure('تعذر إتمام عملية الإرجاع: ${e.toString()}'));
    }
  }
}

final posCartProvider =
    StateNotifierProvider<PosCartNotifier, List<PosCartItem>>((ref) {
  return PosCartNotifier(ref);
});
