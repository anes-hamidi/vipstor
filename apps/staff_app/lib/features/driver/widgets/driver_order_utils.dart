import 'package:domain/domain.dart';

/// Shared presentation helpers for the driver delivery workflow.
///
/// Keeping these helpers in one place avoids subtle differences between the
/// list, map, proof-of-delivery dialog and wallet sheet (address keys, phone
/// fallbacks, status classification, date formatting, ...).

bool isOrderActive(OrderStatus status) {
  switch (status) {
    case OrderStatus.delivered:
    case OrderStatus.settled:
    case OrderStatus.cancelled:
    case OrderStatus.refused:
      return false;
    case OrderStatus.submitted:
    case OrderStatus.confirmed:
    case OrderStatus.preparing:
    case OrderStatus.ready:
    case OrderStatus.assigned:
    case OrderStatus.accepted:
    case OrderStatus.outForDelivery:
    case OrderStatus.requiresManagerReview:
      return true;
  }
}

bool isOrderCompleted(OrderStatus status) =>
    status == OrderStatus.delivered || status == OrderStatus.settled;

String deliveryCustomerName(OrderEntity order) {
  final snapshot = order.customerSnapshot;
  return _firstNonEmpty([
        order.customerName,
        snapshot?['customer_name'],
        snapshot?['store_name'],
        snapshot?['full_name'],
        snapshot?['name'],
      ]) ??
      'زبون';
}

String? deliveryCustomerPhone(OrderEntity order) {
  final snapshot = order.customerSnapshot;
  return _firstNonEmpty([
    order.customerPhone,
    snapshot?['customer_phone'],
    snapshot?['phone'],
    snapshot?['phone_number'],
  ]);
}

String? deliveryAddressText(OrderEntity order) {
  final snapshot = order.customerSnapshot;
  if (snapshot == null) return null;

  final direct = _firstNonEmpty([
    snapshot['address'],
    snapshot['address_text'],
    snapshot['full_address'],
  ]);
  if (direct != null) return direct;

  final parts = <String>[
    if (_firstNonEmpty([snapshot['street']]) != null)
      _firstNonEmpty([snapshot['street']])!,
    if (_firstNonEmpty([snapshot['locality'], snapshot['commune']]) != null)
      _firstNonEmpty([snapshot['locality'], snapshot['commune']])!,
    if (_firstNonEmpty([snapshot['wilaya'], snapshot['city']]) != null)
      _firstNonEmpty([snapshot['wilaya'], snapshot['city']])!,
  ];
  if (parts.isNotEmpty) return parts.join('، ');

  return null;
}

double? orderLatitude(OrderEntity order) {
  final snapshot = order.customerSnapshot;
  return _asDouble(snapshot?['latitude']) ??
      _asDouble(snapshot?['lat']) ??
      order.deliveryLat;
}

double? orderLongitude(OrderEntity order) {
  final snapshot = order.customerSnapshot;
  return _asDouble(snapshot?['longitude']) ??
      _asDouble(snapshot?['lng']) ??
      _asDouble(snapshot?['lon']) ??
      order.deliveryLng;
}

String orderShortNumber(OrderEntity order) {
  final number = order.orderNumber;
  if (number != null) return number.toString();
  final id = order.id;
  return id.length <= 8 ? id : id.substring(0, 8);
}

String? deliveryNote(OrderEntity order) {
  final note = order.notes?.trim();
  return note == null || note.isEmpty ? null : note;
}

String paymentSituationLabel(OrderEntity order) {
  if (order.status == OrderStatus.settled) return 'تمت التسوية';
  if (order.dueAmountCentimes <= 0) return 'مدفوع بالكامل';
  if (order.paidAmountCentimes > 0) return 'دفعة جزئية';
  if (isOrderCompleted(order.status)) return 'على الحساب';
  return 'تحصيل عند التسليم';
}

String formatDistanceKm(double? km) {
  if (km == null || km.isNaN || km.isInfinite || km < 0) return '';
  if (km < 1) return '${(km * 1000).round()} م';
  return '${km.toStringAsFixed(km >= 10 ? 0 : 1)} كم';
}

/// Friendly relative time used on delivery cards.
String formatTimeAgo(DateTime dateTime, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final local = dateTime.toLocal();
  final diff = reference.difference(local);

  if (diff.isNegative) return 'الآن';
  if (diff.inMinutes < 1) return 'الآن';
  if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} د';

  final hours = diff.inHours;
  if (hours < 24) return 'منذ $hours س';

  final days = diff.inDays;
  if (days < 7) return 'منذ $days ي';

  return formatDateShort(local);
}

String formatDateShort(DateTime dateTime) {
  final local = dateTime.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  return '$day/$month/${local.year}';
}

String formatDateTimeShort(DateTime dateTime) {
  final local = dateTime.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${formatDateShort(local)} • $hour:$minute';
}

String formatTime(DateTime dateTime) {
  final local = dateTime.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String? _firstNonEmpty(List<Object?> values) {
  for (final value in values) {
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) return trimmed;
    } else if (value != null) {
      final text = value.toString().trim();
      if (text.isNotEmpty && text != 'null') return text;
    }
  }
  return null;
}

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}
