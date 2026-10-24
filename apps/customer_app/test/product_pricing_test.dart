import 'package:domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

ProductEntity _product({
  String unit = 'piece',
  List<ProductPriceTier> prices = const [],
  int cost = 0,
}) {
  return ProductEntity(
    id: 'p1',
    nameAr: 'منتج',
    nameFr: 'Produit',
    category: 'عام',
    unit: unit,
    packSize: 1,
    availableQty: 100,
    active: true,
    prices: prices,
    lastUnitCostCentimes: cost,
  );
}

void main() {
  group('ProductUnit', () {
    test('maps every supported sale unit', () {
      expect(ProductUnit.fromString('carton'), ProductUnit.carton);
      expect(ProductUnit.fromString('boit'), ProductUnit.box);
      expect(ProductUnit.fromString('boîte'), ProductUnit.box);
      expect(ProductUnit.fromString('box'), ProductUnit.box);
      expect(ProductUnit.fromString('pack'), ProductUnit.pack);
      expect(ProductUnit.fromString('paquet'), ProductUnit.pack);
      expect(ProductUnit.fromString('unit'), ProductUnit.piece);
      expect(ProductUnit.fromString('piece'), ProductUnit.piece);
      expect(ProductUnit.fromString('kg'), ProductUnit.kg);
      expect(ProductUnit.fromString('L'), ProductUnit.liter);
      expect(ProductUnit.fromString('litre'), ProductUnit.liter);
      expect(ProductUnit.fromString(null), ProductUnit.piece);
      expect(ProductUnit.fromString(''), ProductUnit.piece);
    });

    test('exposes compact and bilingual labels', () {
      expect(ProductUnit.carton.arabicLabel, 'كرتون');
      expect(ProductUnit.carton.bilingualLabel, 'كرتون (Carton)');
      expect(ProductUnit.kg.formatQuantity(3), '3 كغ');
      expect(ProductUnit.liter.formatQuantityBilingual(2), '2 لتر (L)');
    });
  });

  group('ProductEntity.getPriceForQuantity', () {
    final tiers = [
      const ProductPriceTier(
        id: 'retail-1',
        tier: PriceTier.retail,
        minQty: 1,
        priceCentimes: 10000,
      ),
      const ProductPriceTier(
        id: 'wholesale-10',
        tier: PriceTier.wholesale,
        minQty: 10,
        priceCentimes: 8500,
      ),
      const ProductPriceTier(
        id: 'bulk-50',
        tier: PriceTier.bulk,
        minQty: 50,
        priceCentimes: 8000,
      ),
    ];

    test('uses the highest matching quantity tier for the customer tier', () {
      final product = _product(prices: tiers);
      expect(product.getPriceForQuantity(PriceTier.retail, 1), 10000);
      expect(product.getPriceForQuantity(PriceTier.wholesale, 10), 8500);
      expect(product.getPriceForQuantity(PriceTier.wholesale, 60), 8500);
      expect(product.getPriceForQuantity(PriceTier.bulk, 50), 8000);
    });

    test('falls back to the entry price below a tier threshold', () {
      final product = _product(prices: tiers);
      expect(product.getPriceForQuantity(PriceTier.wholesale, 2), 10000);
      expect(product.getPriceForQuantity(PriceTier.bulk, 2), 10000);
    });

    test('uses another tier instead of showing zero', () {
      final wholesaleOnly = _product(
        prices: const [
          ProductPriceTier(
            id: 'w1',
            tier: PriceTier.wholesale,
            minQty: 1,
            priceCentimes: 7500,
          ),
        ],
      );
      expect(
        wholesaleOnly.getPriceForQuantity(PriceTier.retail, 1),
        7500,
      );
    });

    test('global fallback picks the lowest quantity threshold, not the first row',
        () {
      final product = _product(
        prices: const [
          ProductPriceTier(
            id: 'w5',
            tier: PriceTier.wholesale,
            minQty: 5,
            priceCentimes: 7000,
          ),
          ProductPriceTier(
            id: 'b1',
            tier: PriceTier.bulk,
            minQty: 1,
            priceCentimes: 9000,
          ),
        ],
      );
      expect(product.getPriceForQuantity(PriceTier.retail, 1), 9000);
    });

    test('keeps the cost fallback when a product has no prices at all', () {
      final product = _product(cost: 5000);
      expect(product.getPriceForQuantity(PriceTier.retail, 1), 5000);
    });

    test('maps product units to display labels', () {
      expect(_product(unit: 'carton').unitLabel, 'كرتون');
      expect(_product(unit: 'boit').unitBilingualLabel, 'علبة (Boîte)');
      expect(_product(unit: 'kg').unitLabel, 'كغ');
      expect(_product(unit: 'L').unitLabel, 'لتر');
    });
  });
}
