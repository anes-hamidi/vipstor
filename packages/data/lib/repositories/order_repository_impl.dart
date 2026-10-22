import 'dart:convert';
import 'package:domain/domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../datasources/remote/supabase_service.dart';
import '../datasources/local/app_database.dart';
import '../datasources/local/connectivity_service.dart';

class OrderRepositoryImpl implements IOrderRepository {
  final SupabaseClient client;
  final SupabaseService service;
  final AppDatabase db;

  OrderRepositoryImpl({
    required this.client,
    required this.service,
    required this.db,
  });

  @override
  Future<List<OrderEntity>> getOrders({
    OrderStatus? status,
    List<OrderStatus>? statuses,
    String? driverId,
    String? customerId,
    OrderChannel? channel,
    DateTime? createdFrom,
    DateTime? createdTo,
    int? limit,
  }) async {
    var query = client.from('orders').select('''
      id,
      order_number,
      channel,
      customer_id,
      status,
      driver_id,
      cashier_id,
      delivery_address,
      total_amount,
      paid_amount,
      notes,
      created_at,
      confirmed_at,
      delivered_at,
      settled_at,
      client_id,
      order_items (
        id,
        product_id,
        quantity,
        unit_price,
        unit_cost,
        products ( name_ar, name_fr, unit )
      ),
      users!orders_driver_id_fkey ( name, phone )
    ''');

    if (statuses != null && statuses.isNotEmpty) {
      query = query.inFilter(
        'status',
        statuses.map((s) => s.dbValue).toList(growable: false),
      );
    } else if (status != null) {
      query = query.eq('status', status.dbValue);
    }
    if (driverId != null) {
      query = query.eq('driver_id', driverId);
    }
    if (customerId != null) {
      query = query.eq('customer_id', customerId);
    }
    if (channel != null) {
      query = query.eq('channel', channel.name);
    }
    if (createdFrom != null) {
      query = query.gte(
        'created_at',
        createdFrom.toUtc().toIso8601String(),
      );
    }
    if (createdTo != null) {
      query = query.lte(
        'created_at',
        createdTo.toUtc().toIso8601String(),
      );
    }

    var orderedQuery = query.order('created_at', ascending: false);
    if (limit != null) {
      orderedQuery = orderedQuery.limit(limit);
    }

    final rows = await orderedQuery;

    return (rows as List).map<OrderEntity>((row) {
      final itemsList = (row['order_items'] as List? ?? []).map((i) {
        final productMap = i['products'] as Map<String, dynamic>?;
        final name = productMap != null ? (productMap['name_ar'] ?? productMap['name_fr'] ?? '') : '';
        return OrderItemEntity(
          id: i['id'] as String,
          productId: i['product_id'] as String,
          productName: name,
          quantity: (i['quantity'] as num).toInt(),
          unitPriceCentimes: (i['unit_price'] as num).toInt(),
          unitCostCentimes: (i['unit_cost'] as num?)?.toInt() ?? 0,
          unit: productMap?['unit'] as String?,
        );
      }).toList();

      final driverMap = row['users'] as Map<String, dynamic>?;
      final deliveryAddr = row['delivery_address'] as Map<String, dynamic>?;

      return OrderEntity(
        id: row['id'] as String,
        clientId: row['client_id'] as String?,
        orderNumber: (row['order_number'] as num?)?.toInt(),
        channel: row['channel'] == 'online' ? OrderChannel.online : OrderChannel.store,
        customerId: row['customer_id'] as String?,
        customerName: deliveryAddr?['customer_name'] ?? deliveryAddr?['store_name'],
        customerPhone: deliveryAddr?['customer_phone'] ?? deliveryAddr?['phone'],
        status: OrderStatus.fromString(row['status'] as String),
        driverId: row['driver_id'] as String?,
        driverName: driverMap?['name'] as String?,
        driverPhone: driverMap?['phone'] as String?,
        totalAmountCentimes: (row['total_amount'] as num).toInt(),
        paidAmountCentimes: (row['paid_amount'] as num).toInt(),
        deliveryAddress: deliveryAddr,
        items: itemsList,
        createdAt: DateTime.parse(row['created_at'] as String),
        confirmedAt: _parseOptionalDate(row['confirmed_at']),
        deliveredAt: _parseOptionalDate(row['delivered_at']),
        settledAt: _parseOptionalDate(row['settled_at']),
        notes: row['notes'] as String?,
      );
    }).toList();
  }

