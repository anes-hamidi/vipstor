import 'package:domain/domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../datasources/remote/supabase_service.dart';

class PurchaseRepositoryImpl implements IPurchaseRepository {
  final SupabaseClient client;
  final SupabaseService service;

  PurchaseRepositoryImpl({required this.client, required this.service});

  @override
  Future<List<Map<String, dynamic>>> getSuppliers() async {
    final rows = await client.from('suppliers').select('id, name, phone, company_register, notes').order('name');
    return List<Map<String, dynamic>>.from(rows as List);
  }

  @override
  Future<Map<String, dynamic>> createSupplier({
    required String name,
    required String phone,
    String? companyRegister,
    String? notes,
  }) async {
    final row = await client.from('suppliers').insert({
      'name': name.trim(),
      'phone': phone.trim(),
      'company_register': companyRegister?.trim(),
      'notes': notes?.trim(),
    }).select().single();

    return Map<String, dynamic>.from(row);
  }

  @override
  Future<List<PurchaseEntity>> getPurchases() async {

    final rows = await client.from('purchases').select('''
      id,
      supplier_id,
      invoice_no,
      invoice_date,
      status,
      total_amount,
      posted_at,
      suppliers ( name ),
      purchase_items (
        id,
        product_id,
        quantity,
        unit_cost,
        selling_price,
        products ( name_ar, name_fr )
      )
    ''').order('created_at', ascending: false);

    return (rows as List).map<PurchaseEntity>((row) {
      final supplierMap = row['suppliers'] as Map<String, dynamic>?;
      final supplierName = supplierMap?['name'] as String? ?? 'Fournisseur';

      final items = (row['purchase_items'] as List? ?? []).map((i) {
        final productMap = i['products'] as Map<String, dynamic>?;
        final name = productMap != null ? (productMap['name_ar'] ?? productMap['name_fr'] ?? '') : '';
        return PurchaseItemEntity(
          id: i['id'] as String,
          productId: i['product_id'] as String,
          productName: name,
          quantity: (i['quantity'] as num).toInt(),
          unitCostCentimes: (i['unit_cost'] as num).toInt(),
          sellingPriceCentimes: (i['selling_price'] as num).toInt(),
        );
      }).toList();

      PurchaseStatus status = PurchaseStatus.draft;
      if (row['status'] == 'posted') status = PurchaseStatus.posted;
      if (row['status'] == 'cancelled') status = PurchaseStatus.cancelled;

      return PurchaseEntity(
        id: row['id'] as String,
        supplierId: row['supplier_id'] as String,
        supplierName: supplierName,
        invoiceNo: row['invoice_no'] as String,
        invoiceDate: DateTime.parse(row['invoice_date'] as String),
        status: status,
        totalAmountCentimes: (row['total_amount'] as num).toInt(),
        items: items,
        postedAt: row['posted_at'] != null ? DateTime.parse(row['posted_at'] as String) : null,
      );
    }).toList();
  }

  Future<String> _resolveValidUserId(String? candidateId) async {
    if (candidateId != null && candidateId.isNotEmpty && candidateId != '22222222-2222-2222-2222-222222222222') {
      try {
        final rows = await client.from('users').select('id').eq('id', candidateId).limit(1);
        if ((rows as List).isNotEmpty) {
          return candidateId;
        }
      } catch (_) {}
    }

    try {
      final rows = await client.from('users').select('id').limit(1);
      if ((rows as List).isNotEmpty) {
        return rows.first['id'] as String;
      }
    } catch (_) {}

    return '11111111-1111-1111-1111-111111111111';
  }

  @override
  Future<String> createDraftPurchase({
    required String supplierId,
    required String invoiceNo,
    DateTime? invoiceDate,
    String? createdBy,
    List<Map<String, dynamic>> items = const [],
  }) async {
    final date = invoiceDate ?? DateTime.now();
    final user = await _resolveValidUserId(createdBy ?? client.auth.currentUser?.id);
    int total = 0;
    for (final it in items) {
      final q = (it['quantity'] ?? it['qty'] ?? 1) as num;
      final c = (it['unit_cost'] ?? it['cost_centimes'] ?? 0) as num;
      total += (q * c).toInt();
    }

    final purchaseRow = await client.from('purchases').insert({
      'supplier_id': supplierId,
      'invoice_no': invoiceNo,
      'invoice_date': date.toIso8601String().split('T').first,
      'status': 'draft',
      'total_amount': total,
      'created_by': user,
    }).select('id').single();

    final purchaseId = purchaseRow['id'] as String;

    if (items.isNotEmpty) {
      final purchaseItemsToInsert = items.map((it) {
        final unitCost = (it['unit_cost'] ?? it['cost_centimes'] ?? 0) as int;
        final sellingPrice = (it['selling_price'] != null ? (it['selling_price'] as num).toInt() : unitCost);
        return {
          'purchase_id': purchaseId,
          'product_id': it['product_id'],
          'quantity': (it['quantity'] ?? it['qty'] ?? 1) as int,
          'unit_cost': unitCost,
          'selling_price': sellingPrice >= unitCost ? sellingPrice : unitCost,
        };
      }).toList();

      await client.from('purchase_items').insert(purchaseItemsToInsert);
    }

    return purchaseId;
  }

  @override
  Future<void> postPurchase({
    required String purchaseId,
    required String userId,
    List<Map<String, dynamic>> items = const [],
  }) async {
    final effectiveUserId = await _resolveValidUserId(userId.isNotEmpty ? userId : client.auth.currentUser?.id);
    await service.postPurchase(
      purchaseId: purchaseId,
      userId: effectiveUserId,
    );
  }
}
