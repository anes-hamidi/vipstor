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
  Future<CustomerProfileEntity?> getCustomerByPhone(String phone) async {
    final cleanPhone = phone.trim();
    if (cleanPhone.isEmpty) return null;

    try {
      // 1. Find user by phone
      final userRows = await client
          .from('users')
          .select('id, name, phone, role')
          .eq('phone', cleanPhone)
          .limit(1);

      if ((userRows as List).isEmpty) {
        return null;
      }

      final user = userRows.first;
      final userId = user['id'] as String;

      // 2. Find customer record
      var customerRows = await client
          .from('customers')
          .select('id, credit_limit, price_tier')
          .eq('user_id', userId)
          .limit(1);

      String customerId;
      int creditLimit = 0;
      String priceTier = 'wholesale';

      if ((customerRows as List).isEmpty) {
        // Auto-create customer record for this user
        final newCust = await client.from('customers').insert({
          'user_id': userId,
        }).select('id, credit_limit, price_tier').single();
        customerId = newCust['id'] as String;
        creditLimit = (newCust['credit_limit'] as num?)?.toInt() ?? 0;
        priceTier = newCust['price_tier'] as String? ?? 'wholesale';
      } else {
        final cust = customerRows.first;
        customerId = cust['id'] as String;
        creditLimit = (cust['credit_limit'] as num?)?.toInt() ?? 0;
        priceTier = cust['price_tier'] as String? ?? 'wholesale';
      }

      // 3. Fetch default address if exists
      String? wilaya;
      String? commune;
      String? addressText;
      double? lat;
      double? lng;

      try {
        final addrRows = await client
            .from('addresses')
            .select('wilaya, commune, address_text, latitude, longitude')
            .eq('customer_id', customerId)
            .order('is_default', ascending: false)
            .limit(1);

        if ((addrRows as List).isNotEmpty) {
          final addr = addrRows.first;
          wilaya = addr['wilaya'] as String?;
          commune = addr['commune'] as String?;
          addressText = addr['address_text'] as String?;
          lat = (addr['latitude'] as num?)?.toDouble();
          lng = (addr['longitude'] as num?)?.toDouble();
        }
      } catch (_) {}

      return CustomerProfileEntity(
        id: customerId,
        userId: userId,
        name: user['name'] as String? ?? 'زبون',
        phone: user['phone'] as String? ?? cleanPhone,
        creditLimitCentimes: creditLimit,
        currentDebtCentimes: 0,
        priceTier: PriceTier.fromString(priceTier),
        wilaya: wilaya,
        commune: commune,
        addressText: addressText,
        latitude: lat,
        longitude: lng,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<CustomerProfileEntity> syncCustomerProfile({
    required String name,
    required String phone,
    required String wilaya,
    required String commune,
    required String addressText,
    double? latitude,
    double? longitude,
    String? existingCustomerId,
    String? existingUserId,
  }) async {
    final cleanPhone = phone.trim();
    final cleanName = name.trim().isNotEmpty ? name.trim() : 'زبون متجر الجملة';

    String? userId = existingUserId;

    // 1. Try finding existing user by ID or Phone
    if (userId == null || userId.isEmpty) {
      try {
        final existingByPhone = await client
            .from('users')
            .select('id')
            .eq('phone', cleanPhone)
            .limit(1);
        if ((existingByPhone as List).isNotEmpty) {
          userId = existingByPhone.first['id'] as String;
        }
      } catch (_) {}
    }

    // If still null and existingCustomerId is provided, find user_id from customer
    if (userId == null && existingCustomerId != null && existingCustomerId.isNotEmpty) {
      try {
        final cust = await client
            .from('customers')
            .select('user_id')
            .eq('id', existingCustomerId)
            .limit(1);
        if ((cust as List).isNotEmpty) {
          userId = cust.first['user_id'] as String;
        }
      } catch (_) {}
    }

    // 2. Insert or Update Users table
    if (userId != null) {
      try {
        await client.from('users').update({
          'name': cleanName,
          'phone': cleanPhone,
          'active': true,
        }).eq('id', userId);
      } catch (_) {}
    } else {
      final userRow = await client.from('users').insert({
        'name': cleanName,
        'phone': cleanPhone,
        'role': 'customer',
        'language': 'ar',
        'active': true,
      }).select('id, name, phone, role, language, active').single();
      userId = userRow['id'] as String;
    }

    // 3. Find or Create Customers row
    String? customerId = existingCustomerId;
    int creditLimit = 0;
    String priceTier = 'wholesale';

    try {
      final custRows = await client
          .from('customers')
          .select('id, credit_limit, price_tier')
          .eq('user_id', userId)
          .limit(1);

      if ((custRows as List).isNotEmpty) {
        final c = custRows.first;
        customerId = c['id'] as String;
        creditLimit = (c['credit_limit'] as num?)?.toInt() ?? 0;
        priceTier = c['price_tier'] as String? ?? 'wholesale';
      } else {
        final newCust = await client.from('customers').insert({
          'user_id': userId,
        }).select('id, credit_limit, price_tier').single();
        customerId = newCust['id'] as String;
        creditLimit = (newCust['credit_limit'] as num?)?.toInt() ?? 0;
        priceTier = newCust['price_tier'] as String? ?? 'wholesale';
      }
    } catch (_) {
      customerId ??= userId;
    }

    // 4. Upsert Address in addresses table
    try {
      final addrRows = await client
          .from('addresses')
          .select('id')
          .eq('customer_id', customerId)
          .limit(1);

      if ((addrRows as List).isNotEmpty) {
        final addrId = addrRows.first['id'] as String;
        await client.from('addresses').update({
          'wilaya': wilaya,
          'commune': commune,
          'address_text': addressText,
          'latitude': latitude,
          'longitude': longitude,
          'is_default': true,
        }).eq('id', addrId);
      } else {
        await client.from('addresses').insert({
          'customer_id': customerId,
          'label': 'المحل الرئيسي',
          'wilaya': wilaya,
          'commune': commune,
          'address_text': addressText,
          'latitude': latitude,
          'longitude': longitude,
          'is_default': true,
        });
      }
    } catch (_) {}

    return CustomerProfileEntity(
      id: customerId,
      userId: userId,
      name: cleanName,
      phone: cleanPhone,
      creditLimitCentimes: creditLimit,
      currentDebtCentimes: 0,
      priceTier: PriceTier.fromString(priceTier),
      wilaya: wilaya,
      commune: commune,
      addressText: addressText,
      latitude: latitude,
      longitude: longitude,
    );
  }

  @override
  Future<CustomerProfileEntity> createCustomer({
    required String name,
    required String phone,
    int creditLimitCentimes = 0,
    String priceTier = 'wholesale',
  }) async {
    // 1. Create User
    final userRow = await client.from('users').insert({
      'name': name,
      'phone': phone,
      'role': 'customer',
      'language': 'ar',
      'active': true,
    }).select('id, name, phone, role, language, active').single();

    final userId = userRow['id'] as String;

    // 2. Create Customer record (inserting user_id only per restricted permissions)
    final customerRow = await client.from('customers').insert({
      'user_id': userId,
    }).select('id, credit_limit, price_tier').single();

    return CustomerProfileEntity(
      id: customerRow['id'] as String,
      userId: userId,
      name: name,
      phone: phone,
      creditLimitCentimes: creditLimitCentimes,
      currentDebtCentimes: 0,
      priceTier: PriceTier.fromString(priceTier),
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

    try {
      // 1. Try atomic RPC (p_client_id ensures idempotency on network retry)
      final rpcRes = await client.rpc('rpc_collect_customer_debt', params: {
        'p_cashier_id': cashierId,
        'p_customer_id': customerId,
        'p_amount': amountCentimes,
        'p_method': paymentMethod,
        'p_notes': noteString.isNotEmpty ? noteString : null,
        'p_client_id': const Uuid().v4(),
      });

      if (rpcRes != null && rpcRes['status'] == 'success') {
        return CustomerDebtPaymentResult(
          paymentId: rpcRes['payment_id'] as String,
          customerId: customerId,
          paidAmountCentimes: (rpcRes['paid_amount'] as num).toInt(),
          previousBalanceCentimes: (rpcRes['previous_balance'] as num).toInt(),
          remainingBalanceCentimes: (rpcRes['new_balance'] as num).toInt(),
          paymentMethod: paymentMethod,
          timestamp: DateTime.tryParse(rpcRes['timestamp'] as String? ?? '') ?? DateTime.now(),
          notes: noteString.isNotEmpty ? noteString : null,
        );
      }
    } catch (_) {
      // Fallback: direct table transactions if RPC is not deployed yet
    }

    // Direct fallback
    final customer = await getCustomerById(customerId);
    final prevBalance = customer?.currentDebtCentimes ?? 0;
    final remaining = (prevBalance - amountCentimes) > 0 ? (prevBalance - amountCentimes) : 0;

    final payRow = await client.from('payments').insert({
      'customer_id': customerId,
      'amount': amountCentimes,
      'method': paymentMethod,
      'received_by': cashierId,
      'status': 'settled',
    }).select().single();

    final paymentId = payRow['id'] as String;

    await client.from('customer_ledger').insert({
      'customer_id': customerId,
      'amount_change': -amountCentimes,
      'ref_type': 'payment',
      'ref_id': paymentId,
      'notes': noteString.isNotEmpty ? noteString : 'سداد دين عند الكاشير',
    });

    return CustomerDebtPaymentResult(
      paymentId: paymentId,
      customerId: customerId,
      paidAmountCentimes: amountCentimes,
      previousBalanceCentimes: prevBalance,
      remainingBalanceCentimes: remaining,
      paymentMethod: paymentMethod,
      timestamp: DateTime.now(),
      notes: noteString.isNotEmpty ? noteString : null,
    );
  }
}

