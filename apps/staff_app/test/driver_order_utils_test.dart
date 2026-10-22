import 'package:domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staff_app/features/driver/widgets/driver_order_utils.dart';

OrderEntity _order({
  String id = 'order-1234567890',
  int? orderNumber,
  OrderStatus status = OrderStatus.outForDelivery,
  int total = 250000,
  int paid = 50000,
  Map<String, dynamic>? snapshot,
  double? deliveryLat,
  double? deliveryLng,
  DateTime? createdAt,
}) {
  return OrderEntity(
    id: id,
    orderNumber: orderNumber,
    channel: OrderChannel.online,
    status: status,
    totalAmountCentimes: total,
    paidAmountCentimes: paid,
    customerSnapshot: snapshot,
    items: const [],
    deliveryLat: deliveryLat,
    deliveryLng: deliveryLng,
    createdAt: createdAt ?? DateTime(2026, 10, 22, 10),
  );
}

void main() {
  group('isOrderActive / isOrderCompleted', () {
    test('driving statuses are active', () {
      expect(isOrderActive(OrderStatus.assigned), isTrue);
      expect(isOrderActive(OrderStatus.accepted), isTrue);
      expect(isOrderActive(OrderStatus.outForDelivery), isTrue);
      expect(isOrderActive(OrderStatus.ready), isTrue);
    });

    test('terminal statuses are not active', () {
      expect(isOrderActive(OrderStatus.delivered), isFalse);
      expect(isOrderActive(OrderStatus.settled), isFalse);
      expect(isOrderActive(OrderStatus.cancelled), isFalse);
      expect(isOrderActive(OrderStatus.refused), isFalse);
    });

    test('only delivered and settled count as completed', () {
      expect(isOrderCompleted(OrderStatus.delivered), isTrue);
      expect(isOrderCompleted(OrderStatus.settled), isTrue);
      expect(isOrderCompleted(OrderStatus.cancelled), isFalse);
      expect(isOrderCompleted(OrderStatus.refused), isFalse);
    });
  });

  group('customer information fallbacks', () {
    test('prefers order fields and falls back to the snapshot', () {
      final order = _order(
        snapshot: {
          'customer_name': '',
          'store_name': 'متجر النور',
          'customer_phone': '0550112233',
          'address_text': 'حي النصر، الجزائر',
        },
      );

      expect(deliveryCustomerName(order), 'متجر النور');
      expect(deliveryCustomerPhone(order), '0550112233');
      expect(deliveryAddressText(order), 'حي النصر، الجزائر');
    });

    test('composes an address from street, commune and wilaya', () {
      final order = _order(
        snapshot: {
          'street': 'شارع ديدوش مراد',
          'commune': 'الجزائر الوسطى',
          'wilaya': 'الجزائر',
        },
      );

      expect(
        deliveryAddressText(order),
        'شارع ديدوش مراد، الجزائر الوسطى، الجزائر',
      );
    });

    test('returns safe placeholders when nothing is known', () {
      final order = _order();

      expect(deliveryCustomerName(order), 'زبون');
      expect(deliveryCustomerPhone(order), isNull);
      expect(deliveryAddressText(order), isNull);
    });
  });

  group('coordinates', () {
    test('parses snapshot coordinates before the entity fallback', () {
      final order = _order(
        snapshot: {'latitude': '36.75', 'longitude': 3.06},
        deliveryLat: 10,
        deliveryLng: 20,
      );

      expect(orderLatitude(order), 36.75);
      expect(orderLongitude(order), 3.06);
    });

    test('falls back to deliveryLat / deliveryLng', () {
      final order = _order(deliveryLat: 36.7, deliveryLng: 3.2);

      expect(orderLatitude(order), 36.7);
      expect(orderLongitude(order), 3.2);
    });

    test('returns null when the customer did not share a location', () {
      expect(orderLatitude(_order()), isNull);
      expect(orderLongitude(_order()), isNull);
    });
  });

  group('formatting', () {
    test('short order number uses the numeric number or the id prefix', () {
      expect(orderShortNumber(_order(orderNumber: 1042)), '1042');
      expect(orderShortNumber(_order(id: 'abcdef1234567890')), 'abcdef12');
      expect(orderShortNumber(_order(id: 'short')), 'short');
    });

    test('formats distances for metres and kilometres', () {
      expect(formatDistanceKm(0.45), '450 م');
      expect(formatDistanceKm(2.34), '2.3 كم');
      expect(formatDistanceKm(12.4), '12 كم');
      expect(formatDistanceKm(null), '');
      expect(formatDistanceKm(double.infinity), '');
    });

    test('formats relative time in Arabic', () {
      final now = DateTime(2026, 10, 22, 12);

      expect(formatTimeAgo(now.subtract(const Duration(minutes: 5)), now: now),
          'منذ 5 د');
      expect(formatTimeAgo(now.subtract(const Duration(hours: 3)), now: now),
          'منذ 3 س');
      expect(formatTimeAgo(now.subtract(const Duration(days: 2)), now: now),
          'منذ 2 ي');
      expect(
          formatTimeAgo(now.add(const Duration(minutes: 1)), now: now), 'الآن');
    });

    test('describes the payment situation from the due amount', () {
      expect(
        paymentSituationLabel(_order(status: OrderStatus.settled)),
        'تمت التسوية',
      );
      expect(paymentSituationLabel(_order(paid: 250000)), 'مدفوع بالكامل');
      expect(paymentSituationLabel(_order(paid: 50000)), 'دفعة جزئية');
      expect(paymentSituationLabel(_order(paid: 0)), 'تحصيل عند التسليم');
      expect(
        paymentSituationLabel(
          _order(status: OrderStatus.delivered, paid: 0),
        ),
        'على الحساب',
      );
    });

    test('due amount subtracts what was already paid', () {
      expect(_order(total: 250000, paid: 50000).dueAmountCentimes, 200000);
    });
  });
}
