import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:domain/domain.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:staff_app/features/auth/login_screen.dart';
import 'package:staff_app/providers/staff_providers.dart';

void main() {
  final mockStaff = [
    const UserEntity(
      id: 'staff-1',
      name: 'أحمد كاشير',
      phone: '0550112233',
      role: UserRole.cashier,
      active: true,
      language: 'ar',
    ),
    const UserEntity(
      id: 'staff-2',
      name: 'كريم مدير المخزن',
      phone: '0550445566',
      role: UserRole.manager,
      active: true,
      language: 'ar',
    ),
  ];

  Widget createLoginWidget({required Size screenSize}) {
    return ProviderScope(
      overrides: [
        liveStaffUsersProvider.overrideWith((ref) => Future.value(mockStaff)),
      ],
      child: MaterialApp(
        theme: AppTheme.createTheme(AppRole.cashier, Brightness.dark),
        home: MediaQuery(
          data: MediaQueryData(size: screenSize),
          child: const LoginScreen(),
        ),
      ),
    );
  }

  group('LoginScreen UI Tests', () {
    testWidgets('renders desktop layout with staff directory and keypad', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createLoginWidget(screenSize: const Size(1200, 800)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('منظومة متجر الجملة VIP'), findsOneWidget);
      expect(find.text('طاقم العمل والورديات'), findsOneWidget);
      expect(find.text('أحمد كاشير'), findsWidgets);
      expect(find.text('كريم مدير المخزن'), findsOneWidget);
      expect(find.text('أدخل رمز PIN لتسجيل الدخول'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('مسح'), findsOneWidget);
    });

    testWidgets('renders mobile layout with staff selector tile', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createLoginWidget(screenSize: const Size(400, 800)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('منظومة متجر الجملة VIP'), findsOneWidget);
      expect(find.text('تبديل'), findsOneWidget);
      expect(find.text('أحمد كاشير'), findsWidgets);
      expect(find.text('أدخل رمز PIN لتسجيل الدخول'), findsOneWidget);
      expect(find.text('مسح'), findsOneWidget);
    });

    testWidgets('typing numbers on keypad updates PIN input', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createLoginWidget(screenSize: const Size(1200, 800)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Tap '1', '2', '3'
      await tester.tap(find.text('1'));
      await tester.pump();
      await tester.tap(find.text('2'));
      await tester.pump();
      await tester.tap(find.text('3'));
      await tester.pump();

      // Tap 'مسح' (Clear)
      await tester.tap(find.text('مسح'));
      await tester.pump();
    });
  });
}
