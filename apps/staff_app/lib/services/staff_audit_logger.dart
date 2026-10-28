import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:domain/domain.dart';

/// Centralized service to log high-level staff access, authentication,
/// terminal shifts, and administrative events.
///
/// Writes go through `rpc_log_staff_event`; direct `audit_log` inserts are
/// revoked from the API roles in schema/005_phase0_security.sql.
class StaffAuditLogger {
  final SupabaseClient client;

  const StaffAuditLogger(this.client);

  Future<void> _log({
    required String action,
    required String targetTable,
    String? targetId,
    Map<String, dynamic>? beforeState,
    Map<String, dynamic>? afterState,
  }) async {
    try {
      await client.rpc('rpc_log_staff_event', params: {
        'p_action': action,
        'p_target_table': targetTable,
        'p_target_id': targetId,
        'p_before_state': beforeState,
        'p_after_state': afterState,
      });
    } catch (e) {
      debugPrint('Failed to log $action: $e');
    }
  }

  /// Log staff login event
  Future<void> logLogin({
    required UserEntity user,
    String? deviceName,
  }) async {
    await _log(
      action: 'STAFF_LOGIN',
      targetTable: 'users',
      targetId: user.id,
      afterState: {
        'user_id': user.id,
        'name': user.name,
        'phone': user.phone,
        'role': user.role.name,
        'device': deviceName ?? 'Terminal',
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  /// Log staff logout event
  Future<void> logLogout({
    required UserEntity user,
    String? reason,
  }) async {
    await _log(
      action: 'STAFF_LOGOUT',
      targetTable: 'users',
      targetId: user.id,
      afterState: {
        'user_id': user.id,
        'name': user.name,
        'phone': user.phone,
        'role': user.role.name,
        'reason': reason ?? 'User clicked logout',
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  /// Log cashier terminal switch
  Future<void> logCashierSwitch({
    required UserEntity previousCashier,
    required UserEntity newCashier,
  }) async {
    await _log(
      action: 'CASHIER_SWITCH',
      targetTable: 'users',
      targetId: newCashier.id,
      beforeState: {
        'previous_cashier_id': previousCashier.id,
        'previous_cashier_name': previousCashier.name,
      },
      afterState: {
        'new_cashier_id': newCashier.id,
        'new_cashier_name': newCashier.name,
        'switched_at': DateTime.now().toIso8601String(),
      },
    );
  }

  /// Log driver delivery cash settlement
  Future<void> logDriverSettlement({
    required String cashierId,
    required String cashierName,
    required String driverId,
    required String driverName,
    required String settlementId,
    required int expectedCentimes,
    required int countedCentimes,
    required int differenceCentimes,
    required String status,
    String? notes,
  }) async {
    await _log(
      action: 'DRIVER_SETTLEMENT',
      targetTable: 'settlements',
      targetId: settlementId,
      afterState: {
        'settlement_id': settlementId,
        'cashier_id': cashierId,
        'cashier_name': cashierName,
        'driver_id': driverId,
        'driver_name': driverName,
        'expected_centimes': expectedCentimes,
        'counted_centimes': countedCentimes,
        'difference_centimes': differenceCentimes,
        'status': status,
        'notes': notes,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }
}
