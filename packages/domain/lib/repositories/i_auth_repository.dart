import '../entities/customer_auth_result.dart';
import '../entities/user_entity.dart';
import 'package:core/core.dart';

abstract class IAuthRepository {
  Future<UserEntity?> getCurrentUser();
  Future<UserEntity> signInWithPhoneAndPassword(String phone, String password);

  /// Creates a customer account through the auth-admin Edge Function.
  ///
  /// The returned recovery code is shown once and must be saved by the
  /// customer. No SMS or email verification is involved.
  Future<CustomerRegistrationResult> registerCustomer({
    required String name,
    required String phone,
    required String password,
  });

  /// Resets a customer password with the recovery code issued at registration.
  Future<CustomerPasswordResetResult> resetCustomerPassword({
    required String phone,
    required String recoveryCode,
    required String newPassword,
  });

  Future<List<UserEntity>> getStaffMembers();

  /// Returns the public PIN-login directory (active cashiers, managers and
  /// drivers). This is available before authentication so the PIN terminal can
  /// list employees; moderators are deliberately excluded because they sign in
  /// with phone + password.
  Future<List<UserEntity>> getStaffDirectory();

  /// Signs a staff member in with their PIN.
  ///
  /// The auth-admin Edge Function verifies the PIN server-side and returns a
  /// short-lived Supabase session for the linked Auth identity. The repository
  /// installs that session so RLS and every existing data/RPC call keep
  /// working, then resolves the matching public staff profile.
  Future<UserEntity> signInStaffWithPin({
    required String userId,
    required String pin,
  });

  /// Verifies a staff PIN as a step-up check for sensitive operations.
  /// Returns [Success(true)] on valid, [Success(false)] on invalid,
  /// [FailureResult(PinLockedFailure)] when account is locked,
  /// [FailureResult(NetworkFailure)] when offline and no cached PIN.
  Future<Result<bool, Failure>> verifyPin(
      {required String userId, required String pin});

  Future<bool> changePin({
    required String userId,
    required String oldPin,
    required String newPin,
  });
  Future<bool> resetStaffPinByModerator({
    required String adminId,
    required String adminPin,
    required String targetUserId,
    required String newPin,
  });
  Future<void> signOut();
}
