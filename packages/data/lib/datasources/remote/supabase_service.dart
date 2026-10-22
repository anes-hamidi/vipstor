import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  final SupabaseClient client;

  SupabaseService(this.client);

  /// Post Supplier Purchase Invoice
  Future<Map<String, dynamic>> postPurchase({
    required String purchaseId,
    required String userId,
  }) async {
    final response = await client.rpc('rpc_post_purchase', params: {
      'p_purchase_id': purchaseId,
      'p_user_id': userId,
    });
    return Map<String, dynamic>.from(response as Map);
  }

  /// Submit Customer Order (Server-side price and cost resolution with device authentication)
  Future<String> submitCustomerOrder({
    required String? clientId,
    required String? customerId,
    required Map<String, dynamic> address,
    required List<Map<String, dynamic>> items,
    String? deviceToken,
  }) async {
    final response = await client.rpc('rpc_submit_customer_order', params: {
      'p_client_id': clientId,
      'p_customer_id': customerId,
      'p_delivery_address': address,
      'p_items': items,
      if (deviceToken != null) 'p_device_token': deviceToken,
    });
    return response.toString();
  }

  /// Post Counter Sale
  Future<Map<String, dynamic>> postStoreSale({
    required String clientId,
    String? cashierId,
    String? customerId,
    required List<Map<String, dynamic>> items,
    required int paidCashCentimes,
    required int onAccountCentimes,
  }) async {
    final response = await client.rpc('rpc_post_store_sale', params: {
      'p_client_id': clientId,
      'p_cashier_id': cashierId,
      'p_customer_id': customerId,
      'p_items': items,
      'p_paid_cash': paidCashCentimes,
      'p_on_account': onAccountCentimes,
    });
    return Map<String, dynamic>.from(response as Map);
  }

  /// Confirm Online Order & Reserve Stock
  Future<Map<String, dynamic>> confirmOnlineOrder({
    required String orderId,
    required String cashierId,
    String? driverId,
  }) async {
    final response = await client.rpc('rpc_confirm_online_order', params: {
      'p_order_id': orderId,
      'p_cashier_id': cashierId,
      'p_driver_id': driverId,
    });
    return Map<String, dynamic>.from(response as Map);
  }

  /// Record Order Delivery & Driver Cash Collection (Idempotent)
  Future<Map<String, dynamic>> recordOrderDelivery({
    required String driverId,
    required String orderId,
    required int collectedCashCentimes,
    required String clientId,
  }) async {
    final response = await client.rpc('rpc_record_order_delivery', params: {
      'p_driver_id': driverId,
      'p_order_id': orderId,
      'p_collected_cash': collectedCashCentimes,
      'p_client_id': clientId,
    });
    return Map<String, dynamic>.from(response as Map);
  }

  /// End-of-Day Driver Cash Settlement
  Future<Map<String, dynamic>> settleDriverWallet({
    required String cashierId,
    required String driverId,
    required int countedCashCentimes,
    String? notes,
  }) async {
    final response = await client.rpc('rpc_settle_driver_wallet', params: {
      'p_cashier_id': cashierId,
      'p_driver_id': driverId,
      'p_counted_cash': countedCashCentimes,
      'p_notes': notes,
    });
    return Map<String, dynamic>.from(response as Map);
  }

  /// Adjust Stock
  Future<Map<String, dynamic>> adjustStock({
    required String userId,
    required String productId,
    required int qtyChange,
    required String reason,
  }) async {
    final response = await client.rpc('rpc_adjust_stock', params: {
      'p_user_id': userId,
      'p_product_id': productId,
      'p_qty_change': qtyChange,
      'p_reason': reason,
    });
    return Map<String, dynamic>.from(response as Map);
  }

  /// Create Staff Member
  /// Create Staff Member (Requires Moderator Authentication)
  Future<Map<String, dynamic>> createStaffMember({
    required String adminId,
    required String adminPin,
    required String name,
    required String phone,
    required String role,
    required String initialPin,
    String language = 'ar',
  }) async {
    final response = await client.rpc('rpc_create_staff_member', params: {
      'p_admin_id': adminId,
      'p_admin_pin': adminPin,
      'p_name': name,
      'p_phone': phone,
      'p_role': role,
      'p_initial_pin': initialPin,
      'p_language': language,
    });
    return Map<String, dynamic>.from(response as Map);
  }

  /// Verify User PIN
  Future<bool> verifyUserPin({
    required String userId,
    required String pin,
  }) async {
    try {
      final res = await client.rpc('rpc_verify_user_pin', params: {
        'p_user_id': userId,
        'p_pin': pin,
      });
      if (res is Map && res['valid'] == true) return true;
      if (res is bool) return res;
    } catch (_) {}
    return false;
  }

  /// Change User PIN
  Future<bool> changeUserPin({
    required String userId,
    required String oldPin,
    required String newPin,
  }) async {
    try {
      final res = await client.rpc('rpc_change_user_pin', params: {
        'p_user_id': userId,
        'p_old_pin': oldPin,
        'p_new_pin': newPin,
      });
      if (res is Map && res['status'] == 'success') return true;
      if (res is bool && res) return true;
    } catch (_) {}
    return false;
  }

  /// Reset Staff PIN by Moderator / Admin (Requires Moderator PIN Proof)
  Future<bool> resetStaffPinByAdmin({
    required String adminId,
    required String adminPin,
    required String targetUserId,
    required String newPin,
  }) async {
    try {
      final res = await client.rpc('rpc_reset_user_pin_by_admin', params: {
        'p_admin_id': adminId,
        'p_admin_pin': adminPin,
        'p_target_user_id': targetUserId,
        'p_new_pin': newPin,
      });
      if (res is Map && res['status'] == 'success') return true;
      if (res is bool && res) return true;
    } catch (_) {}
    return false;
  }

  /// Update or Upsert Driver Live Location
  Future<void> updateDriverLocation({
    required String driverId,
    required double latitude,
    required double longitude,
    double? heading,
    double? speed,
    int? batteryLevel,
  }) async {
    await client.from('driver_locations').upsert({
      'driver_id': driverId,
      'latitude': latitude,
      'longitude': longitude,
      'heading': heading,
      'speed': speed,
      'battery_level': batteryLevel,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }
}

