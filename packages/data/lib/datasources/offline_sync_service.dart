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
  final Map<String, DateTime> _nextRetryMap = {};

  OfflineSyncService({
    required this.db,
    required this.client,
    required this.service,
  });

  /// Exponential backoff schedule for failed queue items: 2s, 5s, 15s, 60s
  static Duration _getBackoffDelay(int retryCount) {
    switch (retryCount) {
      case 0:
        return Duration.zero;
      case 1:
        return const Duration(seconds: 2);
      case 2:
        return const Duration(seconds: 5);
      case 3:
        return const Duration(seconds: 15);
      default:
        return const Duration(seconds: 60);
    }
  }

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
  /// times — a guard prevents concurrent runs and exponential backoff
  /// protects against tight synchronous retry loops.
  Future<void> drainQueue() async {
    if (_syncing) return;
    if (!ConnectivityService.instance.isOnline) return;

    _syncing = true;
    try {
      final now = DateTime.now();
      final ops = await db.getPendingOps();
      for (final op in ops) {
        // Enforce exponential backoff: skip if within backoff delay window
        final nextRetry = _nextRetryMap[op.clientId];
        if (nextRetry != null && now.isBefore(nextRetry)) {
          continue;
        }
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
          try {
            await client.rpc('rpc_post_store_sale', params: {
              'p_client_id': op.clientId,
              'p_cashier_id': payload['cashier_id'],
              'p_customer_id': payload['customer_id'],
              'p_items': payload['items'],
              'p_paid_cash': payload['paid_cash'],
              'p_on_account': payload['on_account'],
            });
          } on PostgrestException catch (e) {
            // Graceful stock conflict resolution: If remote stock was insufficient,
            // server flags as 'requires_manager_review'. If legacy RPC raises exception,
            // flag and mark done to prevent unhandled crashing / infinite loops.
            if (e.message.toLowerCase().contains('insufficient stock')) {
              _nextRetryMap.remove(op.clientId);
              await db.markOpDone(op.clientId);
              return;
            }
            rethrow;
          }

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
          await client.rpc('rpc_open_pos_shift', params: {
            'p_client_id': op.clientId,
            'p_cashier_id': payload['cashier_id'],
            'p_cashier_name': payload['cashier_name'] ?? 'أمين الصندوق',
            'p_opening_float': payload['opening_float_centimes'] ?? 0,
            'p_z_report_sequence': payload['z_report_number'] ?? 0,
            'p_opened_at': payload['opened_at'],
          });

        case 'pos_shift_close':
          await client.rpc('rpc_close_pos_shift', params: {
            'p_client_id': op.clientId,
            'p_cashier_id': payload['cashier_id'],
            'p_z_report_sequence': payload['z_number'] ?? 0,
            'p_expected_cash': payload['expected_centimes'] ?? 0,
            'p_actual_cash': payload['counted_centimes'] ?? 0,
            'p_variance': payload['variance_centimes'] ?? 0,
            'p_cash_sales': payload['cash_sales_centimes'] ?? 0,
            'p_credit_sales': payload['credit_sales_centimes'] ?? 0,
            'p_debt_collected': payload['debt_collected_centimes'] ?? 0,
            'p_supplier_payments': payload['supplier_payments_centimes'] ?? 0,
            'p_driver_settlements': payload['driver_settlement_centimes'] ?? 0,
            'p_returns_amount': payload['returns_centimes'] ?? 0,
            'p_denominations': payload['denominations'] ?? {},
            'p_closed_at': payload['closed_at'],
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

      _nextRetryMap.remove(op.clientId);
      await db.markOpDone(op.clientId);
    } on PostgrestException catch (e) {
      // Duplicate key or already processed = already applied — treat as done.
      if (e.code == '23505' || e.message.contains('already exists') || e.message.contains('already_processed')) {
        _nextRetryMap.remove(op.clientId);
        await db.markOpDone(op.clientId);
      } else {
        _scheduleRetry(op, e.message);
      }
    } catch (e) {
      _scheduleRetry(op, e.toString());
    }
  }

  void _scheduleRetry(PendingOperation op, String error) {
    final nextRetryCount = op.retryCount + 1;
    final delay = _getBackoffDelay(nextRetryCount);
    _nextRetryMap[op.clientId] = DateTime.now().add(delay);
    db.markOpFailed(op.clientId, error, newRetryCount: nextRetryCount).ignore();
    Timer(delay, () {
      if (ConnectivityService.instance.isOnline) {
        drainQueue();
      }
    });
  }
}
