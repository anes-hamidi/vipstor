import 'package:equatable/equatable.dart';

enum PurchaseStatus { draft, posted, cancelled }

class PurchaseItemEntity extends Equatable {
  final String id;
  final String productId;
  final String productName;
  final int quantity;
  final int unitCostCentimes;
  final int sellingPriceCentimes;
  final String? unit;

  const PurchaseItemEntity({
    required this.id,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitCostCentimes,
    required this.sellingPriceCentimes,
    this.unit,
  });

  int get lineCostCentimes => quantity * unitCostCentimes;
  int get linePotentialRevenueCentimes => quantity * sellingPriceCentimes;
  int get lineEstimatedProfitCentimes => linePotentialRevenueCentimes - lineCostCentimes;

  double get grossMarginPercent => unitCostCentimes == 0
      ? 0.0
      : ((sellingPriceCentimes - unitCostCentimes) / unitCostCentimes) * 100;

  @override
  List<Object?> get props => [
        id,
        productId,
        productName,
        quantity,
        unitCostCentimes,
        sellingPriceCentimes,
        unit,
      ];
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
  final String? createdById;
  final String? createdByName;
  final String? createdByPhone;
  final String? createdByRole;
  final DateTime? createdAt;

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
    this.createdById,
    this.createdByName,
    this.createdByPhone,
    this.createdByRole,
    this.createdAt,
  });

  int get totalQuantity => items.fold<int>(0, (sum, it) => sum + it.quantity);

  int get totalPotentialRevenueCentimes =>
      items.fold<int>(0, (sum, it) => sum + it.linePotentialRevenueCentimes);

  int get estimatedGrossProfitCentimes =>
      totalPotentialRevenueCentimes - totalAmountCentimes;

  double get overallGrossMarginPercent => totalAmountCentimes == 0
      ? 0.0
      : ((totalPotentialRevenueCentimes - totalAmountCentimes) /
              totalAmountCentimes) *
          100;

  bool get isPosted => status == PurchaseStatus.posted;
  bool get isDraft => status == PurchaseStatus.draft;
  bool get isCancelled => status == PurchaseStatus.cancelled;

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
        createdById,
        createdByName,
        createdByPhone,
        createdByRole,
        createdAt,
      ];
}

class SupplierProfileEntity extends Equatable {
  final String id;
  final String name;
  final String phone;
  final String? companyRegister;
  final String? notes;
  final int currentBalanceCentimes; // Total unpaid purchases / credit
  final int totalPurchasesCentimes;

  const SupplierProfileEntity({
    required this.id,
    required this.name,
    required this.phone,
    this.companyRegister,
    this.notes,
    this.currentBalanceCentimes = 0,
    this.totalPurchasesCentimes = 0,
  });

  bool get hasOutstandingCredit => currentBalanceCentimes > 0;

  @override
  List<Object?> get props => [
        id,
        name,
        phone,
        companyRegister,
        notes,
        currentBalanceCentimes,
        totalPurchasesCentimes,
      ];
}

class SupplierPaymentResult extends Equatable {
  final String paymentId;
  final String supplierId;
  final String supplierName;
  final int paidAmountCentimes;
  final int previousBalanceCentimes;
  final int remainingBalanceCentimes;
  final String paymentMethod; // Always 'cash'
  final String payerRole; // 'cashier' | 'moderator'
  final String payerId;
  final String payerName;
  final DateTime timestamp;
  final String? notes;

  const SupplierPaymentResult({
    required this.paymentId,
    required this.supplierId,
    required this.supplierName,
    required this.paidAmountCentimes,
    required this.previousBalanceCentimes,
    required this.remainingBalanceCentimes,
    this.paymentMethod = 'cash',
    required this.payerRole,
    required this.payerId,
    required this.payerName,
    required this.timestamp,
    this.notes,
  });

  @override
  List<Object?> get props => [
        paymentId,
        supplierId,
        supplierName,
        paidAmountCentimes,
        previousBalanceCentimes,
        remainingBalanceCentimes,
        paymentMethod,
        payerRole,
        payerId,
        payerName,
        timestamp,
        notes,
      ];
}


