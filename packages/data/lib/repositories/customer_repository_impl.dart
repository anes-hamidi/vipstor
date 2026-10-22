import 'package:domain/domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../datasources/remote/supabase_service.dart';
import '../datasources/local/app_database.dart';
import '../datasources/local/connectivity_service.dart';

class CustomerRepositoryImpl implements ICustomerRepository {
  final SupabaseClient client;
  final SupabaseService service;
  final AppDatabase db;

  static const _staleDuration = Duration(minutes: 10);

  CustomerRepositoryImpl({
    required this.client,
    required this.service,
    required this.db,
  });

  @override
  Future<List<CustomerProfileEntity>> getCustomers({String? search}) async {
    // Background sync if stale
    _maybeRefreshCustomerCache().ignore();

    // Serve from local cache
    final cached = search != null && search.trim().isNotEmpty
        ? await db.searchCustomers(search.trim())
        : await db.getAllCustomers();

    if (cached.isEmpty && ConnectivityService.instance.isOnline) {
      await _syncCustomersFromRemote();
      return getCustomers(search: search);
    }

    return cached.map(_cachedToEntity).toList();
  }

  CustomerProfileEntity _cachedToEntity(CachedCustomer row) =>
      CustomerProfileEntity(
        id: row.id,
        userId: row.userId,
        name: row.name,
        phone: row.phone,
        creditLimitCentimes: row.creditLimitCentimes,
        currentDebtCentimes: row.currentDebtCentimes,
        priceTier: PriceTier.fromString(row.priceTier),
        wilaya: row.wilaya,
        commune: row.commune,
        addressText: row.addressText,
      );

  Future<void> _maybeRefreshCustomerCache() async {
    if (!ConnectivityService.instance.isOnline) return;
    final lastSync = await db.getLastSync('customers');
    final isStale = lastSync == null ||
        DateTime.now().difference(lastSync) > _staleDuration;
    if (isStale) _syncCustomersFromRemote().ignore();
  }

  Future<void> _syncCustomersFromRemote() async {
    try {
      var query = client.from('view_customer_balance').select('''
        customer_id, user_id, customer_name, customer_phone,
        credit_limit, current_balance
      ''');
      final rows = await query.order('customer_name', ascending: true);

      final companions = (rows as List).map((row) {
        return CachedCustomersCompanion.insert(
          id: row['customer_id'] as String,
          userId: row['user_id'] as String,
          name: row['customer_name'] as String? ?? 'زبون',
          phone: row['customer_phone'] as String? ?? '',
          creditLimitCentimes: (row['credit_limit'] as num?)?.toInt() ?? 0,
          currentDebtCentimes: (row['current_balance'] as num?)?.toInt() ?? 0,
          priceTier: 'wholesale',
          syncedAt: DateTime.now(),
        );
      }).toList();

      await db.upsertCustomers(companions);
      await db.setLastSync('customers', DateTime.now());
    } catch (_) {}
  }

  @override
  Future<CustomerProfileEntity?> getCustomerById(String customerId) async {
    try {
      final rows = await client
          .from('view_customer_balance')
          .select('''
            customer_id,
            user_id,
            customer_name,
            customer_phone,
            credit_limit,
            current_balance
          ''')
          .eq('customer_id', customerId)
          .limit(1);

      if ((rows as List).isNotEmpty) {
        final row = rows.first;
        return CustomerProfileEntity(
          id: row['customer_id'] as String,
          userId: row['user_id'] as String,
          name: row['customer_name'] as String? ?? 'زبون',
          phone: row['customer_phone'] as String? ?? '',
          creditLimitCentimes: (row['credit_limit'] as num?)?.toInt() ?? 0,
          currentDebtCentimes: (row['current_balance'] as num?)?.toInt() ?? 0,
          priceTier: PriceTier.wholesale,
        );
      }
    } catch (_) {}

    return null;
  }

