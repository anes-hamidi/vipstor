import 'package:customer_app/features/profile/profile_form_screen.dart';
import 'package:customer_app/providers/customer_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:l10n/l10n.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    // ignore: deprecated_member_use
    anonKey: AppConstants.supabaseAnonKey,
  );

  final prefs = await SharedPreferences.getInstance();
runApp(ProviderScope(
  overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  child: const CustomerApp(),
));
}

class CustomerApp extends StatelessWidget {
  final VoidCallback? onExit;
  const CustomerApp({super.key, this.onExit});

  @override
  Widget build(BuildContext context) {
    debugPrint('customer main() running');

    return MaterialApp(
      title: 'متجر الجملة (Wholesale Store)',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: ProfileGate(onExit: onExit),
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
