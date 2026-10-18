import 'package:equatable/equatable.dart';

enum PurchaseOrderStatus {
  draft('draft', 'مسودة طلب'),
  ordered('ordered', 'تم الإرسال للمورد'),
  partiallyReceived('partially_received', 'مستلم جزئياً (GRN)'),
  fullyReceived('fully_received', 'مستلم بالكامل'),
  cancelled('cancelled', 'طلب ملغى');

  final String code;
  final String labelAr;

  const PurchaseOrderStatus(this.code, this.labelAr);

  static PurchaseOrderStatus fromCode(String code) {
    return PurchaseOrderStatus.values.firstWhere(
      (e) => e.code == code,
      orElse: () => PurchaseOrderStatus.draft,
    );
  }
}

class PurchaseOrderItemEntity extends Equatable {
  final String id;
  final String productId;
  final String productName;
  final String unit;
  final int orderedQty;
  final int receivedQty;
  final int unitCostCentimes;
  final int sellingPriceCentimes;
  final String? batchNumber;
  final DateTime? manufacturingDate;
  final DateTime? expiryDate;
  final String? notes;

  const PurchaseOrderItemEntity({
    required this.id,
    required this.productId,
    required this.productName,
    required this.unit,
    required this.orderedQty,
    this.receivedQty = 0,
    required this.unitCostCentimes,
    required this.sellingPriceCentimes,
    this.batchNumber,
    this.manufacturingDate,
    this.expiryDate,
    this.notes,
  });

  int get remainingQty => (orderedQty - receivedQty).clamp(0, orderedQty);

  bool get isFullyReceived => receivedQty >= orderedQty;

  int get lineOrderedCostCentimes => orderedQty * unitCostCentimes;

  int get lineReceivedCostCentimes => receivedQty * unitCostCentimes;

  PurchaseOrderItemEntity copyWith({
    String? id,
    String? productId,
    String? productName,
    String? unit,
    int? orderedQty,
    int? receivedQty,
    int? unitCostCentimes,
    int? sellingPriceCentimes,
    String? batchNumber,
    DateTime? manufacturingDate,
    DateTime? expiryDate,
    String? notes,
  }) {
    return PurchaseOrderItemEntity(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      unit: unit ?? this.unit,
      orderedQty: orderedQty ?? this.orderedQty,
      receivedQty: receivedQty ?? this.receivedQty,
      unitCostCentimes: unitCostCentimes ?? this.unitCostCentimes,
      sellingPriceCentimes: sellingPriceCentimes ?? this.sellingPriceCentimes,
      batchNumber: batchNumber ?? this.batchNumber,
      manufacturingDate: manufacturingDate ?? this.manufacturingDate,
      expiryDate: expiryDate ?? this.expiryDate,
      notes: notes ?? this.notes,
    );
  }

  @override
  List<Object?> get props => [
        id,
        productId,
        productName,
        unit,
        orderedQty,
        receivedQty,
        unitCostCentimes,
        sellingPriceCentimes,
        batchNumber,
        manufacturingDate,
        expiryDate,
        notes,
      ];
}

class PurchaseOrderEntity extends Equatable {
  final String id;
  final String poNumber;
  final String supplierId;
  final String supplierName;
  final String? supplierPhone;
  final PurchaseOrderStatus status;
  final DateTime orderDate;
  final DateTime? expectedDeliveryDate;
  final DateTime? completedDate;
  final String createdByUserId;
  final String createdByName;
  final String? notes;
  final List<PurchaseOrderItemEntity> items;

  const PurchaseOrderEntity({
    required this.id,
    required this.poNumber,
    required this.supplierId,
    required this.supplierName,
    this.supplierPhone,
    required this.status,
    required this.orderDate,
    this.expectedDeliveryDate,
    this.completedDate,
    required this.createdByUserId,
    required this.createdByName,
    this.notes,
    required this.items,
  });

  int get totalOrderedAmountCentimes =>
      items.fold<int>(0, (sum, it) => sum + it.lineOrderedCostCentimes);

  int get totalReceivedAmountCentimes =>
      items.fold<int>(0, (sum, it) => sum + it.lineReceivedCostCentimes);

  int get totalOrderedQuantity =>
      items.fold<int>(0, (sum, it) => sum + it.orderedQty);

  int get totalReceivedQuantity =>
      items.fold<int>(0, (sum, it) => sum + it.receivedQty);

  bool get isDraft => status == PurchaseOrderStatus.draft;
  bool get isOrdered => status == PurchaseOrderStatus.ordered;
  bool get isPartiallyReceived => status == PurchaseOrderStatus.partiallyReceived;
  bool get isFullyReceived => status == PurchaseOrderStatus.fullyReceived;
  bool get isCancelled => status == PurchaseOrderStatus.cancelled;

  PurchaseOrderEntity copyWith({
    String? id,
    String? poNumber,
    String? supplierId,
    String? supplierName,
    String? supplierPhone,
    PurchaseOrderStatus? status,
    DateTime? orderDate,
    DateTime? expectedDeliveryDate,
    DateTime? completedDate,
    String? createdByUserId,
    String? createdByName,
    String? notes,
    List<PurchaseOrderItemEntity>? items,
  }) {
    return PurchaseOrderEntity(
      id: id ?? this.id,
      poNumber: poNumber ?? this.poNumber,
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      supplierPhone: supplierPhone ?? this.supplierPhone,
      status: status ?? this.status,
      orderDate: orderDate ?? this.orderDate,
      expectedDeliveryDate: expectedDeliveryDate ?? this.expectedDeliveryDate,
      completedDate: completedDate ?? this.completedDate,
      createdByUserId: createdByUserId ?? this.createdByUserId,
      createdByName: createdByName ?? this.createdByName,
      notes: notes ?? this.notes,
      items: items ?? this.items,
    );
  }

  @override
  List<Object?> get props => [
        id,
        poNumber,
        supplierId,
        supplierName,
        supplierPhone,
        status,
        orderDate,
        expectedDeliveryDate,
        completedDate,
        createdByUserId,
        createdByName,
        notes,
        items,
      ];
}
