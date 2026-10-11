import 'package:domain/domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../datasources/remote/supabase_service.dart';

class ProductRepositoryImpl implements IProductRepository {
  final SupabaseClient client;
  final SupabaseService service;

  ProductRepositoryImpl({required this.client, required this.service});

  @override
  Future<List<ProductEntity>> getProducts({
    String? search,
    String? category,
    bool? onlyActive,
  }) async {
    var query = client.from('products').select('''
      id,
      name_ar,
      name_fr,
      category,
      unit,
      pack_size,
      photo_url,
      last_unit_cost,
      active,
      product_prices ( id, tier, min_qty, price ),
      product_barcodes ( barcode, units_per_scan )
    ''');

    if (onlyActive ?? true) {
      query = query.eq('active', true);
    }
    if (category != null && category.isNotEmpty) {
      query = query.eq('category', category);
    }

    final productRows = await query.order('created_at', ascending: false);

    // Fetch live stock from view_product_stock
    final stockRows = await client.from('view_product_stock').select('product_id, on_hand_qty, available_qty');
    final stockMap = <String, Map<String, int>>{};
    for (final s in stockRows as List) {
      stockMap[s['product_id'] as String] = {
        'on_hand': (s['on_hand_qty'] as num?)?.toInt() ?? 0,
        'available': (s['available_qty'] as num?)?.toInt() ?? 0,
      };
    }

    final List<ProductEntity> result = [];
    for (final row in productRows as List) {
      final pid = row['id'] as String;
      final stock = stockMap[pid] ?? {'on_hand': 0, 'available': 0};

      final pricesList = (row['product_prices'] as List? ?? []).map((p) {
        return ProductPriceTier(
          id: p['id'] as String,
          tier: PriceTier.fromString(p['tier'] as String),
          minQty: (p['min_qty'] as num).toInt(),
          priceCentimes: (p['price'] as num).toInt(),
        );
      }).toList();

      final barcodesList = (row['product_barcodes'] as List? ?? [])
          .map((b) => b['barcode'] as String)
          .toList();

      final product = ProductEntity(
        id: pid,
        nameAr: row['name_ar'] as String,
        nameFr: row['name_fr'] as String,
        category: row['category'] as String,
        unit: row['unit'] as String? ?? 'piece',
        packSize: (row['pack_size'] as num?)?.toInt() ?? 1,
        photoUrl: row['photo_url'] as String?,
        lastUnitCostCentimes: (row['last_unit_cost'] as num?)?.toInt() ?? 0,
        onHandQty: stock['on_hand'] ?? 0,
        availableQty: stock['available'] ?? 0,
        active: row['active'] as bool? ?? true,
        barcodes: barcodesList,
        prices: pricesList,
      );

      if (search != null && search.trim().isNotEmpty) {
        final q = search.trim().toLowerCase();
        final match = product.nameAr.toLowerCase().contains(q) ||
            product.nameFr.toLowerCase().contains(q) ||
            product.barcodes.any((b) => b.contains(q));
        if (match) {
          result.add(product);
        }
      } else {
        result.add(product);
      }
    }

    return result;
  }

  @override
  Future<ProductEntity?> getProductByBarcode(String barcode) async {
    final barcodeRows = await client
        .from('product_barcodes')
        .select('product_id')
        .eq('barcode', barcode.trim())
        .limit(1);

    if ((barcodeRows as List).isEmpty) {
      return null;
    }

    final productId = barcodeRows.first['product_id'] as String;
    final products = await getProducts(onlyActive: false);
    return products.where((p) => p.id == productId).firstOrNull;
  }

  Future<String> _resolveValidUserId(String? candidateId) async {
    if (candidateId != null && candidateId.isNotEmpty && candidateId != '22222222-2222-2222-2222-222222222222') {
      try {
        final rows = await client.from('users').select('id').eq('id', candidateId).limit(1);
        if ((rows as List).isNotEmpty) {
          return candidateId;
        }
      } catch (_) {}
    }

    try {
      final rows = await client.from('users').select('id').limit(1);
      if ((rows as List).isNotEmpty) {
        return rows.first['id'] as String;
      }
    } catch (_) {}

    return '11111111-1111-1111-1111-111111111111';
  }

  @override
  Future<void> saveProduct(ProductEntity product, {int initialOpeningStock = 0, String? userId}) async {
    await client.from('products').upsert({
      'id': product.id,
      'name_ar': product.nameAr,
      'name_fr': product.nameFr,
      'category': product.category,
      'unit': product.unit,
      'pack_size': product.packSize,
      'photo_url': product.photoUrl,
      'last_unit_cost': product.lastUnitCostCentimes,
      'active': product.active,
    });

    if (product.barcodes.isNotEmpty) {
      for (final barcode in product.barcodes) {
        await client.from('product_barcodes').upsert({
          'barcode': barcode,
          'product_id': product.id,
          'units_per_scan': 1,
        });
      }
    }

    if (product.prices.isNotEmpty) {
      for (final price in product.prices) {
        await client.from('product_prices').upsert({
          'id': price.id,
          'product_id': product.id,
          'tier': price.tier.name,
          'min_qty': price.minQty,
          'price': price.priceCentimes,
        });
      }
    }

    // If opening stock was specified, write opening stock_ledger record
    final openingQty = initialOpeningStock > 0 ? initialOpeningStock : product.onHandQty;
    if (openingQty > 0) {
      final existingLedger = await client
          .from('stock_ledger')
          .select('id')
          .eq('product_id', product.id)
          .limit(1);

      if ((existingLedger as List).isEmpty) {
        final effectiveUserId = await _resolveValidUserId(userId ?? client.auth.currentUser?.id);
        await client.from('stock_ledger').insert({
          'product_id': product.id,
          'qty_change': openingQty,
          'reason': 'adjustment',
          'ref_type': 'initial_opening_stock',
          'ref_id': product.id,
          'user_id': effectiveUserId,
          'notes': 'المخزون الافتتاحي الأولي عند إنشاء المنتج',
        });
      }
    }
  }

  @override
  Future<void> adjustStock({
    required String productId,
    required int qtyChange,
    required String reason,
    required String userId,
  }) async {
    final effectiveUserId = await _resolveValidUserId(userId);
    await service.adjustStock(
      userId: effectiveUserId,
      productId: productId,
      qtyChange: qtyChange,
      reason: reason,
    );
  }
}
