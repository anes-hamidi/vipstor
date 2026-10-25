import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:domain/domain.dart';
import 'package:staff_app/features/manager/widgets/order_state_inspector.dart';

void main() {
  group('Manager Redesign & Multi-Status Order Architecture Tests', () {
    final sampleOrder = OrderEntity(
      id: 'order-12345678-test',
      orderNumber: 1042,
      channel: OrderChannel.online,
      customerId: 'cust-999',
      customerName: 'كريم بلحاج',
      customerPhone: '0555123456',
      status: OrderStatus.confirmed,
      totalAmountCentimes: 450000,
      paidAmountCentimes: 450000,
      createdAt: DateTime.now(),
      items: const [
        OrderItemEntity(
          id: 'item-1',
          productId: 'prod-1',
          productName: 'عطر مسك الذهب',
          quantity: 3,
          unitPriceCentimes: 150000,
          unitCostCentimes: 90000,
        ),
      ],
    );

    testWidgets('OrderStateStepper renders explicit state machine stages', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: OrderStateStepper(
                status: sampleOrder.status,
                compact: false,
              ),
            ),
          ),
        ),
      );

      // Verify the state machine stages from the architectural specification
      expect(find.text('مسار دورة حياة الطلبية وحجز المخزون'), findsOneWidget);
      expect(find.text('مسودة واردة'), findsOneWidget);
      expect(find.text('مؤكد ومحجوز'), findsWidgets);
      expect(find.text('تجهيز وتغليف'), findsOneWidget);
      expect(find.text('شحن مع السائق'), findsOneWidget);
      expect(find.text('تسليم وتسوية'), findsOneWidget);
    });

    testWidgets('CustomerLedgerSyncCard renders customer ledger balance synchronization', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CustomerLedgerSyncCard(
                order: sampleOrder,
              ),
            ),
          ),
        ),
      );

      // Verify customer info
      expect(find.text('كريم بلحاج'), findsOneWidget);
      expect(find.textContaining('0555123456'), findsOneWidget);

      // Verify ledger synchronization indicator
      expect(find.text('مزامنة دفتر أستاذ الزبون (Customer Ledger)'), findsOneWidget);
      expect(find.text('مربوط آلياً'), findsOneWidget);
    });

    testWidgets('OrderStockAllocationCard displays decoupled reserved vs available stock', (tester) async {
      final sampleProducts = [
        const ProductEntity(
          id: 'prod-1',
          nameAr: 'عطر مسك الذهب',
          nameFr: 'Musk Gold',
          category: 'عطور',
          unit: 'قطعة',
          packSize: 1,
          costCentimes: 90000,
          active: true,
          barcodes: ['123456789'],
          prices: [],
          availableQty: 10,
          onHandQty: 15, // 5 units temporarily reserved for other orders
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: OrderStockAllocationCard(
                order: sampleOrder,
                products: sampleProducts,
              ),
            ),
          ),
        ),
      );

      // Verify stock allocation decoupling rule
      expect(find.text('قاعدة تخصيص وحجز المخزون (Stock Allocation)'), findsOneWidget);
      expect(find.textContaining('10'), findsWidgets);
      expect(find.textContaining('15'), findsWidgets);
      expect(find.text('مخزون محجوز مؤقتاً'), findsOneWidget);
    });
  });
}
