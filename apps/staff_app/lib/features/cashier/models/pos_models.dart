import 'package:equatable/equatable.dart';
import 'package:domain/domain.dart';

enum PosItemUnit {
  box('علبة (Boîte)', 1, 'علبة', 'Boîte', 'Bte'),
  carton('كرتون (Carton)', 12, 'كرتون', 'Carton', 'Ctn'),
  pack('طرد (Pack)', 6, 'طرد', 'Pack', 'Pk'),
  kg('كغ (Kg)', 1, 'كغ', 'Kg', 'Kg'),
  g('غرام (g)', 1, 'غ', 'g', 'g'),
  piece('قطعة (Pièce)', 1, 'قطعة', 'Pièce', 'Pc'),
  l('لتر (L)', 1, 'لتر', 'L', 'L');

  final String label;
  final int defaultFactor;
  final String arabicName;
  final String frenchName;
  final String shortCode;

  const PosItemUnit(
    this.label,
    this.defaultFactor,
    this.arabicName,
    this.frenchName,
    this.shortCode,
  );

  /// Formatted string for thermal/paper invoices and receipts, e.g. "علبة (Boîte)" or "كغ (Kg)"
  String get invoiceLabel => '$arabicName ($frenchName)';

  /// Compact unit string for narrow receipts (e.g. "كرتون", "علبة", "كغ")
  String get receiptLabel => arabicName;

  static PosItemUnit fromString(String? raw) {
    if (raw == null || raw.trim().isEmpty) return PosItemUnit.piece;
    final s = raw.trim().toLowerCase();
    if (s.contains('boit') || s.contains('box') || s.contains('علب') || s.contains('صندوق')) {
      return PosItemUnit.box;
    }
    if (s.contains('carton') || s.contains('كرتون')) {
      return PosItemUnit.carton;
    }
    if (s.contains('pack') || s.contains('طرد') || s.contains('حزم')) {
      return PosItemUnit.pack;
    }
    if (s == 'kg' || s.contains('كغ') || s.contains('كيلو')) {
      return PosItemUnit.kg;
    }
    if (s == 'g' || s.contains('غرام') || s == 'غ' || s.contains('gram')) {
      return PosItemUnit.g;
    }
    if (s == 'l' || s.contains('لتر') || s.contains('litre')) {
      return PosItemUnit.l;
    }
    return PosItemUnit.piece;
  }
}

class PosCartItem extends Equatable {
  final String id;
  final String productId;
  final String nameAr;
  final String nameFr;
  final String barcode;
  final PosItemUnit unit;
  final int unitsPerPack;
  final int quantity; // in current selected unit
  final int baseUnitPriceCentimes;
  final int unitCostCentimes;
  final int availableStock;
  final double discountPercent; // e.g. 5.0 for 5%
  final int manualDiscountCentimes; // fixed discount in centimes
  final bool isCustomItem;
  /// The active pricing tier for this line. Null for custom items.
  final PriceTier? activeTier;
  /// All price tiers from the source product, so the cashier can switch tier
  /// without going back to the product list.
  final List<ProductPriceTier> availableTiers;

  const PosCartItem({
    required this.id,
    required this.productId,
    required this.nameAr,
    required this.nameFr,
    required this.barcode,
    this.unit = PosItemUnit.piece,
    this.unitsPerPack = 1,
    required this.quantity,
    required this.baseUnitPriceCentimes,
    required this.unitCostCentimes,
    required this.availableStock,
    this.discountPercent = 0.0,
    this.manualDiscountCentimes = 0,
    this.isCustomItem = false,
    this.activeTier,
    this.availableTiers = const [],
  });

