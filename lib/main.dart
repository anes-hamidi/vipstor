import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:l10n/l10n.dart';
import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:staff_app/router/staff_router.dart' as staff;
import 'package:staff_app/providers/staff_providers.dart';
import 'package:customer_app/main.dart' as customer;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConstants.ensureSupabaseConfigured();

  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    // ignore: deprecated_member_use
    anonKey: AppConstants.supabaseAnonKey,
  );

  runApp(const ProviderScope(child: VipMasterApp()));
}

class VipMasterApp extends ConsumerStatefulWidget {
  const VipMasterApp({super.key});

  @override
  ConsumerState<VipMasterApp> createState() => _VipMasterAppState();
}

class _VipMasterAppState extends ConsumerState<VipMasterApp> {
  // Mode switcher: 'portal', 'staff', 'customer'
  String _currentAppMode = 'portal';

  @override
  void initState() {
    super.initState();
    // Eagerly start the offline sync worker so it begins connectivity polling
    // and drains any queued operations from previous sessions. Failure to
    // start must never block the portal shell (for example in widget tests or
    // during a cold client bootstrap), so the error is logged instead.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        ref.read(offlineSyncServiceProvider);
      } catch (error, stackTrace) {
        debugPrint('Offline sync worker failed to start: $error\n$stackTrace');
      }
    });
  }

  /// Applies the palette that matches the signed-in staff account. The master
  /// portal swaps entire applications at runtime, so the reactive role has to
  /// follow whichever staff session is active.
  void _syncStaffRole(UserEntity? user) {
    if (!mounted || _currentAppMode != 'staff') return;
    final AppRole role = staff.roleForStaffUser(user);
    if (ref.read(appRoleProvider) != role) {
      ref.read(appRoleProvider.notifier).state = role;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<UserEntity?>(staff.authStateProvider, (previous, next) {
      // Login, logout and session restore all funnel through this listener.
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncStaffRole(next));
    });

    final lightTheme = ref.watch(lightThemeProvider);
    final darkTheme = ref.watch(darkThemeProvider);
    final themeMode = ref.watch(themeModeProvider);

    if (_currentAppMode == 'staff') {
      final router = ref.watch(staff.staffRouterProvider);
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

    if (_currentAppMode == 'customer') {
      return customer.CustomerApp(
        onExit: () => setState(() => _currentAppMode = 'portal'),
      );
    }

    // Portal Switcher
    return MaterialApp(
      title: 'Wholesale Management Portal',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: AppLocalizationHelper.supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          return Scaffold(
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        Icons.storefront_rounded,
                        size: 80,
                        color: scheme.primary,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'نظام إدارة متجر الجملة الشامل',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'اختر التطبيق لتسجيل الدخول وبدء العمل',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 36),
                      Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          leading: CircleAvatar(
                            backgroundColor: scheme.primary,
                            radius: 26,
                            child: Icon(
                              Icons.badge,
                              color: scheme.onPrimary,
                              size: 28,
                            ),
                          ),
                          title: const Text(
                            'تطبيق طاقم العمل (Staff App)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                            ),
                          ),
                          subtitle: const Text(
                            'المشرف العام، مدير المخزون، أمين الصندوق، وسائق التوصيل',
                          ),
                          trailing: const Icon(Icons.arrow_forward_ios),
                          onTap: () =>
                              setState(() => _currentAppMode = 'staff'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          leading: CircleAvatar(
                            backgroundColor: scheme.secondary,
                            radius: 26,
                            child: Icon(
                              Icons.shopping_bag,
                              color: scheme.onSecondary,
                              size: 28,
                            ),
                          ),
                          title: const Text(
                            'تطبيق الزبائن وتجار التجزئة (Customer App)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                            ),
                          ),
                          subtitle: const Text(
                            'تصفح الكتالوج المباشر، أسعار الجملة، والطلبيات',
                          ),
                          trailing: const Icon(Icons.arrow_forward_ios),
                          onTap: () =>
                              setState(() => _currentAppMode = 'customer'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