  @override
  Future<CustomerProfileEntity?> getCustomerByPhone(
    String phone, {
    required String deviceToken,
  }) async {
    final cleanPhone = phone.trim();
    if (cleanPhone.isEmpty) return null;

    final res = await client.rpc('rpc_lookup_customer_by_phone', params: {
      'p_phone': cleanPhone,
      'p_device_token': deviceToken,
    });

    if (res is Map) {
      if (res['device_mismatch'] == true) {
        throw Exception(
          res['message'] ?? 'هذا الحساب مرتبط بجهاز آخر لحماية البيانات',
        );
      }
      if (res['found'] == true) {
        return CustomerProfileEntity(
          id: res['id'] as String,
          userId: res['user_id'] as String,
          name: res['name'] as String? ?? 'زبون',
          phone: res['phone'] as String? ?? cleanPhone,
          creditLimitCentimes: (res['credit_limit'] as num?)?.toInt() ?? 0,
          currentDebtCentimes: 0,
          priceTier:
              PriceTier.fromString(res['price_tier'] as String? ?? 'wholesale'),
          wilaya: res['wilaya'] as String?,
          commune: res['commune'] as String?,
          addressText: res['address_text'] as String?,
          latitude: (res['latitude'] as num?)?.toDouble(),
          longitude: (res['longitude'] as num?)?.toDouble(),
        );
      }
    }

    return null;
  }

  @override
  Future<CustomerProfileEntity> syncCustomerProfile({
    required String name,
    required String phone,
    required String wilaya,
    required String commune,
    required String addressText,
    required String deviceToken,
    double? latitude,
    double? longitude,
    String? existingCustomerId,
    String? existingUserId,
  }) async {
    final cleanPhone = phone.trim();
    final cleanName = name.trim().isNotEmpty ? name.trim() : 'زبون متجر الجملة';

    if (deviceToken.trim().isEmpty) {
      throw Exception('معرف الجهاز مطلوب لمزامنة ملف الزبون');
    }

    final res = await client.rpc('rpc_register_or_bind_customer_device', params: {
      'p_phone': cleanPhone,
      'p_device_token': deviceToken,
      'p_name': cleanName,
      'p_wilaya': wilaya.trim(),
      'p_commune': commune.trim(),
      'p_address_text': addressText.trim(),
      'p_latitude': latitude,
      'p_longitude': longitude,
    });

    if (res is Map && res['success'] == true) {
      return CustomerProfileEntity(
        id: res['customer_id'] as String,
        userId: res['user_id'] as String,
        name: res['name'] as String? ?? cleanName,
        phone: res['phone'] as String? ?? cleanPhone,
        wilaya: res['wilaya'] as String? ?? wilaya,
        commune: res['commune'] as String? ?? commune,
        addressText: res['address_text'] as String? ?? addressText,
        creditLimitCentimes: (res['credit_limit'] as num?)?.toInt() ?? 0,
        currentDebtCentimes: 0,
        priceTier: PriceTier.fromString(res['price_tier'] as String? ?? 'wholesale'),
        latitude: latitude,
        longitude: longitude,
      );
    }

    if (res is Map && res['bound_to_other_device'] == true) {
      throw Exception(res['error'] ?? 'هذا الحساب مرتبط بجهاز آخر بالفعل لحماية البيانات');
    }

    throw Exception(
      (res is Map ? res['error'] : null)?.toString() ??
          'تعذر مزامنة ملف الزبون مع الخادم',
    );
  }

  @override
  Future<CustomerProfileEntity> createCustomer({
    required String name,
    required String phone,
    required String callerId,
    required String callerPin,
    int creditLimitCentimes = 0,
    String priceTier = 'wholesale',
  }) async {
    final res = await client.rpc('rpc_create_customer_by_staff', params: {
      'p_caller_id': callerId,
      'p_caller_pin': callerPin,
      'p_name': name.trim(),
      'p_phone': phone.trim(),
      'p_credit_limit': creditLimitCentimes,
      'p_price_tier': priceTier,
    });

    if (res is! Map || res['status'] != 'success') {
      throw Exception(
        (res is Map ? res['message'] : null)?.toString() ??
            'تعذر تسجيل الزبون',
      );
    }

    return CustomerProfileEntity(
      id: res['customer_id'] as String,
      userId: res['user_id'] as String,
      name: res['name'] as String? ?? name,
      phone: res['phone'] as String? ?? phone,
      creditLimitCentimes:
          (res['credit_limit'] as num?)?.toInt() ?? creditLimitCentimes,
      currentDebtCentimes: 0,
      priceTier: PriceTier.fromString(res['price_tier'] as String? ?? priceTier),
    );
  }

