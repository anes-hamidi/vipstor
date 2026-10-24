import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'router/staff_router.dart';
import 'package:l10n/l10n.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConstants.ensureSupabaseConfigured();

  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    // ignore: deprecated_member_use
    anonKey: AppConstants.supabaseAnonKey,
  );

  runApp(const ProviderScope(child: StaffApp()));
}

class StaffApp extends ConsumerStatefulWidget {
  const StaffApp({super.key});

  @override
  ConsumerState<StaffApp> createState() => _StaffAppState();
}

class _StaffAppState extends ConsumerState<StaffApp> {
  @override
  void initState() {
    super.initState();
    // The widget can be constructed after a session was already restored (for
    // example when embedded in the master portal), so align the role once.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncRole(ref.read(authStateProvider));
    });
  }

  /// Applies the workspace palette matching the sign-in state. Routing updates
  /// are delivered on auth/state changes, never during the current frame.
  void _syncRole(UserEntity? user) {
    final AppRole role = roleForStaffUser(user);
    if (ref.read(appRoleProvider) != role) {
      ref.read(appRoleProvider.notifier).state = role;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<UserEntity?>(authStateProvider, (previous, next) {
      // Login, logout and session restore all funnel through this listener, so
      // the palette always tracks the authenticated staff role.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncRole(next);
      });
    });

    final router = ref.watch(staffRouterProvider);
    final lightTheme = ref.watch(lightThemeProvider);
    final darkTheme = ref.watch(darkThemeProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'Wholesale Staff App',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: AppLocalizationHelper.supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
