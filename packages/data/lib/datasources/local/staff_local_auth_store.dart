// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:domain/domain.dart';

/// Local cache of the last active staff member, the PIN-session marker, and
/// POS shift state.
///
/// PIN verification is intentionally not cached: every staff sign-in is
/// verified by the `auth-admin` Edge Function and exchanged for a real
/// Supabase session. The marker only records that the current session was
/// created by the PIN terminal; it is never used as an authentication proof.
class StaffLocalAuthStore {
  static const _kLastUserKey = 'staff_last_logged_in_user_v1';
  static const _kPinSessionUserKey = 'staff_pin_session_user_v1';
  static const _kActiveShiftKey = 'staff_active_shift_session_v1';

  const StaffLocalAuthStore();

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

  /// Records that the Supabase session on this device was created by the PIN
  /// terminal. [hasPinSession] is checked during session restore so a legacy
  /// password-created staff session cannot bypass the PIN-only login screen.
  Future<void> markPinSession(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPinSessionUserKey, userId);
    } catch (_) {}
  }

  /// Whether the last PIN login on this device belongs to [userId].
  Future<bool> hasPinSession(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_kPinSessionUserKey) == userId;
    } catch (_) {
      return false;
    }
  }

  /// Clears the PIN-session marker on logout or a password-based login.
  Future<void> clearPinSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kPinSessionUserKey);
    } catch (_) {}
  }

  /// Deletes credentials cached by older app versions: the cached staff list
  /// and per-user offline PIN hashes. The current app never reads them.
  Future<void> purgeLegacyAuthCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacyKeys = prefs
          .getKeys()
          .where(
            (key) =>
                key == 'staff_cached_users_list_v1' ||
                key.startsWith('staff_pin_hash_'),
          )
          .toList(growable: false);
      for (final key in legacyKeys) {
        await prefs.remove(key);
      }
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
