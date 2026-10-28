import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Manages the opaque device token used to bind an OTP-verified customer
/// session to this installation.
///
/// The token is generated with a cryptographically secure RNG and stored via
/// SharedPreferences. The token is a binding identifier only — actual auth
/// is handled by Supabase JWT; this token prevents account-sharing between
/// devices by binding the customer to their first verified device.
class CustomerDeviceAuthService {
  static const _kDeviceTokenKey = 'customer_device_auth_token_v1';

  static CustomerDeviceAuthService? _instance;

  CustomerDeviceAuthService._();

  static CustomerDeviceAuthService get instance =>
      _instance ??= CustomerDeviceAuthService._();

  Future<String> getOrCreateDeviceToken() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_kDeviceTokenKey);
    if (existing != null && existing.length >= 32) return existing;
    return _generateAndStore(prefs);
  }

  /// Explicit rotation after an OTP login or when the server reports a
  /// device mismatch.
  Future<String> rotate() async {
    final prefs = await SharedPreferences.getInstance();
    return _generateAndStore(prefs);
  }

  /// Removes the locally stored token after logout. The next OTP login rotates
  /// and rebinds a fresh token instead of reusing the logged-out device secret.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kDeviceTokenKey);
  }

  Future<String> _generateAndStore(SharedPreferences prefs) async {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final token = base64UrlEncode(bytes).replaceAll('=', '');
    await prefs.setString(_kDeviceTokenKey, token);
    return token;
  }
}
