import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:domain/domain.dart';
import 'package:data/data.dart';
import 'staff_providers.dart';


// ── Repository Provider ──────────────────────────────────────────────────────

final inventoryRepositoryProvider = Provider<IInventoryRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final service = ref.watch(supabaseServiceProvider);
  final db = ref.watch(appDatabaseProvider);
  return InventoryRepositoryImpl(
    client: client,
    service: service,
    db: db,
  );
});

// ── Stock Adjustments & History ──────────────────────────────────────────────

final stockAdjustmentHistoryProvider =
    FutureProvider<List<StockAdjustmentEntity>>((ref) async {
  final repo = ref.watch(inventoryRepositoryProvider);
  return repo.getAdjustmentHistory();
});

// ── Cycle Counting & Auditing ────────────────────────────────────────────────

final activeCycleCountProvider =
    StateProvider<CycleCountAuditEntity?>((ref) => null);

final auditHistoryProvider =
    FutureProvider<List<CycleCountAuditEntity>>((ref) async {
  final repo = ref.watch(inventoryRepositoryProvider);
  return repo.getAuditHistory();
});

// ── Multi-Location & Stock Transfers ─────────────────────────────────────────

final stockTransfersProvider =
    FutureProvider<List<StockTransferEntity>>((ref) async {
  final repo = ref.watch(inventoryRepositoryProvider);
  return repo.getTransfers();
});

// ── Low Stock & Replenishment Intelligence ───────────────────────────────────

enum StockFilterOption {
  all('الكل'),
  lowStock('منخفض'),
  critical('حرج'),
  outOfStock('منفد'),
  overstocked('فائض');

  final String labelAr;
  const StockFilterOption(this.labelAr);
}

final stockFilterProvider =
    StateProvider<StockFilterOption>((ref) => StockFilterOption.all);

final lowStockProductsProvider =
    FutureProvider<List<ProductEntity>>((ref) async {
  final repo = ref.watch(inventoryRepositoryProvider);
  return repo.getLowStockProducts();
});

// ── Purchase Orders & GRN ────────────────────────────────────────────────────

final purchaseOrdersListProvider =
    FutureProvider<List<PurchaseOrderEntity>>((ref) async {
  final repo = ref.watch(inventoryRepositoryProvider);
  return repo.getPurchaseOrders();
});
