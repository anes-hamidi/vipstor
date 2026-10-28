import 'package:domain/domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../datasources/remote/supabase_service.dart';

class SettlementRepositoryImpl implements ISettlementRepository {
  final SupabaseClient client;
  final SupabaseService service;

  SettlementRepositoryImpl({required this.client, required this.service});

  @override
  Future<int> getDriverExpectedWallet(String driverId) async {
    final rows = await client
        .from('view_driver_wallet_balance')
        .select('current_wallet_balance')
        .eq('driver_id', driverId)
        .limit(1);

    if ((rows as List).isEmpty) {
      return 0;
    }

    return (rows.first['current_wallet_balance'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<List<WalletEntry>> getDriverWalletEntries(String driverId) async {
    final rows = await client
        .from('wallet_entries')
        .select()
        .eq('driver_id', driverId)
        .order('created_at', ascending: false);

    return (rows as List).map<WalletEntry>((row) {
      WalletEntryType type = WalletEntryType.collection;
      switch (row['type']) {
        case 'collection': type = WalletEntryType.collection; break;
        case 'handover': type = WalletEntryType.handover; break;
        case 'shortage': type = WalletEntryType.shortage; break;
        case 'overage': type = WalletEntryType.overage; break;
        case 'reversal': type = WalletEntryType.reversal; break;
      }

      return WalletEntry(
        id: row['id'] as String,
        driverId: row['driver_id'] as String,
        type: type,
        amountCentimes: (row['amount'] as num).toInt(),
        paymentId: row['payment_id'] as String?,
        settlementId: row['settlement_id'] as String?,
        clientId: row['client_id'] as String?,
        createdAt: DateTime.parse(row['created_at'] as String),
      );
    }).toList();
  }

  @override
  Future<List<DriverSettlementSummaryEntity>> getPendingDriverSettlements() async {
    try {
      final users = await client
          .from('users')
          .select('id, name, phone, role, active')
          .eq('role', 'driver')
          .eq('active', true);

      final balances = await client
          .from('view_driver_wallet_balance')
          .select('driver_id, current_wallet_balance');

      final balanceMap = <String, int>{};
      for (final b in (balances as List)) {
        final dId = b['driver_id'] as String;
        final bal = (b['current_wallet_balance'] as num?)?.toInt() ?? 0;
        balanceMap[dId] = bal;
      }

      final deliveredOrders = await client
          .from('orders')
          .select('driver_id, delivered_at')
          .eq('status', 'delivered');

      final ordersCountMap = <String, int>{};
      final lastDeliveredMap = <String, DateTime>{};
      for (final o in (deliveredOrders as List)) {
        final dId = o['driver_id'] as String?;
        if (dId == null) continue;
        ordersCountMap[dId] = (ordersCountMap[dId] ?? 0) + 1;
        final delStr = o['delivered_at'] as String?;
        if (delStr != null) {
          final dt = DateTime.tryParse(delStr);
          if (dt != null) {
            final cur = lastDeliveredMap[dId];
            if (cur == null || dt.isAfter(cur)) {
              lastDeliveredMap[dId] = dt;
            }
          }
        }
      }

      final results = <DriverSettlementSummaryEntity>[];
      for (final u in (users as List)) {
        final dId = u['id'] as String;
        final pendingBal = balanceMap[dId] ?? 0;
        final count = ordersCountMap[dId] ?? 0;
        results.add(DriverSettlementSummaryEntity(
          driverId: dId,
          driverName: u['name'] as String? ?? 'سائق',
          driverPhone: u['phone'] as String? ?? '',
          pendingCashCentimes: pendingBal,
          unsettledOrdersCount: count,
          lastDeliveredAt: lastDeliveredMap[dId],
        ));
      }

      results.sort((a, b) {
        if (a.pendingCashCentimes != b.pendingCashCentimes) {
          return b.pendingCashCentimes.compareTo(a.pendingCashCentimes);
        }
        return b.unsettledOrdersCount.compareTo(a.unsettledOrdersCount);
      });

      return results;
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<OrderEntity>> getDriverUnsettledOrders(String driverId) async {
    try {
      final rows = await client
          .from('orders')
          .select('''
            id,
            order_number,
            channel,
            customer_id,
            status,
            driver_id,
            cashier_id,
            delivery_address,
            total_amount,
            paid_amount,
            notes,
            created_at,
            order_items (
              id,
              product_id,
              quantity,
              unit_price,
              unit_cost,
              products ( name_ar, name_fr, unit )
            )
          ''')
          .eq('driver_id', driverId)
          .eq('status', 'delivered')
          .order('created_at', ascending: false);

      return (rows as List).map<OrderEntity>((row) {
        final itemsList = (row['order_items'] as List? ?? []).map((i) {
          final productMap = i['products'] as Map<String, dynamic>?;
          final name = productMap != null ? (productMap['name_ar'] ?? productMap['name_fr'] ?? '') : '';
          return OrderItemEntity(
            id: i['id'] as String,
            productId: i['product_id'] as String,
            productName: name,
            quantity: (i['quantity'] as num).toInt(),
            unitPriceCentimes: (i['unit_price'] as num).toInt(),
            unitCostCentimes: (i['unit_cost'] as num?)?.toInt() ?? 0,
            unit: productMap?['unit'] as String?,
          );
        }).toList();

        final deliveryAddr = row['delivery_address'] as Map<String, dynamic>?;

        return OrderEntity(
          id: row['id'] as String,
          orderNumber: (row['order_number'] as num?)?.toInt(),
          channel: row['channel'] == 'online' ? OrderChannel.online : OrderChannel.store,
          customerId: row['customer_id'] as String?,
          customerName: deliveryAddr?['customer_name'] ?? deliveryAddr?['store_name'],
          customerPhone: deliveryAddr?['customer_phone'] ?? deliveryAddr?['phone'],
          status: OrderStatus.delivered,
          driverId: row['driver_id'] as String?,
          totalAmountCentimes: (row['total_amount'] as num).toInt(),
          paidAmountCentimes: (row['paid_amount'] as num).toInt(),
          deliveryAddress: deliveryAddr,
          items: itemsList,
          createdAt: DateTime.parse(row['created_at'] as String),
          notes: row['notes'] as String?,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<SettlementEntity>> getRecentSettlements({String? driverId, int limit = 30}) async {
    try {
      var query = client.from('settlements').select();
      if (driverId != null) {
        query = query.eq('driver_id', driverId);
      }
      final rows = await query.order('created_at', ascending: false).limit(limit);

      final userIds = <String>{};
      for (final r in (rows as List)) {
        if (r['driver_id'] != null) userIds.add(r['driver_id'] as String);
        if (r['cashier_id'] != null) userIds.add(r['cashier_id'] as String);
      }

      final userNames = <String, String>{};
      if (userIds.isNotEmpty) {
        try {
          final users = await client.from('users').select('id, name').inFilter('id', userIds.toList());
          for (final u in (users as List)) {
            userNames[u['id'] as String] = u['name'] as String? ?? '';
          }
        } catch (_) {}
      }

      return (rows as List).map<SettlementEntity>((r) {
        final dId = r['driver_id'] as String;
        final cId = r['cashier_id'] as String;
        return SettlementEntity(
          id: r['id'] as String,
          driverId: dId,
          driverName: userNames[dId] ?? 'سائق',
          cashierId: cId,
          cashierName: userNames[cId] ?? 'أمين صندوق / مشرف',
          expectedAmountCentimes: (r['expected_amount'] as num).toInt(),
          countedAmountCentimes: (r['counted_amount'] as num).toInt(),
          differenceCentimes: (r['difference'] as num?)?.toInt() ??
              ((r['counted_amount'] as num).toInt() - (r['expected_amount'] as num).toInt()),
          status: r['status'] as String? ?? 'settled',
          notes: r['notes'] as String?,
          createdAt: DateTime.parse(r['created_at'] as String),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  String _requireUserId(String candidateId) {
    if (candidateId.trim().isEmpty) {
      throw StateError('missing authenticated user id');
    }
    return candidateId;
  }

  @override
  Future<SettlementEntity> settleDriverWallet({
    required String cashierId,
    required String driverId,
    required int countedAmountCentimes,
    String? notes,
  }) async {
    final effectiveCashierId = _requireUserId(cashierId);
    final effectiveDriverId = _requireUserId(driverId);
    final res = await service.settleDriverWallet(
      cashierId: effectiveCashierId,
      driverId: effectiveDriverId,
      countedCashCentimes: countedAmountCentimes,
      notes: notes,
    );

    final settlementId = res['settlement_id'] as String;
    final expected = (res['expected'] as num).toInt();
    final difference = (res['difference'] as num).toInt();
    final status = res['status'] as String;

    String driverName = 'سائق التوصيل';
    String cashierName = 'أمين الصندوق';
    try {
      final uRows = await client.from('users').select('id, name').inFilter('id', [effectiveDriverId, effectiveCashierId]);
      for (final u in (uRows as List)) {
        if (u['id'] == effectiveDriverId && u['name'] != null) driverName = u['name'] as String;
        if (u['id'] == effectiveCashierId && u['name'] != null) cashierName = u['name'] as String;
      }
    } catch (_) {}

    return SettlementEntity(
      id: settlementId,
      driverId: driverId,
      driverName: driverName,
      cashierId: cashierId,
      cashierName: cashierName,
      expectedAmountCentimes: expected,
      countedAmountCentimes: countedAmountCentimes,
      differenceCentimes: difference,
      status: status,
      notes: notes,
      createdAt: DateTime.now(),
    );
  }
}
