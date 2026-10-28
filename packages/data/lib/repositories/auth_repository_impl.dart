import 'package:core/core.dart';
import 'package:domain/domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../datasources/local/staff_local_auth_store.dart';

/// Real Supabase Auth repository.
///
/// The JWT is the only source of identity. The local staff store is kept only
/// for non-authoritative caches; it is never allowed to restore a session.
class AuthRepositoryImpl implements IAuthRepository {
  final SupabaseClient client;
  final StaffLocalAuthStore localStore;

  AuthRepositoryImpl({
    required this.client,
    this.localStore = const StaffLocalAuthStore(),
  });

  // ── Session resolution ─────────────────────────────────────────────────────

  @override
  Future<UserEntity?> getCurrentUser() async {
    final session = client.auth.currentSession;
    if (session == null) return null;

    var user = await _fetchUserByAuthId(session.user.id);
    if (user == null) {
      await _bootstrapMyAccount();
      user = await _fetchUserByAuthId(session.user.id);
    }
    if (user == null || !user.active) {
      await signOut();
      return null;
    }
    return user;
  }

  // ── Staff list (authenticated staff only) ──────────────────────────────────

  @override
  Future<List<UserEntity>> getStaffMembers() async {
    if (client.auth.currentSession == null) {
      throw const AuthException('يجب تسجيل الدخول أولاً');
    }
    final rows = await client
        .from('users')
        .select('id, phone, name, role, active, language, must_change_pin')
        .eq('active', true)
        .neq('role', 'customer')
        .order('name');

    return (rows as List).map((row) => _rowToEntity(row)).toList();
  }

  // ── Staff phone + password ─────────────────────────────────────────────────

  @override
  Future<UserEntity> signInWithPhoneAndPassword(
    String phone,
    String password,
  ) async {
    final normalized = normalizePhone(phone);
    final response = await client.auth.signInWithPassword(
      phone: normalized,
      password: password,
    );
    final user = await _resolveAuthedUser(response.user?.id);
    if (!user.active) {
      await signOut();
      throw const AuthException('هذا الحساب معطّل. راجع الإدارة.');
    }
    return user;
  }

  // ── Phone OTP (customers and staff step-up) ────────────────────────────────

  @override
  Future<void> sendPhoneOtp(
    String phone, {
    bool shouldCreateUser = true,
  }) async {
    await client.auth.signInWithOtp(
      phone: normalizePhone(phone),
      shouldCreateUser: shouldCreateUser,
    );
  }

  @override
  Future<UserEntity> verifyPhoneOtp({
    required String phone,
    required String token,
  }) async {
    final normalized = normalizePhone(phone);
    final response = await client.auth.verifyOTP(
      phone: normalized,
      token: token.trim(),
      type: OtpType.sms,
    );
    final user = await _resolveAuthedUser(response.user?.id);
    if (!user.active) {
      await signOut();
      throw const AuthException('هذا الحساب معطّل. راجع الإدارة.');
    }
    return user;
  }

  // ── PIN step-up (never a login method) ─────────────────────────────────────

  @override
  Future<Result<bool, Failure>> verifyPin({
    required String userId,
    required String pin,
  }) async {
    if (client.auth.currentSession == null) {
      return const FailureResult(
        NetworkFailure('يجب تسجيل الدخول أولاً للتحقق من رمز PIN.'),
      );
    }
    try {
      final res = await client.rpc('rpc_verify_user_pin', params: {
        'p_user_id': userId,
        'p_pin': pin,
      });
      if (res is Map) {
        if (res['locked'] == true) {
          return const FailureResult(PinLockedFailure(
            'الحساب مقفل مؤقتاً بسبب تكرار المحاولات الخاطئة. يرجى الانتظار.',
          ));
        }
        return Success(res['valid'] == true);
      }
      return const Success(false);
    } catch (_) {
      return const FailureResult(NetworkFailure(
        'تعذر التحقق من رمز PIN. تحقق من الاتصال وحاول مرة أخرى.',
      ));
    }
  }

