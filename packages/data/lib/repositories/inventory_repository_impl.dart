import 'dart:async';
import 'package:domain/domain.dart';
import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../datasources/local/app_database.dart';
import '../datasources/local/connectivity_service.dart';
import '../datasources/remote/supabase_service.dart';

/// Implementation of [IInventoryRepository] supporting:
/// - Offline-first atomic local DB transactions via Drift
/// - Concurrency protection using an internal sequential lock queue
/// - Stock adjustments with mandatory reason tags and audit logging
/// - Non-disruptive cycle counting and reconciliation with variance calculation
/// - Internal multi-location transfers with transit states
/// - Low stock detection and automated draft PO generation
/// - Goods Received Note (GRN) receiving against POs with Moving Weighted Average Cost (WAC) updates
class InventoryRepositoryImpl implements IInventoryRepository {
  final SupabaseClient client;
  final SupabaseService service;
  final AppDatabase db;
  final _uuid = const Uuid();

  // Concurrency queue to protect against race conditions during rapid operations
  Completer<void>? _activeLock;

  InventoryRepositoryImpl({
    required this.client,
    required this.service,
    required this.db,
  });

  /// Acquire mutex lock for critical stock updates
  Future<T> _synchronized<T>(Future<T> Function() action) async {
    while (_activeLock != null) {
      await _activeLock!.future;
    }
    final completer = Completer<void>();
    _activeLock = completer;
    try {
      return await action();
    } finally {
      _activeLock = null;
      completer.complete();
    }
  }

  // ── 1. Stock Adjustments & Audit Trails ────────────────────────────────────

  @override
  Future<List<StockAdjustmentEntity>> getAdjustmentHistory({int limit = 50}) async {
    try {
      final rows = await client
          .from('stock_adjustments')
          .select('''
            id,
            reference_number,
            reason,
            notes,
            location_id,
            location_name,
            adjusted_by_user_id,
            adjusted_by_name,
            created_at,
            items:stock_adjustment_items (
              id,
              product_id,
              product_name,
              unit,
              old_stock,
              new_stock,
              qty_change,
              unit_cost_centimes,
              batch_number,
              expiry_date,
              notes
            )
          ''')
          .order('created_at', ascending: false)
          .limit(limit);

      return (rows as List).map((row) {
        final items = ((row['items'] as List?) ?? []).map((it) {
          return StockAdjustmentItemEntity(
            id: it['id'] as String,
            productId: it['product_id'] as String,
            productName: it['product_name'] as String? ?? 'منتج',
            unit: it['unit'] as String? ?? 'قطعة',
            oldStock: (it['old_stock'] as num?)?.toInt() ?? 0,
            newStock: (it['new_stock'] as num?)?.toInt() ?? 0,
            qtyChange: (it['qty_change'] as num?)?.toInt() ?? 0,
            unitCostCentimes: (it['unit_cost_centimes'] as num?)?.toInt() ?? 0,
            batchNumber: it['batch_number'] as String?,
            expiryDate: it['expiry_date'] != null
                ? DateTime.tryParse(it['expiry_date'] as String)
                : null,
            itemNotes: it['notes'] as String?,
          );
        }).toList();

        return StockAdjustmentEntity(
          id: row['id'] as String,
          referenceNumber: row['reference_number'] as String,
          reason: StockAdjustmentReason.fromCode(row['reason'] as String),
          notes: row['notes'] as String?,
          locationId: row['location_id'] as String? ?? 'loc_main',
          locationName: row['location_name'] as String? ?? 'المستودع المركزي',
          adjustedByUserId: row['adjusted_by_user_id'] as String,
          adjustedByName: row['adjusted_by_name'] as String? ?? 'مدير المخزون',
          createdAt: DateTime.parse(row['created_at'] as String),
          items: items,
        );
      }).toList();
    } catch (_) {
      // Fallback: If table does not exist or remote is offline, query stock ledger or return empty list
      return _queryAdjustmentFromLedger(limit: limit);
    }
  }

