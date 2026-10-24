class AppConstants {
  static const String appNameAr = 'نظام إدارة متجر الجملة';
  static const String appNameFr = 'Système de Gestion de Gros';
  
  static const String defaultLanguage = 'ar';
  static const List<String> supportedLanguages = ['ar', 'fr'];

  // Build-time configuration (required):
  //   flutter run --dart-define-from-file=.env
  //   flutter build apk --release --dart-define-from-file=.env
  //
  // There is deliberately no fallback project. A build without these values
  // fails fast instead of silently connecting to a stale database.
  // Never ship the service_role key to a client app.
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Call before `Supabase.initialize` to produce an actionable error when a
  /// developer forgot the build-time configuration.
  static void ensureSupabaseConfigured() {
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      throw StateError(
        'Supabase credentials are missing. Run from the repository root with '
        '--dart-define-from-file=.env, or pass '
        '--dart-define=SUPABASE_URL=... and '
        '--dart-define=SUPABASE_ANON_KEY=....',
      );
    }
  }
}

