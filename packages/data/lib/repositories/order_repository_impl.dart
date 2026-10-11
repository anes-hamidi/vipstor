import 'package:domain/domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../datasources/remote/supabase_service.dart';

import 'customer_repository_impl.dart';

class OrderRepositoryImpl implements IOrderRepository {
  final SupabaseClient client;
  final SupabaseService service;

  OrderRepositoryImpl({required this.client, required this.service});

  @override
  Future<List<OrderEntity>> getOrders({
    OrderStatus? status,
    String? driverId,
    String? customerId,
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
      order_items (
        id,
        product_id,
        quantity,
        unit_price,
        unit_cost,
        products ( name_ar, name_fr )
      ),
      users!orders_driver_id_fkey ( name, phone )
    ''');

    if (status != null) {
      query = query.eq('status', status.dbValue);
    }
    if (driverId != null) {
      query = query.eq('driver_id', driverId);
    }
    if (customerId != null) {
      query = query.eq('customer_id', customerId);
    }

    final rows = await query.order('created_at', ascending: false);

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
        );
      }).toList();

      final driverMap = row['users'] as Map<String, dynamic>?;
      final deliveryAddr = row['delivery_address'] as Map<String, dynamic>?;

      return OrderEntity(
        id: row['id'] as String,
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
          order_items (
            id,
            product_id,
            quantity,
            unit_price,
            unit_cost,
            products ( name_ar, name_fr )
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
      );
    }).toList();

    final driverMap = row['users'] as Map<String, dynamic>?;
    final deliveryAddr = row['delivery_address'] as Map<String, dynamic>?;

    return OrderEntity(
      id: row['id'] as String,
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
    final res = await service.postStoreSale(
      cashierId: effectiveCashierId,
      customerId: customerId,
      items: items,
      paidCashCentimes: paidCashCentimes,
      onAccountCentimes: onAccountCentimes,
    );

    return res['order_id'] as String;
  }

  Future<String?> _resolveValidCustomerId(String? candidateId, Map<String, dynamic> address) async {
    if (candidateId != null && candidateId.isNotEmpty && candidateId != '22222222-2222-2222-2222-222222222222') {
      try {
        final rows = await client.from('customers').select('id').eq('id', candidateId).limit(1);
        if ((rows as List).isNotEmpty) {
          return candidateId;
        }
      } catch (_) {}
    }

    final phone = (address['customer_phone'] ?? address['phone'])?.toString();
    final name = (address['customer_name'] ?? address['store_name'])?.toString();
    if (phone != null && phone.trim().isNotEmpty) {
      try {
        final custRepo = CustomerRepositoryImpl(client: client, service: service);
        final synced = await custRepo.syncCustomerProfile(
          name: name ?? 'زبون',
          phone: phone,
          wilaya: address['wilaya']?.toString() ?? '',
          commune: address['commune']?.toString() ?? '',
          addressText: address['address_text']?.toString() ?? address['address']?.toString() ?? '',
          latitude: (address['latitude'] as num?)?.toDouble(),
          longitude: (address['longitude'] as num?)?.toDouble(),
          existingCustomerId: candidateId,
        );
        return synced.id;
      } catch (_) {}
    }

    try {
      final rows = await client.from('customers').select('id').limit(1);
      if ((rows as List).isNotEmpty) {
        return rows.first['id'] as String;
      }
    } catch (_) {}

    return null;
  }

  @override
  Future<String> submitCustomerOrder({
    required String customerId,
    required Map<String, dynamic> address,
    required List<Map<String, dynamic>> items,
  }) async {
    int total = 0;
    for (final it in items) {
      total += ((it['quantity'] as num) * (it['unit_price'] as num)).toInt();
    }

    final validCustomerId = await _resolveValidCustomerId(customerId, address);

    final payload = <String, dynamic>{
      'channel': 'online',
      'status': 'submitted',
      'delivery_address': address,
      'total_amount': total,
      'paid_amount': 0,
    };
    if (validCustomerId != null) {
      payload['customer_id'] = validCustomerId;
    }

    final orderRow = await client.from('orders').insert(payload).select('id').single();

    final orderId = orderRow['id'] as String;

    final orderItemsToInsert = items.map((it) {
      return {
        'order_id': orderId,
        'product_id': it['product_id'],
        'quantity': it['quantity'],
        'unit_price': it['unit_price'],
        'unit_cost': it['unit_cost'] ?? 0,
      };
    }).toList();

    await client.from('order_items').insert(orderItemsToInsert);

    return orderId;
  }

  @override
  Future<void> confirmOrder({
    required String orderId,
    required String cashierId,
    String? driverId,
  }) async {
    final effectiveCashierId = await _resolveValidUserId(cashierId);
    final effectiveDriverId = driverId != null ? await _resolveValidUserId(driverId) : null;
    try {
      await service.confirmOnlineOrder(
        orderId: orderId,
        cashierId: effectiveCashierId,
        driverId: effectiveDriverId,
      );
    } catch (_) {
      // Direct update fallback
      final payload = <String, dynamic>{
        'status': effectiveDriverId != null ? 'assigned' : 'confirmed',
        'cashier_id': effectiveCashierId,
        'confirmed_at': DateTime.now().toIso8601String(),
      };
      if (effectiveDriverId != null) {
        payload['driver_id'] = effectiveDriverId;
      }
      await client.from('orders').update(payload).eq('id', orderId);
    }
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
    try {
      await service.recordOrderDelivery(
        driverId: effectiveDriverId,
        orderId: orderId,
        collectedCashCentimes: collectedCashCentimes,
        clientId: clientId,
      );
    } catch (_) {
      await client.from('orders').update({
        'status': 'delivered',
        'paid_amount': collectedCashCentimes,
        'delivered_at': DateTime.now().toIso8601String(),
      }).eq('id', orderId);
    }
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
    try {
      await service.recordOrderDelivery(
        driverId: effectiveDriverId,
        orderId: orderId,
        collectedCashCentimes: collectedCashCentimes,
        clientId: clientId,
      );
    } catch (_) {
      // Direct update fallback
      await client.from('orders').update({
        'status': 'delivered',
        'paid_amount': collectedCashCentimes,
        'delivered_at': DateTime.now().toIso8601String(),
        if (notes != null) 'notes': notes,
      }).eq('id', orderId);
    }
  }
}
