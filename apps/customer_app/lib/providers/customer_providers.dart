import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/customer_models.dart';
import '../services/app_update_service.dart';
import '../services/customer_device_auth_service.dart';
import '../services/customer_local_store.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Infrastructure
// ─────────────────────────────────────────────────────────────────────────────

final sharedPreferencesProvider = Provider<SharedPreferences?>((ref) => null);

final customerLocalStoreProvider = Provider<CustomerLocalStore>((ref) {
  return CustomerLocalStore(ref.watch(sharedPreferencesProvider));
});

final customerSupabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final customerSupabaseServiceProvider = Provider<SupabaseService>((ref) {
  final client = ref.watch(customerSupabaseClientProvider);
  return SupabaseService(client);
});

final customerAppUpdateRepositoryProvider =
    Provider<IAppUpdateRepository>((ref) {
  final client = ref.watch(customerSupabaseClientProvider);
  final service = ref.watch(customerSupabaseServiceProvider);
  return AppUpdateRepositoryImpl(client: client, service: service);
});

final customerAppUpdateServiceProvider = Provider<AppUpdateService>((ref) {
  final repo = ref.watch(customerAppUpdateRepositoryProvider);
  return AppUpdateService(repository: repo, appType: 'customer_app');
});

// ─────────────────────────────────────────────────────────────────────────────
// Authentication
// ─────────────────────────────────────────────────────────────────────────────

final customerAuthRepositoryProvider = Provider<IAuthRepository>((ref) {
  return AuthRepositoryImpl(client: ref.watch(customerSupabaseClientProvider));
});

/// The server explicitly rejected this device. Unlike a transient network
/// error, this must invalidate the restored session and return to password
/// login.
class _DeviceBindingMismatch implements Exception {
  final String message;

  const _DeviceBindingMismatch(this.message);

  @override
  String toString() => message;
}

/// The single source of truth for the customer session.
///
/// There is no local/PIN fallback and no guest identity: the Supabase JWT is
/// resolved to a `public.users` row with role `customer`. Profile hydration and
/// device-token binding happen only after a real session exists.
class CustomerAuthController extends AsyncNotifier<UserEntity?> {
  StreamSubscription<AuthState>? _authSub;
  bool _disposed = false;
  bool _preparing = false;

  @override
  Future<UserEntity?> build() async {
    ref.onDispose(() {
      _disposed = true;
      _authSub?.cancel();
    });

    final client = ref.read(customerSupabaseClientProvider);
    _authSub = client.auth.onAuthStateChange.listen((authState) async {
      if (_disposed) return;
      if (authState.event == AuthChangeEvent.signedOut) {
        state = const AsyncData(null);
        return;
      }
      if (authState.event != AuthChangeEvent.tokenRefreshed &&
          authState.event != AuthChangeEvent.userUpdated) {
        return;
      }
      try {
        final user =
            await ref.read(customerAuthRepositoryProvider).getCurrentUser();
        if (_disposed) return;
        if (user == null || user.role != UserRole.customer) {
          if (user != null) {
            await ref.read(customerAuthRepositoryProvider).signOut();
          }
          state = const AsyncData(null);
          return;
        }
        state = AsyncData(user);
      } catch (e) {
        if (_disposed) return;
        state = AsyncError(e, StackTrace.current);
      }
    });

    final user =
        await ref.read(customerAuthRepositoryProvider).getCurrentUser();
    if (user != null && user.role != UserRole.customer) {
      await ref.read(customerAuthRepositoryProvider).signOut();
      return null;
    }
    if (user != null) {
      try {
        await _afterLogin(user, rotateDevice: false);
      } catch (e) {
        // A restored session that no longer matches the device binding must
        // not grant access to cached customer data. Clear it and show the
        // password login instead of leaving the gate stuck on an error screen.
        debugPrint('[CustomerAuth] session restore rejected: $e');
        await ref.read(customerAuthRepositoryProvider).signOut();
        if (_disposed) return null;
        return null;
      }
    }
    return user;
  }

  /// Phone + password login (no SMS provider required).
  Future<UserEntity> signIn({
    required String phone,
    required String password,
  }) async {
    final user = await ref
        .read(customerAuthRepositoryProvider)
        .signInWithPhoneAndPassword(phone, password);
    if (user.role != UserRole.customer) {
      await ref.read(customerAuthRepositoryProvider).signOut();
      throw Exception('هذا الحساب ليس حساب زبون.');
    }
    try {
      await _afterLogin(user, rotateDevice: true);
    } catch (e) {
      await ref.read(customerAuthRepositoryProvider).signOut();
      if (!_disposed) state = const AsyncData(null);
      rethrow;
    }
    if (!_disposed) state = AsyncData(user);
    return user;
  }

  Future<CustomerRegistrationResult> registerCustomer({
    required String name,
    required String phone,
    required String password,
  }) {
    return ref.read(customerAuthRepositoryProvider).registerCustomer(
          name: name,
          phone: phone,
          password: password,
        );
  }

  Future<CustomerPasswordResetResult> resetCustomerPassword({
    required String phone,
    required String recoveryCode,
    required String newPassword,
  }) {
    return ref.read(customerAuthRepositoryProvider).resetCustomerPassword(
          phone: phone,
          recoveryCode: recoveryCode,
          newPassword: newPassword,
        );
  }

