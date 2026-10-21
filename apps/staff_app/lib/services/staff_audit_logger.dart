import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:domain/domain.dart';

/// Centralized service to log high-level staff access, authentication,
/// terminal shifts, and administrative events to [audit_log].
class StaffAuditLogger {
  final SupabaseClient client;

  const StaffAuditLogger(this.client);

  /// Log staff login event
  Future<void> logLogin({
    required UserEntity user,
    String? deviceName,
  }) async {
    try {
      await client.from('audit_log').insert({
        'user_id': user.id,
        'action': 'STAFF_LOGIN',
        'target_table': 'users',
        'target_id': user.id,
        'after_state': {
          'user_id': user.id,
          'name': user.name,
          'phone': user.phone,
          'role': user.role.name,
          'device': deviceName ?? 'Terminal',
          'timestamp': DateTime.now().toIso8601String(),
        },
      });
    } catch (e) {
      debugPrint('Failed to log staff login: $e');
    }
  }

  /// Log staff logout event
  Future<void> logLogout({
    required UserEntity user,
    String? reason,
  }) async {
    try {
      await client.from('audit_log').insert({
        'user_id': user.id,
        'action': 'STAFF_LOGOUT',
        'target_table': 'users',
        'target_id': user.id,
        'after_state': {
          'user_id': user.id,
          'name': user.name,
          'phone': user.phone,
          'role': user.role.name,
          'reason': reason ?? 'User clicked logout',
          'timestamp': DateTime.now().toIso8601String(),
        },
      });
    } catch (e) {
      debugPrint('Failed to log staff logout: $e');
    }
  }

  /// Log cashier terminal switch
  Future<void> logCashierSwitch({
    required UserEntity previousCashier,
    required UserEntity newCashier,
  }) async {
    try {
      await client.from('audit_log').insert({
        'user_id': newCashier.id,
        'action': 'CASHIER_SWITCH',
        'target_table': 'users',
        'target_id': newCashier.id,
        'before_state': {
          'previous_cashier_id': previousCashier.id,
          'previous_cashier_name': previousCashier.name,
        },
        'after_state': {
          'new_cashier_id': newCashier.id,
          'new_cashier_name': newCashier.name,
          'switched_at': DateTime.now().toIso8601String(),
        },
      });
    } catch (e) {
      debugPrint('Failed to log cashier switch: $e');
    }
  }

  /// Log shift opened by cashier into structured pos_shifts
  Future<void> logShiftOpened({
    required String cashierId,
    required String cashierName,
    required int openingFloatCentimes,
    required int zReportNumber,
  }) async {
    try {
      await client.rpc('rpc_open_pos_shift', params: {
        'p_client_id': null,
        'p_cashier_id': cashierId,
        'p_cashier_name': cashierName,
        'p_opening_float': openingFloatCentimes,
        'p_z_report_sequence': zReportNumber,
        'p_opened_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Failed to log shift open: $e');
    }
  }

  /// Log shift closed with Z-Report into structured pos_shifts
  Future<void> logShiftClosed({
    required String cashierId,
    required String cashierName,
    required int zNumber,
    required int expectedCentimes,
    required int countedCentimes,
    required int varianceCentimes,
    required int cashSalesCentimes,
    required int creditSalesCentimes,
    required int debtCollectedCentimes,
    required int supplierPaymentsCentimes,
    int driverSettlementCentimes = 0,
    int returnsCentimes = 0,
    Map<int, int>? denominations,
  }) async {
    try {
      await client.rpc('rpc_close_pos_shift', params: {
        'p_client_id': null,
        'p_cashier_id': cashierId,
        'p_z_report_sequence': zNumber,
        'p_expected_cash': expectedCentimes,
        'p_actual_cash': countedCentimes,
        'p_variance': varianceCentimes,
        'p_cash_sales': cashSalesCentimes,
        'p_credit_sales': creditSalesCentimes,
        'p_debt_collected': debtCollectedCentimes,
        'p_supplier_payments': supplierPaymentsCentimes,
        'p_driver_settlements': driverSettlementCentimes,
        'p_returns_amount': returnsCentimes,
        'p_denominations': denominations ?? {},
        'p_closed_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Failed to log shift close: $e');
    }
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
    try {
      await client.from('audit_log').insert({
        'user_id': cashierId,
        'action': 'DRIVER_SETTLEMENT',
        'target_table': 'settlements',
        'target_id': settlementId,
        'after_state': {
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
      });
    } catch (e) {
      debugPrint('Failed to log driver settlement: $e');
    }
  }
}
