import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staff_app/features/driver/widgets/delivery_order_card.dart';
import 'package:ui_kit/ui_kit.dart';

OrderEntity _order({OrderStatus status = OrderStatus.outForDelivery}) {
  return OrderEntity(
    id: 'order-card-123456',
    orderNumber: 1042,
    channel: OrderChannel.online,
    customerName: 'سامي بن أحمد',
    customerPhone: '0550112233',
    status: status,
    totalAmountCentimes: 1250000,
    paidAmountCentimes: 250000,
    customerSnapshot: const {
      'address_text': 'حي النصر، شارع الأمير عبد القادر، الجزائر الوسطى',
      'latitude': 36.7538,
      'longitude': 3.0588,
    },
    items: const [
      OrderItemEntity(
        id: 'item-1',
        productId: 'product-1',
        productName: 'كرتون زيت الزيتون',
        quantity: 2,
        unitPriceCentimes: 500000,
        unitCostCentimes: 0,
      ),
    ],
    createdAt: DateTime(2026, 10, 22, 9, 30),
  );
}

Future<void> _pumpCard(
  WidgetTester tester,
  Widget card, {
  required Size size,
  ThemeMode themeMode = ThemeMode.light,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: card,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('delivery card fits a narrow phone and offers active actions', (
    tester,
  ) async {
    await _pumpCard(
      tester,
      DeliveryOrderCard(
        order: _order(),
        stopNumber: 3,
        distanceKm: 1.8,
        onNavigate: () {},
        onCall: () {},
        onDeliver: () {},
      ),
      size: const Size(320, 900),
    );

    expect(find.text('المطلوب تحصيله'), findsOneWidget);
    expect(find.text('تأكيد التسليم'), findsOneWidget);
    expect(find.text('الملاحة'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('delivery card lays out actions in a row on a wide surface', (
    tester,
  ) async {
    await _pumpCard(
      tester,
      DeliveryOrderCard(
        order: _order(),
        stopNumber: 1,
        distanceKm: 0.4,
        onNavigate: () {},
        onCall: () {},
        onDeliver: () {},
      ),
      size: const Size(900, 900),
      themeMode: ThemeMode.dark,
    );

    expect(find.text('المطلوب تحصيله'), findsOneWidget);
    expect(find.text('تأكيد التسليم'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('completed card explains that the task is done', (tester) async {
    await _pumpCard(
      tester,
      DeliveryOrderCard(
        order: _order(status: OrderStatus.delivered),
        distanceKm: 0.4,
      ),
      size: const Size(420, 900),
    );

    expect(find.text('تم إنجاز هذه المهمة بنجاح'), findsOneWidget);
    expect(find.text('تأكيد التسليم'), findsNothing);
    expect(find.text('المحصل نقداً'), findsOneWidget);
    expect(find.text('المتبقي على الحساب'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