  Future<void> signOut() async {
    // Revoke the server-side device binding while the JWT is still valid.
    // Offline logout still clears the local session; the next password login rotates
    // the token and replaces any stale binding.
    try {
      await ref
          .read(customerSupabaseClientProvider)
          .rpc('rpc_revoke_customer_device');
    } catch (e) {
      debugPrint('[CustomerAuth] device revoke failed: $e');
    }
    await ref.read(customerAuthRepositoryProvider).signOut();
    try {
      await CustomerDeviceAuthService.instance.clear();
    } catch (e) {
      debugPrint('[CustomerAuth] device token clear failed: $e');
    }
    ref.read(customerProfileProvider.notifier).clear();
    if (!_disposed) state = const AsyncData(null);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    try {
      final user =
          await ref.read(customerAuthRepositoryProvider).getCurrentUser();
      if (user != null) {
        await _afterLogin(user, rotateDevice: false);
      }
      if (!_disposed) state = AsyncData(user);
    } catch (e) {
      // `getCurrentUser` may fail on a dead network, and a device-binding
      // mismatch must not be retried with the same stale session. Sign out so
      // the login screen can recover; the server still requires a device token
      // for order submission and live tracking.
      debugPrint('[CustomerAuth] refresh rejected: $e');
      try {
        await ref.read(customerAuthRepositoryProvider).signOut();
      } catch (_) {}
      ref.read(customerProfileProvider.notifier).clear();
      if (!_disposed) state = const AsyncData(null);
    }
  }

  Future<void> _afterLogin(
    UserEntity user, {
    required bool rotateDevice,
  }) async {
    if (user.role != UserRole.customer) return;
    if (_preparing) return;
    _preparing = true;
    try {
      try {
        final profile =
            await ref.read(customerRepositoryProvider).getMyCustomerProfile();
        ref.read(customerProfileProvider.notifier).applyServerProfile(profile);
      } catch (e) {
        debugPrint('[CustomerAuth] profile hydration failed: $e');
      }

      final token = rotateDevice
          ? await CustomerDeviceAuthService.instance.rotate()
          : await CustomerDeviceAuthService.instance.getOrCreateDeviceToken();
      try {
        final res = await ref.read(customerSupabaseClientProvider).rpc(
          'rpc_bind_customer_device',
          params: {
            'p_device_token': token,
            'p_rotate': rotateDevice,
          },
        );
        if (res is! Map || res['success'] != true) {
          throw _DeviceBindingMismatch(
            res is Map
                ? (res['error']?.toString() ?? 'تعذر ربط الجهاز بالحساب.')
                : 'تعذر ربط الجهاز بالحساب.',
          );
        }
      } catch (e) {
        // A restored session may be opened without connectivity. Server-side
        // device checks still protect tracking and checkout, so only an
        // explicit mismatch blocks the restored session. A fresh password login is
        // online and must bind successfully before it is accepted.
        if (rotateDevice || e is _DeviceBindingMismatch) rethrow;
        debugPrint('[CustomerAuth] device binding deferred: $e');
      }
    } finally {
      _preparing = false;
    }
  }
}

final customerAuthStateProvider =
    AsyncNotifierProvider<CustomerAuthController, UserEntity?>(
  CustomerAuthController.new,
);



final _customerDbProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final customerProductRepositoryProvider = Provider<IProductRepository>((ref) {
  final client = ref.watch(customerSupabaseClientProvider);
  final service = SupabaseService(client);
  final db = ref.watch(_customerDbProvider);
  return ProductRepositoryImpl(
    client: client,
    service: service,
    db: db,
    isCustomerPortal: true,
  );
});

final customerOrderRepositoryProvider = Provider<IOrderRepository>((ref) {
  final client = ref.watch(customerSupabaseClientProvider);
  final service = SupabaseService(client);
  final db = ref.watch(_customerDbProvider);
  return OrderRepositoryImpl(client: client, service: service, db: db);
});

final customerRepositoryProvider = Provider<ICustomerRepository>((ref) {
  final client = ref.watch(customerSupabaseClientProvider);
  final service = SupabaseService(client);
  final db = ref.watch(_customerDbProvider);
  return CustomerRepositoryImpl(client: client, service: service, db: db);
});

/// Broadcasts connectivity transitions. Polling is started once in `main()`;
/// this provider also starts it defensively for embedded/preview usage.
final customerOnlineProvider = StreamProvider<bool>((ref) async* {
  final service = ConnectivityService.instance;
  service.startPolling();
  yield service.isOnline;
  yield* service.onStatusChange;
});

/// Synchronous convenience read for widgets that only need a boolean.
final customerIsOnlineProvider = Provider<bool>((ref) {
  return ref.watch(customerOnlineProvider).valueOrNull ??
      ConnectivityService.instance.isOnline;
});

// ─────────────────────────────────────────────────────────────────────────────
// Profile
// ─────────────────────────────────────────────────────────────────────────────

class CustomerProfileInfo {
  final String? id;
  final String? userId;
  final String name;
  final String phone;
  final PriceTier priceTier;
  final String wilaya;
  final String commune;
  final String addressText;
  final double? latitude;
  final double? longitude;
  final bool isSynced;

  const CustomerProfileInfo({
    this.id,
    this.userId,
    this.name = '',
    this.phone = '',
    this.priceTier = PriceTier.retail,
    this.wilaya = '',
    this.commune = '',
    this.addressText = '',
    this.latitude,
    this.longitude,
    this.isSynced = false,
  });

  static final _phoneRe = RegExp(r'^(0[5-7]\d{8}|\+213[5-7]\d{8})$');
  static bool isValidPhone(String v) => _phoneRe.hasMatch(v.trim());

  bool get isComplete =>
      name.trim().isNotEmpty &&
      isValidPhone(phone) &&
      wilaya.trim().isNotEmpty &&
      commune.trim().isNotEmpty &&
      addressText.trim().isNotEmpty;

