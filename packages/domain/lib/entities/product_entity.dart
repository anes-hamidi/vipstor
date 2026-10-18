import 'package:equatable/equatable.dart';

enum PriceTier {
  retail,
  wholesale,
  bulk;

  static PriceTier fromString(String val) {
    return PriceTier.values.firstWhere(
      (e) => e.name == val,
      orElse: () => PriceTier.wholesale,
    );
  }
}

class ProductPriceTier extends Equatable {
  final String id;
  final PriceTier tier;
  final int minQty;
  final int priceCentimes; // In centimes

  const ProductPriceTier({
    required this.id,
    required this.tier,
    required this.minQty,
    required this.priceCentimes,
  });

  @override
  List<Object?> get props => [id, tier, minQty, priceCentimes];
}

enum StockHealthStatus {
  normal,
  lowStock,
  critical,
  outOfStock,
  overstocked;

  String get labelAr {
    switch (this) {
      case StockHealthStatus.normal:
        return 'طبيعي ومثالي';
      case StockHealthStatus.lowStock:
        return 'منخفض (وصل نقطة الطلب)';
      case StockHealthStatus.critical:
        return 'حرج (مستوى الأمان)';
      case StockHealthStatus.outOfStock:
        return 'نفد المخزون';
      case StockHealthStatus.overstocked:
        return 'فائض عن السعة';
    }
  }
}

class ProductEntity extends Equatable {
  final String id;
  final String nameAr;
  final String nameFr;
  final String category;
  final String unit;
  final int packSize;
  final String? photoUrl;
  final int lastUnitCostCentimes;
  final int weightedAverageCostCentimes;
  final int onHandQty;
  final int availableQty;
  final int safetyStockLevel;
  final int reorderPoint;
  final int maxCapacity;
  final Map<String, int> locationQuantities;
  final bool active;
  final List<String> barcodes;
  final List<ProductPriceTier> prices;

  const ProductEntity({
    required this.id,
    required this.nameAr,
    required this.nameFr,
    required this.category,
    required this.unit,
    required this.packSize,
    this.photoUrl,
    int? lastUnitCostCentimes,
    int? costCentimes,
    int? weightedAverageCostCentimes,
    this.onHandQty = 0,
    this.availableQty = 0,
    this.safetyStockLevel = 5,
    this.reorderPoint = 15,
    this.maxCapacity = 100,
    this.locationQuantities = const {},
    required this.active,
    this.barcodes = const [],
    List<ProductPriceTier>? prices,
    List<ProductPriceTier>? priceTiers,
  })  : lastUnitCostCentimes = lastUnitCostCentimes ?? costCentimes ?? 0,
        weightedAverageCostCentimes = weightedAverageCostCentimes ?? lastUnitCostCentimes ?? costCentimes ?? 0,
        prices = prices ?? priceTiers ?? const [];

  int get costCentimes => lastUnitCostCentimes;
  List<ProductPriceTier> get priceTiers => prices;

  // ── Inventory Health & Replenishment Intelligence ──────────────────────────

  bool get isOutOfStock => availableQty <= 0;
  bool get isCritical => availableQty > 0 && availableQty <= safetyStockLevel;
  bool get isLowStock => availableQty > 0 && availableQty <= reorderPoint;
  bool get isOverstocked => maxCapacity > 0 && availableQty > maxCapacity;

  StockHealthStatus get healthStatus {
    if (isOutOfStock) return StockHealthStatus.outOfStock;
    if (isCritical) return StockHealthStatus.critical;
    if (isLowStock) return StockHealthStatus.lowStock;
    if (isOverstocked) return StockHealthStatus.overstocked;
    return StockHealthStatus.normal;
  }

  /// Calculates replenishment quantity needed to reach maxCapacity or healthy level
  int get suggestedReplenishmentQty {
    if (maxCapacity > availableQty) {
      return maxCapacity - availableQty;
    }
    if (isLowStock) {
      return (reorderPoint * 2 - availableQty).clamp(0, 9999);
    }
    return 0;
  }

  /// Total valuation at Weighted Average Cost
  int get inventoryValuationCentimes =>
      onHandQty * (weightedAverageCostCentimes > 0 ? weightedAverageCostCentimes : lastUnitCostCentimes);

  String localizedName(String lang) => lang == 'fr' ? nameFr : nameAr;

  int getPriceForQuantity(PriceTier tier, int quantity) {
    final matches = prices.where((p) => p.tier == tier && quantity >= p.minQty).toList();
    if (matches.isEmpty) {
      final fallback = prices.where((p) => p.tier == PriceTier.retail).toList();
      return fallback.isNotEmpty ? fallback.first.priceCentimes : lastUnitCostCentimes;
    }
    matches.sort((a, b) => b.minQty.compareTo(a.minQty));
    return matches.first.priceCentimes;
  }

  ProductEntity copyWith({
    String? id,
    String? nameAr,
    String? nameFr,
    String? category,
    String? unit,
    int? packSize,
    String? photoUrl,
    int? lastUnitCostCentimes,
    int? weightedAverageCostCentimes,
    int? onHandQty,
    int? availableQty,
    int? safetyStockLevel,
    int? reorderPoint,
    int? maxCapacity,
    Map<String, int>? locationQuantities,
    bool? active,
    List<String>? barcodes,
    List<ProductPriceTier>? prices,
  }) {
    return ProductEntity(
      id: id ?? this.id,
      nameAr: nameAr ?? this.nameAr,
      nameFr: nameFr ?? this.nameFr,
      category: category ?? this.category,
      unit: unit ?? this.unit,
      packSize: packSize ?? this.packSize,
      photoUrl: photoUrl ?? this.photoUrl,
      lastUnitCostCentimes: lastUnitCostCentimes ?? this.lastUnitCostCentimes,
      weightedAverageCostCentimes: weightedAverageCostCentimes ?? this.weightedAverageCostCentimes,
      onHandQty: onHandQty ?? this.onHandQty,
      availableQty: availableQty ?? this.availableQty,
      safetyStockLevel: safetyStockLevel ?? this.safetyStockLevel,
      reorderPoint: reorderPoint ?? this.reorderPoint,
      maxCapacity: maxCapacity ?? this.maxCapacity,
      locationQuantities: locationQuantities ?? this.locationQuantities,
      active: active ?? this.active,
      barcodes: barcodes ?? this.barcodes,
      prices: prices ?? this.prices,
    );
  }

  @override
  List<Object?> get props => [
        id,
        nameAr,
        nameFr,
        category,
        unit,
        packSize,
        photoUrl,
        lastUnitCostCentimes,
        weightedAverageCostCentimes,
        onHandQty,
        availableQty,
        safetyStockLevel,
        reorderPoint,
        maxCapacity,
        locationQuantities,
        active,
        barcodes,
        prices,
      ];
}

typedef Product = ProductEntity;

