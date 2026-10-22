import 'package:customer_app/core/catalog_ranking.dart';
import 'package:domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

ProductEntity _product({
  String id = 'p1',
  String nameAr = 'زيت زيتون بكر',
  String nameFr = 'Huile d\'olive vierge',
  String category = 'زيوت',
  int availableQty = 10,
  bool active = true,
  List<String> barcodes = const [],
  List<ProductPriceTier> prices = const [],
  int cost = 0,
}) {
  return ProductEntity(
    id: id,
    nameAr: nameAr,
    nameFr: nameFr,
    category: category,
    unit: 'piece',
    packSize: 1,
    availableQty: availableQty,
    active: active,
    barcodes: barcodes,
    prices: prices,
    lastUnitCostCentimes: cost,
  );
}

void main() {
  group('normalizeCatalogText', () {
    test('unifies Arabic letter variants and strips diacritics', () {
      expect(normalizeCatalogText('  إستيراد  '), 'استيراد');
      expect(normalizeCatalogText('مُنْتَجٌ'), 'منتج');
      expect(normalizeCatalogText('مستشفى'), 'مستشفي');
      expect(normalizeCatalogText('عُلبة'), 'علبه');
    });

    test('strips French accents and punctuation', () {
      expect(normalizeCatalogText('Épicerie'), 'epicerie');
      expect(normalizeCatalogText('Crème  fraîche'), 'creme fraiche');
      expect(normalizeCatalogText('زيت---زيتون'), 'زيت زيتون');
    });

    test('returns empty for blank input', () {
      expect(normalizeCatalogText('   '), '');
    });
  });

  group('catalogSearchScore', () {
    test('barcode exact match beats a name match', () {
      final product = _product(barcodes: const ['6130000000012']);
      final byName = catalogSearchScore(product, 'زيت');
      final byBarcode = catalogSearchScore(product, '6130000000012');
      expect(byBarcode, greaterThan(byName));
    });

    test('matches normalized French names without accents', () {
      final product = _product(nameAr: 'منتج', nameFr: 'Épicerie fine');
      expect(catalogSearchScore(product, 'epicerie'), greaterThan(0));
    });

    test('scores exact names above word prefixes', () {
      final exact = _product(nameAr: 'زيت', nameFr: 'Oil');
      final prefix = _product(nameAr: 'زيت زيتون', nameFr: 'Olive oil');
      expect(
        catalogSearchScore(exact, 'زيت'),
        greaterThan(catalogSearchScore(prefix, 'زيت')),
      );
    });

    test('returns zero when nothing matches', () {
      final product = _product();
      expect(catalogSearchScore(product, 'شوكولاتة'), 0);
    });
  });

  group('rankCatalog', () {
    test('drops inactive products and filters out-of-stock on demand', () {
      final products = [
        _product(id: 'active', availableQty: 4),
        _product(id: 'inactive', active: false),
        _product(id: 'empty', availableQty: 0),
      ];

      final all = rankCatalog(products);
      expect(all.map((p) => p.id), ['active', 'empty']);

      final available = rankCatalog(products, onlyAvailable: true);
      expect(available.map((p) => p.id), ['active']);
    });

    test('filters by category', () {
      final products = [
        _product(id: 'oil', category: 'زيوت'),
        _product(id: 'grain', category: 'حبوب'),
      ];
      final result = rankCatalog(products, category: 'حبوب');
      expect(result.map((p) => p.id), ['grain']);
    });

    test('search results are ordered by relevance', () {
      final products = [
        _product(id: 'contains', nameAr: 'خبز بالزيت'),
        _product(id: 'exact', nameAr: 'زيت'),
        _product(id: 'startsWith', nameAr: 'زيت زيتون'),
        _product(id: 'other', nameAr: 'سكر'),
      ];

      final result = rankCatalog(products, query: 'زيت');
      expect(result.map((p) => p.id), ['exact', 'startsWith', 'contains']);
    });

    test('recommended puts in-stock and affinity first', () {
      final products = [
        _product(id: 'empty', availableQty: 0),
        _product(id: 'regular', availableQty: 8),
        _product(id: 'favorite', availableQty: 2),
      ];

      final result = rankCatalog(
        products,
        affinity: const {'favorite': 5},
      );

      expect(result.map((p) => p.id), ['favorite', 'regular', 'empty']);
    });

    test('price sort uses the requested tier', () {
      final products = [
        _product(
          id: 'cheap',
          nameAr: 'أ',
          prices: const [
            ProductPriceTier(
              id: 'c1',
              tier: PriceTier.wholesale,
              minQty: 1,
              priceCentimes: 500,
            ),
          ],
        ),
        _product(
          id: 'expensive',
          nameAr: 'ب',
          prices: const [
            ProductPriceTier(
              id: 'c2',
              tier: PriceTier.wholesale,
              minQty: 1,
              priceCentimes: 900,
            ),
          ],
        ),
      ];

      final ascending = rankCatalog(
        products,
        sort: CatalogSort.priceAsc,
        tier: PriceTier.wholesale,
      );
      expect(ascending.map((p) => p.id), ['cheap', 'expensive']);

      final descending = rankCatalog(
        products,
        sort: CatalogSort.priceDesc,
        tier: PriceTier.wholesale,
      );
      expect(descending.map((p) => p.id), ['expensive', 'cheap']);
    });

    test('stock sort shows the most available first', () {
      final products = [
        _product(id: 'low', availableQty: 1),
        _product(id: 'high', availableQty: 50),
      ];
      final result = rankCatalog(products, sort: CatalogSort.stockDesc);
      expect(result.map((p) => p.id), ['high', 'low']);
    });
  });

  group('categoryCounts', () {
    test('counts only active products and can require stock', () {
      final products = [
        _product(id: 'a', category: 'زيوت'),
        _product(id: 'b', category: 'زيوت', availableQty: 0),
        _product(id: 'c', category: 'حبوب', active: false),
        _product(id: 'd', category: '  '),
      ];

      expect(categoryCounts(products), {'زيوت': 2});

      expect(
        categoryCounts(products, onlyAvailable: true),
        {'زيوت': 1},
      );
    });
  });

  group('haversineKm', () {
    test('returns zero for the same point', () {
      expect(haversineKm(36.75, 3.05, 36.75, 3.05), closeTo(0, 0.0001));
    });

    test('computes one degree of longitude at the equator', () {
      // 1° of longitude at the equator is ~111.19 km.
      expect(haversineKm(0, 0, 0, 1), closeTo(111.19, 0.2));
    });
  });
}