  bool get hasAccount => id != null && id!.isNotEmpty;

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'customer_id': id,
      if (userId != null) 'user_id': userId,
      'customer_name': name,
      'store_name': name,
      'customer_phone': phone,
      'phone': phone,
      'wilaya': wilaya,
      'commune': commune,
      'address_text': addressText,
      'address': '$wilaya, $commune - $addressText',
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'name': name,
        'phone': phone,
        'priceTier': priceTier.name,
        'wilaya': wilaya,
        'commune': commune,
        'addressText': addressText,
        'latitude': latitude,
        'longitude': longitude,
      };

  factory CustomerProfileInfo.fromJson(Map<String, dynamic> j) =>
      CustomerProfileInfo(
        id: j['id'] as String?,
        userId: j['userId'] as String?,
        name: (j['name'] as String?) ?? '',
        phone: (j['phone'] as String?) ?? '',
        priceTier:
            PriceTier.fromString((j['priceTier'] as String?) ?? 'retail'),
        wilaya: (j['wilaya'] as String?) ?? '',
        commune: (j['commune'] as String?) ?? '',
        addressText: (j['addressText'] as String?) ?? '',
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
        isSynced: j['id'] != null,
      );

  CustomerProfileInfo copyWith({
    String? id,
    String? userId,
    String? name,
    String? phone,
    PriceTier? priceTier,
    String? wilaya,
    String? commune,
    String? addressText,
    double? latitude,
    double? longitude,
    bool? isSynced,
  }) {
    return CustomerProfileInfo(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      priceTier: priceTier ?? this.priceTier,
      wilaya: wilaya ?? this.wilaya,
      commune: commune ?? this.commune,
      addressText: addressText ?? this.addressText,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      isSynced: isSynced ?? this.isSynced,
    );
  }
}

class CustomerProfileNotifier extends StateNotifier<CustomerProfileInfo> {
  final Ref ref;
  static const _prefsKey = 'customer_profile_v1';

  CustomerProfileNotifier(this.ref)
      : super(_load(ref.read(sharedPreferencesProvider))) {
    if (ref.read(sharedPreferencesProvider) == null) {
      _initAsync();
    }
  }

  Future<void> _initAsync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final loaded = _load(prefs);
      if (!mounted) return;
      // Never overwrite edits the customer may already have made while prefs
      // were loading (important when the app is embedded without an override).
      final hasLocalEdits = state.id != null ||
          state.name.isNotEmpty ||
          state.phone.isNotEmpty ||
          state.wilaya.isNotEmpty ||
          state.commune.isNotEmpty ||
          state.addressText.isNotEmpty;
      if (hasLocalEdits) return;
      if (loaded.isComplete ||
          loaded.phone.isNotEmpty ||
          loaded.name.isNotEmpty) {
        state = loaded;
      }
    } catch (_) {}
  }

  static CustomerProfileInfo _load(SharedPreferences? prefs) {
    if (prefs == null) return const CustomerProfileInfo();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return const CustomerProfileInfo();
    try {
      return CustomerProfileInfo.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return const CustomerProfileInfo();
    }
  }

  /// Single place that updates state AND saves it on the device.
  void _set(CustomerProfileInfo next) {
    if (!mounted) return;
    state = next;
    final prefs = ref.read(sharedPreferencesProvider);
    if (prefs != null) {
      unawaited(prefs.setString(_prefsKey, jsonEncode(next.toJson())));
    } else {
      unawaited(() async {
        try {
          final p = await SharedPreferences.getInstance();
          await p.setString(_prefsKey, jsonEncode(next.toJson()));
        } catch (_) {}
      }());
    }
  }

  CustomerProfileInfo _fromEntity(CustomerProfileEntity e) => state.copyWith(
        id: e.id,
        userId: e.userId,
        name: e.name,
        phone: e.phone,
        priceTier: e.priceTier,
        wilaya: e.wilaya ?? state.wilaya,
        commune: e.commune ?? state.commune,
        addressText: e.addressText ?? state.addressText,
        latitude: e.latitude ?? state.latitude,
        longitude: e.longitude ?? state.longitude,
        isSynced: true,
      );

  Future<CustomerProfileEntity> syncWithDatabase() async {
    final repo = ref.read(customerRepositoryProvider);
    final deviceToken =
        await CustomerDeviceAuthService.instance.getOrCreateDeviceToken();

    final entity = await repo.syncCustomerProfile(
      name: state.name,
      phone: state.phone,
      wilaya: state.wilaya,
      commune: state.commune,
      addressText: state.addressText,
      latitude: state.latitude,
      longitude: state.longitude,
      existingCustomerId: state.id,
      existingUserId: state.userId,
      deviceToken: deviceToken,
    );
    _set(_fromEntity(entity));
    return entity;
  }

  /// Replaces local profile state with the server's JWT-bound profile after
  /// password login. This is authoritative: it prevents a previous device owner's
  /// cached name/phone/address from being shown to the next signed-in customer.
  void applyServerProfile(CustomerProfileEntity e) {
    _set(CustomerProfileInfo(
      id: e.id,
      userId: e.userId,
      name: e.name,
      phone: e.phone,
      priceTier: e.priceTier,
      wilaya: e.wilaya ?? '',
      commune: e.commune ?? '',
      addressText: e.addressText ?? '',
      latitude: e.latitude,
      longitude: e.longitude,
      isSynced: true,
    ));
  }

  void clear() {
    _set(const CustomerProfileInfo());
  }

  void updateProfile({
    String? name,
    String? phone,
    String? wilaya,
    String? commune,
    String? addressText,
    double? latitude,
    double? longitude,
  }) {
    _set(state.copyWith(
      name: name,
      phone: phone,
      wilaya: wilaya,
      commune: commune,
      addressText: addressText,
      latitude: latitude,
      longitude: longitude,
      isSynced: false,
    ));
  }
}

final customerProfileProvider =
    StateNotifierProvider<CustomerProfileNotifier, CustomerProfileInfo>((ref) {
  return CustomerProfileNotifier(ref);
});

// ─────────────────────────────────────────────────────────────────────────────
// Cart
// ─────────────────────────────────────────────────────────────────────────────

