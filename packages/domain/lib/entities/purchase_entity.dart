import 'package:equatable/equatable.dart';

enum PurchaseStatus { draft, posted, cancelled }

class PurchaseItemEntity extends Equatable {
  final String id;
  final String productId;
  final String productName;
  final int quantity;
  final int unitCostCentimes;
  final int sellingPriceCentimes;

  const PurchaseItemEntity({
    required this.id,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitCostCentimes,
    required this.sellingPriceCentimes,
  });

  int get lineCostCentimes => quantity * unitCostCentimes;
  double get grossMarginPercent => unitCostCentimes == 0
      ? 0.0
      : ((sellingPriceCentimes - unitCostCentimes) / unitCostCentimes) * 100;

  @override
  List<Object?> get props => [id, productId, productName, quantity, unitCostCentimes, sellingPriceCentimes];
}

class PurchaseEntity extends Equatable {
  final String id;
  final String supplierId;
  final String supplierName;
  final String invoiceNo;
  final DateTime invoiceDate;
  final PurchaseStatus status;
  final int totalAmountCentimes;
  final List<PurchaseItemEntity> items;
  final DateTime? postedAt;

  const PurchaseEntity({
    required this.id,
    required this.supplierId,
    required this.supplierName,
    required this.invoiceNo,
    required this.invoiceDate,
    required this.status,
    required this.totalAmountCentimes,
    required this.items,
    this.postedAt,
  });

  @override
  List<Object?> get props => [
        id,
        supplierId,
        supplierName,
        invoiceNo,
        invoiceDate,
        status,
        totalAmountCentimes,
        items,
        postedAt,
      ];
}
