import 'package:core/core.dart';
import 'package:customer_app/features/shell/customer_shell.dart';
import 'package:customer_app/providers/customer_providers.dart';
import 'package:data/data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    // ignore: deprecated_member_use
    anonKey: AppConstants.supabaseAnonKey,
  );

  // Keep a single connectivity poller alive for the whole app lifetime. The
  // shell listens to the resulting provider and refreshes cached data when the
  // device comes back online.
  ConnectivityService.instance.startPolling(intervalSeconds: 12);

  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const CustomerApp(),
    ),
  );
}

class CustomerApp extends ConsumerStatefulWidget {
  final VoidCallback? onExit;
  const CustomerApp({super.key, this.onExit});

  @override
  ConsumerState<CustomerApp> createState() => _CustomerAppState();
}

class _CustomerAppState extends ConsumerState<CustomerApp> {
  @override
  void initState() {
    super.initState();
    // The customer shell is always the storefront workspace. Force the role
    // after the first frame so embedding it in the master portal cannot leak a
    // staff palette from a previous session.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(appRoleProvider) != AppRole.customer) {
        ref.read(appRoleProvider.notifier).state = AppRole.customer;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final lightTheme = ref.watch(lightThemeProvider);
    final darkTheme = ref.watch(darkThemeProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'متجر الجملة (Wholesale Store)',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      home: CustomerShell(onExit: widget.onExit),
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: AppLocalizationHelper.supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Keep giant accessibility fonts from destroying dense catalog cards
      // while still honouring the user's preference within a sane range.
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(
              minScaleFactor: 0.9,
              maxScaleFactor: 1.3,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
