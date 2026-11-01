import 'package:domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staff_app/features/driver/widgets/driver_route_optimizer.dart';

OrderEntity _order({
  required String id,
  required DateTime createdAt,
  double? lat,
  double? lng,
}) {
  return OrderEntity(
    id: id,
    channel: OrderChannel.online,
    status: OrderStatus.assigned,
    totalAmountCentimes: 100000,
    paidAmountCentimes: 0,
    customerSnapshot: lat == null || lng == null
        ? null
        : <String, dynamic>{'latitude': lat, 'longitude': lng},
    items: const [],
    createdAt: createdAt,
  );
}

void main() {
  group('optimizeDeliveryRoute', () {
    test('starts at the driver and picks the nearest stop each time', () {
      final orders = [
        _order(
          id: 'far',
          lat: 0.02,
          lng: 0,
          createdAt: DateTime(2026, 10, 22, 8),
        ),
        _order(
          id: 'nearest',
          lat: -0.01,
          lng: 0,
          createdAt: DateTime(2026, 10, 22, 9),
        ),
        _order(
          id: 'middle',
          lat: 0.03,
          lng: 0,
          createdAt: DateTime(2026, 10, 22, 10),
        ),
        _order(
          id: 'unlocated',
          createdAt: DateTime(2026, 10, 22, 7),
        ),
      ];

      expect(
        optimizeDeliveryRoute(orders, startLat: 0, startLng: 0),
        ['nearest', 'far', 'middle', 'unlocated'],
      );
    });

    test('falls back to the oldest located stop without a GPS start', () {
      final orders = [
        _order(
          id: 'newest',
          lat: 0.04,
          lng: 0,
          createdAt: DateTime(2026, 10, 22, 10),
        ),
        _order(
          id: 'oldest',
          lat: 0.02,
          lng: 0,
          createdAt: DateTime(2026, 10, 22, 8),
        ),
        _order(
          id: 'middle',
          lat: 0.015,
          lng: 0,
          createdAt: DateTime(2026, 10, 22, 9),
        ),
      ];

      expect(
        optimizeDeliveryRoute(orders),
        ['oldest', 'middle', 'newest'],
      );
    });

    test('keeps every order exactly once and appends unlocated stops', () {
      final orders = [
        _order(
            id: 'a', lat: 36.75, lng: 3.06, createdAt: DateTime(2026, 10, 22)),
        _order(
          id: 'b',
          lat: 36.76,
          lng: 3.05,
          createdAt: DateTime(2026, 10, 22, 1),
        ),
        _order(id: 'c', createdAt: DateTime(2026, 10, 22, 2)),
        _order(id: 'd', createdAt: DateTime(2026, 10, 22, 3)),
      ];

      final result = optimizeDeliveryRoute(
        orders,
        startLat: 36.74,
        startLng: 3.07,
      );

      expect(result, hasLength(orders.length));
      expect(result.toSet(), equals(orders.map((order) => order.id).toSet()));
      expect(result.sublist(result.length - 2), ['c', 'd']);
    });

    test('handles an empty queue', () {
      expect(optimizeDeliveryRoute(const []), isEmpty);
    });
  });
}
