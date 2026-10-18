import '../entities/user_entity.dart';

abstract class IAuthRepository {
  Future<UserEntity?> getCurrentUser();
  Future<UserEntity> signInWithPhoneAndPassword(String phone, String password);
  Future<List<UserEntity>> getStaffMembers();
  Future<bool> verifyPin({required String userId, required String pin});
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
