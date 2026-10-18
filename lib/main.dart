import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ui_kit/ui_kit.dart';
import 'package:l10n/l10n.dart';
import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:staff_app/router/staff_router.dart' as staff;
import 'package:staff_app/providers/staff_providers.dart';
import 'package:customer_app/main.dart' as customer;




Future<void> main() async {

  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    // ignore: deprecated_member_use
    anonKey: AppConstants.supabaseAnonKey,
  );

  runApp( const ProviderScope(child: VipMasterApp()));
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
    // and drains any queued operations from previous sessions.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(offlineSyncServiceProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_currentAppMode == 'staff') {
      final router = ref.watch(staff.staffRouterProvider);
      return MaterialApp.router(
        title: 'Wholesale Staff App',
        theme: AppTheme.lightTheme,
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
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.storefront_rounded, size: 80, color: AppTheme.primaryColor),
                  const SizedBox(height: 16),
                  const Text(
                    'نظام إدارة متجر الجملة الشامل',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'اختر التطبيق لتسجيل الدخول وبدء العمل',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 15),
                  ),
                  const SizedBox(height: 36),
                  Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: const CircleAvatar(
                        backgroundColor: AppTheme.primaryColor,
                        radius: 26,
                        child: Icon(Icons.badge, color: Colors.white, size: 28),
                      ),
                      title: const Text('تطبيق طاقم العمل (Staff App)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                      subtitle: const Text('المشرف العام، مدير المخزون، أمين الصندوق، وسائق التوصيل'),
                      trailing: const Icon(Icons.arrow_forward_ios),
                      onTap: () => setState(() => _currentAppMode = 'staff'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: const CircleAvatar(
                        backgroundColor: AppTheme.accentColor,
                        radius: 26,
                        child: Icon(Icons.shopping_bag, color: Colors.white, size: 28),
                      ),
                      title: const Text('تطبيق الزبائن وتجار التجزئة (Customer App)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                      subtitle: const Text('تصفح الكتالوج المباشر، أسعار الجملة، والطلبيات'),
                      trailing: const Icon(Icons.arrow_forward_ios),
                      onTap: () => setState(() => _currentAppMode = 'customer'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
