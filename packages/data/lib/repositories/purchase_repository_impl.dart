import 'dart:convert';
import 'package:domain/domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../datasources/remote/supabase_service.dart';
import '../datasources/local/app_database.dart';
import '../datasources/local/connectivity_service.dart';

class PurchaseRepositoryImpl implements IPurchaseRepository {
  final SupabaseClient client;
  final SupabaseService service;
  final AppDatabase? db;

  PurchaseRepositoryImpl({
    required this.client,
    required this.service,
    this.db,
  });

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
    try {
      final res = await client.rpc('rpc_create_supplier', params: {
        'p_name': name.trim(),
        'p_phone': phone.trim(),
        'p_company_register': companyRegister?.trim(),
        'p_notes': notes?.trim(),
      });
      return Map<String, dynamic>.from(res as Map);
    } catch (_) {
      // Fallback for offline or legacy environments
      final row = await client.from('suppliers').insert({
        'name': name.trim(),
        'phone': phone.trim(),
        'company_register': companyRegister?.trim(),
        'notes': notes?.trim(),
      }).select().single();

      return Map<String, dynamic>.from(row);
    }
  }

  @override
  Future<List<SupplierProfileEntity>> getSuppliersWithBalances() async {
    try {
      // 1. Try view_supplier_balance
      final rows = await client
          .from('view_supplier_balance')
          .select('supplier_id, supplier_name, supplier_phone, current_balance, total_purchases')
          .order('supplier_name');

      return (rows as List).map<SupplierProfileEntity>((r) {
        return SupplierProfileEntity(
          id: r['supplier_id'] as String,
          name: r['supplier_name'] as String? ?? 'مورد',
          phone: r['supplier_phone'] as String? ?? '',
          currentBalanceCentimes: (r['current_balance'] as num?)?.toInt() ?? 0,
          totalPurchasesCentimes: (r['total_purchases'] as num?)?.toInt() ?? 0,
        );
      }).toList();
    } catch (_) {
      // 2. Fallback: query suppliers table directly and aggregate from purchases
      final suppliers = await getSuppliers();
      final purchases = await getPurchases();

      return suppliers.map<SupplierProfileEntity>((s) {
        final supId = s['id'] as String;
        final supPurchases = purchases.where((p) => p.supplierId == supId);
        final totalPurchases = supPurchases.fold<int>(0, (sum, p) => sum + p.totalAmountCentimes);

        return SupplierProfileEntity(
          id: supId,
          name: s['name'] as String? ?? 'مورد',
          phone: s['phone'] as String? ?? '',
          companyRegister: s['company_register'] as String?,
          notes: s['notes'] as String?,
          currentBalanceCentimes: totalPurchases, // fallback estimation
          totalPurchasesCentimes: totalPurchases,
        );
      }).toList();
    }
  }

  @override
  Future<SupplierProfileEntity?> getSupplierById(String supplierId) async {
    try {
      final rows = await client
          .from('view_supplier_balance')
          .select('supplier_id, supplier_name, supplier_phone, current_balance, total_purchases')
          .eq('supplier_id', supplierId)
          .limit(1);

      if ((rows as List).isNotEmpty) {
        final r = rows.first;
        return SupplierProfileEntity(
          id: r['supplier_id'] as String,
          name: r['supplier_name'] as String? ?? 'مورد',
          phone: r['supplier_phone'] as String? ?? '',
          currentBalanceCentimes: (r['current_balance'] as num?)?.toInt() ?? 0,
          totalPurchasesCentimes: (r['total_purchases'] as num?)?.toInt() ?? 0,
        );
      }
    } catch (_) {}

    final all = await getSuppliersWithBalances();
    return all.where((s) => s.id == supplierId).firstOrNull;
  }

  @override
  Future<List<PurchaseEntity>> getUnpaidPurchasesBySupplier(String supplierId) async {
    final allPurchases = await getPurchases();
    return allPurchases.where((p) => p.supplierId == supplierId && p.isPosted).toList();
  }

  @override
  Future<SupplierPaymentResult> recordSupplierPayment({
    required String supplierId,
    required int amountCentimes,
    required String payerUserId,
    required String payerName,
    required String payerRole,
    String? purchaseId,
    String? notes,
  }) async {
    final effectiveUserId = await _resolveValidUserId(payerUserId);
    final supplier = await getSupplierById(supplierId);
    final prevBalance = supplier?.currentBalanceCentimes ?? 0;
    final remaining = (prevBalance - amountCentimes).clamp(0, 999999999);
    final paymentId = 'PAY-SUP-${DateTime.now().millisecondsSinceEpoch % 1000000}';

    // 1. Insert into supplier_ledger or payments if table exists
    if (ConnectivityService.instance.isOnline) {
      try {
        await client.from('supplier_ledger').insert({
          'supplier_id': supplierId,
          'amount_change': -amountCentimes,
          'ref_type': 'payment',
          'ref_id': purchaseId ?? paymentId,
          'notes': notes ?? 'سداد نقدي لمستحقات المورد بواسطة $payerName ($payerRole)',
          'created_by': effectiveUserId,
        });
      } catch (_) {
        try {
          await client.from('payments').insert({
            'supplier_id': supplierId,
            'amount': amountCentimes,
            'method': 'cash',
            'received_by': effectiveUserId,
            'status': 'settled',
            'notes': notes,
          });
        } catch (_) {}
      }
    } else if (db != null) {
      final clientId = const Uuid().v4();
      await db!.enqueuePendingOp(PendingOperationsCompanion.insert(
        clientId: clientId,
        operationType: 'manager_supplier_payment',
        payloadJson: jsonEncode({
          'supplier_id': supplierId,
          'amount': amountCentimes,
          'payer_user_id': effectiveUserId,
          'payer_name': payerName,
          'payer_role': payerRole,
          'purchase_id': purchaseId,
          'notes': notes,
        }),
        createdAt: DateTime.now(),
      ));
    }

    // 2. Audit Trail logging
    try {
      await client.from('audit_log').insert({
        'action': 'SUPPLIER_PAYMENT',
        'target_table': 'supplier_ledger',
        'target_id': purchaseId ?? supplierId,
        'user_id': effectiveUserId,
        'after_state': {
          'supplier_id': supplierId,
          'supplier_name': supplier?.name ?? 'مورد',
          'amount_centimes': amountCentimes,
          'payment_method': 'cash',
          'previous_balance': prevBalance,
          'remaining_balance': remaining,
          'purchase_id': purchaseId,
          'notes': notes,
          'payer_name': payerName,
          'payer_role': payerRole,
        },
      });
    } catch (_) {}

    return SupplierPaymentResult(
      paymentId: paymentId,
      supplierId: supplierId,
      supplierName: supplier?.name ?? 'المورد',
      paidAmountCentimes: amountCentimes,
      previousBalanceCentimes: prevBalance,
      remainingBalanceCentimes: remaining,
      paymentMethod: 'cash',
      payerRole: payerRole,
      payerId: effectiveUserId,
      payerName: payerName,
      timestamp: DateTime.now(),
      notes: notes,
    );
  }

  @override
  Future<List<PurchaseEntity>> getPurchases() async {
    List<dynamic> rows;
    try {
      final res = await client.from('purchases').select('''
        id,
        supplier_id,
        invoice_no,
        invoice_date,
        status,
        total_amount,
        posted_at,
        created_at,
        created_by,
        suppliers ( name ),
        users!purchases_created_by_fkey ( id, name, phone, role ),
        purchase_items (
          id,
          product_id,
          quantity,
          unit_cost,
          selling_price,
          products ( name_ar, name_fr, unit )
        )
      ''').order('created_at', ascending: false);
      rows = res as List;
    } catch (_) {
      try {
        final res = await client.from('purchases').select('''
          id,
          supplier_id,
          invoice_no,
          invoice_date,
          status,
          total_amount,
          posted_at,
          created_at,
          created_by,
          suppliers ( name ),
          users ( id, name, phone, role ),
          purchase_items (
            id,
            product_id,
            quantity,
            unit_cost,
            selling_price,
            products ( name_ar, name_fr, unit )
          )
        ''').order('created_at', ascending: false);
        rows = res as List;
      } catch (_) {
        final res = await client.from('purchases').select('''
          id,
          supplier_id,
          invoice_no,
          invoice_date,
          status,
          total_amount,
          posted_at,
          created_at,
          created_by,
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
        rows = res as List;
      }
    }

    return rows.map<PurchaseEntity>((row) {
      final supplierMap = row['suppliers'] as Map<String, dynamic>?;
      final supplierName = supplierMap?['name'] as String? ?? 'Fournisseur';

      final userMap = row['users'] as Map<String, dynamic>?;
      final createdByName = userMap?['name'] as String?;
      final createdByPhone = userMap?['phone'] as String?;
      final createdByRole = userMap?['role']?.toString();
      final createdById = row['created_by'] as String? ?? userMap?['id'] as String?;

      final items = (row['purchase_items'] as List? ?? []).map((i) {
        final productMap = i['products'] as Map<String, dynamic>?;
        final name = productMap != null
            ? (productMap['name_ar'] ?? productMap['name_fr'] ?? '')
            : '';
        final unit = productMap?['unit'] as String?;
        return PurchaseItemEntity(
          id: i['id'] as String,
          productId: i['product_id'] as String,
          productName: name,
          quantity: (i['quantity'] as num).toInt(),
          unitCostCentimes: (i['unit_cost'] as num).toInt(),
          sellingPriceCentimes: (i['selling_price'] as num).toInt(),
          unit: unit,
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
        postedAt: row['posted_at'] != null
            ? DateTime.parse(row['posted_at'] as String)
            : null,
        createdById: createdById,
        createdByName: createdByName,
        createdByPhone: createdByPhone,
        createdByRole: createdByRole,
        createdAt: row['created_at'] != null
            ? DateTime.parse(row['created_at'] as String)
            : null,
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

    if (!ConnectivityService.instance.isOnline) {
      // Offline fallback: generate an offline draft purchase ID
      return 'OFFLINE-${const Uuid().v4()}';
    }

    try {
      final res = await client.rpc('rpc_create_draft_purchase', params: {
        'p_supplier_id': supplierId,
        'p_invoice_no': invoiceNo,
        'p_invoice_date': date.toIso8601String().split('T').first,
        'p_total_amount': total,
        'p_created_by': user,
        'p_items': items,
      });
      return res.toString();
    } catch (_) {
      try {
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
      } catch (_) {
        return 'OFFLINE-${const Uuid().v4()}';
      }
    }
  }

  @override
  Future<void> postPurchase({
    required String purchaseId,
    required String userId,
    List<Map<String, dynamic>> items = const [],
  }) async {
    final effectiveUserId = await _resolveValidUserId(userId.isNotEmpty ? userId : client.auth.currentUser?.id);

    if (ConnectivityService.instance.isOnline && !purchaseId.startsWith('OFFLINE-')) {
      try {
        await service.postPurchase(
          purchaseId: purchaseId,
          userId: effectiveUserId,
        );
        return;
      } catch (_) {
        // Fall through to offline queue
      }
    }

    // Offline: queue in PendingOperations
    if (db != null) {
      final clientId = const Uuid().v4();
      await db!.enqueuePendingOp(PendingOperationsCompanion.insert(
        clientId: clientId,
        operationType: 'manager_purchase_post',
        payloadJson: jsonEncode({
          'purchase_id': purchaseId,
          'user_id': effectiveUserId,
          'items': items,
        }),
        createdAt: DateTime.now(),
      ));
    }
  }
}
