import '../entities/product_entity.dart';

abstract class IProductRepository {
  Future<List<ProductEntity>> getProducts({String? search, String? category, bool? onlyActive});
  Future<ProductEntity?> getProductByBarcode(String barcode);
  Future<void> saveProduct(ProductEntity product, {int initialOpeningStock = 0, String? userId});
  Future<void> adjustStock({required String productId, required int qtyChange, required String reason, required String userId});

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
