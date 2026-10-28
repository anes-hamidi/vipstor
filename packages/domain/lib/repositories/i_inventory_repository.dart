import '../entities/product_entity.dart';
import '../entities/inventory_adjustment_entity.dart';
import '../entities/cycle_count_audit_entity.dart';
import '../entities/stock_transfer_entity.dart';
import '../entities/purchase_order_entity.dart';

abstract class IInventoryRepository {
  // ── 1. Stock Adjustments & Audit Trails ────────────────────────────────────
  Future<List<StockAdjustmentEntity>> getAdjustmentHistory({int limit = 50});

  Future<StockAdjustmentEntity> executeStockAdjustment({
    required StockAdjustmentEntity adjustment,
    required String callerPin,
  });

  // ── 2. Cycle Counting & Reconciliation ─────────────────────────────────────
  Future<CycleCountAuditEntity> startCycleCount({
    required String locationId,
    required String locationName,
    List<String>? categoryFilter,
    required String userId,
    required String userName,
  });

  Future<void> recordPhysicalCount({
    required String auditId,
    required String productId,
    required int physicalCount,
    String? notes,
  });

  Future<CycleCountAuditEntity> reconcileAudit({
    required String auditId,
    required String userId,
    required String userName,
    required String reconciliationNotes,
  });

  Future<List<CycleCountAuditEntity>> getAuditHistory({int limit = 20});

  // ── 3. Multi-Location & Stock Transfers ────────────────────────────────────
  Future<List<StockTransferEntity>> getTransfers();

  Future<StockTransferEntity> createTransfer({
    required StockTransferEntity transfer,
  });

  Future<void> updateTransferStatus({
    required String transferId,
    required TransferStatus status,
    required String userId,
    required String userName,
  });

  // ── 4. Low Stock Intelligence & Replenishment ──────────────────────────────
  Future<List<ProductEntity>> getLowStockProducts();

  Future<PurchaseOrderEntity> generateDraftPOFromLowStock({
    required String supplierId,
    required String supplierName,
    required String createdById,
    required String createdByName,
    List<String>? selectedProductIds,
  });

  // ── 5. Purchase Orders & Goods Receiving Note (GRN) ────────────────────────
  Future<List<PurchaseOrderEntity>> getPurchaseOrders();

  Future<PurchaseOrderEntity> createPurchaseOrder({
    required PurchaseOrderEntity purchaseOrder,
  });

  Future<void> receiveGoodsNote({
    required String poId,
    required List<Map<String, dynamic>> receivedItems,
    required String userId,
    required String userName,
    String? locationId,
  });
}
