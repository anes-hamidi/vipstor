import '../entities/user_entity.dart';
import 'package:core/core.dart';

abstract class IAuthRepository {
  Future<UserEntity?> getCurrentUser();
  Future<UserEntity> signInWithPhoneAndPassword(String phone, String password);
  Future<void> sendPhoneOtp(String phone, {bool shouldCreateUser = true});
  Future<UserEntity> verifyPhoneOtp({
    required String phone,
    required String token,
  });
  Future<List<UserEntity>> getStaffMembers();

  /// Verifies a staff PIN.
  /// Returns [Success(true)] on valid, [Success(false)] on invalid,
  /// [FailureResult(PinLockedFailure)] when account is locked,
  /// [FailureResult(NetworkFailure)] when offline and no cached PIN.
  Future<Result<bool, Failure>> verifyPin({required String userId, required String pin});

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