class CustomerCartItem {
  final ProductEntity product;
  final int quantity;
  final PriceTier tier;

  const CustomerCartItem({
    required this.product,
    required this.quantity,
    this.tier = PriceTier.wholesale,
  });

  int get unitPrice => product.getPriceForQuantity(tier, quantity);
  int get lineTotal => quantity * unitPrice;
  bool get isAvailable => product.availableQty > 0;
  bool get exceedsStock =>
      product.availableQty > 0 && quantity > product.availableQty;

  CustomerCartItem copyWith({
    ProductEntity? product,
    int? quantity,
    PriceTier? tier,
  }) {
    return CustomerCartItem(
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
      tier: tier ?? this.tier,
    );
  }
}

Map<String, dynamic> _cartItemToJson(CustomerCartItem item) => {
      'product': productToJson(item.product),
      'quantity': item.quantity,
      'tier': item.tier.name,
    };

CustomerCartItem? _cartItemFromJson(Map<String, dynamic> j) {
  try {
    final product = productFromJson(
      (j['product'] as Map).cast<String, dynamic>(),
    );
    return CustomerCartItem(
      product: product,
      quantity: (j['quantity'] as num?)?.toInt() ?? 1,
      tier: PriceTier.fromString(j['tier'] as String? ?? 'wholesale'),
    );
  } catch (_) {
    return null;
  }
}

class CustomerCartNotifier extends StateNotifier<List<CustomerCartItem>> {
  CustomerCartNotifier(this.ref) : super(_load(ref)) {
    // A persisted cart may carry the tier captured on a previous run. The
    // profile can already be loaded when this provider is created, so the
    // profile listener below would never fire — refresh the tier immediately
    // so prices match the customer's current tier.
    if (state.isNotEmpty) {
      final restored = List<CustomerCartItem>.from(state);
      _recalculateTiersInPlace(restored);
      state = restored;
    }
    if (state.isEmpty) _loadAsync();
  }

  final Ref ref;
  bool _restoring = false;

  CustomerLocalStore get _store => ref.read(customerLocalStoreProvider);

  static List<CustomerCartItem> _load(Ref ref) {
    final raw = ref.read(customerLocalStoreProvider).readCartJsonSync();
    return _decodeCart(raw);
  }

  Future<void> _loadAsync() async {
    if (_restoring) return;
    _restoring = true;
    try {
      final raw = await _store.readCartJson();
      if (!mounted) return;
      if (raw == null) return;
      final restored = _decodeCart(raw);
      if (restored.isNotEmpty && state.isEmpty) {
        _recalculateTiersInPlace(restored);
        state = restored;
      }
    } finally {
      _restoring = false;
    }
  }

