import 'package:customer_app/models/customer_models.dart';
import 'package:customer_app/services/customer_local_store.dart';
import 'package:domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

OrderEntity _order({
  required String id,
  String? clientId,
  List<OrderItemEntity> items = const [],
}) {
  return OrderEntity(
    id: id,
    clientId: clientId,
    channel: OrderChannel.online,
    status: OrderStatus.delivered,
    totalAmountCentimes: 1200,
    paidAmountCentimes: 0,
    items: items,
    createdAt: DateTime(2026, 10, 20, 12, 30),
    confirmedAt: DateTime(2026, 10, 20, 13),
    deliveredAt: DateTime(2026, 10, 20, 15),
    settledAt: DateTime(2026, 10, 21, 9),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('order JSON', () {
    test('round-trips lifecycle timestamps and the client id', () {
      final original = _order(
        id: 'order-1',
        clientId: 'client-1',
        items: const [
          OrderItemEntity(
            id: 'item-1',
            productId: 'product-1',
            productName: 'زيت',
            quantity: 3,
            unitPriceCentimes: 400,
            unitCostCentimes: 300,
          ),
        ],
      );

      final restored = orderFromJson(orderToJson(original));

      expect(restored.id, 'order-1');
      expect(restored.clientId, 'client-1');
      expect(restored.status, OrderStatus.delivered);
      expect(restored.confirmedAt, DateTime(2026, 10, 20, 13));
      expect(restored.deliveredAt, DateTime(2026, 10, 20, 15));
      expect(restored.settledAt, DateTime(2026, 10, 21, 9));
      expect(restored.items.single.quantity, 3);
    });
  });

  group('CustomerLocalStore', () {
    test('persists and reloads a pending offline checkout', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = CustomerLocalStore(prefs);

      final pending = PendingOrder(
        clientId: 'client-9',
        customerId: 'customer-1',
        deliveryAddress: const {
          'wilaya': 'الجزائر',
          'commune': 'باب الوادي',
          'latitude': 36.75,
          'longitude': 3.06,
        },
        items: const [
          PendingOrderItem(
            productId: 'product-1',
            name: 'زيت زيتون',
            unit: 'carton',
            quantity: 2,
            unitPriceCentimes: 1500,
          ),
        ],
        totalAmountCentimes: 3000,
        createdAt: DateTime(2026, 10, 20, 12),
      );

      await store.upsertPendingOrder(pending);
      final loaded = await store.readPendingOrders();

      expect(loaded, hasLength(1));
      expect(loaded.single.clientId, 'client-9');
      expect(loaded.single.deliveryAddress['wilaya'], 'الجزائر');
      expect(loaded.single.items.single.name, 'زيت زيتون');
      expect(loaded.single.totalAmountCentimes, 3000);
      expect(loaded.single.toOrderEntity().clientId, 'client-9');
    });

    test('replaces a queued order with the same client id', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = CustomerLocalStore(prefs);

      PendingOrder pending(String clientId, String productId) => PendingOrder(
            clientId: clientId,
            customerId: null,
            deliveryAddress: const {},
            items: [
              PendingOrderItem(
                productId: productId,
                name: productId,
                unit: 'piece',
                quantity: 1,
                unitPriceCentimes: 100,
              ),
            ],
            totalAmountCentimes: 100,
            createdAt: DateTime(2026, 10, 20),
          );

      await store.upsertPendingOrder(pending('client-a', 'old'));
      await store.upsertPendingOrder(pending('client-a', 'new'));

      final loaded = await store.readPendingOrders();
      expect(loaded, hasLength(1));
      expect(loaded.single.items.single.productId, 'new');
    });

    test('records order affinity once per order id', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = CustomerLocalStore(prefs);

      const items = [
        OrderItemEntity(
          id: 'i1',
          productId: 'product-1',
          productName: 'زيت',
          quantity: 1,
          unitPriceCentimes: 100,
          unitCostCentimes: 50,
        ),
      ];

      await store.recordOrderAffinity([_order(id: 'o1', items: items)]);
      await store.recordOrderAffinity([_order(id: 'o1', items: items)]);
      await store.recordOrderAffinity([_order(id: 'o2', items: items)]);

      expect(await store.readAffinity(), {'product-1': 2});
    });

    test('cart json survives a store instance restart', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = CustomerLocalStore(prefs);

      await store.writeCartJson('[{"productId":"p1","quantity":2}]');

      final restarted = CustomerLocalStore(prefs);
      expect(
        await restarted.readCartJson(),
        '[{"productId":"p1","quantity":2}]',
      );

      await restarted.clearCart();
      expect(await store.readCartJson(), isNull);
    });

    test('wallet snapshot round-trip keeps credit usage', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = CustomerLocalStore(prefs);

      final wallet = WalletSnapshot(
        customerId: 'customer-1',
        customerName: 'محمد',
        creditLimitCentimes: 100000,
        currentDebtCentimes: 25000,
        fetchedAt: DateTime(2026, 10, 20, 9),
      );

      expect(wallet.remainingCreditCentimes, 75000);
      expect(wallet.creditUsage, 0.25);

      await store.writeWallet(wallet);
      final loaded = await store.readWallet();

      expect(loaded, isNotNull);
      expect(loaded!.customerName, 'محمد');
      expect(loaded.creditLimitCentimes, 100000);
      expect(loaded.currentDebtCentimes, 25000);
      expect(loaded.fetchedAt, DateTime(2026, 10, 20, 9));
    });
  });
}
