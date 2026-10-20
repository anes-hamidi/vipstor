import 'package:domain/domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../datasources/local/staff_local_auth_store.dart';

/// Production auth repository with full offline-first staff credentials support.
class AuthRepositoryImpl implements IAuthRepository {
  final SupabaseClient client;
  final StaffLocalAuthStore localStore;

  AuthRepositoryImpl({
    required this.client,
    this.localStore = const StaffLocalAuthStore(),
  });

  // ── Public: resolve current session on app boot ────────────────────────────

  @override
  Future<UserEntity?> getCurrentUser() async {
    try {
      final session = client.auth.currentSession;
      if (session != null) {
        final user = await _fetchUserById(session.user.id);
        if (user != null) {
          await localStore.saveLastActiveUser(user);
          return user;
        }
      }
    } catch (_) {}
    return localStore.getLastActiveUser();
  }

  // ── Public: staff list (real DB with local offline cache fallback) ──────────

  @override
  Future<List<UserEntity>> getStaffMembers() async {
    try {
      final rows = await client
          .from('users')
          .select('id, phone, name, role, active, language, created_at, updated_at')
          .eq('active', true)
          .neq('role', 'customer')
          .order('name');

      final members = (rows as List).map((row) => _rowToEntity(row)).toList();
      if (members.isNotEmpty) {
        await localStore.saveStaffMembers(members);
      }
      return members;
    } catch (_) {
      final cached = await localStore.getStaffMembers();
      if (cached.isNotEmpty) {
        return cached;
      }
      rethrow;
    }
  }

  // ── Public: PIN verification (Server-first with offline salted hash fallback) ─

  @override
  Future<bool> verifyPin({required String userId, required String pin}) async {
    try {
      final res = await client.rpc('rpc_verify_user_pin', params: {
        'p_user_id': userId,
        'p_pin': pin,
      });

      if (res is Map) {
        if (res['locked'] == true) {
          throw const AuthException(
            'الحساب مقفل مؤقتاً بسبب تكرار المحاولات الخاطئة. يرجى الانتظار.',
          );
        }
        final isValid = res['valid'] == true;
        if (isValid) {
          await localStore.saveUserPinHash(userId, pin);
        }
        return isValid;
      }
      return false;
    } catch (e) {
      if (e is AuthException) rethrow;

      final isOfflineValid = await localStore.verifyOfflinePin(userId, pin);
      if (isOfflineValid) {
        return true;
      }

      throw Exception('تعذر الاتصال بالسيرفر، ولم يتم حفظ رمز PIN مسبقاً على هذا الجهاز.');
    }
  }

  // ── Public: sign in as staff after PIN verified ───────────────────────────
  //
  // After PIN is verified locally, we need a Supabase JWT so the RLS policies
  // let the staff member's role access the right tables.
  //
  // Strategy: Supabase doesn't support password-less phone sign-in without OTP
  // delivery in prod. We sign in using the anon key + store the resolved user
  // entity in app state. For full RLS, the staff phone number must be registered
  // in Supabase Auth (auth.users) — we attempt signInWithOtp as a best-effort.
  // If that is not set up, the anon JWT still works for RPCs that are
  // SECURITY DEFINER (which all our RPCs are).
  //
  // This is a deliberate design decision: staff-facing RPCs bypass RLS by being
  // SECURITY DEFINER, so the JWT role doesn't block them.

  @override
  Future<UserEntity> signInWithPhoneAndPassword(
      String phone, String password) async {
    // This method is not used by the staff flow (which is PIN-based).
    // It exists for the customer app's phone+OTP flow.
    throw UnimplementedError(
        'Use verifyPin() for staff or signInWithOtp() for customers.');
  }

  // ── Public: PIN management ─────────────────────────────────────────────────

  @override
  Future<bool> changePin({
    required String userId,
    required String oldPin,
    required String newPin,
  }) async {
    if (newPin.length < 4) return false;
    final res = await client.rpc('rpc_change_user_pin', params: {
      'p_user_id': userId,
      'p_old_pin': oldPin,
      'p_new_pin': newPin,
    });
    if (res is Map) {
      if (res['status'] == 'success') {
        await localStore.saveUserPinHash(userId, newPin);
        return true;
      }
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
    if (newPin.length < 4) return false;
    final res = await client.rpc('rpc_reset_user_pin_by_admin', params: {
      'p_admin_id': adminId,
      'p_admin_pin': adminPin,
      'p_target_user_id': targetUserId,
      'p_new_pin': newPin,
    });
    final ok = res == true || (res is Map && res['status'] == 'success');
    if (ok) {
      await localStore.saveUserPinHash(targetUserId, newPin);
    }
    return ok;
  }

  // ── Public: sign out ───────────────────────────────────────────────────────

  @override
  Future<void> signOut() async {
    try {
      await client.auth.signOut();
    } catch (_) {}
    await localStore.clearLastActiveUser();
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  Future<UserEntity?> _fetchUserById(String id) async {
    final rows = await client
        .from('users')
        .select('id, phone, name, role, active, language, created_at, updated_at')
        .eq('id', id)
        .limit(1);

    if ((rows as List).isEmpty) return null;
    return _rowToEntity(rows.first);
  }

  UserEntity _rowToEntity(Map<String, dynamic> row) {
    return UserEntity(
      id: row['id'] as String,
      phone: row['phone'] as String? ?? '',
      name: row['name'] as String? ?? '',
      role: UserRole.fromString(row['role'] as String? ?? 'cashier'),
      active: row['active'] as bool? ?? true,
      language: row['language'] as String? ?? 'ar',
    );
  }
}
