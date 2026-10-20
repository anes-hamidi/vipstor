import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/app_update_service.dart';



final customerSupabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final customerSupabaseServiceProvider = Provider<SupabaseService>((ref) {
  final client = ref.watch(customerSupabaseClientProvider);
  return SupabaseService(client);
});

final customerAppUpdateRepositoryProvider = Provider<IAppUpdateRepository>((ref) {
  final client = ref.watch(customerSupabaseClientProvider);
  final service = ref.watch(customerSupabaseServiceProvider);
  return AppUpdateRepositoryImpl(client: client, service: service);
});

final customerAppUpdateServiceProvider = Provider<AppUpdateService>((ref) {
  final repo = ref.watch(customerAppUpdateRepositoryProvider);
  return AppUpdateService(repository: repo, appType: 'customer_app');
});

final _customerDbProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

final customerProductRepositoryProvider = Provider<IProductRepository>((ref) {
  final client = ref.watch(customerSupabaseClientProvider);
  final service = SupabaseService(client);
  final db = ref.watch(_customerDbProvider);
  return ProductRepositoryImpl(client: client, service: service, db: db, isCustomerPortal: true);
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

const _kProductsCacheKey = 'customer_cached_products_v1';
const _kPendingOrdersKey = 'customer_pending_orders_v1';

Map<String, dynamic> _productToJson(ProductEntity p) => {
      'id': p.id,
      'nameAr': p.nameAr,
      'nameFr': p.nameFr,
      'category': p.category,
      'unit': p.unit,
      'packSize': p.packSize,
      'photoUrl': p.photoUrl,
      'lastUnitCostCentimes': p.lastUnitCostCentimes,
      'onHandQty': p.onHandQty,
      'availableQty': p.availableQty,
      'active': p.active,
      'barcodes': p.barcodes,
      'prices': p.prices
          .map((price) => {
                'id': price.id,
                'tier': price.tier.name,
                'minQty': price.minQty,
                'priceCentimes': price.priceCentimes,
              })
          .toList(),
    };

ProductEntity _productFromJson(Map<String, dynamic> j) => ProductEntity(
      id: j['id'] as String,
      nameAr: (j['nameAr'] as String?) ?? '',
      nameFr: (j['nameFr'] as String?) ?? '',
      category: (j['category'] as String?) ?? '',
      unit: (j['unit'] as String?) ?? 'piece',
      packSize: (j['packSize'] as num?)?.toInt() ?? 1,
      photoUrl: j['photoUrl'] as String?,
      lastUnitCostCentimes: (j['lastUnitCostCentimes'] as num?)?.toInt() ?? 0,
      onHandQty: (j['onHandQty'] as num?)?.toInt() ?? 0,
      availableQty: (j['availableQty'] as num?)?.toInt() ?? 0,
      active: (j['active'] as bool?) ?? true,
      barcodes: (j['barcodes'] as List? ?? []).cast<String>(),
      prices: (j['prices'] as List? ?? []).map((p) {
        final pm = p as Map<String, dynamic>;
        return ProductPriceTier(
          id: pm['id'] as String,
          tier: PriceTier.fromString(pm['tier'] as String),
          minQty: (pm['minQty'] as num).toInt(),
          priceCentimes: (pm['priceCentimes'] as num).toInt(),
        );
      }).toList(),
    );

final customerLiveProductsProvider = FutureProvider<List<ProductEntity>>((ref) async {
  final repo = ref.watch(customerProductRepositoryProvider);
  // Always resolve prefs — the override is set in main() before runApp so
  // this will have a value, but we guard defensively.
  final prefs = ref.watch(sharedPreferencesProvider) ?? await SharedPreferences.getInstance();

  try {
    final remote = await repo.getProducts(onlyActive: true);
    // Cache fresh data for offline fallback (Stale-While-Revalidate)
    try {
      final jsonList = remote.map(_productToJson).toList();
      await prefs.setString(_kProductsCacheKey, jsonEncode(jsonList));
    } catch (_) {
      // Cache write failure is non-fatal
    }
    return remote;
  } on Exception catch (e) {
    // Attempt local cache fallback on any network/server error
    final cached = prefs.getString(_kProductsCacheKey);
    if (cached != null && cached.isNotEmpty) {
      try {
        final decoded = jsonDecode(cached) as List;
        final products = decoded
            .map((item) => _productFromJson(item as Map<String, dynamic>))
            .toList();
        if (products.isNotEmpty) return products;
      } catch (_) {
        // Cache is corrupt — fall through to rethrow
      }
    }
    // Re-throw with a descriptive message so the UI error state is useful
    throw Exception('فشل تحميل المنتجات: ${e.toString().replaceFirst('Exception: ', '')}');
  }
});

// Provider with async loader or safe fallback instance
final sharedPreferencesProvider = Provider<SharedPreferences?>((ref) => null);

// 3) REPLACE CustomerProfileInfo with:
class CustomerProfileInfo {
  final String? id;
  final String? userId;
  final String name;
  final String phone;
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
    this.wilaya = '',
    this.commune = '',
    this.addressText = '',
    this.latitude,
    this.longitude,
    this.isSynced = false,
  });

  static final _phoneRe = RegExp(r'^0[5-7]\d{8}$');
  static bool isValidPhone(String v) => _phoneRe.hasMatch(v.trim());

  /// True only when the customer has entered real, usable delivery info.
  bool get isComplete =>
      name.trim().isNotEmpty &&
      isValidPhone(phone) &&
      wilaya.trim().isNotEmpty &&
      commune.trim().isNotEmpty &&
      addressText.trim().isNotEmpty;

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
      wilaya: wilaya ?? this.wilaya,
      commune: commune ?? this.commune,
      addressText: addressText ?? this.addressText,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      isSynced: isSynced ?? this.isSynced,
    );
  }
}