  factory PosCartItem.fromProduct(ProductEntity product, {int qty = 1, PriceTier tier = PriceTier.wholesale}) {
    final price = product.getPriceForQuantity(tier, qty);
    final parsedUnit = PosItemUnit.fromString(product.unit);
    return PosCartItem(
      id: product.id,
      productId: product.id,
      nameAr: product.nameAr,
      nameFr: product.nameFr,
      barcode: product.barcodes.isNotEmpty ? product.barcodes.first : '',
      unit: parsedUnit,
      unitsPerPack: product.packSize > 0 ? product.packSize : (parsedUnit.defaultFactor > 1 ? parsedUnit.defaultFactor : 1),
      quantity: qty,
      baseUnitPriceCentimes: price,
      unitCostCentimes: product.lastUnitCostCentimes,
      availableStock: product.availableQty,
      activeTier: tier,
      availableTiers: product.prices,
    );
  }

  factory PosCartItem.custom({
    required String name,
    required int priceCentimes,
    int qty = 1,
    PosItemUnit unit = PosItemUnit.piece,
  }) {
    final uid = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    return PosCartItem(
      id: uid,
      productId: uid,
      nameAr: name,
      nameFr: name,
      barcode: 'MANUAL',
      unit: unit,
      unitsPerPack: 1,
      quantity: qty,
      baseUnitPriceCentimes: priceCentimes,
      unitCostCentimes: 0,
      availableStock: 99999,
      isCustomItem: true,
    );
  }

  int get unitMultiplier {
    switch (unit) {
      case PosItemUnit.piece:
      case PosItemUnit.kg:
      case PosItemUnit.g:
      case PosItemUnit.l:
        return 1;
      case PosItemUnit.pack:
      case PosItemUnit.carton:
      case PosItemUnit.box:
        return unitsPerPack > 1 ? unitsPerPack : unit.defaultFactor;
    }
  }

  int get totalPieces => quantity * unitMultiplier;

  int get effectiveUnitPriceCentimes {
    final unitBase = baseUnitPriceCentimes * unitMultiplier;
    final percentDiscount = (unitBase * (discountPercent / 100)).round();
    final effective = unitBase - percentDiscount - manualDiscountCentimes;
    return effective > 0 ? effective : 0;
  }

  int get lineTotalCentimes => effectiveUnitPriceCentimes * quantity;

  PosCartItem copyWith({
    int? quantity,
    PosItemUnit? unit,
    int? unitsPerPack,
    int? baseUnitPriceCentimes,
    double? discountPercent,
    int? manualDiscountCentimes,
    PriceTier? activeTier,
    List<ProductPriceTier>? availableTiers,
  }) {
    return PosCartItem(
      id: id,
      productId: productId,
      nameAr: nameAr,
      nameFr: nameFr,
      barcode: barcode,
      unit: unit ?? this.unit,
      unitsPerPack: unitsPerPack ?? this.unitsPerPack,
      quantity: quantity ?? this.quantity,
      baseUnitPriceCentimes: baseUnitPriceCentimes ?? this.baseUnitPriceCentimes,
      unitCostCentimes: unitCostCentimes,
      availableStock: availableStock,
      discountPercent: discountPercent ?? this.discountPercent,
      manualDiscountCentimes: manualDiscountCentimes ?? this.manualDiscountCentimes,
      isCustomItem: isCustomItem,
      activeTier: activeTier ?? this.activeTier,
      availableTiers: availableTiers ?? this.availableTiers,
    );
  }

  @override
  List<Object?> get props => [
        id,
        productId,
        quantity,
        unit,
        unitsPerPack,
        baseUnitPriceCentimes,
        discountPercent,
        manualDiscountCentimes,
        activeTier,
      ];
}

class PosHeldTicket extends Equatable {
  final String id;
  final String label;
  final CustomerProfileEntity? customer;
  final List<PosCartItem> items;
  final DateTime heldAt;

  const PosHeldTicket({
    required this.id,
    required this.label,
    this.customer,
    required this.items,
    required this.heldAt,
  });

  int get totalCentimes => items.fold(0, (sum, i) => sum + i.lineTotalCentimes);

  @override
  List<Object?> get props => [id, label, customer, items, heldAt];
}

class PosShiftSession extends Equatable {
  final String id;
  final int zReportNumber;
  final String cashierId;
  final String cashierName;
  final int openingFloatCentimes;
  final int cashSalesCentimes;
  final int creditSalesCentimes;
  final int returnsCentimes;
  final int collectedDebtCashCentimes;
  final int supplierPaymentsCashCentimes;
  final int driverSettlementCashCentimes;
  final DateTime openedAt;
  final bool isOpen;

