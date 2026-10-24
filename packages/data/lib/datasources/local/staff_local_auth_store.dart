// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:domain/domain.dart';

/// Local offline store for caching staff credentials, PIN hashes, and active sessions.
class StaffLocalAuthStore {
  static const _kStaffListKey = 'staff_cached_users_list_v1';
  static const _kLastUserKey = 'staff_last_logged_in_user_v1';
  static const _kActiveShiftKey = 'staff_active_shift_session_v1';
  static const _kPinHashPrefix = 'staff_pin_hash_';

  const StaffLocalAuthStore();

  String _hashPin(String userId, String pin) {
    final salt = 'vip_staff_salt_$userId';
    final bytes = utf8.encode('$salt:$pin');
    return sha256.convert(bytes).toString();
  }

  /// Saves the active staff members list to local storage.
  Future<void> saveStaffMembers(List<UserEntity> staff) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final listJson = staff.map((u) => {
        'id': u.id,
        'name': u.name,
        'phone': u.phone,
        'role': u.role.name,
        'active': u.active,
        'language': u.language,
      }).toList();
      await prefs.setString(_kStaffListKey, jsonEncode(listJson));
    } catch (_) {}
  }

  /// Retrieves the cached staff members list for offline login.
  Future<List<UserEntity>> getStaffMembers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString(_kStaffListKey);
      if (str == null || str.isEmpty) return [];

      final list = jsonDecode(str) as List;
      return list.map((item) {
        final m = item as Map<String, dynamic>;
        return UserEntity(
          id: m['id'] as String,
          name: (m['name'] as String?) ?? '',
          phone: (m['phone'] as String?) ?? '',
          role: UserRole.fromString(m['role'] as String? ?? 'staff'),
          active: (m['active'] as bool?) ?? true,
          language: (m['language'] as String?) ?? 'ar',
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Saves a salted SHA-256 hash of the staff member's PIN upon successful verification.
  Future<void> saveUserPinHash(String userId, String pin) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hash = _hashPin(userId, pin);
      await prefs.setString('$_kPinHashPrefix$userId', hash);
    } catch (_) {}
  }

  /// Verifies the entered PIN against the locally stored salted hash.
  Future<bool> verifyOfflinePin(String userId, String pin) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedHash = prefs.getString('$_kPinHashPrefix$userId');
      if (storedHash == null || storedHash.isEmpty) {
        return false;
      }
      final inputHash = _hashPin(userId, pin);
      return storedHash == inputHash;
    } catch (_) {
      return false;
    }
  }

  /// Saves the last active logged-in staff member.
  Future<void> saveLastActiveUser(UserEntity user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userMap = {
        'id': user.id,
        'name': user.name,
        'phone': user.phone,
        'role': user.role.name,
        'active': user.active,
        'language': user.language,
      };
      await prefs.setString(_kLastUserKey, jsonEncode(userMap));
    } catch (_) {}
  }

  /// Gets the last active logged-in staff member.
  Future<UserEntity?> getLastActiveUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString(_kLastUserKey);
      if (str == null || str.isEmpty) return null;

      final m = jsonDecode(str) as Map<String, dynamic>;
      return UserEntity(
        id: m['id'] as String,
        name: (m['name'] as String?) ?? '',
        phone: (m['phone'] as String?) ?? '',
        role: UserRole.fromString(m['role'] as String? ?? 'staff'),
        active: (m['active'] as bool?) ?? true,
        language: (m['language'] as String?) ?? 'ar',
      );
    } catch (_) {
      return null;
    }
  }

  /// Clears the last active user on logout.
  Future<void> clearLastActiveUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kLastUserKey);
    } catch (_) {}
  }

  /// Saves the active POS cashier shift session (for crash/restart protection offline).
  Future<void> saveActiveShiftJson(String shiftJson) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kActiveShiftKey, shiftJson);
    } catch (_) {}
  }

  /// Retrieves the active POS cashier shift session.
  Future<String?> getActiveShiftJson() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_kActiveShiftKey);
    } catch (_) {
      return null;
    }
  }

  /// Clears the active POS shift session when closed.
  Future<void> clearActiveShift() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kActiveShiftKey);
    } catch (_) {}
  }
}
