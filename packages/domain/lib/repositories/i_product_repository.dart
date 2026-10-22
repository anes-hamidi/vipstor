import '../entities/product_entity.dart';

abstract class IProductRepository {
  Future<List<ProductEntity>> getProducts({String? search, String? category, bool? onlyActive});
  Future<ProductEntity?> getProductByBarcode(String barcode);
  Future<void> saveProduct(ProductEntity product, {int initialOpeningStock = 0, String? userId});
  Future<void> adjustStock({required String productId, required int qtyChange, required String reason, required String userId});

  /// Forces a remote synchronisation of the catalogue and waits for it.
  /// Throws when offline or when the remote call fails, so the caller can
  /// distinguish "served from cache" from "fresh data".
  Future<void> refreshProducts({bool onlyActive = true});

  /// Timestamp of the last successful catalogue sync, if any.
  Future<DateTime?> getLastProductsSyncAt();

  // Delta sync: products updated since [since].
  Future<List<ProductEntity>> getProductsSince({
    required DateTime since,
    int limit,
  });

  // Paginated product fetch.
  Future<List<ProductEntity>> getProductsPage({
    int page,
    int pageSize,
    String? search,
    String? category,
  });
}