  static List<CustomerCartItem> _decodeCart(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => _cartItemFromJson((e as Map).cast<String, dynamic>()))
          .whereType<CustomerCartItem>()
          .where((e) => e.quantity > 0)
          .toList();
    } catch (_) {
      return [];
    }
  }

  PriceTier get _effectiveTier {
    final profile = ref.read(customerProfileProvider);
    // Existing accounts keep their negotiated tier even while offline edits
    // are waiting to sync; only brand-new local profiles fall back to retail.
    return profile.hasAccount ? profile.priceTier : PriceTier.retail;
  }

  void _recalculateTiersInPlace(List<CustomerCartItem> items) {
    final tier = _effectiveTier;
    for (var i = 0; i < items.length; i++) {
      items[i] = items[i].copyWith(tier: tier);
    }
  }

  void _persist() {
    if (state.isEmpty) {
      unawaited(_store.clearCart());
      return;
    }
    final encoded = jsonEncode(state.map(_cartItemToJson).toList());
    unawaited(_store.writeCartJson(encoded));
  }

  void _commit(List<CustomerCartItem> next) {
    if (!mounted) return;
    state = next;
    _persist();
  }

  void addProduct(ProductEntity product, {int quantity = 1}) {
    if (product.availableQty <= 0) return;
    final tier = _effectiveTier;
    final idx = state.indexWhere((it) => it.product.id == product.id);
    if (idx != -1) {
      final existing = state[idx];
      final nextQty = math.min(
        existing.quantity + quantity,
        product.availableQty > 0
            ? product.availableQty
            : existing.quantity + quantity,
      );
      final updated = List<CustomerCartItem>.from(state);
      updated[idx] = existing.copyWith(
        quantity: nextQty,
        tier: tier,
        product: product,
      );
      _commit(updated);
    } else {
      _commit([
        ...state,
        CustomerCartItem(
          product: product,
          quantity: product.availableQty > 0
              ? math.min(quantity, product.availableQty)
              : quantity,
          tier: tier,
        ),
      ]);
    }
  }

  void recalculateTiers() {
    if (state.isEmpty) return;
    final next = List<CustomerCartItem>.from(state);
    _recalculateTiersInPlace(next);
    _commit(next);
  }

  void updateQuantity(String productId, int quantity) {
    if (quantity <= 0) {
      removeProduct(productId);
      return;
    }
    final next = state.map((it) {
      if (it.product.id != productId) return it;
      final max = it.product.availableQty;
      return it.copyWith(
        quantity: max > 0 ? math.min(quantity, max) : quantity,
      );
    }).toList();
    _commit(next);
  }

  void removeProduct(String productId) {
    _commit(state.where((it) => it.product.id != productId).toList());
  }

  void clear() {
    _commit([]);
  }

  int get totalCentimes => state.fold(0, (sum, item) => sum + item.lineTotal);

  int get totalQuantity => state.fold(0, (sum, item) => sum + item.quantity);

  /// Updates cart lines with fresh catalogue data (price, stock, photo).
  void reconcileCatalog(List<ProductEntity> products) {
    if (state.isEmpty) return;
    final byId = {for (final p in products) p.id: p};
    final tier = _effectiveTier;
    var changed = false;
    final next = state.map((item) {
      final fresh = byId[item.product.id];
      if (fresh == null) return item;
      final capped = fresh.availableQty > 0
          ? math.min(item.quantity, fresh.availableQty)
          : item.quantity;
      if (fresh == item.product &&
          capped == item.quantity &&
          tier == item.tier) {
        return item;
      }
      changed = true;
      return item.copyWith(
        product: fresh,
        quantity: capped,
        tier: tier,
      );
    }).toList();
    if (changed) _commit(next);
  }

  /// Adds every still-available line from a past order to the cart.
  ({int added, int skipped}) reorder(
    OrderEntity order,
    List<ProductEntity> catalog,
  ) {
    final byId = {for (final p in catalog) p.id: p};
    final tier = _effectiveTier;
    final next = List<CustomerCartItem>.from(state);
    var added = 0;
    var skipped = 0;

    for (final item in order.items) {
      final product = byId[item.productId];
      if (product == null || product.availableQty <= 0) {
        skipped++;
        continue;
      }
      final idx = next.indexWhere((it) => it.product.id == product.id);
      if (idx >= 0) {
        final existing = next[idx];
        next[idx] = existing.copyWith(
          product: product,
          quantity: math.min(
            existing.quantity + item.quantity,
            product.availableQty,
          ),
          tier: tier,
        );
      } else {
        next.add(CustomerCartItem(
          product: product,
          quantity: math.min(item.quantity, product.availableQty),
          tier: tier,
        ));
      }
      added++;
    }

    if (added > 0) _commit(next);
    return (added: added, skipped: skipped);
  }

  Future<void> syncPendingOrders() async {
    await ref.read(customerSyncCoordinatorProvider).syncPendingOrders();
  }

  Future<CheckoutOutcome> checkout({
    required CustomerProfileInfo profile,
  }) async {
    if (ref.read(customerCheckoutInProgressProvider)) {
      throw Exception('جاري إرسال الطلبية، يرجى الانتظار.');
    }
    ref.read(customerCheckoutInProgressProvider.notifier).state = true;

    try {
      String? customerId = profile.id;

      // First-time setup needs one online round-trip; an existing account can
      // keep ordering offline because the id is already known.
      if (customerId == null || customerId.isEmpty) {
        try {
          final synced =
              await ref.read(customerProfileProvider.notifier).syncWithDatabase();
          customerId = synced.id;
        } catch (_) {
          throw Exception(
            'أكمل بيانات التوصيل مرة واحدة عبر الإنترنت قبل أول طلبية.',
          );
        }
      }

      return await submitOrder(
        customerId: customerId,
        address: profile.toMap(),
      );
    } finally {
      if (mounted) {
        ref.read(customerCheckoutInProgressProvider.notifier).state = false;
      }
    }
  }

  Future<CheckoutOutcome> submitOrder({
    required String customerId,
    required Map<String, dynamic> address,
  }) async {
    if (state.isEmpty) {
      throw Exception('السلة فارغة.');
    }

    final pending = PendingOrder(
      clientId: const Uuid().v4(),
      customerId: customerId.isEmpty ? null : customerId,
      deliveryAddress: Map<String, dynamic>.from(address),
      items: state
          .map(
            (it) => PendingOrderItem(
              productId: it.product.id,
              name: it.product.nameAr.isNotEmpty
                  ? it.product.nameAr
                  : it.product.nameFr,
              unit: it.product.unit,
              quantity: it.quantity,
              unitPriceCentimes: it.unitPrice,
              unitCostCentimes: it.product.lastUnitCostCentimes,
            ),
          )
          .toList(),
      totalAmountCentimes: totalCentimes,
      createdAt: DateTime.now(),
    );

    final orderRepo = ref.read(customerOrderRepositoryProvider);
    final online = ConnectivityService.instance.isOnline;

    if (online) {
      try {
        final deviceToken =
            await CustomerDeviceAuthService.instance.getOrCreateDeviceToken();
        final orderId = await orderRepo.submitCustomerOrder(
          customerId: customerId,
          address: address,
          items: pending.items
              .map((i) => {
                    'product_id': i.productId,
                    'quantity': i.quantity,
                  })
              .toList(),
          clientId: pending.clientId,
          deviceToken: deviceToken,
        );
        await _store.removePendingOrder(pending.clientId);
        clear();
        unawaited(
            ref.read(customerOrdersProvider.notifier).refresh(silent: true));
        unawaited(
          ref.read(customerCatalogProvider.notifier).refresh(silent: true),
        );
        return CheckoutOutcome(orderId: orderId, queued: false);
      } catch (e) {
        debugPrint('[Checkout] online submit failed, queueing: $e');
      }
    }

    await _store.upsertPendingOrder(pending);
    clear();
    unawaited(ref.read(customerOrdersProvider.notifier).refresh(silent: true));
    return CheckoutOutcome(orderId: pending.clientId, queued: true);
  }
}

final customerCartProvider =
    StateNotifierProvider<CustomerCartNotifier, List<CustomerCartItem>>((ref) {
  final notifier = CustomerCartNotifier(ref);
  ref.listen<CustomerProfileInfo>(customerProfileProvider, (prev, next) {
    if (prev?.isSynced != next.isSynced || prev?.priceTier != next.priceTier) {
      notifier.recalculateTiers();
    }
  });
  return notifier;
});

/// Shared checkout guard. The cart itself is app state, so an in-flight
/// checkout must be visible to every cart screen: otherwise a second screen
/// could submit the same cart again while the first request is still pending.
final customerCheckoutInProgressProvider = StateProvider<bool>((ref) => false);

// ─────────────────────────────────────────────────────────────────────────────
// Catalogue
// ─────────────────────────────────────────────────────────────────────────────

