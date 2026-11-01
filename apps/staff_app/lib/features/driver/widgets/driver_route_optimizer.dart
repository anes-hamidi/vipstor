import 'dart:math' as math;

import 'package:domain/domain.dart';

import 'driver_order_utils.dart';

/// Builds a deterministic nearest-neighbour route from the driver's current
/// position (or from the oldest located stop when GPS is unavailable).
///
/// Orders without coordinates cannot be optimized, so they are appended after
/// the located stops in FIFO order. The function is pure and returns order IDs
/// so the UI can keep its own manual sequencing state.
List<String> optimizeDeliveryRoute(
  List<OrderEntity> orders, {
  double? startLat,
  double? startLng,
}) {
  if (orders.isEmpty) return const [];

  final located = <_RoutePoint>[];
  final unlocated = <OrderEntity>[];

  for (var i = 0; i < orders.length; i++) {
    final order = orders[i];
    final lat = orderLatitude(order);
    final lng = orderLongitude(order);
    if (lat == null || lng == null) {
      unlocated.add(order);
    } else {
      located.add(_RoutePoint(order: order, lat: lat, lng: lng, index: i));
    }
  }

  located.sort((a, b) {
    final created = a.order.createdAt.compareTo(b.order.createdAt);
    return created != 0 ? created : a.index.compareTo(b.index);
  });
  unlocated.sort((a, b) {
    final created = a.createdAt.compareTo(b.createdAt);
    return created != 0 ? created : a.id.compareTo(b.id);
  });

  final remaining = List<_RoutePoint>.of(located);
  final sequence = <String>[];
  double? currentLat = startLat;
  double? currentLng = startLng;

  if ((currentLat == null || currentLng == null) && remaining.isNotEmpty) {
    final first = remaining.removeAt(0);
    sequence.add(first.order.id);
    currentLat = first.lat;
    currentLng = first.lng;
  }

  while (remaining.isNotEmpty) {
    var bestIndex = 0;
    var bestDistance = double.infinity;

    for (var i = 0; i < remaining.length; i++) {
      final point = remaining[i];
      final distance = _haversineKm(
        currentLat!,
        currentLng!,
        point.lat,
        point.lng,
      );
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }

    final next = remaining.removeAt(bestIndex);
    sequence.add(next.order.id);
    currentLat = next.lat;
    currentLng = next.lng;
  }

  sequence.addAll(unlocated.map((order) => order.id));
  return sequence;
}

double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const earthRadiusKm = 6371.0;
  final dLat = _radians(lat2 - lat1);
  final dLng = _radians(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_radians(lat1)) *
          math.cos(_radians(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusKm * c;
}

double _radians(double degrees) => degrees * math.pi / 180.0;

class _RoutePoint {
  final OrderEntity order;
  final double lat;
  final double lng;
  final int index;

  const _RoutePoint({
    required this.order,
    required this.lat,
    required this.lng,
    required this.index,
  });
}
