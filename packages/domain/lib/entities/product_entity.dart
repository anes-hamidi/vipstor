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

class ProductEntity extends Equatable {
  final String id;
  final String nameAr;
  final String nameFr;
  final String category;
  final String unit;
  final int packSize;
  final String? photoUrl;
  final int lastUnitCostCentimes;
  final int onHandQty;
  final int availableQty;
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
    this.onHandQty = 0,
    this.availableQty = 0,
    required this.active,
    this.barcodes = const [],
    List<ProductPriceTier>? prices,
    List<ProductPriceTier>? priceTiers,
  })  : lastUnitCostCentimes = lastUnitCostCentimes ?? costCentimes ?? 0,
        prices = prices ?? priceTiers ?? const [];

  int get costCentimes => lastUnitCostCentimes;
  List<ProductPriceTier> get priceTiers => prices;

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
        onHandQty,
        availableQty,
        active,
        barcodes,
        prices,
      ];
}

typedef Product = ProductEntity;