class CustomerCatalogNotifier extends AsyncNotifier<CatalogSnapshot> {
  late final CustomerLocalStore _store;
  bool _disposed = false;
  bool _booting = false;
  bool _refreshing = false;

  @override
  Future<CatalogSnapshot> build() async {
    _store = ref.read(customerLocalStoreProvider);
    ref.onDispose(() => _disposed = true);
    _booting = true;
    try {
      final cached = await _store.readCatalog();
      if (cached != null && cached.products.isNotEmpty) {
        Future<void>.delayed(
          const Duration(milliseconds: 300),
          () => refresh(silent: true),
        );
        return cached;
      }
      return await _load(force: true);
    } finally {
      _booting = false;
    }
  }

  Future<CatalogSnapshot> _load({required bool force}) async {
    final repo = ref.read(customerProductRepositoryProvider);
    final online = ConnectivityService.instance.isOnline;
    String? refreshError;

    if (force && online) {
      try {
        await repo.refreshProducts();
      } catch (e) {
        refreshError = _prettyError(e);
      }
    }

    var products = const <ProductEntity>[];
    try {
      products = await repo.getProducts(onlyActive: true);
    } catch (e) {
      refreshError ??= _prettyError(e);
    }

    final cached = await _store.readCatalog();
    if (products.isEmpty && cached != null) {
      products = cached.products;
    }

    if (products.isEmpty) {
      if (!online) {
        throw Exception('لا يوجد اتصال ولا نسخة محفوظة من المنتجات بعد.');
      }
      throw Exception('تعذر تحميل المنتجات. حاول مرة أخرى.');
    }

    final syncedAt = await repo.getLastProductsSyncAt() ?? cached?.syncedAt;

    final snapshot = CatalogSnapshot(
      products: products,
      syncedAt: syncedAt,
      isOffline: !online,
      lastError: refreshError,
      affinity: await _store.readAffinity(),
    );

    await _store.writeCatalog(snapshot);
    _reconcileCart(products);
    return snapshot;
  }

  Future<void> refresh({bool silent = false}) async {
    if (_disposed || _booting || _refreshing) return;
    _refreshing = true;
    try {
      final snapshot = await _load(force: true);
      if (!_disposed) state = AsyncData(snapshot);
    } catch (e, st) {
      if (_disposed) return;
      if (state.hasValue) {
        state = AsyncData(
          state.requireValue.copyWith(
            isOffline: true,
            lastError: _prettyError(e),
          ),
        );
      } else if (!silent) {
        state = AsyncError(e, st);
      }
    } finally {
      _refreshing = false;
    }
  }

  void _reconcileCart(List<ProductEntity> products) {
    try {
      ref.read(customerCartProvider.notifier).reconcileCatalog(products);
    } catch (e) {
      debugPrint('[Catalog] cart reconciliation skipped: $e');
    }
  }

  ProductEntity? productById(String id) {
    final snapshot = state.valueOrNull;
    if (snapshot == null) return null;
    for (final product in snapshot.products) {
      if (product.id == id) return product;
    }
    return null;
  }
}

final customerCatalogProvider =
    AsyncNotifierProvider<CustomerCatalogNotifier, CatalogSnapshot>(
  CustomerCatalogNotifier.new,
);

// ─────────────────────────────────────────────────────────────────────────────
// Orders
// ─────────────────────────────────────────────────────────────────────────────

class CustomerOrdersNotifier extends AsyncNotifier<OrdersSnapshot> {
  late final CustomerLocalStore _store;
  bool _disposed = false;
  bool _booting = false;
  bool _refreshing = false;

  @override
  Future<OrdersSnapshot> build() async {
    _store = ref.read(customerLocalStoreProvider);
    ref.onDispose(() => _disposed = true);
    final customerId = ref.watch(customerProfileProvider.select((p) => p.id));
    _booting = true;
    try {
      final cached = await _store.readOrders();
      if (cached != null && cached.customerId == customerId) {
        Future<void>.delayed(
          const Duration(milliseconds: 300),
          () => refresh(silent: true),
        );
        return cached;
      }
      return await _load(customerId);
    } finally {
      _booting = false;
    }
  }

  Future<OrdersSnapshot> _load(String? customerId) async {
    final profile = ref.read(customerProfileProvider);
    final store = _store;
    final online = ConnectivityService.instance.isOnline;
    String? error;

    if (online) {
      try {
        await ref.read(customerSyncCoordinatorProvider).syncPendingOrders();
      } catch (e) {
        debugPrint('[Orders] pending sync failed: $e');
      }
    }

    List<PendingOrder> pending = const [];
    try {
      pending = await store.readPendingOrders();
    } catch (e) {
      debugPrint('[Orders] pending read failed: $e');
    }

    var remote = const <OrderEntity>[];
    if (customerId != null && customerId.isNotEmpty && online) {
      try {
        remote = await ref.read(customerOrderRepositoryProvider).getOrders(
              customerId: customerId,
              limit: 120,
            );
        unawaited(store.recordOrderAffinity(remote));
      } catch (e) {
        error = _prettyError(e);
      }
    }

    final cached = await store.readOrders();
    if (remote.isEmpty &&
        error != null &&
        cached != null &&
        cached.customerId == customerId) {
      remote = cached.orders;
    }

    final merged = _mergeOrders(remote, pending, profile);

    final snapshot = OrdersSnapshot(
      customerId: customerId,
      orders: merged,
      pendingCount: pending.length,
      fetchedAt: DateTime.now(),
      isOffline: !online,
      lastError: error,
    );

    await store.writeOrders(
      OrdersSnapshot(
        customerId: customerId,
        orders: remote,
        fetchedAt: snapshot.fetchedAt,
      ),
    );

    return snapshot;
  }

