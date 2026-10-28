import 'package:supabase_flutter/supabase_flutter.dart';

/// Thin client for the `auth-admin` Supabase Edge Function.
///
/// The function owns all service-role Auth lifecycle operations. The app never
/// embeds a service-role key and never calls the Supabase Auth admin API
/// directly. Business errors are surfaced as [AuthException] so existing UI
/// error handlers can display the server's Arabic message.
class AuthAdminGateway {
  const AuthAdminGateway(this.client);

  final SupabaseClient client;

  Future<Map<String, dynamic>> invoke(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    try {
      final response = await client.functions.invoke(
        'auth-admin',
        body: <String, dynamic>{'action': action, ...payload},
      );

      final data = response.data;
      if (data is Map) {
        final map = Map<String, dynamic>.from(data);
        if (map['success'] == true) return map;
        throw AuthException(
          map['error']?.toString() ?? 'تعذر إكمال العملية.',
        );
      }

      throw const AuthException(
        'استجابة غير صالحة من خدمة إدارة الحسابات. حاول مرة أخرى.',
      );
    } on AuthException {
      rethrow;
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['error'] != null) {
        throw AuthException(details['error'].toString());
      }
      if (error.status == 404) {
        throw const AuthException(
          'خدمة إدارة الحسابات غير منشورة على الخادم. راجع مسؤول النظام.',
        );
      }
      throw const AuthException(
        'تعذر الاتصال بخدمة إدارة الحسابات. تحقق من الإنترنت وحاول مرة أخرى.',
      );
    } catch (_) {
      throw const AuthException(
        'تعذر الاتصال بخدمة إدارة الحسابات. تحقق من الإنترنت وحاول مرة أخرى.',
      );
    }
  }
}
