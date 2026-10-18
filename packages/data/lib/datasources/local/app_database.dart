import 'package:drift/drift.dart';
import 'connection/connection.dart';

part 'app_database.g.dart';

// ─── Table definitions ────────────────────────────────────────────────────────

/// Cached products (refreshed from remote on login + every 5 min online).
class CachedProducts extends Table {
  TextColumn get id => text()();
  TextColumn get nameAr => text()();
  TextColumn get nameFr => text()();
  TextColumn get category => text()();
  TextColumn get unit => text()();
  IntColumn get packSize => integer()();
  IntColumn get lastUnitCostCentimes => integer()();
  IntColumn get onHandQty => integer()();
  IntColumn get availableQty => integer()();
  BoolColumn get active => boolean()();
  TextColumn get photoUrl => text().nullable()();
  /// JSON-encoded List<{id,tier,min_qty,price}>
  TextColumn get pricesJson => text()();
  /// JSON-encoded List<String>
  TextColumn get barcodesJson => text()();
  DateTimeColumn get syncedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Cached customers for cashier lookup.
class CachedCustomers extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get name => text()();
  TextColumn get phone => text()();
  IntColumn get creditLimitCentimes => integer()();
  IntColumn get currentDebtCentimes => integer()();
  TextColumn get priceTier => text()();
  TextColumn get wilaya => text().nullable()();
  TextColumn get commune => text().nullable()();
  TextColumn get addressText => text().nullable()();
  DateTimeColumn get syncedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Pending writes that must be replayed to Supabase when connectivity returns.
/// Every entry is idempotent via clientId.
class PendingOperations extends Table {
  /// UUID generated on-device before the operation — used as idempotency key.
  TextColumn get clientId => text()();
  /// 'pos_sale' | 'delivery' | 'debt_payment'
  TextColumn get operationType => text()();
  /// Full JSON payload matching the corresponding RPC parameters.
  TextColumn get payloadJson => text()();
  DateTimeColumn get createdAt => dateTime()();
  /// 'pending' | 'syncing' | 'failed'
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column> get primaryKey => {clientId};
}

/// Stores the last-sync timestamps so we can do incremental syncs.
class SyncMeta extends Table {
  TextColumn get entity => text()(); // 'products' | 'customers'
  DateTimeColumn get lastSyncedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {entity};
}

// ─── Database ────────────────────────────────────────────────────────────────

@DriftDatabase(tables: [CachedProducts, CachedCustomers, PendingOperations, SyncMeta])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(openAppDbConnection());

  @override
  int get schemaVersion => 1;

  // ── Products DAO ──────────────────────────────────────────────────────────

  Future<List<CachedProduct>> getAllProducts() =>
      select(cachedProducts).get();

  Future<CachedProduct?> getProductByBarcode(String barcode) async {
    // Search JSON array in barcodesJson for the barcode string
    final all = await select(cachedProducts).get();
    for (final p in all) {
      if (p.barcodesJson.contains('"$barcode"')) return p;
    }
    return null;
  }

  Future<void> upsertProducts(List<CachedProductsCompanion> rows) =>
      batch((b) => b.insertAllOnConflictUpdate(cachedProducts, rows));

  Future<void> clearProducts() => delete(cachedProducts).go();

  // ── Customers DAO ─────────────────────────────────────────────────────────

  Future<List<CachedCustomer>> getAllCustomers() =>
      select(cachedCustomers).get();

  Future<List<CachedCustomer>> searchCustomers(String query) {
    final q = query.toLowerCase();
    return (select(cachedCustomers)
          ..where((c) => c.name.lower().contains(q) | c.phone.contains(q)))
        .get();
  }

  Future<void> upsertCustomers(List<CachedCustomersCompanion> rows) =>
      batch((b) => b.insertAllOnConflictUpdate(cachedCustomers, rows));

  Future<void> upsertCustomer(CachedCustomersCompanion row) =>
      into(cachedCustomers).insertOnConflictUpdate(row);

  // ── Pending operations DAO ────────────────────────────────────────────────

  Future<void> enqueuePendingOp(PendingOperationsCompanion op) =>
      into(pendingOperations).insertOnConflictUpdate(op);

  Future<List<PendingOperation>> getPendingOps() =>
      (select(pendingOperations)
            ..where((o) => o.status.isIn(['pending', 'failed']))
            ..orderBy([(o) => OrderingTerm.asc(o.createdAt)]))
          .get();

  Future<void> markOpSyncing(String clientId) => (update(pendingOperations)
        ..where((o) => o.clientId.equals(clientId)))
      .write(const PendingOperationsCompanion(status: Value('syncing')));

  Future<void> markOpDone(String clientId) =>
      (delete(pendingOperations)..where((o) => o.clientId.equals(clientId)))
          .go();

  Future<void> markOpFailed(String clientId, String error) =>
      (update(pendingOperations)..where((o) => o.clientId.equals(clientId)))
          .write(PendingOperationsCompanion(
        status: const Value('failed'),
        lastError: Value(error),
        retryCount: const Value.absent(),
      ));

  Future<int> countPendingOps() async {
    final count = pendingOperations.clientId.count();
    final q = selectOnly(pendingOperations)
      ..where(pendingOperations.status.isIn(['pending', 'failed']))
      ..addColumns([count]);
    final result = await q.getSingle();
    return result.read(count) ?? 0;
  }

  // ── SyncMeta ──────────────────────────────────────────────────────────────

  Future<DateTime?> getLastSync(String entity) async {
    final row = await (select(syncMeta)
          ..where((s) => s.entity.equals(entity)))
        .getSingleOrNull();
    return row?.lastSyncedAt;
  }

  Future<void> setLastSync(String entity, DateTime ts) =>
      into(syncMeta).insertOnConflictUpdate(
        SyncMetaCompanion(entity: Value(entity), lastSyncedAt: Value(ts)),
      );
}


