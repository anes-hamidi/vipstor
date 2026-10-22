import 'dart:math' as math;

import 'package:domain/domain.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Offline / cached models for the customer experience.
// ─────────────────────────────────────────────────────────────────────────────

/// A cart line captured at the moment the customer checked out while offline.
///
/// Product names, units and prices are stored so the pending order can be
/// rendered with real data instead of "منتج / 0 دج" placeholders.
class PendingOrderItem {
  final String productId;
  final String name;
  final String unit;
  final int quantity;
  final int unitPriceCentimes;
  final int unitCostCentimes;

  const PendingOrderItem({
    required this.productId,
    required this.name,
    required this.unit,
    required this.quantity,
    required this.unitPriceCentimes,
    this.unitCostCentimes = 0,
  });

  int get lineTotalCentimes => quantity * unitPriceCentimes;

  Map<String, dynamic> toJson() => {
        'product_id': productId,
        'product_name': name,
        'unit': unit,
        'quantity': quantity,
        'unit_price': unitPriceCentimes,
        'unit_cost': unitCostCentimes,
      };

  factory PendingOrderItem.fromJson(Map<String, dynamic> j) =>
      PendingOrderItem(
        productId: j['product_id'] as String? ?? '',
        name: j['product_name'] as String? ?? 'منتج',
        unit: j['unit'] as String? ?? 'piece',
        quantity: (j['quantity'] as num?)?.toInt() ?? 1,
        unitPriceCentimes: (j['unit_price'] as num?)?.toInt() ?? 0,
        unitCostCentimes: (j['unit_cost'] as num?)?.toInt() ?? 0,
      );
}

/// An order queued locally until the device gets connectivity back.
class PendingOrder {
  final String clientId;
  final String? customerId;
  final Map<String, dynamic> deliveryAddress;
  final List<PendingOrderItem> items;
  final int totalAmountCentimes;
  final DateTime createdAt;
  final String? lastError;

  const PendingOrder({
    required this.clientId,
    required this.customerId,
    required this.deliveryAddress,
    required this.items,
    required this.totalAmountCentimes,
    required this.createdAt,
    this.lastError,
  });

  String get tempId => clientId;

  OrderEntity toOrderEntity({
    String customerName = '',
    String customerPhone = '',
  }) {
    return OrderEntity(
      id: clientId,
      clientId: clientId,
      channel: OrderChannel.online,
      customerId: customerId,
      customerName: deliveryAddress['customer_name'] as String? ?? customerName,
      customerPhone: deliveryAddress['customer_phone'] as String? ?? customerPhone,
      status: OrderStatus.submitted,
      totalAmountCentimes: totalAmountCentimes,
      paidAmountCentimes: 0,
      deliveryAddress: deliveryAddress,
      items: items
          .map(
            (item) => OrderItemEntity(
              id: '${clientId}_${item.productId}',
              productId: item.productId,
              productName: item.name,
              quantity: item.quantity,
              unitPriceCentimes: item.unitPriceCentimes,
              unitCostCentimes: item.unitCostCentimes,
              unit: item.unit,
            ),
          )
          .toList(),
      createdAt: createdAt,
      notes: 'في انتظار المزامنة (محفوظ محلياً)',
    );
  }

  PendingOrder copyWith({String? lastError}) => PendingOrder(
        clientId: clientId,
        customerId: customerId,
        deliveryAddress: deliveryAddress,
        items: items,
        totalAmountCentimes: totalAmountCentimes,
        createdAt: createdAt,
        lastError: lastError ?? this.lastError,
      );

  Map<String, dynamic> toJson() => {
        'client_id': clientId,
        'customer_id': customerId,
        'delivery_address': deliveryAddress,
        'items': items.map((i) => i.toJson()).toList(),
        'total_amount': totalAmountCentimes,
        'created_at': createdAt.toIso8601String(),
        'last_error': lastError,
      };