  @override
  Future<List<CustomerLedgerEntryEntity>> getCustomerLedger(String customerId) async {
    try {
      final rows = await client
          .from('customer_ledger')
          .select('''
            id,
            customer_id,
            amount_change,
            ref_type,
            ref_id,
            notes,
            created_at
          ''')
          .eq('customer_id', customerId)
          .order('created_at', ascending: false);

      return (rows as List).map<CustomerLedgerEntryEntity>((row) {
        return CustomerLedgerEntryEntity(
          id: row['id'] as String,
          customerId: row['customer_id'] as String,
          amountChangeCentimes: (row['amount_change'] as num?)?.toInt() ?? 0,
          refType: row['ref_type'] as String? ?? 'payment',
          refId: row['ref_id'] as String? ?? '',
          notes: row['notes'] as String?,
          createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now(),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<CustomerUnpaidOrderEntity>> getCustomerUnpaidOrders(String customerId) async {
    try {
      final rows = await client
          .from('orders')
          .select('''
            id,
            created_at,
            total_amount,
            paid_amount,
            order_items (
              quantity,
              products ( name_ar, name_fr )
            )
          ''')
          .eq('customer_id', customerId)
          .order('created_at', ascending: false);

      final result = <CustomerUnpaidOrderEntity>[];
      for (final row in rows as List) {
        final total = (row['total_amount'] as num?)?.toInt() ?? 0;
        final paid = (row['paid_amount'] as num?)?.toInt() ?? 0;
        final remaining = total - paid;
        if (remaining > 0) {
          final itemsList = <String>[];
          final rawItems = row['order_items'] as List?;
          if (rawItems != null) {
            for (final item in rawItems) {
              final prod = item['products'] as Map<String, dynamic>?;
              final qty = item['quantity'] ?? 1;
              final name = prod?['name_ar'] ?? prod?['name_fr'] ?? 'منتج';
              itemsList.add('$name ($qty)');
            }
          }

          result.add(
            CustomerUnpaidOrderEntity(
              orderId: row['id'] as String,
              orderDate: DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now(),
              totalAmountCentimes: total,
              paidAmountCentimes: paid,
              remainingDebtCentimes: remaining,
              itemsSummary: itemsList,
            ),
          );
        }
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  @override
  Future<CustomerDebtPaymentResult> collectCustomerDebt({
    required String cashierId,
    required String customerId,
    required int amountCentimes,
    required String paymentMethod,
    String? notes,
    String? referenceNumber,
  }) async {
    final noteString = [
      if (notes != null && notes.isNotEmpty) notes,
      if (referenceNumber != null && referenceNumber.isNotEmpty) 'مرجع: $referenceNumber',
    ].join(' | ');

    // The atomic RPC verifies the cashier, writes the payment and ledger
    // rows in one transaction, and is idempotent through p_client_id.
    final rpcRes = await client.rpc('rpc_collect_customer_debt', params: {
      'p_cashier_id': cashierId,
      'p_customer_id': customerId,
      'p_amount': amountCentimes,
      'p_method': paymentMethod,
      'p_notes': noteString.isNotEmpty ? noteString : null,
      'p_client_id': const Uuid().v4(),
    });

    if (rpcRes is! Map || rpcRes['status'] != 'success') {
      throw Exception(
        (rpcRes is Map ? rpcRes['message'] : null)?.toString() ??
            'تعذر تحصيل الدين',
      );
    }

    return CustomerDebtPaymentResult(
      paymentId: rpcRes['payment_id'] as String,
      customerId: customerId,
      paidAmountCentimes: (rpcRes['paid_amount'] as num).toInt(),
      previousBalanceCentimes: (rpcRes['previous_balance'] as num).toInt(),
      remainingBalanceCentimes: (rpcRes['new_balance'] as num).toInt(),
      paymentMethod: paymentMethod,
      timestamp: DateTime.tryParse(rpcRes['timestamp'] as String? ?? '') ??
          DateTime.now(),
      notes: noteString.isNotEmpty ? noteString : null,
    );
  }
}

