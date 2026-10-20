import 'dart:async';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'local/app_database.dart';
import 'local/connectivity_service.dart';
import 'remote/supabase_service.dart';

/// Drains [PendingOperations] by replaying each entry against the matching
/// Supabase RPC.  Called once on app start and again whenever connectivity
/// is restored.  Every entry carries a `client_id` so all RPCs are idempotent
/// — re-running a completed entry is safe.
class OfflineSyncService {
  final AppDatabase db;
  final SupabaseClient client;
  final SupabaseService service;

  bool _syncing = false;
  StreamSubscription<bool>? _connectivitySub;

  OfflineSyncService({
    required this.db,
    required this.client,
    required this.service,
  });

  /// Call once from the app bootstrapper (after Supabase init).
  void start() {
    // React to connectivity changes.
    _connectivitySub = ConnectivityService.instance.onStatusChange.listen((online) {
      if (online) drainQueue();
    });
    ConnectivityService.instance.startPolling(intervalSeconds: 15);

    // Try immediately on boot.
    drainQueue();
  }

  void dispose() {
    _connectivitySub?.cancel();
  }

  /// Tries to flush all pending / failed operations.  Safe to call multiple
  /// times — a guard prevents concurrent runs.
  Future<void> drainQueue() async {
    if (_syncing) return;
    if (!ConnectivityService.instance.isOnline) return;

    _syncing = true;
    try {
      final ops = await db.getPendingOps();
      for (final op in ops) {
        await _replayOp(op);
      }
    } finally {
      _syncing = false;
    }
  }

  Future<void> _replayOp(PendingOperation op) async {
    await db.markOpSyncing(op.clientId);
    try {
      final payload = jsonDecode(op.payloadJson) as Map<String, dynamic>;

      switch (op.operationType) {
        case 'pos_sale':
          await client.rpc('rpc_post_store_sale', params: {
            'p_client_id': op.clientId,
            'p_cashier_id': payload['cashier_id'],
            'p_customer_id': payload['customer_id'],
            'p_items': payload['items'],
            'p_paid_cash': payload['paid_cash'],
            'p_on_account': payload['on_account'],
          });

        case 'delivery':
          await service.recordOrderDelivery(
            driverId: payload['driver_id'] as String,
            orderId: payload['order_id'] as String,
            collectedCashCentimes: payload['collected_cash'] as int,
            clientId: op.clientId,
          );

        case 'debt_payment':
          await client.rpc('rpc_collect_customer_debt', params: {
            'p_client_id': op.clientId,
            'p_cashier_id': payload['cashier_id'],
            'p_customer_id': payload['customer_id'],
            'p_amount': payload['amount'],
            'p_method': payload['method'],
            'p_notes': payload['notes'],
          });

        case 'pos_shift_open':
          await client.from('audit_log').insert({
            'user_id': payload['cashier_id'],
            'action': 'SHIFT_OPENED',
            'target_table': 'settlements',
            'target_id': payload['cashier_id'],
            'after_state': {
              'client_id': op.clientId,
              'cashier_id': payload['cashier_id'],
              'cashier_name': payload['cashier_name'],
              'opening_float_centimes': payload['opening_float_centimes'],
              'z_report_number': payload['z_report_number'],
              'opened_at': payload['opened_at'],
              'synced_at': DateTime.now().toIso8601String(),
            },
          });

        case 'pos_shift_close':
          await client.from('audit_log').insert({
            'user_id': payload['cashier_id'],
            'action': 'SHIFT_CLOSED',
            'target_table': 'settlements',
            'target_id': payload['cashier_id'],
            'after_state': {
              'client_id': op.clientId,
              'cashier_id': payload['cashier_id'],
              'cashier_name': payload['cashier_name'],
              'z_number': payload['z_number'],
              'expected_centimes': payload['expected_centimes'],
              'counted_centimes': payload['counted_centimes'],
              'variance_centimes': payload['variance_centimes'],
              'cash_sales_centimes': payload['cash_sales_centimes'],
              'credit_sales_centimes': payload['credit_sales_centimes'],
              'debt_collected_centimes': payload['debt_collected_centimes'],
              'supplier_payments_centimes': payload['supplier_payments_centimes'],
              'driver_settlement_centimes': payload['driver_settlement_centimes'],
              'opened_at': payload['opened_at'],
              'closed_at': payload['closed_at'],
              'denominations': payload['denominations'],
              'synced_at': DateTime.now().toIso8601String(),
            },
          });

        case 'manager_purchase_post':
          final purchaseId = payload['purchase_id'] as String;
          final userId = payload['user_id'] as String;
          if (!purchaseId.startsWith('OFFLINE-')) {
            await service.postPurchase(
              purchaseId: purchaseId,
              userId: userId,
            );
          }

        case 'manager_supplier_payment':
          await client.from('supplier_ledger').insert({
            'supplier_id': payload['supplier_id'],
            'amount_change': -(payload['amount'] as int),
            'ref_type': 'payment',
            'ref_id': payload['purchase_id'] ?? op.clientId,
            'notes': payload['notes'] ?? 'سداد نقدي تم ترحيله بعد استعادة الاتصال',
            'created_by': payload['payer_user_id'],
          });

        case 'order_status_update':
          await client.from('orders').update({
            'status': payload['status'],
            if (payload['driver_id'] != null) 'driver_id': payload['driver_id'],
            if (payload['notes'] != null) 'notes': payload['notes'],
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', payload['order_id']);
      }

      await db.markOpDone(op.clientId);
    } on PostgrestException catch (e) {
      // Duplicate key = already applied — treat as done.
      if (e.code == '23505' || (e.message.contains('already exists'))) {
        await db.markOpDone(op.clientId);
      } else {
        await db.markOpFailed(op.clientId, e.message);
      }
    } catch (e) {
      await db.markOpFailed(op.clientId, e.toString());
    }
  }
}
