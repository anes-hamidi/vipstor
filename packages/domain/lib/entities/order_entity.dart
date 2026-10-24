import 'package:equatable/equatable.dart';

import 'product_unit.dart';

enum OrderChannel { store, online }

enum OrderStatus {
  submitted,
  confirmed,
  preparing,
  ready,
  assigned,
  accepted,
  refused,
  outForDelivery,
  delivered,
  settled,
  cancelled,
  requiresManagerReview;

  static OrderStatus fromString(String val) {
    switch (val) {
      case 'submitted': return OrderStatus.submitted;
      case 'confirmed': return OrderStatus.confirmed;
      case 'preparing': return OrderStatus.preparing;
      case 'ready': return OrderStatus.ready;
      case 'assigned': return OrderStatus.assigned;
      case 'accepted': return OrderStatus.accepted;
      case 'refused': return OrderStatus.refused;
      case 'out_for_delivery': return OrderStatus.outForDelivery;
      case 'delivered': return OrderStatus.delivered;
      case 'settled': return OrderStatus.settled;
      case 'cancelled': return OrderStatus.cancelled;
      case 'requires_manager_review': return OrderStatus.requiresManagerReview;
      default: return OrderStatus.submitted;
    }
  }

  String get dbValue {
    switch (this) {
      case OrderStatus.outForDelivery: return 'out_for_delivery';
      case OrderStatus.requiresManagerReview: return 'requires_manager_review';
      default: return name;
    }
  }
}

class OrderItemEntity extends Equatable {
  final String id;
  final String productId;
  final String productName;
  final int quantity;
  final int unitPriceCentimes;
  final int unitCostCentimes;
  final String? unit;

  const OrderItemEntity({
    required this.id,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPriceCentimes,
    required this.unitCostCentimes,
    this.unit,
  });

  int get lineTotalCentimes => quantity * unitPriceCentimes;

  String get formattedQuantityWithUnit {
    if (unit == null || unit!.trim().isEmpty) return '$quantity';
    return ProductUnit.fromString(unit).formatQuantityBilingual(quantity);
  }

  @override
  List<Object?> get props => [
        id,
        productId,
        productName,
        quantity,
        unitPriceCentimes,
        unitCostCentimes,
        unit,
      ];
}

class OrderEntity extends Equatable {
  final String id;

  /// Client-generated idempotency key. Lets the customer app reconcile an
  /// offline-queued order with the row created on the server once it syncs.
  final String? clientId;
  final int? orderNumber;
  final OrderChannel channel;
  final String? customerId;
  final String? customerName;
  final String? customerPhone;
  final OrderStatus status;
  final String? driverId;
  final String? driverName;
  final String? driverPhone;
  final int totalAmountCentimes;
  final int paidAmountCentimes;
  final Map<String, dynamic>? customerSnapshot;
  final List<OrderItemEntity> items;
  final DateTime createdAt;
  final String? preparedBy;
  final DateTime? preparedAt;
  final String? signatureBase64;
  final String? photoBase64;
  final double? deliveryLat;
  final double? deliveryLng;
  final DateTime? confirmedAt;
  final DateTime? deliveredAt;
  final DateTime? settledAt;
  final String? notes;

  const OrderEntity({
    required this.id,
    this.clientId,
    this.orderNumber,
    required this.channel,
    this.customerId,
    this.customerName,
    this.customerPhone,
    required this.status,
    this.driverId,
    this.driverName,
    this.driverPhone,
    required this.totalAmountCentimes,
    required this.paidAmountCentimes,
    Map<String, dynamic>? customerSnapshot,
    Map<String, dynamic>? deliveryAddress,
    required this.items,
    required this.createdAt,
    this.preparedBy,
    this.preparedAt,
    this.signatureBase64,
    this.photoBase64,
    this.deliveryLat,
    this.deliveryLng,
    this.confirmedAt,
    this.deliveredAt,
    this.settledAt,
    this.notes,
  }) : customerSnapshot = customerSnapshot ?? deliveryAddress;

  Map<String, dynamic>? get deliveryAddress => customerSnapshot;

