import 'dart:convert';
import 'package:domain/domain.dart';
import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../datasources/remote/supabase_service.dart';
import '../datasources/local/app_database.dart';
import '../datasources/local/connectivity_service.dart';

/// Offline-first product repository.
///
/// Read path:
///   1. Return cached data from SQLite immediately.
///   2. If online AND the cache is stale (> 5 min) OR empty, refresh from
///      Supabase in the background and update the cache.
///
/// Write path (saveProduct / adjustStock):
///   Requires connectivity — these are manager operations that need
///   immediate DB confirmation for stock accuracy.
class ProductRepositoryImpl implements IProductRepository {
  final SupabaseClient client;
  final SupabaseService service;
  final AppDatabase db;
  final bool isCustomerPortal;

  static const _staleDuration = Duration(minutes: 5);

  /// Guards against overlapping background/full catalogue syncs.
  Future<void>? _inFlightSync;

  ProductRepositoryImpl({
    required this.client,
    required this.service,
    required this.db,
    this.isCustomerPortal = false,
  });

  // ── Public API ────────────────────────────────────────────────────────────

  @override
  Future<List<ProductEntity>> getProducts({
    String? search,
    String? category,
    bool? onlyActive,
  }) async {
    // 1. Trigger background sync if stale / online
    _maybeRefreshCache();

    // 2. Read from local cache
    final cached = await db.getAllProducts();
    if (cached.isEmpty && ConnectivityService.instance.isOnline) {
      // Cold start with connectivity — wait for the first sync before returning
      await _syncProductsFromRemote();
      return _buildEntitiesFromCache(search, category, onlyActive);
    }

    return _buildEntitiesFromCache(search, category, onlyActive,
        cached: cached);
  }

  @override
  Future<void> refreshProducts({bool onlyActive = true}) async {
    if (!ConnectivityService.instance.isOnline) {
      throw Exception('لا يوجد اتصال بالإنترنت');
    }
    final existing = _inFlightSync;
    if (existing != null) {
      await existing;
      return;
    }
    final future = _syncProductsFromRemote(shouldRethrow: true);
    _inFlightSync = future;
    try {
      await future;
    } finally {
      if (identical(_inFlightSync, future)) _inFlightSync = null;
    }
  }

  @override
  Future<DateTime?> getLastProductsSyncAt() => db.getLastSync('products');

  @override
  Future<ProductEntity?> getProductByBarcode(String barcode) async {
    // Try local first
    final local = await db.getProductByBarcode(barcode.trim());
    if (local != null) return _cachedToEntity(local);

    // Fallback: remote lookup
    if (!ConnectivityService.instance.isOnline) return null;
    final barcodeRows = await client
        .from('product_barcodes')
        .select('product_id')
        .eq('barcode', barcode.trim())
        .limit(1);
    if ((barcodeRows as List).isEmpty) return null;

    final productId = barcodeRows.first['product_id'] as String;
    final all = await getProducts(onlyActive: false);
    return all.where((p) => p.id == productId).firstOrNull;
  }

  @override
  Future<void> saveProduct(ProductEntity product,
      {int initialOpeningStock = 0, String? userId}) async {
    final effectiveUserId = _requireActorId(userId);
    final openingQty =
        initialOpeningStock > 0 ? initialOpeningStock : product.onHandQty;

    await client.rpc('rpc_create_product', params: {
      'p_product': {
        'id': product.id,
        'name_ar': product.nameAr,
        'name_fr': product.nameFr,
        'category': product.category,
        'unit': product.unit,
        'pack_size': product.packSize,
        'photo_url': product.photoUrl,
        'last_unit_cost': product.lastUnitCostCentimes,
        'active': product.active,
      },
      'p_barcodes': product.barcodes,
      'p_prices': product.prices
          .map((p) => {
                'id': p.id,
                'tier': p.tier.name,
                'min_qty': p.minQty,
                'price': p.priceCentimes,
              })
          .toList(),
      'p_opening_stock': openingQty,
      'p_user_id': effectiveUserId,
    });

    // Refresh cache after successful write
    await _syncProductsFromRemote();
  }