  factory PendingOrder.fromJson(Map<String, dynamic> j) => PendingOrder(
        clientId: j['client_id'] as String? ?? j['id'] as String? ?? '',
        customerId: j['customer_id'] as String?,
        deliveryAddress:
            (j['delivery_address'] as Map?)?.cast<String, dynamic>() ?? const {},
        items: (j['items'] as List? ?? [])
            .map((i) => PendingOrderItem.fromJson(
                  (i as Map).cast<String, dynamic>(),
                ))
            .where((i) => i.productId.isNotEmpty)
            .toList(),
        totalAmountCentimes: (j['total_amount'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ??
            DateTime.now(),
        lastError: j['last_error'] as String?,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Snapshots
// ─────────────────────────────────────────────────────────────────────────────

class CatalogSnapshot {
  final List<ProductEntity> products;
  final DateTime? syncedAt;
  final bool isOffline;
  final String? lastError;
  final Map<String, int> affinity;

  const CatalogSnapshot({
    required this.products,
    this.syncedAt,
    this.isOffline = false,
    this.lastError,
    this.affinity = const {},
  });

  CatalogSnapshot copyWith({
    List<ProductEntity>? products,
    DateTime? syncedAt,
    bool? isOffline,
    String? lastError,
    Map<String, int>? affinity,
  }) =>
      CatalogSnapshot(
        products: products ?? this.products,
        syncedAt: syncedAt ?? this.syncedAt,
        isOffline: isOffline ?? this.isOffline,
        lastError: lastError ?? this.lastError,
        affinity: affinity ?? this.affinity,
      );
}

class OrdersSnapshot {
  final String? customerId;
  final List<OrderEntity> orders;
  final int pendingCount;
  final DateTime? fetchedAt;
  final bool isOffline;
  final String? lastError;

  const OrdersSnapshot({
    this.customerId,
    required this.orders,
    this.pendingCount = 0,
    this.fetchedAt,
    this.isOffline = false,
    this.lastError,
  });

  OrdersSnapshot copyWith({
    String? customerId,
    List<OrderEntity>? orders,
    int? pendingCount,
    DateTime? fetchedAt,
    bool? isOffline,
    String? lastError,
  }) =>
      OrdersSnapshot(
        customerId: customerId ?? this.customerId,
        orders: orders ?? this.orders,
        pendingCount: pendingCount ?? this.pendingCount,
        fetchedAt: fetchedAt ?? this.fetchedAt,
        isOffline: isOffline ?? this.isOffline,
        lastError: lastError ?? this.lastError,
      );

  List<OrderEntity> get activeOrders =>
      orders.where((o) => o.isOpen).toList(growable: false);

  List<OrderEntity> get pastOrders =>
      orders.where((o) => !o.isOpen).toList(growable: false);
}

class WalletSnapshot {
  final String? customerId;
  final String customerName;
  final int creditLimitCentimes;
  final int currentDebtCentimes;
  final List<CustomerLedgerEntryEntity> ledger;
  final List<CustomerUnpaidOrderEntity> unpaidOrders;
  final DateTime? fetchedAt;
  final bool isOffline;
  final String? lastError;

  const WalletSnapshot({
    this.customerId,
    this.customerName = '',
    this.creditLimitCentimes = 0,
    this.currentDebtCentimes = 0,
    this.ledger = const [],
    this.unpaidOrders = const [],
    this.fetchedAt,
    this.isOffline = false,
    this.lastError,
  });

  int get remainingCreditCentimes =>
      math.max(0, creditLimitCentimes - currentDebtCentimes);

  double get creditUsage =>
      creditLimitCentimes <= 0
          ? 0
          : (currentDebtCentimes / creditLimitCentimes).clamp(0.0, 1.0).toDouble();

  WalletSnapshot copyWith({
    String? customerId,
    String? customerName,
    int? creditLimitCentimes,
    int? currentDebtCentimes,
    List<CustomerLedgerEntryEntity>? ledger,
    List<CustomerUnpaidOrderEntity>? unpaidOrders,
    DateTime? fetchedAt,
    bool? isOffline,
    String? lastError,
  }) =>
      WalletSnapshot(
        customerId: customerId ?? this.customerId,
        customerName: customerName ?? this.customerName,
        creditLimitCentimes:
            creditLimitCentimes ?? this.creditLimitCentimes,
        currentDebtCentimes: currentDebtCentimes ?? this.currentDebtCentimes,
        ledger: ledger ?? this.ledger,
        unpaidOrders: unpaidOrders ?? this.unpaidOrders,
        fetchedAt: fetchedAt ?? this.fetchedAt,
        isOffline: isOffline ?? this.isOffline,
        lastError: lastError ?? this.lastError,
      );
}

class CheckoutOutcome {
  final String orderId;
  final bool queued;

  const CheckoutOutcome({required this.orderId, required this.queued});
}

/// One poll of the live order / driver state.
class LiveOrderUpdate {
  final String? orderId;
  final bool found;
  final bool isOffline;
  final OrderStatus? status;
  final int? orderNumber;
  final String? driverId;
  final String? driverName;
  final String? driverPhone;
  final double? driverLat;
  final double? driverLng;
  final DateTime? driverUpdatedAt;
  final double? destinationLat;
  final double? destinationLng;
  final DateTime? confirmedAt;
  final DateTime? deliveredAt;
  final DateTime? settledAt;
  final String? error;

  const LiveOrderUpdate({
    this.orderId,
    this.found = false,
    this.isOffline = false,
    this.status,
    this.orderNumber,
    this.driverId,
    this.driverName,
    this.driverPhone,
    this.driverLat,
    this.driverLng,
    this.driverUpdatedAt,
    this.destinationLat,
    this.destinationLng,
    this.confirmedAt,
    this.deliveredAt,
    this.settledAt,
    this.error,
  });

  bool get hasDriverLocation => driverLat != null && driverLng != null;
}

// ─────────────────────────────────────────────────────────────────────────────
// JSON helpers (catalog, orders, wallet)
// ─────────────────────────────────────────────────────────────────────────────

Map<String, dynamic> productToJson(ProductEntity p) => {
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

ProductEntity productFromJson(Map<String, dynamic> j) => ProductEntity(
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
        final pm = (p as Map).cast<String, dynamic>();
        return ProductPriceTier(
          id: pm['id'] as String? ?? '',
          tier: PriceTier.fromString(pm['tier'] as String? ?? 'retail'),
          minQty: (pm['minQty'] as num?)?.toInt() ?? 1,
          priceCentimes: (pm['priceCentimes'] as num?)?.toInt() ?? 0,
        );
      }).toList(),
    );

Map<String, dynamic> orderToJson(OrderEntity o) => {
      'id': o.id,
      'clientId': o.clientId,
      'orderNumber': o.orderNumber,
      'channel': o.channel.name,
      'customerId': o.customerId,
      'customerName': o.customerName,
      'customerPhone': o.customerPhone,
      'status': o.status.dbValue,
      'driverId': o.driverId,
      'driverName': o.driverName,
      'driverPhone': o.driverPhone,
      'totalAmountCentimes': o.totalAmountCentimes,
      'paidAmountCentimes': o.paidAmountCentimes,
      'customerSnapshot': o.customerSnapshot,
      'items': o.items
          .map((i) => {
                'id': i.id,
                'productId': i.productId,
                'productName': i.productName,
                'quantity': i.quantity,
                'unitPriceCentimes': i.unitPriceCentimes,
                'unitCostCentimes': i.unitCostCentimes,
                'unit': i.unit,
              })
          .toList(),
      'createdAt': o.createdAt.toIso8601String(),
      'confirmedAt': o.confirmedAt?.toIso8601String(),
      'deliveredAt': o.deliveredAt?.toIso8601String(),
      'settledAt': o.settledAt?.toIso8601String(),
      'notes': o.notes,
    };

OrderEntity orderFromJson(Map<String, dynamic> j) => OrderEntity(
      id: j['id'] as String,
      clientId: j['clientId'] as String?,
      orderNumber: (j['orderNumber'] as num?)?.toInt(),
      channel: (j['channel'] as String?) == 'store'
          ? OrderChannel.store
          : OrderChannel.online,
      customerId: j['customerId'] as String?,
      customerName: j['customerName'] as String?,
      customerPhone: j['customerPhone'] as String?,
      status: OrderStatus.fromString(j['status'] as String? ?? 'submitted'),
      driverId: j['driverId'] as String?,
      driverName: j['driverName'] as String?,
      driverPhone: j['driverPhone'] as String?,
      totalAmountCentimes:
          (j['totalAmountCentimes'] as num?)?.toInt() ?? 0,
      paidAmountCentimes: (j['paidAmountCentimes'] as num?)?.toInt() ?? 0,
      customerSnapshot:
          (j['customerSnapshot'] as Map?)?.cast<String, dynamic>(),
      items: (j['items'] as List? ?? [])
          .map((i) {
            final m = (i as Map).cast<String, dynamic>();
            return OrderItemEntity(
              id: m['id'] as String? ?? '',
              productId: m['productId'] as String? ?? '',
              productName: m['productName'] as String? ?? 'منتج',
              quantity: (m['quantity'] as num?)?.toInt() ?? 1,
              unitPriceCentimes:
                  (m['unitPriceCentimes'] as num?)?.toInt() ?? 0,
              unitCostCentimes:
                  (m['unitCostCentimes'] as num?)?.toInt() ?? 0,
              unit: m['unit'] as String?,
            );
          })
          .toList(),
      createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
          DateTime.now(),
      confirmedAt: _date(j['confirmedAt']),
      deliveredAt: _date(j['deliveredAt']),
      settledAt: _date(j['settledAt']),
      notes: j['notes'] as String?,
    );

DateTime? _date(dynamic value) =>
    value is String && value.isNotEmpty ? DateTime.tryParse(value) : null;

Map<String, dynamic> ledgerToJson(CustomerLedgerEntryEntity e) => {
      'id': e.id,
      'customerId': e.customerId,
      'amountChangeCentimes': e.amountChangeCentimes,
      'refType': e.refType,
      'refId': e.refId,
      'notes': e.notes,
      'createdAt': e.createdAt.toIso8601String(),
    };

CustomerLedgerEntryEntity ledgerFromJson(Map<String, dynamic> j) =>
    CustomerLedgerEntryEntity(
      id: j['id'] as String? ?? '',
      customerId: j['customerId'] as String? ?? '',
      amountChangeCentimes:
          (j['amountChangeCentimes'] as num?)?.toInt() ?? 0,
      refType: j['refType'] as String? ?? 'payment',
      refId: j['refId'] as String? ?? '',
      notes: j['notes'] as String?,
      createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );

Map<String, dynamic> unpaidOrderToJson(CustomerUnpaidOrderEntity e) => {
      'orderId': e.orderId,
      'orderDate': e.orderDate.toIso8601String(),
      'totalAmountCentimes': e.totalAmountCentimes,
      'paidAmountCentimes': e.paidAmountCentimes,
      'remainingDebtCentimes': e.remainingDebtCentimes,
      'itemsSummary': e.itemsSummary,
    };

CustomerUnpaidOrderEntity unpaidOrderFromJson(Map<String, dynamic> j) =>
    CustomerUnpaidOrderEntity(
      orderId: j['orderId'] as String? ?? '',
      orderDate: DateTime.tryParse(j['orderDate'] as String? ?? '') ??
          DateTime.now(),
      totalAmountCentimes: (j['totalAmountCentimes'] as num?)?.toInt() ?? 0,
      paidAmountCentimes: (j['paidAmountCentimes'] as num?)?.toInt() ?? 0,
      remainingDebtCentimes:
          (j['remainingDebtCentimes'] as num?)?.toInt() ?? 0,
      itemsSummary: (j['itemsSummary'] as List? ?? []).cast<String>(),
    );
