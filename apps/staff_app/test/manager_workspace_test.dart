import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:domain/domain.dart';
import 'package:staff_app/features/manager/widgets/purchase_orders_view.dart';

void main() {
  const item = PurchaseOrderItemEntity(
    id: 'line-1',
    productId: 'product-1',
    productName: 'عطر مسك الذهب',
    unit: 'قطعة',
    orderedQty: 10,
    receivedQty: 4,
    unitCostCentimes: 100000,
    sellingPriceCentimes: 150000,
  );

  PurchaseOrderEntity buildOrder({
    PurchaseOrderStatus status = PurchaseOrderStatus.ordered,
  }) {
    return PurchaseOrderEntity(
      id: 'po-1',
      poNumber: 'PO-2026-00042',
      supplierId: 'supplier-1',
      supplierName: 'مؤسسة النور للتوريد',
      status: status,
      orderDate: DateTime(2026, 10, 1),
      expectedDeliveryDate: DateTime(2026, 10, 8),
      createdByUserId: 'manager-1',
      createdByName: 'مدير المخزون',
      items: const [item],
    );
  }

  Widget host(Widget child) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );
  }

  group('Purchase order workspace widgets', () {
    testWidgets('ordered PO exposes GRN receiving and progress',
        (tester) async {
      var received = false;
      final order = buildOrder(status: PurchaseOrderStatus.partiallyReceived);

      await tester.pumpWidget(
        host(
          PurchaseOrderCard(
            purchaseOrder: order,
            onTap: () {},
            onReceive: () => received = true,
            onCancel: () {},
          ),
        ),
      );

      expect(find.text('PO-2026-00042'), findsOneWidget);
      expect(find.text('مؤسسة النور للتوريد'), findsOneWidget);
      expect(find.textContaining('تم استلام 4 من 10'), findsOneWidget);
      expect(find.text('استلام (GRN)'), findsOneWidget);

      await tester.tap(find.text('استلام (GRN)'));
      await tester.pump();
      expect(received, isTrue);
    });

    testWidgets('draft PO can be sent to the supplier', (tester) async {
      var sent = false;
      final order = buildOrder(status: PurchaseOrderStatus.draft);

      await tester.pumpWidget(
        host(
          PurchaseOrderCard(
            purchaseOrder: order,
            onTap: () {},
            onSend: () => sent = true,
            onCancel: () {},
          ),
        ),
      );

      expect(find.text('إرسال للمورد'), findsOneWidget);
      expect(find.text('استلام (GRN)'), findsNothing);

      await tester.tap(find.text('إرسال للمورد'));
      await tester.pump();
      expect(sent, isTrue);
    });

    testWidgets('completed PO has no lifecycle action bar', (tester) async {
      final order = buildOrder(status: PurchaseOrderStatus.fullyReceived);

      await tester.pumpWidget(
        host(
          PurchaseOrderCard(
            purchaseOrder: order,
            onTap: () {},
          ),
        ),
      );

      expect(find.text('إرسال للمورد'), findsNothing);
      expect(find.text('استلام (GRN)'), findsNothing);
      expect(find.text('إلغاء'), findsNothing);
      expect(find.textContaining('تم استلام 4 من 10'), findsOneWidget);
    });
  });
}
