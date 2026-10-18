import 'package:equatable/equatable.dart';

enum TransferStatus {
  pending('pending', 'قيد الانتظار والموافقة'),
  inTransit('in_transit', 'في الطريق / قيد النقل'),
  completed('completed', 'مكتمل ومستلم'),
  cancelled('cancelled', 'ملغى');

  final String code;
  final String labelAr;

  const TransferStatus(this.code, this.labelAr);

  static TransferStatus fromCode(String code) {
    return TransferStatus.values.firstWhere(
      (e) => e.code == code,
      orElse: () => TransferStatus.pending,
    );
  }
}

class InventoryLocationEntity extends Equatable {
  final String id;
  final String nameAr;
  final String code;
  final bool isDefault;

  const InventoryLocationEntity({
    required this.id,
    required this.nameAr,
    required this.code,
    this.isDefault = false,
  });

  static const mainWarehouse = InventoryLocationEntity(
    id: 'loc_main',
    nameAr: 'المستودع المركزي',
    code: 'WH-MAIN',
    isDefault: true,
  );

  static const backroom = InventoryLocationEntity(
    id: 'loc_backroom',
    nameAr: 'المخزن الداخلي الاحتياطي',
    code: 'WH-BACK',
  );

  static const retailFloor = InventoryLocationEntity(
    id: 'loc_floor',
    nameAr: 'صالة العرض والرفوف',
    code: 'RETAIL-FLOOR',
  );

  static const defaultLocations = [mainWarehouse, backroom, retailFloor];

  @override
  List<Object?> get props => [id, nameAr, code, isDefault];
}

class StockTransferItemEntity extends Equatable {
  final String id;
  final String productId;
  final String productName;
  final String unit;
  final int quantity;
  final int unitCostCentimes;

  const StockTransferItemEntity({
    required this.id,
    required this.productId,
    required this.productName,
    required this.unit,
    required this.quantity,
    required this.unitCostCentimes,
  });

  int get totalCostCentimes => quantity * unitCostCentimes;

  @override
  List<Object?> get props => [
        id,
        productId,
        productName,
        unit,
        quantity,
        unitCostCentimes,
      ];
}

class StockTransferEntity extends Equatable {
  final String id;
  final String transferNumber;
  final String sourceLocationId;
  final String sourceLocationName;
  final String targetLocationId;
  final String targetLocationName;
  final TransferStatus status;
  final String requestedByUserId;
  final String requestedByName;
  final String? approvedByUserId;
  final String? approvedByName;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? notes;
  final List<StockTransferItemEntity> items;

  const StockTransferEntity({
    required this.id,
    required this.transferNumber,
    required this.sourceLocationId,
    required this.sourceLocationName,
    required this.targetLocationId,
    required this.targetLocationName,
    required this.status,
    required this.requestedByUserId,
    required this.requestedByName,
    this.approvedByUserId,
    this.approvedByName,
    required this.createdAt,
    this.completedAt,
    this.notes,
    required this.items,
  });

  int get totalQuantity =>
      items.fold<int>(0, (sum, it) => sum + it.quantity);

  int get totalCostCentimes =>
      items.fold<int>(0, (sum, it) => sum + it.totalCostCentimes);

  bool get isCompleted => status == TransferStatus.completed;
  bool get isPending => status == TransferStatus.pending;
  bool get isInTransit => status == TransferStatus.inTransit;
  bool get isCancelled => status == TransferStatus.cancelled;

  StockTransferEntity copyWith({
    String? id,
    String? transferNumber,
    String? sourceLocationId,
    String? sourceLocationName,
    String? targetLocationId,
    String? targetLocationName,
    TransferStatus? status,
    String? requestedByUserId,
    String? requestedByName,
    String? approvedByUserId,
    String? approvedByName,
    DateTime? createdAt,
    DateTime? completedAt,
    String? notes,
    List<StockTransferItemEntity>? items,
  }) {
    return StockTransferEntity(
      id: id ?? this.id,
      transferNumber: transferNumber ?? this.transferNumber,
      sourceLocationId: sourceLocationId ?? this.sourceLocationId,
      sourceLocationName: sourceLocationName ?? this.sourceLocationName,
      targetLocationId: targetLocationId ?? this.targetLocationId,
      targetLocationName: targetLocationName ?? this.targetLocationName,
      status: status ?? this.status,
      requestedByUserId: requestedByUserId ?? this.requestedByUserId,
      requestedByName: requestedByName ?? this.requestedByName,
      approvedByUserId: approvedByUserId ?? this.approvedByUserId,
      approvedByName: approvedByName ?? this.approvedByName,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
      notes: notes ?? this.notes,
      items: items ?? this.items,
    );
  }

  @override
  List<Object?> get props => [
        id,
        transferNumber,
        sourceLocationId,
        sourceLocationName,
        targetLocationId,
        targetLocationName,
        status,
        requestedByUserId,
        requestedByName,
        approvedByUserId,
        approvedByName,
        createdAt,
        completedAt,
        notes,
        items,
      ];
}
