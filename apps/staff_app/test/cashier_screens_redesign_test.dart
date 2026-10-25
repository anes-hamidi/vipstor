import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:data/data.dart';
import 'package:staff_app/features/cashier/widgets/pos_checkout_dialog.dart';
import 'package:staff_app/features/cashier/widgets/custom_item_dialog.dart';
import 'package:staff_app/features/cashier/widgets/item_discount_dialog.dart';
import 'package:staff_app/features/cashier/widgets/shift_audit_dialog.dart';
import 'package:staff_app/features/cashier/widgets/printer_settings_dialog.dart';
import 'package:staff_app/features/cashier/widgets/cashier_pin_dialog.dart';
import 'package:staff_app/features/cashier/models/pos_models.dart';
import 'package:staff_app/providers/staff_providers.dart';
import 'package:ui_kit/ui_kit.dart';

class FakePosShiftNotifier extends PosShiftNotifier {
  FakePosShiftNotifier([PosShiftSession? initial])
      : super(
          localStore: const StaffLocalAuthStore(),
          db: AppDatabase(),
          client: null,
        ) {
    state = initial;
  }

  @override
  void openShift({
    required String cashierId,
    required String cashierName,
    required int openingFloatCentimes,
  }) {
    state = PosShiftSession(
      id: 'mock-shift-1',
      cashierId: cashierId,
      cashierName: cashierName,
      openedAt: DateTime.now(),
      openingFloatCentimes: openingFloatCentimes,
      zReportNumber: 1,
    );
  }

  @override
  ZReportSummary closeShift({
    required int countedCashCentimes,
    required Map<int, int> denominations,
  }) {
    final current = state ??
        PosShiftSession(
          id: 'mock-shift-1',
          cashierId: 'cashier-1',
          cashierName: 'محمد أحمد',
          openedAt: DateTime.now(),
          openingFloatCentimes: 1000000,
          zReportNumber: 1,
        );
    final summary = ZReportSummary(
      zNumber: current.zReportNumber,
      cashierName: current.cashierName,
      openedAt: current.openedAt,
      closedAt: DateTime.now(),
      openingFloatCentimes: current.openingFloatCentimes,
      cashSalesCentimes: current.cashSalesCentimes,
      creditSalesCentimes: current.creditSalesCentimes,
      collectedDebtCashCentimes: current.collectedDebtCashCentimes,
      supplierPaymentsCashCentimes: current.supplierPaymentsCashCentimes,
      driverSettlementCashCentimes: current.driverSettlementCashCentimes,
      totalSalesCentimes:
          current.cashSalesCentimes + current.creditSalesCentimes,
      returnsCentimes: current.returnsCentimes,
      expectedCashCentimes: current.expectedCashInDrawerCentimes,
      countedCashCentimes: countedCashCentimes,
      varianceCentimes: 0,
      denominations: denominations,
    );
    state = null;
    return summary;
  }
}

void main() {
  group('Cashier Screens Redesign & Responsive Verification Tests', () {
    testWidgets('PosCheckoutDialog renders as a full responsive Scaffold screen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: const PosCheckoutDialog(totalCentimes: 150000), // 1,500 DZD
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('إتمام الدفع وتحصيل الوصل'), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);

      expect(find.text('نقدًا بالكامل'), findsOneWidget);
      expect(find.text('دين على الحساب'), findsOneWidget);
      expect(find.text('دفع مجزأ'), findsOneWidget);

      expect(find.text('كامل المبلغ (بدون باقي)'), findsOneWidget);
      expect(find.text('5000 دج'), findsOneWidget);
      expect(find.text('2000 دج'), findsOneWidget);

      expect(find.text('7'), findsOneWidget);
      expect(find.text('8'), findsOneWidget);
      expect(find.text('9'), findsOneWidget);
      expect(find.text('C'), findsOneWidget);
    });

    testWidgets('CustomItemDialog renders as a full responsive Scaffold screen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: const CustomItemDialog(),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('إضافة منتج يدوي / غير مسجل'), findsOneWidget);
      expect(find.text('اسم / وصف المنتج أو الخدمة *'), findsOneWidget);
      expect(find.text('سعر الوحدة (دج) *'), findsOneWidget);
    });

    testWidgets('ItemDiscountDialog renders as a full responsive Scaffold screen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));

      const mockItem = PosCartItem(
        id: 'cart-1',
        productId: 'prod-1',
        nameAr: 'شوكولاتة فاخرة',
        nameFr: 'Chocolat',
        barcode: '123456789',
        quantity: 2,
        baseUnitPriceCentimes: 50000,
        unitCostCentimes: 30000,
        availableStock: 50,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: const ItemDiscountDialog(item: mockItem),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('تخفيض: شوكولاتة فاخرة'), findsOneWidget);
      expect(find.text('نسبة مئوية (%)'), findsOneWidget);
      expect(find.text('مبلغ مالي ثابت (دج)'), findsOneWidget);
    });

    testWidgets('ShiftAuditDialog renders open shift screen with float presets', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 700));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            posActiveShiftProvider.overrideWith((ref) => FakePosShiftNotifier()),
          ],
          child: const MaterialApp(
            home: ShiftAuditDialog(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.text('فتح وردية صندوق جديدة'), findsOneWidget);
      expect(find.text('بدء جلسة ووردية عمل جديدة'), findsOneWidget);
      expect(find.text('10000 دج'), findsOneWidget);
      expect(find.text('تأكيد فتح الوردية وبدء البيع'), findsOneWidget);
    });

    testWidgets('PrinterSettingsDialog renders with USB and LAN printer tabs', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 700));

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: PrinterSettingsDialog(autoScan: false),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.text('إعدادات طابعات الإيصالات الحرارية'), findsOneWidget);
      expect(find.text('اختبار فتح الدرج (Kick)'), findsOneWidget);
      expect(find.text('الطابعات المتصلة والمكتشفة تلقائيًا:'), findsOneWidget);
      expect(find.text('ربط طابعة إيصالات عبر كابل الشبكة LAN (Port 9100):'), findsOneWidget);
    });

    testWidgets('CashierPinDialog renders full luxury authentication screen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: CashierPinDialog(mode: CashierPinMode.switchCashier),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.text('المصادقة بواسطة رمز PIN'), findsOneWidget);
      expect(find.text('C'), findsOneWidget);
      expect(find.text('⌫'), findsOneWidget);
      expect(find.text('تأكيد الرمز'), findsOneWidget);
    });
  });
}
