import '../entities/order_entity.dart';

abstract class IOrderRepository {
  Future<List<OrderEntity>> getOrders({
    OrderStatus? status,
    List<OrderStatus>? statuses,
    String? driverId,
    String? customerId,
    OrderChannel? channel,
    DateTime? createdFrom,
    DateTime? createdTo,
    int? limit,
  });
  Future<OrderEntity> getOrderById(String orderId);
  Future<String> createInStoreSale({
    required String cashierId,
    String? customerId,
    required List<Map<String, dynamic>> items,
    required int paidCashCentimes,
    required int onAccountCentimes,
  });
  Future<String> submitCustomerOrder({
    required String customerId,
    required Map<String, dynamic> address,
    required List<Map<String, dynamic>> items,
    String? clientId,
    String? deviceToken,
  });
  Future<void> confirmOrder({required String orderId, required String cashierId, String? driverId});
  Future<void> updateOrderStatus({required String orderId, required OrderStatus status, String? notes});
  Future<void> assignOrderToDriver({
    required String orderId,
    required String driverId,
    required String driverName,
    String? driverPhone,
  });
  Future<void> updateOrderPreparation({
    required String orderId,
    required String preparedBy,
    String? notes,
  });
  Future<void> recordDelivery({
    required String driverId,
    required String orderId,
    required int collectedCashCentimes,
    required String clientId,
  });
  Future<void> completeDeliveryWithProof({
    required String driverId,
    required String orderId,
    required int collectedCashCentimes,
    String? signatureBase64,
    String? photoBase64,
    double? deliveryLat,
    double? deliveryLng,
    String? notes,
    required String clientId,
  });

  // Delta sync: orders created/updated since [since].
  Future<List<OrderEntity>> getOrdersSince({
    required DateTime since,
    String? customerId,
    int limit,
  });

  // Paginated, date-filtered order fetch.
  Future<List<OrderEntity>> getOrdersPage({
    int page,
    int pageSize,
    OrderStatus? status,
    List<OrderStatus>? statuses,
    String? driverId,
    String? customerId,
    OrderChannel? channel,
    DateTime? createdFrom,
    DateTime? createdTo,
  });
}
