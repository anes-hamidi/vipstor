import '../entities/customer_entity.dart';
import '../entities/customer_ledger_entity.dart';

abstract class ICustomerRepository {
  Future<List<CustomerProfileEntity>> getCustomers({String? search});
  Future<CustomerProfileEntity?> getCustomerById(String customerId);
  Future<CustomerProfileEntity> createCustomer({
    required String name,
    required String phone,
    required String callerId,
    required String callerPin,
    int creditLimitCentimes = 0,
    String priceTier = 'wholesale',
  });
  Future<CustomerProfileEntity?> getCustomerByPhone(
    String phone, {
    required String deviceToken,
  });
  Future<CustomerProfileEntity> syncCustomerProfile({
    required String name,
    required String phone,
    required String wilaya,
    required String commune,
    required String addressText,
    required String deviceToken,
    double? latitude,
    double? longitude,
    String? existingCustomerId,
    String? existingUserId,
  });
  Future<List<CustomerLedgerEntryEntity>> getCustomerLedger(String customerId);
  Future<List<CustomerUnpaidOrderEntity>> getCustomerUnpaidOrders(String customerId);
  Future<CustomerDebtPaymentResult> collectCustomerDebt({
    required String cashierId,
    required String customerId,
    required int amountCentimes,
    required String paymentMethod,
    String? notes,
    String? referenceNumber,
  });
}

