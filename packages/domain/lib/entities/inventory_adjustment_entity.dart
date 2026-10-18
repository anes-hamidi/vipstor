import 'package:equatable/equatable.dart';

/// Mandatory reason tags for all stock adjustments and shrinkage tracking.
enum StockAdjustmentReason {
  damaged('damaged', 'بضاعة متضررة / تالفة'),
  expired('expired', 'منتهي الصلاحية'),
  auditCorrection('audit_correction', 'تسوية جرد دوري'),
  internalConsumption('internal_consumption', 'استهلاك داخلي للمؤسسة'),
  returnToVendor('return_to_vendor', 'إرجاع بضاعة للمورد'),
  manualRestock('manual_restock', 'إضافة مخزون يدوية'),
  shrinkage('shrinkage', 'عجز أو فقدان غير مبرر'),
  other('other', 'أسباب تشغيلية أخرى');

  final String code;
  final String labelAr;

  const StockAdjustmentReason(this.code, this.labelAr);

  static StockAdjustmentReason fromCode(String code) {
    return StockAdjustmentReason.values.firstWhere(
      (e) => e.code == code,
      orElse: () => StockAdjustmentReason.other,
    );
  }
}

enum AdjustmentDirection {
  increase, // Stock In (+)
  decrease; // Stock Out (-)

  String get labelAr => this == increase ? 'إضافة (+)' : 'خصم (-)';
}

class StockAdjustmentItemEntity extends Equatable {
  final String id;
  final String productId;
  final String productName;
  final String unit;
  final int oldStock;
  final int newStock;
  final int qtyChange; // Positive or negative
  final int unitCostCentimes;
  final String? batchNumber;
  final DateTime? expiryDate;
  final String? itemNotes;

  const StockAdjustmentItemEntity({
    required this.id,
    required this.productId,
    required this.productName,
    required this.unit,
    required this.oldStock,
    required this.newStock,
    required this.qtyChange,
    required this.unitCostCentimes,
    this.batchNumber,
    this.expiryDate,
    this.itemNotes,
  });

  int get totalCostImpactCentimes => qtyChange.abs() * unitCostCentimes;

  @override
  List<Object?> get props => [
        id,
        productId,
        productName,
        unit,
        oldStock,
        newStock,
        qtyChange,
        unitCostCentimes,
        batchNumber,
        expiryDate,
        itemNotes,
      ];
}

class StockAdjustmentEntity extends Equatable {
  final String id;
  final String referenceNumber;
  final StockAdjustmentReason reason;
  final String? notes;
  final String locationId;
  final String locationName;
  final String adjustedByUserId;
  final String adjustedByName;
  final DateTime createdAt;
  final List<StockAdjustmentItemEntity> items;

  const StockAdjustmentEntity({
    required this.id,
    required this.referenceNumber,
    required this.reason,
    this.notes,
    this.locationId = 'main_warehouse',
    this.locationName = 'المستودع الرئيسي',
    required this.adjustedByUserId,
    required this.adjustedByName,
    required this.createdAt,
    required this.items,
  });

  int get totalCostImpactCentimes =>
      items.fold<int>(0, (sum, it) => sum + it.totalCostImpactCentimes);

  int get totalItemsCount => items.length;

  int get totalQuantityChanged =>
      items.fold<int>(0, (sum, it) => sum + it.qtyChange.abs());

  @override
  List<Object?> get props => [
        id,
        referenceNumber,
        reason,
        notes,
        locationId,
        locationName,
        adjustedByUserId,
        adjustedByName,
        createdAt,
        items,
      ];
}
