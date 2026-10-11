import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

final customerSupabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final customerProductRepositoryProvider = Provider<IProductRepository>((ref) {
  final client = ref.watch(customerSupabaseClientProvider);
  final service = SupabaseService(client);
  return ProductRepositoryImpl(client: client, service: service);
});

final customerOrderRepositoryProvider = Provider<IOrderRepository>((ref) {
  final client = ref.watch(customerSupabaseClientProvider);
  final service = SupabaseService(client);
  return OrderRepositoryImpl(client: client, service: service);
});

final customerRepositoryProvider = Provider<ICustomerRepository>((ref) {
  final client = ref.watch(customerSupabaseClientProvider);
  final service = SupabaseService(client);
  return CustomerRepositoryImpl(client: client, service: service);
});

final customerLiveProductsProvider = FutureProvider<List<ProductEntity>>((ref) async {
  final repo = ref.watch(customerProductRepositoryProvider);
  return repo.getProducts(onlyActive: true);
});

// customer_providers.dart
// 1) ADD these imports at the top:

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
    final itemsPayload = state.map((it) {
      return {
        'product_id': it.product.id,
        'quantity': it.quantity,
        'unit_price': it.unitPrice,
        'unit_cost': it.product.lastUnitCostCentimes,
      };
    }).toList();

    final orderId = await orderRepo.submitCustomerOrder(
      customerId: customerId,
      address: address,
      items: itemsPayload,
    );

    clear();
    ref.invalidate(customerLiveProductsProvider);
    ref.invalidate(customerOrdersProvider);
    return orderId;
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
  if (profile.id == null || profile.id!.isEmpty) {
    return [];
  }
  final repo = ref.watch(customerOrderRepositoryProvider);
  return repo.getOrders(customerId: profile.id);
});