  const PosShiftSession({
    required this.id,
    required this.zReportNumber,
    required this.cashierId,
    required this.cashierName,
    required this.openingFloatCentimes,
    this.cashSalesCentimes = 0,
    this.creditSalesCentimes = 0,
    this.returnsCentimes = 0,
    this.collectedDebtCashCentimes = 0,
    this.supplierPaymentsCashCentimes = 0,
    this.driverSettlementCashCentimes = 0,
    required this.openedAt,
    this.isOpen = true,
  });

  int get expectedCashInDrawerCentimes =>
      openingFloatCentimes +
      cashSalesCentimes +
      collectedDebtCashCentimes +
      driverSettlementCashCentimes -
      returnsCentimes -
      supplierPaymentsCashCentimes;

  PosShiftSession copyWith({
    int? cashSalesCentimes,
    int? creditSalesCentimes,
    int? returnsCentimes,
    int? collectedDebtCashCentimes,
    int? supplierPaymentsCashCentimes,
    int? driverSettlementCashCentimes,
    bool? isOpen,
  }) {
    return PosShiftSession(
      id: id,
      zReportNumber: zReportNumber,
      cashierId: cashierId,
      cashierName: cashierName,
      openingFloatCentimes: openingFloatCentimes,
      cashSalesCentimes: cashSalesCentimes ?? this.cashSalesCentimes,
      creditSalesCentimes: creditSalesCentimes ?? this.creditSalesCentimes,
      returnsCentimes: returnsCentimes ?? this.returnsCentimes,
      collectedDebtCashCentimes: collectedDebtCashCentimes ?? this.collectedDebtCashCentimes,
      supplierPaymentsCashCentimes: supplierPaymentsCashCentimes ?? this.supplierPaymentsCashCentimes,
      driverSettlementCashCentimes: driverSettlementCashCentimes ?? this.driverSettlementCashCentimes,
      openedAt: openedAt,
      isOpen: isOpen ?? this.isOpen,
    );
  }

  @override
  List<Object?> get props => [
        id,
        zReportNumber,
        cashierId,
        openingFloatCentimes,
        cashSalesCentimes,
        creditSalesCentimes,
        returnsCentimes,
        collectedDebtCashCentimes,
        supplierPaymentsCashCentimes,
        driverSettlementCashCentimes,
        isOpen,
      ];
}

class ZReportSummary extends Equatable {
  final int zNumber;
  final String cashierName;
  final DateTime openedAt;
  final DateTime closedAt;
  final int openingFloatCentimes;
  final int cashSalesCentimes;
  final int creditSalesCentimes;
  final int collectedDebtCashCentimes;
  final int supplierPaymentsCashCentimes;
  final int driverSettlementCashCentimes;
  final int totalSalesCentimes;
  final int returnsCentimes;
  final int expectedCashCentimes;
  final int countedCashCentimes;
  final int varianceCentimes; // Counted - Expected
  final Map<int, int> denominations;

  const ZReportSummary({
    required this.zNumber,
    required this.cashierName,
    required this.openedAt,
    required this.closedAt,
    required this.openingFloatCentimes,
    required this.cashSalesCentimes,
    required this.creditSalesCentimes,
    this.collectedDebtCashCentimes = 0,
    this.supplierPaymentsCashCentimes = 0,
    this.driverSettlementCashCentimes = 0,
    required this.totalSalesCentimes,
    required this.returnsCentimes,
    required this.expectedCashCentimes,
    required this.countedCashCentimes,
    required this.varianceCentimes,
    required this.denominations,
  });

  @override
  List<Object?> get props => [
        zNumber,
        cashierName,
        openedAt,
        closedAt,
        totalSalesCentimes,
        collectedDebtCashCentimes,
        supplierPaymentsCashCentimes,
        driverSettlementCashCentimes,
        varianceCentimes,
      ];
}

