import 'dart:math' as math;

import 'package:domain/domain.dart';

/// Ordering options exposed in the catalogue UI.
enum CatalogSort {
  recommended,
  priceAsc,
  priceDesc,
  nameAsc,
  stockDesc;

  String get label {
    switch (this) {
      case CatalogSort.recommended:
        return 'الأكثر ملاءمة';
      case CatalogSort.priceAsc:
        return 'الأرخص أولاً';
      case CatalogSort.priceDesc:
        return 'الأغلى أولاً';
      case CatalogSort.nameAsc:
        return 'أبجدي';
      case CatalogSort.stockDesc:
        return 'الأكثر توفراً';
    }
  }
}

/// Arabic/French-aware normalisation used for search.
///
/// Removes Arabic diacritics/tatweel, unifies alef/ya/ta-marbuta variants,
/// strips French accents and collapses punctuation so "إستيراد" matches
/// "استيراد" and "Épicerie" matches "epicerie".
String normalizeCatalogText(String input) {
  var text = input.trim().toLowerCase();
  if (text.isEmpty) return '';

  text = text
      .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '') // tashkeel
      .replaceAll('\u0640', '') // tatweel
      .replaceAll(RegExp('[أإآٱ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه')
      .replaceAll('ؤ', 'و')
      .replaceAll('ئ', 'ي');

  const accents = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
    'ç': 'c', 'ñ': 'n', 'ÿ': 'y',
  };
  accents.forEach((from, to) => text = text.replaceAll(from, to));

  return text
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Relevance score for one product against a pre-normalised query.
///
/// Higher is better; zero means no match. Exact name and barcode matches win,
/// then prefix/word matches, then loose substring matches.
int catalogSearchScore(ProductEntity product, String query) {
  if (query.isEmpty) return 1;

  final ar = normalizeCatalogText(product.nameAr);
  final fr = normalizeCatalogText(product.nameFr);

  var best = 0;
  best = math.max(best, _scoreName(ar, query, 0));
  best = math.max(best, _scoreName(fr, query, 20));

  final category = normalizeCatalogText(product.category);
  if (category.isNotEmpty) {
    if (category == query) {
      best = math.max(best, 260);
    } else if (_hasWordStartingWith(category, query)) {
      best = math.max(best, 220);
    } else if (category.contains(query)) {
      best = math.max(best, 160);
    }
  }

  for (final barcode in product.barcodes) {
    final code = barcode.trim().toLowerCase();
    if (code == query) {
      best = math.max(best, 900);
      break;
    }
    if (code.contains(query)) best = math.max(best, 350);
  }

  return best;
}

int _scoreName(String name, String query, int penalty) {
  if (name.isEmpty) return 0;
  if (name == query) return 1000 - penalty;
  if (name.startsWith(query)) return 820 - penalty;
  if (_hasWordStartingWith(name, query)) return 700 - penalty;
  if (name.contains(query)) return 520 - penalty;
  return 0;
}

bool _hasWordStartingWith(String haystack, String needle) {
  for (final word in haystack.split(' ')) {
    if (word.startsWith(needle)) return true;
  }
  return false;
}

/// Filters + orders the catalogue for display.
///
/// [affinity] maps product ids to how many times the customer ordered them;
/// it only affects [CatalogSort.recommended].
List<ProductEntity> rankCatalog(
  List<ProductEntity> products, {
  String query = '',
  String? category,
  CatalogSort sort = CatalogSort.recommended,
  bool onlyAvailable = false,
  PriceTier tier = PriceTier.retail,
  Map<String, int> affinity = const {},
}) {
  final normalizedQuery = normalizeCatalogText(query);
  final hasCategory = category != null && category.trim().isNotEmpty;

  final scored = <({ProductEntity product, int score})>[];
  for (final product in products) {
    if (!product.active) continue;
    if (onlyAvailable && product.availableQty <= 0) continue;
    if (hasCategory && product.category != category) continue;

    final score = catalogSearchScore(product, normalizedQuery);
    if (normalizedQuery.isNotEmpty && score == 0) continue;
    scored.add((product: product, score: score));
  }

  int compare(ProductEntity a, ProductEntity b) {
    switch (sort) {
      case CatalogSort.priceAsc:
        return _price(a, tier).compareTo(_price(b, tier));
      case CatalogSort.priceDesc:
        return _price(b, tier).compareTo(_price(a, tier));
      case CatalogSort.nameAsc:
        return a.nameAr.compareTo(b.nameAr);
      case CatalogSort.stockDesc:
        return b.availableQty.compareTo(a.availableQty);
      case CatalogSort.recommended:
        final aStock = a.availableQty > 0 ? 1 : 0;
        final bStock = b.availableQty > 0 ? 1 : 0;
        if (aStock != bStock) return bStock.compareTo(aStock);
        final aAffinity = affinity[a.id] ?? 0;
        final bAffinity = affinity[b.id] ?? 0;
        if (aAffinity != bAffinity) return bAffinity.compareTo(aAffinity);
        return 0;
    }
  }

  scored.sort((a, b) {
    if (sort == CatalogSort.recommended) {
      if (b.score != a.score && normalizedQuery.isNotEmpty) {
        return b.score.compareTo(a.score);
      }
      final byLogic = compare(a.product, b.product);
      if (byLogic != 0) return byLogic;
      return a.product.nameAr.compareTo(b.product.nameAr);
    }
    final byLogic = compare(a.product, b.product);
    if (byLogic != 0) return byLogic;
    return a.product.nameAr.compareTo(b.product.nameAr);
  });

  return scored.map((e) => e.product).toList(growable: false);
}

int _price(ProductEntity product, PriceTier tier) {
  final price = product.getPriceForQuantity(tier, 1);
  return price > 0 ? price : product.lastUnitCostCentimes;
}

/// Number of products per category (used by the category chips).
Map<String, int> categoryCounts(
  List<ProductEntity> products, {
  bool onlyAvailable = false,
}) {
  final counts = <String, int>{};
  for (final product in products) {
    if (!product.active) continue;
    if (onlyAvailable && product.availableQty <= 0) continue;
    final category = product.category.trim();
    if (category.isEmpty) continue;
    counts[category] = (counts[category] ?? 0) + 1;
  }
  return counts;
}

/// Great-circle distance in km (driver → delivery address).
double haversineKm(
  double lat1,
  double lng1,
  double lat2,
  double lng2,
) {
  const earthRadius = 6371.0;
  final dLat = _radians(lat2 - lat1);
  final dLng = _radians(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_radians(lat1)) *
          math.cos(_radians(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadius * c;
}

double _radians(double degrees) => degrees * math.pi / 180.0;