  @override
  Future<bool> changePin({
    required String userId,
    required String oldPin,
    required String newPin,
  }) async {
    final next = newPin.trim();
    if (!RegExp(r'^[0-9]{4,8}$').hasMatch(next)) return false;
    final res = await client.rpc('rpc_change_user_pin', params: {
      'p_user_id': userId,
      'p_old_pin': oldPin,
      'p_new_pin': next,
    });
    if (res is Map) {
      if (res['status'] == 'success') return true;
      if (res['message'] != null) {
        throw AuthException(res['message'] as String);
      }
    }
    return false;
  }

  @override
  Future<bool> resetStaffPinByModerator({
    required String adminId,
    required String adminPin,
    required String targetUserId,
    required String newPin,
  }) async {
    final next = newPin.trim();
    if (!RegExp(r'^[0-9]{4,8}$').hasMatch(next)) return false;
    final res = await client.rpc('rpc_reset_user_pin_by_admin', params: {
      'p_admin_id': adminId,
      'p_admin_pin': adminPin,
      'p_target_user_id': targetUserId,
      'p_new_pin': next,
    });
    return res == true || (res is Map && res['status'] == 'success');
  }

  // ── Sign out ───────────────────────────────────────────────────────────────

  @override
  Future<void> signOut() async {
    try {
      await client.auth.signOut();
    } catch (_) {}
    await localStore.clearLastActiveUser();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Future<UserEntity> _resolveAuthedUser(String? authId) async {
    final id = authId ?? client.auth.currentUser?.id;
    if (id == null) {
      throw const AuthException('فشل تسجيل الدخول: لا توجد جلسة صالحة.');
    }

    var user = await _fetchUserByAuthId(id);
    if (user == null) {
      await _bootstrapMyAccount();
      user = await _fetchUserByAuthId(id);
    }
    if (user == null) {
      await signOut();
      throw const AuthException(
        'تم إنشاء جلسة الدخول لكن لا يوجد حساب موظف/زبون مرتبط بهذا الهاتف. '
        'اطلب من الإدارة ربط الحساب.',
      );
    }
    return user;
  }

  Future<void> _bootstrapMyAccount() async {
    try {
      await client.rpc('rpc_bootstrap_my_account');
    } catch (_) {
      // The auth trigger normally provisions the row. If bootstrap is not
      // available, the caller will surface the missing-link error.
    }
  }

  Future<UserEntity?> _fetchUserByAuthId(String authId) async {
    final rows = await client
        .from('users')
        .select('id, phone, name, role, active, language, must_change_pin')
        .eq('auth_user_id', authId)
        .limit(1);

    if ((rows as List).isEmpty) return null;
    return _rowToEntity(rows.first);
  }

  UserEntity _rowToEntity(Map<String, dynamic> row) {
    return UserEntity(
      id: row['id'] as String,
      phone: row['phone'] as String? ?? '',
      name: row['name'] as String? ?? '',
      role: UserRole.fromString(row['role'] as String? ?? 'customer'),
      active: row['active'] as bool? ?? false,
      language: row['language'] as String? ?? 'ar',
      mustChangePin: row['must_change_pin'] as bool? ?? false,
    );
  }
}

/// Normalizes Algerian phone numbers to E.164. Supabase Auth expects a stable
/// international format for both password login and OTP delivery.
String normalizePhone(String input) {
  var value = input.trim().replaceAll(RegExp(r'[^0-9+]'), '');
  if (value.startsWith('00')) {
    value = '+${value.substring(2)}';
  }
  if (value.startsWith('+')) {
    return value;
  }
  if (value.startsWith('213')) {
    return '+$value';
  }
  if (RegExp(r'^0[5-7][0-9]{8}$').hasMatch(value)) {
    return '+213${value.substring(1)}';
  }
  return value.isEmpty ? value : '+$value';
}
