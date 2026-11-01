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

  /// Shared order projection. `*` keeps the query forward/backward compatible
  /// with optional proof columns, while relations are selected explicitly.
  static const String _orderSelect = '''
    *,
    order_items (
      id,
      product_id,
      quantity,
      unit_price,
      unit_cost,
      products ( name_ar, name_fr, unit )
    ),
    users!orders_driver_id_fkey ( name, phone )
  ''';

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
    var query = client.from('orders').select(_orderSelect);

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

    return (rows as List).map(_mapOrderRow).toList();
  }

  @override
  Future<OrderEntity> getOrderById(String orderId) async {
    final rows = await client
        .from('orders')
        .select(_orderSelect)
        .eq('id', orderId)
        .limit(1);

    if ((rows as List).isEmpty) {
      throw Exception('Order not found: $orderId');
    }

    return _mapOrderRow(rows.first);
  }

  /// The server derives the real actor from the JWT. This helper only rejects
  /// empty local IDs so offline payloads stay well-formed; it never substitutes
  /// another user.
  String _requireUserId(String? candidateId) {
    if (candidateId == null || candidateId.trim().isEmpty) {
      throw StateError('missing authenticated user id');
    }
    return candidateId;
  }

  @override
  Future<String> createInStoreSale({
    required String cashierId,
    String? customerId,
    required List<Map<String, dynamic>> items,
    required int paidCashCentimes,
    required int onAccountCentimes,
  }) async {
    final effectiveCashierId = _requireUserId(cashierId);
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

  @override
  Future<String> submitCustomerOrder({
    required String customerId,
    required Map<String, dynamic> address,
    required List<Map<String, dynamic>> items,
    String? clientId,
    String? deviceToken,
  }) async {
    // Only send product_id and quantity. The RPC derives the customer from the
    // JWT and computes price/cost server-side; p_customer_id is ignored.
    final cleanItems = items.map((it) {
      return {
        'product_id': it['product_id'],
        'quantity': it['quantity'],
      };
    }).toList();

    return await service.submitCustomerOrder(
      clientId: clientId,
      customerId: customerId,
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
    await service.confirmOnlineOrder(
      orderId: orderId,
      cashierId: _requireUserId(cashierId),
      driverId: driverId,
    );
  }

  @override
  Future<void> updateOrderStatus({
    required String orderId,
    required OrderStatus status,
    String? notes,
  }) async {
    await client.rpc('rpc_update_order_status', params: {
      'p_order_id': orderId,
      'p_status': status.dbValue,
      'p_notes': notes,
    });
  }

  @override
  Future<void> assignOrderToDriver({
    required String orderId,
    required String driverId,
    required String driverName,
    String? driverPhone,
  }) async {
    await client.rpc('rpc_assign_order_driver', params: {
      'p_order_id': orderId,
      'p_driver_id': driverId,
    });
  }

  @override
  Future<void> updateOrderPreparation({
    required String orderId,
    required String preparedBy,
    String? notes,
  }) async {
    await client.rpc('rpc_mark_order_ready', params: {
      'p_order_id': orderId,
      'p_notes': notes,
    });
  }

  @override
  Future<void> recordDelivery({
    required String driverId,
    required String orderId,
    required int collectedCashCentimes,
    required String clientId,
  }) async {
    final effectiveDriverId = _requireUserId(driverId);

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
    String? deliveryRecipientName,
    String? notes,
    required String clientId,
  }) async {
    final effectiveDriverId = _requireUserId(driverId);

    if (ConnectivityService.instance.isOnline) {
      try {
        await service.recordOrderDeliveryWithProof(
          driverId: effectiveDriverId,
          orderId: orderId,
          collectedCashCentimes: collectedCashCentimes,
          clientId: clientId,
          signatureBase64: signatureBase64,
          photoBase64: photoBase64,
          deliveryLat: deliveryLat,
          deliveryLng: deliveryLng,
          recipientName: deliveryRecipientName,
          notes: notes,
        );
        return;
      } catch (_) {
        // Fall through to the offline queue. The sync worker replays the same
        // v2 RPC with the captured proof.
      }
    }

    await db.enqueuePendingOp(PendingOperationsCompanion.insert(
      clientId: clientId,
      operationType: 'delivery',
      payloadJson: jsonEncode({
        'driver_id': effectiveDriverId,
        'order_id': orderId,
        'collected_cash': collectedCashCentimes,
        if (notes != null) 'notes': notes,
        if (signatureBase64 != null) 'signature_base64': signatureBase64,
        if (photoBase64 != null) 'photo_base64': photoBase64,
        if (deliveryLat != null) 'delivery_lat': deliveryLat,
        if (deliveryLng != null) 'delivery_lng': deliveryLng,
        if (deliveryRecipientName != null)
          'delivery_recipient_name': deliveryRecipientName,
      }),
      createdAt: DateTime.now(),
    ));
  }

  @override
  Future<void> reportDeliveryFailure({
    required String driverId,
    required String orderId,
    required String reason,
    String? notes,
    double? deliveryLat,
    double? deliveryLng,
    required String clientId,
  }) async {
    _requireUserId(driverId);

    if (ConnectivityService.instance.isOnline) {
      try {
        await service.recordDeliveryFailure(
          orderId: orderId,
          reason: reason,
          clientId: clientId,
          notes: notes,
          deliveryLat: deliveryLat,
          deliveryLng: deliveryLng,
        );
        return;
      } catch (_) {
        // Fall through to the offline queue.
      }
    }

    await db.enqueuePendingOp(PendingOperationsCompanion.insert(
      clientId: clientId,
      operationType: 'delivery_failure',
      payloadJson: jsonEncode({
        'driver_id': driverId,
        'order_id': orderId,
        'reason': reason,
        if (notes != null) 'notes': notes,
        if (deliveryLat != null) 'delivery_lat': deliveryLat,
        if (deliveryLng != null) 'delivery_lng': deliveryLng,
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
    var query = client.from('orders').select(_orderSelect);

    // Apply filters BEFORE ordering/limiting (required by PostgrestFilterBuilder)
    if (customerId != null) {
      query = query.eq('customer_id', customerId);
    }

    final rows = await query
        .gt('updated_at', since.toUtc().toIso8601String())
        .order('updated_at', ascending: false)
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
    var query = client.from('orders').select(_orderSelect);

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
    final rows =
        await query.order('created_at', ascending: false).range(from, to);

    return _buildOrderEntities(rows as List);
  }

  List<OrderEntity> _buildOrderEntities(List rows) {
    return rows.map(_mapOrderRow).toList();
  }

  OrderEntity _mapOrderRow(dynamic rawRow) {
    final row = Map<String, dynamic>.from(rawRow as Map);
    final itemsList = (row['order_items'] as List? ?? []).map((rawItem) {
      final i = Map<String, dynamic>.from(rawItem as Map);
      final rawProduct = i['products'];
      final productMap =
          rawProduct is Map ? Map<String, dynamic>.from(rawProduct) : null;
      final name = productMap != null
          ? (productMap['name_ar'] ?? productMap['name_fr'] ?? '')
          : '';
      return OrderItemEntity(
        id: i['id'] as String,
        productId: i['product_id'] as String,
        productName: name?.toString() ?? '',
        quantity: (i['quantity'] as num).toInt(),
        unitPriceCentimes: (i['unit_price'] as num).toInt(),
        unitCostCentimes: (i['unit_cost'] as num?)?.toInt() ?? 0,
        unit: productMap?['unit'] as String?,
      );
    }).toList();

    final rawDriver = row['users'];
    final driverMap =
        rawDriver is Map ? Map<String, dynamic>.from(rawDriver) : null;
    final rawAddress = row['delivery_address'];
    final deliveryAddr =
        rawAddress is Map ? Map<String, dynamic>.from(rawAddress) : null;

    return OrderEntity(
      id: row['id'] as String,
      clientId: _stringOrNull(row['client_id']),
      orderNumber: (row['order_number'] as num?)?.toInt(),
      channel:
          row['channel'] == 'online' ? OrderChannel.online : OrderChannel.store,
      customerId: _stringOrNull(row['customer_id']),
      customerName: _stringOrNull(
        deliveryAddr?['customer_name'] ?? deliveryAddr?['store_name'],
      ),
      customerPhone: _stringOrNull(
        deliveryAddr?['customer_phone'] ?? deliveryAddr?['phone'],
      ),
      status: OrderStatus.fromString(row['status'] as String),
      driverId: _stringOrNull(row['driver_id']),
      driverName: _stringOrNull(driverMap?['name']),
      driverPhone: _stringOrNull(driverMap?['phone']),
      totalAmountCentimes: (row['total_amount'] as num).toInt(),
      paidAmountCentimes: (row['paid_amount'] as num).toInt(),
      deliveryAddress: deliveryAddr,
      items: itemsList,
      createdAt: DateTime.parse(row['created_at'] as String),
      signatureBase64: _stringOrNull(row['delivery_signature']),
      photoBase64: _stringOrNull(row['delivery_photo']),
      deliveryLat: _asDouble(row['delivery_lat']),
      deliveryLng: _asDouble(row['delivery_lng']),
      deliveryRecipientName: _stringOrNull(row['delivery_recipient_name']),
      deliveryNotes: _stringOrNull(row['delivery_notes']),
      deliveryFailureReason: _stringOrNull(row['delivery_failure_reason']),
      deliveryAttemptedAt: _parseOptionalDate(row['delivery_attempted_at']),
      confirmedAt: _parseOptionalDate(row['confirmed_at']),
      deliveredAt: _parseOptionalDate(row['delivered_at']),
      settledAt: _parseOptionalDate(row['settled_at']),
      notes: _stringOrNull(row['notes']),
    );
  }

  static String? _stringOrNull(dynamic value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : value;
  }

  static double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static DateTime? _parseOptionalDate(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}