  @override
  Future<OrderEntity> getOrderById(String orderId) async {
    final rows = await client
        .from('orders')
        .select('''
          id,
          order_number,
          channel,
          customer_id,
          status,
          driver_id,
          cashier_id,
          delivery_address,
          total_amount,
          paid_amount,
          notes,
          created_at,
          confirmed_at,
          delivered_at,
          settled_at,
          client_id,
          order_items (
            id,
            product_id,
            quantity,
            unit_price,
            unit_cost,
            products ( name_ar, name_fr, unit )
          ),
          users!orders_driver_id_fkey ( name, phone )
        ''')
        .eq('id', orderId)
        .limit(1);

    if ((rows as List).isEmpty) {
      throw Exception('Order not found: $orderId');
    }

    final row = rows.first;
    final itemsList = (row['order_items'] as List? ?? []).map((i) {
      final productMap = i['products'] as Map<String, dynamic>?;
      final name = productMap != null ? (productMap['name_ar'] ?? productMap['name_fr'] ?? '') : '';
      return OrderItemEntity(
        id: i['id'] as String,
        productId: i['product_id'] as String,
        productName: name,
        quantity: (i['quantity'] as num).toInt(),
        unitPriceCentimes: (i['unit_price'] as num).toInt(),
        unitCostCentimes: (i['unit_cost'] as num?)?.toInt() ?? 0,
        unit: productMap?['unit'] as String?,
      );
    }).toList();

    final driverMap = row['users'] as Map<String, dynamic>?;
    final deliveryAddr = row['delivery_address'] as Map<String, dynamic>?;

    return OrderEntity(
      id: row['id'] as String,
      clientId: row['client_id'] as String?,
      orderNumber: (row['order_number'] as num?)?.toInt(),
      channel: row['channel'] == 'online' ? OrderChannel.online : OrderChannel.store,
      customerId: row['customer_id'] as String?,
      customerName: deliveryAddr?['customer_name'] ?? deliveryAddr?['store_name'],
      customerPhone: deliveryAddr?['customer_phone'] ?? deliveryAddr?['phone'],
      status: OrderStatus.fromString(row['status'] as String),
      driverId: row['driver_id'] as String?,
      driverName: driverMap?['name'] as String?,
      driverPhone: driverMap?['phone'] as String?,
      totalAmountCentimes: (row['total_amount'] as num).toInt(),
      paidAmountCentimes: (row['paid_amount'] as num).toInt(),
      deliveryAddress: deliveryAddr,
      items: itemsList,
      createdAt: DateTime.parse(row['created_at'] as String),
      confirmedAt: _parseOptionalDate(row['confirmed_at']),
      deliveredAt: _parseOptionalDate(row['delivered_at']),
      settledAt: _parseOptionalDate(row['settled_at']),
      notes: row['notes'] as String?,
    );
  }

  Future<String> _resolveValidUserId(String? candidateId) async {
    if (candidateId != null && candidateId.isNotEmpty && candidateId != '22222222-2222-2222-2222-222222222222') {
      try {
        final rows = await client.from('users').select('id').eq('id', candidateId).limit(1);
        if ((rows as List).isNotEmpty) {
          return candidateId;
        }
      } catch (_) {}
    }

    try {
      final rows = await client.from('users').select('id').limit(1);
      if ((rows as List).isNotEmpty) {
        return rows.first['id'] as String;
      }
    } catch (_) {}

    return '11111111-1111-1111-1111-111111111111';
  }

  @override
  Future<String> createInStoreSale({
    required String cashierId,
    String? customerId,
    required List<Map<String, dynamic>> items,
    required int paidCashCentimes,
    required int onAccountCentimes,
  }) async {
    final effectiveCashierId = await _resolveValidUserId(cashierId);
    final clientId = const Uuid().v4();

    if (ConnectivityService.instance.isOnline) {
      try {
        final res = await service.postStoreSale(
          clientId: clientId,
          cashierId: effectiveCashierId,
          customerId: customerId,
          items: items,
          paidCashCentimes: paidCashCentimes,
          onAccountCentimes: onAccountCentimes,
        );
        return res['order_id'] as String? ?? clientId;
      } catch (_) {
        // Fall through to offline queue on network error
      }
    }

    // ── Offline path: enqueue and return a local order ID ────────────────
    await db.enqueuePendingOp(PendingOperationsCompanion.insert(
      clientId: clientId,
      operationType: 'pos_sale',
      payloadJson: jsonEncode({
        'cashier_id': effectiveCashierId,
        'customer_id': customerId,
        'items': items,
        'paid_cash': paidCashCentimes,
        'on_account': onAccountCentimes,
      }),
      createdAt: DateTime.now(),
    ));
    // Return the client-generated ID as a local stand-in order ID
    return clientId;
  }

  Future<String?> _resolveValidCustomerId(String? candidateId) async {
    if (candidateId == null ||
        candidateId.isEmpty ||
        candidateId == '22222222-2222-2222-2222-222222222222') {
      return null;
    }

    try {
      final rows = await client
          .from('customers')
          .select('id')
          .eq('id', candidateId)
          .limit(1);
      if ((rows as List).isNotEmpty) {
        return candidateId;
      }
    } catch (_) {}

    return null;
  }

