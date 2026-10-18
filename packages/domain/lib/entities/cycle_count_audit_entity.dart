import 'package:equatable/equatable.dart';

enum AuditStatus {
  inProgress('in_progress', 'قيد الجرد الفعلي'),
  reconciled('reconciled', 'تمت التسوية والاعتماد'),
  cancelled('cancelled', 'ملغى');

  final String code;
  final String labelAr;

  const AuditStatus(this.code, this.labelAr);

  static AuditStatus fromCode(String code) {
    return AuditStatus.values.firstWhere(
      (e) => e.code == code,
      orElse: () => AuditStatus.inProgress,
    );
  }
}

class CycleCountItemEntity extends Equatable {
  final String id;
  final String productId;
  final String productName;
  final String category;
  final String unit;
  final List<String> barcodes;
  final int systemStock;
  final int physicalCount;
  final int unitCostCentimes;
  final String? notes;
  final DateTime? countedAt;

  const CycleCountItemEntity({
    required this.id,
    required this.productId,
    required this.productName,
    required this.category,
    required this.unit,
    this.barcodes = const [],
    required this.systemStock,
    required this.physicalCount,
    required this.unitCostCentimes,
    this.notes,
    this.countedAt,
  });

  /// Variance: Positive means excess physical stock (+), Negative means shortage / shrinkage (-)
  int get varianceQty => physicalCount - systemStock;

  bool get hasDiscrepancy => varianceQty != 0;

  bool get isShortage => varianceQty < 0;

  bool get isExcess => varianceQty > 0;

  /// Total cost impact of variance in centimes
  int get varianceCostCentimes => varianceQty * unitCostCentimes;

  CycleCountItemEntity copyWith({
    String? id,
    String? productId,
    String? productName,
    String? category,
    String? unit,
    List<String>? barcodes,
    int? systemStock,
    int? physicalCount,
    int? unitCostCentimes,
    String? notes,
    DateTime? countedAt,
  }) {
    return CycleCountItemEntity(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      category: category ?? this.category,
      unit: unit ?? this.unit,
      barcodes: barcodes ?? this.barcodes,
      systemStock: systemStock ?? this.systemStock,
      physicalCount: physicalCount ?? this.physicalCount,
      unitCostCentimes: unitCostCentimes ?? this.unitCostCentimes,
      notes: notes ?? this.notes,
      countedAt: countedAt ?? this.countedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        productId,
        productName,
        category,
        unit,
        barcodes,
        systemStock,
        physicalCount,
        unitCostCentimes,
        notes,
        countedAt,
      ];
}

class CycleCountAuditEntity extends Equatable {
  final String id;
  final String auditNumber;
  final AuditStatus status;
  final String locationId;
  final String locationName;
  final String countedByUserId;
  final String countedByName;
  final String? reconciledByUserId;
  final String? reconciledByName;
  final DateTime startedAt;
  final DateTime? reconciledAt;
  final String? reconciliationNotes;
  final List<CycleCountItemEntity> items;

  const CycleCountAuditEntity({
    required this.id,
    required this.auditNumber,
    required this.status,
    this.locationId = 'main_warehouse',
    this.locationName = 'المستودع الرئيسي',
    required this.countedByUserId,
    required this.countedByName,
    this.reconciledByUserId,
    this.reconciledByName,
    required this.startedAt,
    this.reconciledAt,
    this.reconciliationNotes,
    required this.items,
  });

  int get totalItemsCount => items.length;

  int get matchedItemsCount => items.where((it) => !it.hasDiscrepancy).length;

  int get discrepantItemsCount => items.where((it) => it.hasDiscrepancy).length;

  int get netVarianceQuantity =>
      items.fold<int>(0, (sum, it) => sum + it.varianceQty);

  int get netCostVarianceCentimes =>
      items.fold<int>(0, (sum, it) => sum + it.varianceCostCentimes);

  double get accuracyRate =>
      totalItemsCount == 0 ? 100.0 : (matchedItemsCount / totalItemsCount) * 100;

  CycleCountAuditEntity copyWith({
    String? id,
    String? auditNumber,
    AuditStatus? status,
    String? locationId,
    String? locationName,
    String? countedByUserId,
    String? countedByName,
    String? reconciledByUserId,
    String? reconciledByName,
    DateTime? startedAt,
    DateTime? reconciledAt,
    String? reconciliationNotes,
    List<CycleCountItemEntity>? items,
  }) {
    return CycleCountAuditEntity(
      id: id ?? this.id,
      auditNumber: auditNumber ?? this.auditNumber,
      status: status ?? this.status,
      locationId: locationId ?? this.locationId,
      locationName: locationName ?? this.locationName,
      countedByUserId: countedByUserId ?? this.countedByUserId,
      countedByName: countedByName ?? this.countedByName,
      reconciledByUserId: reconciledByUserId ?? this.reconciledByUserId,
      reconciledByName: reconciledByName ?? this.reconciledByName,
      startedAt: startedAt ?? this.startedAt,
      reconciledAt: reconciledAt ?? this.reconciledAt,
      reconciliationNotes: reconciliationNotes ?? this.reconciliationNotes,
      items: items ?? this.items,
    );
  }

  @override
  List<Object?> get props => [
        id,
        auditNumber,
        status,
        locationId,
        locationName,
        countedByUserId,
        countedByName,
        reconciledByUserId,
        reconciledByName,
        startedAt,
        reconciledAt,
        reconciliationNotes,
        items,
      ];
}