  List<OrderEntity> _mergeOrders(
    List<OrderEntity> remote,
    List<PendingOrder> pending,
    CustomerProfileInfo profile,
  ) {
    final pendingClientIds =
        pending.map((p) => p.clientId).where((id) => id.isNotEmpty).toSet();
    final filteredRemote = remote
        .where(
            (o) => o.clientId == null || !pendingClientIds.contains(o.clientId))
        .toList();

    final pendingEntities = pending
        .map((p) => p.toOrderEntity(
              customerName: profile.name,
              customerPhone: profile.phone,
            ))
        .toList();

    return <OrderEntity>[...pendingEntities, ...filteredRemote]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> refresh({bool silent = false}) async {
    if (_disposed || _booting || _refreshing) return;
    _refreshing = true;
    try {
      final customerId = ref.read(customerProfileProvider).id;
      final snapshot = await _load(customerId);
      if (!_disposed) state = AsyncData(snapshot);
    } catch (e, st) {
      if (_disposed) return;
      if (state.hasValue) {
        state = AsyncData(
          state.requireValue.copyWith(
            isOffline: true,
            lastError: _prettyError(e),
          ),
        );
      } else if (!silent) {
        state = AsyncError(e, st);
      }
    } finally {
      _refreshing = false;
    }
  }
}

final customerOrdersProvider =
    AsyncNotifierProvider<CustomerOrdersNotifier, OrdersSnapshot>(
  CustomerOrdersNotifier.new,
);

// ─────────────────────────────────────────────────────────────────────────────
// Wallet
// ─────────────────────────────────────────────────────────────────────────────

class CustomerWalletNotifier extends AsyncNotifier<WalletSnapshot> {
  late final CustomerLocalStore _store;
  bool _disposed = false;
  bool _booting = false;
  bool _refreshing = false;

  @override
  Future<WalletSnapshot> build() async {
    _store = ref.read(customerLocalStoreProvider);
    ref.onDispose(() => _disposed = true);
    final customerId = ref.watch(customerProfileProvider.select((p) => p.id));
    _booting = true;
    try {
      final cached = await _store.readWallet();
      if (cached != null && cached.customerId == customerId) {
        Future<void>.delayed(
          const Duration(milliseconds: 350),
          () => refresh(silent: true),
        );
        return cached;
      }
      return await _load(customerId);
    } finally {
      _booting = false;
    }
  }

  Future<WalletSnapshot> _load(String? customerId) async {
    final store = _store;
    final profile = ref.read(customerProfileProvider);
    final cachedRaw = await store.readWallet();
    final cached = cachedRaw != null && cachedRaw.customerId == customerId
        ? cachedRaw
        : null;
    final online = ConnectivityService.instance.isOnline;

    var name = cached?.customerName ?? '';
    if (name.isEmpty) name = profile.name;

    var limit = cached?.creditLimitCentimes ?? 0;
    var debt = cached?.currentDebtCentimes ?? 0;
    var ledger = cached?.ledger ?? const <CustomerLedgerEntryEntity>[];
    var unpaid = cached?.unpaidOrders ?? const <CustomerUnpaidOrderEntity>[];
    String? error;

    if (customerId != null && customerId.isNotEmpty && online) {
      final repo = ref.read(customerRepositoryProvider);
      try {
        final entity = await repo.getCustomerById(customerId);
        if (entity != null) {
          name = entity.name;
          limit = entity.creditLimitCentimes;
          debt = entity.currentDebtCentimes;
        }
      } catch (e) {
        error = _prettyError(e);
      }
      try {
        final freshLedger = await repo.getCustomerLedger(customerId);
        if (freshLedger.isNotEmpty || ledger.isEmpty) ledger = freshLedger;
      } catch (e) {
        error ??= _prettyError(e);
      }
      try {
        final freshUnpaid = await repo.getCustomerUnpaidOrders(customerId);
        if (freshUnpaid.isNotEmpty || unpaid.isEmpty) unpaid = freshUnpaid;
      } catch (e) {
        error ??= _prettyError(e);
      }
    }

    final snapshot = WalletSnapshot(
      customerId: customerId,
      customerName: name,
      creditLimitCentimes: limit,
      currentDebtCentimes: debt,
      ledger: ledger,
      unpaidOrders: unpaid,
      fetchedAt: DateTime.now(),
      isOffline: !online,
      lastError: error,
    );

    if (customerId != null && customerId.isNotEmpty) {
      await store.writeWallet(snapshot);
    }
    return snapshot;
  }

  Future<void> refresh({bool silent = false}) async {
    if (_disposed || _booting || _refreshing) return;
    _refreshing = true;
    try {
      final customerId = ref.read(customerProfileProvider).id;
      final snapshot = await _load(customerId);
      if (!_disposed) state = AsyncData(snapshot);
    } catch (e, st) {
      if (_disposed) return;
      if (state.hasValue) {
        state = AsyncData(
          state.requireValue.copyWith(
            isOffline: true,
            lastError: _prettyError(e),
          ),
        );
      } else if (!silent) {
        state = AsyncError(e, st);
      }
    } finally {
      _refreshing = false;
    }
  }
}

final customerWalletProvider =
    AsyncNotifierProvider<CustomerWalletNotifier, WalletSnapshot>(
  CustomerWalletNotifier.new,
);

// ─────────────────────────────────────────────────────────────────────────────
// Sync coordinator
// ─────────────────────────────────────────────────────────────────────────────

class CustomerSyncCoordinator {
  CustomerSyncCoordinator(this.ref);

  final Ref ref;
  bool _syncing = false;

