import 'package:shared_preferences/shared_preferences.dart';

/// Phone + password remembered from the last successful customer login.
class SavedCustomerCredentials {
  const SavedCustomerCredentials({
    required this.phone,
    required this.password,
  });

  final String phone;
  final String password;

  bool get isEmpty => phone.isEmpty && password.isEmpty;
}

/// Persists the last successful customer login so the login form can be
/// prefilled on this installation.
///
/// The Supabase JWT is persisted separately by `supabase_flutter` (also via
/// SharedPreferences), which is what keeps an authenticated customer signed in
/// across app restarts. This store only exists as a convenience for the login
/// form when a session is not available.
///
/// SECURITY: SharedPreferences is not encrypted. Keeping the customer password
/// here is a deliberate convenience trade-off for the storefront; never use
/// this store for staff or admin credentials.
class CustomerCredentialStore {
  CustomerCredentialStore([this._prefs]);

  SharedPreferences? _prefs;

  static const _kPhoneKey = 'customer.auth.remembered_phone.v1';
  static const _kPasswordKey = 'customer.auth.remembered_password.v1';

  Future<SharedPreferences?> _ensure() async {
    if (_prefs != null) return _prefs;
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
    return _prefs;
  }

  /// Synchronous read for the normal startup path where `main()` already
  /// loaded SharedPreferences and injected them into the provider scope.
  SavedCustomerCredentials? readSync() {
    final prefs = _prefs;
    if (prefs == null) return null;
    final saved = SavedCustomerCredentials(
      phone: prefs.getString(_kPhoneKey) ?? '',
      password: prefs.getString(_kPasswordKey) ?? '',
    );
    return saved.isEmpty ? null : saved;
  }

  Future<SavedCustomerCredentials?> read() async {
    final prefs = await _ensure();
    if (prefs == null) return null;
    final saved = SavedCustomerCredentials(
      phone: prefs.getString(_kPhoneKey) ?? '',
      password: prefs.getString(_kPasswordKey) ?? '',
    );
    return saved.isEmpty ? null : saved;
  }

  Future<void> save({
    required String phone,
    required String password,
  }) async {
    final prefs = await _ensure();
    if (prefs == null) return;
    try {
      await prefs.setString(_kPhoneKey, phone.trim());
      await prefs.setString(_kPasswordKey, password);
    } catch (_) {
      // Remembering credentials is best-effort and must never block login.
    }
  }

  Future<void> clear() async {
    final prefs = await _ensure();
    if (prefs == null) return;
    try {
      await prefs.remove(_kPhoneKey);
      await prefs.remove(_kPasswordKey);
    } catch (_) {}
  }
}