  @override
  Future<void> adjustStock({
    required String productId,
    required int qtyChange,
    required String reason,
    required String userId,
    required String callerPin,
  }) async {
    final effectiveUserId = _requireActorId(userId);
    await service.adjustStock(
      userId: effectiveUserId,
      callerPin: callerPin,
      productId: productId,
      qtyChange: qtyChange,
      reason: reason,
    );
    // Refresh cache after stock adjustment
    await _syncProductsFromRemote();
  }

  // ── Cache management ──────────────────────────────────────────────────────

  Future<void> _maybeRefreshCache() async {
    if (!ConnectivityService.instance.isOnline) return;
    final lastSync = await db.getLastSync('products');
    final isStale =
        lastSync == null || DateTime.now().difference(lastSync) > _staleDuration;
    if (isStale) {
      // Fire-and-forget; don't await so UI gets cached data immediately
      _syncProductsFromRemote().ignore();
    }
  }

  Future<void> _syncProductsFromRemote({bool shouldRethrow = false}) async {
    try {
      if (isCustomerPortal) {
        await _syncCustomerPortalProducts();
      } else {
        await _syncStaffProducts();
      }
      await db.setLastSync('products', DateTime.now());
    } catch (_) {
      // Sync failure is silent for background refresh — cached data remains
      // available. Interactive refreshes pass [rethrow] so the UI can show a
      // meaningful message while keeping the cached catalogue visible.
      if (shouldRethrow) rethrow;
    }
  }

  Future<void> _syncStaffProducts() async {
    final productRows = await client.from('products').select('''
      id, name_ar, name_fr, category, unit, pack_size,
      photo_url, last_unit_cost, active,
      product_prices ( id, tier, min_qty, price ),
      product_barcodes ( barcode )
    ''');

    final stockRows = await client
        .from('view_product_stock')
        .select('product_id, on_hand_qty, available_qty');
    final stockMap = <String, Map<String, int>>{};
    for (final s in stockRows as List) {
      stockMap[s['product_id'] as String] = {
        'on_hand': (s['on_hand_qty'] as num?)?.toInt() ?? 0,
        'available': (s['available_qty'] as num?)?.toInt() ?? 0,
      };
    }

    final companions = (productRows as List).map<CachedProductsCompanion>((r) {
      final pid = r['id'] as String;
      final stock = stockMap[pid] ?? {'on_hand': 0, 'available': 0};
      final prices = (r['product_prices'] as List? ?? []);
      final barcodes = (r['product_barcodes'] as List? ?? [])
          .map((b) => b['barcode'] as String)
          .toList();
      return CachedProductsCompanion.insert(
        id: pid,
        nameAr: r['name_ar'] as String? ?? '',
        nameFr: r['name_fr'] as String? ?? '',
        category: r['category'] as String? ?? '',
        unit: r['unit'] as String? ?? 'piece',
        packSize: (r['pack_size'] as num?)?.toInt() ?? 1,
        lastUnitCostCentimes:
            (r['last_unit_cost'] as num?)?.toInt() ?? 0,
        onHandQty: stock['on_hand'] ?? 0,
        availableQty: stock['available'] ?? 0,
        active: r['active'] as bool? ?? true,
        photoUrl: Value(r['photo_url'] as String?),
        pricesJson: jsonEncode(prices),
        barcodesJson: jsonEncode(barcodes),
        syncedAt: DateTime.now(),
      );
    }).toList();

    await db.upsertProducts(companions);
  }

