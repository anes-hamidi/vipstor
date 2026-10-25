import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinput/pinput.dart';
import 'package:domain/domain.dart';
import 'package:staff_app/features/auth/widgets/change_pin_dialog.dart';

void main() {
  const sampleStaff = UserEntity(
    id: 'staff-99',
    name: 'حسام أمين الصندوق',
    phone: '0555998877',
    role: UserRole.cashier,
    active: true,
    language: 'ar',
  );

  group('ChangePinDialog Responsive & Keyboard Tests', () {
    testWidgets('renders minimized dialog without pop-up system keyboard', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ChangePinDialog(staffMember: sampleStaff),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify title & subtitles
      expect(find.text('تغيير رمز PIN'), findsOneWidget);
      expect(find.text('أدخل رمز PIN الحالي'), findsOneWidget);
      expect(find.text('التحقق من هوية حسام أمين الصندوق'), findsOneWidget);

      // Verify step indicators
      expect(find.text('القديم'), findsOneWidget);
      expect(find.text('الجديد'), findsOneWidget);
      expect(find.text('التأكيد'), findsOneWidget);

      // Verify keypad keys
      expect(find.widgetWithText(InkWell, '1'), findsOneWidget);
      expect(find.widgetWithText(InkWell, '0'), findsOneWidget);
      expect(find.widgetWithText(InkWell, 'C'), findsOneWidget);
      expect(find.widgetWithText(InkWell, '⌫'), findsOneWidget);

      // Verify Pinput has useNativeKeyboard: false
      final pinputFinder = find.byType(Pinput);
      expect(pinputFinder, findsOneWidget);
      final pinputWidget = tester.widget<Pinput>(pinputFinder);
      expect(pinputWidget.useNativeKeyboard, isFalse,
          reason: 'Must disable native system keyboard to prevent pop-up');

      // Tap digits 1, 2, 3
      await tester.tap(find.widgetWithText(InkWell, '1'));
      await tester.pump();
      await tester.tap(find.widgetWithText(InkWell, '2'));
      await tester.pump();
      await tester.tap(find.widgetWithText(InkWell, '3'));
      await tester.pump();

      // Tap ⌫ backspace
      await tester.tap(find.widgetWithText(InkWell, '⌫'));
      await tester.pump();

      // Tap C clear
      await tester.tap(find.widgetWithText(InkWell, 'C'));
      await tester.pump();
    });

    testWidgets('adapts smoothly to tablet & desktop screens without overflow', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1024, 768));

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ChangePinDialog(staffMember: sampleStaff),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('تغيير رمز PIN'), findsOneWidget);
      expect(find.byType(Dialog), findsOneWidget);
    });
  });
}