// 4) REPLACE CustomerProfileNotifier with:
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
      if (loaded.isComplete || loaded.phone.isNotEmpty || loaded.name.isNotEmpty) {
        state = loaded;
      }
    } catch (_) {}
  }

  static CustomerProfileInfo _load(SharedPreferences? prefs) {
    if (prefs == null) return const CustomerProfileInfo();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return const CustomerProfileInfo();
    try {
      return CustomerProfileInfo.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const CustomerProfileInfo();
    }
  }

  /// Single place that updates state AND saves it on the device.
  void _set(CustomerProfileInfo next) async {
    state = next;
    final prefs = ref.read(sharedPreferencesProvider);
    if (prefs != null) {
      prefs.setString(_prefsKey, jsonEncode(next.toJson()));
    } else {
      try {
        final p = await SharedPreferences.getInstance();
        p.setString(_prefsKey, jsonEncode(next.toJson()));
      } catch (_) {}
    }
  }

  CustomerProfileInfo _fromEntity(CustomerProfileEntity e) => state.copyWith(
        id: e.id,
        userId: e.userId,
        name: e.name,
        phone: e.phone,
        wilaya: e.wilaya ?? state.wilaya,
        commune: e.commune ?? state.commune,
        addressText: e.addressText ?? state.addressText,
        latitude: e.latitude ?? state.latitude,
        longitude: e.longitude ?? state.longitude,
        isSynced: true,
      );

  Future<CustomerProfileEntity> syncWithDatabase() async {
    final repo = ref.read(customerRepositoryProvider);
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
    );
    _set(_fromEntity(entity));
    return entity;
  }

  Future<bool> lookupCustomerByPhone(String phone) async {
    final clean = phone.trim();
    if (clean.isEmpty) return false;

    final repo = ref.read(customerRepositoryProvider);
    final entity = await repo.getCustomerByPhone(clean);
    if (entity == null) return false;
    _set(_fromEntity(entity));
    return true;
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

// customerProfileProvider stays exactly as it is.
final customerProfileProvider = StateNotifierProvider<CustomerProfileNotifier, CustomerProfileInfo>((ref) {
  return CustomerProfileNotifier(ref);
});

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

class CustomerCartNotifier extends StateNotifier<List<CustomerCartItem>> {
  final Ref ref;

  CustomerCartNotifier(this.ref) : super([]);

  void addProduct(ProductEntity product, {int quantity = 1}) {
    final idx = state.indexWhere((it) => it.product.id == product.id);
    if (idx != -1) {
      final existing = state[idx];
      final updated = List<CustomerCartItem>.from(state);
      updated[idx] = existing.copyWith(quantity: existing.quantity + quantity);
      state = updated;
    } else {
      state = [...state, CustomerCartItem(product: product, quantity: quantity)];
    }
  }

  void updateQuantity(String productId, int quantity) {
    if (quantity <= 0) {
      removeProduct(productId);
      return;
    }
    state = state.map((it) {
      if (it.product.id == productId) {
        return it.copyWith(quantity: quantity);
      }
      return it;
    }).toList();
  }

  void removeProduct(String productId) {
    state = state.where((it) => it.product.id != productId).toList();
  }

  void clear() {
    state = [];
  }

  int get totalCentimes => state.fold(0, (sum, item) => sum + item.lineTotal);

  Future<String> submitOrder({
    required String customerId,
    required Map<String, dynamic> address,
  }) async {
    final orderRepo = ref.read(customerOrderRepositoryProvider);
    final prefs = ref.read(sharedPreferencesProvider) ?? await SharedPreferences.getInstance();

    final itemsPayload = state.map((it) {
      return {
        'product_id': it.product.id,
        'quantity': it.quantity,
      };
    }).toList();

    try {
      final orderId = await orderRepo.submitCustomerOrder(
        customerId: customerId,
        address: address,
        items: itemsPayload,
      );

      clear();
      ref.invalidate(customerLiveProductsProvider);
      ref.invalidate(customerOrdersProvider);
      return orderId;
    } catch (e) {
      // Offline fallback: save order to pending outbox with a client UUID
      final tempId = const Uuid().v4();
      final totalAmount = totalCentimes;

      final pendingOrder = {
        'id': tempId,
        'client_id': tempId,
        'order_number': null,
        'customer_id': customerId,
        'delivery_address': address,
        'total_amount': totalAmount,
        'paid_amount': 0,
        'status': 'submitted',
        'is_offline_pending': true,
        'created_at': DateTime.now().toIso8601String(),
        'items': itemsPayload,
      };

      final existingRaw = prefs.getString(_kPendingOrdersKey);
      List<dynamic> list = [];
      if (existingRaw != null && existingRaw.isNotEmpty) {
        try {
          list = jsonDecode(existingRaw) as List;
        } catch (_) {}
      }
      list.add(pendingOrder);
      await prefs.setString(_kPendingOrdersKey, jsonEncode(list));

      clear();
      ref.invalidate(customerOrdersProvider);
      return tempId;
    }
  }

  Future<void> syncPendingOrders() async {
    final prefs = ref.read(sharedPreferencesProvider) ?? await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPendingOrdersKey);
    if (raw == null || raw.isEmpty) return;

    try {
      final list = jsonDecode(raw) as List;
      if (list.isEmpty) return;

      final orderRepo = ref.read(customerOrderRepositoryProvider);
      final remaining = <dynamic>[];

      for (final item in list) {
        final orderMap = item as Map<String, dynamic>;
        try {
          final items = (orderMap['items'] as List).cast<Map<String, dynamic>>();
          await orderRepo.submitCustomerOrder(
            customerId: orderMap['customer_id'] as String,
            address: orderMap['delivery_address'] as Map<String, dynamic>,
            items: items,
            clientId: orderMap['client_id'] as String?,
          );
        } catch (_) {
          remaining.add(orderMap);
        }
      }

      await prefs.setString(_kPendingOrdersKey, jsonEncode(remaining));
      ref.invalidate(customerOrdersProvider);
    } catch (_) {}
  }

  Future<String> checkout({
    required CustomerProfileInfo profile,
  }) async {
    String effectiveCustomerId = profile.id ?? '';
    
    // Sync profile to ensure database record exists
    try {
      final synced = await ref.read(customerProfileProvider.notifier).syncWithDatabase();
      effectiveCustomerId = synced.id;
    } catch (_) {}

    return submitOrder(
      customerId: effectiveCustomerId,
      address: profile.toMap(),
    );
  }
}