  Future<void> _syncCustomerPortalProducts() async {
    final viewRows = await client
        .from('view_customer_products')
        .select(
            'product_id, name_ar, name_fr, category, unit, pack_size, photo_url, active, available_qty, retail_price, wholesale_price')
        .eq('active', true);

    if ((viewRows as List).isEmpty) return;
    final ids = viewRows.map((r) => r['product_id'] as String).toList();

    // Fetch price tiers and barcodes in parallel — halves the cold-start
    // latency of the customer catalogue.
    List priceRows = const [];
    List barcodeRows = const [];
    final results = await Future.wait<List>([
      () async {
        try {
          final rows = await client
              .from('product_prices')
              .select('id, product_id, tier, min_qty, price')
              .inFilter('product_id', ids);
          return rows as List;
        } catch (_) {
          return const <dynamic>[];
        }
      }(),
      () async {
        try {
          final rows = await client
              .from('product_barcodes')
              .select('product_id, barcode')
              .inFilter('product_id', ids);
          return rows as List;
        } catch (_) {
          return const <dynamic>[];
        }
      }(),
    ]);
    priceRows = results[0];
    barcodeRows = results[1];

    final pricesMap = <String, List<Map<String, dynamic>>>{};
    for (final p in priceRows) {
      pricesMap.putIfAbsent(p['product_id'] as String, () => [])
        .add(Map<String, dynamic>.from(p));
    }
    final barcodesMap = <String, List<String>>{};
    for (final b in barcodeRows) {
      barcodesMap.putIfAbsent(b['product_id'] as String, () => [])
        .add(b['barcode'] as String);
    }

    final companions = viewRows.map<CachedProductsCompanion>((r) {
      final pid = r['product_id'] as String;
      final retail = (r['retail_price'] as num?)?.toInt() ?? 0;
      final wholesale = (r['wholesale_price'] as num?)?.toInt() ?? retail;

      // Fallback/Synthesis if product_prices rows were restricted by RLS
      final pList = pricesMap[pid] ?? [];
      if (pList.isEmpty) {
        pList.add({
          'id': '${pid}_retail',
          'product_id': pid,
          'tier': 'retail',
          'min_qty': 1,
          'price': retail,
        });
        pList.add({
          'id': '${pid}_wholesale',
          'product_id': pid,
          'tier': 'wholesale',
          'min_qty': 1,
          'price': wholesale,
        });
      }

      return CachedProductsCompanion.insert(
        id: pid,
        nameAr: r['name_ar'] as String? ?? '',
        nameFr: r['name_fr'] as String? ?? '',
        category: r['category'] as String? ?? '',
        unit: r['unit'] as String? ?? 'piece',
        packSize: (r['pack_size'] as num?)?.toInt() ?? 1,
        lastUnitCostCentimes: 0,
        onHandQty: (r['available_qty'] as num?)?.toInt() ?? 0,
        availableQty: (r['available_qty'] as num?)?.toInt() ?? 0,
        active: r['active'] as bool? ?? true,
        photoUrl: Value(r['photo_url'] as String?),
        pricesJson: jsonEncode(pList),
        barcodesJson: jsonEncode(barcodesMap[pid] ?? []),
        syncedAt: DateTime.now(),
      );
    }).toList();

    await db.upsertProducts(companions);
    // Prune products that no longer exist / are no longer visible to the
    // customer portal so stale cached rows (e.g. renamed or deactivated
    // items) never resurface while offline.
    await db.pruneProducts(companions.map((c) => c.id.value).toSet());
  }

  // ── Entity assembly ───────────────────────────────────────────────────────

  Future<List<ProductEntity>> _buildEntitiesFromCache(
    String? search,
    String? category,
    bool? onlyActive, {
    List<CachedProduct>? cached,
  }) async {
    final rows = cached ?? await db.getAllProducts();
    final result = <ProductEntity>[];

    for (final row in rows) {
      if ((onlyActive ?? true) && !row.active) continue;
      if (category != null &&
          category.isNotEmpty &&
          row.category != category) {
        continue;
      }

      final entity = _cachedToEntity(row);

      if (search != null && search.trim().isNotEmpty) {
        final q = search.trim().toLowerCase();
        final match = entity.nameAr.toLowerCase().contains(q) ||
            entity.nameFr.toLowerCase().contains(q) ||
            entity.barcodes.any((b) => b.contains(q));
        if (match) result.add(entity);
      } else {
        result.add(entity);
      }
    }
    return result;
  }

