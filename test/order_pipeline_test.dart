import 'package:flutter_test/flutter_test.dart';
import 'package:domain/domain.dart';

void main() {
  group('Online Orders & Pipeline Domain Tests', () {
    test('OrderStatus serialization and state transitions', () {
      expect(OrderStatus.fromString('submitted'), OrderStatus.submitted);
      expect(OrderStatus.fromString('confirmed'), OrderStatus.confirmed);
      expect(OrderStatus.fromString('preparing'), OrderStatus.preparing);
      expect(OrderStatus.fromString('ready'), OrderStatus.ready);
      expect(OrderStatus.fromString('assigned'), OrderStatus.assigned);
      expect(OrderStatus.fromString('out_for_delivery'), OrderStatus.outForDelivery);
      expect(OrderStatus.fromString('delivered'), OrderStatus.delivered);

      expect(OrderStatus.outForDelivery.dbValue, 'out_for_delivery');
      expect(OrderStatus.submitted.dbValue, 'submitted');
    });

    test('OrderEntity creation and copyWith', () {
      final order = OrderEntity(
        id: 'order-123',
        channel: OrderChannel.online,
        status: OrderStatus.submitted,
        totalAmountCentimes: 500000,
        paidAmountCentimes: 0,
        customerSnapshot: const {
          'customer_name': 'Superette Essalam',
          'phone': '+213555123456',
          'latitude': 36.7538,
          'longitude': 3.0588,
          'address': 'Alger Centre',
        },
        items: const [
          OrderItemEntity(
            id: 'item-1',
            productId: 'prod-1',
            productName: 'Huile Elio 5L',
            quantity: 10,
            unitPriceCentimes: 50000,
            unitCostCentimes: 45000,
          ),
        ],
        createdAt: DateTime.now(),
      );

      expect(order.dueAmountCentimes, 500000);
      expect(order.items.first.lineTotalCentimes, 500000);
      expect(order.customerSnapshot?['latitude'], 36.7538);

      // Transition to confirmed
      final confirmed = order.copyWith(status: OrderStatus.confirmed);
      expect(confirmed.status, OrderStatus.confirmed);

      // Transition to prepared
      final ready = confirmed.copyWith(
        status: OrderStatus.ready,
        preparedBy: 'Manager Ahmed',
      );
      expect(ready.status, OrderStatus.ready);
      expect(ready.preparedBy, 'Manager Ahmed');

      // Transition to assigned to driver
      final assigned = ready.copyWith(
        status: OrderStatus.assigned,
        driverId: 'driver-007',
        driverName: 'Karim Driver',
        driverPhone: '+213661234567',
      );
      expect(assigned.driverId, 'driver-007');
      expect(assigned.driverName, 'Karim Driver');

      // Transition to delivered with proof
      final delivered = assigned.copyWith(
        status: OrderStatus.delivered,
        paidAmountCentimes: 500000,
        signatureBase64: 'data:image/png;base64,signature...',
        photoBase64: 'data:image/jpeg;base64,photo...',
        deliveryLat: 36.7540,
        deliveryLng: 3.0590,
      );
      expect(delivered.status, OrderStatus.delivered);
      expect(delivered.dueAmountCentimes, 0);
      expect(delivered.signatureBase64, isNotNull);
      expect(delivered.photoBase64, isNotNull);
      expect(delivered.deliveryLat, 36.7540);
    });
  });
}