final customerCartProvider = StateNotifierProvider<CustomerCartNotifier, List<CustomerCartItem>>((ref) {
  return CustomerCartNotifier(ref);
});

final customerOrdersProvider = FutureProvider<List<OrderEntity>>((ref) async {
  final profile = ref.watch(customerProfileProvider);
  final prefs = ref.watch(sharedPreferencesProvider) ?? await SharedPreferences.getInstance();

  // 1. Read locally queued pending orders
  final List<OrderEntity> pendingEntities = [];
  final rawPending = prefs.getString(_kPendingOrdersKey);
  if (rawPending != null && rawPending.isNotEmpty) {
    try {
      final list = jsonDecode(rawPending) as List;
      for (final p in list) {
        final pm = p as Map<String, dynamic>;
        final itemsList = (pm['items'] as List? ?? []).map((i) {
          final im = i as Map<String, dynamic>;
          return OrderItemEntity(
            id: im['product_id'] as String? ?? '',
            productId: im['product_id'] as String? ?? '',
            productName: (im['product_name'] as String?) ?? 'منتج',
            quantity: (im['quantity'] as num?)?.toInt() ?? 1,
            // unit_price may be absent in orders saved before this fix
            unitPriceCentimes: (im['unit_price'] as num?)?.toInt() ?? 0,
            unitCostCentimes: (im['unit_cost'] as num?)?.toInt() ?? 0,
          );
        }).toList();

        pendingEntities.add(OrderEntity(
          id: pm['id'] as String,
          orderNumber: null,
          channel: OrderChannel.online,
          customerId: pm['customer_id'] as String?,
          customerName: profile.name,
          customerPhone: profile.phone,
          status: OrderStatus.submitted,
          totalAmountCentimes: (pm['total_amount'] as num?)?.toInt() ?? 0,
          paidAmountCentimes: 0,
          deliveryAddress: pm['delivery_address'] as Map<String, dynamic>?,
          items: itemsList,
          createdAt: DateTime.tryParse(pm['created_at'] as String? ?? '') ?? DateTime.now(),
          notes: 'في انتظار المزامنة (محفوظ محلياً)',
        ));
      }
    } catch (_) {
      // Malformed pending store — ignore so remote orders still load
    }
  }

  // 2. Fetch remote orders from Supabase if customer has an id
  List<OrderEntity> remoteOrders = [];
  if (profile.id != null && profile.id!.isNotEmpty) {
    final repo = ref.watch(customerOrderRepositoryProvider);
    try {
      remoteOrders = await repo.getOrders(customerId: profile.id);
      // Background sync of any pending offline orders
      if (pendingEntities.isNotEmpty) {
        ref.read(customerCartProvider.notifier).syncPendingOrders();
      }
    } on Exception catch (e) {
      // If we have at least the pending local orders, return those with an
      // appended note. Otherwise propagate so the UI shows an error state.
      if (pendingEntities.isEmpty) {
        throw Exception('فشل جلب الطلبيات: ${e.toString().replaceFirst('Exception: ', '')}');
      }
      // Fall through: return pending-only list so the user isn't left blank
    }
  }

  // Merge: pending offline at the top, remote below
  return [...pendingEntities, ...remoteOrders];
});
