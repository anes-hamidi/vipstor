import '../entities/order_entity.dart';

abstract class IOrderRepository {
  Future<List<OrderEntity>> getOrders({OrderStatus? status, String? driverId, String? customerId});
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
}
