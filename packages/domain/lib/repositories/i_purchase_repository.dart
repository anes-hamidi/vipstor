import '../entities/purchase_entity.dart';

abstract class IPurchaseRepository {
  Future<List<Map<String, dynamic>>> getSuppliers();
  Future<Map<String, dynamic>> createSupplier({
    required String name,
    required String phone,
    String? companyRegister,
    String? notes,
  });
  Future<List<SupplierProfileEntity>> getSuppliersWithBalances();
  Future<SupplierProfileEntity?> getSupplierById(String supplierId);
  Future<List<PurchaseEntity>> getUnpaidPurchasesBySupplier(String supplierId);
  Future<SupplierPaymentResult> recordSupplierPayment({
    required String supplierId,
    required int amountCentimes,
    required String payerUserId,
    required String payerName,
    required String payerRole,
    String? purchaseId,
    String? notes,
  });
  Future<List<PurchaseEntity>> getPurchases();
  Future<String> createDraftPurchase({
    required String supplierId,
    required String invoiceNo,
    DateTime? invoiceDate,
    String? createdBy,
    List<Map<String, dynamic>> items = const [],
  });
  Future<void> postPurchase({
    required String purchaseId,
    required String userId,
    List<Map<String, dynamic>> items = const [],
  });
}