  /// Replays locally queued checkouts. Idempotent thanks to `client_id`.
  Future<bool> syncPendingOrders() async {
    if (_syncing) return false;
    if (!ConnectivityService.instance.isOnline) return false;

    _syncing = true;
    try {
      final store = ref.read(customerLocalStoreProvider);
      final pending = await store.readPendingOrders();
      if (pending.isEmpty) return false;

      final repo = ref.read(customerOrderRepositoryProvider);
      final profile = ref.read(customerProfileProvider);
      String? token;
      try {
        token =
            await CustomerDeviceAuthService.instance.getOrCreateDeviceToken();
      } catch (_) {}

      var changed = false;
      for (final order in pending) {
        final customerId = order.customerId ?? profile.id;
        if (customerId == null || customerId.isEmpty) {
          // Wait until the profile is bound to a server account; submitting
          // anonymously would hide the order from the customer's history.
          continue;
        }
        try {
          await repo.submitCustomerOrder(
            customerId: customerId,
            address: order.deliveryAddress,
            items: order.items
                .map((i) => {
                      'product_id': i.productId,
                      'quantity': i.quantity,
                    })
                .toList(),
            clientId: order.clientId,
            deviceToken: token,
          );
          await store.removePendingOrder(order.clientId);
          changed = true;
        } catch (e) {
          await store.markPendingError(order.clientId, _prettyError(e));
        }
      }
      return changed;
    } finally {
      _syncing = false;
    }
  }

  /// Syncs a profile edited while offline once connectivity returns.
  Future<void> syncProfileIfNeeded() async {
    final profile = ref.read(customerProfileProvider);
    if (!profile.isComplete || profile.isSynced) return;
    if (!ConnectivityService.instance.isOnline) return;
    try {
      await ref.read(customerProfileProvider.notifier).syncWithDatabase();
    } catch (e) {
      debugPrint('[Sync] profile sync failed: $e');
    }
  }

  Future<void> refreshAll() async {
    await syncProfileIfNeeded();
    await syncPendingOrders();
    await Future.wait([
      ref.read(customerCatalogProvider.notifier).refresh(silent: true),
      ref.read(customerOrdersProvider.notifier).refresh(silent: true),
      ref.read(customerWalletProvider.notifier).refresh(silent: true),
    ]);
  }
}

final customerSyncCoordinatorProvider =
    Provider<CustomerSyncCoordinator>((ref) {
  return CustomerSyncCoordinator(ref);
});

// ─────────────────────────────────────────────────────────────────────────────
// Live order tracking (RPC only; the device token is validated server-side)
// ─────────────────────────────────────────────────────────────────────────────

bool _isTerminalStatus(OrderStatus status) =>
    status == OrderStatus.delivered ||
    status == OrderStatus.settled ||
    status == OrderStatus.cancelled ||
    status == OrderStatus.refused;

final customerLiveOrderProvider =
    StreamProvider.autoDispose.family<LiveOrderUpdate, String>((ref, orderId) {
  final client = ref.watch(customerSupabaseClientProvider);

  return (() async* {
    while (true) {
      if (!ConnectivityService.instance.isOnline) {
        yield LiveOrderUpdate(orderId: orderId, isOffline: true);
        await Future<void>.delayed(const Duration(seconds: 8));
        continue;
      }

      String token;
      try {
        token = await CustomerDeviceAuthService.instance.getOrCreateDeviceToken();
      } catch (e) {
        yield LiveOrderUpdate(
          orderId: orderId,
          error: 'تعذر التحقق من أمان الجهاز.',
        );
        await Future<void>.delayed(const Duration(seconds: 12));
        continue;
      }

      if (token.isEmpty) {
        yield LiveOrderUpdate(
          orderId: orderId,
          error: 'تعذر التحقق من أمان الجهاز.',
        );
        await Future<void>.delayed(const Duration(seconds: 12));
        continue;
      }

      try {
        final res = await client.rpc(
          'rpc_get_customer_order_live',
          params: {
            'p_order_id': orderId,
            'p_device_token': token,
          },
        );
        final update = _liveFromRpc(orderId, res);
        yield update;
        if (update.found &&
            update.status != null &&
            _isTerminalStatus(update.status!)) {
          return;
        }
      } catch (e) {
        debugPrint('[Tracking] live RPC unavailable: $e');
        yield LiveOrderUpdate(orderId: orderId, error: _prettyError(e));
      }

      await Future<void>.delayed(const Duration(seconds: 12));
    }
  })();
});

LiveOrderUpdate _liveFromRpc(String orderId, dynamic response) {
  if (response is! Map) {
    return LiveOrderUpdate(orderId: orderId, error: 'استجابة غير صالحة');
  }
  final map = response.cast<String, dynamic>();
  if (map['found'] != true) {
    return LiveOrderUpdate(
      orderId: orderId,
      error: map['error'] as String? ?? 'الطلب غير متوفر',
    );
  }
  return LiveOrderUpdate(
    orderId: orderId,
    found: true,
    status: OrderStatus.fromString(map['status'] as String? ?? 'submitted'),
    orderNumber: (map['order_number'] as num?)?.toInt(),
    driverId: map['driver_id'] as String?,
    driverName: map['driver_name'] as String?,
    driverPhone: map['driver_phone'] as String?,
    driverLat: _asDouble(map['driver_lat']),
    driverLng: _asDouble(map['driver_lng']),
    driverUpdatedAt: _parseDate(map['driver_updated_at']),
    destinationLat: _asDouble(map['destination_lat']),
    destinationLng: _asDouble(map['destination_lng']),
    confirmedAt: _parseDate(map['confirmed_at']),
    deliveredAt: _parseDate(map['delivered_at']),
    settledAt: _parseDate(map['settled_at']),
  );
}

double? _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

DateTime? _parseDate(dynamic value) =>
    value is String && value.isNotEmpty ? DateTime.tryParse(value) : null;

String _prettyError(Object error) =>
    error.toString().replaceFirst('Exception: ', '').trim();