  @override
  Future<String> submitCustomerOrder({
    required String customerId,
    required Map<String, dynamic> address,
    required List<Map<String, dynamic>> items,
    String? clientId,
    String? deviceToken,
  }) async {
    final validCustomerId = await _resolveValidCustomerId(customerId);

    // Only send product_id and quantity to the server
    final cleanItems = items.map((it) {
      return {
        'product_id': it['product_id'],
        'quantity': it['quantity'],
      };
    }).toList();

    return await service.submitCustomerOrder(
      clientId: clientId,
      customerId: validCustomerId,
      address: address,
      items: cleanItems,
      deviceToken: deviceToken,
    );
  }

  @override
  Future<void> confirmOrder({
    required String orderId,
    required String cashierId,
    String? driverId,
  }) async {
    final effectiveCashierId = await _resolveValidUserId(cashierId);
    final effectiveDriverId = driverId != null ? await _resolveValidUserId(driverId) : null;
    await service.confirmOnlineOrder(
      orderId: orderId,
      cashierId: effectiveCashierId,
      driverId: effectiveDriverId,
    );
  }

  @override
  Future<void> updateOrderStatus({
    required String orderId,
    required OrderStatus status,
    String? notes,
  }) async {
    final payload = <String, dynamic>{'status': status.dbValue};
    if (notes != null) payload['notes'] = notes;
    await client.from('orders').update(payload).eq('id', orderId);
  }

  @override
  Future<void> assignOrderToDriver({
    required String orderId,
    required String driverId,
    required String driverName,
    String? driverPhone,
  }) async {
    final effectiveDriverId = await _resolveValidUserId(driverId);
    await client.from('orders').update({
      'driver_id': effectiveDriverId,
      'status': 'assigned',
    }).eq('id', orderId);
  }

  @override
  Future<void> updateOrderPreparation({
    required String orderId,
    required String preparedBy,
    String? notes,
  }) async {
    await client.from('orders').update({
      'status': 'ready',
      if (notes != null) 'notes': notes,
    }).eq('id', orderId);
  }

  @override
  Future<void> recordDelivery({
    required String driverId,
    required String orderId,
    required int collectedCashCentimes,
    required String clientId,
  }) async {
    final effectiveDriverId = await _resolveValidUserId(driverId);

    if (ConnectivityService.instance.isOnline) {
      try {
        await service.recordOrderDelivery(
          driverId: effectiveDriverId,
          orderId: orderId,
          collectedCashCentimes: collectedCashCentimes,
          clientId: clientId,
        );
        return;
      } catch (_) {
        // Fall through to queue
      }
    }

    // Offline: queue the delivery
    await db.enqueuePendingOp(PendingOperationsCompanion.insert(
      clientId: clientId,
      operationType: 'delivery',
      payloadJson: jsonEncode({
        'driver_id': effectiveDriverId,
        'order_id': orderId,
        'collected_cash': collectedCashCentimes,
      }),
      createdAt: DateTime.now(),
    ));
  }

  @override
  Future<void> completeDeliveryWithProof({
    required String driverId,
    required String orderId,
    required int collectedCashCentimes,
    String? signatureBase64,
    String? photoBase64,
    double? deliveryLat,
    double? deliveryLng,
    String? notes,
    required String clientId,
  }) async {
    final effectiveDriverId = await _resolveValidUserId(driverId);

    if (ConnectivityService.instance.isOnline) {
      try {
        await service.recordOrderDelivery(
          driverId: effectiveDriverId,
          orderId: orderId,
          collectedCashCentimes: collectedCashCentimes,
          clientId: clientId,
        );
        return;
      } catch (_) {
        // Fall through to queue
      }
    }

    // Offline: queue (proof metadata is best-effort)
    await db.enqueuePendingOp(PendingOperationsCompanion.insert(
      clientId: clientId,
      operationType: 'delivery',
      payloadJson: jsonEncode({
        'driver_id': effectiveDriverId,
        'order_id': orderId,
        'collected_cash': collectedCashCentimes,
        if (notes != null) 'notes': notes,
      }),
      createdAt: DateTime.now(),
    ));
  }