  ProductEntity _cachedToEntity(CachedProduct row) {
    List<ProductPriceTier> prices = [];
    List<String> barcodes = [];
    try {
      final rawPrices = jsonDecode(row.pricesJson) as List;
      prices = rawPrices.map((p) {
        final m = p as Map<String, dynamic>;
        return ProductPriceTier(
          id: m['id'] as String? ?? '',
          tier: PriceTier.fromString(m['tier'] as String? ?? 'retail'),
          minQty: (m['min_qty'] as num?)?.toInt() ?? 1,
          priceCentimes: (m['price'] as num?)?.toInt() ?? 0,
        );
      }).toList();
    } catch (_) {}
    try {
      barcodes = List<String>.from(jsonDecode(row.barcodesJson) as List);
    } catch (_) {}

    return ProductEntity(
      id: row.id,
      nameAr: row.nameAr,
      nameFr: row.nameFr,
      category: row.category,
      unit: row.unit,
      packSize: row.packSize,
      photoUrl: row.photoUrl,
      lastUnitCostCentimes: row.lastUnitCostCentimes,
      onHandQty: row.onHandQty,
      availableQty: row.availableQty,
      active: row.active,
      barcodes: barcodes,
      prices: prices,
    );
  }

  String _requireActorId(String? candidateId) {
    final id = (candidateId == null || candidateId.trim().isEmpty)
        ? client.auth.currentUser?.id
        : candidateId;
    if (id == null || id.trim().isEmpty) {
      throw StateError('missing authenticated user id');
    }
    return id;
  }

  // ------------------------------------------------------------------
  // Delta sync: products updated since [since]. Used for incremental
  // catalogue sync instead of fetching the full catalogue every session.
  // ------------------------------------------------------------------
  @override
  Future<List<ProductEntity>> getProductsSince({
    required DateTime since,
    int limit = 200,
  }) async {
    final rows = await client
        .from('products')
        .select('''
          id, name_ar, name_fr, category, unit, pack_size,
          last_unit_cost, min_stock_alert, active, photo_url, updated_at
        ''')
        .eq('active', true)
        .gt('updated_at', since.toIso8601String())
        .order('updated_at', ascending: false)
        .limit(limit);

    return _buildEntitiesFromSqlRows(rows as List);
  }

  // ------------------------------------------------------------------
  // Paginated product fetch. Returns [pageSize] rows starting at offset
  // ((page - 1) * pageSize). Used to avoid loading the entire catalogue
  // when only a subset is needed.
  // ------------------------------------------------------------------
  @override
  Future<List<ProductEntity>> getProductsPage({
    int page = 1,
    int pageSize = 50,
    String? search,
    String? category,
  }) async {
    var query = client
        .from('products')
        .select('''
          id, name_ar, name_fr, category, unit, pack_size,
          last_unit_cost, min_stock_alert, active, photo_url, updated_at
        ''')
        .eq('active', true);

    if (search != null && search.isNotEmpty) {
      query = query.or('name_ar.ilike.%$search%,name_fr.ilike.%$search%');
    }
    if (category != null && category.isNotEmpty) {
      query = query.eq('category', category);
    }

    final from = (page - 1) * pageSize;
    final to = from + pageSize - 1;
    final rows = await query.order('name_ar').range(from, to);

    return _buildEntitiesFromSqlRows(rows as List);
  }

  /// Builds [ProductEntity] list from raw Supabase rows (used by delta/page methods).
  List<ProductEntity> _buildEntitiesFromSqlRows(List rows) {
    return rows.map((r) {
      return ProductEntity(
        id: r['id'] as String,
        nameAr: r['name_ar'] as String? ?? '',
        nameFr: r['name_fr'] as String? ?? '',
        category: r['category'] as String? ?? '',
        unit: r['unit'] as String? ?? 'piece',
        packSize: (r['pack_size'] as num?)?.toInt() ?? 1,
        lastUnitCostCentimes: (r['last_unit_cost'] as num?)?.toInt() ?? 0,
        onHandQty: (r['on_hand_qty'] as num?)?.toInt() ?? 0,
        availableQty: (r['available_qty'] as num?)?.toInt() ?? 0,
        active: r['active'] as bool? ?? true,
        photoUrl: r['photo_url'] as String?,
        barcodes: const [],
        prices: const [],
      );
    }).toList();
  }
}