  int get dueAmountCentimes => totalAmountCentimes - paidAmountCentimes;

  /// True while the order is still being processed / delivered.
  bool get isOpen {
    switch (status) {
      case OrderStatus.submitted:
      case OrderStatus.confirmed:
      case OrderStatus.preparing:
      case OrderStatus.ready:
      case OrderStatus.assigned:
      case OrderStatus.accepted:
      case OrderStatus.outForDelivery:
      case OrderStatus.requiresManagerReview:
        return true;
      case OrderStatus.delivered:
      case OrderStatus.settled:
      case OrderStatus.cancelled:
      case OrderStatus.refused:
        return false;
    }
  }

  bool get isFinished =>
      status == OrderStatus.delivered || status == OrderStatus.settled;

  bool get isCancelled =>
      status == OrderStatus.cancelled || status == OrderStatus.refused;

  /// Progress step for the customer timeline (0..4), -1 when cancelled.
  int get timelineStep {
    switch (status) {
      case OrderStatus.submitted:
        return 0;
      case OrderStatus.confirmed:
        return 1;
      case OrderStatus.preparing:
        return 2;
      case OrderStatus.ready:
      case OrderStatus.assigned:
      case OrderStatus.accepted:
      case OrderStatus.outForDelivery:
        return 3;
      case OrderStatus.delivered:
      case OrderStatus.settled:
        return 4;
      case OrderStatus.requiresManagerReview:
        return 1;
      case OrderStatus.cancelled:
      case OrderStatus.refused:
        return -1;
    }
  }

  OrderEntity copyWith({
    String? id,
    String? clientId,
    int? orderNumber,
    OrderChannel? channel,
    String? customerId,
    String? customerName,
    String? customerPhone,
    OrderStatus? status,
    String? driverId,
    String? driverName,
    String? driverPhone,
    int? totalAmountCentimes,
    int? paidAmountCentimes,
    Map<String, dynamic>? customerSnapshot,
    List<OrderItemEntity>? items,
    DateTime? createdAt,
    String? preparedBy,
    DateTime? preparedAt,
    String? signatureBase64,
    String? photoBase64,
    double? deliveryLat,
    double? deliveryLng,
    DateTime? confirmedAt,
    DateTime? deliveredAt,
    DateTime? settledAt,
    String? notes,
  }) {
    return OrderEntity(
      id: id ?? this.id,
      clientId: clientId ?? this.clientId,
      orderNumber: orderNumber ?? this.orderNumber,
      channel: channel ?? this.channel,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      status: status ?? this.status,
      driverId: driverId ?? this.driverId,
      driverName: driverName ?? this.driverName,
      driverPhone: driverPhone ?? this.driverPhone,
      totalAmountCentimes: totalAmountCentimes ?? this.totalAmountCentimes,
      paidAmountCentimes: paidAmountCentimes ?? this.paidAmountCentimes,
      customerSnapshot: customerSnapshot ?? this.customerSnapshot,
      items: items ?? this.items,
      createdAt: createdAt ?? this.createdAt,
      preparedBy: preparedBy ?? this.preparedBy,
      preparedAt: preparedAt ?? this.preparedAt,
      signatureBase64: signatureBase64 ?? this.signatureBase64,
      photoBase64: photoBase64 ?? this.photoBase64,
      deliveryLat: deliveryLat ?? this.deliveryLat,
      deliveryLng: deliveryLng ?? this.deliveryLng,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      settledAt: settledAt ?? this.settledAt,
      notes: notes ?? this.notes,
    );
  }

  @override
  List<Object?> get props => [
        id,
        clientId,
        orderNumber,
        channel,
        customerId,
        customerName,
        customerPhone,
        status,
        driverId,
        driverName,
        driverPhone,
        totalAmountCentimes,
        paidAmountCentimes,
        customerSnapshot,
        items,
        createdAt,
        preparedBy,
        preparedAt,
        signatureBase64,
        photoBase64,
        deliveryLat,
        deliveryLng,
        confirmedAt,
        deliveredAt,
        settledAt,
        notes,
      ];
}