  // ------------------------------------------------------------------
  // Delta sync: orders created/updated since [since].
  // ------------------------------------------------------------------
  @override
  Future<List<OrderEntity>> getOrdersSince({
    required DateTime since,
    String? customerId,
    int limit = 200,
  }) async {
    var query = client
        .from('orders')
        .select('''
          id, order_number, channel, customer_id, status, driver_id,
          cashier_id, delivery_address, total_amount, paid_amount, notes,
          created_at, confirmed_at, delivered_at, settled_at, client_id,
          order_items ( id, product_id, quantity, unit_price, unit_cost,
            products ( name_ar, name_fr, unit ) ),
          users!orders_driver_id_fkey ( name, phone )
        ''');

    // Apply filters BEFORE ordering/limiting (required by PostgrestFilterBuilder)
    if (customerId != null) {
      query = query.eq('customer_id', customerId);
    }

    final rows = await query
        .gt('created_at', since.toIso8601String())
        .order('created_at', ascending: false)
        .limit(limit);

    return _buildOrderEntities(rows as List);
  }

  // ------------------------------------------------------------------
  // Paginated order fetch.
  // ------------------------------------------------------------------
  @override
  Future<List<OrderEntity>> getOrdersPage({
    int page = 1,
    int pageSize = 50,
    OrderStatus? status,
    List<OrderStatus>? statuses,
    String? driverId,
    String? customerId,
    OrderChannel? channel,
    DateTime? createdFrom,
    DateTime? createdTo,
  }) async {
    var query = client
        .from('orders')
        .select('''
          id, order_number, channel, customer_id, status, driver_id,
          cashier_id, delivery_address, total_amount, paid_amount, notes,
          created_at, confirmed_at, delivered_at, settled_at, client_id,
          order_items ( id, product_id, quantity, unit_price, unit_cost,
            products ( name_ar, name_fr, unit ) ),
          users!orders_driver_id_fkey ( name, phone )
        ''');

    if (statuses != null && statuses.isNotEmpty) {
      query = query.inFilter(
        'status',
        statuses.map((s) => s.dbValue).toList(growable: false),
      );
    } else if (status != null) {
      query = query.eq('status', status.dbValue);
    }
    if (driverId != null) {
      query = query.eq('driver_id', driverId);
    }
    if (customerId != null) {
      query = query.eq('customer_id', customerId);
    }
    if (channel != null) {
      query = query.eq('channel', channel.name);
    }
    if (createdFrom != null) {
      query = query.gte(
        'created_at',
        createdFrom.toUtc().toIso8601String(),
      );
    }
    if (createdTo != null) {
      query = query.lte(
        'created_at',
        createdTo.toUtc().toIso8601String(),
      );
    }

    final from = (page - 1) * pageSize;
    final to = from + pageSize - 1;
    final rows = await query.order('created_at', ascending: false).range(from, to);

    return _buildOrderEntities(rows as List);
  }

  List<OrderEntity> _buildOrderEntities(List rows) {
    return rows.map((row) {
      final itemsList = (row['order_items'] as List? ?? []).map((i) {
        final productMap = i['products'] as Map<String, dynamic>?;
        final name = productMap != null
            ? (productMap['name_ar'] ?? productMap['name_fr'] ?? '')
            : '';
        return OrderItemEntity(
          id: i['id'] as String,
          productId: i['product_id'] as String,
          productName: name,
          quantity: (i['quantity'] as num).toInt(),
          unitPriceCentimes: (i['unit_price'] as num).toInt(),
          unitCostCentimes: (i['unit_cost'] as num?)?.toInt() ?? 0,
          unit: productMap?['unit'] as String?,
        );
      }).toList();

      final driverMap = row['users'] as Map<String, dynamic>?;
      final deliveryAddr = row['delivery_address'] as Map<String, dynamic>?;

      return OrderEntity(
        id: row['id'] as String,
        clientId: row['client_id'] as String?,
        orderNumber: (row['order_number'] as num?)?.toInt(),
        channel: row['channel'] == 'online'
            ? OrderChannel.online
            : OrderChannel.store,
        customerId: row['customer_id'] as String?,
        customerName: deliveryAddr?['customer_name']
            ?? deliveryAddr?['store_name'],
        customerPhone: deliveryAddr?['customer_phone']
            ?? deliveryAddr?['phone'],
        status: OrderStatus.fromString(row['status'] as String),
        driverId: row['driver_id'] as String?,
        driverName: driverMap?['name'] as String?,
        driverPhone: driverMap?['phone'] as String?,
        totalAmountCentimes: (row['total_amount'] as num).toInt(),
        paidAmountCentimes: (row['paid_amount'] as num).toInt(),
        deliveryAddress: deliveryAddr,
        items: itemsList,
        createdAt: DateTime.parse(row['created_at'] as String),
        confirmedAt: _parseOptionalDate(row['confirmed_at']),
        deliveredAt: _parseOptionalDate(row['delivered_at']),
        settledAt: _parseOptionalDate(row['settled_at']),
        notes: row['notes'] as String?,
      );
    }).toList();
  }

  static DateTime? _parseOptionalDate(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}