  Future<List<StockAdjustmentEntity>> _queryAdjustmentFromLedger({int limit = 50}) async {
    try {
      final rows = await client
          .from('stock_ledger')
          .select('''
            id,
            product_id,
            qty_change,
            reason,
            created_at,
            user_id,
            products ( name_ar, unit, last_unit_cost )
          ''')
          .order('created_at', ascending: false)
          .limit(limit);

      return (rows as List).map((row) {
        final prod = row['products'] as Map<String, dynamic>?;
        final qtyChange = (row['qty_change'] as num?)?.toInt() ?? 0;
        final unitCost = (prod?['last_unit_cost'] as num?)?.toInt() ?? 0;

        return StockAdjustmentEntity(
          id: row['id'] as String,
          referenceNumber: 'ADJ-${row['id'].toString().substring(0, 6).toUpperCase()}',
          reason: StockAdjustmentReason.fromCode(row['reason'] as String? ?? 'other'),
          locationId: 'loc_main',
          locationName: 'المستودع المركزي',
          adjustedByUserId: row['user_id'] as String? ?? 'system',
          adjustedByName: 'مدير المخزون',
          createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now(),
          items: [
            StockAdjustmentItemEntity(
              id: row['id'] as String,
              productId: row['product_id'] as String,
              productName: prod?['name_ar'] as String? ?? 'منتج',
              unit: prod?['unit'] as String? ?? 'قطعة',
              oldStock: 0,
              newStock: qtyChange,
              qtyChange: qtyChange,
              unitCostCentimes: unitCost,
            ),
          ],
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<StockAdjustmentEntity> executeStockAdjustment({
    required StockAdjustmentEntity adjustment,
    required String callerPin,
  }) async {
    return _synchronized(() async {
      if (!ConnectivityService.instance.isOnline) {
        throw Exception(
          'تسوية المخزون تتطلب اتصالاً بالإنترنت لتأكيد رمز PIN وكتابة سجل التدقيق.',
        );
      }

      // The RPC verifies the caller's PIN, derives the actor from the JWT and
      // writes the authoritative stock ledger. Never mirror this into
      // stock_adjustments from the client.
      for (final item in adjustment.items) {
        await service.adjustStock(
          userId: adjustment.adjustedByUserId,
          callerPin: callerPin,
          productId: item.productId,
          qtyChange: item.qtyChange,
          reason:
              '${adjustment.reason.code}: ${adjustment.notes ?? adjustment.reason.labelAr}',
        );
      }

      // Refresh the local cache only after the server accepted the adjustment.
      await db.transaction(() async {
        for (final item in adjustment.items) {
          final cached = await (db.select(db.cachedProducts)
                ..where((tbl) => tbl.id.equals(item.productId)))
              .getSingleOrNull();

          if (cached != null) {
            final updatedOnHand =
                (cached.onHandQty + item.qtyChange).clamp(0, 9999999);
            final updatedAvailable =
                (cached.availableQty + item.qtyChange).clamp(0, 9999999);

            await (db.update(db.cachedProducts)
                  ..where((tbl) => tbl.id.equals(item.productId)))
                .write(CachedProductsCompanion(
              onHandQty: Value(updatedOnHand),
              availableQty: Value(updatedAvailable),
            ));
          }
        }
      });

      return adjustment;
    });
  }

  // ── 2. Cycle Counting & Reconciliation ─────────────────────────────────────

  final List<CycleCountAuditEntity> _localAudits = [];

  @override
  Future<CycleCountAuditEntity> startCycleCount({
    required String locationId,
    required String locationName,
    List<String>? categoryFilter,
    required String userId,
    required String userName,
  }) async {
    final cachedProducts = await db.getAllProducts();

    final filtered = cachedProducts.where((p) {
      if (!p.active) return false;
      if (categoryFilter != null && categoryFilter.isNotEmpty) {
        return categoryFilter.contains(p.category);
      }
      return true;
    }).toList();

    final auditId = _uuid.v4();
    final auditNumber = 'AUD-${DateTime.now().millisecondsSinceEpoch % 100000}';

    final items = filtered.map((p) {
      return CycleCountItemEntity(
        id: _uuid.v4(),
        productId: p.id,
        productName: p.nameAr,
        category: p.category,
        unit: p.unit,
        barcodes: (p.barcodesJson.replaceAll(RegExp(r'[\[\]"]'), '').split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList()),
        systemStock: p.availableQty,
        physicalCount: p.availableQty, // Pre-filled default to minimize typing, user adjusts
        unitCostCentimes: p.lastUnitCostCentimes,
      );
    }).toList();

    final audit = CycleCountAuditEntity(
      id: auditId,
      auditNumber: auditNumber,
      status: AuditStatus.inProgress,
      locationId: locationId,
      locationName: locationName,
      countedByUserId: userId,
      countedByName: userName,
      startedAt: DateTime.now(),
      items: items,
    );

    _localAudits.insert(0, audit);
    return audit;
  }

  @override
  Future<void> recordPhysicalCount({
    required String auditId,
    required String productId,
    required int physicalCount,
    String? notes,
  }) async {
    final auditIdx = _localAudits.indexWhere((a) => a.id == auditId);
    if (auditIdx < 0) return;

    final audit = _localAudits[auditIdx];
    final updatedItems = audit.items.map((item) {
      if (item.productId == productId) {
        return item.copyWith(
          physicalCount: physicalCount,
          notes: notes,
          countedAt: DateTime.now(),
        );
      }
      return item;
    }).toList();

    _localAudits[auditIdx] = audit.copyWith(items: updatedItems);
  }

  @override
  Future<CycleCountAuditEntity> reconcileAudit({
    required String auditId,
    required String userId,
    required String userName,
    required String callerPin,
    required String reconciliationNotes,
  }) async {
    return _synchronized(() async {
      if (!ConnectivityService.instance.isOnline) {
        throw Exception(
          'اعتماد الجرد يتطلب اتصالاً بالإنترنت لتأكيد رمز PIN وترحيل الفروقات إلى السجل السحابي.',
        );
      }
      if (callerPin.trim().length != 4) {
        throw Exception('رمز PIN غير صالح. يرجى إدخال رمز مكوّن من 4 أرقام.');
      }

      final auditIdx = _localAudits.indexWhere((a) => a.id == auditId);
      if (auditIdx < 0) {
        throw Exception('جلسة الجرد غير موجودة أو انتهت صلاحيتها.');
      }

      final audit = _localAudits[auditIdx];
      if (audit.status != AuditStatus.inProgress) {
        throw Exception('لا يمكن اعتماد جلسة جرد تمت تسويتها أو إلغاؤها.');
      }
      final discrepantItems =
          audit.items.where((it) => it.hasDiscrepancy).toList();

      // The server ledger is authoritative: post every variance before the
      // local cache is reconciled. A rejected PIN aborts the whole operation.
      for (final item in discrepantItems) {
        await service.adjustStock(
          userId: userId,
          callerPin: callerPin,
          productId: item.productId,
          qtyChange: item.varianceQty,
          reason:
              'تسوية جرد [${audit.auditNumber}]: ${reconciliationNotes.isNotEmpty ? reconciliationNotes : "موازنة المخزون الفعلي"}',
        );
      }

      // Execute bulk atomic stock updates in Drift after the server accepted.
      await db.transaction(() async {
        for (final item in discrepantItems) {
          await (db.update(db.cachedProducts)
                ..where((tbl) => tbl.id.equals(item.productId)))
              .write(CachedProductsCompanion(
            onHandQty: Value(item.physicalCount),
            availableQty: Value(item.physicalCount),
          ));
        }
      });

      final reconciledAudit = audit.copyWith(
        status: AuditStatus.reconciled,
        reconciledByUserId: userId,
        reconciledByName: userName,
        reconciledAt: DateTime.now(),
        reconciliationNotes: reconciliationNotes,
      );

      _localAudits[auditIdx] = reconciledAudit;
      return reconciledAudit;
    });
  }

  @override
  Future<List<CycleCountAuditEntity>> getAuditHistory({int limit = 20}) async {
    return _localAudits.take(limit).toList();
  }

  // ── 3. Multi-Location & Stock Transfers ────────────────────────────────────

  final List<StockTransferEntity> _localTransfers = [];

  @override
  Future<List<StockTransferEntity>> getTransfers() async {
    return List.unmodifiable(_localTransfers);
  }

  @override
  Future<StockTransferEntity> createTransfer({
    required StockTransferEntity transfer,
  }) async {
    _localTransfers.insert(0, transfer);
    return transfer;
  }

  @override
  Future<void> updateTransferStatus({
    required String transferId,
    required TransferStatus status,
    required String userId,
    required String userName,
  }) async {
    final idx = _localTransfers.indexWhere((t) => t.id == transferId);
    if (idx < 0) return;

    final existing = _localTransfers[idx];
    _localTransfers[idx] = existing.copyWith(
      status: status,
      approvedByUserId: status == TransferStatus.inTransit
          ? userId
          : existing.approvedByUserId,
      approvedByName: status == TransferStatus.inTransit
          ? userName
          : existing.approvedByName,
      completedAt: status == TransferStatus.completed
          ? DateTime.now()
          : existing.completedAt,
    );
  }

  // ── 4. Low Stock Intelligence & Replenishment ──────────────────────────────

  @override
  Future<List<ProductEntity>> getLowStockProducts() async {
    final cached = await db.getAllProducts();

    return cached
        .map((p) => ProductEntity(
              id: p.id,
              nameAr: p.nameAr,
              nameFr: p.nameFr,
              category: p.category,
              unit: p.unit,
              packSize: p.packSize,
              lastUnitCostCentimes: p.lastUnitCostCentimes,
              onHandQty: p.onHandQty,
              availableQty: p.availableQty,
              active: p.active,
              photoUrl: p.photoUrl,
              prices: const [],
              barcodes: (p.barcodesJson.replaceAll(RegExp(r'[\[\]"]'), '').split(',')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList()),
              // Business rules thresholds
              safetyStockLevel: 5,
              reorderPoint: 10,
              maxCapacity: 50,
              weightedAverageCostCentimes: p.lastUnitCostCentimes,
            ))
        .where((p) => p.isLowStock || p.isCritical || p.isOutOfStock)
        .toList();
  }

  @override
  Future<PurchaseOrderEntity> generateDraftPOFromLowStock({
    required String supplierId,
    required String supplierName,
    required String createdById,
    required String createdByName,
    List<String>? selectedProductIds,
    Map<String, int>? quantityOverrides,
  }) async {
    final lowStock = await getLowStockProducts();

    final targetProducts = lowStock.where((p) {
      if (selectedProductIds != null && selectedProductIds.isNotEmpty) {
        return selectedProductIds.contains(p.id);
      }
      return true;
    }).toList();

    final items = targetProducts
        .map((p) {
          final suggested = p.suggestedReplenishmentQty > 0
              ? p.suggestedReplenishmentQty
              : (p.packSize * 5);
          final override = quantityOverrides?[p.id];
          final replenishmentQty = override ?? suggested;

          return PurchaseOrderItemEntity(
            id: _uuid.v4(),
            productId: p.id,
            productName: p.nameAr,
            unit: p.unit,
            orderedQty: replenishmentQty,
            receivedQty: 0,
            unitCostCentimes: p.lastUnitCostCentimes,
            sellingPriceCentimes: p.lastUnitCostCentimes > 0
                ? (p.lastUnitCostCentimes * 1.25).round()
                : 0,
            notes:
                'إعادة تزويد آلي (نقطة الطلب: ${p.reorderPoint}، المخزون الحالي: ${p.availableQty})',
          );
        })
        .where((it) => it.orderedQty > 0)
        .toList();

    final po = PurchaseOrderEntity(
      id: _uuid.v4(),
      poNumber:
          'PO-${DateTime.now().year}-${DateTime.now().millisecondsSinceEpoch % 100000}',
      supplierId: supplierId,
      supplierName: supplierName,
      status: PurchaseOrderStatus.draft,
      orderDate: DateTime.now(),
      createdByUserId: createdById,
      createdByName: createdByName,
      notes: 'مسودة أمر شراء تم إنشاؤها تلقائياً للمنتجات ذات المخزون المنخفض',
      items: items,
    );

    _localPurchaseOrders.insert(0, po);
    return po;
  }

  // ── 5. Purchase Orders & Goods Receiving Note (GRN) ────────────────────────

  final List<PurchaseOrderEntity> _localPurchaseOrders = [];

  @override
  Future<List<PurchaseOrderEntity>> getPurchaseOrders() async {
    return List.unmodifiable(_localPurchaseOrders);
  }

  @override
  Future<PurchaseOrderEntity> createPurchaseOrder({
    required PurchaseOrderEntity purchaseOrder,
  }) async {
    _localPurchaseOrders.insert(0, purchaseOrder);
    return purchaseOrder;
  }

  @override
  Future<void> receiveGoodsNote({
    required String poId,
    required List<Map<String, dynamic>> receivedItems,
    required String userId,
    required String userName,
    required String callerPin,
    String? locationId,
  }) async {
    return _synchronized(() async {
      if (!ConnectivityService.instance.isOnline) {
        throw Exception(
          'استلام أمر الشراء يتطلب اتصالاً بالإنترنت لتأكيد رمز PIN وترحيل الكميات للمخزون.',
        );
      }
      if (callerPin.trim().length != 4) {
        throw Exception('رمز PIN غير صالح. يرجى إدخال رمز مكوّن من 4 أرقام.');
      }

      final poIdx = _localPurchaseOrders.indexWhere((p) => p.id == poId);
      if (poIdx < 0) {
        throw Exception('أمر الشراء غير موجود.');
      }

      final po = _localPurchaseOrders[poIdx];
      if (po.isFullyReceived || po.isCancelled) {
        throw Exception('لا يمكن استلام أمر شراء مكتمل أو ملغى.');
      }
      if (po.isDraft) {
        throw Exception(
          'أرسل أمر الشراء إلى المورد أولاً قبل تسجيل استلام البضاعة.',
        );
      }

      // Resolve and clamp quantities against the remaining PO quantity. Each
      // accepted line is posted to the authoritative stock ledger first.
      final acceptedItems = <Map<String, dynamic>>[];
      for (final rec in receivedItems) {
        final productId = rec['product_id'] as String;
        final poItem =
            po.items.where((it) => it.productId == productId).firstOrNull;
        if (poItem == null) continue;

        final requestedQty = (rec['qty_received'] as num?)?.toInt() ?? 0;
        final qtyReceived = requestedQty.clamp(0, poItem.remainingQty);
        if (qtyReceived <= 0) continue;

        final unitCost = (rec['unit_cost_centimes'] as num?)?.toInt() ??
            poItem.unitCostCentimes;

        await service.adjustStock(
          userId: userId,
          callerPin: callerPin,
          productId: productId,
          qtyChange: qtyReceived,
          reason:
              'استلام أمر شراء [${po.poNumber}] من المورد ${po.supplierName}',
        );

        acceptedItems.add({
          ...rec,
          'product_id': productId,
          'qty_received': qtyReceived,
          'unit_cost_centimes': unitCost,
        });
      }

      if (acceptedItems.isEmpty) {
        throw Exception('لم يتم إدخال أي كمية صالحة للاستلام.');
      }

      await db.transaction(() async {
        for (final rec in acceptedItems) {
          final productId = rec['product_id'] as String;
          final qtyReceived = (rec['qty_received'] as num).toInt();
          final unitCost = (rec['unit_cost_centimes'] as num).toInt();

          final cached = await (db.select(db.cachedProducts)
                ..where((tbl) => tbl.id.equals(productId)))
              .getSingleOrNull();

          if (cached != null) {
            final oldQty = cached.onHandQty;
            final oldWAC = cached.lastUnitCostCentimes;

            // Moving Weighted Average Cost (WAC) formula:
            // newWAC = ((existingOnHand * currentWAC) + (receivedQty * unitCost)) / (existingOnHand + receivedQty)
            final totalExistingValuation = oldQty * oldWAC;
            final totalNewValuation = qtyReceived * unitCost;
            final newTotalQty = oldQty + qtyReceived;
            final dynamicWAC = newTotalQty > 0
                ? ((totalExistingValuation + totalNewValuation) / newTotalQty)
                    .round()
                : unitCost;

            await (db.update(db.cachedProducts)
                  ..where((tbl) => tbl.id.equals(productId)))
                .write(CachedProductsCompanion(
              onHandQty:
                  Value((cached.onHandQty + qtyReceived).clamp(0, 9999999)),
              availableQty:
                  Value((cached.availableQty + qtyReceived).clamp(0, 9999999)),
              lastUnitCostCentimes: Value(dynamicWAC),
            ));
          }
        }
      });

      // Update PO items received counts and determine new PO status
      final updatedItems = po.items.map((it) {
        final rec = acceptedItems.firstWhere(
          (r) => r['product_id'] == it.productId,
          orElse: () => const {},
        );
        if (rec.isNotEmpty) {
          final addedQty = (rec['qty_received'] as num).toInt();
          return it.copyWith(
            receivedQty: it.receivedQty + addedQty,
            unitCostCentimes: (rec['unit_cost_centimes'] as num?)?.toInt() ??
                it.unitCostCentimes,
            batchNumber: rec['batch_number'] as String? ?? it.batchNumber,
            expiryDate: rec['expiry_date'] != null
                ? DateTime.tryParse(rec['expiry_date'] as String)
                : it.expiryDate,
          );
        }
        return it;
      }).toList();

      final allFulfilled = updatedItems.every((it) => it.isFullyReceived);
      final anyReceived = updatedItems.any((it) => it.receivedQty > 0);

      final nextStatus = allFulfilled
          ? PurchaseOrderStatus.fullyReceived
          : (anyReceived ? PurchaseOrderStatus.partiallyReceived : po.status);

      _localPurchaseOrders[poIdx] = po.copyWith(
        status: nextStatus,
        completedDate: allFulfilled ? DateTime.now() : po.completedDate,
        items: updatedItems,
      );
    });
  }

  @override
  Future<PurchaseOrderEntity> updatePurchaseOrderStatus({
    required String poId,
    required PurchaseOrderStatus status,
    required String userId,
    required String userName,
  }) async {
    final poIdx = _localPurchaseOrders.indexWhere((p) => p.id == poId);
    if (poIdx < 0) throw Exception('أمر الشراء غير موجود.');

    final po = _localPurchaseOrders[poIdx];
    if (po.isFullyReceived || po.isCancelled) {
      throw Exception('لا يمكن تعديل حالة أمر شراء مكتمل أو ملغى.');
    }
    if (status == PurchaseOrderStatus.partiallyReceived ||
        status == PurchaseOrderStatus.fullyReceived) {
      throw Exception(
        'حالات الاستلام تُحدَّث تلقائياً عند تسجيل استلام البضاعة (GRN).',
      );
    }
    if (status == PurchaseOrderStatus.ordered && !po.isDraft) {
      throw Exception(
        'أمر الشراء أُرسل إلى المورد مسبقاً ولا يمكن إعادة إرساله.',
      );
    }

    final updated = po.copyWith(
      status: status,
      completedDate:
          status == PurchaseOrderStatus.cancelled ? DateTime.now() : null,
    );
    _localPurchaseOrders[poIdx] = updated;

    // Keep the newest activity at the top for the manager workspace.
    _localPurchaseOrders.sort((a, b) => b.orderDate.compareTo(a.orderDate));
    return updated;
  }
}
