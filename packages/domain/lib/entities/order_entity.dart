import 'package:equatable/equatable.dart';

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
  cancelled;

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
      default: return OrderStatus.submitted;
    }
  }

  String get dbValue {
    switch (this) {
      case OrderStatus.outForDelivery: return 'out_for_delivery';
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

  const OrderItemEntity({
    required this.id,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPriceCentimes,
    required this.unitCostCentimes,
  });

  int get lineTotalCentimes => quantity * unitPriceCentimes;

  @override
  List<Object?> get props => [id, productId, productName, quantity, unitPriceCentimes, unitCostCentimes];
}

class OrderEntity extends Equatable {
  final String id;
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
  final DateTime? deliveredAt;
  final String? notes;

  const OrderEntity({
    required this.id,
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
    this.deliveredAt,
    this.notes,
  }) : customerSnapshot = customerSnapshot ?? deliveryAddress;

  Map<String, dynamic>? get deliveryAddress => customerSnapshot;

  int get dueAmountCentimes => totalAmountCentimes - paidAmountCentimes;

  OrderEntity copyWith({
    String? id,
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
    DateTime? deliveredAt,
    String? notes,
  }) {
    return OrderEntity(
      id: id ?? this.id,
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
      deliveredAt: deliveredAt ?? this.deliveredAt,
      notes: notes ?? this.notes,
    );
  }

  @override
  List<Object?> get props => [
        id,
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
        deliveredAt,
        notes,
      ];
}
