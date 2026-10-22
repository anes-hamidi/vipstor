import 'dart:convert';

import 'package:domain/domain.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/customer_models.dart';

/// Durable JSON cache for everything the customer app must show offline.
///
/// SQLite (drift) already mirrors the catalogue for the repository layer; this
/// store adds the pieces drift does not track (orders, wallet, pending checkout,
/// affinity) plus an instant-paint catalogue snapshot for cold starts.
class CustomerLocalStore {
  CustomerLocalStore([this._prefs]);

  SharedPreferences? _prefs;

  static const _kCatalog = 'customer.catalog.v2';
  static const _kOrders = 'customer.orders.v2';
  static const _kPending = 'customer.pending_orders.v2';
  static const _kWallet = 'customer.wallet.v2';
  static const _kAffinity = 'customer.affinity.v2';
  static const _kCart = 'customer.cart.v2';

  SharedPreferences? get prefs => _prefs;

  Future<SharedPreferences?> _ensure() async {
    if (_prefs != null) return _prefs;
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
    return _prefs;
  }

  Future<Map<String, dynamic>?> _readJson(String key) async {
    final prefs = await _ensure();
    final raw = prefs?.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? decoded.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeJson(String key, Map<String, dynamic> value) async {
    final prefs = await _ensure();
    try {
      await prefs?.setString(key, jsonEncode(value));
    } catch (_) {
      // Cache write failures are never fatal.
    }
  }

  // ── Catalogue ─────────────────────────────────────────────────────────────

  Future<CatalogSnapshot?> readCatalog() async {
    final j = await _readJson(_kCatalog);
    if (j == null) return null;
    try {
      final products = (j['products'] as List? ?? [])
          .map((p) => productFromJson((p as Map).cast<String, dynamic>()))
          .toList();
      if (products.isEmpty) return null;
      return CatalogSnapshot(
        products: products,
        syncedAt: DateTime.tryParse(j['syncedAt'] as String? ?? ''),
        isOffline: false,
        affinity: await readAffinity(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> writeCatalog(CatalogSnapshot snapshot) => _writeJson(_kCatalog, {
        'syncedAt': snapshot.syncedAt?.toIso8601String(),
        'products': snapshot.products.map(productToJson).toList(),
      });

  // ── Orders ────────────────────────────────────────────────────────────────

  Future<OrdersSnapshot?> readOrders() async {
    final j = await _readJson(_kOrders);
    if (j == null) return null;
    try {
      final orders = (j['orders'] as List? ?? [])
          .map((o) => orderFromJson((o as Map).cast<String, dynamic>()))
          .toList();
      return OrdersSnapshot(
        customerId: j['customerId'] as String?,
        orders: orders,
        fetchedAt: DateTime.tryParse(j['fetchedAt'] as String? ?? ''),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> writeOrders(OrdersSnapshot snapshot) => _writeJson(_kOrders, {
        'customerId': snapshot.customerId,
        'fetchedAt': snapshot.fetchedAt?.toIso8601String(),
        'orders': snapshot.orders.map(orderToJson).toList(),
      });

  // ── Pending checkout ──────────────────────────────────────────────────────

  Future<List<PendingOrder>> readPendingOrders() async {
    final j = await _readJson(_kPending);
    if (j == null) return const [];
    try {
      return (j['items'] as List? ?? [])
          .map((i) => PendingOrder.fromJson((i as Map).cast<String, dynamic>()))
          .where((o) => o.clientId.isNotEmpty && o.items.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> writePendingOrders(List<PendingOrder> orders) =>
      _writeJson(_kPending, {
        'items': orders.map((o) => o.toJson()).toList(),
      });

  Future<void> upsertPendingOrder(PendingOrder order) async {
    final current = await readPendingOrders();
    final next = [
      order,
      ...current.where((o) => o.clientId != order.clientId),
    ];
    await writePendingOrders(next);
  }

  Future<void> removePendingOrder(String clientId) async {
    final current = await readPendingOrders();
    await writePendingOrders(
      current.where((o) => o.clientId != clientId).toList(),
    );
  }

  Future<void> markPendingError(String clientId, String error) async {
    final current = await readPendingOrders();
    var changed = false;
    final next = current.map((o) {
      if (o.clientId != clientId) return o;
      changed = true;
      return o.copyWith(lastError: error);
    }).toList();
    if (changed) await writePendingOrders(next);
  }

  // ── Wallet ────────────────────────────────────────────────────────────────

  Future<WalletSnapshot?> readWallet() async {
    final j = await _readJson(_kWallet);
    if (j == null) return null;
    try {
      return WalletSnapshot(
        customerId: j['customerId'] as String?,
        customerName: j['customerName'] as String? ?? '',
        creditLimitCentimes:
            (j['creditLimitCentimes'] as num?)?.toInt() ?? 0,
        currentDebtCentimes:
            (j['currentDebtCentimes'] as num?)?.toInt() ?? 0,
        ledger: (j['ledger'] as List? ?? [])
            .map((e) => ledgerFromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        unpaidOrders: (j['unpaidOrders'] as List? ?? [])
            .map((e) => unpaidOrderFromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        fetchedAt: DateTime.tryParse(j['fetchedAt'] as String? ?? ''),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> writeWallet(WalletSnapshot snapshot) => _writeJson(_kWallet, {
        'customerId': snapshot.customerId,
        'customerName': snapshot.customerName,
        'creditLimitCentimes': snapshot.creditLimitCentimes,
        'currentDebtCentimes': snapshot.currentDebtCentimes,
        'fetchedAt': snapshot.fetchedAt?.toIso8601String(),
        'ledger': snapshot.ledger.map(ledgerToJson).toList(),
        'unpaidOrders': snapshot.unpaidOrders.map(unpaidOrderToJson).toList(),
      });

  // ── Purchase affinity (smart "recommended" ordering) ─────────────────────

  Future<Map<String, int>> readAffinity() async {
    final j = await _readJson(_kAffinity);
    if (j == null) return {};
    final raw = j['counts'];
    if (raw is! Map) return {};
    final result = <String, int>{};
    raw.forEach((key, value) {
      if (key is String && value is num) result[key] = value.toInt();
    });
    return result;
  }

  Future<void> recordOrderAffinity(List<OrderEntity> orders) async {
    if (orders.isEmpty) return;
    final j = await _readJson(_kAffinity);
    final counts = <String, int>{};
    if (j != null && j['counts'] is Map) {
      (j['counts'] as Map).forEach((key, value) {
        if (key is String && value is num) counts[key] = value.toInt();
      });
    }
    final seen = <String>{
      ...((j?['seenOrders'] as List?) ?? const []).cast<String>(),
    };

    for (final order in orders) {
      if (seen.contains(order.id)) continue;
      seen.add(order.id);
      for (final item in order.items) {
        if (item.productId.isEmpty) continue;
        counts[item.productId] = (counts[item.productId] ?? 0) + 1;
      }
    }

    // Keep the maps bounded so prefs does not grow forever.
    if (counts.length > 600) {
      final sorted = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      counts
        ..clear()
        ..addEntries(sorted.take(400));
    }
    final seenList = seen.toList();
    final boundedSeen = seenList.length > 400
        ? seenList.sublist(seenList.length - 400)
        : seenList;

    await _writeJson(_kAffinity, {
      'counts': counts,
      'seenOrders': boundedSeen,
    });
  }

  // ── Cart (raw JSON so this layer stays independent from widgets) ─────────-

  String? readCartJsonSync() => _prefs?.getString(_kCart);

  Future<String?> readCartJson() async {
    final prefs = await _ensure();
    return prefs?.getString(_kCart);
  }

  Future<void> writeCartJson(String json) async {
    final prefs = await _ensure();
    try {
      await prefs?.setString(_kCart, json);
    } catch (_) {}
  }

  Future<void> clearCart() async {
    final prefs = await _ensure();
    try {
      await prefs?.remove(_kCart);
    } catch (_) {}
  }
}
