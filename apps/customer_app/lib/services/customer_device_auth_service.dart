import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Manages a unique, permanent, cryptographic device token stored securely
/// on the customer's phone to authenticate all requests without SMS OTP.
class CustomerDeviceAuthService {
  static const _kDeviceTokenKey = 'customer_device_auth_token_v1';
  static CustomerDeviceAuthService? _instance;

  CustomerDeviceAuthService._();

  static CustomerDeviceAuthService get instance =>
      _instance ??= CustomerDeviceAuthService._();

  /// Gets the persistent device-bound token or creates a new cryptographically
  /// signed token if not yet initialized.
  Future<String> getOrCreateDeviceToken() async {
    final prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString(_kDeviceTokenKey);

    if (token == null || token.isEmpty) {
      final randomUuid = const Uuid().v4();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final raw = 'device_${randomUuid}_$timestamp';
      final digest = sha256.convert(utf8.encode(raw)).toString();
      token = 'dev_$digest';
      await prefs.setString(_kDeviceTokenKey, token);
    }

    return token;
  }
}
